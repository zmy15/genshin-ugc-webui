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

local CELL = 8            -- 每个逻辑格 8px（仙人掌/翼龙/云 用）

--[[ ★★ 恐龙的格宽（浮点）

     用户反馈 16x17 重采样后【眼睛丢了】。
     8px/格 x 17行 = 136px，但重采样把 1 格的眼睛吞掉了。

     解法：回到原版 22x24 点阵（含眼睛），
     并把格宽缩小保持高度 136px：
       cell = 136 / 24 = 5.67px

     ★ 22 格 x 5.67 = 125px 宽，24 格 x 5.67 = 136px 高
     眼睛 = 5.67 - 2*1(bleed) = 3.67px 可见 ]]--
local DINO_CELL = 5.67

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
  cloud    = { rects = sprite.cloudRects(),    w = 10, h = 5  },
}

--[[ ★★ 仙人掌三档（原版有大/中/小，随机出现）+ 空中翼龙。

     每个障碍槽可以从这几档里随机挑一种，宽度/高度都不同：
       大 9x18 格 = 72x144 px
       中 6x17 格 = 48x136 px
       小 5x12 格 = 40x 96 px
       翼龙 16x8 格 = 128x64 px（空中，两个高度）

     ★ 它们的【底边都对齐地面线】，所以 top 要按各自高度算：
         top = 地面 700 - 高度px ]]--
local OBS_KINDS = {
  --[[ ★ 障碍四种。字段含义：

       w, h     逻辑尺寸（格），实际像素 = w*CELL x h*CELL
       ground   true = 底边对齐地面线；false = 在空中（用 BIRD_YS）

       hitL/hitW/hitT/hitH  ★ 碰撞盒（相对控件左上角）
         点阵的图形周围总有空格，碰撞盒比控件小一圈
         手感更接近原版（看着没撞就不该判死）。

       ★ 这四组数值都经数值验证：
           三种仙人掌 -> 站着必撞 ✓  跳到峰值能过 ✓
           低飞鸟     -> 站着撞 ✓    峰值安全 ✓（必须跳）
           高飞鸟     -> 站着安全 ✓  峰值撞 ✓（不能跳） ]]
  { name = "cactusBig",   rects = sprite.cactusBigRects(),
    w = 9,  h = 18, ground = true,
    hitL = 10, hitW = 52, hitT = 0, hitH = 144 },

  { name = "cactusMid",   rects = sprite.cactusMidRects(),
    w = 6,  h = 17, ground = true,
    hitL = 6,  hitW = 36, hitT = 0, hitH = 136 },

  { name = "cactusSmall", rects = sprite.cactusSmallRects(),
    w = 5,  h = 12, ground = true,
    hitL = 5,  hitW = 30, hitT = 0, hitH = 96 },

  --[[ ★★ 仙人掌组合：一次出 2 株（原版常见）。
       双小株：13 格宽 = 104px；中+小：14 格宽 = 112px
       碰撞盒覆盖两株（每株各留一点余量）。 ]]
  { name = "cactusDouble", rects = sprite.cactusDoubleRects(),
    w = 13, h = 12, ground = true,
    hitL = 4, hitW = 96, hitT = 0, hitH = 96 },

  { name = "cactusMix", rects = sprite.cactusMixRects(),
    w = 14, h = 17, ground = true,
    hitL = 4, hitW = 104, hitT = 0, hitH = 136 },

  { name = "bird",        rects = sprite.birdRects(),
    w = 20, h = 10, ground = false,
    hitL = 20, hitW = 120, hitT = 8, hitH = 72 },
}

