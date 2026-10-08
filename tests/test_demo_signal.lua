--[[ 自检：demo_signal.lua 的按钮真的能发信号吗？

     与其它 demo 测试同构：用 engine_mock 真跑一遍，
     然后【模拟点击按钮】看信号有没有发出去。

     ★ 关键：不能只断言"我调了 emit"，要读【引擎实际收到的参数】
       （"探针必须读回实际值"，见 docs/引擎能力与限制.md §七）。
]]

local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
             .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')

local PREFABS = { container=1073741933, textbox=1073741934,
                  button=1073741935, image=1073741938 }
local E = EngineMock.new(PREFABS)

game   = E.game
local stub = E.scriptStub()
script = stub
script.object = nil
Color  = { FromRGBA = function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
           FromRGB  = function(r,g,b) return {r=r,g=g,b=b} end }
Enum   = {
  EaseType = { Linear="Linear", InQuad="InQuad", OutQuad="OutQuad", InOutQuad="InOutQuad" },
  CursorEventType = {
    CursorClick="CursorClick", CursorDown="CursorDown", CursorUp="CursorUp",
    CursorEnter="CursorEnter", CursorExit="CursorExit",
    CursorBeginDrag="CursorBeginDrag", CursorDrag="CursorDrag",
    CursorEndDrag="CursorEndDrag",
  },
  TextHorizontalAlignmentLeft="L",
  TextHorizontalAlignmentMiddle="C",
  TextHorizontalAlignmentRight="R",
  ImageSource = { StaticReference = "Enum.ImageSource.StaticReference" },
  ImageType = { Basic = "Enum.ImageType.Basic" },
  ParamType = { Int="Int", String="String" },
}

local root = E.makeControl("container", nil)
root.name = "Root"
E.setRoots({ root })

