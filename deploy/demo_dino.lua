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

--[[ ★★ 障碍：仙人掌【运行时随机拼 1~4 株】+ 翼龙（四档飞行高度）。

     ══════════════════════════════════════════════════════════════════════
     为什么仙人掌不再写死成 5 档
     ══════════════════════════════════════════════════════════════════════

       旧版把「单株大/中/小 + 双株小 + 中+小」写死成 5 种组合，
       用户反馈：应该【随机组合 1~4 个】，而不是硬写。

       现在改成：库里 joinStalks 把随机挑出的 N 株【底部对齐】拼成一行
       （见 webui_sprite.lua），demo 只负责决定「这一波出几株、哪几株」。

     ══════════════════════════════════════════════════════════════════════
     ★★★ 株数/宽度必须按【当前速度】限制 —— 否则是死局
     ══════════════════════════════════════════════════════════════════════

       障碍越宽，恐龙要"悬在它上方"的时间越久，而滞空时间是有限的：

         跳跃全程 = 2 x 1600 / 6100 = 0.525s
         恐龙盒底高于「大仙人掌顶」的窗口 = 0.343s

       所以能越过的障碍最大宽度 = speed x 窗口 - 恐龙盒宽：

         速度  620 -> 最多 137px（17 格）  ★ 初始速度下 4 株大仙人掌(288px) 必然撞死
         速度 1500 -> 最多 439px（55 格）

       => 组宽预算由【当前速度】算出来（见 widthBudget），
          随机拼株时一旦超预算就减少株数。
          ★ 这是"难度递增"的几何依据，不是手感偏好。

     ══════════════════════════════════════════════════════════════════════
     ★★ 翼龙：四档高度，全部落在【跳跃可达范围】内
     ══════════════════════════════════════════════════════════════════════

       恐龙碰撞盒：站立 620..676，跳到峰值 410..466
       => 恐龙 top 的可达区间 = [354, 564]

       旧版只有 603 / 405 两档，用户反馈「最上面的鸟太高了，跳起来撞不到」。
       405 那档的盒子(413..485)正好卡在峰值盒上 —— 玩家跳起来【反而撞】，
       既躲不开也够不着，观感上就是"高度不对"。

       现在四档（数值与安全区宽度都验算过）：

         top=596 必须跳   下方安全区 138px
         top=566 必须跳   下方安全区 108px
         top=440 不能跳   上方安全区 100px
         top=406 不能跳   上方安全区 134px

       ★ 四档【都在可达区间内】—— 玩家跳到任何高度都能与它发生关系，
         不存在"够不着的鸟"。
       ★ 安全区都 >= 100px，不是"帧级精度才活得下来"的伪死局。

     ══════════════════════════════════════════════════════════════════════
     ★★ 翼龙三帧扇翅
     ══════════════════════════════════════════════════════════════════════

       旧版只有 2 帧（抬/放），来回切换看起来是"抖"。
       现在用 sprite.birdFrames() 的三帧循环：抬 -> 半收 -> 放 -> 半收 -> 抬。
       ★ 三帧点阵尺寸严格一致（20x10），否则扇翅时会横向错位。 ]]--
local OBS_KINDS = {
  --[[ ★ 仙人掌：点阵由 makeCactus() 运行时随机拼出（1~4 株）。

       w/h 与碰撞盒都在那里按【实际拼出的组合】算，
       这里只登记"它是地面障碍"。 ]]
  { name = "cactus", ground = true },

  --[[ ★★ 翼龙：容器尺寸固定 20x10 格 = 160x80px，高度由 birdY 决定。

       碰撞盒 hitT=8 / hitH=72：
         点阵第 1 行是喙（只有 2 格宽），最后一行是翅尖 ——
         真正"实体"的部分在 y 8..80，所以盒比容器矮一圈、且偏下。 ]]
  { name = "bird", rects = sprite.birdRects(),
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

     ⚠️【翼龙三帧的矩形数不同】（15 / 14 / 12）——
        必须把【三帧都】纳入比较，否则扇翅时会缺一块
        （多出的那个矩形没控件可画）。

     ⚠️ 仙人掌是【运行时随机拼】的，矩形数不固定 ——
        所以必须按【理论上最宽的组合（4 株大仙人掌）】建节点。
        宁可多建（空闲矩形 hide 掉），也不能少建（缺一块）。 ]]--
