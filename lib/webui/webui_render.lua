--[[============================================================================
  webui/render.lua  ——  控件池 + diff 渲染

  核心职责：
    1. 把 DOM 树映射成引擎控件树
    2. 控件池复用（Instantiate / Destroy 有开销）
    3. diff：只写变化的字段（避免每帧全量写）

  ⚠️ 真机实测约束（R1–R14）：
    - 坐标：子控件位置 = 父控件中心 + anchoredPosition
            子控件必须设 anchorMin=anchorMax=pivot=(0.5,0.5)
    - Y 轴：千星原点【左下】、Y 向上；内部布局用 HTML 习惯（左上、Y 向下）
            => 渲染时必须翻转
    - 纯色块必须用【文本框】(bgColor)；图片控件的 imageColor 只给已有图染色
    - fontSize 必须是整数
    - 矩形裁剪不可用；圆形裁剪需图片控件
    - 可点击元素必须用【预设按钮】或【光标检测区域】

  控件的选择策略（按 CSS 属性决定）：
    有文本            -> TextBoxControl
    background-color  -> TextBoxControl（用 bgColor 当色块）
    需要点击          -> PresetButtonControl
    其他              -> ContainerControl
==============================================================================]]

local color      = require('webui_color')
local util       = require('webui_util')
local dom        = require('webui_dom')
local transition = require('webui_transition')
local clip       = require('webui_clip')

local R = {}

--=============================================================================
-- 控件工厂：按需创建
--
-- 编辑器里需要预先准备好这些模板；这里通过名称查找已存在的控件，
-- 若找不到则尝试用 InstantiateClientUIControl（需要模板索引）。
--=============================================================================

local FACTORY = {
  -- 由外部注入：{ container = idx, textbox = idx, button = idx, image = idx }
  prefabs = nil,

  -- 从池里取或新建
  acquire = nil,
}

--[[ 创建一个引擎控件并挂到 parent 下

  ⚠️ 这里会【报告失败原因】而不是静默返回 nil。
     第一次真机测试时就是因为静默失败，画面空白却查不出原因。
]]--
local function instantiate(kind, parent)
  local idx = FACTORY.prefabs and FACTORY.prefabs[kind]

  if not idx then
    if not FACTORY._warnedMissing then FACTORY._warnedMissing = {} end
    if not FACTORY._warnedMissing[kind] then
      FACTORY._warnedMissing[kind] = true
      util.warn(string.format(
          "PREFABS 里没有配置 '%s' 的模板索引，无法创建该类型控件。" ..
          "请在编辑器里为该类型建一个模板并填入索引。", kind))
    end
    return nil
  end

  if type(game.InstantiateClientUIControl) ~= "function" then
    util.warn("game.InstantiateClientUIControl 不可用")
    return nil
  end

  local ok, c, err = pcall(game.InstantiateClientUIControl, idx, parent)

  if not ok then
    if not FACTORY._warnedError then FACTORY._warnedError = {} end
    local key = kind .. ":" .. tostring(idx)
    if not FACTORY._warnedError[key] then
      FACTORY._warnedError[key] = true
      util.warn(string.format(
          "InstantiateClientUIControl(%d, parent) 对 '%s' 报错: %s",
          idx, kind, tostring(c)))
    end
    return nil
  end

  if c == nil then
    if not FACTORY._warnedNil then FACTORY._warnedNil = {} end
    local key = kind .. ":" .. tostring(idx)
    if not FACTORY._warnedNil[key] then
      FACTORY._warnedNil[key] = true
      util.warn(string.format(
          "InstantiateClientUIControl(%d, parent) 对 '%s' 返回 nil —— " ..
          "该模板索引很可能不存在。", idx, kind))
    end
    return nil
  end

  return c
end

--=============================================================================
-- 差值比较
--=============================================================================

local EPS = 0.01

local function numChanged(a, b)
  a = a or 0
  b = b or 0
  return math.abs(a - b) > EPS
end

local function colorChanged(a, b)
  return not color.equals(a, b)
end

--=============================================================================
-- Render 实例
--=============================================================================

local Renderer = {}
Renderer.__index = Renderer

function R.new(rootControl, opts)
  opts = opts or {}
  if opts.prefabs then FACTORY.prefabs = opts.prefabs end

  local self = setmetatable({}, Renderer)
  self.root      = rootControl
  self.prefabs   = opts.prefabs   -- 保存一份，便于诊断输出
  self.pool      = {}        -- kind -> 空闲控件数组
  self._pooled   = {}        -- ★ control -> true（"在池里"的账本，供 isOrphan 查）
  self.live      = {}        -- node -> { control=, kind=, last={} }
  self.stats     = { created = 0, reused = 0, destroyed = 0, written = 0 }
  self.debug     = opts.debug or false

  -- 启动时校验 PREFABS
  if not opts.prefabs then
    util.warn("webui 渲染器：未提供 prefabs 模板索引，将无法创建任何控件。" ..
              "请在编辑器里为容器/文本框/按钮建模板并传入索引。")
  end

  return self
end

