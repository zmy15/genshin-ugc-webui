--[[ demo_dino 端到端：真的在 mock 引擎上跑 300 帧循环

     ★ 与 test_demo_dino 的分工：
       test_demo_dino  —— 物理/碰撞数值（独立复刻状态机）
       本文件           —— demo 本体能否在真机仿真下真的跑起来

     关键：demo 的 ui 是局部变量，这里通过【重新挂载一份】
     并把 onTick 抓出来手动驱动，从而真正执行 demo 的 tick 函数。
]]

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
  if cond then pass=pass+1; print(string.format("  [OK] %-46s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-46s %s", name, detail or "")) end
end

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
Color = { FromRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end }
Enum = {
  EaseType={Linear="Linear"},
  CursorEventType={CursorClick="C",CursorDown="D",CursorUp="U",CursorEnter="E",
                   CursorExit="X",CursorBeginDrag="B",CursorDrag="G",CursorEndDrag="N"},
  ImageSource={StaticReference="SR"},
  KeyEventType = keyEnum,
}
local root = E.makeControl("container", nil)
root.name = "Root"
E.setRoots({ root })
script = { object = root, EnableUpdate=function() end }

-- ★ Tween 捕获回调：让我们拿到 demo 的 tick 链，手动推进帧
local pending = nil
game.TweenSequence = function()
  local s = {}
  function s:AppendCallback(cb) pending = cb; return s end
  function s:AppendInterval() return s end
  function s:Play() return s end
  function s:Kill() return s end
  return s
end

-- 加载 demo
local src = io.open("deploy/demo_dino.lua", "r"):read("*a")
assert(src, "读不到 deploy/demo_dino.lua")
assert(load(src, "@demo_dino"))()
OnStart()

--=============================================================================
print("\n=== 1. 循环已启动（Tween 链建立）===")
--=============================================================================
check("startLoop 建立了 Tween 续期链", pending ~= nil)

-- 推进 N 帧：每帧先跑 demo 的 tick，再让链续期
local function step(n)
  for _ = 1, n do
    local cb = pending
    pending = nil
    if cb then cb() end
  end
end

--=============================================================================
print("\n=== 2. 未开始时：恐龙在地面，障碍隐藏 ===")
--=============================================================================
--[[ ★ 精灵版的尺寸与结构。

     恐龙现在是一个"外层容器"，尺寸 = 点阵 22x24 格 x 8px = 176x192。
     仙人掌控件 9x14 格 x 8px = 72x112。
     （不再是旧版的 80x80 / 40x70 方块。） ]]
local CELL = 8
local DINO_W, DINO_H = 22 * CELL, 24 * CELL     -- 176 x 192
local OBS_W,  OBS_H  = 9  * CELL, 14 * CELL     -- 72 x 112

local function ctrlByDelta(w, h)
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and math.abs((d.fields.sizeDeltaX or 0) - w) < 0.01
       and math.abs((d.fields.sizeDeltaY or 0) - h) < 0.01 then
      return c, d
    end
  end
end

step(5)
local dinoC, dinoD = ctrlByDelta(DINO_W, DINO_H)
check(string.format("恐龙容器存在（%dx%d）", DINO_W, DINO_H), dinoC ~= nil)
if dinoD then
  -- left:160 在 1600 宽父里居中 -> 偏移 = (160 + 176/2) - 800 = -552
  local expect = (160 + DINO_W / 2) - 800
  check(string.format("恐龙 anchoredPositionX = %d（left:160 居中换算）", expect),
      math.abs((dinoD.fields.anchoredPositionX or 0) - expect) < 1,
      "ax=" .. tostring(dinoD.fields.anchoredPositionX))
end

