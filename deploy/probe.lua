--[[============================================================================
  probe.lua  ——  ★ 唯一探针（所有真机验证都写在这里）

  ══════════════════════════════════════════════════════════════════════════
  用法：改下面的 ACTIVE 变量，选一个测试模块，挂到客户端控件上跑。
        不再新增文件 —— 新验证就往对应模块里加，或新增一个 MODULES 条目。
  ══════════════════════════════════════════════════════════════════════════

  模块清单：

    "key"     ★ 键盘事件          —— 跳跃键能否捕获（做小恐龙游戏的前提）
                                    Down/Up 成对？哪个控件能收到？

  ══════════════════════════════════════════════════════════════════════════
  ⚠️ 已移除的模块（text / mask / glyph / clip / mount）
  ══════════════════════════════════════════════════════════════════════════

    这 5 个模块曾用于产出 R15~R19 的真机结论，2026-10-07 精简时移除。
    它们的**结论、设计意图与重建要点**已归档到：

        docs/探针模块归档.md

    ★ 需要复验某条历史结论（如"矩形裁剪可行"、"字形有缝 1.59em"、
      "框高 ≥ 字号 × 1.8"）时，按该文档「重建要点」一节重建模块。
    ★ 若 main.lua 又出现"界面空白且无日志"，**优先重建 `mount` 模块**
      （它是唯一排障型模块，只读回环境事实，不做实验）。

  ══════════════════════════════════════════════════════════════════════════
  历史结论索引（真机实测，详见 docs/引擎能力与限制.md）
  ══════════════════════════════════════════════════════════════════════════

    R15  30 个几何字符全部渲染正常；■ 连排有 10px 缝（advance 1.59em）
         纯色块 bgColor 完全无缝（478px 单区间）
    R16  遮罩形状 = 图片 alpha，不限圆形
         SetImage(imageSource, imageId) 可运行时换图
         枚举真名 Enum.ImageSource.StaticReference（非文档写法）
         圆角 6 字段写入全部失败 -> border-radius 不可行
    R17  矩形图当遮罩 => overflow:hidden 可实现
         遮罩等比适配，圆形图在 2:1 父里仍是正圆
    R18  裁剪容器能装文字（11/11）
         图片控件自身无 text 字段，但子控件可以有
    R20  ★ 键盘事件可用（2026-10-08，模块 key）
         Enum.KeyEventType 存在且 pairs() 可遍历 164 项
         （★ 与 R16 的 Enum.ImageSource 相反 —— 同为 Enum 行为却不同）
         18 个候选枚举名全部命中（文档这次是对的）
         AddKeyEventListener 在 textbox/root 上都有，绑定 54/54 成功
         KeyboardJumpKeyDown/Up 均收到，Down/Up 可成对判定
         ★★ 同一事件会被【每个绑定它的控件】各收一遍
            -> 一个按键只能绑一个挂载点，否则按一次跳 3 次
         ⚠️ 按键回调的 data.type 读回为空（取值方式与光标事件不同）

    ⚠️ R15~R18 的复现模块已移除，见上面「已移除的模块」。
       结论本身仍有效（来自真机实测），只是当前无现成复现手段。

  ══════════════════════════════════════════════════════════════════════════
  硬性约束（真机实测，写探针时必须遵守）
  ══════════════════════════════════════════════════════════════════════════

    · 新控件 active 默认 false —— 不 SetActive(true) 则完全不可见
    · fontSize 必须整数（浮点写入失败）
    · 字段按类型封死：image 无 text/bgColor；container/button 无 bgColor
    · Enum 顶层 pairs() 为空（元表），但 Enum.Xxx 可直接索引
    · game.Tween 是 3 参数：Tween(obj, {field=val}, 时长)
    · 截图像素 = 画布单位 × 1.6（2560 屏 / 1600 画布）
    · 真机读 .gil，不是文件夹 —— 新增文件要在编辑器导入
=============================================================================]]

--=============================================================================
-- ★★ 选择要跑的模块（改这里）
--=============================================================================

local ACTIVE = "key"

--=============================================================================
-- 通用配置
--=============================================================================

local PREFABS = {
  container = 1073741933,
  textbox   = 1073741934,
  button    = 1073741935,
  image     = 1073741938,
}

local ROOT_NAME = "Root"
local TAG = "[PROBE]"

