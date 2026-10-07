--[[============================================================================
  demo_dino.lua  ——  Chrome 离线小恐龙（跳跃游戏）

  ┌──────────────────────────────────────────────────────────┐
  │   HI 00000  00000                                        │
  │                                                          │
  │                    ▄▄                                    │
  │      ██           ████          ▄▄                      │
  │      ██    ▄▄     ████    ▄▄    ██                      │
  │  ════════════════════════════════════════════════════════│
  └──────────────────────────────────────────────────────────┘

  ★ 操作：空格 / ↑（游戏默认跳跃键）
     撞到障碍 -> Game Over，按跳跃键重开

  ══════════════════════════════════════════════════════════════════════════
  本示例演示的三件事（都是真机验证过的能力）
  ══════════════════════════════════════════════════════════════════════════

    1. ★ onTick(dt) 游戏循环钩子（2026-10-08 新增）
       —— 每帧【先跑逻辑再渲染】，物理用固定步长

    2. ★ keys 键盘绑定（R20 真机验证，2026-10-08）
       —— KeyboardJumpKeyDown/Up，只绑 root 一处

    3. transform: translate 驱动移动
       —— 障碍与恐龙都用 translate，不改布局

  ══════════════════════════════════════════════════════════════════════════
  为什么这样写（踩过的约束）
  ══════════════════════════════════════════════════════════════════════════

    · 文字框高 ≥ 字号 × 1.9  —— 分数栏高度按此留够
    · 裁剪容器不设 background-color —— .stage 专注裁剪，底色由子层承载
    · 障碍移出屏幕要主动 hide() —— 裁剪容器只裁子控件，
      但 hide 更省（不占控件池的渲染开销）
    · 不用 type() 判断宿主对象
=============================================================================]]

local webui = require('webui')

--=============================================================================
-- 页面：纯 HTML + CSS
--=============================================================================

local HTML = [[
<div class="stage" id="stage">
  <div class="scene" id="scene">
    <div class="score" id="score">HI 00000  00000</div>

    <div class="ground"></div>

    <div class="dino" id="dino"></div>

    <div class="obs" id="o0"></div>
    <div class="obs" id="o1"></div>
    <div class="obs" id="o2"></div>

    <div class="over" id="over">G A M E   O V E R</div>
    <div class="hint" id="hint">按 空格 / ↑ 开始</div>
  </div>
</div>
]]

local CSS = [[
/* 舞台：裁剪容器（overflow:hidden 用矩形图当遮罩）
   ★ 不设 background-color —— 它的填充不受自身遮罩约束，会溢出 */
.stage {
  width: 1600px; height: 900px;
  overflow: hidden;
}

/* ★ 底色由这一层承载（包住所有内容的那一层） */
.scene {
  width: 1600px; height: 900px;
  background-color: #f7f7f7;
}

/* 分数：框高 38 >= 字号 18 x 1.9 = 34.2 ✓
   ★★ 必须显式写 background-color + text-align（R21 真机实证）。

   为什么"不写背景"会看不见字：
     引擎给文本框的默认底色是【深色】#535353（不是透明！）。
     本项目实测：Game Over 用了 color:#535353 + 未写背景
     -> 底(49,48,48) vs 字(46,45,45)，对比度只有 3，文字完全消失。
     （截图逐像素量得，详见 docs/引擎能力与限制.md §4.4.1）

   为什么"不写 text-align"会偏左：
     text-align 默认 left，文字从框左边开始排。
     实测：框宽 800、文字宽 328，左边距 3.8px / 右边距 473.8px。
     （框居中 ≠ 文字居中，见 §4.4.2） */
.score {
  position: absolute; left: 1080px; top: 60px;
  width: 440px; height: 38px;
  font-size: 18px; color: #535353;
  background-color: #f7f7f7;   /* ★ 显式，与页面同色 */
  text-align: right;           /* 原版分数靠右 */
}

/* 地面：纯色块，无缝 */
.ground {
  position: absolute; left: 0px; top: 700px;
  width: 1600px; height: 4px;
  background-color: #535353;
}

/* 恐龙：80x80 方块（用纯色块，无需图片资源） */
.dino {
  position: absolute; left: 160px; top: 620px;
  width: 80px; height: 80px;
  background-color: #535353;
}

/* 障碍：仙人掌，40x70 */
.obs {
  position: absolute; left: 0px; top: 630px;
  width: 40px; height: 70px;
  background-color: #535353;
}

/* Game Over：框高 76 >= 字号 40 x 1.9 = 76 ✓（刚好够） */
/* Game Over：框高 80 >= 字号 40 x 1.9 = 76 ✓

   ★★ 两个真机实测踩出来的坑（2026-10-08，见 docs/引擎能力与限制.md）：

   ① 必须【显式】指明背景。不写 background-color 时，引擎给文本框
      画的是默认【深色】底 —— 而字色又是我设的深灰 #535353，
      结果实测对比度只有 3（底 48 / 字 45），文字几乎完全看不见。
      -> 实测证据：截图逐像素量得 底=(49,48,48) 字=(46,45,45)

   ② 必须设 text-align: center。不设时文字从框左边开始排：
      实测文字左边距 3.8px、右边距 473.8px（差 470px），严重偏左。

   ★ 模仿原版：不要底条，白底上直接一行深灰字 —— 与 .scene 同底色。 */
.over {
  position: absolute; left: 400px; top: 300px;
  width: 800px; height: 80px;
  font-size: 40px; color: #535353;
  background-color: #f7f7f7;   /* ★ 与 .scene 同色 = 视觉上无底条 */
  text-align: center;          /* ★ 必须：否则文字贴左边 */
  display: none;
}

/* 提示：框高 38 >= 字号 18 x 1.9 ✓
   ★ 同样要显式设背景色 + 居中（同一类坑）

   ⚠️ 字色不能用 #9a9a9a —— 实测在真机底色上对比度只有 93，
      而引擎实际渲染的页面底是 (255,253,245)（比 #f7f7f7 更亮），
      实测截图该区域【只有底色像素，文字完全不可见】。
      改用 #6a6a6a：对比度 ≈ 157，够清晰。 */
.hint {
  position: absolute; left: 600px; top: 400px;
  width: 400px; height: 38px;
  font-size: 18px; color: #6a6a6a;
  background-color: #f7f7f7;   /* ★ 显式，不吃引擎默认深色底 */
  text-align: center;          /* ★ 居中 */
}
]]

