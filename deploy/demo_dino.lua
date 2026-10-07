--[[============================================================================
  demo_dino.lua  ——  Chrome 离线小恐龙（像素图形版）

  ┌──────────────────────────────────────────────────────────┐
  │   HI 00000  00000                                        │
  │                    ▄▄                                    │
  │      ██           ████          ▄▄                      │
  │      ██    ▄▄     ████    ▄▄    ██                      │
  │  ════════════════════════════════════════════════════════│
  └──────────────────────────────────────────────────────────┘

  ★ 操作：空格 / ↑（游戏默认跳跃键）
     撞到障碍 -> Game Over，按跳跃键重开

  ══════════════════════════════════════════════════════════════════════════
  ★★ 恐龙不再是方块 —— 用 33 个矩形拼出了真实像素轮廓
  ══════════════════════════════════════════════════════════════════════════

    引擎不能导入外部图像，于是把原版点阵【分解成矩形】，
    每个矩形 = 1 个纯色块控件。

      恐龙站立  33 个矩形
      恐龙跑动  29 个矩形（两条腿交替）
      恐龙死亡  30 个矩形
      仙人掌     8 个矩形
      云         6 个矩形

  ══════════════════════════════════════════════════════════════════════════
  ★★ 性能设计：父容器整体移动 + 换帧时重算
  ══════════════════════════════════════════════════════════════════════════

    R22 真机实测的成本模型：
        每帧耗时(ms) = 11.92 + 0.0449 x 写入次数

    · 写入极便宜（44.9 微秒/次）—— 33 个矩形全量更新只要约 1.5ms
    · 真正的开销是固定 11.92ms（与 DOM 节点数相关）

    所以做法是：
      · 【每帧】只移动外层容器（1 次写入）-> 整只恐龙跟着动
      · 【换姿态】才重算内层 33 个矩形（约 1.5ms，每几帧一次）

    这样每帧的写入量从 33 降到 1，把便宜的东西用在刀刃上。

  ══════════════════════════════════════════════════════════════════════════
  为什么这样写（踩过的约束）
  ══════════════════════════════════════════════════════════════════════════

    · 文字框高 ≥ 字号 × 1.9      —— 分数/提示的框高按此留够
    · 文本框必须显式写 background-color —— 引擎默认底是深色 #535353
    · 要居中必须写 text-align    —— 默认 left（实测左右边距差 470px）
    · 裁剪容器不设 background-color —— 填充不受自身遮罩约束
    · 障碍移出屏幕要主动 hide()  —— 省控件开销
    · 不用 type() 判断宿主对象
=============================================================================]]

local webui  = require('webui')
local sprite = require('webui_sprite')

--=============================================================================
-- 精灵：把点阵转成矩形，再生成 HTML
--=============================================================================

local CELL = 8            -- 每个逻辑格 8px

--[[ ★ 相邻矩形外扩量（px）。

     真机实测（R23）：矩形铺开后，相邻块之间会露出 1.25~4.38px 的
     背景缝（截图逐像素量得，缝里是纯背景色），整只恐龙看起来是碎的。
     点阵内部有 45 条相邻边界 —— 每条都是一条潜在缝。

     解法：每个矩形四边各向外扩 1px，让相邻块互相压住。
     代价是轮廓胖 1px，但同色压在同色背景上，看不出来。

     ⚠️ toHTML 与 sprite.apply 必须用同一个值。 ]]--
local BLEED = 1

--[[ ★ 每个精灵：{ 矩形表, 宽(格), 高(格) } ]]--
local SP = {
  dino     = { rects = sprite.dinoRects(),     w = 22, h = 24 },
  dinoRun  = { rects = sprite.dinoRunRects(),  w = 22, h = 24 },
  dinoDead = { rects = sprite.dinoDeadRects(), w = 22, h = 24 },
  cactus   = { rects = sprite.cactusRects(),   w = 9,  h = 14 },
  cloud    = { rects = sprite.cloudRects(),    w = 10, h = 5  },
}