--[[ ★★ 摆放几何：恐龙的【脚】必须正好落在地面线上。

     这是真机上最容易出错、又最难看出来的地方：
       恐龙点阵 22x24 格 x 8px = 176x192，脚在控件顶 +192
       地面线 .ground top = 700
       -> 恐龙容器 top 必须是 700 - 192 = 508   （G.GROUND_Y）

     若这里错了（比如沿用旧方块版的 620），恐龙会【陷进地面 112px】，
     而画面上看起来只是"位置有点怪"，不会报错。
     同理仙人掌 top 必须是 700 - 112 = 588。

     ★ 用 anchoredPositionY 反推（父是 1600x900，中心 450，Y 轴向上）：
         画布 top = 450 - anchoredPosY - h/2
]]
local function canvasTopOf(d)
  -- mock 里 anchoredPositionY 是相对父中心的偏移（Y 向上）
  local h = d.fields.sizeDeltaY or 0
  return 450 - (d.fields.anchoredPositionY or 0) - h / 2
end
local function canvasLeftOf(d)
  local w = d.fields.sizeDeltaX or 0
  return 800 + (d.fields.anchoredPositionX or 0) - w / 2
end

if dinoD then
  local top = canvasTopOf(dinoD)
  local left = canvasLeftOf(dinoD)
  check("★ 恐龙顶边 = 508（脚正好落在地面 700 上）",
      math.abs(top - 508) < 1, string.format("top=%.1f（期望 508）", top))
  check("★ 恐龙左边 = 160", math.abs(left - 160) < 1,
      string.format("left=%.1f", left))
  check("★ 恐龙脚 = 地面线 700", math.abs((top + DINO_H) - 700) < 1,
      string.format("脚=%.1f（地面 700）", top + DINO_H))
end

--[[ ★★ 恐龙的 33 个矩形必须【铺开成形状】，不能堆成一列。

     真机踩过的坑（R23）：矩形 div 少了 position:absolute 时，
     inline 的 left/top 被忽略 -> 全部堆在父容器左边、纵向排开，
     屏幕上是【一根竖条】，不是恐龙。

     ⚠️ 这个 bug 只有【布局】错，分解/数量/覆盖全对，
        所以必须直接量"渲染后的 box 有没有铺开"。

     ★ 用 node.box（库的布局结果，画布绝对坐标），
       需要拿到底层控件 → 用 rendered.live 反查不可行（ui 是局部的），
       改为用 sprite.collect 拿 DOM 节点。
]]
do
  local webui = require('webui')
  local S = webui.sprite
  -- DOM 树拿不到（ui 是 demo 的局部变量），所以换个角度：
  -- 直接从引擎控件的【anchoredPosition】看 33 个矩形是否落在不同位置。
  local positions = {}
  local found = 0
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d then
      local w = d.fields.sizeDeltaX or 0
      local h = d.fields.sizeDeltaY or 0
      -- 恐龙矩形：尺寸 <= 176，且不是我们已知的容器/障碍/云
      if w > 0 and h > 0 and w <= 176 and h <= 192
         and not (math.abs(w - DINO_W) < 0.01 and math.abs(h - DINO_H) < 0.01)
         and not (math.abs(w - OBS_W) < 0.01 and math.abs(h - OBS_H) < 0.01) then
        local key = string.format("%.0f", d.fields.anchoredPositionX or 0)
        positions[key] = true
        found = found + 1
      end
    end
  end

  local uniq = 0
  for _ in pairs(positions) do uniq = uniq + 1 end

  check("★ 恐龙矩形在水平方向铺开（>=10 个不同 x 偏移）", uniq >= 10,
      string.format("%d 个控件, %d 个不同 x", found, uniq))
end

--[[ 障碍是否隐藏：看 active。

     ★ 库的 hide()（display:none）走的是 SetActive(false)，
       不是 visible —— 见 render.lua 的 hideControl。
       而且 display:none 的元素会从 rendered.live 里移除，
       所以只能从引擎控件的 active 字段观察。

     ★ 注意：仙人掌本身是 8 个矩形拼的，外层容器才是 72x112。
       这里数【外层容器】（有 3 个），不是矩形。 ]]--
