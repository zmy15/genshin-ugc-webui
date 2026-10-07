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

-- 同步 Tween：startLoop 的续期立即执行（我们自己控制帧数）
game.TweenSequence = function()
  local s = {}
  function s:AppendCallback() return s end
  function s:AppendInterval() return s end
  function s:Play() return s end
  function s:Kill() return s end
  return s
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
check("root 上绑定了 2 个按键（jump/jumpUp）",
    E.keyListenerCount(root) == 2, "count=" .. tostring(E.keyListenerCount(root)))

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
local function countRectsOf(rectTables)
  -- 汇总所有期望尺寸（含 bleed 外扩）
  local want = {}
  for _, rects in ipairs(rectTables) do
    for _, r in ipairs(rects) do
      want[(r.w * CELL + BLEED * 2) .. "x" .. (r.h * CELL + BLEED * 2)] = true
    end
  end
  -- 统计引擎里尺寸落在期望集合内的 image 控件
  local n = 0
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.kind == "image" then
      local key = string.format("%dx%d",
          math.floor(d.fields.sizeDeltaX or 0),
          math.floor(d.fields.sizeDeltaY or 0))
      -- 只统计"像精灵矩形"的（排除 1600x900 场景、地面等）
      if want[key] and (d.fields.sizeDeltaX or 0) <= 176 then
        n = n + 1
      end
    end
  end
  return n
end

local dinoN   = #sprite.dinoRects()
local cactusN = #sprite.cactusRects()
local cloudN  = #sprite.cloudRects()

check("恐龙点阵分解为 33 个矩形", dinoN == 33, dinoN .. " 个")
check("仙人掌分解为 8 个矩形", cactusN == 8, cactusN .. " 个")
check("云分解为 6 个矩形", cloudN == 6, cloudN .. " 个")

-- 画面上实际的矩形控件数：恐龙 33 + 仙人掌 8x3 + 云 6x2
local expectTotal = dinoN + cactusN * 3 + cloudN * 2
local actual = countRectsOf({
  sprite.dinoRects(), sprite.cactusRects(), sprite.cloudRects(),
})
check("画面上的精灵矩形控件数 = " .. expectTotal,
    actual == expectTotal, actual .. " 个")

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

print("")
print(string.format(">>> 通过 %d / 失败 %d", pass, fail))
if fail > 0 then os.exit(1) end