--[[ 生成一个"精灵容器"的 HTML：外层负责移动，内层装矩形。

     ★ 两层结构是关键：
         .spr      <- 每帧移动它（1 次写入）
         .spr-body <- 换姿态时重算里面的矩形

     ★★ 用 image 控件（asImage=true）而不是纯色块（R24 真机确认）：

        textbox 模板【自带圆角，半径 >= 8px】：
          · 8px 的色块被画成【圆形】
          · 33 个矩形里 29 个（88%）至少一边 <= 16px -> 全部变形
          · 圆角还让相邻矩形的四角对不上 -> 就是那些缝

        image 模板【是方的】（编辑器确认）-> 用它拼图。

        ⚠️ 代价：每个矩形要 SetImage 一次。但只需在【建控件时】做，
           换姿态只改尺寸/位置，不用重贴。
]]--
local function spriteHTML(rects, prefix, wrapId, bodyId, color)
  return string.format([[
<div class="spr" id="%s"><div class="spr-body" id="%s">
%s</div></div>
]], wrapId, bodyId,
     sprite.toHTML(rects, { cell = CELL, prefix = prefix,
                            bleed = BLEED, asImage = true }))
end

--=============================================================================
-- 页面
--=============================================================================

local HTML = ([[
<div class="stage" id="stage">
  <div class="scene" id="scene">
    <div class="score" id="score">HI 00000  00000</div>

    <div class="ground"></div>

    <!-- 恐龙：外层移动 / 内层换帧 -->
    %s

    <!-- 障碍：3 个仙人掌槽位 -->
    %s
    %s
    %s

    <!-- 云：2 朵 -->
    %s
    %s

    <div class="over" id="over">G A M E   O V E R</div>
    <div class="hint" id="hint">按 空格 / ↑ 开始</div>
  </div>
</div>
]]):format(
  spriteHTML(SP.dino.rects, "dR",  "dino", "dinoBody"),
  spriteHTML(SP.cactus.rects, "c0R", "o0", "o0Body", "#535353"),
  spriteHTML(SP.cactus.rects, "c1R", "o1", "o1Body", "#535353"),
  spriteHTML(SP.cactus.rects, "c2R", "o2", "o2Body", "#535353"),
  spriteHTML(SP.cloud.rects,  "k0R", "cl0", "cl0Body", "#c8cdd4"),
  spriteHTML(SP.cloud.rects,  "k1R", "cl1", "cl1Body", "#c8cdd4")
)

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
      不写背景 -> 引擎给默认深色底 #535353，深灰字压深灰底看不见。
      不写 text-align -> 默认 left，文字贴框左边。 */
.score {
  position: absolute; left: 1080px; top: 60px;
  width: 440px; height: 38px;
  font-size: 18px; color: #535353;
  background-color: #f7f7f7;
  text-align: right;
}

/* 地面：纯色块，无缝 */
.ground {
  position: absolute; left: 0px; top: 700px;
  width: 1600px; height: 4px;
  background-color: #535353;
}

/* ★★ 精灵：外层容器负责移动，内层装矩形。
   外层尺寸 = 精灵逻辑尺寸 x CELL（撑住布局，避免溢出到父背景外）。 */
.spr      { position: absolute; left: 0px; top: 0px; }
.spr-body { position: absolute; left: 0px; top: 0px; }

/* 恐龙：22x24 格 x 8px = 176 x 192
   ★ top=508 让【点阵的脚】正好落在地面线 700 上（508 + 192 = 700） */
#dino { left: 160px; top: 508px; width: 176px; height: 192px; }

/* 仙人掌：9x14 格 x 8px = 72 x 112
   ★ top=588 让底落在地面线（588 + 112 = 700） */
#o0, #o1, #o2 { top: 588px; width: 72px; height: 112px; }

/* 云：10x5 格 x 8px = 80 x 40 */
#cl0 { left: 400px; top: 200px; width: 80px; height: 40px; }
#cl1 { left: 1100px; top: 300px; width: 80px; height: 40px; }

/* Game Over：框高 80 >= 字号 40 x 1.9 = 76 ✓
   ★ 显式背景 + 居中（同 .score 的两个坑） */
.over {
  position: absolute; left: 400px; top: 300px;
  width: 800px; height: 80px;
  font-size: 40px; color: #535353;
  background-color: #f7f7f7;
  text-align: center;
  display: none;
}

/* 提示：框高 38 >= 字号 18 x 1.9 ✓
   ⚠️ 字色不能太浅：#9a9a9a 在真机底色上对比度只有 93，实测不可见。
      #6a6a6a 对比度约 157，够清晰。 */
.hint {
  position: absolute; left: 600px; top: 400px;
  width: 400px; height: 38px;
  font-size: 18px; color: #6a6a6a;
  background-color: #f7f7f7;
  text-align: center;
}
]]

