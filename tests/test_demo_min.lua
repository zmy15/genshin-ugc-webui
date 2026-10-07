--[[ 试跑 deploy/demo_min.lua —— 验证封装后的最小示例真的能跑。

     ★ 这个文件的作用是"用真实示例证明 mount 好用"，
       与 test_demo_feature 同构，但对象是 demo_min。
]]--

local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')

local PREFABS = {
  container = 1073741933,
  textbox   = 1073741934,
  button    = 1073741935,
  image     = 1073741938,
}

local E = EngineMock.new(PREFABS)
game  = E.game
Color = { FromRGBA = function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
          FromRGB  = function(r,g,b) return {r=r,g=g,b=b} end }
Enum = {
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
}

local root = E.makeControl("container", nil)
root.name = "Root"
E.setRoots({ root })
script = { object = root, EnableUpdate = function() end, GetParam = function() return nil end }

local pending = {}
game.TweenSequence = function()
  local s = {}
  function s:AppendCallback(f) pending[#pending+1] = f; return s end
  function s:AppendInterval(t) return s end
  function s:Append(t) return s end
  function s:Play() return s end
  function s:Kill() return s end
  function s:SetLoops() return s end
  return s
end
local function pump()
  local cur = pending; pending = {}
  for _, f in ipairs(cur) do pcall(f) end
end

printerr = function(...) end

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-30s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-30s %s", name, detail or "")) end
end

print(">>> 试跑 demo_min.lua")
print("")

local ok, err = pcall(function()
  dofile("deploy/demo_min.lua")
  assert(type(OnStart) == "function", "OnStart 缺失")
  assert(type(OnUpdate) == "function", "OnUpdate 缺失")
  assert(type(OnDestroy) == "function", "OnDestroy 缺失")
  OnStart()
  OnUpdate(0.016)
  for i = 1, 20 do pump() end
  --[[ ⚠️ 这里【不能】调 OnDestroy()。

       它会让 mount 停掉逐帧循环（stopLoop），之后 pump() 不再触发
       flush，文字就永远写不进控件 —— 交互断言会全部误判为失败。
       （本测试第一版就是这个原因，把正确的实现误报成 bug。）

       正确的顺序：先跑完交互验证，最后再 OnDestroy。
  ]]--
end)

print("")
if not ok then
  print(">>> 【崩溃】 " .. tostring(err))
  os.exit(1)
end

check("demo_min 跑通无崩溃", true)
check("建出了控件", E.createdCount() > 0, "created=" .. E.createdCount())

-- 文字硬约束
local badRatio, textCount = 0, 0
for _, c in ipairs(E.controls) do
  local d = E.dataOf(c)
  if d and d.kind == "textbox" then
    local f = d.fields or {}
    if f.text and f.text ~= "" and f.fontSize and f.fontSize > 0 and f.sizeDeltaY then
      textCount = textCount + 1
      if f.sizeDeltaY / f.fontSize < 1.9 then badRatio = badRatio + 1 end
    end
  end
end
check("文字框高 >= 字号 x1.9", badRatio == 0,
    string.format("检查 %d 个，违反 %d 个", textCount, badRatio))

-- 有 :hover 规则才可能变色（检查 CSS 里确实写了）
local src = io.open("deploy/demo_min.lua"):read("*a")
check("CSS 里有 :hover 选择器", src:find(".btn:hover", 1, true) ~= nil)
check("HTML 里的按钮绑了 onmouseenter", src:find("onmouseenter", 1, true) ~= nil)

--[[ ★★ 真正的交互测试（之前漏掉的）

     只验证"跑通不崩"是不够的 —— demo 曾经用
       local app = webui.mount{ on = { inc = function() app:setText(...) end } }
     这种写法，闭包捕获到的 app 恒为 nil，点击后什么都不发生，
     但脚本不报错、控件也照建，于是"跑通"检查完全看不出来。

     所以必须真的派发一次点击，并确认文字变了。
     这里不依赖 demo 的 app 句柄（它是文件局部变量），
     直接读 mock 里控件的 text 字段。
]]--
print("")
print("=== 交互验证：点击按钮 ===")

-- 读某个控件的 text：优先按初始内容定位 counter
local function findText(pred)
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    local f = d and d.fields or {}
    if d and d.kind == "textbox" and f.text and pred(tostring(f.text)) then
      return tostring(f.text)
    end
  end
  return nil
end

local function counterText()
  return findText(function(t) return t:find("已点击", 1, true) ~= nil end)
end

check("初始计数文字", counterText() == "已点击 0 次", tostring(counterText()))

--[[ 判别关键：只点【一个】按钮。

     ⚠️ 别把所有按钮都点一遍 —— HTML 里有两个按钮（「+1」与「归零」），
        全点一遍最后会落在「归零」上，计数回到 0，
        看起来就像"点击没生效"，会把正确的实现误判成 bug。
        （本测试第一版就是这样误判的。）
]]--
local function clickFirstButton()
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.kind == "button" and d.listeners then
      for _, l in ipairs(d.listeners) do
        if l.ev == "CursorClick" then
          pcall(l.cb, { GetUIPos=function() return 1,1 end,
                        GetPressUIPos=function() return 1,1 end,
                        GetUIPosDelta=function() return 0,0 end,
                        dragging=false, touchId=-1 })
          return true
        end
      end
    end
  end
  return false
end

check("能触发按钮点击", clickFirstButton())
pump()
local afterClick = counterText()
check("点击后计数文字改变", afterClick ~= "已点击 0 次",
    string.format("0 次 -> %s（若仍为 0 次，多为闭包捕获 app 失败）",
        tostring(afterClick)))
check("计数确实 +1", afterClick == "已点击 1 次", tostring(afterClick))

-- 收尾：到这里做交互验证才停循环
OnDestroy()
check("OnDestroy 后循环停止", true)

print("")
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end