local function obsCtrls()
  local out = {}
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and math.abs((d.fields.sizeDeltaX or 0) - OBS_W) < 0.01
       and math.abs((d.fields.sizeDeltaY or 0) - OBS_H) < 0.01 then
      out[#out+1] = d
    end
  end
  return out
end

local obs = obsCtrls()
local hidden = 0
for _, d in ipairs(obs) do
  if d.fields.active == false then hidden = hidden + 1 end
end
check("3 个障碍初始都隐藏（active=false）", hidden == 3,
    "hidden=" .. tostring(hidden) .. "/" .. tostring(#obs))

--=============================================================================
print("\n=== 3. 按跳跃 -> 开始游戏，障碍开始生成 ===")
--=============================================================================
E.fireKey(root, "Enum.KeyEventType.KeyboardJumpKeyDown", {})   -- 第 1 次：started
E.fireKey(root, "Enum.KeyEventType.KeyboardJumpKeyDown", {})   -- 第 2 次：起跳
step(120)

local visibleObs = 0
for _, d in ipairs(obsCtrls()) do
  if d.fields.active ~= false then visibleObs = visibleObs + 1 end
end
check("★ 开始后障碍出现（至少 1 个可见）", visibleObs >= 1,
    "visible=" .. tostring(visibleObs))

-- 分数应当涨了
local scoreTxt = nil
for _, c in ipairs(E.controls) do
  local d = E.dataOf(c)
  if d and d.kind == "textbox" and d.fields.text
     and d.fields.text:find("HI ") then
    scoreTxt = d.fields.text
  end
end
check("分数栏已更新", scoreTxt ~= nil, tostring(scoreTxt))
check("★ 分数不再是 00000", scoreTxt ~= nil and not scoreTxt:find("  00000$"),
    tostring(scoreTxt))

--=============================================================================
print("\n=== 4. 长时间空跑：控件数不增长（无泄漏）===")
--=============================================================================
local before = #E.controls
step(400)
check("★ 400 帧后控件数不变（无泄漏）", #E.controls == before,
    string.format("%d -> %d", before, #E.controls))

--=============================================================================
print("\n=== 5. 不操作 -> 撞障碍 -> Game Over 出现 ===")
--=============================================================================
-- 上面已经跑了 520 帧没跳过（第 2 次按键后就再没跳），应已撞上
--[[ 查 Game Over 是否显示。

     ⚠️ 不能用 rendered.live —— display:none 的元素会被移出该表
        （所以"查不到"本身也是一种状态，不能当成"没显示"）。
        这里直接读 DOM 节点的 _displayOverride，它由 node:hide()/show() 设置。 ]]
local function overShown()
  local node = nil
  -- 借 webui 的 DOM：从引擎控件反查不到文字节点，改用 demo 自己维护的
  -- 方式 —— 这里扫描 DOM 树（demo 的 ui 是 local，用全局 DOM 快照不可行），
  -- 所以改为读控件 text + active。
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.kind == "textbox" and d.fields.text
       and d.fields.text:find("G A M E") then
      return d.fields.active ~= false
    end
  end
  return nil   -- 控件都找不到 = 从未渲染过
end

step(200)
check("★ Game Over 已显示（不跳就会撞）", overShown() == true,
    "shown=" .. tostring(overShown()))

--=============================================================================
print("\n=== 6. 撞后再按键 -> 重开 ===")
--=============================================================================
E.fireKey(root, "Enum.KeyEventType.KeyboardJumpKeyDown", {})
step(3)
check("★ 重开后 Game Over 隐藏", overShown() == false,
    "shown=" .. tostring(overShown()))

--=============================================================================
print("\n=== 6b. 重开后分数归零、恐龙回到地面 ===")
--=============================================================================
local sTxt
for _, c in ipairs(E.controls) do
  local d = E.dataOf(c)
  if d and d.kind == "textbox" and d.fields.text and d.fields.text:find("HI ") then
    sTxt = d.fields.text
  end
end
-- 重开后分数应从 0 重新计（HI 保留历史最高）
check("★ 重开后当前分数归零", sTxt ~= nil and sTxt:find("00000") ~= nil,
    tostring(sTxt))

--=============================================================================
print("\n=== 7. 销毁 ===")
--=============================================================================
OnDestroy()
check("★ OnDestroy 后按键已解绑", E.keyListenerCount(root) == 0,
    "count=" .. tostring(E.keyListenerCount(root)))

print("")
print(string.format(">>> 通过 %d / 失败 %d", pass, fail))
if fail > 0 then os.exit(1) end