--=============================================================================
-- 游戏参数（调这些就能改手感）
--=============================================================================

local G = {
  --[[ ★★ 摆放几何（必须与点阵尺寸一致，否则恐龙会悬空/陷地）

       地面线 .ground top = 700
       恐龙点阵 22x24 格 x 8px = 176x192，脚在控件顶 +192
         -> 站在地面时控件 top = 700 - 192 = 508
       仙人掌点阵 9x14 格 x 8px = 72x112，底在控件顶 +112
         -> 贴地时控件 top = 700 - 112 = 588

       ⚠️ 之前 GROUND_Y=620 是按旧的 80x80 方块算的，
          换成 192 高的点阵后恐龙会【陷到地面下 112px】。 ]]
  GROUND_Y   = 508,     -- 恐龙落地时的 top（= 地面 700 - 点阵高 192）
  GRAVITY    = 4200,    -- 重力加速度 px/s^2
  JUMP_V     = -1150,   -- 起跳初速度 px/s（负 = 向上）
  BASE_SPEED = 620,     -- 障碍初始速度 px/s
  MAX_SPEED  = 1500,    -- 最高速度（封顶）
  ACCEL      = 32,      -- 每秒加速 px/s

  --[[ ★ 碰撞盒：只取【身体主体】，不含头部最上和尾巴尖。

       恐龙点阵里躯干+腿大致在格 y 12..21 -> 像素 88..168（相对控件顶）。
       取这个区间做碰撞盒，手感更接近原版：
         · 站着时 画布 y = 508+88 .. 508+168 = 596..676
         · 跳到峰值（146px）时 = 450..530，低于仙人掌顶 588 -> 安全 ✓ ]]
  DINO_X     = 160,
  DINO_SPR_H = 192,     -- 恐龙点阵总高
  DINO_HIT_W = 92,      -- 碰撞盒宽（比控件 176 窄：点阵左右有空格）
  DINO_HIT_T = 88,      -- 碰撞盒顶（相对控件顶）
  DINO_HIT_B = 168,     -- 碰撞盒底（相对控件顶）

  -- 仙人掌：实心柱，取全高
  OBS_W      = 72,
  OBS_H      = 112,
  OBS_TOP    = 588,
  OBS_HIT_W  = 46,      -- 比控件窄：点阵左右有空格
  OBS_HIT_T  = 0,       -- 相对控件顶
  OBS_HIT_B  = 112,

  SPAWN_GAP  = 760,     -- 障碍之间的最小水平间距
  RUN_FRAME  = 6,       -- 每多少帧换一次跑动姿态
  FPS        = 50,      -- 循环步长（固定）
}

--=============================================================================
-- 游戏状态（★ 存在外部表里 —— 控件上无法写自定义字段）
--=============================================================================

local S = {
  y       = 0,
  vy      = 0,
  onAir   = false,
  obs     = {},
  clouds  = {},
  speed   = G.BASE_SPEED,
  dist    = 0,
  score   = 0,
  hi      = 0,
  over    = false,
  started = false,
  runPhase = 1,         -- 1 或 2：当前用哪个跑动姿态
  runTimer = 0,
}

local nodes = {}       -- id -> DOM 节点

-- 精灵的矩形节点缓存（换姿态时直接操作，不用每帧查 DOM）
local spNodes = {}

local function reset()
  S.y, S.vy, S.onAir = G.GROUND_Y, 0, false
  S.speed = G.BASE_SPEED
  S.dist, S.score = 0, 0
  S.over, S.started = false, false
  S.runPhase, S.runTimer = 1, 0
  S.obs = {}
  for i = 1, 3 do
    S.obs[i] = { x = -9999, active = false }
  end
  S.clouds = {
    { x = 400,  y = 200, speed = 0.18 },
    { x = 1100, y = 300, speed = 0.14 },
  }
end

reset()

local function pad5(n)
  local s = tostring(math.floor(n))
  while #s < 5 do s = "0" .. s end
  return s
end

--=============================================================================
-- 换姿态：把新矩形表写回节点
--=============================================================================

--[[ 换姿态：把新矩形表写回节点。

     ★ bleed 必须与 toHTML 用同一个值 —— 否则换姿态后缝又回来了。
       这里显式传 BLEED（定义在 CELL 旁边）。

     ★ asImage 模式下还要传 reimage：换姿态会把某些矩形从隐藏
       变为显示，而那些控件可能已被控件池回收（图丢了）-> 重贴一次。 ]]--