local OBS_MAX_RECTS = 0
local OBS_TEMPLATE_RECTS = nil
local obsAllRects = {}
for _, k in ipairs(OBS_KINDS) do
  if k.rects then obsAllRects[#obsAllRects + 1] = k.rects end
end
-- ★ 翼龙三帧全算上
for _, r in ipairs(sprite.birdFrames()) do
  obsAllRects[#obsAllRects + 1] = r
end
-- ★ 仙人掌：按最坏情况（4 株大仙人掌）算
obsAllRects[#obsAllRects + 1] = sprite.cactusGroup({1, 1, 1, 1}).rects
for _, rects in ipairs(obsAllRects) do
  if #rects > OBS_MAX_RECTS then
    OBS_MAX_RECTS = #rects
    OBS_TEMPLATE_RECTS = rects
  end
end
print(string.format("[dino] 障碍槽按 %d 个矩形建节点（最坏情况）",
    OBS_MAX_RECTS))

local function obsSlotHTML(slot)
  -- 用"矩形最多"的那组生成，保证节点够用
  return spriteHTML(OBS_TEMPLATE_RECTS,
                    "o" .. slot .. "R", "o" .. slot, "o" .. slot .. "Body")
end

--[[ ★ 星空：只在夜间显示的星星与月亮。

     星星数量与位置【写死在 HTML 里】（不是运行时随机）——
     理由：星星不参与碰撞、不移动（只用视差慢慢滚动），
     写死可以让节点数在建控件时一次到位，运行时不新增控件。

     ★ 位置刻意【避开】分数栏（右上角 ~1080..1520 x 60..98）
       和障碍活动区（地面附近），免得挡住关键信息。 ]]--
local SKY_STARS = {
  -- { x, y, 用大星还是小星 }
  {  120, 120, true  },
  {  330,  70, false },
  {  520, 190, false },
  {  700, 100, true  },
  {  880, 240, false },
  { 1250, 300, false },
  { 1420, 170, false },
  { 1520, 330, false },
  {  240, 330, false },
  {  620, 360, true  },
}

local function skyHTML()
  local out = {}
  --[[ ★★ 星月统一用 5px 格宽。

       ⚠️ 为什么不沿用默认的 CELL=8：
         星星点阵是 5x5 / 3x3，8px 下会变成 42x42 / 26x26 的"大色块"，
         不像星芒。5px 下大星 25x25、小星 15x15、月亮 40x40，
         与原版观感接近。

       ⚠️ 月亮也必须【显式传】5 —— 漏传会退回默认 CELL=8，
         月亮变成 64x64，与星星比例失衡（写这段时刚踩过）。 ]]
  local SKY_CELL = 5
  -- 月亮：固定在左上偏中（与截图一致）
  out[#out + 1] = spriteHTML(sprite.moonRects(), "mnR",
                             "moon", "moonBody", SKY_CELL)
  -- 星星
  for i, s in ipairs(SKY_STARS) do
    local rects = s[3] and sprite.starRects() or sprite.starSmallRects()
    out[#out + 1] = spriteHTML(rects, "st" .. i .. "R",
                               "st" .. i, "st" .. i .. "Body", SKY_CELL)
  end
  return table.concat(out, "\n")
end

local HTML = ([[
<div class="stage" id="stage">
  <div class="scene" id="scene">
    <!-- 星空：只在夜间显示（月亮 + 星星），白天整组隐藏 -->
    <div class="sky" id="sky">
%s
    </div>

    <div class="score" id="score">HI 00000  00000</div>

    <div class="ground" id="ground"></div>

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
  skyHTML(),
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
/* ==========================================================================
   ★★ 昼夜过渡（R28）

   给"承载颜色"的元素加 CSS transition —— 库会把它翻译成
   引擎的 game.Tween（bgColor / fontColor 都是 Tweenable，见
   webui_transition.lua 的说明），于是换主题时颜色【平滑插值】，
   而不是"啪"地跳变。

   ⚠️ 只给这几类元素加：
       .scene / .ground / .score / .over / .hint
     它们都是 textbox（有 bgColor / fontColor 字段）。

   ⚠️ 不要给 .sky 加 —— 星月是 image 控件，靠 display 显隐，
      transition 对它没有意义（而且 imageColor 的过渡会在
      显示瞬间闪一下）。

   ★ 时长取 0.8s：够看出"天在变"，又不至于拖到玩家以为卡了。
   ========================================================================== */
.scene, .ground, .score, .over, .hint {
  transition: background-color 0.8s linear, color 0.8s linear;
}

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

/* ==========================================================================
   ★★ 星空（昼夜更替）
   ==========================================================================

   .sky 是【纯容器】：不设 background-color（设了会盖住背景色），
   只负责把星月分组，方便整组 show/hide。

   ⚠️ 月亮的初始色由运行时按主题染色（image 控件用 imageColor），
      这里不写颜色 —— 写了也没用（image 没有 bgColor 字段）。 */
.sky { position: absolute; left: 0px; top: 0px;
       width: 1600px; height: 700px; }

/* 月亮：6x12 格 x 5px = 30x60（细长月牙，格宽与星星一致 SKY_CELL=5） */
#moon { left: 300px; top: 100px; width: 30px; height: 60px; }

/* 星星：位置与大小由 HTML 生成时决定，这里只补 top/left/尺寸 */
#st1  { left: 120px;  top: 120px; width: 25px; height: 25px; }
#st2  { left: 330px;  top:  70px; width: 15px; height: 15px; }
#st3  { left: 520px;  top: 190px; width: 15px; height: 15px; }
#st4  { left: 700px;  top: 100px; width: 25px; height: 25px; }
#st5  { left: 880px;  top: 240px; width: 15px; height: 15px; }
#st6  { left: 1250px; top: 300px; width: 15px; height: 15px; }
#st7  { left: 1420px; top: 170px; width: 15px; height: 15px; }
#st8  { left: 1520px; top: 330px; width: 15px; height: 15px; }
#st9  { left: 240px;  top: 330px; width: 15px; height: 15px; }
#st10 { left: 620px;  top: 360px; width: 25px; height: 25px; }

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
       恐龙 22x24 格 x DINO_CELL(5.67) = 125x136，脚在控件顶 +136
         -> 站在地面时控件 top = 700 - 136 = 564
       仙人掌底边都对齐地面：top = 700 - 高度px ]]
  GROUND_Y   = 564,     -- 恐龙落地时的 top（= 地面 700 - 点阵高 136）
  GRAVITY    = 6100,    -- 重力加速度 px/s^2

  --[[ ★★ 起跳初速：让跳跃峰值达到 ~210px

       为什么是 210：需求要求「跳跃必须高过最高的仙人掌」
         最高仙人掌（大）= 144px
         峰值 210 -> 余量 66px，不是"碰巧越过"

       峰值公式：H = v^2 / (2g)
         v = 1600, g = 6100 -> H = 209.8  ✓

       ★ v 与 g 必须【同时提高】：只提 v 会让全程变长、手感拖沓
         （v=1330/g=4200 全程 0.633s -> v=1600/g=6100 全程 0.525s）。 ]]
  JUMP_V     = -1600,   -- 起跳初速度 px/s（负 = 向上）-> 峰值约 210px

  BASE_SPEED = 620,     -- 障碍初始速度 px/s
  MAX_SPEED  = 1500,    -- 最高速度（封顶）
  ACCEL      = 32,      -- 每秒加速 px/s

  --[[ ★★ 碰撞盒：只取【身体主体】，不含头部最上和尾巴尖。

       恐龙点阵 22x24，躯干+腿大致在格 y 11..20
         -> 像素 56..112（相对控件顶）
       站着时 画布 y = 564+56 .. 564+112 = 620..676
       峰值时 = 564-210+56 .. 564-210+112 = 410..466

       ★ 宽度取 76（比控件 125 窄：点阵左右有空格） ]]
  DINO_X     = 160,
  DINO_SPR_H = 136,     -- 恐龙点阵总高
  DINO_HIT_W = 76,      -- 碰撞盒宽
  DINO_HIT_T = 56,      -- 碰撞盒顶（相对控件顶）
  DINO_HIT_B = 112,     -- 碰撞盒底（相对控件顶）

  --[[ ★★ 障碍：仙人掌（运行时随机拼 1~4 株）+ 翼龙。

       所有【地面】障碍的底边都对齐地面线 700：top = 700 - 高度px ]]
  GROUND_LINE = 700,
  OBS_HIT_PAD = 13,     -- 碰撞盒比控件每边窄这么多（点阵左右有空格）

  --[[ ★★★ 翼龙四档飞行高度（算出来的，不是拍的）

       恐龙碰撞盒：  站立 620..676   跳到峰值 410..466
       => 恐龙 top 的可达区间 = [峰值 354, 站立 564]
       翼龙碰撞盒 = [birdY+8, birdY+80]

       判据（三选一，前两条是"有威胁"，第三条是"无威胁"）：
         必须跳 = 与站立盒重叠 且 与峰值盒不重叠
         不能跳 = 与站立盒不重叠 且 与峰值盒重叠
         无威胁 = 两者都不重叠（★ 绝不能出现 —— 障碍形同虚设）

       实算（安全区 = 可达区间内"能安全通过"的 top 宽度）：

         top=596  必须跳  下方安全区 138px
         top=566  必须跳  下方安全区 108px
         top=440  不能跳  上方安全区 100px
         top=406  不能跳  上方安全区 134px

       ★★ 与旧版的关键差别：旧版高飞档 405 —— 盒子 413..485，
          而恐龙峰值盒 410..466，两者【几乎完全重合】，
          玩家跳起来不但躲不开、还"够不着"（够不着 = 高度不在可达范围内
          的有效交互区）。观感就是用户说的"太高了，跳起来撞不到"。

       现在最低 596 / 最高 406，【全部落在可达区间 [354,564] 内】，
       且安全区都 >= 100px（不是帧级精度才能活的伪死局）。 ]]
  BIRD_YS = { 596, 566, 440, 406 },  -- 前两档"必须跳"，后两档"不能跳"
  BIRD_LOW_COUNT = 2,                -- ★ BIRD_YS 前几个是"必须跳"档

--[[ ★★★ 难度曲线：开局只有单个仙人掌，往后才出鸟和多株仙人掌

       用户要求：「游戏刚开始应该只有单个仙人掌，没有鸟，
                  往后难度变大再增加鸟和仙人掌的数量和密度」

       用【已跑距离 dist】分阶段（不是按分数 —— 距离才是速度的积分，
       与"障碍跑得多快"直接对应）：

         阶段1  dist <  4600 : 只出【单株】仙人掌，绝不出鸟   ★ 学习期
         阶段2  dist < 24000 : 1~2 株，开始出鸟（只出"必须跳"档）
         阶段3  dist < 40000 : 1~3 株，鸟四档全开，间隔缩小
         阶段4  dist >= 40000: 1~4 株，最密

       ★ 株数与组宽【还要再受 widthBudget 约束】（见 makeCactus），
         所以 stage 只是"上限"，实际宽度永远是可解的。

       ══════════════════════════════════════════════════════════════
       ★★★ 分界值有【两条】约束，缺一条就会出现"阶段形同虚设"
       ══════════════════════════════════════════════════════════════

       ① 必须 >= 第一波的出场距离

          ⚠️ 踩过的坑：第一版写的三个分界是 900 / 5000 / 20000，
             而第一波是在 dist ~1100 才生成的（= 阶段1 的 waveGap）。
             900 < 1100  =>  【第一波生成时已经是阶段2】
             => 阶段1 从未生效，开局第一波就是 2 株仙人掌，
                第 2 波就出鸟 —— 与需求完全相反。

          所以这里按【波数】定：阶段1 的 waveGap=1100，
          要覆盖前 4 波 -> STAGE_DIST[1] >= 1100 x 4 = 4400，取 4600。

       ② 必须按【速度曲线】标定（否则玩家感知不到变化）

          速度在 dist=1665 到 700、dist=9628 到 1000、dist=29159 封顶 1500。
          曾用 3000/7000/12000 -> 阶段4 要到分数 144 才开始，
          而那时速度已近封顶 => 前 20 秒一直停在最简单档。

       ③ 阶段2（无鸟 -> 有鸟 的过渡期）必须够长

          ⚠️ 踩过的坑：曾用 STAGE_DIST[2]=14000，阶段2 只有 9 波，
             而 birdChance=0.25 -> 9 波全不出鸟的概率仍有 7.5%，
             实测那一轮就是 0 鸟。玩家可能【一只鸟都没见到】
             就进入阶段3（那时会出现"不能跳"的鸟，规则正好相反）。

          现在 STAGE_DIST[2]=24000 -> 阶段2 约 19 波，
          见到至少一只鸟的概率 = 1 - 0.75^19 = 99.6%。

       ★ 当前分界的实际节奏（纯逻辑复刻实测）：
           阶段1  用时 ~6.4s（分数 ~77）    4 波    ★ 纯单株、无鸟
           阶段2  用时 ~24s （分数 ~350）   24 波（其中约 19 波属阶段2）
           阶段3  用时 ~35s （分数 ~490）   41 波
           阶段4  此后
       ]]--
  STAGE_DIST = { 4600, 24000, 40000 },  -- 三个分界 -> 共 4 个阶段

  --[[ 每阶段：{ 最多株数, 出鸟概率, 波间隔, 鸟档数 } ]]--
  STAGE_RULES = {
    { maxStalks = 1, birdChance = 0.00, waveGap = 1100, birdTiers = 0 },
    { maxStalks = 2, birdChance = 0.25, waveGap = 1000, birdTiers = 2 },
    { maxStalks = 3, birdChance = 0.45, waveGap = 950,  birdTiers = 4 },
    { maxStalks = 4, birdChance = 0.60, waveGap = 900,  birdTiers = 4 },
  },
  --[[ ★ 组宽安全系数：算出"理论上能越过"的宽度后，再打这个折扣。
        0.8 = 留 20% 余量，避免"刚好卡着也能过"的极限操作。 ]]--
  WIDTH_SAFETY = 0.80,

  RUN_FRAME  = 6,       -- 每多少帧换一次跑动姿态
  BIRD_FLAP  = 8,       -- ★ 翼龙扇翅膀的帧间隔（三帧循环）
  FPS        = 50,      -- 循环步长（固定）

  --[[ ★★★ 昼夜更替（R28）

       需求：「添加昼夜更替效果，黑天背景变成深色，天空加上星星和月亮」

       ══════════════════════════════════════════════════════════════
       为什么是【两套主题 + 按距离切换】，而不是连续插值
       ══════════════════════════════════════════════════════════════

         插值（渐变过渡）需要每帧改颜色，而颜色写入要走
         Color.FromRGBA 新建表 + 引擎字段写入 —— 每帧多次写入
         虽然便宜（44.9 微秒/次），但【diff 缓存会失效】：
         颜色每次都是新表，渲染器按分量比较，若值不变则跳过。
         插值意味着值一直在变 -> 每帧都写 -> 白花性能。

         ★ 更关键的是：真机的颜色写入是否支持平滑过渡未经实测
           （§4.6.2 的教训：不要假设未验证的行为）。

         所以用【瞬切】—— 只在主题真正切换的那一帧写一次颜色。
         视觉上"啪"地天黑了，反而更像原版的关卡切换。

       ══════════════════════════════════════════════════════════════
       两组主题的颜色对应关系（★ 必须同时改，漏一个就露馅）
       ══════════════════════════════════════════════════════════════

         背景 bg      ：浅 #f7f7f7  <->  深 #14161c
         前景 fg      ：深 #535353  <->  浅 #d8dce6
         精灵 sprite  ：深灰(83,83,83) <-> 浅灰(216,220,230)
         地面 ground  ：同 fg（地面线跟字色一起走）
         提示 hint    ：中灰 #6a6a6a <-> #8a93a8（★ 都要与背景有对比度）

       ⚠️ 陷阱：文字框必须【显式】背景色（R21），所以 score/over/hint
          的背景色也要跟着主题改 —— 否则深色主题下会出现三条浅色底。 ]]--
  THEME = {
    day = {
      name    = "day",
      bg      = "#f7f7f7",
      fg      = "#535353",
      sprite  = { 83, 83, 83 },      -- 精灵染色（r,g,b）
      hint    = "#6a6a6a",
      sky     = false,               -- 星月是否可见
    },
    night = {
      name    = "night",
      bg      = "#14161c",
      fg      = "#d8dce6",
      sprite  = { 216, 220, 230 },
      hint    = "#8a93a8",
      sky     = true,
    },
  },

  --[[ ★ 昼夜切换节奏：按【已跑距离】来回切。

       为什么不是按时间：分数/距离本身就是游戏进度，
       按距离切能与难度阶段对齐（阶段边界也按距离）。

       节奏：DIST 每跑 12000px 切一次（约 10~15 秒），
             开局是白天（与原版一致），跑到阈值转夜。 ]]--
  DAYNIGHT_DIST = 12000,
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

--=============================================================================
-- ★★★ 难度曲线 + 组宽预算（"有解"的几何保证）
--=============================================================================

--[[ 当前处于第几阶段（1~4）。按【已跑距离】分，不按分数。 ]]--
local function stageOf(dist)
  for i = 1, #G.STAGE_DIST do
    if dist < G.STAGE_DIST[i] then return i end
  end
  return #G.STAGE_DIST + 1
end

local function ruleOf(stage)
  return G.STAGE_RULES[stage] or G.STAGE_RULES[#G.STAGE_RULES]
end

--[[ ★★★ 当前速度下，恐龙能越过的障碍【最大宽度】（px）。

     推导（这是"有解"的硬保证，不是手感调参）：

       跳跃全程        T = 2|v|/g
       恐龙盒底高于障碍顶的窗口 = 解 0.5*g*t^2 + v*t + need = 0
         其中 need = 恐龙站立 top - 允许的最高 top
                    = GROUND_Y - (GROUND_LINE - 障碍高 - DINO_HIT_B)

       => 最大宽度 = speed x 窗口 - 恐龙盒宽 - 安全余量

     ⚠️ 若障碍比这个还宽，玩家【无论怎么跳都会撞】——
        而且游戏看起来完全正常、不报错。 ]]--
local function maxClearWidth(obsH, speed)
  local needTop = G.GROUND_LINE - obsH - G.DINO_HIT_B
  local need = G.GROUND_Y - needTop          -- 需要上升的像素
  if need <= 0 then return math.huge end     -- 站着就能过（如很高的鸟）

  local a = 0.5 * G.GRAVITY
  local b = G.JUMP_V
  local c = need
  local disc = b * b - 4 * a * c
  if disc < 0 then return 0 end              -- 跳不了这么高

  local t1 = (-b - math.sqrt(disc)) / (2 * a)
  local t2 = (-b + math.sqrt(disc)) / (2 * a)
  local window = t2 - t1
  if window <= 0 then return 0 end

  local w = speed * window - G.DINO_HIT_W
  if w < 0 then w = 0 end
  return w * G.WIDTH_SAFETY
end

--[[ ★★ 随机拼一株仙人掌组（1~maxStalks 株），并保证【组宽不超预算】。

     做法：从 maxStalks 往下试 —— 拼出来的组若太宽就减一株，
           直到宽度进入预算。（最少 1 株，而单株一定在预算内：
           最高的大仙人掌 72px < 初始预算 109px。）

     返回 { rects=, w=, h=, stalks=, hitL=, hitW=, hitT=, hitH= } ]]--
local function makeCactus(maxStalks, speed)
  -- 用最高的一档算预算（保守：组里可能有高株）
  local tallest = 0
  for _, k in ipairs(sprite.CACTUS_KINDS) do
    if k.h > tallest then tallest = k.h end
  end
  local budget = maxClearWidth(tallest * CELL, speed)

  local n = maxStalks
  local grp
  while n >= 1 do
    grp = sprite.randomCactusGroup(n, rnd)
    if grp.w * CELL <= budget then break end
    n = n - 1
  end

  --[[ ★ 碰撞盒按【实际点阵】量，不能用控件尺寸。

       点阵四周有空格（尤其组合后株与株之间的空隙），
       用控件尺寸会导致"看着没撞却判死"。

       这里逐列扫，找出【真正有填充格】的左右边界：
         hitL = 最左填充列 x CELL
         hitW = (最右填充列 - 最左填充列 + 1) x CELL ]]--
  local rows = grp.rows
  local minC, maxC = nil, nil
  for y = 1, #rows do
    local line = rows[y]
    for x = 1, #line do
      if line:sub(x, x) == "#" then
        if not minC or x < minC then minC = x end
        if not maxC or x > maxC then maxC = x end
      end
    end
  end
  minC = minC or 1
  maxC = maxC or grp.w

  return {
    rects = grp.rects,
    w     = grp.w,
    h     = grp.h,
    stalks = grp.stalks,
    -- 碰撞盒：横向贴合实际填充；纵向整高（仙人掌是实心的）
    hitL  = (minC - 1) * CELL,
    hitW  = (maxC - minC + 1) * CELL,
    hitT  = 0,
    hitH  = grp.h * CELL,
  }
end

--[[ 障碍槽数量。

     ★ 不能是"同时最多几个障碍"，而是【节点池上限】：
       槽位按最坏情况的矩形数建节点（4 株大仙人掌 = 通过）。
       4 个槽足够：最密阶段波间隔 1450px，屏宽 1600 + 出屏余量，
       同屏最多 2 个障碍。 ]]--
local OBS_SLOTS = 4
local DECO_SLOTS = 3

local function reset()
  S.y, S.vy, S.onAir = G.GROUND_Y, 0, false
  S.speed = G.BASE_SPEED
  S.dist, S.score = 0, 0
  S.over, S.started = false, false
  S.runPhase, S.runTimer = 1, 0
  --[[ ★ 下一波的生成距离。reset 必须清掉 ——
       否则重开一局时会沿用上一局的进度，第一波延迟出场。 ]]--
  S.nextSpawnDist = G.STAGE_RULES[1].waveGap
  S.obs = {}
  for i = 1, OBS_SLOTS do
    S.obs[i] = { x = -9999, active = false, isBird = false,
                 birdY = 0, frame = 1, flapTimer = 0,
                 rects = nil, w = 0, h = 0,
                 hitL = 0, hitW = 0, hitT = 0, hitH = 0 }
  end
  S.clouds = {
    { x = 400,  y = 200, speed = 0.18 },
    { x = 1100, y = 300, speed = 0.14 },
  }
  S.decos = {}
  for i = 1, DECO_SLOTS do
    S.decos[i] = { x = 300 + i * 420, kind = ((i - 1) % #DECO_KINDS) + 1 }
  end
  --[[ ★ 昼夜状态：开局【白天】（与原版一致）。

       S.dayPhase 记"已经切过几次"，用来算该用哪套主题：
         math.floor(dist / DAYNIGHT_DIST) 为偶数 -> 白天，奇数 -> 夜晚 ]]--
  S.dayPhase = 0
  S.theme    = G.THEME.day
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

--[[ ★★ 当前精灵染色（随昼夜主题变化）。

     ⚠️ reimageNode 与 onReady 的初次贴图【都要用这个值】——
        否则换主题后，某个被控件池回收又重新显示的矩形
        会用旧颜色重贴 -> 夜里冒出一块深灰。

     ★ 用 S.theme 而不是常量：主题切换时它会先更新，
       之后任何重贴都会拿到新颜色。 ]]--
local function spriteColor()
  local s = (S.theme and S.theme.sprite) or { 83, 83, 83 }
  return Color.FromRGBA(s[1], s[2], s[3], 255)
end

--[[ ★★★ 矩形节点 -> 引擎控件 的引用表。

     ⚠️⚠️ 只能用于【reimageNode】（换姿态时重贴方图）—— 那发生在
        节点可见、控件稳定的时刻。

     ★ 绝对不能拿它做长期染色（R28 两次踩坑）：
       节点 display:none 时控件会被还回共享控件池，
       引用会被别的节点取走 -> 染色写错对象且【不报错】。
       染色一律走 rendered.live 现查（见 paintSprites）。 ]]--
local spriteCtrls = {}     -- node -> control

local function rememberCtrl(node, ctrl)
  if node and ctrl then spriteCtrls[node] = ctrl end
end

--[[ 给一个矩形节点重贴方形图 + 染色（asImage 模式必需）。

     ⚠️⚠️ 控件引用必须【现查 rendered.live】，不能用 spriteCtrls 缓存：
        共享控件池会把控件换给别人（节点隐藏/显示时），
        缓存的引用可能指向别人的控件 —— 那样会：
          · 把别人的控件染色（它自己那个没染 -> 变成白色方块）
          · 或者贴图贴错对象
        这正是真机上"冒出白色方块"的成因之一。

     ★ spriteCtrls 只作为【最后的兜底】，且用前检查 _orphan。 ]]--
local function reimageNode(node)
  if not clipRef then clipRef = require('webui_clip') end

  local ctrl = nil
  local e = uiRef and uiRef.rendered and uiRef.rendered.live
            and uiRef.rendered.live[node]
  ctrl = e and e.control
  if not ctrl then
    -- 兜底：用缓存的引用，但必须确认它没被还池
    local cached = spriteCtrls[node]
    if cached and not cached._orphan then ctrl = cached end
  end
  if ctrl then spriteCtrls[node] = ctrl end

  if ctrl and type(ctrl.SetImage) == "function" then
    --[[ ★★ 不加 diff 缓存 —— 每次都真写（R29）。

         ⚠️ 为什么不能用 node 上的缓存来"避免重复写"：
            缓存是挂在【节点】上的，而节点的控件会被共享池换掉
            （节点隐藏 -> 还池 -> 别的节点取走 -> 再取回来可能是另一个）。
            于是"上次已经染过"的记录会撒谎：
              · 控件换了，但缓存说"颜色没变" -> 跳过 -> 白块留下

         ★ 这里写入很便宜（44.9 微秒/次，见 webui_sprite 的性能依据），
           而且只在【可见矩形】上写（隐藏的由 skip 回调挡掉）。
           用正确性换这点开销是划算的。 ]]
    pcall(function() ctrl:SetImage(clipRef.imageSource(), 100001) end)
    pcall(function() ctrl.imageColor = spriteColor() end)
  end
end

--[[ ★★★ 补贴图：保证【当前可见】的精灵矩形都有图有色。

     ══════════════════════════════════════════════════════════════════════
     为什么必须有这一层（R29 白块根因）
     ══════════════════════════════════════════════════════════════════════

       引擎每帧顺序 = onTick（游戏逻辑）-> flush（渲染）。
       而"生成障碍"发生在 onTick 里（applyObstacle -> setPose ->
       sprite.apply -> reimage）—— 那一帧渲染器【还没】给这些节点建控件
       （它们上一帧还是 display:none，不在 rendered.live 里）。

       => reimage 查不到控件 -> 静默跳过 -> flush 建出来的控件
          图/色都是默认值（方形图 100001 是白→灰渐变）= 【一块白】。

       ⚠️ 而 sprite.apply 只在【换姿态】时调用：
          · 仙人掌生成后再也不换姿态 -> 白块一直留到出屏
          · 翼龙扇翅周期性换姿态 -> 白块过一会儿自己好了
       => 用户看到「固定间隔出现、一个白一个正常」正是这个组合。

       ★ 修法：每帧对【显示的】精灵矩形补一次贴图+染色。
         隐藏的节点跳过（它们本来就不显示，控件可能已还池）。 ]]--
--[[ ★★ 对【全部精灵】补帖图（每帧调用）。

     ⚠️ 恐龙有 4 个别名（dR / dino / dinoRun / dinoDead）指向【同一份】节点表，
        重复处理会白白多写两遍 —— 所以这里按【节点表身份】去重。

     ★ 障碍槽同理：o0R..o3R 是 4 份独立表，逐个处理。

     ★ 星月在白天整组 display:none —— skip 回调会跳过它们的矩形，
       所以这个函数在白天不会去碰已经还池的星月控件（安全）。 ]]--
local function reassertSprites()
  local done = {}
  for _, list in pairs(spNodes) do
    if list and not done[list] then
      done[list] = true
      sprite.reassert(list, reimageNode, function(node)
        return node._displayOverride == "none"
      end)
    end
  end
end

local function setPose(prefix, rects, count, cell)
  cell = cell or CELL
  sprite.apply(spNodes[prefix] or {}, rects, cell, count, BLEED, reimageNode)
end

--=============================================================================
-- ★★★ 昼夜更替：把主题写到所有受影响的控件上
--=============================================================================

--[[ 把某个主题应用到界面。

     theme  = G.THEME.day 或 G.THEME.night

     ★★ 必须同时改的五个地方（漏一个就在深色下露馅）：

       ① 背景（.scene 的 bgColor）—— 它决定了整片天
       ② 文字色（score / over / hint 的 fontColor）
       ③ 文字框【自身背景】（★ R21：文字框必须显式背景色，
          不跟着改就会出现"深色天 + 三条浅色底"）
       ④ 地面线（.ground 的 bgColor）
       ⑤ 所有精灵矩形的 imageColor（恐龙/仙人掌/云/装饰/翼龙/星月）

     ★ 精灵染色为什么要遍历 spNodes：
       它们是 image 控件，颜色存在 imageColor 上，
       和 .scene 的 bgColor 是两条完全不同的通路。

     ⚠️ 不要每帧调用！只在主题【真正切换】时调一次。
        颜色写入虽然便宜（44.9 微秒/次），但这里一次要写
        180+ 个矩形 —— 每帧写就是纯浪费。 ]]--
--[[ 把当前主题的精灵色写到所有精灵矩形上。

     ★★ 关键：这里【不缓存控件引用】，每次都用 rendered.live 现查。

       为什么不能缓存（R28 两次踩坑）：
         节点一旦 display:none，渲染器会把它的控件【还回控件池】
         （标 _orphan），而池子是共享的 —— 那个控件随时会被
         别的节点取走。缓存的引用就指向了别人，染色写错对象，
         而且【不报错】，表现为颜色时对时坏（flaky）。

       每帧现查则永远拿到"当前真正配给这个节点"的控件。
       隐藏中的节点查不到 -> 跳过（它本来就不可见，不需要染色）。

     ⚠️ 这也是"星月用 show/hide 显隐"能成立的前提：
        必须在显示【之后】重新查引用再染色（见 applyTheme 的顺序）。 ]]--
--[[ ★★ 主题切换后的【补染窗口】帧数。

     ⚠️ 为什么需要跨帧补染：
        sky:show() 只改了 DOM 的 display，
        控件是【下一帧 flush】才从池里配给节点的 ——
        那一帧之前渲染器还不知道这个节点，paintSprites 查不到控件。

     所以切换后连着补几帧，直到渲染器把控件配好并染上正确颜色。
     实测 3~6 帧足够；取 6 留余量。 ]]--
local REASSERT_FRAMES = 6
local reassertLeft = 0

local function paintSprites()
  local col = spriteColor()
  for _, list in pairs(spNodes) do
    for i = 1, #list do
      local node = list[i]
      if node then
        local e = uiRef and uiRef.rendered and uiRef.rendered.live
                  and uiRef.rendered.live[node]
        local ctrl = e and e.control
        if ctrl and type(ctrl.SetImage) == "function" then
          pcall(function()
            ctrl.imageColor = Color.FromRGBA(col.r, col.g, col.b, 255)
          end)
        end
      end
    end
  end
end

local function applyTheme(theme)
  S.theme = theme

  -- ① 背景 + ③ 文字框背景（两者同色，视觉上"融"成一片天）
  for _, id in ipairs({ "scene", "score", "over", "hint" }) do
    local nd = nodes[id]
    if nd then nd:setStyle("background-color", theme.bg) end
  end

  -- ② 文字色
  local scoreNd = nodes.score
  if scoreNd then scoreNd:setStyle("color", theme.fg) end
  local overNd = nodes.over
  if overNd then overNd:setStyle("color", theme.fg) end
  local hintNd = nodes.hint
  if hintNd then hintNd:setStyle("color", theme.hint) end

  -- ④ 地面线：跟字色走（截图里地面线就是白色）
  local gnd = nodes.ground
  if gnd then gnd:setStyle("background-color", theme.fg) end

-- ⑤ 所有精灵矩形重新染色
  --
  --[[ ⚠️ 用 spriteCtrls 缓存 + rendered.live 兜底，两者都可能拿不到：
         · display:none 的节点被移出 live
         · 缓存引用的控件可能已被还池、被别的节点取走（_orphan）
       星月常驻显示，所以下一帧就能拿到引用；这里跳过不会留下错色。 ]]
  paintSprites()

  --[[ ★★★ 星月显隐：先 show/hide，再染色（顺序不能反）。

       ⚠️⚠️ 顺序是关键：
         1) 先 sky:show()  -> DOM 的 display 变回 block
         2) 再 paintSprites() -> 此时【下一帧】渲染器才把控件配给节点 …
            ……所以这里要立刻染一次 + 靠 tick 里的补染窗口再补几帧。

       ★ 为什么不用 imageColor 的 alpha=0 当"隐形"：
         实测真机上【无效】—— 白天仍然看得见星月（截图已证）。
         R16 那次 alpha=0 生效是因为那是【裁剪容器（enableMask）】，
         语义是"遮住遮罩图自身的白边"，与"普通图片控件调透明度"不是一回事。
         => 不要从一个场景的实测外推到另一个场景。 ]]--
  local sky = nodes.sky
  if sky then
    if theme.sky then sky:show() else sky:hide() end
  end

  -- 立刻染一次（当天这次能覆盖到非隐藏的普通精灵）
  paintSprites()

  -- 开补染窗口：星月刚显示，控件要下一帧才配好
  reassertLeft = REASSERT_FRAMES
end

--[[ 按已跑距离决定当前该是哪套主题，变了才切。

     ★ 返回 true 表示【这一帧发生了切换】（调用方可用于调试打印）。 ]]--
local function updateDayNight()
  local phase = math.floor(S.dist / G.DAYNIGHT_DIST)
  if phase == S.dayPhase then return false end
  S.dayPhase = phase
  -- 偶数 -> 白天，奇数 -> 夜晚
  local isNight = (phase % 2) == 1
  applyTheme(isNight and G.THEME.night or G.THEME.day)
  return true
end

--=============================================================================
-- ★★ 障碍：把某个槽位切换成指定的类型（换精灵 + 改尺寸 + 改位置）
--=============================================================================

--[[ 改变一个障碍槽的"外观"。

     slot  1..OBS_SLOTS
     o     障碍槽对象（含 rects / w / h / isBird / birdY / 碰撞盒）

     ★ 做法：
       ① 把旧精灵的多余矩形隐藏，再按新精灵的矩形表铺开（setPose）
       ② 改外层容器的尺寸与 top（让底边对齐地面，或放到空中）

     ★★ 与旧版的关键差别：障碍的【矩形表 / 尺寸 / 碰撞盒】
        现在都存在 o 上 —— 因为仙人掌是运行时随机拼的（1~4 株），
        不再是一张固定的 OBS_KINDS 表能描述的。

     ⚠️ 矩形节点数必须 >= 本精灵的矩形数：
        节点按【最坏情况】建（见 HTML 生成处的 OBS_MAX_RECTS），
        这里只需显示前 N 个、其余隐藏。 ]]--
local function applyObstacle(slot, o)
  local wrap = nodes["o" .. (slot - 1)]
  if not wrap or not o then return end

  -- ① 先按新精灵的矩形表铺开（内部会 show/hide 到正确的数量）
  setPose("o" .. (slot - 1) .. "R", o.rects, #o.rects)

  -- ② 定位：地面障碍底边贴地面线；翼龙放空中
  local w = o.w * CELL
  local h = o.h * CELL
  if o.isBird then
    wrap:setStyle("top",  (o.birdY or G.BIRD_YS[1]) .. "px")
  else
    wrap:setStyle("top",  (G.GROUND_LINE - h) .. "px")
  end
  wrap:setStyle("left",  "0px")     -- 实际 x 由每帧 translateX 控制
  wrap:setStyle("width",  w .. "px")
  wrap:setStyle("height", h .. "px")
end

--=============================================================================
-- 每帧逻辑
--=============================================================================

local function tick(dt)
  --[[ ★ 补染窗口：主题刚切换的几帧里继续补色。

       ⚠️ 放在【最前面】且在 started/over 早退之前 ——
          否则游戏结束/未开始时窗口不推进，星月可能停在池里的旧色。 ]]--
  if reassertLeft > 0 then
    reassertLeft = reassertLeft - 1
    paintSprites()
  end

  --[[ ★★★ 每帧补帖图（R29 白块根因修复）。

       ⚠️⚠️ 位置很关键：必须在 tick 的【最开头】。

       原因：引擎每帧 = onTick（本函数）-> flush（渲染建控件）。
          · 生成障碍在【上一帧】的 tick 里发生，那时控件还没建 ->
            reimage 查不到，静默跳过
          · 控件要到那一帧的 flush 才建出来
          => 本帧开头补一次，正好覆盖上一帧刚建出来的控件。

       ★ 覆盖【全部精灵】：恐龙/障碍/云/装饰/星月。
         隐藏的节点由 reassertSprites 内部跳过（其控件可能已还池）。

       ⚠️ 初始（未开始）状态也要补 —— 恐龙此时就该是可见的，
          否则开局第一帧恐龙是白的。所以这行在 S.started 早退之前。 ]]--
  reassertSprites()

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

  --[[ ★ 昼夜更替：按已跑距离决定该白天还是夜里。

       ★ 只在【跨越阈值的那一帧】真正写颜色（updateDayNight 内部判等），
         不在每帧写 —— 见 applyTheme 的注释。 ]]--
  updateDayNight()

  --===========================================================================
  -- ③ 障碍移动（★ 出屏判定用障碍自己的宽度 o.w）
  --===========================================================================
  for i = 1, #S.obs do
    local o = S.obs[i]
    if o.active then
      o.x = o.x - S.speed * dt
      local w = o.w * CELL
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
  --     -> 【无解】（实测公共安全区只有 15px，等同死局）。
  --
  --     所以每次只派一个障碍，且下一个要等足够远（waveGap）——
  --     保证玩家有时间回到地面再跳。
  --
  --   ★★★ 难度曲线（用户要求「开局只有单个仙人掌，往后加鸟和数量/密度」）：
  --       阶段由【已跑距离】决定，逐级放开
  --       【株数上限】【出鸟概率】【鸟档数】【波间隔】。
  --       开局 STAGE_RULES[1].birdChance = 0 -> 绝不出鸟。
  --===========================================================================
  local stage = stageOf(S.dist)
  local rule  = ruleOf(stage)

  -- ★ 下一波的生成距离（记在 S 上，避免用 % 取模 —— 波间隔逐阶段变化）
  if not S.nextSpawnDist then S.nextSpawnDist = rule.waveGap end
  if S.dist >= S.nextSpawnDist then
    for i = 1, #S.obs do
      if not S.obs[i].active then
        local o = S.obs[i]
        o.active = true
        o.x = 1600 + 60

        --[[ 出鸟概率按阶段放开。
             ⚠️ 只在 rule.birdTiers > 0 时才可能出鸟（开局 birdTiers=0）。 ]]
        local isBird = (rule.birdTiers > 0) and (rnd() < rule.birdChance)

        if isBird then
          o.isBird = true
          local k = OBS_KINDS[2]                 -- bird
          o.rects = k.rects
          o.w, o.h = k.w, k.h
          o.hitL, o.hitW = k.hitL, k.hitW
          o.hitT, o.hitH = k.hitT, k.hitH

          --[[ ★ 只从【本阶段开放的档位】里挑。

               前 BIRD_LOW_COUNT 档 = "必须跳"，其余 = "不能跳"。
               阶段 2 只开放前 2 档（都是"必须跳"）——
               先让玩家学会"看到鸟就跳"，再引入"有的鸟不能跳"，
               避免一上来就把两种相反的规则同时丢给玩家。 ]]
          local nTiers = math.min(rule.birdTiers, #G.BIRD_YS)
          local t = math.floor(rnd() * nTiers) + 1
          if t > nTiers then t = nTiers end
          if t < 1 then t = 1 end
          o.birdY = G.BIRD_YS[t]

          o.frame = 1                            -- ★ 三帧扇翅的当前帧
          o.flapTimer = 0
        else
          --[[ ★★★ 仙人掌：运行时随机拼 1~maxStalks 株，
                且组宽受【当前速度的预算】约束（见 makeCactus）。
                这样"株数变多"永远不会变成死局。 ]]
          o.isBird = false
          local c = makeCactus(rule.maxStalks, S.speed)
          o.rects = c.rects
          o.w, o.h = c.w, c.h
          o.hitL, o.hitW = c.hitL, c.hitW
          o.hitT, o.hitH = c.hitT, c.hitH
          o.stalks = c.stalks
          o.birdY = 0
        end

        applyObstacle(i, o)

        -- ★ 排下一波：用【本阶段的波间隔】，加一点随机抖动打散节奏
        S.nextSpawnDist = S.dist + rule.waveGap * (0.85 + rnd() * 0.30)
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
  -- ⑥ 碰撞检测（AABB，用【每个障碍自己的碰撞盒】）
  --
  --[[ ★★ 为什么不能用"控件实际尺寸"：
         点阵四周有空格（鸟的喙只占 2 格、仙人掌组合的株间有空隙）。
         用控件尺寸会导致：看着没碰上，实际已判死；或反过来漏判。

       ★ 所以碰撞盒存在 o 上：
           翼龙        -> 取 OBS_KINDS.bird 的固定盒
           仙人掌组合  -> makeCactus() 按实际点阵【逐列量】出来的盒 ]]
  local dinoL = G.DINO_X
  local dinoR = G.DINO_X + G.DINO_HIT_W
  local dinoT = S.y + G.DINO_HIT_T
  local dinoB = S.y + G.DINO_HIT_B

  for i = 1, #S.obs do
    local o = S.obs[i]
    if o.active then
      local h = o.h * CELL
      -- 容器的 top：地面障碍贴地，翼龙在指定高度
      local top
      if o.isBird then
        top = o.birdY or G.BIRD_YS[1]
      else
        top = G.GROUND_LINE - h
      end

      local obsL = o.x + (o.hitL or 0)
      local obsR = obsL + (o.hitW or (o.w * CELL))
      local obsT = top + (o.hitT or 0)
      local obsB = obsT + (o.hitH or h)

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

        --[[ ★★ 翼龙扇翅：三帧循环（抬 -> 半收 -> 放 -> 半收 -> 抬）。

             ★ 帧表统一从 sprite.birdFrames() 取 ——
               避免"demo 里抄一份帧表、库里改一份"两边不一致。

             ⚠️ 换姿态要传 reimageNode（apply 内部会在"从隐藏变显示"时
                重贴图，否则控件池回收后图丢了 -> 缺一块）。 ]]
        if o.isBird then
          o.flapTimer = (o.flapTimer or 0) + 1
          if o.flapTimer >= G.BIRD_FLAP then
            o.flapTimer = 0
            local frames = sprite.birdFrames()
            local f = (o.frame or 1) + 1
            if f > #frames then f = 1 end
            o.frame = f
            local rects = frames[f]
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
    --[[ ★★ 重开必须【立刻回到白天】（R28 修）。

         ⚠️ 踩过的坑：死在黑天时重开，背景仍是黑的。
           原因：reset() 只是把 S.dayPhase / S.theme 改成白天，
           但【没有把主题写进 DOM】—— 真正改颜色的是 applyTheme。
           而 updateDayNight 只在 phase【变化】时才调 applyTheme，
           reset 后 dist=0 -> phase=0 与 S.dayPhase=0 相同 ->
           它认为"没变化"，于是永远不刷新。

         ★ 所以这里显式应用一次白天主题。 ]]--
    applyTheme(G.THEME.day)
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
      -- ★ 星空：月亮 + 每颗星（前缀与 skyHTML 的生成一致）
      mnR = #sprite.moonRects(),
    }
    for i = 1, #SKY_STARS do
      prefixes["st" .. i .. "R"] =
        SKY_STARS[i][3] and #sprite.starRects() or #sprite.starSmallRects()
    end
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
            --[[ ★★★ 立刻把控件引用存下来（R28）。
                 这是昼夜更替能工作的前提 —— 之后 applyTheme
                 直接写这个引用，不再依赖 rendered.live
                 （星月白天隐藏会被移出 live，反查会失败）。 ]]
            rememberCtrl(node, ctrl)
            if pcall(function() ctrl:SetImage(
                clip.imageSource(), 100001) end) then
              -- 染成当前主题的精灵色（白天深灰 / 夜里浅灰）
              pcall(function() ctrl.imageColor = spriteColor() end)
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

    --[[ 障碍槽先按【最坏情况的矩形表】铺满（隐藏状态）。

         ⚠️ 必须用 OBS_TEMPLATE_RECTS（= 矩形最多的那一组），
            否则切到"矩形更多"的精灵时会缺一块。
         第一次生成时 applyObstacle 会覆盖成实际精灵。 ]]
    for i = 1, OBS_SLOTS do
      setPose("o" .. (i - 1) .. "R",
              OBS_TEMPLATE_RECTS, #OBS_TEMPLATE_RECTS)
    end

    -- 地面装饰：铺上各自的图案
    for i = 1, DECO_SLOTS do
      local dk = DECO_KINDS[S.decos[i].kind]
      setPose("p" .. (i - 1) .. "R", dk.rects, #dk.rects)
      local nd = nodes["dc" .. (i - 1)]
      if nd then nd:setStyle("width", (dk.w * CELL) .. "px") end
    end

    --[[ ★★ 应用初始主题（开局是白天）。

         ⚠️ 必须放在【所有精灵都贴完图之后】——
            applyTheme 会遍历 spNodes 染色，先于贴图调用的话
            那些控件的 imageColor 会被贴图流程用 spriteColor() 覆盖，
            结果虽然也对（spriteColor 读的就是 S.theme），
            但会多写一遍 180+ 个控件。
         这里放在最后，一次到位。 ]]--
    applyTheme(G.THEME.day)

    print(string.format("[dino] 就绪：恐龙 %d 矩形，障碍 %d 种，槽位上限 %d 矩形",
        #SP.dino.rects, #OBS_KINDS, OBS_MAX_RECTS))
    print(string.format("[dino] 贴方形图 %d / %d（image 模式，绕开文本框圆角）",
        okCount, total))
    print(string.format("[dino] 昼夜：每 %dpx 切换一次（开局白天）",
        G.DAYNIGHT_DIST))
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
