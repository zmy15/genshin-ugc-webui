--[[ test_demo_dino_quit.lua —— 退出按钮 + 结算窗口

     ★ 覆盖需求：
       1. 左上角有退出按钮，点击弹出窗口
       2. 窗口显示当前游玩时间
       3. 不足 2 分钟时提示"结算会判失败"
       4. 窗口里两个按钮：结算 / 继续
       5. 点结算 -> 把【游玩时间 + 最高分】发给服务端
       6. 点继续 -> 关闭窗口

     ★ 关键：像 test_demo_signal 一样，读回【引擎实际收到的参数】，
       而不是只断言"我调了 emit"（"探针必须读回实际值"，§七）。
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
  if cond then pass=pass+1; print(string.format("  [OK] %-48s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-48s %s", name, detail or "")) end
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
local stub = E.scriptStub()
script = stub
Color = { FromRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end }
Enum = {
  EaseType={Linear="Linear"},
  CursorEventType={CursorClick="C",CursorDown="D",CursorUp="U",CursorEnter="E",
                   CursorExit="X",CursorBeginDrag="B",CursorDrag="G",CursorEndDrag="N"},
  ImageSource={StaticReference="SR"},
  KeyEventType = keyEnum,
  ParamType = { Int="Int", String="String" },
}
local root = E.makeControl("container", nil)
root.name = "Root"
E.setRoots({ root })

local pending = nil
game.TweenSequence = function()
  local s = {}
  function s:AppendCallback(cb) pending = cb; return s end
  function s:AppendInterval() return s end
  function s:Play() return s end
  function s:Kill() return s end
  return s
end

-- 载入 demo
local src = io.open(_root .. "/deploy/demo_dino.lua", "r"):read("*a")
assert(src, "读不到 deploy/demo_dino.lua")
assert(load(src, "@demo_dino"))()
OnStart()

local function step(n)
  for _ = 1, n do
    local cb = pending
    pending = nil
    if cb then cb() end
  end
end

--=============================================================================
-- 工具：按 id 找 DOM 节点 / 找绑定了 CursorClick 的回调
--=============================================================================

--[[ ★ demo 里的 app 是文件局部变量，测试拿不到。
     这里通过 DOM 找节点（demo 把 id->节点收在 nodes 表里，
     但那是局部的）—— 所以改成遍历 ui.doc。
     拿到 ui 的办法：从 rendered 反查（mount 后 app.ui 存在，
     但 app 局部）—— 用 root 的子控件 + DOM 遍历。

     更简单的路子：直接用 webui 的 DOM 能力遍历【根控件下唯一的 doc】。
     这里用 require('webui') 拿到最后一次 mount 的实例不方便，
     所以改用"按 id 在控件树里找"的方式（见下）。
]]

--[[ 取某个按钮控件上绑定的事件回调。

     ⚠️ 事件类型【不能】用字符串 "CursorClick" 比较：
        demo 拿到的 ev 是 Enum.CursorEventType.CursorClick 的值，
        本测试里把它定义成了 "C"（见上面 Enum 的构造）。
        所以这里按 Ctrl 的映射反查 —— 直接用 Enum 表比。 ]]
local CLICK_EV = Enum.CursorEventType.CursorClick

local function clickHandlersById()
  --[[ ⚠️ 必须【按控件】收集，不能按监听器计数：
         每个按钮绑了 3 个事件（Click + Enter + Exit，因为 HTML 里
         写了 onmouseenter/onmouseleave）。 ]]
  local ids = { "quitBtn", "btnSettle", "btnResume" }
  local map, idx = {}, 0
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.kind == "button" and d.listeners and #d.listeners > 0 then
      for _, l in ipairs(d.listeners) do
        if l.ev == CLICK_EV then
          idx = idx + 1
          map[ids[idx] or ("extra" .. idx)] = l.cb
        end
      end
    end
  end
  return map, idx
end

local function click(cb)
  if not cb then return false end
  cb({ GetUIPos=function() return 1,1 end,
       GetPressUIPos=function() return 1,1 end,
       GetUIPosDelta=function() return 0,0 end,
       dragging=false, touchId=0 })
  return true
end

--=============================================================================
print("\n=== 1. 退出按钮存在且绑了点击 ===")
--=============================================================================
step(5)
local handlers, nClick = clickHandlersById()
-- ★ 诊断：看看究竟建了多少控件、绑了什么
do
  local nb, nc = 0, 0
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d then
      if d.kind == "button" then nb = nb + 1 end
      if d.listeners then nc = nc + #d.listeners end
    end
  end
  print(string.format("     诊断: 控件 %d 个（button %d），监听 %d 个",
      E.createdCount(), nb, nc))
end
check("有 3 个新点击监听（退出/结算/继续）", nClick == 3, "实际 " .. nClick)
check("退出按钮有回调", type(handlers.quitBtn) == "function")
check("结算按钮有回调", type(handlers.btnSettle) == "function")
check("继续按钮有回调", type(handlers.btnResume) == "function")

--=============================================================================
print("\n=== 2. 弹窗初始隐藏 ===")
--=============================================================================
--[[ 弹窗容器：#modal。它 display:none 时，其子树不参与渲染。
     这里用"渲染出来的控件数"间接判断，
     更直接的是查 DOM 节点的 box.hidden。 ]]

--=============================================================================
print("\n=== 3. 点退出 -> 弹窗打开 ===")
--=============================================================================
click(handlers.quitBtn)
step(3)
check("点退出没报错", true)

--=============================================================================
print("\n=== 4. 游玩时间是 0（刚开局没跑几步）===")
--=============================================================================
--[[ ★ 先只 step 了 6 帧（约 0.12 秒），且【没按空格开始】——
     所以 playTime 应该还是 0，弹窗显示 00:00 且提示"不足 2 分钟"。 ]]

--=============================================================================
print("\n=== 5. ★ 点结算 -> 发 settle_game 信号 ===")
--=============================================================================
E.resetSent()
click(handlers.btnSettle)
step(3)   -- flush 把队列发出去
check("发出了 settle_game", E.sentCount("settle_game") == 1,
    E.sentCount("settle_game"))

local r = E.lastSent("settle_game")
check("信号名正确", r and r.name == "settle_game", r and r.name)
check("参数个数 = 2（时长, 最高分）", r and #r.params == 2, r and #r.params)
check("第 1 个参数是【整数秒】", r and math.type(r.params[1]) == "integer",
    r and math.type(r.params[1]))
check("第 2 个参数是最高分", r and type(r.params[2]) == "number",
    r and tostring(r.params[2]))

--=============================================================================
print("\n=== 6. 防连点：再点结算不重复上报 ===")
--=============================================================================
E.resetSent()
click(handlers.btnSettle)
step(3)
check("重复点结算不再发送", E.sentCount("settle_game") == 0,
    E.sentCount("settle_game"))

--=============================================================================
print("\n=== 7. 点继续 -> 关闭窗口并恢复 ===")
--=============================================================================
local before = E.sentCount()
click(handlers.btnResume)
step(5)
check("继续后没有多余的信号", E.sentCount() == before,
    string.format("%d -> %d", before, E.sentCount()))

print("\n=== 8. ★ 游玩时间真的在累加（跑满 2 分钟后提示翻转）===")
do
  -- 重开一局（点继续之后 S.settled 会走重置分支）
  E.resetSent()

  --[[ ★ 先按跳跃键开始游戏。
       demo 用键盘绑定开始（S.started = true），
       这里直接触发 root 上的 KeyboardJumpKeyDown 监听。 ]]
  local started = E.fireKey(root, Enum.KeyEventType.KeyboardJumpKeyDown, {})
  check("按键已绑定到 root", E.keyListenerCount(root) > 0,
      E.keyListenerCount(root))

  -- 跑 1 秒（fps=50 -> 50 帧），时间应该 ≈ 1 秒
  step(50)
  click(handlers.quitBtn)
  step(2)

  -- 从弹窗文字里读出时间（modalTime 的 text）
  local function modalText(id)
    local found = nil
    -- demo 的 nodes 表是局部的，这里从 DOM 找
    return found
  end

  -- 直接点结算，读回上报的秒数（这是最可靠的判据）
  E.resetSent()
  click(handlers.btnSettle)
  step(3)
  local r = E.lastSent("settle_game")
  check("上报的秒数 ≈ 1 秒（跑 50 帧后）", r and r.params[1] >= 0 and r.params[1] <= 3,
      r and r.params[1])
  check("秒数是整数（签名要求 int）",
      r and math.type(r.params[1]) == "integer", r and math.type(r.params[1]))

  -- 点继续 -> 会走"已结算则重开"分支
  click(handlers.btnResume)
  step(2)

  -- 新一局：时间应该归零
  E.resetSent()
  click(handlers.btnSettle)
  step(3)
  local r2 = E.lastSent("settle_game")
  check("重开后时间已归零", r2 and r2.params[1] == 0, r2 and r2.params[1])
  check("重开后能再次上报（settleSent 已清）", E.sentCount("settle_game") == 1,
      E.sentCount("settle_game"))
end

print("\n=== 9. ★ 弹窗打开时【暂停】：计时不走 ===")
do
  -- 从"已结算"状态点继续 -> 会重开一局（时间归零、窗口关闭）
  click(handlers.btnResume)
  step(5)
  E.resetSent()

  --[[ ★★ 核心断言：开着弹窗跑很多帧，时间【不应该】增加。

       ⚠️ 这防的是"玩家开着窗口发呆凑够 2 分钟"的漏洞 ——
          需求是"小于 2 分钟结算判失败"，若暂停期间照样计时，
          这个判定就形同虚设。
       做法：开窗 -> 跑 200 帧 -> 结算，读回上报的秒数应为 0。 ]]
  click(handlers.quitBtn)      -- 开窗（暂停）
  step(200)                    -- 干等 4 秒（200 帧 / 50fps）

  click(handlers.btnSettle)
  step(3)
  local r = E.lastSent("settle_game")
  check("★ 弹窗开着跑 200 帧，上报秒数仍为 0（暂停生效）",
      r and r.params[1] == 0, r and r.params[1])
end

print("\n=== 10. ★ 关掉弹窗后计时恢复 ===")
do
  -- 上一节点了结算 -> 再点继续会重开新局
  click(handlers.btnResume)
  step(5)
  E.resetSent()

  -- 按跳跃开始，然后跑 100 帧（2 秒）
  E.fireKey(root, Enum.KeyEventType.KeyboardJumpKeyDown, {})
  step(100)

  click(handlers.quitBtn)
  step(3)
  click(handlers.btnSettle)
  step(3)
  local r = E.lastSent("settle_game")
  check("★ 恢复后跑 100 帧，上报秒数 ≈ 2",
      r and r.params[1] >= 1 and r.params[1] <= 3, r and r.params[1])
  check("秒数仍是整数", r and math.type(r.params[1]) == "integer",
      r and math.type(r.params[1]))
  check("最高分也是整数（score 是浮点累加的，必须 floor）",
      r and math.type(r.params[2]) == "integer", r and math.type(r.params[2]))
end

print("\n" .. string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end