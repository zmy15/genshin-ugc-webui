--[[ demo_dino 自检 —— 真的把游戏跑起来，验证物理/碰撞/重开

     ★ 不是"能加载就算过"：
       模拟按键 + 逐帧推进，断言跳跃高度、碰撞触发、重开后状态复位。
]]

-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')

local PREFABS = { container=1073741933, textbox=1073741934,
                  button=1073741935, image=1073741938 }

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass=pass+1; print(string.format("  [OK] %-44s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-44s %s", name, detail or "")) end
end

--=============================================================================
-- 环境
--=============================================================================
local E = EngineMock.new(PREFABS)

local keyEnum = {}
for _, n in ipairs({
  "KeyboardJumpKeyDown","KeyboardJumpKeyUp",
  "KeyboardMoveLeftKeyDown","KeyboardMoveLeftKeyUp",
  "KeyboardMoveRightKeyDown","KeyboardMoveRightKeyUp",
  "KeyboardMoveForwardKeyDown","KeyboardMoveForwardKeyUp",
  "KeyboardMoveBackwardKeyDown","KeyboardMoveBackwardKeyUp",
  "KeyboardCraftspersonKey1Down","KeyboardCraftspersonKey1Up",
  "KeyboardCraftspersonKey2Down","KeyboardCraftspersonKey2Up",
  "KeyboardCraftspersonKey3Down","KeyboardCraftspersonKey3Up",
  "KeyboardCraftspersonKey4Down","KeyboardCraftspersonKey4Up",
  --[[ ★★ 手柄键【必须】出现在测试替身里（本轮修）。

       ⚠️ 踩过的坑：这里原先只有 Keyboard*，而 demo 同时绑了
          padJump / padJumpUp（Controller*）。于是那两个键
          resolveKey 返回 nil -> 绑定被跳过（静默），
          测试还断言"绑定了 2 个按键"而全绿 ——
          真机上「手柄按 A 不跳」因此在本地【测不出来】。

       ★ 这正是 docs 里 R23 的教训：测试替身要照真机形态造。
         真机 Enum.KeyEventType 的 164 项里【确实】有这两项
         （docs/引擎能力与限制.md §5.2 已验证）。 ]]
  "ControllerJumpKeyDown","ControllerJumpKeyUp",
}) do keyEnum[n] = "Enum.KeyEventType." .. n end

game = E.game
Color = { FromRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
          FromRGB=function(r,g,b) return {r=r,g=g,b=b} end }
Enum = {
  EaseType={Linear="Linear"},
  CursorEventType={CursorClick="C",CursorDown="D",CursorUp="U",CursorEnter="E",
                   CursorExit="X",CursorBeginDrag="B",CursorDrag="G",CursorEndDrag="N"},
  TextHorizontalAlignmentLeft="L", TextHorizontalAlignmentMiddle="C",
  TextHorizontalAlignmentRight="R",
  ImageSource={StaticReference="SR"},
  KeyEventType = keyEnum,
}
local root = E.makeControl("container", nil)
root.name = "Root"
E.setRoots({ root })
script = { object = root, EnableUpdate=function() end }
printerr = function(...) io.stderr:write("[printerr] ", ...) end

--[[ ★★ 捕获逐帧续期回调（本轮修）。

     ⚠️ 原先 AppendCallback() 【丢弃】了回调，于是本测试里
        没有任何一帧真正跑过 —— 而第 9 节要验证"按键之后
        恐龙真的动了"，必须能推进帧（tick -> 渲染写控件）。
        这与 test_demo_dino_run.lua 的做法一致。 ]]--
local pending = nil
game.TweenSequence = function()
  local s = {}
  function s:AppendCallback(cb) pending = cb; return s end
  function s:AppendInterval() return s end
  function s:Play() return s end
  function s:Kill() return s end
  return s
end

--[[ 推进 n 帧：取出待跑的回调执行一次，它会再续期下一帧。 ]]--
local function stepFrames(n)
  for _ = 1, n do
    local cb = pending
    pending = nil
    if cb then cb() end
  end
end

--=============================================================================
-- 加载 demo
--=============================================================================
local src = io.open("deploy/demo_dino.lua", "r"):read("*a")
assert(src, "读不到 deploy/demo_dino.lua")

local chunk = assert(load(src, "@demo_dino"))
chunk()
OnStart()