--[[ ★ 地面装饰：贴在地面线上的小图案，打破"一条直线"的单调。 ]]--
local DECO_KINDS = {
  { name = "pebble", rects = sprite.pebbleRects(), w = 5, h = 2 },
  { name = "grass",  rects = sprite.grassRects(),  w = 7, h = 2 },
  { name = "tuft",   rects = sprite.tuftRects(),   w = 3, h = 2 },
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
local function spriteHTML(rects, prefix, wrapId, bodyId, cell)
  cell = cell or CELL
  return string.format([[
<div class="spr" id="%s"><div class="spr-body" id="%s">
%s</div></div>
]], wrapId, bodyId,
     sprite.toHTML(rects, { cell = cell, prefix = prefix,
                            bleed = BLEED, asImage = true }))
end

--=============================================================================
-- 页面
--=============================================================================

--[[ ★ 障碍槽：按【矩形数最多的那种障碍】来建节点。

     ⚠️ 运行时会在同一槽里切换大/中/小仙人掌和翼龙，
        节点数必须按最大需求建，否则换到"矩形更多"的类型时
        多出来的矩形没有控件可画 -> 缺一块。

     ★ 初始用哪种都行（都会被隐藏），这里用矩形最多的那种，
       保证节点数一次到位。

     ⚠️【翼龙的扇翅帧矩形数可能比主帧多】（实测 16 > 15）——
        所以必须把扇翅帧也纳入比较，
        否则扇翅时会缺一块（多出的那个矩形没控件可画）。 ]]--
local OBS_MAX_RECTS = 0
local OBS_TEMPLATE_RECTS = nil
local obsAllRects = {}
for _, k in ipairs(OBS_KINDS) do
  obsAllRects[#obsAllRects + 1] = k.rects
end
obsAllRects[#obsAllRects + 1] = sprite.birdFlapRects()   -- ★ 扇翅帧也算上
for _, rects in ipairs(obsAllRects) do
  if #rects > OBS_MAX_RECTS then
    OBS_MAX_RECTS = #rects
    OBS_TEMPLATE_RECTS = rects
  end
end

local function obsSlotHTML(slot)
  -- 用"矩形最多"的那组生成，保证节点够用
  return spriteHTML(OBS_TEMPLATE_RECTS,
                    "o" .. slot .. "R", "o" .. slot, "o" .. slot .. "Body")
end

local HTML = ([[
<div class="stage" id="stage">
  <div class="scene" id="scene">
    <div class="score" id="score">HI 00000  00000</div>

    <div class="ground"></div>

    <!-- 地面装饰：3 个点缀（石子/草丛/小簇），随场景滚动 -->
    %s
    %s
    %s

    <!-- 恐龙：外层移动 / 内层换帧 -->
    %s

    <!-- 障碍：4 个槽位，运行时按类型切换精灵（大/中/小仙人掌 或 翼龙） -->
    %s
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
  -- 地面装饰：初始用三种不同的图案
  spriteHTML(DECO_KINDS[1].rects, "p0R", "dc0", "dc0Body"),
  spriteHTML(DECO_KINDS[2].rects, "p1R", "dc1", "dc1Body"),
  spriteHTML(DECO_KINDS[3].rects, "p2R", "dc2", "dc2Body"),
  -- 恐龙
  spriteHTML(SP.dino.rects, "dR", "dino", "dinoBody", DINO_CELL),
  -- 障碍槽（按最大矩形数建节点）
  obsSlotHTML(0), obsSlotHTML(1), obsSlotHTML(2), obsSlotHTML(3),
  -- 云
  spriteHTML(SP.cloud.rects,  "k0R", "cl0", "cl0Body"),
  spriteHTML(SP.cloud.rects,  "k1R", "cl1", "cl1Body")
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

/* ★★ 恐龙：16x17 格 x 8px = 128 x 136
   为什么是这个尺寸：需求要求「恐龙高度 = 中仙人掌高度」
     中仙人掌 17 格 = 136px，恐龙 17 格 = 136px ✓

   ★ top = 地面 700 - 136 = 564（脚正好踩在地面线上） */
#dino { left: 160px; top: 564px; width: 125px; height: 136px; }

/*[[ 障碍槽：尺寸与 top 由运行时按【实际类型】设置。

     各种类型的底边都对齐地面线 700：
       大仙人掌 9x18 格 = 72x144  ->  top = 700-144 = 556
       中仙人掌 6x17 格 = 48x136  ->  top = 700-136 = 564
       小仙人掌 5x12 格 = 40x 96  ->  top = 700- 96 = 604
       翼龙    16x 8 格 = 128x 64 ->  在空中，两个高度（见 BIRD_YS）

     ★ 所以这里【不给固定的 width/height/top】——
       初始值随便给，onReady 后由 applyObstacle 立刻覆盖。 */
#o0, #o1, #o2, #o3 { top: 604px; width: 40px; height: 96px; }

/* 地面装饰：贴在地面线上（top = 700 - 高度px）
   高 2 格 = 16px -> top = 684 */
#dc0, #dc1, #dc2 { top: 684px; height: 16px; }
#dc0 { left: 500px;  width: 40px; }
#dc1 { left: 1000px; width: 56px; }
#dc2 { left: 1400px; width: 24px; }

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
       恐龙 16x17 格 x 8px = 128x136，脚在控件顶 +136
         -> 站在地面时控件 top = 700 - 136 = 564
       仙人掌底边都对齐地面：top = 700 - 高度px ]]
  GROUND_Y   = 564,     -- 恐龙落地时的 top（= 地面 700 - 点阵高 136）
  GRAVITY    = 6100,    -- 重力加速度 px/s^2

  --[[ ★★ 起跳初速：让跳跃峰值达到 ~210px

       为什么要 210：需求要求「跳跃必须高过最高的仙人掌」
         大仙人掌 = 144px
         旧参数峰值 146px -> 只高出 2px，碰巧就撞，太勉强

       峰值公式：H = v^2 / (2g)
         v = 1150 -> H = 1150^2/(2*4200) = 157
         v = 1330 -> H = 1330^2/(2*4200) = 210  ✓

       ★ 210 还给了「高飞鸟」充足的可用空间（见 BIRD_YS）。 ]]
  JUMP_V     = -1600,   -- 起跳初速度 px/s（负 = 向上）-> 峰值约 210px

  BASE_SPEED = 620,     -- 障碍初始速度 px/s
  MAX_SPEED  = 1500,    -- 最高速度（封顶）
  ACCEL      = 32,      -- 每秒加速 px/s

  --[[ ★★ 碰撞盒：只取【身体主体】，不含头部最上和尾巴尖。

       恐龙点阵 16x17，躯干+腿大致在格 y 7..14
         -> 像素 56..112（相对控件顶）
       站着时 画布 y = 564+56 .. 564+112 = 620..676
       峰值时 = 564-210+56 .. 564-210+112 = 410..466

       ★ 寬度取 76（比控件 128 窄：点阵左右有空格） ]]
  DINO_X     = 160,
  DINO_SPR_H = 136,     -- 恐龙点阵总高
  DINO_HIT_W = 76,      -- 碰撞盒宽
  DINO_HIT_T = 56,      -- 碰撞盒顶（相对控件顶）
  DINO_HIT_B = 112,     -- 碰撞盒底（相对控件顶）

  --[[ ★★ 障碍：三种仙人掌 + 翼龙，尺寸各不同。

       所有【地面】障碍的底边都对齐地面线 700：top = 700 - 高度px ]]
  GROUND_LINE = 700,
  OBS_HIT_PAD = 13,     -- 碰撞盒比控件每边窄这么多（点阵左右有空格）

  --[[ ★★★ 翼龙的两个飞行高度（算出来的，不是拍的）

       恐龙碰撞盒：  站立 620..676   跳到峰值 410..466
       翼龙高 80px

       低飞=603（区间 603..683）：
         ✓ 与站立盒重叠  -> 不跳就撞（必须跳）
         ✓ 与峰值盒不重叠 -> 跳起来能躲

       高飞=405（区间 405..485）：
         ✓ 与站立盒不重叠 -> 站着就能过（不用跳）
         ✓ 与峰值盒重叠  -> 跳了反而撞

       ★ 两者都用数值搜索验证过有解，且余量充足。 ]]
  BIRD_YS = { 603, 405 },   -- 低飞（必须跳）/ 高飞（不能跳）

  SPAWN_GAP  = 760,     -- 障碍之间的最小水平间距
  WAVE_GAP   = 1500,    -- ★ 两波障碍的间隔（保证不会"仙人掌+鸟"同时挡路）
  RUN_FRAME  = 6,       -- 每多少帧换一次跑动姿态
  BIRD_FLAP  = 8,       -- ★ 翼龙扇翅膀的帧间隔
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
  decos   = {},         -- 地面装饰（随场景滚动）
  speed   = G.BASE_SPEED,
  dist    = 0,
  score   = 0,
  hi      = 0,
  over    = false,
  started = false,
  runPhase = 1,         -- 1 或 2：当前用哪个跑动姿态
  runTimer = 0,
  seed    = 20261008,   -- ★ 自带的伪随机种子（不用 math.random，见下）
}

local nodes = {}       -- id -> DOM 节点

-- 精灵的矩形节点缓存（换姿态时直接操作，不用每帧查 DOM）
local spNodes = {}

--[[ ★ 自带线性同余随机数。

     ⚠️ 不用 math.random：真机沙箱里它的种子行为未验证，
        而且我们希望每次开局序列【可复现】（便于调试）。
     返回 0..1 的浮点。 ]]--
local function rnd()
  S.seed = (S.seed * 1103515245 + 12345) % 2147483648
  return S.seed / 2147483648
end

local function pickKind()
  -- 三种仙人掌 + 两种组合（双株小、中+小）等概率
  -- ★ 4 是翼龙（空中），不走这里 —— 所以从 {1,2,3,5,6} 里挑
  local r = rnd()
  if r < 0.20 then return 1        -- 大
  elseif r < 0.40 then return 2    -- 中
  elseif r < 0.60 then return 3    -- 小
  elseif r < 0.80 then return 5    -- 双小株组合
  else return 6 end                -- 中+小组合
end

--[[ 障碍槽数量（4 个，够放同屏的障碍） ]]--
local OBS_SLOTS = 4
local DECO_SLOTS = 3

local function reset()
  S.y, S.vy, S.onAir = G.GROUND_Y, 0, false
  S.speed = G.BASE_SPEED
  S.dist, S.score = 0, 0
  S.over, S.started = false, false
  S.runPhase, S.runTimer = 1, 0
  S.obs = {}
  for i = 1, OBS_SLOTS do
    S.obs[i] = { x = -9999, active = false, kind = 1, birdY = 0 }
  end
  S.clouds = {
    { x = 400,  y = 200, speed = 0.18 },
    { x = 1100, y = 300, speed = 0.14 },
  }
  S.decos = {}
  for i = 1, DECO_SLOTS do
    S.decos[i] = { x = 300 + i * 420, kind = ((i - 1) % #DECO_KINDS) + 1 }
  end
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

local function setPose(prefix, rects, count, cell)
  cell = cell or CELL
  sprite.apply(spNodes[prefix] or {}, rects, cell, count, BLEED, reimageNode)
end

--=============================================================================
-- ★★ 障碍：把某个槽位切换成指定的类型（换精灵 + 改尺寸 + 改位置）
--=============================================================================

--[[ 改变一个障碍槽的"外观"。

     slot   1..OBS_SLOTS
     kind   OBS_KINDS 的下标（1=大仙人掌 2=中 3=小 4=翼龙）
     birdY  仅翼龙用：飞行高度（画布 top）

     ★ 做法：
       ① 把旧精灵的多余矩形隐藏，再按新精灵的矩形表铺开（setPose）
       ② 改外层容器的尺寸与 top（让底边对齐地面，或放到空中）

     ⚠️ 矩形节点是按【最大需求】建的？不是 —— 每个槽初始只用
        "小仙人掌"的矩形数建了节点。换成大仙人掌（矩形更多）时，
        节点不够用，多出来的矩形【画不出来】。

     ★ 所以这里按【矩形数最多的那种】来建初始节点（见 HTML 生成处），
       切换时只显示需要的前 N 个。
]]--
local function applyObstacle(slot, kind, birdY)
  local k = OBS_KINDS[kind]
  local wrap = nodes["o" .. (slot - 1)]
  if not wrap or not k then return end

  -- ① 先按新精灵的矩形表铺开（内部会 show/hide 到正确的数量）
  setPose("o" .. (slot - 1) .. "R", k.rects, #k.rects)

  -- ② 定位：地面障碍底边贴地面线；翼龙放空中
  local w = k.w * CELL
  local h = k.h * CELL
  if k.ground then
    wrap:setStyle("top",   (G.GROUND_LINE - h) .. "px")
    wrap:setStyle("left",  "0px")     -- 实际 x 由每帧 translateX 控制
  else
    wrap:setStyle("top",   (birdY or G.BIRD_YS[1]) .. "px")
    wrap:setStyle("left",  "0px")
  end
  wrap:setStyle("width",  w .. "px")
  wrap:setStyle("height", h .. "px")
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
      setPose("dinoDead", SP.dinoDead.rects, #SP.dinoDead.rects, DINO_CELL)
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
      local k = OBS_KINDS[o.kind]
      local w = k and (k.w * CELL) or 72
      if o.x < -w - 60 then
        o.active = false
        o.x = -9999
      end
    end
  end

  --===========================================================================
  -- ④ 生成障碍
  --
  --   ★★ 关键约束：一波只出【一种】障碍
  --
  --     为什么：若仙人掌和高飞的鸟同时挡在身前，
  --     玩家跳起来躲仙人掌就会撞上高飞的鸟，不跳又撞仙人掌
  --     -> 【无解】。
  --
  --     所以每次只派一个障碍，且下一个要等足够远
  --     （WAVE_GAP）—— 保证玩家有时间回到地面再跳。
  --===========================================================================
  local needSpawn = (S.dist % G.WAVE_GAP) < (S.speed * dt)
  if needSpawn then
    for i = 1, #S.obs do
      if not S.obs[i].active then
        local o = S.obs[i]
        o.active = true
        o.x = 1600 + 60
        -- 约 25% 出翼龙，其余三种仙人掌随机
        if rnd() < 0.25 then
          o.kind = 4
          -- 低飞（必须跳）/ 高飞（不能跳）
          o.birdY = G.BIRD_YS[(rnd() < 0.5) and 1 or 2]
        else
          o.kind = pickKind()
          o.birdY = 0
        end
        o.flap = 1          -- ★ 翼龙扇翅姿态
        o.flapTimer = 0
        applyObstacle(i, o.kind, o.birdY)
        break
      end
    end
  end

  --===========================================================================
  -- ⑤ 云（视差：比障碍慢很多）+ 地面装饰
  --===========================================================================
  for i = 1, #S.clouds do
    local c = S.clouds[i]
    c.x = c.x - S.speed * c.speed * dt
    if c.x < -100 then c.x = 1700 end
  end

  --[[ ★ 地面装饰：跟障碍【同速】滚动（贴地的东西不该有视差），
       移出屏幕后从右边回来并换一个图案 —— 这样地面就不单调了。 ]]
  for i = 1, #S.decos do
    local d = S.decos[i]
    d.x = d.x - S.speed * dt
    if d.x < -100 then
      d.x = 1700 + rnd() * 200
      d.kind = math.floor(rnd() * #DECO_KINDS) + 1
      local dk = DECO_KINDS[d.kind]
      setPose("p" .. (i - 1) .. "R", dk.rects, #dk.rects)
      local nd = nodes["dc" .. (i - 1)]
      if nd then nd:setStyle("width", (dk.w * CELL) .. "px") end
    end
  end

  --===========================================================================
  -- ⑥ 碰撞检测（AABB，按【每个障碍的实际类型】算碰撞盒）
  --
  --[[ ★★ 修正：之前用的是"控件实际尺寸"，而点阵四周有空格
         （比如鸟的翅膀只占下半部）。
         用控件尺寸会导致：看着没碰上，实际已判死；或反过来漏判。

       ★ 所以这里用【每个精灵自己的碰撞盒】（存在 OBS_KINDS 里），
         它是按点阵内容量出来的。 ]]
  local dinoL = G.DINO_X
  local dinoR = G.DINO_X + G.DINO_HIT_W
  local dinoT = S.y + G.DINO_HIT_T
  local dinoB = S.y + G.DINO_HIT_B

  for i = 1, #S.obs do
    local o = S.obs[i]
    if o.active then
      local k = OBS_KINDS[o.kind]
      local w = k.w * CELL
      local h = k.h * CELL
      -- 容器的 top：地面障碍贴地，翼龙在指定高度
      local top = k.ground and (G.GROUND_LINE - h) or (o.birdY or G.BIRD_YS[1])

      -- ★ 碰撞盒：容器 top + 精灵自带的相对盒
      local obsL = o.x + (k.hitL or 0)
      local obsR = obsL + (k.hitW or w)
      local obsT = top + (k.hitT or 0)
      local obsB = obsT + (k.hitH or h)

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
      setPose("dino", pose.rects, #pose.rects, DINO_CELL)
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

        --[[ ★★ 翼龙扇翅：每 BIRD_FLAP 帧在两帧之间切换。

             ★ 只在【是翼龙】时做 —— 仙人掌没有动画帧。
             ⚠️ 换姿态要用 reimageNode（apply 内部会在"从隐藏变显示"时
                重贴图），这里直接传进去。 ]]
        if o.kind == 4 then
          o.flapTimer = (o.flapTimer or 0) + 1
          if o.flapTimer >= G.BIRD_FLAP then
            o.flapTimer = 0
            o.flap = (o.flap == 1) and 2 or 1
            local rects = (o.flap == 1) and sprite.birdRects()
                                          or sprite.birdFlapRects()
            setPose("o" .. (i - 1) .. "R", rects, #rects)
          end
        end
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

  -- 地面装饰（跟场景同速滚动）
  for i = 1, #S.decos do
    local d = S.decos[i]
    local nd = nodes["dc" .. (i - 1)]
    if nd then
      nd:setStyle("transform", string.format("translateX(%.1fpx)", d.x))
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
    setPose("dino", SP.dino.rects, #SP.dino.rects, DINO_CELL)
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
    --[[ ⚠️ 障碍槽要按【矩形数最多的那种障碍】建节点 ——
          因为运行时会在同一槽里切换大/中/小仙人掌和翼龙，
          节点不够时多出来的矩形画不出来（会缺一块）。
          HTML 里已经按最大需求生成了，这里也按最大数收。 ]]
    -- ★ 与 HTML 生成处保持一致（OBS_MAX_RECTS 已含翼龙扇翅帧）
    local maxObsRects = OBS_MAX_RECTS

    local prefixes = {
      dR  = #SP.dino.rects,
      k0R = #SP.cloud.rects,  k1R = #SP.cloud.rects,
      p0R = #DECO_KINDS[1].rects,
      p1R = #DECO_KINDS[2].rects,
      p2R = #DECO_KINDS[3].rects,
    }
    for s = 0, OBS_SLOTS - 1 do
      prefixes["o" .. s .. "R"] = maxObsRects
    end

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
    for i = 0, OBS_SLOTS - 1 do
      local nd = nodes["o" .. i]
      if nd then nd:hide() end
    end
    if nodes.over then nodes.over:hide() end

    -- 恐龙初始朝右站好
    setPose("dino", SP.dino.rects, #SP.dino.rects, DINO_CELL)

    -- 障碍槽先都铺成小仙人掌（隐藏状态，第一次生成时会 applyObstacle）
    for i = 1, OBS_SLOTS do
      setPose("o" .. (i - 1) .. "R",
              OBS_KINDS[3].rects, #OBS_KINDS[3].rects)
    end

    -- 地面装饰：铺上各自的图案
    for i = 1, DECO_SLOTS do
      local dk = DECO_KINDS[S.decos[i].kind]
      setPose("p" .. (i - 1) .. "R", dk.rects, #dk.rects)
      local nd = nodes["dc" .. (i - 1)]
      if nd then nd:setStyle("width", (dk.w * CELL) .. "px") end
    end

    print(string.format("[dino] 就绪：恐龙 %d 矩形，障碍 %d 种，云 %d",
        #SP.dino.rects, #OBS_KINDS, #SP.cloud.rects))
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