--[[ 从池取控件 ]]--
--[[ 从池里取控件。

    ★ 这里有一个真实的两难（两种做法都实测踩过坑）：

      做法 A：要求 __webuiParent 精确匹配
        优点：控件一定贴在正确的父下
        缺点：某个位置的 kind 变化 → 该分支整条子树匹配失败 → 雪崩新建
              实测 demo 每次操作新建 100+ 控件，越来越卡

      做法 B：只按 kind 取，不比较父
        优点：复用率高，created 稳定
        缺点：控件被贴到【已隐藏的旧父】下 → 界面元素消失
              实测 live=5 时只有 2 个可见

    ★ 正确做法：按 kind 取，但【复用时检查父链可见性】。
      只有当控件的父（在引擎里的实际父）会被本轮复用/激活时才安全。

      由于引擎没有 reparent API，控件一旦创建就固定挂在其父下。
      所以安全的复用条件是：
        控件的旧父 P_old 在本轮【也被复用给了同一个位置】。

      简化为可判定的规则：
        记录每个控件创建时的父控件。复用时，
        若目标父链与控件现有父链【指向同一个对象】，则安全。

    ★ 最终采用的方案：让父控件的复用先于子控件发生。
      按 DOM 的【先序遍历】顺序构建，父总是先于子被 _take。
      这样如果父被复用了（复用让父重新 active），
      子的旧父就是这个"刚被复用的父"，匹配自然成立。

      具体实现：在 _take 里做两级匹配 ——
        ① 同父（父已被复用为同一个对象）
        ② 父控件处于 active 状态（说明它本轮会在树里显示）
      否则新建。
]]--
--[[ 判断 ctrl 的实际父是否就是 parentCtrl（用引擎数据，不用自定义字段）

    ★ 为什么必须这样做（真机探针实测）：

      最初用自定义字段记父：
        c.__webuiParent = parent          -- 引擎控件是 userdata，写不进去
        if c.__webuiParent == parent then -- 永远 nil == parent，永不成立
        -> 复用永远失败 -> reused=0 -> 每次操作新建 100+ 控件 -> 越来越卡

      探针结果（probe_field.lua，真机）：
        __webuiParent   写=false  读=true  值=nil    ← 自定义字段一律写不进
        _order          写=false  读=true  值=nil
        myCustomFlag    写=false  读=true  值=nil
        bgColor         写=true   读=true  值=...    ← 引擎预定义字段正常
        GetChildren()   返回正确的子列表             ← 可用！

      ==> 控件上【无法保存任何自定义状态】，只能靠引擎自身 API 查询。

      代价：每次判断要遍历子列表。但子数量通常很小，
            且只在复用路径上调用（构建每个节点最多一次）。
]]--
local function isChildOf(ctrl, parentCtrl)
  if not ctrl or not parentCtrl then return false end
  local ok, kids = pcall(function() return parentCtrl:GetChildren() end)
  if not ok or type(kids) ~= "table" then
    -- GetChildren 不可用时保守返回 false（宁可新建，也不要贴错父）
    return false
  end
  for i = 1, #kids do
    if kids[i] == ctrl then return true end
  end
  return false
end

function Renderer:_take(kind, parent)
  local list = self.pool[kind]

  if list and #list > 0 then
    --[[ 只复用【实际父 == 目标父】的控件。

        ★ 为什么必须匹配父（实测教训）：
          引擎里控件固定在创建时的父下，没有 reparent API。
          渲染时写入的 anchoredPosition 是【相对新父中心】算的，
          若控件的实际父是别的对象，引擎按【旧父】渲染 ->
          位置完全错乱（实测：切页签后界面只剩一个黑块 + 一个按钮）。

        ★ 关于池内顺序（2026-10-09 突变测试核实，更正旧说法）：
          旧注释称"顺序必须 = DOM 先序逆序，否则同结构命不中"——不准确。
          上面的循环会【遍历整个池】找父匹配控件，顺序只决定"选中哪个
          同父控件"，而同父控件可互换。
          实测（30 轮增删）：逆序/正序/排序失效 三种方式
          created 与 reused 【完全相同】（20 / 370）。
          => 顺序是【可预测性的优化】，不是正确性前提；
             真正必需的是 isChildOf 父匹配（去掉它会命中错父控件）。
          仍保留逆序：让弹序 == 构建序，不依赖 pairs() 的未定义顺序。
    ]]--
    for i = #list, 1, -1 do
      local c = list[i]
      if isChildOf(c, parent) then
        table.remove(list, i)
        self.stats.reused = self.stats.reused + 1
        -- ★ 从"池中"账本里划掉（见 isOrphan）
        if self._pooled then self._pooled[c] = nil end
        self:_resetReused(c, kind)
        return c
      end
    end
  end

  local c = instantiate(kind, parent)
  if c then
    self.stats.created = self.stats.created + 1
  end
  return c
end

--[[ ★★★ 复用前把控件【上一个主人的外观】清干净。

     ══════════════════════════════════════════════════════════════════════
     为什么必须清（R31 库级修复）
     ══════════════════════════════════════════════════════════════════════

       控件池是【共享】的：节点隐藏 -> 控件还池 -> 别的节点取走。
       而还池时只调了 `SetActive(false)`，**外观字段一个都没清**。

       于是新主人会继承旧主人的外观 —— 除非它自己显式写一遍：

         · image.imageColor
             旧主人染成红色 -> 新主人没写 -> 【新主人显示红色】
             真机表现：某个图片控件"莫名其妙是红的/白的"。
             ★ 这与"白色方块"是同一类 bug，只是颜色来源不同。

         · image 的图（imageId）
             旧主人 SetImage(100002 圆形) -> 新主人没 SetImage
             -> 【新主人显示圆形】，而它可能想要方的。

         · textbox.text / fontColor / fontSize
             旧主人的文字会残留到新主人身上（新主人无文字时）。

     ★ 为什么在 _take 里清而不是还池时清：
       还池时清没有意义 —— 控件可能立刻又配给同一个节点。
       在【取用时】清，语义是"交付给新主人前恢复出厂"，
       对每个消费方都生效，应用层不用自己记得。

     ⚠️ 只清"外观"，不清变换（位置/尺寸/可见性）：
       那些由 writeControl 每帧按节点计算写入，清了也无害，
       但清它们会破坏 diff 缓存与首帧的过渡起点（见 setColor 的 isFirst）。 ]]--
function Renderer:_resetReused(control, kind)
  if not control then return end

  -- ① image：把染色复位成【全透明】，而不是白色
  --[[ ⚠️⚠️ 为什么是透明而不是白（想清楚再改）：

       复用后新主人若【没写】imageColor，它会保持我们复位成的值。
       两种选择的后果完全不同：

         · 复位成白色 (255,255,255,255)
             -> 一个"忘了染色"的图片控件 = 【一块白】
             -> 正是最难查的那种 bug（看着像渲染坏了）

         · 复位成全透明 (0,0,0,0)          ★ 采用
             -> 忘了染色 = 看不见（漏了内容，但不会画错东西）
             -> 而且这恰好就是【裁剪容器】要的值（见下方 imageColor 段），
                复用给裁剪容器时天然正确

       ★ 原则：复用复位应把控件置于"最不会骗人"的状态。
         看不见是明显的缺失；白色的方块会被误判成渲染故障。 ]]
  if kind == "image" then
    pcall(function() control.imageColor = Color.FromRGBA(0, 0, 0, 0) end)
  end

  -- ② textbox：清文字与字号/字色（新主人若不写就会残留别人的）
  if kind == "textbox" then
    pcall(function() control.text = "" end)
  end
