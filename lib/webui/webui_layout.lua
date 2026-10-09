--[[============================================================================
  webui/layout.lua  ——  盒模型布局计算

  坐标约定（内部统一用 HTML 习惯）：
    - 原点在【左上角】，X 向右，Y 向下
    - 渲染层负责翻转成千星的【左下原点、Y 向上】

  布局模型：
    - block：垂直堆叠，宽度默认填满父
    - inline：行内（简化：当作 block 处理，但宽度收缩到内容）
    - inline-block：宽度收缩到内容
    - none：不参与布局
    - flex：单行主轴排列（row / column）

  position：
    static / relative：参与正常流
    absolute / fixed：脱离流，相对父 padding box 定位

  输出：node.box = {
    x, y, w, h,            -- 相对画布左上角的内容盒位置
    contentX, contentY,    -- 内容区起点（去掉 padding）
    contentW, contentH,
    contentBoxW, contentBoxH,
  }
==============================================================================]]

local style = require('webui_style')
local util  = require('webui_util')
local dom   = require('webui_dom')

local L = {}

--=============================================================================
-- 辅助
--=============================================================================

--[[ 长度求值上下文：vw/vh 的换算是按【逻辑设计尺寸】而不是真实画布。

     ★ 因为布局全程在设计坐标系里算，适配缩放由渲染层统一施加
       （见 webui_fit.lua）。若这里用真实画布，后面会被再缩放一次。 ]]--
local CTX = { vw = nil, vh = nil, rootFontSize = nil }

--[[ 设置视口单位基准（由 layout.compute 每帧调用） ]]--
function L.setViewportBase(w, h, rootFs)
  CTX.vw = w
  CTX.vh = h
  if rootFs then CTX.rootFontSize = rootFs end
end

--[[ 解析长度。

     返回 value, mode，mode ∈ {"px","%","auto","none"}。
     ★ 视口单位 / em / rem 在这里就换算成 px（它们不依赖父盒）。
     ★ % 保持原样返回，由调用方用正确的基准换算。 ]]--
local function len(str, base, fontSize)
  --[[ calc() 单独处理：它可能要基准才能算完。

       ⚠️ calc(50% - 100px) 这种混合表达式，
          必须把 base（父内容区宽/高）喂进去才算得对。
          普通 parseLength 走不到这里 —— 它不知道基准。 ]]--
  if type(str) == "string" then
    local s = util.trim(str):lower()
    if s:sub(1, 5) == "calc(" and s:sub(-1) == ")" then
      local ctx = { fontSize = fontSize or 14,
                    rootFontSize = CTX.rootFontSize or 14,
                    vw = CTX.vw, vh = CTX.vh }
      local v, unit, ok = style.evalCalc(s:sub(6, -2), ctx, base)
      if ok then
        if unit == "%" then
          -- 没给基准：无法定值
          return nil, "%"
        end
        return v, "px"
      end
      if not L._warnedCalc then L._warnedCalc = {} end
      if not L._warnedCalc[str] then
        L._warnedCalc[str] = true
        util.warn("无法求值的 calc() 表达式 '" .. tostring(str) .. "' —— 已当作 0 处理")
      end
      return 0, "px"
    end
  end

  local l = style.parseLength(str)

  -- ★ 无法解析的值：告警而不是静默当 0（静默失效最难查）
  if l.invalid then
    if not L._warnedBadLen then L._warnedBadLen = {} end
    local key = tostring(l.src)
    if not L._warnedBadLen[key] then
      L._warnedBadLen[key] = true
      util.warn(string.format(
        "无法解析的长度值 '%s'%s —— 已当作 0 处理。"
        .. "支持的单位：px / %% / em / rem / vw / vh / vmin / vmax / calc()",
        tostring(l.src),
        l.unknownUnit and ("（单位 '" .. l.unknownUnit .. "' 未实现）") or ""))
    end
    return 0, "px"
  end

  if l.auto then return nil, "auto" end
  if l.none then return nil, "none" end
  if l.unit == "%" then return base and (base * l.n / 100) or nil, "%" end
  if l.unit == "px" then return l.n, "px" end

  -- em / rem
  if l.unit == "em" then return l.n * (fontSize or 14), "em" end
  if l.unit == "rem" then
    return l.n * (CTX.rootFontSize or 14), "rem"
  end

  -- ★ 视口单位（按逻辑设计尺寸换算）
  if l.unit == "vw" then return l.n * (CTX.vw or 1600) / 100, "vw" end
  if l.unit == "vh" then return l.n * (CTX.vh or 900) / 100, "vh" end
  if l.unit == "vmin" then
    local a, b = CTX.vw or 1600, CTX.vh or 900
    return l.n * (a < b and a or b) / 100, "vmin"
  end
  if l.unit == "vmax" then
    local a, b = CTX.vw or 1600, CTX.vh or 900
    return l.n * (a > b and a or b) / 100, "vmax"
  end

  return l.n, "px"
end

--[[ 取四个方向的边距（数值形式，auto 当 0）。

     ⚠️ 绝大多数调用点要的是数值（间距累加、宽度扣减等），
        所以默认返回数值。需要区分 auto 的地方（水平居中）
        请用 boxEdgesRaw。 ]]--
local function boxEdges(st, base, attr)
  local out = {}
  for _, side in ipairs{"top", "right", "bottom", "left"} do
    local k = attr .. "-" .. side
    local v, mode = len(st[k], base, st._fontSize)
    if mode == "auto" then
      out[side] = 0
    else
      out[side] = v or 0
    end
  end
  return out
end

--[[ 取四个方向的边距，【保留 auto 语义】。

     ★★ 原生 CSS 里 `margin: 0 auto` 是水平居中的标准写法，
        必须能区分 "0" 和 "auto"，否则居中永远失效。
        返回：每个方向是 数值 或 字符串 "auto"。 ]]--