--[[ 形状图 ID（编辑器里配好的预置资源）。

     ⚠️ 当前 key 模块用不到它 —— 保留是因为重建 mask/glyph 模块
        或写新页面时需要（见 docs/探针模块归档.md）。
        参考：100001 方 / 100002 圆 / 100003 三角
              100004 四角星 / 100005 五角星 / 100006 圆环
  ]]--
local SHAPES = {
  SQUARE   = 100001,
  CIRCLE   = 100002,
  TRIANGLE = 100003,
  STAR4    = 100004,
  STAR5    = 100005,
  RING     = 100006,
}

--=============================================================================
-- 通用工具
--=============================================================================

local function log(fmt, ...) print(string.format(fmt, ...)) end

local function hr(title)
  log("------------------------------------------------------------")
  if title then log(title) end
  log("------------------------------------------------------------")
end

local function warn(...)
  local n = select('#', ...)
  local t = {}
  for i = 1, n do t[i] = tostring((select(i, ...))) end
  local m = TAG .. "[warn] " .. table.concat(t, " ")
  if type(printerr) == "function" then pcall(printerr, m) else print(m) end
end

local function safeCall(fn)
  local ok, v = pcall(fn)
  return ok and v or nil
end

-- ★ 所有探针模块挂在这个表上（M.key / 将来 M.xxx）
local M = {}

--[[ 收集当前页面上【指定 class】的控件状态，供各模块的 report() 使用。

     用途：探针必须【读回实际值】（真机坐标 / 字段），
           而不是打印"我打算设什么" —— 后者误导过好几轮。
  ]]--
local function collect(ui, classSet)
  local dom = require('webui').dom
  local items = {}
  if not (dom and type(dom.walk) == "function" and ui.doc) then return items end

  pcall(function()
    dom.walk(ui.doc, function(n)
      if not n:isElement() then return end
      local cls = (n.attrs and n.attrs.class) or ""
      local hit = false
      for c in cls:gmatch("%S+") do
        if classSet[c] then hit = true break end
      end
      if not hit then return end

      local e = ui.rendered.live[n]
      if not e then return end
      local b = n.box
      local c = e.control
      items[#items + 1] = {
        cls = cls,
        pid = (n.parent and n.parent.id) or (n.parent and n.parent.tag) or "?",
        text = safeCall(function() return c.text end),
        fs = safeCall(function() return c.fontSize end),
        bx = b and b.x or -1, by = b and b.y or -1,
        bw = b and b.w or -1, bh = b and b.h or -1,
        kind = e.kind,
      }
    end)
  end)

  -- ★ pairs 顺序未定义 -> 显式排序，保证日志稳定
  table.sort(items, function(a, b)
    if a.pid ~= b.pid then return a.pid < b.pid end
    if a.cls ~= b.cls then return a.cls < b.cls end
    return (a.text or "") < (b.text or "")
  end)
  return items
end

--=============================================================================
-- 模块：键盘事件（★ 做「小恐龙跳跃」类游戏的前提）
--
--   ══════════════════════════════════════════════════════════════════════
--   为什么必须专门验一次：
--
--     库的 webui_event.lua 只映射了 8 种【光标】事件，全库 grep
--     AddKeyEventListener = 0 次 —— 键盘能力【从未被本项目的代码验证过】。
--     docs/引擎能力与限制.md §5.2 只留了一句"容器节点上可用，实测
--     45~54 次捕获"，没有实现、没有测试。
--
--     而官方文档 docs/client_control_api.md 第 762 行写着
--     AddKeyEventListener(eventType, callback)，Enum.KeyEventType 共 164 项，
--     含 KeyboardJumpKeyDown/Up。按本项目铁律：
--       「下'做不到'的结论前，先确认真的试过」
--     所以先探针，再谈实现。
--
--   ══════════════════════════════════════════════════════════════════════
--   ★ 本模块不需要做任何动作 —— 它是【纯监听】的。
--
--     屏幕上会出现 3 个色块 + 一段提示，然后请你【按键】：
--        空格 / ↑ / ↓ / F 等，随便按几下，每个键按 3 次以上。
--     探针把每次捕获打印到日志，并做 3 组对照统计。
--
--   ══════════════════════════════════════════════════════════════════════
--   3 组对照（一次把关键问题全问完）：
--
--     A. 跳跃专用键    KeyboardJumpKeyDown/Up   —— 语义键，游戏最该用的
--     B. 移动键        MoveLeft/Right/Fwd/Back —— 备用方案
--     C. 奇匠按键 1~4  CraftspersonKey1~4Down   —— 通用槽位，最可能拿到
--
--   ══════════════════════════════════════════════════════════════════════
--   判读（看日志末尾的【判读表】）：
--
--     某组 Down 有数、Up 也有数   -> ✅ 该键可用，且能做成对判定
--     只有 Down 有数、Up 为 0     -> ⚠️ 只能用 Down 触发一次性跳跃
--     三组全 0                    -> ❌ 容器收不到按键，改用「光标点击」
--                                    兜底（库的 onclick 已真机验证可用）
--     ★ jumpDown 有数、jumpUp 为 0 -> 跳跃按下即触发，反而更好写
--        （省掉"必须松手才能再跳"的状态机）
--
--   ══════════════════════════════════════════════════════════════════════
--   ⚠️ 两个已知陷阱（写探针时必须规避）：
--
--     1. 官方文档第 1317 行："按键事件被 Lua 回调标记已处理后，
--        同容器内其他按键不再响应本次事件"。
--        => 回调里【绝不能返回 true】。本模块一律 return false。
--
--     2. 回调必须返回 boolean。返回 nil 有些实现会当成"已处理"。
--=============================================================================