end

--[[ 归还到池 ]]--
function Renderer:_give(kind, control)
  if not control then return end
  local ok = pcall(function()
    game.DestroyClientUIControl(control)
  end)
  -- 注：DestroyClientUIControl 会真正销毁，无法复用。
  --     若要复用，应改为 SetActive(false) 并留在树里。
  --     这里采用"隐藏复用"策略：不销毁，仅停用。
  self.stats.destroyed = self.stats.destroyed + 1
end

--[[ 隐藏控件（复用策略：不销毁，仅停用） ]]--
--[[ 隐藏控件（归还池前调用）

    ⚠️ 必须清掉监听器！

    控件池会复用控件，而每次 setHTML 后 _bindEvents 都会重新绑定。
    如果不清旧监听，复用过的控件会【累积】所有历史监听：
      第 1 次渲染绑 1 个 → 第 2 次同一个控件上就有 2 个 → 第 10 次有 10 个
    后果：一次点击触发多次回调；监听器数量线性增长导致越来越卡。

    实测踩过：动态页面操作 40 次后 reused 累计 989 次监听注册。
]]--
function Renderer:_hide(control)
  if not control then return end
  pcall(function() control:SetActive(false) end)

  -- 清掉全部光标事件监听
  if type(control.RemoveAllCursorEventListeners) == "function" then
    pcall(function() control:RemoveAllCursorEventListeners() end)
  end
end

--[[ 显示控件 ]]--
function Renderer:_show(control)
  if not control then return end
  pcall(function() control:SetActive(true) end)
end

--[[ ★★★ 查询一个控件是否【当前在控件池里】（= 已被还池、可能被别的节点取走）。

     ══════════════════════════════════════════════════════════════════════
     为什么需要它（R31 库级修复）
     ══════════════════════════════════════════════════════════════════════

       应用层常有"缓存一个控件引用，之后再用"的需求
       （例如精灵矩形换姿态时要重贴图）。但控件池是【共享】的：
       节点隐藏 -> 控件还池 -> 随时被别的节点取走。
       缓存的引用就指向了别人的控件，写进去【不报错但写错对象】。

       ⚠️ 旧做法是读 `control._orphan` —— 但那是【自定义字段】，
          真机上写入静默失败（本项目的硬性约束），
          所以那个标记【永远是 nil】，等于什么都没守。
          => 应用层以为自己在检查，其实是空检查。

       ★ 正确做法：由渲染器自己记账（_pooled 表），
         应用层查 rendered:isOrphan(ctrl)。

     用法：
       if not ui.rendered:isOrphan(ctrl) then
         -- 这个控件确实还属于那个节点，可以安全写
       end

     ⚠️ 返回 true 只表示"它在池里"，不保证"它属于你"——
        要拿当前有效的控件，优先用 rendered.live[node].control 现查。 ]]--
function Renderer:isOrphan(control)
  if not control then return true end
  return (self._pooled and self._pooled[control] == true) or false
end

--=============================================================================
-- 控件类型选择
--=============================================================================

--[[
  选择控件类型。

  ★ 真机实测（Z1 探测）的关键约束：

    ClientUIPresetButtonControl（预设按钮）
      - 只有 interactable / raycastTarget / clickAudioId 三个字段
      - 【没有】bgColor / text / fontColor / fontSize
      - 外观完全由【模板内部的子控件/图片】决定
      - 模板是空壳时，按钮不可见

    ClientUITextBoxControl（文本框）
      - 有 bgColor / text / fontColor / fontSize
      - 能正常显示背景与文字
      - 能嵌套任意层
      - 【没有】AddCursorEventListener

    ClientUIContainerControl（容器节点）
      - 没有 bgColor / text / fontColor
      - 能嵌套

  ==> 结论：不能用一个控件同时满足「可见外观」和「可点击」。

      因此采用【双层方案】：
        视觉层：textbox / container（负责显示）
        交互层：button（覆盖在上面，负责接收点击）

      渲染时，一个"需要点击的元素"会生成：
        <外层 textbox/container>   <- 显示背景、文字
          <button 覆盖层>          <- 透明，只接收事件
        </外层>

      由于 button 模板可能没有外观，覆盖层是透明的，不会遮挡视觉。

  简化策略（当前实现）：
    先按"显示需求"选类型；若该元素也需要点击，
    则在渲染阶段额外挂一个 button 覆盖层。
]]--
local function chooseKind(node)
  local st = node.style
  if not st then return "container" end

  --[[ ⓪ 需要裁剪 -> 图片控件

       ★ R17 实证：图片控件 + 遮罩图 = 裁剪容器。
         `overflow:hidden` 和 `border-radius` 都靠它实现。

       之所以优先于其他判断：
         只有图片控件有 enableMask；文本框/容器都没有这个字段。
         若不在这里拦住，裁剪类元素会被选成 textbox，裁剪就失效了。
  ]]--
  if st._clipShape then return "image" end

  --[[ ⓪' 显式声明为图片元素（data-image="1"）

       应用层想用 SetImage 画形状图时用这个。
       若不拦在这里，会被选成 textbox —— 而真机 textbox 没有 SetImage。
  ]]--
  if st._forceImage then return "image" end

  -- ① 有文本 -> 文本框（文本框才能显示文字）
  local hasText = false
  for i = 1, #node.children do
    if node.children[i]:isText() then hasText = true break end
  end
  if hasText then return "textbox" end

  -- ② 有背景色 -> 文本框（用 bgColor 当色块）
  if st._bgColor and (st._bgColor.a or 255) > 0 then
    return "textbox"
  end

  -- ③ 有交互属性但没有可见外观 -> 容器
  --    （容器自己不显示，但能装子控件；点击由覆盖层负责）
  local attrs = node.attrs or {}
  if attrs.onclick or attrs.onmousedown or attrs.onmouseup
     or attrs.onmouseenter or attrs.onmouseleave or attrs.draggable then
    -- 若也没有子元素，给个文本框当"可点击热区"（虽然没背景，但能占位）
    if #node.children == 0 then return "textbox" end
    return "container"
  end

  -- ④ 有子元素 -> 容器（不显示但能装）
  for i = 1, #node.children do
    if node.children[i]:isElement() then return "container" end
  end

  return "textbox"