local function boxEdgesRaw(st, base, attr)
  local out = {}
  for _, side in ipairs{"top", "right", "bottom", "left"} do
    local k = attr .. "-" .. side
    local v, mode = len(st[k], base, st._fontSize)
    if mode == "auto" then
      out[side] = "auto"
    else
      out[side] = v or 0
    end
  end
  return out
end

--[[ ★★ 按 auto margin 调整水平位置（原生 CSS 的 auto margin 语义）

     margin-left/right 为 auto 时，剩余空间按规则分配：
       两边都 auto   -> 平分（水平居中）
       只有左边 auto -> 全部给左边（右对齐）
       只有右边 auto -> 全部给右边（左对齐）

     返回值语义（务必看清，这里踩过重复计算的坑）：
       offset      相对"父内容区左边 + 非 auto 的左边距"的额外偏移
       marL/marR   归一化后的实际左右边距（auto 已变成具体值）
       都不是 auto 时 offset 返回 nil，调用方按原 margleft 定位
]]--
local function resolveAutoMarginH(marL, marR, availW, usedW)
  local lAuto = (marL == "auto")
  local rAuto = (marR == "auto")
  if not lAuto and not rAuto then
    return nil, (marL or 0), (marR or 0)
  end

  local baseL = lAuto and 0 or (marL or 0)
  local baseR = rAuto and 0 or (marR or 0)
  local free = availW - baseL - baseR - usedW
  if free < 0 then free = 0 end

  if lAuto and rAuto then
    return free / 2, free / 2, free / 2
  elseif lAuto then
    return free, free, baseR          -- 左边吃全部剩余 -> 靠右
  else
    return 0, baseL, free             -- 右边吃全部剩余 -> 靠左
  end
end

--=============================================================================
-- 内容固有尺寸测量（文本 / 收缩宽度）
--=============================================================================

--[[ 递归估算节点的"收缩到内容"宽度（shrink-to-fit）]]--
--[[ 元素自身的固有宽度（★ 不含 margin）

     ⚠️ 2026-10-07 修正：原来这里把 margin 也算进了 extraW，
        但本函数的语义是"元素自身宽度"，margin 是【外部间距】，
        不该算进来。而且调用方（flex）还会自己加一次 margin，
        导致宽度被多算一个 margin 的量。

     真机表现：
        .avatar { width:130px; margin-right:20px }
          -> 布局宽度算成 150
          -> 子元素 .avatar-inner 只有 130
          -> 父右侧露出 20px（控件默认白底）-> 屏幕上一条白色竖条

     现在 extraW 只含 padding，margin 由调用方处理。
]]--
local function intrinsicWidth(node, availW, availH)
  if node:isText() then
    local st = node.style or {}
    return util.measureText(node.text or "", st._fontSize or 14)
  end
  if not node:isElement() then
    -- root
    local mw = 0
    for i = 1, #node.children do
      local w = intrinsicWidth(node.children[i], availW, availH)
      if w > mw then mw = w end
    end
    return mw
  end

  local st = node.style
  if not st or st.display == "none" then return 0 end

  local pad = boxEdges(st, availW, "padding")
  local extraW = pad.left + pad.right       -- ★ 不含 margin

  -- 显式宽度优先
  local w, mode = len(st.width, availW, st._fontSize)
  if w and mode ~= "auto" and mode ~= "none" then
    return w + extraW
  end

  -- 子节点横向排布
  local st_display = st.display
  if st_display == "flex" and st["flex-direction"] ~= "column" then
    local total = 0
    for i = 1, #node.children do
      total = total + intrinsicWidth(node.children[i], availW, availH)
    end
    local gap = len(st.gap, availW, st._fontSize) or 0
    if #node.children > 1 then total = total + gap * (#node.children - 1) end
    return total + extraW
  end

  -- block：取子节点最大值
  local mw = 0
  for i = 1, #node.children do
    local cw = intrinsicWidth(node.children[i], availW, availH)
    if cw > mw then mw = cw end
  end
  return mw + extraW
end

--[[ 递归估算高度（用于 height:auto）]]--
local function intrinsicHeight(node, w, availH)
  if node:isText() then
    local st = node.style or {}
    local fs = st._fontSize or 14
    local lh = st._lineHeight or (fs * 1.2)
    -- 按可用宽度算行数
    local text = node.text or ""
    if text == "" then return 0 end
    local textW = util.measureText(text, fs)
    local lines = 1
    if w and w > 1 and textW > w then
      lines = math.ceil(textW / w)
    end
    return lines * lh
  end

  if not node:isElement() then
    local total = 0
    for i = 1, #node.children do
      total = total + intrinsicHeight(node.children[i], w, availH)
    end
    return total
  end

  local st = node.style
  if not st or st.display == "none" then return 0 end

  local pad = boxEdges(st, w, "padding")
  local mar = boxEdges(st, w, "margin")
  local extraH = pad.top + pad.bottom + mar.top + mar.bottom

  local h, mode = len(st.height, availH, st._fontSize)
  if h and mode ~= "auto" and mode ~= "none" then
    return h + extraH
  end

  local innerW = (w or 0) - pad.left - pad.right
  if innerW < 1 then innerW = w or 0 end

  local total = 0
  if st.display == "flex" and st["flex-direction"] == "column" then
    for i = 1, #node.children do
      total = total + intrinsicHeight(node.children[i], innerW, availH)
    end
    local gap = len(st.gap, w, st._fontSize) or 0
    if #node.children > 1 then total = total + gap * (#node.children - 1) end
  else
    for i = 1, #node.children do
      total = total + intrinsicHeight(node.children[i], innerW, availH)
    end
  end
  return total + pad.top + pad.bottom + mar.top + mar.bottom
end

--=============================================================================
-- 主布局
--=============================================================================