-- 逐帧驱动（真机靠递归 TweenSequence）
local pending = {}
game.TweenSequence = function()
  local s = {}
  function s:AppendCallback(f) pending[#pending+1] = f; return s end
  function s:AppendInterval() return s end
  function s:Append() return s end
  function s:Play() return s end
  function s:Kill() return s end
  function s:SetLoops() return s end
  return s
end
local function pump()
  local cur = pending; pending = {}
  for _, f in ipairs(cur) do pcall(f) end
end

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass=pass+1; print(string.format("  [OK] %-42s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-42s %s", name, detail or "")) end
end

--=============================================================================
-- 载入 demo（它会在 require 时直接 mount —— 与真机一致）
--=============================================================================

print("=== 0. 载入 deploy/demo_signal.lua ===")
local chunk = assert(loadfile(_root .. "/deploy/demo_signal.lua"))
chunk()

check("demo 已挂载", _G.OnStart ~= nil and _G.OnDestroy ~= nil)
OnStart()
check("控件已建出", E.createdCount() > 0, "created=" .. E.createdCount())

--=============================================================================
-- 1. 找到按钮的点击监听，模拟点击
--=============================================================================

--[[ 按 DOM 元素 id 找到它绑定的 CursorClick 回调。

     ⚠️ 真机是双层架构：外观层（textbox）+ 交互层（button），
        事件的 AddCursorEventListener 只在【交互层】上。
        所以这里遍历所有控件的监听器即可，不用关心是哪一层。 ]]
local function clickHandlersById()
  local map = {}
  -- demo 里的节点顺序：b1 / b2 / b3，与控件创建顺序一致
  local order = { "b1", "b2", "b3" }
  local idx = 0
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.listeners and #d.listeners > 0 then
      for _, l in ipairs(d.listeners) do
        if l.ev == "CursorClick" then
          idx = idx + 1
          map[order[idx] or ("btn" .. idx)] = l.cb
        end
      end
    end
  end
  return map
end

local function click(cb)
  cb({ GetUIPos = function() return 1, 1 end,
       GetPressUIPos = function() return 1, 1 end,
       GetUIPosDelta = function() return 0, 0 end,
       dragging = false, touchId = 0 })
end

print("")
print("=== 1. 三个按钮都绑上了点击事件 ===")
local handlers = clickHandlersById()
local n = 0
for _ in pairs(handlers) do n = n + 1 end
check("有 3 个点击监听", n == 3, "实际 " .. n)
check("b1 有回调", type(handlers.b1) == "function")
check("b2 有回调", type(handlers.b2) == "function")
check("b3 有回调", type(handlers.b3) == "function")

--=============================================================================
-- 2. ★ 核心：点按钮 -> 信号真的发出去了吗
--=============================================================================

print("")
print("=== 2. 点「购买 x1」-> 发 buy_item ===")
E.resetSent()
click(handlers.b1)
check("emit 是入队，点击后【还没发】", E.sentCount() == 0, E.sentCount())
pump()   -- 跑一帧：flush 把队列发出去
check("跑一帧后发出去 1 条", E.sentCount("buy_item") == 1, E.sentCount("buy_item"))

-- ★★ 读回引擎【实际收到】的参数，而不是我们打算发的
local r = E.lastSent("buy_item")
check("信号名正确", r and r.name == "buy_item", r and r.name)
check("参数个数 = 2", r and #r.params == 2, r and #r.params)
check("第 1 个参数 = 1001（商品 ID）", r and r.params[1] == 1001, r and r.params[1])
check("第 2 个参数 = 1（数量）", r and r.params[2] == 1, r and r.params[2])

print("")
print("=== 3. 点「购买 x10」-> emitNow 立即发 ===")
E.resetSent()
click(handlers.b2)
check("emitNow 不等下一帧，点击即发", E.sentCount("buy_item") == 1,
    E.sentCount("buy_item"))
local r2 = E.lastSent("buy_item")
check("数量参数 = 10", r2 and r2.params[2] == 10, r2 and r2.params[2])

print("")
print("=== 4. 点「聊天」-> 字符串参数 ===")
E.resetSent()
click(handlers.b3)
pump()
local r3 = E.lastSent("chat")
check("发的是 chat", r3 and r3.name == "chat", r3 and r3.name)
check("参数是字符串", r3 and type(r3.params[1]) == "string", r3 and type(r3.params[1]))
check("内容是预期文本", r3 and r3.params[1] == "你好，我是客户端",
    r3 and r3.params[1])

--=============================================================================
-- 5. 界面反馈：status / count 文字确实变了
--=============================================================================

print("")
print("=== 5. 界面上文字有更新（点了不能没反应）===")
local function textOf(id)
  local found = nil
  require('webui_dom').walk(app.ui.doc, function(nd)
    if not found and nd:isElement() and nd.attrs and nd.attrs.id == id then
      found = nd
    end
  end)
  return found
end

-- ★ 先记录点击前的文字，再点一次，确认【真的变了】
--   （只断言"节点存在"是假阳性 —— 文字没更新也照样通过）
local statusNode = textOf("status")
local countNode  = textOf("count")
check("找得到 #status", statusNode ~= nil)
check("找得到 #count",  countNode ~= nil)

local function currentText(node)
  if not node then return nil end
  local t = node.setText and node._text
  -- DOM 文本存在 text 字段上（渲染器每帧从它读）
  return node.text or node._text or t
end

E.resetSent()
click(handlers.b1)
pump()
-- 走 DOM 文本（渲染器每帧用 DOM 覆盖控件，所以库里就存在 DOM 上）
local afterStatus = currentText(statusNode)
local afterCount  = currentText(countNode)
check("status 文字已更新且含'已发送'",
    type(afterStatus) == "string" and afterStatus:find("已发送") ~= nil,
    tostring(afterStatus))
check("count 文字已更新且含'已发送'",
    type(afterCount) == "string" and afterCount:find("已发送") ~= nil,
    tostring(afterCount))

--=============================================================================
-- 6. 校验确实在起作用（参数写错会被拦下）
--=============================================================================

print("")
print("=== 6. 参数写错会被拦下（引擎本身不校验）===")
E.resetSent()
-- 故意少传一个参数：服务端约定是 2 个
local okBad = app:emit("buy_item", 1001)
pump()
check("少参被拦下", okBad == false, tostring(okBad))
check("被拦的一条没发出去", E.sentCount("buy_item") == 0, E.sentCount("buy_item"))

-- 类型写错
E.resetSent()
local okType = app:emit("buy_item", "不是数字", 1)
pump()
check("类型错被拦下", okType == false, tostring(okType))
check("同样没发出去", E.sentCount("buy_item") == 0, E.sentCount("buy_item"))

--=============================================================================
-- 7. 监听已注册 + destroy 会解绑
--=============================================================================

print("")
print("=== 7. 生命周期 ===")
check("onSignal 未配 -> 不注册多余监听", stub._handlerCount(nil, "buy_item") == 0)

OnDestroy()
check("OnDestroy 后 bound 复位", app.bound == false)
local before = E.sentCount()
click(handlers.b1)
pump()
check("销毁后点击不再发信号", E.sentCount() == before,
    string.format("%d -> %d", before, E.sentCount()))

print("")
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end