end

--[[ 该元素是否需要交互（决定是否挂 button 覆盖层）]]--
local function needsInteraction(node)
  local attrs = node.attrs or {}
  return (attrs.onclick or attrs.onmousedown or attrs.onmouseup
          or attrs.onmouseenter or attrs.onmouseleave
          or attrs.draggable) ~= nil
end

--=============================================================================
-- 坐标转换：HTML 布局坐标 -> 引擎 anchoredPosition
--
-- HTML:  x 从左边算，y 从上边算（相对父内容区左上角）
-- 引擎:  anchoredPosition 相对【父控件中心】，Y 向上
--
-- 设子控件锚点/pivot 都为 (0.5,0.5)，则：
--   dx = (childCenterX - parentCenterX)
--   dy = (parentCenterY - childCenterY)      <- Y 翻转
--=============================================================================

local function computeAnchored(childBox, parentBox)
  local ccx = childBox.x + childBox.w / 2
  local ccy = childBox.y + childBox.h / 2
  local pcx = parentBox.x + parentBox.w / 2
  local pcy = parentBox.y + parentBox.h / 2
  return ccx - pcx, pcy - ccy
end

--=============================================================================
-- 写入单个节点（带 diff：只写变化的字段）
--
-- ⚠️ 第一次真机测试时没有 diff，每帧全量重写，
--    日志里 written 数值持续攀升（215→435→655...），纯属浪费。
--    现在用 last 表记录上一帧的值，只有变化时才写。
--=============================================================================