--=============================================================================
-- 游戏参数（调这些就能改手感）
--=============================================================================

local G = {
  GROUND_Y   = 620,     -- 恐龙落地时的 top
  GRAVITY    = 4200,    -- 重力加速度 px/s^2
  JUMP_V     = -1150,   -- 起跳初速度 px/s（负 = 向上）
  BASE_SPEED = 620,     -- 障碍初始速度 px/s
  MAX_SPEED  = 1500,    -- 最高速度（封顶）
  ACCEL      = 32,      -- 每秒加速 px/s
  DINO_W     = 80,
  DINO_X     = 160,
  OBS_W      = 40,
  SPAWN_GAP  = 620,     -- 障碍之间的最小水平间距
  FPS        = 50,      -- 循环步长（固定）
}

--=============================================================================
-- 游戏状态（★ 存在外部表里 —— 控件上无法写自定义字段）
--=============================================================================

local S = {
  y       = 0,        -- 恐龙 top
  vy      = 0,        -- 垂直速度
  onAir   = false,
  obs     = {},       -- { {x=, active=}, ... }（只存数据，不存控件）
  speed   = G.BASE_SPEED,
  dist    = 0,        -- 已跑距离（用于刷障碍）
  score   = 0,
  hi      = 0,
  over    = false,
  started = false,
}

local nodes = {}      -- id -> DOM 节点（渲染后填充）

local function reset()
  S.y, S.vy, S.onAir = G.GROUND_Y, 0, false
  S.speed = G.BASE_SPEED
  S.dist, S.score = 0, 0
  S.over, S.started = false, false
  S.obs = {}
  for i = 1, 3 do
    S.obs[i] = { x = -1000, active = false }
  end
end

reset()

local function pad5(n)
  local s = tostring(math.floor(n))
  while #s < 5 do s = "0" .. s end
  return s
end

--=============================================================================
-- 每帧逻辑
--=============================================================================

