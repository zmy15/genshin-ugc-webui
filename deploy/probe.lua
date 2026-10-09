--[[============================================================================
  probe.lua  ——  ★ 唯一探针（所有真机验证都写在这里）

  ══════════════════════════════════════════════════════════════════════════
  用法：改下面的 ACTIVE 变量，选一个测试模块，挂到客户端控件上跑。
        不再新增文件 —— 新验证就往对应模块里加，或新增一个 MODULES 条目。
  ══════════════════════════════════════════════════════════════════════════

  模块清单：

    "key"     ★ 键盘事件          —— 跳跃键能否捕获（做小恐龙游戏的前提）
                                    Down/Up 成对？哪个控件能收到？
    "perf"    ★ 逐帧写入上限      —— 用图片拼恐龙(34控件)真机扛得住吗？
                                    测每帧能写多少次字段 / 掉帧 / 显存
    "align"   ★ 文字居中/坐标系   —— 弹窗里的文字为什么不居中？
                                    A 直接放 / B 嵌容器 / C 显式 width /
                                    D 嵌两层 / E 按钮尺寸，五组对照
    "fit"     ★★ 多屏幕比例适配   —— 非 16:9 屏幕上内容没铺满？
                                    读回真实画布尺寸 + 算 k/留边 +
                                    反变换自检（16:10 / 4:3 / 21:9）

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
    R22  ★★ 逐帧写入成本模型（2026-10-08，模块 perf，两轮）

         第一轮（含等待计时）: 4 档全 38~45ms —— ★ 探针缺陷，
           量到的是 TweenSequence 的 1/30 间隔，不是性能。
           教训：计时必须【把等待和干活分开】。

         第二轮（纯工作计时，干净数字）:
           档位   控件  写入/帧  纯工作ms
           L1      10      20    13.03
           L2      40      80    15.32
           L3      80     160    19.01
           L4     160     320    26.38

         ★ 线性拟合（误差 < 0.21ms，非常可信）:
             每帧耗时 = 11.92ms + 0.0449ms x 写入次数
           - 固定开销 11.92 ms/帧  （style.apply + layout + 控件遍历）
           - 每次写入 44.9 微秒

         ★ 结论:
           1. 写入【极便宜】（45 微秒/次）—— 34 个矩形全量更新
              ≈ 1.5ms，性能上毫无压力
           2. 真正的开销是【固定 11.9ms】，与 DOM 节点数正相关
              -> 优化方向是【减节点】，不是"少写字段"
           3. 30fps 预算 33.3ms：L4(320 写入) 实测 26.38ms，仍在预算内
           4. ⚠️ 固定开销 11.9ms 已占预算的 36%，
              真机 TweenSequence 调度还有 5~9ms 抖动（见第一轮）

    R15~R18 的复现模块已移除，见上面「已移除的模块」。
       结论本身仍有效（来自真机实测），只是当前无现成复现手段。

    R23  ★★★ 水平对齐枚举真名（2026-10-09，模块 align，真机实测）—— 已定位并修复

         起因：demo_dino 结算窗口的文字永远贴框左边。

         第一次真机（六组对照）：框宽/位置/控件类型全部正确，
         但 horizontalAlignment 六组【全部停在默认 Left】。

         第二次真机（枚举形态实验）—— 根因：

           Enum.TextHorizontalAlignment        = 子表（可索引）
           Enum.TextHorizontalAlignment.Middle = 可用 ✅   ← 真名
           Enum.TextHorizontalAlignmentMiddle  = nil      ❌ ← 文档写法

         ★ 所以 text-align:center 从来没生效过：库写的是文档的扁平名
           （nil），而那次写入被 pcall 包着 -> 失败【静默吞掉】。

         ★ 修复：webui_render.lua 新增 resolveAlign()，按
           「子表形式 -> 扁平形式」取，取不到就 util.warn（不再静默）。
           两个调用点（普通文本框 / 裁剪容器文字子控件）共用。

         ★★ 修复已真机验证（同日 02:56 第三轮）：
            五组对照（B/C/D/E + 长文本）ha 全部读回 Middle，
            截图确认文字全部居中（含 120x54 的「退出」按钮）。
            ⚠️ al-a1（A 组基线）显示 Left 是【探针自身副作用】——
               枚举实验反复写过它，而还原时又误用了扁平名（也是 nil）。
               已修（改用子表形式还原）。其余五组未被触碰，结论有效。

         ★ 这是本项目第三例「文档枚举名不可用」——
           R16 Enum.ImageSource.StaticReference、
           R23 Enum.TextHorizontalAlignment.Middle。
           凡枚举一律运行时显式取 + 失败告警，禁止照文档写死。

         ★★ 为什么藏了这么久：各测试自己手写 Enum 表且写的是
            【文档扁平形式】-> mock 里可用、测试全绿、真机全错。
            已抽出 tests/enum_kit.lua 按【真机形态】统一构造
            （扁平名故意为 nil），并加 tests/test_align_enum.lua 守着。

         ⚠️ 另修两个探针自身的缺陷（都会产出假结论）：
            ① 判定写成 ha ~= "Left" 就算通过 -> 真机六组全 Left
               却全打印 ✅，自己发假绿勾。改成正面匹配 Middle。
            ② 枚举实验每条候选前没重置字段 -> 第一条成功后，
               后面"取值=nil、写入=false"也读回 Middle 被判成功，
               一次骗了 7 条。现在每步先重置为 Left。

    R24  ★★ 多屏幕比例适配（2026-10-09，模块 fit）

         起因：非 16:9 屏幕上页面【没铺满】，四周露出游戏画面。

         真机截图逐像素量得（16:10 屏）：
           可见面板区域 = 2151 x 1209 px
           面板宽高比   = 1.7792
           屏幕宽高比   = 1.7778
           ★ 两者几乎相等 -> 不是"拉伸变形"，
             而是【内容尺寸没跟着画布缩放】，四周留空。

         根因（三处，全在库侧）：
           ① util.canvasSize() 首次取值就【永久缓存】——
              换分辨率后布局全错
           ② render 把根控件 sizeDelta 直接写死成 canvasSize()
           ③ parseLength 不认 vw / vh，CSS 尺寸全是绝对值

         ★★ 绝对不能用"拉伸铺满"：像素精灵被非等比压扁，
            8px 格子变 7.3px，§4.5 那条"外扩 1px 盖缝"立刻失效。

         ★ 正确做法 = 等比缩放 + 居中留边（letterbox）：
              k = min(画布宽/设计宽, 画布高/设计高)
              留边 = (画布 - 设计 x k) / 2

           | 屏幕      | k    | 缩放后    | 留边        |
           |-----------|------|----------|-------------|
           | 2560x1440 | 1.60 | 2560x1440| 无          |
           | 2560x1600 | 1.60 | 2560x1440| 上下各 80   |
           | 1920x1440 | 1.20 | 1920x1080| 上下各 180  |
           | 3440x1440 | 1.60 | 2560x1440| 左右各 440  |

         ★ 取【任意倍】而非整数倍：整数倍在 2560x1440 上 k 掉到 1，
           画面缩成居中小窗，代价不可接受。

         ★ 留边必须填色（否则露出草地/天空，像渲染 bug）。
           库用【四条边条】覆盖留边区（矩形环、中间镂空）——
           不用一整块铺满，因为引擎没有可靠置底手段，会盖住内容。

         ★ 光标坐标必须反变换：
             设计坐标 = (画布坐标 - 留边偏移) / k
           不做则缩放下所有点击错位（2560x1600 上垂直差 80px+）。
           事件回调改用 info.lx / info.ly。

         库侧开关：webui.new{ designSize, fit, fitBg }。
         不传 designSize 时行为与旧版完全一致（16:9 无差别）。

         ⏳ 待真机验证：模块 fit 用于在真机上读回画布尺寸、
            算 k/留边、自检反变换。截图判读四边是否贴齐。

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

local ACTIVE = "align"

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

-- ★ 吞掉错误的执行（探针里各处都要用，避免一处失败打断整轮压测）
local function util_probe_try(fn)
  local ok, err = pcall(fn)
  if not ok then warn("执行失败: " .. tostring(err)) end
  return ok
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
-- 模块：逐帧写入上限（★ 决定"用图片拼恐龙"是否可行）
--
--   ══════════════════════════════════════════════════════════════════════
--   为什么测这个：
--
--     原版小恐龙的身体是不规则轮廓。引擎不能导入外部图像，
--     所以只能用【多张/多个矩形图片控件】拼出来：
--
--       44x47 逻辑格 -> 贪心矩形分解 -> 34 个矩形
--       每个矩形 = 1 个 image 控件
--
--     ★ 34 个控件【每帧都要更新坐标】（恐龙要跑、要跳），
--       再加障碍/云/分数 -> 每帧 100+ 次字段写入。
--
--     而现在的 demo 每帧只写 6 次。真机扛不扛得住【完全未知】——
--     这就是本模块要回答的唯一问题。
--
--   ══════════════════════════════════════════════════════════════════════
--   设计：4 档逐级加压，每档跑固定帧数，量三个指标
--
--     档位    控件数   每帧写入      对应场景
--     L1       10       20 次      现状 demo
--     L2       40       80 次      拼一只恐龙
--     L3       80      160 次      恐龙 + 障碍 + 云
--     L4      160      320 次      最坏情况（双倍冗余）
--
--     指标：
--       ① 实际帧间隔（用 os.clock 量）—— 掉帧没有？
--       ② 每档耗时 / 帧
--       ③ 内存或句柄是否异常增长
--
--   ══════════════════════════════════════════════════════════════════════
--   判读（★ 只认真机数字）：
--     L3 每帧仍 < 33ms  -> ✅ 34 控件拼恐龙可行
--     L3 偏慢(33~66ms)   -> ⚠️ 降级：只在姿态切换时更新矩形
--                          （中间帧只移动整只恐龙的父容器，1 次写入）
--     L3 明显卡(>66ms)   -> ❌ 放弃拼接，用少控件方案
--
--   ⚠️ 本地 mock 跑出来的数字【只能验证探针本身没写错】，
--      【不能】当作真机性能结论 —— mock 的字段写入是纯 Lua 表操作，
--      而真机要过引擎的控件系统。必须在真机上跑这一轮。
--
--   ⚠️ 探针会自己起一条 TweenSequence 循环，跑完自动停并打印结果。
--      屏幕上会看到方块在动 —— 那是正常的，代表正在压测。
--=============================================================================

M.perf = {}

M.perf.CSS = [[
<style>
  .stage { width: 1600px; height: 900px; background-color: #f7f7f7;
           overflow: hidden; }
  .scene { width: 1600px; height: 900px; background-color: #f7f7f7; }
  .hdr { position: absolute; left: 40px; top: 20px;
         width: 1000px; height: 40px;
         font-size: 20px; color: #535353;
         background-color: #f7f7f7; text-align: left; }
  .st  { position: absolute; left: 40px; top: 64px;
         width: 1200px; height: 34px;
         font-size: 16px; color: #6a6a6a;
         background-color: #f7f7f7; text-align: left; }

  /* ★ 被压测的"像素块"：全部用方形图 100001，尺寸各异 */
  .px  { position: absolute; left: 0px; top: 0px;
         width: 8px; height: 8px; }
</style>
]]

--[[ ★ 生成"恐龙形状"的矩形表。

     这里用【真实的贪心矩形分解结果】的近似：一个大躯干 + 头 + 腿 + 尾。
     重点不是形状好看，而是【矩形数量与每帧写入量】要真实。
]]--
M.perf.RECTS = {
  -- {x, y, w, h}  —— 以逻辑格为单位（每格 8px）
  { 24,  0, 18, 12},   -- 头
  { 26,  3,  4,  4},   -- 眼（留空效果）
  { 22, 12, 11,  4},   -- 颈
  { 22, 14, 18,  2},   -- 上颚
  {  0, 16,  2,  6},   -- 尾尖
  {  2, 21,  2,  4},   -- 尾
  {  4, 22,  8,  7},   -- 臀
  { 12, 25, 15,  4},   -- 躯干
  { 13, 29, 13,  2},   -- 腹
  { 16, 31,  8,  4},   -- 后腿
  { 18, 36, 12,  2},   -- 脚
  {  6, 33, 10,  2},   -- 前腿
  { 11, 39,  4,  2},   -- 爪
  { 11, 41,  4,  2},
  { 27, 38,  4,  2},
  { 27, 41,  4,  2},
}

M.perf.build = function()
  local out = { M.perf.CSS, '<div class="stage"><div class="scene">\n' }
  out[#out+1] = '<div class="hdr">逐帧写入上限压测</div>\n'
  out[#out+1] = '<div class="st" id="perf-status">准备中…</div>\n'

  -- 生成 160 个方块（L4 档位用满，其余档位按需隐藏）
  for i = 1, 160 do
    local r = M.perf.RECTS[((i - 1) % #M.perf.RECTS) + 1]
    out[#out+1] = string.format(
      '<div class="px" id="px%d" data-image="1" style="left:%dpx;top:%dpx;width:%dpx;height:%dpx"></div>\n',
      i, r[1]*8, 120 + r[2]*8, r[3]*8, r[4]*8)
  end

  out[#out+1] = '</div></div>\n'
  return table.concat(out)
end

M.perf.classes = { px = true, hdr = true, st = true }

M.perf.after = function(ui)
  log("")
  log("============================================================")
  log("  逐帧写入上限压测：4 档逐级加压")
  log("============================================================")
  log("")
  log("  目的：回答『用 34 个图片控件拼恐龙，每帧更新坐标，")
  log("        真机扛得住吗？』")
  log("  方法：用 os.clock 量每档的实际帧间隔与耗时")
  log("")

  -- 收集方块控件
  local pxNodes = {}
  for i = 1, 160 do
    local node = nil
    require('webui').dom.walk(ui.doc, function(n)
      if not node and n:isElement() and n.id == ("px" .. i) then node = n end
    end)
    pxNodes[i] = node
  end
  local have = 0
  for i = 1, 160 do if pxNodes[i] then have = have + 1 end end
  log(string.format("  已建方块控件: %d / 160", have))

  -- 状态栏节点
  local stNode = nil
  require('webui').dom.walk(ui.doc, function(n)
    if not stNode and n:isElement() and n.id == "perf-status" then stNode = n end
  end)

  --===========================================================================
  -- 档位定义：{控件数, 每帧写入次数, 帧数}
  --===========================================================================
  local LEVELS = {
    { name = "L1 现状demo",   ctrls = 10,  writes = 20,  frames = 120 },
    { name = "L2 拼一只恐龙", ctrls = 40,  writes = 80,  frames = 120 },
    { name = "L3 恐龙+障碍",  ctrls = 80,  writes = 160, frames = 120 },
    { name = "L4 最坏情况",   ctrls = 160, writes = 320, frames = 120 },
  }

  local results = {}

  --[[ ★ 用一条递归 TweenSequence 驱动（真机唯一可靠的逐帧手段）。

       每"帧"里做 `writes` 次 setStyle 写入 —— 用 setStyle 而不是直接
       写控件字段，因为它走的是完整渲染通路（含 diff），
       更接近真实游戏的开销。 ]]
  --[[ ★ li 从 1 开始 —— Lua 表是 1-based。
        从 0 开始会让 LEVELS[li] 恒为 nil，第一帧就"以为跑完了"，
        打印一张【空判读表】。（这个 bug 真出现过，
        tests/test_probe.lua 有断言守着：必须记录到 4 档结果。） ]]--
  local li = 1
  local frameInLevel = 0
  local tStart = 0
  local curWrites = 0

  --[[ ★★ 关键修正（R22 第一轮真机数据暴露的探针缺陷）：

       第一轮我用 [进入档位时记 os.clock，跑完 120 帧再记] 来算速度。
       结果 4 档全是 38~45ms/帧，【与负载完全无关】：
         L1  20 写入 = 42.20 ms
         L4 320 写入 = 45.48 ms   （负载放大 16 倍，耗时只差 7.8%）

       原因：循环里 AppendInterval(1/30) = 33.3ms 是【每帧的等待时间】，
       而 os.clock 量的是【真实经过时间】—— 量到的主要是"等下一帧"，
       不是"干活"。

       ★ 正确做法：把【等待】和【干活】分开计时。
         下面 workTime 只累加"本帧实际执行的工作"耗时，
         不含任何等待 —— 这才是真正要看的数字。
  ]]--
  local workTime = 0        -- 本档累计的纯工作耗时
  local frameWork = 0       -- 本帧的纯工作耗时

  local function finishLevel(elapsed)
    local lv = LEVELS[li]
    local totalMs = (elapsed / lv.frames) * 1000        -- 含等待（旧指标）
    local workMs  = (workTime / lv.frames) * 1000       -- ★ 纯工作
    results[#results+1] = {
      name = lv.name, ctrls = lv.ctrls, writes = lv.writes,
      ms = workMs, totalMs = totalMs, elapsed = elapsed,
    }
    log(string.format(
        "  [%s] %d 控件 x %d 写入/帧 -> 纯工作 %.2f ms/帧（含等待 %.2f ms/帧）",
        lv.name, lv.ctrls, lv.writes, workMs, totalMs))
  end

  local tick
  tick = function()
    local lv = LEVELS[li]
    if not lv then
      -- 全部跑完 -> 打印判读表
      M.perf.printResults(results, stNode)
      return
    end

    if frameInLevel == 0 then
      tStart = os.clock()
      workTime = 0
      -- 进入本档：按档位数量显示/隐藏方块
      for i = 1, 160 do
        local n = pxNodes[i]
        if n then
          if i <= lv.ctrls then n:show() else n:hide() end
        end
      end
      if stNode then
        stNode:setText(string.format("压测中：%s（%d 控件 x %d 写入/帧）",
            lv.name, lv.ctrls, lv.writes))
      end
    end

    -- ★ 开始计"纯工作"耗时（不含任何等待）
    frameWork = os.clock()

    -- ── 本帧的写入负载 ──
    curWrites = 0
    local n = lv.ctrls
    local perCtrl = math.max(1, math.floor(lv.writes / n))
    local phase = frameInLevel * 0.15
    for i = 1, n do
      local node = pxNodes[i]
      if node then
        -- 每个控件写 perCtrl 次（模拟位置/尺寸更新）
        for k = 1, perCtrl do
          if k == 1 then
            node:setStyle("transform", string.format("translateX(%.1fpx)",
                math.sin(phase + i) * 30))
          elseif k == 2 then
            node:setStyle("transform", string.format("translateY(%.1fpx)",
                math.cos(phase + i) * 10))
          else
            node:setStyle("width", string.format("%dpx", 8 + (i % 3)))
          end
          curWrites = curWrites + 1
        end
      end
    end

    -- 渲染（这一步才是真正写进引擎控件）
    util_probe_try(function() ui:flush() end)

    -- ★ 累计本帧纯工作耗时
    workTime = workTime + (os.clock() - frameWork)

    frameInLevel = frameInLevel + 1
    if frameInLevel >= lv.frames then
      finishLevel(os.clock() - tStart)
      li = li + 1
      frameInLevel = 0
    end

    -- 续期
    util_probe_try(function()
      local seq = game.TweenSequence()
      if seq then
        seq:AppendInterval(1.0 / 30)
        seq:AppendCallback(tick)
        seq:Play()
      end
    end)
  end

  -- 起跑（延一帧，让渲染先落地）
  util_probe_try(function()
    local seq = game.TweenSequence()
    if seq then
      seq:AppendInterval(1.0 / 30)
      seq:AppendCallback(tick)
      seq:Play()
    else
      tick()
    end
  end)

  log("  ★ 压测已启动，约 16 秒后打印结果（4 档 x 120 帧）")
  log("    屏幕上会看到方块在动 —— 正常现象")
end

--[[ 打印判读表 ]]--
M.perf.printResults = function(results, stNode)
  hr("【判读表】逐帧写入上限")
  log("  ★ 看【纯工作】列 —— 那才是写入开销；")
  log("     【含等待】列被 TweenSequence 的 1/30 间隔主导，不代表性能。")
  log("")
  log(string.format("  %-18s %-8s %-10s %-12s %-12s %s",
      "档位", "控件数", "写入/帧", "纯工作ms", "含等待ms", "判定"))
  log("  " .. string.rep("-", 82))

  for _, r in ipairs(results) do
    local verdict
    if r.ms < 8 then verdict = "✅ 很轻松"
    elseif r.ms < 16 then verdict = "✅ 够用（>60fps 有余量）"
    elseif r.ms < 33 then verdict = "✅ 可用（>=30fps）"
    elseif r.ms < 66 then verdict = "⚠️ 偏慢"
    else verdict = "❌ 卡" end
    log(string.format("  %-18s %-8d %-10d %-12.2f %-12.2f %s",
        r.name, r.ctrls, r.writes, r.ms, r.totalMs or 0, verdict))
  end

  log("")
  hr("【结论】")
  local l3 = nil
  for _, r in ipairs(results) do
    if r.name:find("L3") then l3 = r end
  end

  if not l3 then
    log("  L3 档未跑完，无法判定。")
  elseif l3.ms < 16 then
    log("  ✅ L3（80 控件 / 160 写入/帧）纯工作 " .. string.format("%.2f", l3.ms)
        .. " ms/帧 —— 远低于 33ms 预算")
    log("     -> 【34 个图片控件拼恐龙】方案可行，每帧全量更新没问题。")
  elseif l3.ms < 33 then
    log("  ✅ L3 纯工作 " .. string.format("%.2f", l3.ms) .. " ms/帧 < 33ms")
    log("     -> 拼恐龙可行，但余量不多，建议配合下面的优化。")
  elseif l3.ms < 66 then
    log("  ⚠️ L3 纯工作 " .. string.format("%.2f", l3.ms) .. " ms/帧")
    log("     -> 拼恐龙可行，但【不能每帧更新全部矩形】。")
    log("     -> 降级方案：只在恐龙姿态切换时更新（约每 6 帧一次），")
    log("        中间帧只更新整只恐龙的偏移（一个父容器一起移动）。")
  else
    log("  ❌ L3 纯工作 " .. string.format("%.2f", l3.ms) .. " ms/帧，太慢。")
    log("     -> 放弃多控件拼接，改用单一色块/少控件方案。")
  end

  --[[ ★ 诚实提示：本模块常在本地 mock 上试跑（test_probe.lua）。
        mock 的字段写入是纯 Lua 表操作，没有引擎开销，
        跑出来必然"很轻松" —— 那不是真机结论。 ]]
  log("")
  log("  ⚠️ 若这些数字来自本地 mock（test_probe.lua），")
  log("     【不构成真机性能结论】—— mock 无引擎开销。")
  log("     方案取舍必须看真机跑出来的数字。")

  log("")
  log("  ★ 别忘了把结论追加到本文件头部的「历史结论索引」（R22）。")
  log("")

  if stNode then
    local msg = "压测完成"
    if l3 then msg = msg .. string.format("：L3 = %.2f ms/帧", l3.ms) end
    stNode:setText(msg)
  end
  log("============================================================")
end

M.perf.report = function(ui, items)
  -- 结果在压测跑完后由 printResults 打印，这里不重复
  log(string.format("  （本模块共 %d 个方块控件）", #items))
end

--[[============================================================================
  模块：文字居中 / 坐标系（align）

  ══════════════════════════════════════════════════════════════════════════
  两组问题：

   【水平】text-align 到底有没有生效？
      （R23 已定位：库用错了枚举名，扁平名在真机上是 nil，
        失败被 pcall 吞掉 -> 从来没生效过。已修并验证。）

   【垂直】vertical-align 到底有没有生效？
      ⚠️ 垂直轴原先【根本没实现】—— webui_style 里只有一个默认值
         "middle"，解析 / 继承 / 写控件三处都没有。
         默认恰好等于引擎默认（垂直居中），所以"看着像对的"，
         但写 top / bottom 完全没效果。已补上，本模块负责取证。

  ══════════════════════════════════════════════════════════════════════════
  ★★ 对照组设计（关键实验必须带对照组 —— docs/引擎能力与限制.md §七）

     A. 直接放在 .stage 下（与已知可用的 .over 同构）—— 基线

     B. 嵌在【绝对定位容器】里（复刻结算窗口结构）
        —— 若 A 居而 B 不居 -> 根因是嵌套

     C. 同 B，但显式写 width 与 text-align（不依赖继承）
        —— 若 B 不居而 C 居 -> 根因是样式继承

     D. 嵌两层（容器 > 容器 > 文字）
        —— 若 C 居而 D 不居 -> 根因与嵌套深度有关

     E. 退出按钮的复刻（宽 120 高 54）
        —— 验证尺寸/坐标系换算

     F. ★ 垂直对齐三连（三个【同尺寸】框，只有 vertical-align 不同）
        top / middle / bottom —— 框高 120 / 字号 20 = 6.0，
        三者文字的 y 位置应有肉眼可见的差别。
        若三者看起来一样 -> 垂直对齐没生效。

  ══════════════════════════════════════════════════════════════════════════
  判读：读回表同时给出 ha 与 va 两列，以及截图上文字的左右/上下留白。
        引擎没有「文字实际 bbox」API，渲染位置只能靠截图量。
=============================================================================]]

M.align = {}

--[[ 各对照组的声明参数。

     ⚠️ 这里的数字必须与 CSS 里【逐字对应】—— 本模块的核心就是
        拿"声明的"与"读回的"对比，两边对不上就白测了。 ]]
M.align.GROUPS = {
  { id = "a", label = "A 直接放 stage",        w = 400, declaredW = 400 },
  { id = "b", label = "B 嵌绝对定位容器",       w = 400, declaredW = 400 },
  { id = "c", label = "C 同 B + 显式 width",    w = 400, declaredW = 400 },
  { id = "d", label = "D 嵌两层",              w = 400, declaredW = 400 },
  { id = "e", label = "E 退出按钮复刻",         w = 120, declaredW = 120 },
}

M.align.CSS = [[
<style>
  .stage { width: 1600px; height: 900px; background-color: #0e1016; }

  .hdr { width: 1500px; height: 40px; font-size: 20px; color: #7fd1ff;
         margin-left: 40px; margin-top: 20px; }
  .sub { width: 1500px; height: 30px; font-size: 15px; color: #c8cfe0;
         margin-left: 40px; margin-top: 6px; }

  /* 每组的标签（左对齐，便于认出是哪一组） */
  .glabel { width: 1500px; height: 26px; font-size: 15px; color: #ffffff;
            margin-left: 40px; margin-top: 10px; }

  /* ---- A 组：直接放 stage 下（与 .over 同构）---- */
  /* 框高 50 >= 字号 20 x 1.9 = 38 ✓ */
  .a-box { position: absolute; left: 40px; top: 150px;
           width: 400px; height: 50px;
           font-size: 20px; color: #ffffff; background-color: #2a3550;
           text-align: center; }

  /* ---- B 组：嵌在绝对定位容器里（复刻结算窗口结构）---- */
  .b-wrap { position: absolute; left: 40px; top: 220px;
            width: 500px; height: 120px; }
  /* ⚠️ 容器不写 background-color：容器没有 bgColor 字段，写了也无效；
        而且它是"裁剪容器不设背景"那条约束的同理 */
  .b-box  { position: absolute; left: 20px; top: 10px;
            width: 400px; height: 50px;
            font-size: 20px; color: #ffffff; background-color: #2a3550;
            text-align: center; }

  /* ---- C 组：同 B，但把 width 与 text-align 都显式写在子元素上 ---- */
  .c-wrap { position: absolute; left: 40px; top: 360px;
            width: 500px; height: 120px; }
  .c-box  { position: absolute; left: 20px; top: 10px;
            width: 400px; height: 50px;
            font-size: 20px; color: #ffffff; background-color: #2a3550;
            text-align: center; }

  /* ---- D 组：嵌两层 ---- */
  .d-wrap1 { position: absolute; left: 40px; top: 500px;
             width: 500px; height: 120px; }
  .d-wrap2 { position: absolute; left: 10px; top: 10px;
             width: 460px; height: 90px; }
  .d-box   { position: absolute; left: 10px; top: 10px;
             width: 400px; height: 50px;
             font-size: 20px; color: #ffffff; background-color: #2a3550;
             text-align: center; }

  /* ---- E 组：退出按钮复刻（demo_dino 里那个）---- */
  .e-box { position: absolute; left: 40px; top: 650px;
           width: 120px; height: 54px;
           font-size: 18px; color: #535353; background-color: #e8e8e8;
           text-align: center; }

  /* ---- F 组：垂直对齐对照（框比字高得多，差别肉眼可见）----
     三个框尺寸完全相同，只有 vertical-align 不同。
     框高 120 / 字号 20 = 6.0 —— 三者的文字 y 位置应有明显差别：
       top    -> 贴框顶
       middle -> 垂直居中（默认）
       bottom -> 贴框底 */
  .fv-top { position: absolute; left: 640px; top: 150px;
            width: 400px; height: 120px;
            font-size: 20px; color: #ffffff; background-color: #2a3550;
            text-align: left; vertical-align: top; }
  .fv-mid { position: absolute; left: 640px; top: 290px;
            width: 400px; height: 120px;
            font-size: 20px; color: #ffffff; background-color: #2a3550;
            text-align: left; vertical-align: middle; }
  .fv-bot { position: absolute; left: 640px; top: 430px;
            width: 400px; height: 120px;
            font-size: 20px; color: #ffffff; background-color: #2a3550;
            text-align: left; vertical-align: bottom; }

  /* 长文本对照组：同样居中，但内容长，便于量左右留白是否相等 */
  .long { position: absolute; left: 40px; top: 730px;
          width: 400px; height: 50px;
          font-size: 20px; color: #ffffff; background-color: #2a3550;
          text-align: center; }

  .tail { width: 1500px; height: 28px; font-size: 15px; color: #ff9a4a;
          margin-left: 40px; margin-top: 10px; }
</style>
]]

function M.align.build()
  -- ★ 必须把 CSS 拼进来：库只从返回的 HTML 里提取 <style>，
  --   单独定义一个 M.align.CSS 常量【不会】被用到（踩过）。
  return M.align.CSS .. [[
<div class="stage">
  <div class="hdr" id="al-hdr">文字居中 / 坐标系探针</div>
  <div class="sub" id="al-sub">请截图，并看日志里的【读回表】—— 每组两个文本：短 / 长</div>

  <!-- A：直接放 stage 下（基线，与已知可用的 .over 同构） -->
  <div class="glabel" id="al-gA">A 直接放 stage（基线）</div>
  <div class="a-box" id="al-a1">居中</div>

  <!-- B：嵌在绝对定位容器里 -->
  <div class="glabel" id="al-gB">B 嵌绝对定位容器（复刻结算窗口）</div>
  <div class="b-wrap" id="al-bw">
    <div class="b-box" id="al-b1">居中</div>
  </div>

  <!-- C：同 B，显式 width + text-align -->
  <div class="glabel" id="al-gC">C 同 B 但显式写 width / text-align</div>
  <div class="c-wrap" id="al-cw">
    <div class="c-box" id="al-c1">居中</div>
  </div>

  <!-- D：嵌两层 -->
  <div class="glabel" id="al-gD">D 嵌两层</div>
  <div class="d-wrap1" id="al-dw1">
    <div class="d-wrap2" id="al-dw2">
      <div class="d-box" id="al-d1">居中</div>
    </div>
  </div>

  <!-- E：退出按钮复刻（验证尺寸是否为声明的 1.6 倍） -->
  <div class="glabel" id="al-gE">E 退出按钮复刻（宽 120 高 54）</div>
  <div class="e-box" id="al-e1">退出</div>

  <!-- F：垂直对齐对照（三个同尺寸框，只有 vertical-align 不同） -->
  <div class="glabel" id="al-gF">F 垂直对齐：top / middle / bottom（框高 120，字号 20）</div>
  <div class="fv-top" id="al-ft">顶部 top</div>
  <div class="fv-mid" id="al-fm">居中 middle</div>
  <div class="fv-bot" id="al-fb">底部 bottom</div>

  <!-- 长文本：同 A，但内容长，便于量左右留白 -->
  <div class="glabel" id="al-gL">长文本对照组（同 A 的样式）</div>
  <div class="long" id="al-l1">1234567890</div>

  <div class="tail" id="al-tail">判读：看日志 ha 字段 与 截图里文字的左右留白</div>
</div>
]]
end

M.align.classes = { hdr = true, sub = true, glabel = true,
                    ["a-box"] = true, ["b-box"] = true, ["c-box"] = true,
                    ["d-box"] = true, ["e-box"] = true, long = true,
                    tail = true }

--[[ ★★★ 枚举形态实验 —— 本模块最关键的一段。

     第一次真机跑的结果：六组对照的 horizontalAlignment 【全部读回 Left】，
     而框宽/位置全部正确（见日志）。也就是说：
       · CSS 的 text-align: center 算出来了（本地已验证）
       · 但写进控件时【没生效】—— 字段停在默认 Left
       · 库的写入是 pcall(...)，失败会被静默吞掉

     最可能的原因：Enum.TextHorizontalAlignmentMiddle 这个名字取不到
     （R16 已经踩过同类：文档写 Enum.ImageSource.ImageSourceStaticReference，
      真名却是 Enum.ImageSource.StaticReference）。

     ★ 本段把【所有可能的取法】逐个试，并【读回实际值】判断哪个成功 ——
       而不是照着文档猜一个就完事（"枚举名禁止照文档猜"是本项目铁律）。

     还顺带打印 Enum 的真实形态（顶层能否 pairs、有哪些子表），
     这些事实下次写别的枚举时能直接用。 ]]--
function M.align.probeEnum(ui)
  hr("[枚举形态实验] 找出 horizontalAlignment 真正认的值")

  -- 取一个被测控件（A 组）
  local dom = require('webui').dom
  local nd = nil
  dom.walk(ui.doc, function(n)
    if n:isElement() and n.attrs and n.attrs.id == "al-a1" then nd = n end
  end)
  local e = nd and ui.rendered.live[nd]
  local ctrl = e and e.control
  if not ctrl then
    log("  ❌ 拿不到被测控件，跳过本实验")
    return
  end

  --===========================================================================
  log("")
  log("[1] Enum 的真实形态")
  --===========================================================================
  log(string.format("    type(Enum) = %s", tostring(type(Enum))))
  local n = 0
  safeCall(function()
    for k, v in pairs(Enum) do
      n = n + 1
      if n <= 40 then
        log(string.format("      Enum.%-38s = %s", tostring(k), tostring(v)))
      end
    end
  end)
  log(string.format("    pairs(Enum) 共 %d 项%s", n,
      n == 0 and "（★ 顶层不可遍历 —— 与 R16 结论一致，只能显式索引）" or ""))

  -- 几个可能的子表名，逐个试
  local SUBNAMES = {
    "TextHorizontalAlignment", "HorizontalAlignment",
    "TextAlignment", "Alignment",
  }
  log("")
  log("    子表探测（pcall 显式取）：")
  for _, sn in ipairs(SUBNAMES) do
    local sub = safeCall(function() return Enum[sn] end)
    log(string.format("      Enum.%-28s = %s", sn, tostring(sub)))
    if type(sub) == "table" then
      local cnt = 0
      safeCall(function()
        for k, v in pairs(sub) do
          cnt = cnt + 1
          if cnt <= 12 then
            log(string.format("          .%-30s = %s", tostring(k), tostring(v)))
          end
        end
      end)
      log(string.format("          （共 %d 项）", cnt))
    end
  end

  --===========================================================================
  log("")
  log("[2] 逐个尝试写入，读回看哪个生效")
  --===========================================================================
  --[[ ⚠️ 必须在【一个控件】上依次试，每次试完读回。
       如果一次试多个，无法区分是哪个生效的。 ]]

  --[[ ★★ 逐个尝试写入，读回看哪个生效。

       ⚠️⚠️ 每次尝试【之前必须把字段重置成一个"已知不等于目标"的值】，
          否则会出现假阳性：上一条把值写成 Middle 之后，
          后面即使"取值=nil、写入=false"，读回【仍然是 Middle】，
          被判成"✅ 生效"—— 第一次真机跑就这么骗了我 7 条。

       ★ 重置值也要挑：用 Left（不是 Middle、也不是 nil）。
         真机上 Left 能取到（见下面的实测），是合适的基线。 ]]--
  local function resetToLeft()
    -- ★ 优先用子表形式（真机可用）；扁平名保底（mock 用）
    local lv = nil
    local sub = safeCall(function() return Enum.TextHorizontalAlignment end)
    if type(sub) == "table" then
      lv = safeCall(function() return sub.Left end)
    end
    if lv == nil then
      lv = safeCall(function() return Enum.TextHorizontalAlignmentLeft end)
    end
    if lv ~= nil then
      safeCall(function() ctrl.horizontalAlignment = lv end)
    end
    return lv
  end

  local function tryWrite(label, getter)
    -- ★ 先重置，再取值、写入、读回
    resetToLeft()

    local v = safeCall(getter)
    local vstr = tostring(v)
    local typeOK = (v ~= nil)
    local wrote = false

    if typeOK then
      wrote = safeCall(function()
        ctrl.horizontalAlignment = v
        return true
      end) == true
    end

    local back = tostring(safeCall(function() return ctrl.horizontalAlignment end))
    -- 判定：读回值是否表示"居中"（同读回表的口径 —— 见那里的说明）
    local ok = type(back) == "string"
      and (back:find("Middle", 1, true) ~= nil
           or back == "C" or back == "M" or back == "center")
    log(string.format("      %-46s 取值=%-8s 写入=%-6s 读回=%-38s %s",
        label, typeOK and "有" or "nil", tostring(wrote), back,
        ok and "✅ 生效" or "❌"))
    return ok
  end

  -- 先置回 Left，确保每次实验的起点一致。
  -- ⚠️ 同样不能用扁平名 —— 真机上是 nil，写了等于没置。
  safeCall(function()
    local sub = Enum.TextHorizontalAlignment
    if type(sub) == "table" then
      ctrl.horizontalAlignment = sub.Left
    else
      ctrl.horizontalAlignment = Enum.TextHorizontalAlignmentLeft
    end
  end)
  log(string.format("    （起点已置为 %s）",
      tostring(safeCall(function() return ctrl.horizontalAlignment end))))

  local winners = {}
  local CANDIDATES = {
    { "Enum.TextHorizontalAlignmentMiddle",
      function() return Enum.TextHorizontalAlignmentMiddle end },
    { "Enum.TextHorizontalAlignment.Middle",
      function() return Enum.TextHorizontalAlignment.Middle end },
    { "Enum.HorizontalAlignment.Middle",
      function() return Enum.HorizontalAlignment.Middle end },
    { "Enum.TextAlignment.Middle",
      function() return Enum.TextAlignment.Middle end },
    { "Enum.TextHorizontalAlignment.Center",
      function() return Enum.TextHorizontalAlignment.Center end },
    { "Enum.TextHorizontalAlignmentMiddle 的 tostring 反查",
      function()
        -- 有些实现里枚举是字符串，用名字直接写也认
        return "Middle"
      end },
    { '字符串 "Center"', function() return "Center" end },
    { '字符串 "middle"', function() return "middle" end },
    { "由 Left 的读回值反推：把末尾换成 Middle",
      function()
        local cur = tostring(ctrl.horizontalAlignment)
        local guess = cur:gsub("Left", "Middle")
        if guess == cur then return nil end
        return guess
      end },
  }

  for _, c in ipairs(CANDIDATES) do
    -- ★ 重置已由 tryWrite 内部完成（见那里的假阳性说明）
    if tryWrite(c[1], c[2]) then winners[#winners + 1] = c[1] end
  end

  --[[ ★ 实验做完必须【还原】被测控件。

       ⚠️ 每次 tryWrite 前都把它置成 Left 做基线，所以循环结束时
          它停在 Left —— 而紧接着的"读回表"是拿同一个 A 组控件测的，
          会把实验的副作用当成"库没写进去"，得出错误结论。
          （第一次跑就踩了：读回表显示 al-a1 = Left 而其余五组 = C。）

       ★ 还原办法：用【实验刚刚证明可用的那个取法】写回去。

         ⚠️⚠️ 这里踩过一次：还原时写的是
              Enum.TextHorizontalAlignmentMiddle（文档的扁平名），
              而那个名字在真机上是 nil —— 于是"还原"本身失败，
              读回表里 al-a1 依然显示 Left，白白多报一条假不符。
              （2026-10-09 真机：实验证明 .Middle 可用、扁平名不可用。）
         现在按子表形式还原；万一还失败，就标记 dirtyA 让读回表跳过它。 ]]
  local restored = false
  safeCall(function()
    local sub = Enum.TextHorizontalAlignment
    if type(sub) == "table" then
      ctrl.horizontalAlignment = sub.Middle
      restored = true
    end
  end)
  -- 兼容 mock（短 token "C"）
  if not restored then
    safeCall(function() ctrl.horizontalAlignment = Enum.TextHorizontalAlignmentMiddle end)
  end

  local back = tostring(safeCall(function() return ctrl.horizontalAlignment end))
  if not (back:find("Middle", 1, true) or back == "C") then
    M.align.dirtyA = true
    log("")
    log("  ⚠️ A 组控件无法还原成 Middle（读回 " .. back .. "）——")
    log("     下面的读回表里 al-a1 会被跳过，因为它做过枚举写入实验，")
    log("     读回值不代表库的结果。其余五组未被本实验触碰，依然有效。")
  end

  --===========================================================================
  log("")
  log("[3] 判读")
  --===========================================================================
  if #winners == 0 then
    log("  ❌ 没有任何取法能写入 Middle。")
    log("     => horizontalAlignment 这条路在真机上【写不进去】。")
    log("     => 结论：库的 text-align:center 无效（真机实测）。")
    log("     => 兜底方案：靠【框宽 = 文字宽】间接居中 ——")
    log("        即用 util.measureText 量出文字宽度，把框宽设成等于它，")
    log("        再把框本身居中（left = (父宽 - 文字宽)/2）。")
    log("        这样文字自然就在视觉中间，不依赖对齐字段。")
  else
    log("  ✅ 以下取法可以生效：")
    for _, w in ipairs(winners) do log("       " .. w) end
    log("")
    log("  => 把 webui_render.lua 里写 horizontalAlignment 的地方")
    log("     改成上面第一个能生效的取法，并加 pcall + 失败告警")
    log("     （现在失败是静默的，所以一直没人发现）。")
  end

  log("")
  log("  ★ 若真相是「字段可写但真机不渲染」——")
  log("     本实验的读回会是 Middle 而屏幕仍不居中，")
  log("     那就必须改用上面的【框宽=文字宽】兜底方案。")
  log("     请把本段日志 + 截图一起回传。")
  log("")
end

--[[ 读回：把每个对照元素的【声明值】与【实际值】并排列出来。

     ⚠️ 这是本模块的重点 —— 不打印"我打算设什么"，而是读引擎侧
        真正生效的字段与布局结果。 ]]--
function M.align.after(ui)
  log("")
  log("============================================================")
  log("  读回表：声明值 vs 引擎实际值")
  log("============================================================")

  --[[ ★★ 第一次真机跑的结果（2026-10-09）已经回答了核心问题：

       六组对照的 horizontalAlignment 【全部读回 Left】，
       而框宽/位置【全部正确】。结论：
         · CSS 的 text-align: center 算得出来（本地验证过）
         · 但写进引擎控件时【没生效】，字段停在默认 Left
         · 库用 pcall 包着写入，失败被静默吞掉 -> 一直没人发现

       所以本模块现在【先做枚举形态实验】，再做常规读回表。
       枚举实验会找出"到底哪种取法能写进去"，或者证明写不进去。 ]]
  M.align.probeEnum(ui)

  log("")
  hr("读回表：声明值 vs 引擎实际值（重新测量）")

  -- ★ 等一帧，确保控件都建出来了（render 后控件在同一帧内创建）
  local dom = require('webui').dom

  -- 每个 id 的【声明宽度】（与 CSS 逐字对应；改 CSS 记得同步改这里）
  local DECLARED = {
    ["al-a1"] = 400, ["al-b1"] = 400, ["al-c1"] = 400,
    ["al-d1"] = 400, ["al-e1"] = 120, ["al-l1"] = 400,
    ["al-ft"] = 400, ["al-fm"] = 400, ["al-fb"] = 400,
  }
  --[[ 期望的【垂直】对齐。
       F 组三个框尺寸完全相同、只有 vertical-align 不同 ——
       若三者读回都是同一个值，说明垂直对齐没有生效。 ]]--
  local EXPECT_V = {
    ["al-ft"] = "Top", ["al-fm"] = "Middle", ["al-fb"] = "Bottom",
  }
  -- 期望的 ha（全部都是 center / 或 F 组的 left）
  local EXPECT = "Middle"
  local EXPECT_H = {
    ["al-ft"] = "Left", ["al-fm"] = "Left", ["al-fb"] = "Left",
  }

  local order = { "al-a1", "al-b1", "al-c1", "al-d1", "al-e1", "al-l1",
                  "al-ft", "al-fm", "al-fb" }

  log("")
  log(string.format("  %-8s %-10s %-12s %-10s %-12s %-14s %s",
      "id", "声明宽", "实际框宽", "ha读回", "va读回", "对齐判定", "说明"))
  log("  " .. string.rep("-", 100))

  local problems = {}

  for _, id in ipairs(order) do
    local nd = nil
    dom.walk(ui.doc, function(n)
      if n:isElement() and n.attrs and n.attrs.id == id then nd = n end
    end)

    if not nd then
      log(string.format("  %-8s (找不到该 DOM 节点)", id))
      problems[#problems + 1] = id .. ":节点缺失"
    else
      local e = ui.rendered.live[nd]
      local ctrl = e and e.control
      local box = nd.box

      local ha = "?"
      local va = "?"
      local kind = e and e.kind or "?"
      if ctrl then
        ha = tostring(safeCall(function() return ctrl.horizontalAlignment end))
        va = tostring(safeCall(function() return ctrl.verticalAlignment end))
      end

      local declared = DECLARED[id] or -1
      local actualW = box and box.w or -1

      --[[ ★ 判定读回的 ha 是不是"居中"。

             ⚠️ 必须同时认两种形态，否则本地自检会假红：
               · 真机： "Enum.TextHorizontalAlignment.Middle"（带点、名字形式）
               · mock： "C"（本仓库测试里把枚举值定义成短 token）

             ★ 曾经这里写得过于宽松 —— 把 Left 也判成"相符"，
               第一次真机跑就给出了假的 ✅，白误导一轮。
               所以现在【正面匹配】，且 Left 一律判失败。 ]]
      local function isMiddle(ha)
        if type(ha) ~= "string" then return false end
        if ha:find("Middle", 1, true) then return true end
        -- 短 token 形式：mock 用 C/M，排除 Left/L
        if ha == "C" or ha == "M" or ha == "center" then return true end
        return false
      end
      local function isLeft(ha)
        if type(ha) ~= "string" then return false end
        return ha:find("Left", 1, true) ~= nil or ha == "L" or ha == "left"
      end
      -- ★ 通用：读回值里是否含某个词（Top / Middle / Bottom）
      local function has(ha, word)
        return type(ha) == "string" and ha:find(word, 1, true) ~= nil
      end

      -- ha 判定：F 组期望 Left，其余期望 Middle
      local wantH = EXPECT_H[id]
      local haOK
      if wantH == "Left" then haOK = isLeft(ha) else haOK = isMiddle(ha) end
      local wOK = math.abs(actualW - declared) < 1.5

      -- ★ 垂直判定（只有 F 组有期望值）
      local wantV = EXPECT_V[id]
      local vaOK = true
      if wantV then
        vaOK = has(va, wantV)
        -- mock 的短 token 兼容
        if not vaOK then
          local short = { Top = "T", Middle = "M", Bottom = "B" }
          vaOK = (va == short[wantV])
        end
      end

      local verdict, note = "", ""
      -- ★ al-a1 被枚举实验动过，读回值不可信（见 probeEnum 末尾的还原说明）
      if id == "al-a1" and M.align.dirtyA then
        verdict = "— 已跳过"
        note = "该控件做过枚举写入实验，读回值不代表库的结果"
      elseif not haOK then
        verdict = isLeft(ha) and "❌ ha=Left（未生效）" or "❌ ha不对"
        note = "写入未生效 -> 看下方的枚举形态实验"
        problems[#problems + 1] = id .. ":ha=" .. tostring(ha)
      elseif not vaOK then
        verdict = "❌ va不符"
        note = string.format("期望 %s，读回 %s（垂直对齐没生效）",
            wantV, tostring(va))
        problems[#problems + 1] = string.format("%s:va=%s", id, tostring(va))
      elseif not wOK then
        verdict = "⚠️ 宽度不符"
        note = string.format("差 %.1f（布局/尺寸问题）", actualW - declared)
        problems[#problems + 1] = string.format("%s:宽 %.0f≠%.0f",
            id, actualW, declared)
      else
        verdict = "✅ 相符"
        note = string.format("被测控件 kind=%s", kind)
      end

      log(string.format("  %-8s %-10d %-12.1f %-10s %-12s %-14s %s",
          id, declared, actualW, ha, va, verdict, note))

      -- 额外打印位置，便于与截图对照
      if box then
        log(string.format("           box x=%.1f y=%.1f w=%.1f h=%.1f",
            box.x or -1, box.y or -1, box.w or -1, box.h or -1))
      end
    end
  end

  --===========================================================================
  hr("【判读表】")
  --===========================================================================

  log("  ★★ 关键：本表只能证明【库有没有把值写进去】。")
  log("     文字在屏幕上到底有没有居中，必须看【截图】量左右留白 ——")
  log("     引擎没有「文字实际 bbox」的 API，日志给不出渲染位置。")
  log("")
  log("  换算常数：截图像素 = 画布单位 x 1.6（2560 屏 / 1600 画布）")
  log("    例：A 组框 left=40 宽=400 -> 截图上应为 x 64 ~ 704")
  log("        若文字左边界不在中间（约 x 384 起），就是没居中")
  log("")

  if #problems == 0 then
    log("  ✅ 所有对照组的 ha 与框宽都与声明相符")
    log("     => 库这一层没问题。")
    log("     => 那 demo_dino 弹窗里文字不居中的原因，只可能是：")
    log("        ① 截图上量错了框的位置（框不在你以为的地方），或")
    log("        ② 真机上 horizontalAlignment 对【某些控件】不生效")
    log("")
    log("  ⚠️ 请重点对比截图里的 A（基线）与 B（嵌套）：")
    log("       A 居中而 B 不居中 -> 根因是【嵌套】")
    log("       A、B 都不居中      -> 根因是引擎/库层（与嵌套无关）")
    log("       A、B 都居中        -> 那 demo 的问题在别处，需再看 demo 截图")
  else
    log("  ⚠️ 发现 " .. #problems .. " 处与声明不符：")
    for _, p in ipairs(problems) do log("     - " .. p) end
    log("")
    log("  => 先修这些【可测的】不符项，再谈文字居中。")
  end

  log("")
  log("  ★ 别忘了把结论追加到本文件头部的「历史结论索引」。")
  log("")
  log("============================================================")
end

M.align.report = function(ui, items)
  log(string.format("  （本模块共 %d 个对照文本控件）", #items))
  log("  ★ 请【截图】，然后按「读回表」+ 截图留白一起判读。")
end

--=============================================================================
-- 模块 fit ——  ★★ 多屏幕比例适配取证
--=============================================================================
--[[ 目的：在【当前这台设备】上确认真实画布尺寸与适配参数。

     这个模块【不做实验】，只读回环境事实 + 算一遍适配参数：
       ① game.GetUICanvasSize() 到底返回什么（不同屏幕不一样！）
       ② 设计尺寸 1600x900 在该画布下的 k / 留边
       ③ 实测：页面按适配铺开后，四边是否真的贴边（靠截图判读）
       ④ 光标反变换自检（反变换回来的设计坐标是否落在预期）

     ★ 为什么重要：非 16:9 屏幕上画布比例会变，
       不做适配就会"内容没铺满、四周露出游戏画面"。
       真机实测数据见 docs/引擎能力与限制.md §6.4。
]]--

M.fit = {}

-- 设计尺寸（页面 CSS 里写的逻辑分辨率）
M.fit.DESIGN = { 1600, 900 }

--[[ 页面：一个铺满设计尺寸的底色层 + 四角标记 + 中心十字。

     判读方式（截图）：
       · 底色层应当【四边贴齐】内容区边缘（不留缝、不溢出）
       · 四角标记应当正好在内容区四角
       · 中心十字应当正好在屏幕中心
     若底色层没有贴边 -> 适配没生效（k 算错或没传 designSize）
]]--
M.fit.CSS = [[
<style>
  .stage { width: 1600px; height: 900px; background-color: #10141c; }

  /* 内容区边框：四个 1px 细条，用于判断"内容区边界到底在哪" */
  .edge-t { position: absolute; left: 0px;   top: 0px;    width: 1600px; height: 2px;  background-color: #ff4444; }
  .edge-b { position: absolute; left: 0px;   top: 898px;  width: 1600px; height: 2px;  background-color: #ff4444; }
  .edge-l { position: absolute; left: 0px;   top: 0px;    width: 2px;    height: 900px; background-color: #44ff44; }
  .edge-r { position: absolute; left: 1598px; top: 0px;   width: 2px;    height: 900px; background-color: #44ff44; }

  /* 中心十字：应当落在屏幕正中 */
  .cx { position: absolute; left: 780px; top: 440px; width: 40px; height: 20px; background-color: #ffd23f; }
  .cy { position: absolute; left: 790px; top: 430px; width: 20px; height: 40px; background-color: #ffd23f; }

  /* 四角标记：应当正好在内容区四角 */
  .c-tl { position: absolute; left: 0px;     top: 0px;     width: 60px; height: 20px; background-color: #3a7bd5; }
  .c-tr { position: absolute; left: 1540px;  top: 0px;     width: 60px; height: 20px; background-color: #3a7bd5; }
  .c-bl { position: absolute; left: 0px;     top: 880px;   width: 60px; height: 20px; background-color: #3a7bd5; }
  .c-br { position: absolute; left: 1540px;  top: 880px;   width: 60px; height: 20px; background-color: #3a7bd5; }

  /* 文字：报告设计尺寸（框高 38 >= 字号 18 x 1.9 = 34.2 ✓） */
  .lbl { position: absolute; left: 620px; top: 60px;
         width: 360px; height: 38px;
         font-size: 18px; color: #ffffff; background-color: #10141c;
         text-align: center; }
</style>
]]

function M.fit.build()
  return ([[
<div class="stage">
  <div class="edge-t"></div><div class="edge-b"></div>
  <div class="edge-l"></div><div class="edge-r"></div>
  <div class="cx"></div><div class="cy"></div>
  <div class="c-tl"></div><div class="c-tr"></div>
  <div class="c-bl"></div><div class="c-br"></div>
  <div class="lbl">DESIGN 1600x900</div>
</div>
]] ) .. M.fit.CSS
end

--[[ ★ before 钩子：读回画布尺寸 + 算适配参数 + 自检反变换 ]]--
M.fit.before = function(ui)
  local util = require('webui_util')
  local fitMod = require('webui_fit')

  log("")
  log("  ── ① 真实画布尺寸 ──")

  -- 强制刷新，拿到【当前这台设备】的真值
  local cw, ch = util.canvasSize(true)
  log(string.format("     game.GetUICanvasSize() -> %.4f x %.4f", cw, ch))
  log(string.format("     屏幕比例 = %.5f", cw / ch))

  local dw, dh = M.fit.DESIGN[1], M.fit.DESIGN[2]
  log(string.format("     设计尺寸 = %d x %d（比例 %.5f）", dw, dh, dw / dh))

  if math.abs(cw / ch - dw / dh) < 0.005 then
    log("     → 与设计比例【一致】：k 应为画布/设计，且无留边")
  else
    log("     → 与设计比例【不一致】：必须等比缩放 + 留边（见 §6.4）")
  end

  log("")
  log("  ── ② 适配参数（designSize = 1600x900）──")
  local f = fitMod.compute(dw, dh, cw, ch)
  log("     " .. fitMod.describe(f))
  log(string.format("     缩放后内容 = %.1f x %.1f", f.scaledW, f.scaledH))
  log(string.format("     留边 = 左右 %.1f / 上下 %.1f", f.offsetX, f.offsetY))

  -- 预期：至少有一边贴边（不然就是用错了算法）
  local touchW = math.abs(f.scaledW - cw) < 1
  local touchH = math.abs(f.scaledH - ch) < 1
  log(string.format("     贴边检查：水平 %s / 垂直 %s",
      touchW and "✓贴边" or "✗未贴边", touchH and "✓贴边" or "✗未贴边"))
  if not (touchW or touchH) then
    log("     ⚠️ 两边都没贴边 —— 算法有问题，请检查 webui_fit.compute")
  end

  log("")
  log("  ── ③ 光标反变换自检 ──")
  -- 画布中心反变换后应当 = 设计中心
  local midX, midY = fitMod.toDesign(f, cw / 2, ch / 2)
  log(string.format("     画布中心 (%.1f, %.1f) -> 设计 (%.2f, %.2f)",
      cw / 2, ch / 2, midX, midY))
  log(string.format("     期望设计中心 (%.1f, %.1f)", dw / 2, dh / 2))
  if math.abs(midX - dw / 2) < 1 and math.abs(midY - dh / 2) < 1 then
    log("     ✅ 反变换正确 —— 点击命中不会错位")
  else
    log("     ⚠️ 反变换不对！缩放后点击会偏 —— 检查 webui_fit.toDesign")
  end

  log("")
  log("  ── ④ 判读方式（截图）──")
  log("     红条 = 内容区上下边界（2px）")
  log("     绿条 = 内容区左右边界（2px）")
  log("     黄十字 = 内容区中心（应落在屏幕正中）")
  log("     蓝块 = 内容区四角")
  log("")
  log("     · 若四角蓝块正好在【屏幕四角】且无留边 -> 16:9，k 已正确铺满")
  log("     · 若上下有留边但红条贴齐留边内侧 -> 适配正确 ✓")
  log("     · 若红/绿条【跑到屏幕外】或四周露出游戏画面 -> 适配未生效 ✗")
  log("     · 若黄十字不在屏幕正中 -> 居中有问题 ✗")
  log("")
  log("  ⚠️ 本模块【不传 designSize】（ui 由主流程统一创建）。")
  log("     要验证适配生效，请在 main.lua 里给 webui.new 传：")
  log('        designSize = {1600, 900}, fit = "letterbox", fitBg = "#10141c"')
  log("")
  log("  ★ 别忘了把结论追加到本文件头部的「历史结论索引」。")
  log("")
  log("============================================================")
end

--=============================================================================
-- 主流程
--=============================================================================

--[[ ★ 模块注册表。新增模块就在这加一行，并把 ACTIVE 改成模块名。

     ⚠️ 已移除：text / mask / glyph / clip / mount
        —— 归档在 docs/探针模块归档.md，需要时按那里重建。
  ]]--
local MODULES = { key = M.key, perf = M.perf, align = M.align, fit = M.fit }

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

  -- ★ 探针的 before 钩子：需要在首帧渲染【之前】做的事
  --   （align 模块用它给对照组做第二遍 flush，确保读回的是稳定结果）
  if mod.before then
    local ok0, err0 = pcall(mod.before, ui)
    if not ok0 then warn("before() 异常: " .. tostring(err0)) end
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
