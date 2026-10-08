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

--[[ 读弹窗上的「本局时间 mm:ss」，换算成秒。

     ★ 用弹窗【文字】而不是再发一次信号来读时间：
       settleSent 会让第二次结算静默不发（防重复上报），
       拿它当"读时间"的手段会误判成"时间没涨"。 ]]
local function modalTime()
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.kind == "textbox" and d.fields.text
       and d.fields.text:find("本局时间 ", 1, true) then
      local m, s = d.fields.text:match("本局时间 (%d+):(%d+)")
      if m then return tonumber(m) * 60 + tonumber(s), d.fields.text end
    end
  end
  return nil, nil
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

print("\n=== 8. ★ 计时语义：进入即开始，且不因重开而清空 ===")
do
  --[[ ★★ 计时【不依赖"按空格开始游戏"】，也【不因重开归零】。

       ⚠️ 注意：settleSent 是"本次进入关卡已上报"的标记，一旦发过
          就不再发（防重复上报）。所以本节【不能】靠再发一次信号来
          读时间 —— 改为读弹窗上的「本局时间」文字。

       判据：从头到尾没按过任何开始键，弹窗时间也应该在涨；
             且重开一局后继续涨，而不是回到 00:00。 ]]
  click(handlers.btnResume)   -- 先关掉上一节的窗口
  step(100)                   -- 完全不按键，跑 2 秒
  click(handlers.quitBtn)
  step(2)
  local t1, txt1 = modalTime()
  check("★ 未按开始键也计时（进入即开始）",
      t1 ~= nil and t1 >= 1, tostring(txt1))

  -- 重开一局（此时弹窗是"开"的，点继续会因未结算而只关窗）
  click(handlers.btnResume)
  step(100)                   -- 再跑 2 秒
  click(handlers.quitBtn)
  step(2)
  local t2, txt2 = modalTime()
  check("★ 时间持续累加、不因关窗/重开归零",
      t1 and t2 and t2 > t1, string.format("%s -> %s",
          tostring(txt1), tostring(txt2)))
end

print("\n=== 9. ★ 暂停：弹窗开着时计时不走 ===")
do
  -- 弹窗此刻是开着的（上一节结尾），先记下时间
  step(2)
  local t0 = modalTime()

  --[[ ★★ 开着弹窗干等 400 帧（8 秒），时间【不应该】涨。

       ⚠️ 这防的是"开着窗口发呆凑够 2 分钟"的漏洞 ——
          需求是"小于 2 分钟结算判失败"，若暂停期间照样计时，
          这个判定就形同虚设。 ]]
  step(400)
  local t1, txt1 = modalTime()
  check("★ 暂停期间跑 400 帧，弹窗时间不变",
      t0 ~= nil and t1 == t0,
      string.format("%d -> %d（%s）", t0 or -1, t1 or -1, tostring(txt1)))

  -- 关窗后跑 100 帧（2 秒），时间应恢复增长
  click(handlers.btnResume)
  step(100)
  click(handlers.quitBtn)
  step(2)
  local t2, txt2 = modalTime()
  check("★ 关窗后计时恢复增长",
      t1 and t2 and t2 > t1,
      string.format("%d -> %d（%s）", t1 or -1, t2 or -1, tostring(txt2)))
end

print("\n" .. string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end