local function tick(dt)
  -- 分数栏（两种状态都要刷新）
  if nodes.score then
    nodes.score:setText(string.format("HI %s  %s", pad5(S.hi), pad5(S.score)))
  end

  -- 未开始 / 已结束：只闪提示
  if not S.started or S.over then
    if nodes.dino then
      nodes.dino:setStyle("transform", "translateY(0px)")
    end
    return
  end

  -- ① 恐龙物理（固定步长，结果可复现）
  if S.onAir then
    S.vy = S.vy + G.GRAVITY * dt
    S.y = S.y + S.vy * dt
    if S.y >= G.GROUND_Y then
      S.y = G.GROUND_Y
      S.vy = 0
      S.onAir = false
    end
  end

  -- ② 加速
  S.speed = math.min(G.MAX_SPEED, S.speed + G.ACCEL * dt)

  -- ③ 障碍移动
  S.dist = S.dist + S.speed * dt
  S.score = S.score + S.speed * dt * 0.012
  if S.score > S.hi then S.hi = S.score end

  for i = 1, #S.obs do
    local o = S.obs[i]
    if o.active then
      o.x = o.x - S.speed * dt
      -- 移出左边界 -> 回收（★ 主动失效，省控件开销）
      if o.x < -G.OBS_W - 40 then
        o.active = false
        o.x = -1000
      end
    end
  end

  -- ④ 生成障碍：每隔 SPAWN_GAP 距离放一个未占用的槽
  local needSpawn = (S.dist % G.SPAWN_GAP) < (S.speed * dt)
  if needSpawn then
    for i = 1, #S.obs do
      if not S.obs[i].active then
        S.obs[i].active = true
        S.obs[i].x = 1600 + 40
        break
      end
    end
  end

  -- ⑤ 碰撞检测（AABB）
  local dinoL, dinoR = G.DINO_X, G.DINO_X + G.DINO_W
  local dinoT, dinoB = S.y, S.y + G.DINO_W
  for i = 1, #S.obs do
    local o = S.obs[i]
    if o.active then
      local obsL, obsR = o.x, o.x + G.OBS_W
      local obsT, obsB = 630, 630 + 70
      -- 留一点宽容度，手感更接近原版
      if dinoR - 8 > obsL and dinoL + 8 < obsR
         and dinoB - 6 > obsT and dinoT < obsB then
        S.over = true
        if S.score > S.hi then S.hi = S.score end
      end
    end
  end

  --===========================================================================
  -- 渲染：把状态写回 DOM
  --===========================================================================

  if nodes.dino then
    nodes.dino:setStyle("transform",
        string.format("translateY(%.1fpx)", S.y - G.GROUND_Y))
  end

  for i = 1, #S.obs do
    local o = S.obs[i]
    local nd = nodes["o" .. (i - 1)]
    if nd then
      if o.active then
        nd:show()
        nd:setStyle("transform", string.format("translateX(%.1fpx)", o.x))
      else
        nd:hide()
      end
    end
  end

  if nodes.over then
    if S.over then nodes.over:show() else nodes.over:hide() end
  end
  if nodes.hint then
    if not S.started then nodes.hint:show() else nodes.hint:hide() end
  end
end

--=============================================================================
-- 跳跃 / 重开
--=============================================================================

local function onJump()
  if S.over then
    -- 重开
    local hi = S.hi
    reset()
    S.hi = hi
    S.started = true
    return
  end
  if not S.started then
    S.started = true
    return
  end
  -- 只有落地时才能起跳（避免空中连跳）
  if not S.onAir then
    S.vy = G.JUMP_V
    S.onAir = true
  end
end

-- 抬起时给一点"松手减速"的手感：上升中松手则立刻开始下落
local function onJumpUp()
  if S.onAir and S.vy < 0 then
    S.vy = S.vy * 0.45
  end
end

--=============================================================================
-- 挂载
--=============================================================================

local app
app = webui.mount{
  root    = "Root",
  prefabs = {
    container = 1073741933,
    textbox   = 1073741934,
    button    = 1073741935,
    image     = 1073741938,
  },
  html = HTML,
  css  = CSS,
  fps  = G.FPS,

  -- ★ 游戏逻辑钩子：每帧先跑它，再渲染
  onTick = tick,

  -- ★★ 键盘（R20 真机验证）：只绑 root 一处，避免"按一次跳多次"
  keys = {
    jump   = onJump,      -- KeyboardJumpKeyDown
    jumpUp = onJumpUp,    -- KeyboardJumpKeyUp
  },

  -- 渲染完成后抓 DOM 节点（运行时改状态靠它们）
  onReady = function(ui, a)
    local dom = webui.dom
    dom.walk(ui.doc, function(n)
      if n:isElement() and n.attrs and n.attrs.id then
        nodes[n.attrs.id] = n
      end
    end)
    -- 初始隐藏障碍
    for i = 0, 2 do
      local nd = nodes["o" .. i]
      if nd then nd:hide() end
    end
    if nodes.over then nodes.over:hide() end
    print("[dino] 就绪，按 空格 / ↑ 开始")
  end,

  on = {},
}

--=============================================================================
-- 生命周期接线（引擎的硬性约定，3 行）
--=============================================================================

function OnStart()    app:start()  end
function OnUpdate(dt) app:update() end
function OnDestroy()  app:stop()   end