--[[ 对一个盒子布局：parentX/Y 是父的【内容区】左上角

     widthOverride: 由 flex 布局算出的宽度。传入时忽略 st.width，
                    否则 flex-grow / flex-shrink 的结果会被丢弃。

     heightOverride: 由 flex 的 align-items:stretch 算出的高度。
                     传入时忽略 st.height（且当 autoH 处理），
                     用于把子项拉伸到本行高度。
]]--
local function layoutNode(node, parentContentX, parentContentY, parentContentW, parentContentH, canvasW, canvasH, widthOverride, heightOverride)
  if node:isText() then
    -- 文本节点：占据父给的位置，高度按自身算
    local st = node.style or {}
    local fs = st._fontSize or 14
    local lh = st._lineHeight or (fs * 1.2)
    local text = node.text or ""
    local textW = util.measureText(text, fs)
    local lines = 1
    if parentContentW and parentContentW > 1 and textW > parentContentW then
      lines = math.ceil(textW / parentContentW)
    end
    node.box = {
      x = parentContentX, y = parentContentY,
      w = parentContentW, h = lines * lh,
      contentX = parentContentX, contentY = parentContentY,
      contentW = parentContentW, contentH = lines * lh,
      isText = true,
    }
    return node.box
  end

  local st = node.style
  if not st then
    -- 没有样式（不该发生），给个空盒
    node.box = { x = parentContentX, y = parentContentY, w = 0, h = 0,
                 contentX = parentContentX, contentY = parentContentY,
                 contentW = 0, contentH = 0 }
    return node.box
  end

  if st.display == "none" or st.visibility == "hidden" and false then
    node.box = { x = parentContentX, y = parentContentY, w = 0, h = 0,
                 contentX = parentContentX, contentY = parentContentY,
                 contentW = 0, contentH = 0, hidden = true }
    return node.box
  end

  local fs = st._fontSize or 14

  -- ---- 解析宽高 ----
  local pos = st.position or "static"
  local isAbs = (pos == "absolute" or pos == "fixed")

  -- 可用基准：绝对定位相对父 padding box；普通流相对父内容区
  local baseW = parentContentW
  local baseH = parentContentH
  if isAbs then
    -- 用父的 padding box（近似：内容区 + 父 padding 已被上层扣除，这里直接用 parentContent）
    baseW = parentContentW
    baseH = parentContentH
  end

  -- ---- 边距 / 内边距 ----
  --   ⚠️ 必须在算宽高【之前】就拿到 padding ——
  --      box-sizing: border-box 要用它把声明值换算成内容区尺寸。
  local mar = boxEdges(st, baseW, "margin")
  local pad = boxEdges(st, baseW, "padding")

  --[[ ★★ box-sizing（严格对齐原生 CSS）

     ⚠️ 历史：这个属性原来写在 DEFAULTS 里但布局器【从未读过】，
        而实际行为是 border-box（width 含 padding）——
        与它声明的默认值 content-box 相反。
        现按【原生语义】修正：

       content-box（默认）：width/height 只算内容区，
                            实际占位 = width + padding + border
       border-box        ：width/height 含 padding，
                            内容区 = width - padding

     ⚠️ 这是一次【行为变更】：以前写 width:400px; padding:20px
        得到 400 宽，现在得到 440（原生行为）。
        需要旧的"宽度含 padding"语义时，显式写 box-sizing: border-box。
  ]]--
  local borderBox = (st["box-sizing"] == "border-box")

  --[[ 把"声明的宽度/高度"换算成【内容区】尺寸。

       content-box：声明值就是内容区 → 原样返回
       border-box ：声明值含 padding  → 减去 padding ]]--
  local function toContentW(declared)
    if declared == nil then return nil end
    if borderBox then
      return declared - pad.left - pad.right
    end
    return declared
  end
  local function toContentH(declared)
    if declared == nil then return nil end
    if borderBox then
      return declared - pad.top - pad.bottom
    end
    return declared
  end

  -- 内部统一用【内容区宽度】运算（cw），最后再转回外框
  local function toBorderW(contentW)
    if borderBox then return contentW end
    return contentW + pad.left + pad.right
  end

  --[[ 宽度

       ⚠️ 这里 w 全程表示【内容区宽度】（与原生 CSS 的 width 属性一致），
          最后创建 box 时才转成外框宽度（见下方 borderW）。
          这样 padding 才不会重复计入。 ]]--
  local w, wmode = len(st.width, baseW, fs)
  if widthOverride then
    w = widthOverride
    wmode = "px"
  elseif wmode == "auto" or w == nil then
    if isAbs then
      -- 绝对定位 + auto：收缩到内容
      w = intrinsicWidth(node, baseW, baseH)
    elseif st.display == "inline-block" or st.display == "inline" then
      w = intrinsicWidth(node, baseW, baseH)
      if baseW and w > baseW then w = baseW end
    else
      --[[ block：填满父内容区

           ★ 原生语义：auto 宽度下，元素外框 = 父内容区宽 - 左右 margin，
             而内容区 = 外框 - padding（padding 从里面扣）。
             所以这里要先把 padding 从可用宽度里减掉。 ]]--
      w = (baseW or 0) - pad.left - pad.right
      if w < 0 then w = 0 end
    end
  else
    -- ★ 显式 width：统一换算成内容区宽度
    w = toContentW(w)
  end
  -- min/max（原生：作用于内容区，这里已在内容区口径下比较）
  local minW = len(st["min-width"], baseW, fs)
  local maxW = len(st["max-width"], baseW, fs)
  minW = toContentW(minW)
  maxW = toContentW(maxW)
  if minW and w < minW then w = minW end
  if maxW and w > maxW then w = maxW end

  -- 高度（同样是内容区口径；auto 时后面按内容撑开）
  local h, hmode = len(st.height, baseH, fs)
  local autoH = (hmode == "auto" or h == nil)
  if h ~= nil then h = toContentH(h) end

  --[[ ★ flex stretch：由父指定高度（覆盖 st.height）

       语义：拉伸到本行高度，所以高度是【外框高度】，
             内容区 = 外框 - 上下 padding。
             ⚠️ 仍当 autoH 处理 —— 这样父的自动高度逻辑与不拉伸时一致，
                不会因为拉伸值反向影响父的行高计算。 ]]--
  if heightOverride then
    h = heightOverride - pad.top - pad.bottom
    if h < 0 then h = 0 end
    autoH = false
  end

  -- 外框宽度（渲染与定位都用它）
  local borderW = w + pad.left + pad.right

  --[[ ★★ auto margin 水平居中（原生 CSS `margin: 0 auto`）

       ⚠️ 这是原生 CSS 最常用的居中写法，之前静默失效（auto 变 0，
          元素贴在左边）。

       只在【正常流 + 非 absolute】时生效：
       绝对定位元素没有"剩余空间"概念（它的宽度由 left/right 决定）。

       ★ 语义：_autoMarginX 是【相对父内容区左边】的完整水平位置，
         调用方用它【取代】mar.left，不要再叠加（踩过重复计算的坑）。
  ]]--
  if not isAbs then
    local rawMar = boxEdgesRaw(st, baseW, "margin")
    local offL, ml, mr = resolveAutoMarginH(rawMar.left, rawMar.right,
                                            baseW or 0, w)
    if offL then
      mar.left, mar.right = ml, mr
      node._autoMarginX = offL      -- 完整水平位置（取代 mar.left）
    else
      node._autoMarginX = nil
    end
  else
    node._autoMarginX = nil
  end

  -- ---- 定位原点 ----
  local x, y
  if isAbs then
    -- 相对父 padding box：left/right/top/bottom
    local l, _ = len(st.left, baseW, fs)
    local r, _ = len(st.right, baseW, fs)
    local t, _ = len(st.top, baseH, fs)
    local b, _ = len(st.bottom, baseH, fs)

    if l then x = parentContentX + l
    elseif r then x = parentContentX + (baseW or 0) - r - w
    else x = parentContentX end

    if b then
      -- 注意：内部坐标是 Y 向下，CSS 的 bottom 是距底部
      y = parentContentY + (baseH or 0) - b - (h or 0)
    elseif t then
      y = parentContentY + t
    else
      y = parentContentY
    end
  else
    --[[ 正常流：父排布决定实际位置。

         ⚠️ 这里保留 mar.top 的叠加 —— 这是本函数与调用方的约定：
            调用方传进来的 parentContentY 是"上一个元素的底边
            （或父内容区顶端，用于第一个元素）"，
            本函数负责加上自己的 margin-top。

         所以调用方【不要】预先加 margin-top，否则会重复计算
         （实测踩过：间距变成两倍）。 ]]--
    --[[ ★ auto margin 时 _autoMarginX 是【完整水平位置】，
         直接用它取代 mar.left（不要再叠加）。 ]]--
    if node._autoMarginX then
      x = parentContentX + node._autoMarginX
    else
      x = parentContentX + mar.left
    end
    y = parentContentY + mar.top
  end

  -- relative：在正常流基础上偏移
  if pos == "relative" then
    local l = len(st.left, baseW, fs)
    local t = len(st.top, baseH, fs)
    if l then x = x + l end
    if t then y = y + t end
  end

  --[[ 先创建 box（高度可能待定）

       ★ box.w / box.h 是【外框尺寸】（内容 + padding），
         因为渲染层把它们直接写进 sizeDelta。
         box.contentW / contentH 才是内容区。 ]]--
  local box = {
    x = x, y = y,
    w = borderW,
    h = (h ~= nil) and (h + pad.top + pad.bottom) or 0,
    margin = mar, padding = pad,
    isAbs = isAbs,
    autoH = autoH,
  }
  node.box = box

  -- ---- 内容区 ----
  local cw = w                       -- w 已是内容区宽度
  if cw < 0 then cw = 0 end
  local contentX = x + pad.left
  local contentY = y + pad.top

  -- ---- 子节点布局 ----
  local children = {}
  for i = 1, #node.children do
    local c = node.children[i]
    -- 跳过 display:none
    local show = true
    if c:isElement() and c.style and c.style.display == "none" then show = false end
    if show then children[#children + 1] = c end
  end

  -- 可用高度传给子节点：如果自身高度 auto，先给一个估计
  local childBaseH = box.h
  if autoH or childBaseH <= 0 then
    childBaseH = (parentContentH or 0) - y + parentContentY
    if childBaseH < 0 then childBaseH = 0 end
  end

  local flowChildren = {}
  local absChildren = {}
  for i = 1, #children do
    local c = children[i]
    local cst = c.style
    if cst and (cst.position == "absolute" or cst.position == "fixed") then
      absChildren[#absChildren + 1] = c
    else
      flowChildren[#flowChildren + 1] = c
    end
  end

  local usedH = 0

  if st.display == "flex" then
    -- ---- flex 布局（简化：单行） ----
    local dir = st["flex-direction"] or "row"
    local justify = st["justify-content"] or "flex-start"
    local alignItems = st["align-items"] or "stretch"
    local gap = len(st.gap, cw, fs) or 0

    if dir == "column" then
      local cy = contentY

      --[[ ★ flex column 的交叉轴对齐（2026-10-07 修）

           bug：这里原来无条件把子项宽度设为父容器宽度（cw2 = cw），
                导致子项 CSS 里显式写的 width 【被完全忽略】。

           真机表现（很隐蔽）：
             #root { display:flex; flex-direction:column }
               .avatar { width:130px }   -> 实际被算成 980px（父宽）
               于是 border-radius:50% 按 980:130 适配
               -> 圆形被横向拉成"扁椭圆"
               同理 overflow:hidden 的卡片变宽 -> 子元素不再溢出 -> 裁剪看不出效果

           正确语义：
             align-items: stretch 时，只有【未显式指定宽度】的子项才拉伸；
             指定了 width 的子项应保持自身宽度，并按 align-items 决定水平位置。
      ]]--
      for i = 1, #flowChildren do
        local c = flowChildren[i]
        local cst = c.style or {}
        local cmar = boxEdges(cst, cw, "margin")
        local ch = intrinsicHeight(c, cw, childBaseH)

        -- 子项是否显式指定了宽度
        local expW, expMode = len(cst.width, cw, cst._fontSize or 14)
        local hasExplicitW = expW and expMode ~= "auto" and expMode ~= "none"

        local cw2
        local cx2 = contentX + cmar.left

        if hasExplicitW then
          -- 显式宽度：保持自身宽度，按 align-items 水平定位
          cw2 = expW
          local availW = cw - cmar.left - cmar.right
          local free = availW - cw2
          local align = alignItems
          if align == "center" then
            cx2 = contentX + cmar.left + free / 2
          elseif align == "flex-end" then
            cx2 = contentX + cmar.left + free
          end
          -- flex-start / stretch 都靠左
        else
          -- 未指定：stretch 填满；否则收缩到内容宽
          if alignItems == "stretch" then
            cw2 = cw - cmar.left - cmar.right
          else
            cw2 = intrinsicWidth(c, cw, childBaseH)
            local availW = cw - cmar.left - cmar.right
            local free = availW - cw2
            if alignItems == "center" then
              cx2 = contentX + cmar.left + free / 2
            elseif alignItems == "flex-end" then
              cx2 = contentX + cmar.left + free
            end
          end
        end

        layoutNode(c, cx2, cy + cmar.top, cw2, childBaseH,
                   canvasW, canvasH, cw2)
        cy = cy + ch + gap
      end
      usedH = cy - contentY - (gap > 0 and gap or 0)
    else
      -- row（支持 flex-wrap: wrap）
      local wrap = (st["flex-wrap"] == "wrap" or st["flex-wrap"] == "wrap-reverse")

      local widths = {}
      for i = 1, #flowChildren do
        local c = flowChildren[i]
        local cst = c.style or {}
        local cmar = boxEdges(cst, cw, "margin")

        --[[ ★ 行内占位宽度 = 元素自身宽度 + 左右 margin

             intrinsicWidth() 【不含 margin】（已修正），
             所以这里加一次 margin 得到行内占位，是正确的。
        ]]--
        local cwid = intrinsicWidth(c, cw, childBaseH)
        local outerW = cwid + cmar.left + cmar.right   -- 行内占位

        -- flex 基础尺寸：flex-basis > width > 内容宽
        local basis = nil
        local fb = cst["flex-basis"]
        if fb and fb ~= "auto" and fb ~= "none" then
          local b = len(fb, cw, cst._fontSize)
          if b then basis = b end
        end

        widths[i] = {
          w = outerW,        -- 行内占位（含 margin）
          inner = cwid,      -- 元素自身内容宽（不含 margin）
          basis = basis,
          mar = cmar,
          grow = tonumber(cst["flex-grow"]) or 0,
          shrink = tonumber(cst["flex-shrink"]) or 1,
        }
      end

      -- ---- 分行（flex-wrap）----
      local lines = {}
      if wrap then
        local cur = { items = {}, width = 0 }
        for i = 1, #flowChildren do
          local wI = widths[i].basis or widths[i].w
          local add = wI + (#cur.items > 0 and gap or 0)
          if #cur.items > 0 and cur.width + add > cw then
            lines[#lines + 1] = cur
            cur = { items = {}, width = 0 }
            add = wI
          end
          cur.items[#cur.items + 1] = i
          cur.width = cur.width + add
        end
        if #cur.items > 0 then lines[#lines + 1] = cur end
      else
        local all = { items = {}, width = 0 }
        for i = 1, #flowChildren do
          all.items[#all.items + 1] = i
          all.width = all.width + (widths[i].basis or widths[i].w)
        end
        if #all.items > 1 then all.width = all.width + gap * (#all.items - 1) end
        lines[1] = all
      end

      -- ---- 逐行布局 ----
      local lineY = contentY
      local totalH = 0

      for li = 1, #lines do
        local line = lines[li]
        local items = line.items
        local n = #items

        -- 本行的 grow / shrink 计算
        local lineW = 0
        for _, idx in ipairs(items) do
          lineW = lineW + (widths[idx].basis or widths[idx].w)
        end
        if n > 1 then lineW = lineW + gap * (n - 1) end

        local free = cw - lineW
        if free > 0 then
          local totalGrow = 0
          for _, idx in ipairs(items) do totalGrow = totalGrow + widths[idx].grow end
          if totalGrow > 0 then
            for _, idx in ipairs(items) do
              local info = widths[idx]
              if info.grow > 0 then
                info.w = (info.basis or info.w) + free * info.grow / totalGrow
              elseif info.basis then
                info.w = info.basis
              end
            end
          else
            for _, idx in ipairs(items) do
              if widths[idx].basis then widths[idx].w = widths[idx].basis end
            end
          end
        elseif free < 0 then
          local totalShrink = 0
          for _, idx in ipairs(items) do
            local info = widths[idx]
            totalShrink = totalShrink + info.shrink * (info.basis or info.w)
          end
          if totalShrink > 0 then
            for _, idx in ipairs(items) do
              local info = widths[idx]
              local base = info.basis or info.w
              local cut = (-free) * (info.shrink * base) / totalShrink
              local nw = base - cut
              if nw < 0 then nw = 0 end
              info.w = nw
            end
            lineW = 0
            for _, idx in ipairs(items) do lineW = lineW + widths[idx].w end
            if n > 1 then lineW = lineW + gap * (n - 1) end
          end
        else
          for _, idx in ipairs(items) do
            if widths[idx].basis then widths[idx].w = widths[idx].basis end
          end
        end

        -- justify（每行独立）
        local free2 = cw - lineW
        local startX = contentX
        local useGap = gap
        if justify == "center" then startX = contentX + free2 / 2
        elseif justify == "flex-end" then startX = contentX + free2
        elseif justify == "space-between" and n > 1 then
          useGap = gap + free2 / (n - 1)
        end

        -- 本行高度
        local maxH = 0
        local cx = startX
        local lineItems = {}
        for _, idx in ipairs(items) do
          local c = flowChildren[idx]
          local info = widths[idx]
          local cwid = info.w - info.mar.left - info.mar.right
          if cwid < 0 then cwid = 0 end
          local ch = intrinsicHeight(c, cwid, childBaseH)
          if ch + info.mar.top + info.mar.bottom > maxH then
            maxH = ch + info.mar.top + info.mar.bottom
          end
          lineItems[#lineItems + 1] = { c = c, info = info, cwid = cwid, ch = ch, x = cx }
          cx = cx + info.w + useGap
        end

        --[[ 真实布局（等本行 maxH 算完后才能做 align-items）

             ⚠️ 原来这里有两个 bug：
               ① center / flex-end 算出的 cy 之后，
                  layoutNode 内部又加了一次 mar.top —— 垂直居中不准
               ② stretch（默认值！）完全没实现 ——
                  子项不写 height 时高度塌成内容高，
                  而原生应为"拉伸到本行高度"

             ★ align-items 的基准高度（原生语义）：

                 · 容器有【确定高度】(height 非 auto) 且只有一行
                     -> 拉伸/居中都以【容器内容区高度】为准
                        （不是最高的子项！否则 stretch 永远不会生效）
                 · 否则 -> 以本行最高的子项为准

               ⚠️ 这里踩过：一开始用 maxH（最高子项）当基准，
                  结果 200px 高的容器里，子项只能拉伸到 16.8px。
            ]]--
        local alignBaseH = maxH
        if (not autoH) and #lines == 1 and cw >= 0 then
          -- 容器高度确定 + 单行：用容器内容区高度
          local containerContentH = box.h - pad.top - pad.bottom
          if containerContentH > alignBaseH then
            alignBaseH = containerContentH
          end
        end

        for _, it in ipairs(lineItems) do
          local mt = it.info.mar.top
          local mb = it.info.mar.bottom

          -- 可用于放置的净高度（扣掉子项自己的上下 margin）
          local slotH = alignBaseH - mt - mb
          if slotH < 0 then slotH = 0 end

          -- 基准位置（含 margin-top），layoutNode 会再加一次 mt？—— 不会，
          -- 因为我们传的是"内容顶端上一格"，这里统一按下面公式给基准
          local cy

          --[[ 是否要拉伸：align-items 默认就是 stretch；子项可用 align-self 覆盖

               ⚠️ align-self 的默认值是 "auto"（原生语义 = 跟随父的 align-items）。
                  所以【不能】用 `(cst["align-self"]) or alignItems` ——
                  那样拿到的是字符串 "auto"，既不等于 "stretch" 也不等于
                  "center"，于是掉到 flex-start 分支，拉伸**静默失效**。
                  实测：200px 容器里子项只有 16.8px。
                  （这是引入 align-self 默认值时踩的坑，回归被 test_wrap 抓到） ]]--
          local asRaw = it.c.style and it.c.style["align-self"]
          if asRaw == nil or asRaw == "auto" then asRaw = alignItems end
          local childAlign = asRaw
          local cst = it.c.style or {}
          local hasExplicitH = not (cst.height == nil or cst.height == "auto")

          if childAlign == "center" then
            cy = lineY + mt + (slotH - it.ch) / 2
          elseif childAlign == "flex-end" then
            cy = lineY + mt + (slotH - it.ch)
          elseif childAlign == "stretch" and not hasExplicitH then
            cy = lineY + mt
          else
            cy = lineY + mt          -- flex-start（默认）
          end

          --[[ ★ stretch：把子项高度撑到本行高度

               做法：给它一个"高度覆盖"，让 layoutNode 按这个高度算。
               仅在没有显式 height 时生效（见上面的 hasExplicitH）。

               ⚠️ 不能直接改 node.box.h —— 那会被 layoutNode 覆盖。
                  这里通过传一个 stretchH 参数实现（见 layoutNode 签名）。 ]]--
          local stretchH = nil
          if childAlign == "stretch" and not hasExplicitH and slotH > 0 then
            stretchH = slotH
          end

          -- ⚠️ layoutNode 会自己加 mar.top，所以这里传的是"基准 - mt"
          layoutNode(it.c, it.x + it.info.mar.left, cy - mt, it.cwid,
                     childBaseH, canvasW, canvasH, it.cwid, stretchH)
        end

        --[[ ★ 行高以 alignBaseH 为准推进

             因为 stretch 会把子项撑到 alignBaseH，
             若还用 maxH 推进，父的 auto 高度会算小（子项溢出）。 ]]--
        lineY = lineY + alignBaseH
        totalH = totalH + alignBaseH
      end

      usedH = totalH
    end

  elseif st.display == "grid" or st.display == "inline-grid" then
    --[[ ---- CSS Grid 布局 ----

         轨道解析 / 放置算法在 webui_grid.lua 里（纯计算，可单独验算）。
         这里负责：测量固有尺寸 -> 解析轨道 -> 逐项定位。

         ⚠️ 与 flex 的关键差异：
            grid 的"项"直接放在容器内容区里（不是嵌套在行盒里），
            所以 layoutNode 的 parentContentW 要传【轨道尺寸】而不是 cw。
     ]]--
    local g = require('webui_grid')
    local gs = g.parseStyle(st, cw)

    if not gs or not gs.cols then
      -- 没有 grid-template-columns：退化成单列（原生也会自动生成隐式列）
      gs = gs or {}
      gs.cols = { { kind = "auto" } }
      gs.rows = gs.rows or {}
      gs.colGap = gs.colGap or 0
      gs.rowGap = gs.rowGap or 0
      gs.flow = gs.flow or "row"
      gs.justifyItems = gs.justifyItems or "stretch"
      gs.alignItems = gs.alignItems or "stretch"
    end

    -- ① 放置
    local cols = #gs.cols
    local placed = g.place(flowChildren, cols, gs.flow == "column" and "column" or "row")

    -- ② 列尺寸
    local colSizes = g.resolveTracks(gs.cols or {}, cw, gs.colGap, placed, "col",
      function(item, _)
        local cst = item.style or {}
        local cmar = boxEdges(cst, cw, "margin")
        local w = intrinsicWidth(item, cw, childBaseH)
        return w + cmar.left + cmar.right
      end)

    -- ③ 行尺寸（用已定的列宽测量高度）
    local rowSizes = g.resolveTracks(gs.rows or {}, box.h - pad.top - pad.bottom,
      gs.rowGap, placed, "row",
      function(item, _)
        local cst = item.style or {}
        local cmar = boxEdges(cst, cw, "margin")
        local h = intrinsicHeight(item, cw, childBaseH)
        return h + cmar.top + cmar.bottom
      end)

    -- 把行尺寸补齐到放置结果所需
    local maxRow = 0
    for _, p in ipairs(placed) do
      local e = p.row + p.rowSpan - 1
      if e > maxRow then maxRow = e end
    end
    for i = #rowSizes + 1, maxRow do rowSizes[i] = 0 end

    -- ④ 轨道起始坐标（累加 gap）
    local colX = {}
    local x = contentX
    for i = 1, #colSizes do
      colX[i] = x
      x = x + (colSizes[i] or 0) + gs.colGap
    end

    local rowY = {}
    local y = contentY
    for i = 1, #rowSizes do
      rowY[i] = y
      y = y + (rowSizes[i] or 0) + gs.rowGap
    end

    -- ⑤ 逐项布局
    local maxBottom = contentY
    for _, p in ipairs(placed) do
      local c = p.item
      local cst = c.style or {}
      local cmar = boxEdges(cst, cw, "margin")

      -- 跨轨道时的尺寸 = 各轨道 + 中间的 gap
      local spanW = 0
      for k = p.col, p.col + p.colSpan - 1 do
        spanW = spanW + (colSizes[k] or 0)
      end
      if p.colSpan > 1 then spanW = spanW + gs.colGap * (p.colSpan - 1) end

      local spanH = 0
      for k = p.row, p.row + p.rowSpan - 1 do
        spanH = spanH + (rowSizes[k] or 0)
      end
      if p.rowSpan > 1 then spanH = spanH + gs.rowGap * (p.rowSpan - 1) end

      local px = colX[p.col] or contentX
      local py = rowY[p.row] or contentY

      --[[ 轨道内对齐

           stretch（默认）：撑满轨道（扣掉自身 margin）
           start/center/end：按内容尺寸，在轨道内对齐

           ⚠️ justify-self / align-self 的默认值是 "auto"
              （原生语义 = 跟随容器的 justify-items / align-items），
              不能直接 `or` —— 见 flex 分支里那条同样的坑。 ]]--
      local jsRaw = cst["justify-self"]
      if jsRaw == nil or jsRaw == "auto" then jsRaw = gs.justifyItems end
      local asRaw2 = cst["align-self"]
      if asRaw2 == nil or asRaw2 == "auto" then asRaw2 = gs.alignItems end
      local ji = jsRaw
      local ai = asRaw2

      local availW = spanW - cmar.left - cmar.right
      if availW < 0 then availW = 0 end

      local cw2 = availW
      if ji == "center" or ji == "end" or ji == "flex-end" then
        local iw = intrinsicWidth(c, availW, childBaseH)
        cw2 = math.min(iw, availW)
      end

      local cellX = px + cmar.left
      if ji == "center" then
        cellX = px + cmar.left + (availW - cw2) / 2
      elseif ji == "end" or ji == "flex-end" then
        cellX = px + cmar.left + (availW - cw2)
      end

      -- 高度：stretch 时撑满轨道
      local hOverride = nil
      local explicitH = cst.height and cst.height ~= "auto"
      if not explicitH and (ai == "stretch" or ai == nil) then
        hOverride = spanH - cmar.top - cmar.bottom
        if hOverride < 0 then hOverride = 0 end
      end

      local cb = layoutNode(c, 0, 0, availW, spanH, canvasW, canvasH, cw2, hOverride)

      -- 覆盖位置（layoutNode 按父内容区算的，这里改成轨道坐标）
      cb.x = cellX
      cb.contentX = cellX + (cb.padding and cb.padding.left or 0)

      local cy2 = py + cmar.top
      if not hOverride then
        if ai == "center" then
          cy2 = py + cmar.top + (spanH - cmar.top - cmar.bottom - cb.h) / 2
        elseif ai == "end" or ai == "flex-end" then
          cy2 = py + cmar.top + (spanH - cmar.top - cmar.bottom - cb.h)
        end
      end
      cb.y = cy2
      cb.contentY = cy2 + (cb.padding and cb.padding.top or 0)

      local bottom = cb.y + cb.h + cmar.bottom
      if bottom > maxBottom then maxBottom = bottom end
    end

    usedH = maxBottom - contentY

  else
    --[[ 普通 block 流

         ★ 同时修掉两个原生语义问题：
           ① auto margin 居中（之前 auto 当 0，元素贴左边）
           ② 外边距折叠：相邻兄弟取【较大者】，不是相加

         ⚠️ 与 layoutNode 的约定（这里踩过一次，务必看清）：
              layoutNode 内部会自己加 mar.top。
              所以这里传的是【基准位置】，不是最终位置：
                · 第一个元素      -> 父内容区顶端
                · 后续元素        -> 上一个元素的底边
                                   + max(prevMB, curMT) - curMT
              最后一个减去的 curMT 是因为 layoutNode 会再加回来，
              这样净效果正好是 max(prevMB, curMT)。
      ]]--
    local cy = contentY
    local prevMarginBottom = 0      -- 上一个元素的下外边距
    local prevBottom = contentY     -- 上一个元素的底边（不含下外边距）

    for i = 1, #flowChildren do
      local c = flowChildren[i]
      local cst = c.style or {}
      local cmar = boxEdges(cst, cw, "margin")

      -- 算出"基准位置"（layoutNode 会在此基础上加自己的 margin-top）
      local baseY
      if i > 1 then
        -- 折叠：相邻取较大者
        local gap = math.max(prevMarginBottom, cmar.top)
        baseY = prevBottom + gap - cmar.top
      else
        baseY = contentY
      end

      local childBaseW = cw - cmar.left - cmar.right
      if childBaseW < 0 then childBaseW = 0 end

      -- ★ auto margin 的水平位置已在 layoutNode 内处理，这里不再叠加
      local cb = layoutNode(c, contentX + cmar.left, baseY,
                            childBaseW, childBaseH, canvasW, canvasH)

      -- 记下这个元素的底边（不含下外边距）供下一个元素折叠用
      prevBottom = cb.y + cb.h
      prevMarginBottom = cmar.bottom
      cy = prevBottom
    end

    -- 总高度 = 最后一个元素底边 + 它的下外边距
    usedH = (prevBottom - contentY) + prevMarginBottom
  end

  -- 绝对定位子节点
  for i = 1, #absChildren do
    local c = absChildren[i]
    local cst = c.style or {}
    layoutNode(c, contentX, contentY, cw, box.h, canvasW, canvasH)
  end

  -- ---- 高度定案 ----
  if autoH then
    -- usedH 是内容区高度；外框要加上下 padding
    box.h = usedH + pad.top + pad.bottom

    -- min/max-height 作用于【内容区】（原生语义）
    local minH = toContentH(len(st["min-height"], baseH, fs))
    local maxH2 = toContentH(len(st["max-height"], baseH, fs))
    if minH then
      local outer = minH + pad.top + pad.bottom
      if box.h < outer then box.h = outer end
    end
    if maxH2 then
      local outer = maxH2 + pad.top + pad.bottom
      if box.h > outer then box.h = outer end
    end
  end

  box.contentX = contentX
  box.contentY = contentY
  box.contentW = cw
  box.contentH = box.h - pad.top - pad.bottom
  if box.contentH < 0 then box.contentH = 0 end

  --[[ ★★ transform 里的百分比要按【元素自身盒尺寸】重算

       ⚠️ 原生语义：translateX(50%) = 自身宽度的 50%。
          而样式计算阶段还不知道盒子尺寸，原来只能按 0 处理 ——
          于是 translateX(50%) 得到 50px（把 50% 当成了 50）。
          这里在布局完成后重算一次，基准就是刚算出的外框尺寸。

       ★ 只含百分比时才重算（否则每帧多一次解析，纯属浪费）。
  ]]--
  if st.transform and st.transform ~= "none"
     and type(st.transform) == "string"
     and st.transform:find("%%") then
    st._transform = style.parseTransform(st.transform, box.w, box.h, fs)
  end

  return box
end

--[[ 计算整棵树的布局。

     ⚠️ canvasW/H 这里是【逻辑设计尺寸】（如 1600x900），
        不是真实画布。多屏幕比例的适配缩放由渲染层施加，
        布局全程在设计坐标系里算 —— 否则会被缩放两次。 ]]--
function L.compute(root, canvasW, canvasH)
  canvasW = canvasW or 1600
  canvasH = canvasH or 900

  -- ★ 视口单位（vw/vh/vmin/vmax）按设计尺寸换算
  L.setViewportBase(canvasW, canvasH)

  --[[ 从 root 的每个子节点开始（root 自身当作画布）

       ★ 根级子节点也要走【上一元素底边 + 折叠后的间距】这套规则，
         否则直接挂在画布下的元素会丢掉外边距（与嵌套时行为不一致，
         实测：margin-bottom:30px / margin-top:10px 的两个根级元素
         间距变成 30 而不是 50）。 ]]--
  local cy = 0
  local prevMarginBottom = 0
  local prevBottom = 0

  for i = 1, #root.children do
    local c = root.children[i]
    if c:isElement() and c.style and c.style.display == "none" then
      c.box = { x = 0, y = 0, w = 0, h = 0, hidden = true,
                contentX = 0, contentY = 0, contentW = 0, contentH = 0 }
    else
      local cst = c.style or {}
      local cmar = boxEdges(cst, canvasW, "margin")

      local baseY
      if i > 1 then
        local gap = math.max(prevMarginBottom, cmar.top)
        baseY = prevBottom + gap - cmar.top
      else
        baseY = 0
      end

      layoutNode(c, 0, baseY, canvasW, canvasH, canvasW, canvasH)

      -- ★ auto margin 的水平位置已在 layoutNode 内处理，这里不再叠加
      if c.box and not c.box.isAbs then
        prevBottom = c.box.y + c.box.h
        prevMarginBottom = cmar.bottom
        cy = prevBottom
      end
    end
  end

  return root
end

--=============================================================================
-- 调试
--=============================================================================

function L.dump(root, maxDepth)
  maxDepth = maxDepth or 20
  local lines = {}
  dom.walk(root, function(n, d)
    if d > maxDepth or not n.box then return end
    local b = n.box
    local pad = string.rep("  ", d)
    local label = n:isText() and ('"' .. (n.text or ""):sub(1, 12) .. '"') or ("<" .. (n.tag or "?") .. ">")
    lines[#lines + 1] = string.format("%s%-14s x=%.1f y=%.1f w=%.1f h=%.1f",
        pad, label, b.x, b.y, b.w, b.h)
  end)
  return table.concat(lines, "\n")
end

L.intrinsicWidth = intrinsicWidth
L.intrinsicHeight = intrinsicHeight

return L