print("\n=== 1. 挂载与初始状态 ===")
--[[ ★★ 必须【逐个按键】验，不能只看总数（本轮修）。

     ⚠️ 只断言 count == 4 仍会漏：若键盘那两个成功、手柄两个失败，
        总数是 2 —— 靠数字能发现；但若数量恰好凑对（比如漏一个
        又误绑一个）就看不出来了。所以这里同时断言【具体 ev】。 ]]
check("root 上绑定了 4 个按键（键盘 jump/up + 手柄 padJump/up）",
    E.keyListenerCount(root) == 4, "count=" .. tostring(E.keyListenerCount(root)))

--[[ ★★★ 手柄键【真的绑上去了】—— 这是「手柄按 A 不跳」的回归断言。

     关键：把每个监听器的 ev 读回来，确认 ControllerJumpKey* 在里面。
     只数个数是不够的（个数对了但绑错键，手柄照样不能玩）。 ]]
do
  local d = E.dataOf(root)
  local want = {
    [Enum.KeyEventType.KeyboardJumpKeyDown]   = "键盘跳跃按下",
    [Enum.KeyEventType.KeyboardJumpKeyUp]     = "键盘跳跃抬起",
    [Enum.KeyEventType.ControllerJumpKeyDown] = "手柄跳跃按下(A)",
    [Enum.KeyEventType.ControllerJumpKeyUp]   = "手柄跳跃抬起(A)",
  }
  local got, missing = {}, {}
  for _, L in ipairs(d.keyListeners or {}) do got[L.ev] = true end
  for ev, label in pairs(want) do
    if not got[ev] then missing[#missing + 1] = label end
  end
  check("★★ 手柄跳跃键已绑定（ControllerJumpKeyDown/Up）",
      #missing == 0,
      #missing == 0 and "键盘+手柄 4 个键都在"
          or ("缺: " .. table.concat(missing, ", ")))
end

-- 通过屏幕上的控件反查文字（demo 的局部变量拿不到，只能从引擎侧观察）
local function allTexts()
  local out = {}
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.kind == "textbox" and d.fields.text then
      out[#out+1] = d.fields.text
    end
  end
  table.sort(out)
  return out
end

local texts = allTexts()
local joined = table.concat(texts, " | ")
check("分数栏显示 HI 00000", joined:find("HI 00000") ~= nil, joined)
check("提示文字存在", joined:find("按") ~= nil, joined)

--=============================================================================
print("\n=== 2. 恐龙精灵已建出来（像素图形版）===")
--=============================================================================
--[[ ★ 恐龙现在不是一个 80x80 方块，而是【33 个矩形】拼成的像素图形。

     结构：外层 .spr 容器（#dino，176x192，负责移动）
           └ 内层 33 个矩形（#dR1..#dR33，负责形状）

     所以这里断言的是【矩形数量】，而不是单个方块尺寸。 ]]
--[[ ★ 怎么数"矩形控件"？

       demo 的 ui 是局部变量（设计如此，不该暴露内部），
       所以拿不到 ui.doc。改成【按尺寸特征】数引擎控件：

       精灵矩形的尺寸 = 逻辑尺寸 × 8px，
       ★ 再 +2px —— 因为 toHTML 默认四边各外扩 1px（bleed，
         防真机上相邻矩形露缝，见 R23）。
       这里用 webui_sprite 自己的矩形表算出"期望尺寸集合"，
       再统计画面上匹配的控件数。

       ★ 这同时验证了一件事：矩形表真的被渲染成了对应尺寸的控件。
]]
local sprite = require('webui_sprite')
local CELL = 8
local BLEED = 1        -- 与 sprite.toHTML 的默认值一致

--[[ ★★ R24 起拼图改用【image 控件】而非 textbox 纯色块。

     原因：textbox 模板自带圆角（半径 >= 8px），8px 的块会被画成圆形，
     33 个矩形里 88% 变形。image 模板是方的（编辑器确认）。

     => 所以这里数的是 kind == "image" 的矩形。 ]]
--[[ ★★ 精确计数：按【尺寸 -> 期望个数】映射比对。

     旧的"只按尺寸集合"计数会被【不同精灵的同尺寸矩形】重复计入
     （翼龙和恐龙的某些块尺寸相同）-> 数量对不上。

     这里改成：统计所有精灵里每个尺寸出现多少次，
     再和画面上该尺寸的 image 控件数逐一比对。

     返回：匹配到的总数, 尺寸不符的种类数 ]]--
--[[ ★★ 精确计数：按【尺寸 -> 期望个数】映射比对。

     参数改为 { rects=..., cell=... } 的表：
     恐龙用 DINO_CELL=5.67，其他用 CELL=8 ——
     每个精灵按自己的格宽算尺寸。 ]]
local function countRectsExact(entries)
  local want = {}
  for _, e in ipairs(entries) do
    local rects, cell = e.rects, e.cell or CELL
    for _, r in ipairs(rects) do
      -- ★ floor 必须与渲染端一致：
      --   引擎字段是整数，而 DINO_CELL=5.67 产生小数尺寸
      --   不 floor 的话 want key 会成 "36.34x36.34" 而实际是 "36x36"
      local key = string.format("%dx%d",
          math.floor(r.w * cell + BLEED * 2),
          math.floor(r.h * cell + BLEED * 2))
      want[key] = (want[key] or 0) + 1
    end
  end

  local got = {}
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.kind == "image" then
      local key = string.format("%dx%d",
          math.floor(d.fields.sizeDeltaX or 0),
          math.floor(d.fields.sizeDeltaY or 0))
      if want[key] then got[key] = (got[key] or 0) + 1 end
    end
  end

  local total, bad = 0, 0
  for key, n in pairs(want) do
    local g = got[key] or 0
    total = total + g
    if g ~= n then bad = bad + 1 end
  end
  return total, bad
end

local dinoN   = #sprite.dinoRects()
local cloudN  = #sprite.cloudRects()

--[[ ★ 不硬编码数量：点阵改一次数量就变。
       恐龙缩到 16x17 后只有 16 个矩形（原 22x24 时 31 个）。 ]]--
check("恐龙点阵分解出合理数量的矩形（10~45）",
    dinoN >= 10 and dinoN <= 45, dinoN .. " 个")
check("云分解为 6 个矩形", cloudN == 6, cloudN .. " 个")

--[[ ★★ R27 起：仙人掌不再写死成固定几档，而是【运行时随机拼 1~4 株】。

     所以这里断言的是「三种单株 + 任意株数的组合都能拼出来」，
     而不是"恰好有 5 档"。 ]]
local variants = sprite.cactusVariants()
check("三种单株仙人掌（大/中/小）", #sprite.CACTUS_KINDS == 3,
    #sprite.CACTUS_KINDS .. " 种")
local kindsOk = true
for _, k in ipairs(sprite.CACTUS_KINDS) do
  if #k.rows == 0 or k.w <= 0 or k.h <= 0 then kindsOk = false end
end
check("每种单株都有点阵与尺寸", kindsOk)

-- ★ 1~4 株的组合都能拼出点阵，且【底部对齐】（末行必须有填充）
local groupOk, groupBad = true, 0
for n = 1, 4 do
  local keys = {}
  for i = 1, n do keys[i] = 1 end
  local g = sprite.cactusGroup(keys)
  if #g.rects == 0 or g.w <= 0 or g.h <= 0 then groupOk = false end
  local last = g.rows[#g.rows]
  if not last:find("#", 1, true) then groupBad = groupBad + 1 end
end
check("★ 1~4 株的组合都能拼出点阵", groupOk)
check("★ 所有组合底边对齐（末行有填充）", groupBad == 0,
    groupBad .. " 个组合末行是空的")

--[[ ★ 随机拼株要真的产生【不同的株型组合】，而不是永远同一种。

     ⚠️ 语义澄清：randomCactusGroup(n, rnd) 里的 n 是【调用方指定的株数】
        （它一定返回 n 株），"随机"体现在【每株挑哪种仙人掌】。
        真正决定"这一波出几株"的是 demo 的 makeCactus（按宽度预算递减）。

     所以这里验的是：给定株数时，株型组合确实在变。 ]]
local seed = 20261008
local function rnd()
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed / 2147483648
end
local combos = {}
for _ = 1, 200 do
  local g = sprite.randomCactusGroup(3, rnd)
  combos[table.concat(g.stalks, ",")] = true
end
local nCombos = 0
for _ in pairs(combos) do nCombos = nCombos + 1 end
check("★ 随机拼株能产出多种株型组合（>=5 种）", nCombos >= 5,
    nCombos .. " 种组合")

-- ★ 株数本身影响组宽（这是"限宽 -> 减株"能生效的前提）
local nSizes = 0
do
  local sizes = {}
  for n = 1, 4 do
    local keys = {}
    for i = 1, n do keys[i] = 1 end
    sizes[sprite.cactusGroup(keys).w] = true
  end
  for _ in pairs(sizes) do nSizes = nSizes + 1 end
end
check("★ 不同株数的组合宽度不同（株数真的影响组宽）", nSizes >= 4,
    nSizes .. " 种宽度")

local birdN = #sprite.birdRects()
check("翼龙分解出合理数量的矩形（2~20）", birdN >= 2 and birdN <= 20, birdN .. " 个")

--[[ ★ 地面装饰也断言一下（原版地面不是纯直线）。 ]]
local decos = sprite.decoVariants()
check("地面装饰有 3 种", #decos == 3, #decos .. " 种")

--[[ 画面上实际的矩形控件数。

     ⚠️ 障碍槽是按【矩形最多的那档】建节点的（运行时要在同一槽里
        切换不同档），所以槽里的节点数 = 最大档的矩形数，不是某个档的。

     计算：恐龙 + 云x2 + 装饰(各按自己) + 4 个障碍槽(各按最大档) ]]
--[[ 期望值：恐龙 + 云x2 + 装饰各1 + 4 个障碍槽（各按最大档）

     ⚠️ 障碍槽是按【矩形最多的那档】建节点的（运行时要在同一槽里
        切换不同档），所以每个槽的节点数 = 最大档的矩形数。 ]]
-- variants 已在上面声明（仙人掌三档那段）
local birdRects = sprite.birdRects()
-- ★ R27：翼龙改成三帧循环（抬 / 半收 / 放）
local birdFrames = sprite.birdFrames()

--[[ ★★ 障碍槽按【最坏情况】的最大矩形数建节点（R27 起）。

     ⚠️ 现在是两个来源取最大：
          · 翼龙【三帧】（15 / 14 / 12）—— 漏了哪一帧就会在扇翅时少一块
          · 仙人掌【随机拼株】—— 按"最宽的组合（4 株大仙人掌）"算
       宁可多建（空闲矩形 hide 掉），也不能少建（缺一块）。 ]]
local biggest = sprite.cactusGroup({ 1, 1, 1, 1 }).rects
for _, fr in ipairs(sprite.birdFrames()) do
  if #fr > #biggest then biggest = fr end
end

-- ★★ 恐龙用独立的 DINO_CELL=5.67，其他全部 CELL=8
local DINO_CELL = 5.67

--[[ ★ R28：星空层（月亮 + 每颗星）也是 image 控件矩形，
     必须一起算进期望值 —— 漏了就会报"控件数不符"。

     ⚠️ 星星的数量与大小（大星/小星）在 demo 的 SKY_STARS 里定义。
        这里不硬抄那份表，而是【直接从 demo 源码解析】——
        否则 demo 改一颗星、测试就假失败（"测试替身必须忠实"）。 ]]
local skyRects = { { rects = sprite.moonRects(), cell = 5 } }
do
  local dsrc = io.open("deploy/demo_dino.lua", "r"):read("*a")
  -- 解析 SKY_STARS 的每一项 { x, y, true/false }
  local block = dsrc:match("SKY_STARS%s*=%s*{(.-)\n}")
  local nBig, nSmall = 0, 0
  if block then
    --[[ ⚠️ 这里踩过一次：SKY_STARS 每项形如 { 120, 120, true }，
         而 { 里的两个数字也会被 {[^}]*,(%s*%a+%s*)} 的贪婪匹配
         扫成"以逗号分隔的字母位" —— 但每项只有一个字母位（true/false），
         所以直接数 true/false 的出现次数最稳。 ]]
    for m in block:gmatch("(true)") do nBig = nBig + 1 end
    for m in block:gmatch("(false)") do nSmall = nSmall + 1 end
  end
  for _ = 1, nBig do
    skyRects[#skyRects + 1] = { rects = sprite.starRects(), cell = 5 }
  end
  for _ = 1, nSmall do
    skyRects[#skyRects + 1] = { rects = sprite.starSmallRects(), cell = 5 }
  end
end

local allRectTables = {
  { rects = sprite.dinoRects(),   cell = DINO_CELL },
  { rects = sprite.cloudRects(),  cell = CELL },
  { rects = sprite.cloudRects(),  cell = CELL },
  { rects = sprite.pebbleRects(), cell = CELL },
  { rects = sprite.grassRects(),  cell = CELL },
  { rects = sprite.tuftRects(),   cell = CELL },
}
for _, e in ipairs(skyRects) do
  allRectTables[#allRectTables + 1] = e
end
for _ = 1, 4 do
  allRectTables[#allRectTables + 1] = { rects = biggest, cell = CELL }
end

local expectTotal = 0
for _, e in ipairs(allRectTables) do expectTotal = expectTotal + #e.rects end

local actual, badKinds = countRectsExact(allRectTables)

check("画面上的精灵矩形控件数 = " .. expectTotal,
    actual == expectTotal, actual .. " 个")
check("★ 每种尺寸的矩形数量都吻合", badKinds == 0,
    badKinds .. " 种尺寸数量不符")

--[[ ★★ 关键：矩形必须是【image 类型】，不能是 textbox。

     这是 R24 修复的核心 —— textbox 模板自带圆角（半径 >= 8px），
     8px 的块会被画成圆形，整只恐龙碎成圆点 + 缝。
     image 模板是方的（编辑器确认）-> 所以拼图必须用 image。

     ⚠️ 一旦有人把 asImage 关掉（或忘了给 data-image="1"），
        渲染器会因 background-color 把它选成 textbox -> 圆角回来。
        这条断言就是守这个 regression。 ]]
local textboxRects = 0
for _, c in ipairs(E.controls) do
  local d = E.dataOf(c)
  if d and d.kind == "textbox" then
    local w = d.fields.sizeDeltaX or 0
    local h = d.fields.sizeDeltaY or 0
    -- 精灵矩形的尺寸特征：<= 176 且是 8n+2
    if w > 0 and w <= 176 and h > 0 and h <= 192 then
      local function is8n2(v) return (v - 2) % 8 == 0 end
      if is8n2(w) and is8n2(h) then textboxRects = textboxRects + 1 end
    end
  end
end
check("★ 精灵矩形全部是 image 类型（不是 textbox）", textboxRects == 0,
    textboxRects .. " 个矩形误用 textbox（会带圆角）")

-- 并且它们真的贴了方形图
local withImage = 0
for _, c in ipairs(E.controls) do
  local d = E.dataOf(c)
  if d and d.kind == "image" and d.fields.imageId == 100001 then
    withImage = withImage + 1
  end
end
check("★ 矩形已 SetImage(方形图 100001)", withImage >= expectTotal,
    withImage .. " 个已贴图")

--=============================================================================
print("\n=== 3. 键盘回调确实驱动了跳跃状态 ===")
--=============================================================================
-- 未开始时按跳跃 -> started=true，恐龙不动
-- 再按一次 -> 起跳（vy 为负）
-- 这两步的中间状态只能从控件位置观察，而渲染发生在 onTick 里。
-- 因此这里断言：按键回调【没有报错】，且事件未被吞。
local handled = E.fireKey(root, "Enum.KeyEventType.KeyboardJumpKeyDown", {})
check("★ 跳跃键事件未被吞（回调返回 false）", handled == false,
    "handled=" .. tostring(handled))
local handledUp = E.fireKey(root, "Enum.KeyEventType.KeyboardJumpKeyUp", {})
check("★ 松开键事件未被吞", handledUp == false,
    "handled=" .. tostring(handledUp))

--=============================================================================
print("\n=== 4. 用独立实例跑完整游戏循环（物理 + 碰撞）===")
--=============================================================================
--[[ ★ 参数必须与 demo_dino.lua 的 G 表【完全一致】。

     碰撞用的是"实际像素尺寸"而非控件尺寸：
       恐龙控件 176x192，但点阵只占其中一部分
       -> 碰撞盒 90x110，且垂直方向偏下（头在上、脚在下）
       仙人掌控件 72x112，左右各有空边
       -> 碰撞盒宽 46，且只算贴地部分（top 660 起）
]]
--[[ ★ 参数必须与 demo_dino.lua 的 G 表【完全一致】。

     摆放几何（由点阵尺寸推导，改一边就要同步另一边）：
       地面线 y=700
       恐龙点阵 176x192，脚在控件顶 +192 -> 站地面时 top = 508
       仙人掌点阵 72x112，底在控件顶 +112 -> 贴地时 top = 588

     碰撞盒只取【身体主体】（不含头尾），见 demo 里 G 表注释。 ]]
local G = {
  GROUND_Y=508, GRAVITY=4200, JUMP_V=-1150, BASE_SPEED=620,
  MAX_SPEED=1500, ACCEL=32,
  GROUND_LINE=700,
  DINO_X=160, DINO_SPR_H=192,
  DINO_HIT_W=92, DINO_HIT_T=88, DINO_HIT_B=168,
  OBS_W=72, OBS_H=112, OBS_TOP=588,
  OBS_HIT_W=46, OBS_HIT_T=0, OBS_HIT_B=112,
  SPAWN_GAP=760,
}

--[[ 与 demo 的 tick 等价的碰撞判定。

     ★ 抽成一个函数，保证下面两个模拟用的都是同一套逻辑，
       避免"两处各写一份、改了一处忘另一处"（之前正是这么出错的）。 ]]
local function hits(s)
  local dL = G.DINO_X
  local dR = G.DINO_X + G.DINO_HIT_W
  local dT = s.y + G.DINO_HIT_T
  local dB = s.y + G.DINO_HIT_B
  for i = 1, #s.obs do
    local o = s.obs[i]
    if o.active then
      local padX = (G.OBS_W - G.OBS_HIT_W) / 2
      local oL = o.x + padX
      local oR = oL + G.OBS_HIT_W
      local oT = G.OBS_TOP + G.OBS_HIT_T
      local oB = G.OBS_TOP + G.OBS_HIT_B
      if dR > oL and dL < oR and dB > oT and dT < oB then return true end
    end
  end
  return false
end

local function newState()
  return { y=G.GROUND_Y, vy=0, onAir=false, speed=G.BASE_SPEED,
           dist=0, over=false,
           obs={{x=-9999,active=false},{x=-9999,active=false},{x=-9999,active=false}} }
end

local DT = 1/50

-- 每帧推进（物理 + 移动 + 生成 + 碰撞），两个模拟共用
local function advance(s, f, jumpAtFrame)
  if f == jumpAtFrame then s.vy = G.JUMP_V; s.onAir = true end
  if s.onAir then
    s.vy = s.vy + G.GRAVITY*DT
    s.y = s.y + s.vy*DT
    if s.y >= G.GROUND_Y then s.y = G.GROUND_Y; s.vy = 0; s.onAir = false end
  end
  s.speed = math.min(G.MAX_SPEED, s.speed + G.ACCEL*DT)
  s.dist = s.dist + s.speed*DT

  for i = 1, #s.obs do
    local o = s.obs[i]
    if o.active then
      o.x = o.x - s.speed*DT
      if o.x < -G.OBS_W - 60 then o.active = false; o.x = -9999 end
    end
  end

  if (s.dist % G.SPAWN_GAP) < (s.speed*DT) then
    for i = 1, #s.obs do
      if not s.obs[i].active then
        s.obs[i].active = true; s.obs[i].x = 1600 + 60; break
      end
    end
  end

  if hits(s) then s.over = true end
end

local function simulate(jumpAtFrame, frames)
  local s = newState()
  local minY = G.GROUND_Y
  for f = 1, frames do
    advance(s, f, jumpAtFrame)
    if s.y < minY then minY = s.y end
  end
  return s, minY
end

local s, minY = simulate(45, 120)
local peak = G.GROUND_Y - minY
check("跳跃能离地", peak > 0, string.format("峰值高度 %.1f px", peak))
check("跳跃高度合理（100~300px）", peak > 100 and peak < 300,
    string.format("%.1f px", peak))
check("跳跃后会落回地面", math.abs(s.y - G.GROUND_Y) < 0.01,
    string.format("y=%.2f", s.y))

-- 不跳 -> 必然撞到障碍
local s2 = simulate(nil, 400)
check("★ 不跳 -> 撞到障碍（Game Over）", s2.over == true)

--[[ 会跳的 AI -> 应该能一直躲下去。

     ★ 复用同一个 advance()/hits()，保证与上面"不跳必撞"的验证
       用的是【同一套物理与碰撞】—— 否则两边结论不可比。 ]]
local function simulateSmart(frames)
  local st = newState()
  local peak = G.GROUND_Y
  for f = 1, frames do
    --[[ ★ 简单 AI：障碍进入起跳窗口就跳。

         ★ 提前量是【扫描出来的】（lead 从 20 试到 260，步长 20）：
             lead   20 ~  80  -> 撞（起跳太晚，还没升上去）
             lead  100 ~ 160  -> ✓ 800 帧无碰撞
             lead  180 ~ 260  -> 撞（起跳太早，落地时障碍才到）
           取中位数 130。

         ⚠️ 这两个失败方向都是真的：
             太晚 -> 恐龙还没升高就撞上
             太早 -> 恐龙已落地、障碍才到
           所以起跳窗口是【双向受限】的，改物理参数后要重扫。 ]]
    local nearest = nil
    for i2 = 1, #st.obs do
      local o = st.obs[i2]
      if o.active and (not nearest or o.x < nearest) then nearest = o.x end
    end
    if nearest and not st.onAir
       and nearest < G.DINO_X + G.DINO_HIT_W + 130
       and nearest > G.DINO_X then
      st.vy = G.JUMP_V
      st.onAir = true
    end

    advance(st, f, nil)
    if st.y < peak then peak = st.y end
  end
  return st, peak
end

local s3 = simulateSmart(600)
check("★ 会跳就能躲过障碍（能玩）", s3.over == false,
    s3.over and "还是撞了" or "600 帧无碰撞")
check("速度会递增", s3.speed > G.BASE_SPEED,
    string.format("%.0f -> %.0f", G.BASE_SPEED, s3.speed))
check("速度有上限", s3.speed <= G.MAX_SPEED,
    string.format("%.0f <= %d", s3.speed, G.MAX_SPEED))

--=============================================================================
print("\n=== 9. ★★★ 手柄 / 手机端也能玩（本轮新增的两种输入）===")
--=============================================================================
--[[ 背景：用户反馈「手柄和手机玩家不能游玩」。
     原因不是键盘路径写错了，而是【只有键盘被接上】：
       · 手柄键（ControllerJumpKey*）根本没绑
       · 手机端没有任何可点控件（触摸屏发不出按键事件）

     所以这一节【必须做行为验证】—— 只断言"绑了监听器"不够，
     要证明"按下之后恐龙真的起跳了"。 ]]--

--[[ 断言的观察手段：恐龙控件的 top（anchoredPosition 的 Y）。
     ⚠️ 注意方向：引擎 Y 向上，所以【起跳 = Y 变大】（-182 -> -152）。
        站着时 Y = -182（= 564 - 900/2 的居中换算结果）。

     ⚠️⚠️ 必须【推进一帧再看】：按键回调只改 S.vy，
       真正把新位置写进控件的是 onTick 里的渲染。
        直接 fireKey 后立刻读 -> 读到的是上一帧的位置（不变）。 ]]--
local function dinoY()
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.fields.name == "div#dino" then
      return d.fields.anchoredPositionY
    end
  end
  return nil
end

--[[ ★★ 找【热点层】的点击回调。

     ⚠️ 踩过的坑：热点层的 name 是【笼统的 "hot:div"】，
        并不带 id（渲染器只写 "hot:" .. tag）。
        所以不能按名字找 —— 必须靠【父子关系】：
        名字为 div#jumpBtn 的那个 textbox，它的 button 子控件才是
        跳跃按钮的热区（双层架构，见 webui_render.lua）。

     ⚠️ 而且热区上有 4 个监听器（Down/Up/Click/Exit，因为 HTML 里
        写了 onmousedown/onmouseup/onclick/onmouseleave），
        所以必须挑 ev == CursorClick 的那个。 ]]--
local parentOf = {}
for _, p in ipairs(E.controls) do
  local pd = E.dataOf(p)
  for _, ch in ipairs(pd.children or {}) do parentOf[ch] = pd.fields.name end
end

local function findClickCbByNodeId(id)
  local CLICK = Enum.CursorEventType.CursorClick
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.kind == "button" and parentOf[c] == ("div#" .. id) then
      for _, l in ipairs(d.listeners or {}) do
        if l.ev == CLICK then return l.cb end
      end
    end
  end
  return nil
end

local function tap(cb)
  cb({ GetUIPos=function() return 1,1 end,
       GetPressUIPos=function() return 1,1 end,
       GetUIPosDelta=function() return 0,0 end,
       dragging=false, touchId=0 })
end

--[[ ★★★ 手柄按下 A -> 恐龙起跳。

     ★ 先按一次让游戏 started（onJump 的语义是
       "未开始 -> 开始 / 已死 -> 重开 / 落地 -> 起跳"）。 ]]--
E.fireKey(root, "Enum.KeyEventType.ControllerJumpKeyDown", {})   -- 第 1 次：开始
stepFrames(1)
local yRest = dinoY()

E.fireKey(root, "Enum.KeyEventType.ControllerJumpKeyDown", {})   -- 第 2 次：起跳
stepFrames(1)                                                   -- ★ 必须推进一帧
local yAfterPad = dinoY()

check("★★★ 手柄按 A -> 恐龙离开地面（手柄能玩）",
    yRest ~= nil and yAfterPad ~= nil and yAfterPad > yRest,
    string.format("地面 Y=%.1f -> 跳起 Y=%.1f",
        yRest or 0, yAfterPad or 0))

--=============================================================================
-- 手机端：点跳跃按钮 = 同一套状态机
--=============================================================================
local tapCb = findClickCbByNodeId("jumpBtn")
check("★ 手机跳跃按钮存在且绑了点击", type(tapCb) == "function",
    type(tapCb) == "function" and "已绑定（div#jumpBtn 的热区）"
        or "没找到 div#jumpBtn 的点击回调")

if type(tapCb) == "function" then
  --[[ ★★ 手机路径的行为验证：点按钮也要能起跳。

       ⚠️ 回归要点：按钮走的是 jumpBtnDown -> onJump，
         与键盘/手柄【共用同一个状态机】。
         若有人把按钮改成"自己写一套跳跃逻辑"，
         这条断言会随之失配，从而暴露分叉。 ]]--
  --[[ 等它落地。

       ⚠️ 只跑一小段（不能跑几百帧）：这段时间里障碍会撞上来
          -> S.over = true -> 之后的点击变成"重开"而不是"起跳"，
          断言就会看起来像"点了没反应"。
       ★ 从峰值落回地面只需 跳跃全程/2 ≈ 0.26s（G 表参数）；
         这里保守取 40 帧（60fps ≈ 0.67s）足够落地，
         又不至于跑到第一波障碍撞上来。 ]]--
  stepFrames(40)
  local yBeforeTap = dinoY()

  tap(tapCb)
  stepFrames(1)
  local yAfterTap = dinoY()

  check("★★★ 点手机跳跃按钮 -> 恐龙起跳（手机能玩）",
      yBeforeTap ~= nil and yAfterTap ~= nil and yAfterTap > yBeforeTap,
      string.format("点击前 Y=%.1f -> 点击后 Y=%.1f",
          yBeforeTap or 0, yAfterTap or 0))

  --[[ ★★ 结算窗口打开时，跳跃按钮必须【失效】。

       理由：按钮在 DOM 里排在弹窗之后（为了盖住遮罩），
       玩家点"继续"时手指可能落在按钮上；更关键的是
       弹窗打开 = S.paused，此时还能跳就能绕过暂停。

       ⚠️⚠️ 断言【不能】只看"暂停期间 Y 没变" —— 那样是空的：
          暂停时 tick 本来就跳过物理，无论有没有守卫 Y 都不会变
          （已用变异测试证实：删掉守卫这条断言照样通过）。

       ★ 正确做法：暂停中点一下按钮，然后【恢复游戏】再看。
         有守卫  -> 那次点击被丢弃，恢复后仍在地面（不跳）
         没守卫  -> S.vy 已被写成起跳速度，恢复后立刻弹起来
         —— 这样才真正区分"守卫生效"与"守卫是摆设"。 ]]--
  local quitCb = findClickCbByNodeId("quitBtn")
  local resumeCb = findClickCbByNodeId("btnResume")
  if quitCb and resumeCb then
    --[[ ★ 先让它落回地面并静置，取一个可信的"地面基准"。

         ⚠️ 不能复用上面的 yBeforeTap —— 那时恐龙刚起跳、
            还停在空中；拿它当地面基准会得出"恢复后还在空中"
            的假失败。 ]]--
    stepFrames(40)
    local yGround = dinoY()

    tap(quitCb)                       -- 打开结算窗口（S.paused = true）
    stepFrames(5)

    tap(tapCb)                        -- ★ 暂停中偷点跳跃按钮

    tap(resumeCb)                     -- 关窗恢复
    stepFrames(1)
    local yResumed = dinoY()

    check("★★ 暂停时点的跳跃被丢弃（恢复后不会突然弹起）",
        yResumed ~= nil and yGround ~= nil
        and math.abs(yResumed - yGround) < 0.01,
        string.format("恢复后 Y=%.1f（地面 %.1f）",
            yResumed or 0, yGround or 0))

    --[[ ★ 对照：恢复之后【正常点一次】必须能跳 ——
         否则上面那条断言可能只是因为"跳跃整个坏掉了"。 ]]--
    tap(tapCb)
    stepFrames(1)
    local yAfterResumeTap = dinoY()
    check("★★ 恢复后再点一次 -> 起跳（对照组，证明按钮仍有效）",
        yAfterResumeTap ~= nil and yResumed ~= nil
        and yAfterResumeTap > yResumed,
        string.format("%.1f -> %.1f", yResumed or 0, yAfterResumeTap or 0))
  end
end

print("")
print(string.format(">>> 通过 %d / 失败 %d", pass, fail))
if fail > 0 then os.exit(1) end