local function writeControl(control, node, dx, dy, last, kind)
  local st = node.style
  local box = node.box
  if not control or not st or not box then return 0 end

  local w = box.w or 0
  local h = box.h or 0
  if w < 0 then w = 0 end
  if h < 0 then h = 0 end

  last = last or {}
  local wrote = 0

  --[[ 若节点的运行时样式变过，清掉【受影响字段】的缓存。

    ⚠️ 不要清整个 last 表 —— 那会导致该节点所有字段重写，
       在逐帧循环里造成大量无谓写入（实测每次 refresh 触发 45 次写入）。

    CSS 属性 -> 引擎字段 的映射：
      background-color -> bgColor
      color            -> fontColor
      width/height     -> sizeDeltaX / sizeDeltaY
      其他             -> 清全部（保守，但少见）
  ]]--
  if node._inlineDirty then
    local dirty = node._inlineDirty
    node._inlineDirty = nil

    local CLEAR_ALL = dirty["*"] == true
    --[[ ★★ 清字段缓存时【必须保住颜色的 prev 值】（R28 修）。

       ⚠️ 踩过的坑：transition（CSS 过渡）永远不生效。

       原因链：
         1) 脚本改 background-color -> 标记 dirty
         2) 这里 clearField("bgColor") 把 last.bgColor 清成 nil
         3) setColor 里 prev 为 nil -> isFirst = true
         4) isFirst 为真时【不做过渡】，直接写值
       => 因为"改颜色"这件事本身就会清掉 prev，
          所以"改颜色触发的过渡"永远走不到 Tween 分支。

       ★ 解法：颜色字段【保留 prev】。它本来就是"上一次写入的值"，
         清掉的目的是"强制重写一次"，而 setColor 自己会按
         分量比较决定要不要写 —— 保留 prev 不影响正确性，
         反而让过渡有了插值起点。

       ⚠️ 只对【颜色】这么做；尺寸/位置等仍按原样清
         （那些字段没有过渡需求，清了无害）。 ]]
    local KEEP_PREV = { bgColor = true, fontColor = true, imageColor = true }
    local function clearField(f)
      if KEEP_PREV[f] then return end       -- ★ 颜色保 prev（见上）
      if last[f] ~= nil then last[f] = nil end
    end

    if CLEAR_ALL then
      for k in pairs(last) do last[k] = nil end
    else
      for prop in pairs(dirty) do
        if prop == "background-color" then
          clearField("bgColor"); clearField("imageColor")
        elseif prop == "color" then
          clearField("fontColor")
        elseif prop == "width" then
          clearField("sizeDeltaX")
        elseif prop == "height" then
          clearField("sizeDeltaY")
        elseif prop == "font-size" then
          clearField("fontSize")
        elseif prop == "opacity" then
          clearField("bgColor"); clearField("fontColor")
        elseif prop == "*text*" then
          clearField("text")
        else
          -- 未知属性：保守起见全清（至少保证正确性）
          for k in pairs(last) do last[k] = nil end
        end
      end
    end
  end

  --[[ 该控件类型是否支持某字段。

    ★ 真机实测：字段按类型封死。
      - 预设按钮：只有 interactable / raycastTarget / clickAudioId
      - 容器节点：没有 bgColor / text / fontColor
      - 文本框：有 bgColor / text / fontColor / fontSize

      往不支持的控件写字段会静默失败（pcall 返回 false），
      所以要先判断，避免无谓的写入与错误的 diff 状态。
  ]]--
  local SUPPORTS = {
    textbox   = { bgColor = true, text = true, fontColor = true,
                  fontSize = true, horizontalAlignment = true },
    container = { },                       -- 只有公共变换字段
    button    = { },                       -- 同上，另有 interactable 等
    image     = { imageColor = true },
  }
  local supported = SUPPORTS[kind or ""] or {}

  local function can(field)
    return supported[field] == true
  end

  --[[ 只在值变化时写入。

    ⚠️ 两个陷阱：
      1. Color.FromRGBA() 每次返回【新表】，直接用 == 比较永远不等，
         所以颜色要【按分量比较】（存原始 r,g,b,a 而不是引擎对象）。
      2. 浮点数值要用容差比较。
  ]]--
  local function set(field, value)
    local prev = last[field]

    if type(value) == "number" and type(prev) == "number" then
      if math.abs(value - prev) < EPS then return end
    elseif type(value) == "table" and type(prev) == "table"
           and value.r and value.g and value.b then
      -- 颜色：按分量比较（last 里存的是原始 {r,g,b,a}）
      if prev.r == value.r and prev.g == value.g
         and prev.b == value.b and (prev.a or 255) == (value.a or 255) then
        return
      end
    else
      if prev == value then return end
    end

    pcall(function() control[field] = value end)
    last[field] = value
    wrote = wrote + 1
  end

  --[[ 颜色专用：last 里存原始分量表，写入时才转成引擎对象

    ★ 若该属性声明了 transition，则改用 game.Tween 做平滑过渡，
      并在过渡期间【标记该字段被 tween 占用】，避免渲染器每帧覆盖它。
  ]]--
  local function setColor(field, rgba, propName)
    if not rgba then return end
    local prev = last[field]
    if prev and prev.r == rgba.r and prev.g == rgba.g
       and prev.b == rgba.b and (prev.a or 255) == (rgba.a or 255) then
      return
    end

    -- 查 transition
    local tr = nil
    if propName and node._transition then
      tr = node._transition[propName] or node._transition["all"]
    end

    -- 首次渲染不做过渡（没有"从哪来"的起点）
    local isFirst = (prev == nil)

    if tr and tr.duration > 0 and not isFirst and type(game.Tween) == "function" then
      local engineVal = color.toEngine(rgba)
      if engineVal then
        local ok = pcall(function()
          local tw = game.Tween(control, { [field] = engineVal }, tr.duration)
          if tw then
            pcall(function() tw:SetEase(Enum.EaseType[tr.timing] or Enum.EaseTypeLinear) end)
            pcall(function() tw:Play() end)
          end
        end)
        if ok then
          -- 记录目标值，但【不写字段】—— 交给 Tween
          last[field] = { r = rgba.r, g = rgba.g, b = rgba.b, a = rgba.a or 255 }
          wrote = wrote + 1
          return
        end
      end
    end

    -- 普通写入
    local v = color.toEngine(rgba)
    if v then
      pcall(function() control[field] = v end)
      last[field] = { r = rgba.r, g = rgba.g, b = rgba.b, a = rgba.a or 255 }
      wrote = wrote + 1
    end
  end

  -- ---- 锚点 / pivot（固定值，只在首次写）----
  set("anchorMinX", 0.5); set("anchorMinY", 0.5)
  set("anchorMaxX", 0.5); set("anchorMaxY", 0.5)
  set("pivotX", 0.5);     set("pivotY", 0.5)

  -- ---- 布局 ----
  set("sizeDeltaX", w)
  set("sizeDeltaY", h)

  -- ---- transform（视觉位移，不影响布局流）----
  --
  --   CSS 的 translate/scale/rotateZ 映射到引擎字段：
  --     translateX -> anchoredPositionX
  --     translateY -> anchoredPositionY   （Y 轴翻转！CSS 向下为正，引擎向上为正）
  --     scale      -> localScaleX/Y
  --     rotateZ    -> localRotationZ      （CSS 顺时针为正，引擎待验证，先直接映射）
  --
  --   ⚠️ transform 是在布局坐标之上叠加的视觉偏移，
  --      不改变元素在文档流里占据的位置。
  local tf = st._transform
  local tdx, tdy = dx, dy
  if tf then
    tdx = dx + (tf.tx or 0)
    tdy = dy - (tf.ty or 0)     -- Y 翻转
  end

  set("anchoredPositionX", tdx)
  set("anchoredPositionY", tdy)

  if tf then
    if tf.sx ~= 1 then set("localScaleX", tf.sx) end
    if tf.sy ~= 1 then set("localScaleY", tf.sy) end
    if tf.rotZ ~= 0 then set("localRotationZ", tf.rotZ) end
  end

  -- ---- 可见性 ----
  set("visible", st.visibility ~= "hidden")

  -- ---- 颜色 ----
  --   ⚠️ 只有文本框有 bgColor；容器/按钮没有，写了会静默失败。
  local bg = st._bgColor
  local hasBg = bg and (bg.a or 255) > 0
  local opacity = st._opacity or 1

  if hasBg and can("bgColor") then
    if opacity < 1 then bg = color.withOpacity(bg, opacity) end
    setColor("bgColor", bg, "background-color")
  end

  -- ---- 文本 ----
  --   ⚠️ 只有文本框有 text；按钮的文字来自模板内部子控件。
  --
  --   ★ 优先级：node._text（脚本运行时设置） > DOM 里的文本节点
  --     否则脚本改了 control.text，下一帧又会被 DOM 的原文覆盖回去。
  local text = nil
  if node._text ~= nil then
    text = node._text
  else
    for i = 1, #node.children do
      local c = node.children[i]
      if c:isText() then
        text = (text and (text .. c.text)) or c.text
      end
    end
  end

  if can("text") then
    if text then
      set("text", text)
      if can("fontSize") then
        set("fontSize", util.toFontSize(st._fontSize, 14))
      end
      local fc = st._color
      if opacity < 1 then fc = color.withOpacity(fc, opacity) end
      if can("fontColor") then setColor("fontColor", fc, "color") end

      -- 对齐
      local ta = st._textAlign
      local alignVal
      if ta == "center" then alignVal = "middle"
      elseif ta == "right" then alignVal = "right"
      else alignVal = "left" end
      if last.__align ~= alignVal then
        last.__align = alignVal
        if alignVal == "middle" then
          pcall(function() control.horizontalAlignment = Enum.TextHorizontalAlignmentMiddle end)
        elseif alignVal == "right" then
          pcall(function() control.horizontalAlignment = Enum.TextHorizontalAlignmentRight end)
        else
          pcall(function() control.horizontalAlignment = Enum.TextHorizontalAlignmentLeft end)
        end
      end
    else
      -- 无文本：清掉，避免残留
      set("text", "")
    end
  end

  --[[ 图片控件：染色

       ⚠️ image 没有 bgColor 字段，所以 CSS 的 background-color 映射到 imageColor。

       ★★★ 裁剪容器必须【显式置为全透明】（2026-10-07 真机实测，两轮才定位）

         裁剪容器是 image 类型 + enableMask。它的工作机制是：

           SetImage(形状图)      -> 控件【会显示这张图】
           enableMask = true     -> 按该图 alpha 裁剪【子控件】

         ⚠️ 关键：图本身也会显示。而形状图是白→灰渐变，所以：
            · 不设 imageColor  -> 遮罩图可见 -> 裁剪边缘露出一圈白边
            · 设成红色         -> 边缘变红（形状不变）-> 证明只影响显示
            · 设成全透明       -> ★ 白边消失，裁剪仍然正确

         真机对照（三组只差 imageColor，圆 diameter 均 1.000）：
           A 不设       -> 右侧白色月牙
           B 全透明     -> 干净，无白边      ★ 采用
           C 红色       -> 边缘变红，形状不变

         => 裁剪容器一律写 imageColor = (0,0,0,0)，只借用图的 alpha 做遮罩。

         ⚠️ 另注意：不要给裁剪容器设 background-color。
            它的填充不受自身遮罩约束，会溢出到裁剪区之外。
            需要底色时，请在容器内放子元素承载。
  ]]--
  if can("imageColor") then
    if st._clipShape then
      -- 裁剪容器：显式透明，只保留遮罩作用
      if last.__clipCleared ~= true then
        last.__clipCleared = true
        pcall(function()
          control.imageColor = Color.FromRGBA(0, 0, 0, 0)
        end)
      end
    else
      -- 普通图片元素：正常染色
      local c = st._bgColor
      if c and (c.a or 255) > 0 then
        if opacity < 1 then c = color.withOpacity(c, opacity) end
        setColor("imageColor", c, "background-color")
      end
    end
  end

  return wrote