local clipRef = nil      -- 延迟取 webui_clip
local uiRef   = nil      -- onReady 里存 ui

local function reimageNode(node)
  if not clipRef then clipRef = require('webui_clip') end
  if not uiRef then return end
  local e = uiRef.rendered and uiRef.rendered.live and uiRef.rendered.live[node]
  local ctrl = e and e.control
  if ctrl and type(ctrl.SetImage) == "function" then
    pcall(function() ctrl:SetImage(clipRef.imageSource(), 100001) end)
    pcall(function() ctrl.imageColor = Color.FromRGBA(83, 83, 83, 255) end)
  end
end

local function setPose(prefix, rects, count)
  sprite.apply(spNodes[prefix] or {}, rects, CELL, count, BLEED, reimageNode)
end

--=============================================================================
-- 每帧逻辑
--=============================================================================

local function tick(dt)
  -- 分数栏（两种状态都要刷新）
  if nodes.score then
    nodes.score:setText(string.format("HI %s  %s", pad5(S.hi), pad5(S.score)))
  end

  -- 未开始：只显示提示
  if not S.started then
    return
  end

  --===========================================================================
  -- 已结束：摆死亡姿态，不再跑逻辑
  --===========================================================================
  if S.over then
    if nodes.dino then
      nodes.dino:setStyle("transform", "translateY(0px)")
    end
    if not S._deadPosed then
      S._deadPosed = true
      setPose("dinoDead", SP.dinoDead.rects, #SP.dinoDead.rects)
    end
    return
  end

  --===========================================================================
  -- ① 恐龙物理（固定步长，结果可复现）
  --===========================================================================
  if S.onAir then
    S.vy = S.vy + G.GRAVITY * dt
    S.y = S.y + S.vy * dt
    if S.y >= G.GROUND_Y then
      S.y = G.GROUND_Y
      S.vy = 0
      S.onAir = false
    end
  end

  --===========================================================================
  -- ② 加速 + 计分
  --===========================================================================
  S.speed = math.min(G.MAX_SPEED, S.speed + G.ACCEL * dt)
  S.dist = S.dist + S.speed * dt
  S.score = S.score + S.speed * dt * 0.012
  if S.score > S.hi then S.hi = S.score end

  --===========================================================================
  -- ③ 障碍移动
  --===========================================================================
  for i = 1, #S.obs do
    local o = S.obs[i]
    if o.active then
      o.x = o.x - S.speed * dt
      if o.x < -G.OBS_W - 60 then
        o.active = false
        o.x = -9999
      end
    end
  end

  -- ④ 生成障碍
  local needSpawn = (S.dist % G.SPAWN_GAP) < (S.speed * dt)
  if needSpawn then
    for i = 1, #S.obs do
      if not S.obs[i].active then
        S.obs[i].active = true
        S.obs[i].x = 1600 + 60
        break
      end
    end
  end

  --===========================================================================
  -- ⑤ 云（视差：比障碍慢很多）
  --===========================================================================
  for i = 1, #S.clouds do
    local c = S.clouds[i]
    c.x = c.x - S.speed * c.speed * dt
    if c.x < -100 then c.x = 1700 end
  end

  --===========================================================================
  -- ⑥ 碰撞检测（AABB，用点阵推导出的真实碰撞盒）
  --===========================================================================
  local dinoL = G.DINO_X
  local dinoR = G.DINO_X + G.DINO_HIT_W
  local dinoT = S.y + G.DINO_HIT_T
  local dinoB = S.y + G.DINO_HIT_B

  for i = 1, #S.obs do
    local o = S.obs[i]
    if o.active then
      local padX = (G.OBS_W - G.OBS_HIT_W) / 2
      local obsL = o.x + padX
      local obsR = obsL + G.OBS_HIT_W
      local obsT = G.OBS_TOP + G.OBS_HIT_T
      local obsB = G.OBS_TOP + G.OBS_HIT_B

      if dinoR > obsL and dinoL < obsR and dinoB > obsT and dinoT < obsB then
        S.over = true
        S._deadPosed = false
        if S.score > S.hi then S.hi = S.score end
        break
      end
    end
  end

  --===========================================================================
  -- 渲染：把状态写回 DOM
  --===========================================================================

  -- ★ 恐龙：只移动外层（1 次写入），内层矩形不碰
  if nodes.dino then
    nodes.dino:setStyle("transform",
        string.format("translateY(%.1fpx)", S.y - G.GROUND_Y))
  end

  -- ★ 跑动动画：每 RUN_FRAME 帧换一次姿态
  if not S.onAir then
    S.runTimer = S.runTimer + 1
    if S.runTimer >= G.RUN_FRAME then
      S.runTimer = 0
      S.runPhase = (S.runPhase == 1) and 2 or 1
      local pose = (S.runPhase == 1) and SP.dino or SP.dinoRun
      setPose("dino", pose.rects, #pose.rects)
    end
  end

  -- 障碍
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

  -- 云
  for i = 1, #S.clouds do
    local c = S.clouds[i]
    local nd = nodes["cl" .. (i - 1)]
    if nd then
      nd:setStyle("transform", string.format("translateX(%.1fpx)", c.x))
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
    -- 重开：保留最高分
    local hi = S.hi
    reset()
    S.hi = hi
    S.started = true
    S._deadPosed = false
    -- 恢复站立姿态
    setPose("dino", SP.dino.rects, #SP.dino.rects)
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

  onReady = function(ui, a)
    local dom = webui.dom
    uiRef = ui          -- ★ 供 reimageNode 用（换姿态时重贴图）

    -- 收集所有 id 节点
    dom.walk(ui.doc, function(n)
      if n:isElement() and n.attrs and n.attrs.id then
        nodes[n.attrs.id] = n
      end
    end)

    -- ★ 收集【每个精灵的矩形节点】，供换姿态时直接操作
    --   精灵前缀 -> 矩形数：见 SP 表
    local prefixes = {
      dR = #SP.dino.rects,
      c0R = #SP.cactus.rects, c1R = #SP.cactus.rects, c2R = #SP.cactus.rects,
      k0R = #SP.cloud.rects,  k1R = #SP.cloud.rects,
    }
    for prefix, count in pairs(prefixes) do
      spNodes[prefix] = sprite.collect(dom, ui.doc, prefix, count)
    end
    -- 跑动/死亡姿态共用 "dR" 前缀的节点，这里登记别名
    spNodes["dino"]     = spNodes["dR"]
    spNodes["dinoRun"]  = spNodes["dR"]
    spNodes["dinoDead"] = spNodes["dR"]

    --[[ ★★ 给每个矩形贴方形图（asImage 模式必需）。

         textbox 模板自带圆角（8px 的块会变成圆），而 image 模板是方的
         （编辑器确认）-> 所以用 image 控件 + SetImage(方形图 100001)。

         ★ 只需在这里做【一次】；换姿态只改尺寸/位置，不用重贴。
    ]]
    local clip = require('webui_clip')
    local total, okCount = 0, 0
    for prefix, count in pairs(prefixes) do
      for i = 1, count do
        local node = spNodes[prefix] and spNodes[prefix][i]
        if node then
          total = total + 1
          local e = ui.rendered and ui.rendered.live and ui.rendered.live[node]
          local ctrl = e and e.control
          if ctrl and type(ctrl.SetImage) == "function" then
            if pcall(function() ctrl:SetImage(
                clip.imageSource(), 100001) end) then
              -- 染成深灰（方形图是白→灰渐变，需染色才有正确颜色）
              pcall(function()
                ctrl.imageColor = Color.FromRGBA(83, 83, 83, 255)
              end)
              okCount = okCount + 1
            end
          end
        end
      end
    end

    -- 初始隐藏障碍
    for i = 0, 2 do
      local nd = nodes["o" .. i]
      if nd then nd:hide() end
    end
    if nodes.over then nodes.over:hide() end

    -- 恐龙初始朝右站好
    setPose("dino", SP.dino.rects, #SP.dino.rects)

    print(string.format("[dino] 就绪：恐龙 %d 矩形，仙人掌 %d，云 %d",
        #SP.dino.rects, #SP.cactus.rects, #SP.cloud.rects))
    print(string.format("[dino] 贴方形图 %d / %d（image 模式，绕开文本框圆角）",
        okCount, total))
    print("[dino] 按 空格 / ↑ 开始")
  end,

  on = {},
}

--=============================================================================
-- 生命周期接线（引擎的硬性约定，3 行）
--=============================================================================

function OnStart()    app:start()  end
function OnUpdate(dt) app:update() end
function OnDestroy()  app:stop()   end