M.key = {}

--[[ ★ 候选按键表。
     key   = 日志里的短名
     name  = Enum.KeyEventType 的成员名（★ 用 pcall 显式取，禁止照文档猜）
     grp   = 分组（A 跳跃 / B 移动 / C 奇匠）
]]--
M.key.CANDIDATES = {
  { key = "jumpDown",  name = "KeyboardJumpKeyDown",          grp = "A" },
  { key = "jumpUp",    name = "KeyboardJumpKeyUp",            grp = "A" },
  { key = "leftDown",  name = "KeyboardMoveLeftKeyDown",      grp = "B" },
  { key = "leftUp",    name = "KeyboardMoveLeftKeyUp",        grp = "B" },
  { key = "rightDown", name = "KeyboardMoveRightKeyDown",     grp = "B" },
  { key = "rightUp",   name = "KeyboardMoveRightKeyUp",       grp = "B" },
  { key = "fwdDown",   name = "KeyboardMoveForwardKeyDown",   grp = "B" },
  { key = "fwdUp",     name = "KeyboardMoveForwardKeyUp",     grp = "B" },
  { key = "backDown",  name = "KeyboardMoveBackwardKeyDown",  grp = "B" },
  { key = "backUp",    name = "KeyboardMoveBackwardKeyUp",    grp = "B" },
  { key = "c1Down",    name = "KeyboardCraftspersonKey1Down", grp = "C" },
  { key = "c1Up",      name = "KeyboardCraftspersonKey1Up",   grp = "C" },
  { key = "c2Down",    name = "KeyboardCraftspersonKey2Down", grp = "C" },
  { key = "c2Up",      name = "KeyboardCraftspersonKey2Up",   grp = "C" },
  { key = "c3Down",    name = "KeyboardCraftspersonKey3Down", grp = "C" },
  { key = "c3Up",      name = "KeyboardCraftspersonKey3Up",   grp = "C" },
  { key = "c4Down",    name = "KeyboardCraftspersonKey4Down", grp = "C" },
  { key = "c4Up",      name = "KeyboardCraftspersonKey4Up",   grp = "C" },
}