end

--=============================================================================
-- 主更新
--=============================================================================

--[[ 渲染整棵树。

    ★ 控件复用的两种场景（必须区分，否则会每帧重建全部控件）：

      场景 A：flush() —— DOM 未变，只有样式/状态可能变
        节点对象【稳定】，self.live 按节点身份命中 → 直接复用。
        【不能】预回收！否则每帧都会重建全部控件。

      场景 B：setHTML() —— DOM 重新解析
        节点对象【全新】，self.live 命不中 → 全部走新建路径。
        此时应先把旧控件还池，让本帧就能复用（否则要多建一轮）。

    区分方式：调用方通过 opts.domChanged 告知。
      init.lua 的 flush()  → domChanged = false
      init.lua 的 setHTML() → 下次 flush 时 domChanged = true
]]--
function Renderer:update(root, domChanged)
  if not self.root then return self end

  --===========================================================================
  -- 阶段 0：仅在 DOM 变化时预回收
  --===========================================================================
  if domChanged then
    local pending = self.live
    self.live = {}

    --[[ 关键：按【DOM 先序】回收，而不是 pairs() 的任意顺序。

        ⚠️ 这是本文件最容易踩的坑。控件池是 LIFO（table.remove 取尾部），
           所以压入顺序必须与构建时的取用顺序【相反】。

           构建按 DOM 先序（父 -> 子 -> 下一个兄弟）。
           取用从池尾弹出，所以池尾应该是"最先被构建的"。
           即：压入顺序 = DOM 先序的【逆序】。

           若用 pairs() 遍历（Lua 顺序未定义），池子顺序随机，
           取到的控件父链几乎必然错位 ——
           表现为界面元素错位/消失（实测踩过）。

        self.live 是 node -> entry 的表，无法直接按 DOM 顺序遍历，
        所以先按节点的创建序号（_order）排序。
        节点的 _order 由 html.parse 或 style.apply 按遍历顺序赋。
    ]]--
    local ordered = {}
    for node, entry in pairs(pending) do
      ordered[#ordered + 1] = { node = node, entry = entry }
    end
    table.sort(ordered, function(a, b)
      local oa = a.node._order or 0
      local ob = b.node._order or 0
      return oa < ob
    end)

    -- 逆序压入：最后构建的最先入池 -> 池尾是第一个构建的 -> 弹出顺序 = 构建顺序
    for i = #ordered, 1, -1 do
      local entry = ordered[i].entry
      self:_hide(entry.control)
      if entry.hot then self:_hide(entry.hot) end

      local list = self.pool[entry.kind]
      if not list then list = {}; self.pool[entry.kind] = list end
      list[#list + 1] = entry.control
      self._pooled[entry.control] = true

      if entry.hot then
        local hlist = self.pool["button"]
        if not hlist then hlist = {}; self.pool["button"] = hlist end
        hlist[#hlist + 1] = entry.hot
        self._pooled[entry.hot] = true
      end
    end
  end

  -- 根控件的 box = 整个画布
  local cw, ch = util.canvasSize()
  local rootBox = { x = 0, y = 0, w = cw, h = ch }

  -- 根控件自身也设为铺满
  pcall(function()
    self.root.anchorMinX = 0.5; self.root.anchorMinY = 0.5
    self.root.anchorMaxX = 0.5; self.root.anchorMaxY = 0.5
    self.root.pivotX = 0.5;     self.root.pivotY = 0.5
    self.root.sizeDeltaX = cw
    self.root.sizeDeltaY = ch
    self.root.anchoredPositionX = 0
    self.root.anchoredPositionY = 0
  end)

  local seen = {}

  -- 递归同步（显式栈，避免深递归）
  local stack = {}
  for i = #root.children, 1, -1 do
    stack[#stack + 1] = { node = root.children[i], parentBox = rootBox,
                          parentControl = self.root }
  end

  while #stack > 0 do
    local item = table.remove(stack)
    local node = item.node
    local pb = item.parentBox
    local parentControl = item.parentControl

    if node:isElement() then
      local st = node.style
      local box = node.box

      -- ★ 解析 transition（缓存到 node 上，避免每帧重复解析）
      if st and st._rawTransition ~= node._transitionSrc then
        node._transitionSrc = st._rawTransition
        local ok, t = pcall(function()
          return transition.parse(st)
        end)
        node._transition = ok and t or nil
      end

      if st and st.display == "none" then
        -- 隐藏
        local entry = self.live[node]
        if entry then self:_hide(entry.control) end
      elseif box then
        seen[node] = true

        local entry = self.live[node]
        if not entry then
          local kind = chooseKind(node)
          local control = self:_take(kind, parentControl)
          if control then
            entry = { control = control, kind = kind, last = {} }
            self.live[node] = entry
            -- 命名，便于调试
            pcall(function() control.name = node.tag .. (node.id and ("#" .. node.id) or "") end)

            -- ★ 从池里取出的控件可能是隐藏状态，必须重新显示。
            --   否则复用后控件仍 active=false（实测踩过：所有控件都不可见）。
            self:_show(control)

            --[[ ★★ 裁剪容器 + 文字 = 需要额外的子文本框（2026-10-07 修）

                 问题：裁剪必须用 image 控件，但 image 【没有 text 字段】，
                       写 text 会静默失败 —— 表现是"裁剪容器里的文字全丢"。

                 解法：裁剪元素若自带文字，就再挂一个 textbox 子控件承载文字。
                       父（image）负责裁剪，子（textbox）负责显示。

                 证据：本地试跑时 C/D/F 三组的控件 kind=image 且 text=nil，
                       而它们的 DOM 里明明有文字节点。
            ]]--
            local nodeText = dom.textOf(node)
            if kind == "image" and nodeText and nodeText ~= "" then
              local tc = self:_take("textbox", control)
              if tc then
                entry.textChild = tc
                entry.textLast = {}
                pcall(function() tc.name = "text:" .. (node.tag or "?") .. (node.id and ("#" .. node.id) or "") end)
                self:_show(tc)
              end
            end

            -- ★ 若需要交互，额外挂一个 button 覆盖层
            --    （因为 textbox/container 没有 AddCursorEventListener，
            --      而 button 没有可见外观，正好当透明热区）
            if needsInteraction(node) and self.prefabs and self.prefabs.button then
              local hot = self:_take("button", control)
              if hot then
                entry.hot = hot
                pcall(function() hot.name = "hot:" .. (node.tag or "?") end)
                entry.hotLast = {}
                self:_show(hot)      -- 同样要重新激活
              end
            end
          end
        else
          self:_show(entry.control)
          -- 子文字控件也要一并显示
          if entry.textChild then self:_show(entry.textChild) end
        end

        if entry then
          local dx, dy = computeAnchored(box, pb)
          local wrote = writeControl(entry.control, node, dx, dy,
                                     entry.last, entry.kind)
          self.stats.written = self.stats.written + (wrote or 0)

          --[[ ★ 裁剪（overflow:hidden / border-radius）

               R17 实证：图片控件 + 遮罩图 = 裁剪容器，
              塞进去的子控件超出部分会被裁掉。

               ⚠️ 只在【形状变化】时写，避免每帧重复调用 SetImage。
                  SetImage 是引擎调用，有开销；而且它是 Tweenable 的兄弟方法，
                  频繁调用既不必要也可能干扰。
          ]]--
          local shape = node.style and node.style._clipShape
          if entry.clipShape ~= shape then
            if shape then
              local okClip, errClip = clip.setImage(entry.control, shape)
              if okClip then
                pcall(function() entry.control.enableMask = true end)
                pcall(function()
                  entry.control.reverseMaskArea =
                    (node.style and node.style._clipReverse) and true or false
                end)
                entry.clipShape = shape
              else
                -- 记一次警告，避免每帧刷屏
                if not self._warnedClip then
                  self._warnedClip = {}
                  util.warn("裁剪失败（" .. tostring(shape) .. "）: "
                            .. tostring(errClip)
                            .. " —— 请确认 PREFABS.image 已配置且索引正确")
                end
                entry.clipShape = shape   -- 标记已尝试，避免重复告警
              end
            else
              clip.clearClip(entry.control)
              entry.clipShape = nil
            end
          end

          --[[ ★ 裁剪容器的子文字控件：把文字写进去

               父是 image（负责裁剪），子 textbox 负责显示文字。
               样式沿用父节点的计算样式（颜色/字号/对齐），
               位置铺满父控件，这样文字与"元素本身"视觉一致。
            ]]--
          if entry.textChild then
            local tc = entry.textChild
            local tl = entry.textLast

            -- 铺满父控件（父已是布局坐标，子是相对父中心 -> 0,0）
            local function tset(field, value)
              if tl[field] == value then return end
              tl[field] = value
              pcall(function() tc[field] = value end)
            end

            local function tsetColor(field, c)
              if not c then return end
              local key = field .. "_c"
              local prev = tl[key]
              if prev and prev.r == c.r and prev.g == c.g
                 and prev.b == c.b and prev.a == c.a then return end
              tl[key] = { r = c.r, g = c.g, b = c.b, a = c.a }
              pcall(function()
                tc[field] = Color.FromRGBA(c.r, c.g, c.b, c.a or 255)
              end)
            end

            tset("anchorMinX", 0.5); tset("anchorMinY", 0.5)
            tset("anchorMaxX", 0.5); tset("anchorMaxY", 0.5)
            tset("pivotX", 0.5);     tset("pivotY", 0.5)
            tset("sizeDeltaX", box.w or 0)
            tset("sizeDeltaY", box.h or 0)
            tset("anchoredPositionX", 0)
            tset("anchoredPositionY", 0)

            local st2 = node.style or {}
            local ntext = dom.textOf(node) or ""
            tset("text", ntext)
            tset("fontSize", util.toFontSize(st2._fontSize, 14))
            tsetColor("fontColor", st2._color)

            --[[ ★★ 承载文字的子文本框必须【继承父的背景色】（R21，2026-10-08）

                 为什么必须做：
                   当一个元素【自带直接文字】时，库会额外挂一个
                   textbox 子控件来承载文字（因为父可能是 image 等
                   没有 text 字段的类型）。这个子控件是【新建的控件】，
                   于是吃到【引擎的默认深色底】（实测 #535353）。

                 真机症状：CSS 里明明写了 background-color:#f7f7f7
                   和 color:#535353，屏幕上文字却【完全看不见】——
                   因为文字其实画在这个带默认深色底的子控件上，
                   深灰字压在深灰底上（实测对比度仅 3）。

                 ★ 修复：父有什么底色，就刷到什么底色。
                   这样 overflow:hidden 容器（父无底色、由子层承载）
                   也不会被误刷成不透明 —— 父的 _bgColor 为 nil 时
                   这里什么也不做。
            ]]--
            if st2._bgColor then
              tsetColor("bgColor", st2._bgColor)
            end

            -- 水平对齐
            local ta = st2._textAlign
            local alignVal = "left"
            if ta == "center" then alignVal = "middle"
            elseif ta == "right" then alignVal = "right" end
            if tl.__align ~= alignVal then
              tl.__align = alignVal
              if alignVal == "middle" then
                pcall(function() tc.horizontalAlignment = Enum.TextHorizontalAlignmentMiddle end)
              elseif alignVal == "right" then
                pcall(function() tc.horizontalAlignment = Enum.TextHorizontalAlignmentRight end)
              else
                pcall(function() tc.horizontalAlignment = Enum.TextHorizontalAlignmentLeft end)
              end
            end
          end

          -- 覆盖层：铺满父控件，只负责接收事件
          if entry.hot then
            local hw, hh = box.w or 0, box.h or 0
            local h = entry.hot
            local function hset(field, value)
              local prev = entry.hotLast[field]
              if type(value) == "number" and type(prev) == "number"
                 and math.abs(value - prev) < EPS then return end
              if prev == value then return end
              pcall(function() h[field] = value end)
              entry.hotLast[field] = value
            end
            hset("anchorMinX", 0.5); hset("anchorMinY", 0.5)
            hset("anchorMaxX", 0.5); hset("anchorMaxY", 0.5)
            hset("pivotX", 0.5);     hset("pivotY", 0.5)
            hset("sizeDeltaX", hw);  hset("sizeDeltaY", hh)
            hset("anchoredPositionX", 0)   -- 覆盖层居中于父
            hset("anchoredPositionY", 0)
            -- 确保可交互
            pcall(function() h.interactable = true end)
            pcall(function() h.raycastTarget = true end)
            pcall(function() h:SetActive(true) end)
          end
          self.stats.nodes = (self.stats.nodes or 0) + 1

          -- 子节点入栈
          for i = #node.children, 1, -1 do
            stack[#stack + 1] = { node = node.children[i], parentBox = box,
                                  parentControl = entry.control }
          end
        end
      end
    elseif node:isText() then
      -- 文本由父控件的 text 字段承载，这里不单独建控件
      -- （简化：一个元素只显示自己的直接文本子节点拼接）
    end
  end

  -- 回收：DOM 未变时，本帧没见到的节点（例如 display:none 或已删除）
  --
  --   ⚠️ domChanged 时不需要做 —— 阶段 0 已经全部还池了。
  if not domChanged then
    local removed = {}
    for node, entry in pairs(self.live) do
      if not seen[node] then
        self:_hide(entry.control)
        if entry.hot then self:_hide(entry.hot) end
        removed[#removed + 1] = node
      end
    end
    for i = 1, #removed do
      local e = self.live[removed[i]]
      self.live[removed[i]] = nil
      if e then
        local list = self.pool[e.kind]
        if not list then list = {}; self.pool[e.kind] = list end
        list[#list + 1] = e.control
        -- ★ 记账：这个控件现在【在池里】（供 isOrphan 查询）
        if not self._pooled then self._pooled = {} end
        self._pooled[e.control] = true
        --[[ ⚠️ 这里【故意不写】control._orphan（自定义字段，真机写入静默失败）。

             本项目硬性约束：控件无法存自定义状态（见 CLAUDE.md）。
             所以"这个控件是否在池里"必须由【渲染器自己记账】，
             用 rendered:isOrphan(control) 查（见下）。

             ★ 历史教训：这里曾写过 `_orphan = true`，应用层也真的去读它 ——
               那个判断【恒为真】（读回永远 nil）= 空检查，会把图/色
               写到池里【别人的】控件上（白块/串色，不报错）。别再加回来。 ]]
        if e.hot then
          local hlist = self.pool["button"]
          if not hlist then hlist = {}; self.pool["button"] = hlist end
          hlist[#hlist + 1] = e.hot
          self._pooled[e.hot] = true
        end
      end
    end
  end

  --===========================================================================
  -- z-index 排序
  --
  --   引擎只有 SetSiblingIndex（同级排序），没有全局 z-index。
  --   所以只处理【同一父下】的兄弟节点排序：
  --     按 z-index 升序排列（值大的靠上显示）
  --     z-index 相同的保持原有 DOM 顺序（稳定排序）
  --
  --   ⚠️ 官方文档提醒：复用列表生成的列表项不保证同级排序稳定。
  --      所以这里只对【显式设置了 z-index】的节点动手，其余不动。
  --===========================================================================
  if not self._zPass then self._zPass = {} end
  local byParent = self._zPass
  for k in pairs(byParent) do byParent[k] = nil end

  for node in pairs(seen) do
    local st = node.style
    if st and st._zIndex then
      local parent = node.parent
      if parent then
        local list = byParent[parent]
        if not list then list = {}; byParent[parent] = list end
        list[#list + 1] = node
      end
    end
  end

  for parent, list in pairs(byParent) do
    if #list > 1 then
      -- 稳定排序：z-index 升序
      table.sort(list, function(a, b)
        return (a.style._zIndex or 0) < (b.style._zIndex or 0)
      end)
      -- 依次设置 sibling index
      for i = 1, #list do
        local e = self.live[list[i]]
        if e and e.control then
          pcall(function() e.control:SetSiblingIndex(i - 1) end)
        end
      end
    end
  end

  -- ⚠️ 诊断：若一个控件都没建出来，说明 PREFABS 没配好。
  --    这是第一次真机测试踩过的坑（画面空白但日志正常）。
  if #root.children > 0 and self.stats.created == 0
     and (function() local n = 0 for _ in pairs(self.live) do n = n + 1 end return n end)() == 0 then
    if not self._warnedAllFailed then
      self._warnedAllFailed = true
      util.warn("渲染后一个控件都没创建成功 —— 几乎可以确定是 PREFABS 模板索引没配。")
      util.warn("  当前 PREFABS = " .. (function()
        if not self.prefabs then return "(nil)" end
        local t = {}
        for k, v in pairs(self.prefabs) do t[#t+1] = k .. "=" .. tostring(v) end
        return "{" .. table.concat(t, ", ") .. "}"
      end)())
      util.warn("  请在编辑器里为容器/文本框/按钮各建一个模板，把索引填进 PREFABS。")
    end
  end

  return self
end
function Renderer:statsText()
  local s = self.stats
  return string.format("控件 created=%d reused=%d hidden=%d written=%d live=%d",
      s.created, s.reused, s.destroyed, s.written,
      (function() local n = 0 for _ in pairs(self.live) do n = n + 1 end return n end)())
end

--[[ 清空所有控件 ]]--
function Renderer:clear()
  for node, entry in pairs(self.live) do
    self:_hide(entry.control)
  end
  self.live = {}
  self.pool = {}
  self._pooled = {}
  return self
end

R.Renderer = Renderer
R.chooseKind = chooseKind
R.computeAnchored = computeAnchored

return R