M.key.CSS = [[
<style>
  .stage { width: 1600px; height: 900px; background-color: #0e1016; }

  .hdr { width: 1400px; height: 48px; font-size: 24px; color: #7fd1ff;
         margin-left: 100px; margin-top: 40px; }
  .sub { width: 1400px; height: 36px; font-size: 16px; color: #c8cfe0;
         margin-left: 100px; margin-top: 8px; }

  /* 3 个对照组标题 —— 用色块标出，便于在画面上确认探针跑起来了 */
  .grp  { width: 420px; height: 40px; font-size: 18px; color: #ffffff;
          margin-left: 100px; margin-top: 24px; }
  .band { width: 420px; height: 10px; margin-left: 100px; margin-top: 4px; }
  .a { background-color: #4ad07a; }   /* A 组 绿 */
  .b { background-color: #7fd1ff; }   /* B 组 蓝 */
  .c { background-color: #ffcc44; }   /* C 组 黄 */

  .tip  { width: 1400px; height: 40px; font-size: 18px; color: #ff9a4a;
          margin-left: 100px; margin-top: 30px; }
  .tail { width: 1400px; height: 36px; font-size: 16px; color: #8a93a8;
          margin-left: 100px; margin-top: 10px; }
</style>
]]

function M.key.build()
  return [[
<div class="stage">
  <div class="hdr" id="k-hdr">键盘事件探针 · 等待按键</div>
  <div class="sub" id="k-sub">请按 空格 / ↑ / ↓ / F 等，每个键按 3 次以上</div>

  <div class="grp" id="k-gA">A 组 · 跳跃键 KeyboardJumpKey</div>
  <div class="band a" id="k-bA"></div>

  <div class="grp" id="k-gB">B 组 · 移动键 KeyboardMove*Key</div>
  <div class="band b" id="k-bB"></div>

  <div class="grp" id="k-gC">C 组 · 奇匠按键 CraftspersonKey1~4</div>
  <div class="band c" id="k-bC"></div>

  <div class="tip" id="k-tip">★ 本探针只监听，不做任何动作 —— 结果全部看日志</div>
  <div class="tail" id="k-tail">判读：Down 有数=能收到；Up 也有数=能做按下/抬起成对判定</div>
</div>
]]
end

M.key.classes = { hdr = true, sub = true, grp = true, band = true,
                  tip = true, tail = true }

--[[ ★ 核心：绑按键监听 + 统计。

     探针是【裸调 webui.new】，拿不到 webui.mount 的 app 句柄，
     所以这里直接对【引擎控件】AddKeyEventListener —— 反正要验的
     就是引擎这一层的能力，绕开库反而更干净。

     父控件候选顺序：control（视觉层）→ hot（按钮覆盖层）→ root。
     哪个收到事件就说明【该把监听挂在哪】—— 这本身就是结论的一部分。
]]--
function M.key.after(ui)
  log("")
  log("============================================================")
  log("  键盘事件诊断：AddKeyEventListener 到底能不能用")
  log("============================================================")

  --===========================================================================
  -- [1] Enum.KeyEventType 是否可索引（★ 真名不许猜，逐个读回）
  --===========================================================================
  log("")
  log("[1] Enum.KeyEventType 成员实测（pcall 显式取，不照文档猜）")
  local KET = safeCall(function() return Enum.KeyEventType end)
  log(string.format("    Enum.KeyEventType = %s   type = %s",
      tostring(KET), tostring(type(KET))))
  if KET == nil then
    log("    ★ Enum.KeyEventType 为 nil —— 键盘事件这条路走不通，")
    log("      请直接用「光标点击」兜底（库的 onclick 已真机验证）。")
    log("")
    log("============================================================")
    return
  end

  local resolved = {}
  local missing = 0
  for _, c in ipairs(M.key.CANDIDATES) do
    local v = safeCall(function() return KET[c.name] end)
    resolved[c.key] = v
    if v == nil then
      missing = missing + 1
      log(string.format("    %-10s %-32s -> nil  ★ 该成员不存在", c.key, c.name))
    else
      log(string.format("    %-10s %-32s -> %s", c.key, c.name, tostring(v)))
    end
  end
  log(string.format("    ★ 命中 %d / %d，缺失 %d",
      #M.key.CANDIDATES - missing, #M.key.CANDIDATES, missing))
  if missing > 0 then
    log("    ★ 有缺失说明【枚举名与文档不一致】（R16 的教训），")
    log("      缺失项不能在代码里硬写，要按命中项降级。")
  end

  -- ★ 顺便列出真实枚举项，避免下次再猜
  log("")
  log("    [1b] 尝试遍历 Enum.KeyEventType 找含 Jump 的项")
  local cnt, jump = 0, 0
  pcall(function()
    for k in pairs(KET) do
      cnt = cnt + 1
      if tostring(k):find("Jump") then
        jump = jump + 1
        if jump <= 6 then log("         " .. tostring(k)) end
      end
    end
  end)
  log(string.format("        pairs() 遍历到 %d 项，含 Jump 的 %d 项", cnt, jump))
  if cnt == 0 then
    log("        （★ pairs 为 0 是正常的 —— Enum 用了元表，")
    log("          见引擎能力与限制.md §4.3.3，只能显式索引）")
  end

  --===========================================================================
  -- [2] 找父控件，试挂监听
  --===========================================================================
  log("")
  log("[2] 挂载点候选")

  local targets = {}
  -- 取一个活的 live 条目，拿它的 control / hot
  for node, entry in pairs(ui.rendered.live or {}) do
    if entry.control then
      targets[#targets + 1] = { tag = "control(" .. tostring(entry.kind) .. ")", c = entry.control }
    end
    if entry.hot then
      targets[#targets + 1] = { tag = "hot(button 覆盖层)", c = entry.hot }
    end
    if #targets >= 2 then break end
  end
  targets[#targets + 1] = { tag = "root(根控件)", c = ui.rootControl }

  local stats = {}   -- stats[key] = { n=收到次数, grp=组, target=挂在哪 }
  for _, cd in ipairs(M.key.CANDIDATES) do
    stats[cd.key] = { n = 0, grp = cd.grp, target = nil, name = cd.name }
  end

  local boundOK, boundFail, noMethod = 0, 0, 0

  for _, t in ipairs(targets) do
    local c = t.c
    local has = safeCall(function() return type(c.AddKeyEventListener) end)
    log(string.format("    %-24s AddKeyEventListener = %s", t.tag, tostring(has)))

    if has ~= "function" then
      noMethod = noMethod + 1
    else
      for _, cd in ipairs(M.key.CANDIDATES) do
        local ev = resolved[cd.key]
        if ev ~= nil then
          local ok = pcall(function()
            c:AddKeyEventListener(ev, function(data)
              -- ★★ 绝不返回 true —— 否则会吞掉同容器内其他按键
              --    （官方文档第 1317 行）
              local st = stats[cd.key]
              st.n = st.n + 1
              if st.target == nil then st.target = t.tag end

              -- 前 3 次逐条打印，便于确认参数结构
              if st.n <= 3 then
                local extra = ""
                if data ~= nil then
                  extra = string.format(" data.type=%s",
                      tostring(safeCall(function() return data.type end)))
                end
                log(string.format("      ★[捕获] %-10s %s 第%d次%s",
                    cd.key, t.tag, st.n, extra))
              end
              return false
            end)
          end)
          if ok then boundOK = boundOK + 1 else boundFail = boundFail + 1 end
        end
      end
    end
  end

  log("")
  log(string.format("    绑定成功 %d 次 / 失败 %d 次 / 无该方法的控件 %d 个",
      boundOK, boundFail, noMethod))
  if noMethod == #targets then
    log("    ★★ 所有候选控件都没有 AddKeyEventListener ——")
    log("       键盘这条路在本版本不可用，请走「光标点击」兜底。")
  end

  --===========================================================================
  -- [3] 提示用户按键
  --===========================================================================
  log("")
  log("============================================================")
  log("  ★★ 现在请按键 ★★")
  log("============================================================")
  log("  请在游戏里按：空格 / ↑ / ↓ / F / E / Q，每个键按 3 次以上")
  log("  然后回来读下方【判读表】（或重跑一次本模块看统计）。")
  log("")
  log("  ⚠️ 本探针是【只监听】的，屏幕上不会有任何变化 ——")
  log("     所有结果都在日志里。按键后日志会多出 [捕获] 行。")
  log("")
  M.key._stats = stats
  M.key._resolved = resolved
  M.key._targets = targets

  -- 立刻先打一版判读表（此刻多半还是 0，供按键后对比）
  M.key.printVerdict()
end

--[[ 打印判读表。按键期间会被 report() 再调一次，用于看最新统计。]]--
function M.key.printVerdict()
  local stats = M.key._stats
  if not stats then return end

  hr("【判读表】按键统计")
  log(string.format("  %-10s %-24s %-6s %-8s %s",
      "短名", "枚举成员", "组", "收到次数", "挂在哪个控件"))

  local order = { "jumpDown", "jumpUp",
                  "leftDown", "leftUp", "rightDown", "rightUp",
                  "fwdDown", "fwdUp", "backDown", "backUp",
                  "c1Down", "c1Up", "c2Down", "c2Up",
                  "c3Down", "c3Up", "c4Down", "c4Up" }
  local grpSum = { A = 0, B = 0, C = 0 }
  local total = 0
  for _, k in ipairs(order) do
    local st = stats[k]
    if st then
      grpSum[st.grp] = grpSum[st.grp] + st.n
      total = total + st.n
      log(string.format("  %-10s %-24s %-6s %-8d %s",
          k, st.name, st.grp, st.n, tostring(st.target or "-")))
    end
  end
  log("")
  log(string.format("  分组合计： A(跳跃)=%d   B(移动)=%d   C(奇匠)=%d   总计=%d",
      grpSum.A, grpSum.B, grpSum.C, total))

  hr("【结论】")
  if total == 0 then
    log("  还没有捕获到任何按键。")
    log("  · 若你【确实按了】-> 键盘事件在本版本拿不到，")
    log("    改用「光标点击」兜底（库的 onclick 已真机验证可用）。")
    log("  · 若你【还没按】-> 按几下再重跑本模块，或看日志末尾统计。")
  else
    local jd = stats.jumpDown and stats.jumpDown.n or 0
    local ju = stats.jumpUp and stats.jumpUp.n or 0
    if jd > 0 and ju > 0 then
      log("  ✅ 跳跃键 Down/Up 都收到了 —— 可做成对判定（推荐）。")
    elseif jd > 0 and ju == 0 then
      log("  ⚠️ 只有 jumpDown 有数 —— 只能按下触发一次性跳跃。")
      log("     ★ 这对小恐龙反而够用（按下即跳，省掉松手状态机）。")
    elseif grpSum.C > 0 then
      log("  ⚠️ 跳跃/移动键拿不到，但【奇匠按键】能收到 ——")
      log("     改为绑定 CraftspersonKey1Down 当跳跃键即可。")
    else
      log("  ⚠️ 收到了按键但不在候选表里 —— 看上面 [捕获] 行确认是哪个。")
    end

    -- 挂载点结论
    local seenT = {}
    for _, k in ipairs(order) do
      local st = stats[k]
      if st and st.target and not seenT[st.target] then
        seenT[st.target] = true
        log(string.format("  · 事件来自 %s", st.target))
      end
    end
    log("  ★ 记下这个挂载点：以后实现键盘绑定时就挂它。")
  end
  log("")
end

M.key.report = function(ui, items)
  log("")
  log("【屏幕元素】")
  log(string.format("  %-6s %-28s %-22s %s", "cls", "父", "box(x,y,w,h)", "kind"))
  for _, it in ipairs(items) do
    log(string.format("  %-6s %-28s (%4.0f,%4.0f,%4.0f,%4.0f) %s",
        it.cls, tostring(it.pid), it.bx, it.by, it.bw, it.bh, tostring(it.kind)))
  end
  log(string.format("  共 %d 个控件", #items))
  -- 再打一版统计（若之前已按过键，这里能看到数）
  M.key.printVerdict()
end

--=============================================================================
-- 主流程
--=============================================================================

--[[ ★ 模块注册表。新增模块就在这加一行，并把 ACTIVE 改成模块名。

     ⚠️ 已移除：text / mask / glyph / clip / mount
        —— 归档在 docs/探针模块归档.md，需要时按那里重建。
  ]]--
local MODULES = { key = M.key }

local root, ui, bound, retryCount = nil, nil, false, 0

local function runModule(name)
  local mod = MODULES[name]
  if not mod then
    warn("未知模块: " .. tostring(name))
    return false
  end

  log("")
  log("============================================================")
  log("  探针模块: " .. name)
  log("============================================================")

  local ok, err = pcall(function() ui:render(mod.build()) end)
  if not ok then
    warn("渲染失败: " .. tostring(err))
    return false
  end

  if mod.after then
    local ok2, err2 = pcall(mod.after, ui)
    if not ok2 then warn("after() 异常: " .. tostring(err2)) end
  end

  local items = collect(ui, mod.classes or {})
  if mod.report then pcall(mod.report, ui, items) end
  return true
end

local function boot()
  root = game.FindClientUIRoot(ROOT_NAME)
  if not root then return false end

  ui = require('webui').new({
    root = root,
    prefabs = PREFABS,
    handlers = {},
  })

  log("")
  log("============================================================")
  log("  probe.lua   模块 = " .. tostring(ACTIVE))
  log("  画布: " .. tostring(select(1, game.GetUICanvasSize()))
      .. " x " .. tostring(select(2, game.GetUICanvasSize())))
  log("============================================================")

  -- ★ 当前只有 key 一个模块，故无 "all" 分支；
  --   将来模块多了可恢复：if ACTIVE == "all" then for ... runModule(name) end
  runModule(ACTIVE)

  return true
end

function OnInit() end

function OnStart()
  log(TAG .. " OnStart")
  if boot() then bound = true; return end
  log(TAG .. " 未找到 " .. ROOT_NAME .. "，重试")
  script:EnableUpdate(true)
end

function OnUpdate(dt)
  if bound then return end
  if boot() then bound = true; script:EnableUpdate(false); return end
  retryCount = retryCount + 1
  if retryCount >= 120 then
    warn("等待 " .. ROOT_NAME .. " 超时")
    script:EnableUpdate(false)
  end
end

function OnDestroy() end
