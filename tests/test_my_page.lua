--[[ 试跑 deploy/my_page.lua —— 站在"新用户"视角验证这个示例真的能用。

     重点验证的是交互，不只是"能跑起来"：
     上一轮的教训是这个页面会"跑通但点了没反应"。
]]--

local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')
local PREFABS = { container=1073741933, textbox=1073741934, button=1073741935, image=1073741938 }
local E = EngineMock.new(PREFABS)
game  = E.game
Color = { FromRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
          FromRGB =function(r,g,b) return {r=r,g=g,b=b} end }
Enum = {
  EaseType = { Linear="Linear", InQuad="InQuad", OutQuad="OutQuad", InOutQuad="InOutQuad" },
  CursorEventType = {
    CursorClick="CursorClick", CursorDown="CursorDown", CursorUp="CursorUp",
    CursorEnter="CursorEnter", CursorExit="CursorExit",
    CursorBeginDrag="CursorBeginDrag", CursorDrag="CursorDrag", CursorEndDrag="CursorEndDrag",
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
  function s:AppendCallback(fn) pending[#pending+1] = fn; return s end
  function s:AppendInterval(t) return s end
  function s:Append(t) return s end
  function s:Play() return s end
  function s:Kill() return s end
  function s:SetLoops() return s end
  return s
end
local function pump()
  local cur = pending; pending = {}
  for _, fn in ipairs(cur) do pcall(fn) end
end
printerr = function(...) end

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-30s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-30s %s", name, detail or "")) end
end

print(">>> 试跑 my_page.lua")
print("")
local ok, err = pcall(function()
  dofile("deploy/my_page.lua")
  assert(type(OnStart) == "function", "OnStart 缺失")
  assert(type(OnUpdate) == "function", "OnUpdate 缺失")
  assert(type(OnDestroy) == "function", "OnDestroy 缺失")
  OnStart()
  OnUpdate(0.016)
  for i = 1, 10 do pump() end
  -- ⚠️ 先不 OnDestroy：交互验证需要逐帧循环还在跑
end)

print("")
if not ok then
  print(">>> 【崩溃】 " .. tostring(err))
  os.exit(1)
end

check("my_page 跑通无崩溃", true)
check("建出了控件", E.createdCount() > 0, "created=" .. E.createdCount())

-- 按控件文字找控件
local function findCtrlByText(needle)
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    local f = d and d.fields or {}
    if f.text and tostring(f.text):find(needle, 1, true) then
      return tostring(f.text), d
    end
  end
  return nil, nil
end

local function budgetText()
  -- 预算栏会被"请先选择角色"等提示临时占用，所以两种都认
  local t = findCtrlByText("预算")
  if t then return t end
  return (findCtrlByText("请先选择角色"))
end

-- 收集所有带点击监听的 button 覆盖层（卡片 6 + 清空 + 出战 = 8）
local buttons = {}
for _, c in ipairs(E.controls) do
  local d = E.dataOf(c)
  if d and d.kind == "button" and d.listeners and #d.listeners > 0 then
    buttons[#buttons + 1] = d
  end
end

local function clickButtonAt(i)
  local d = buttons[i]
  if not d then return false end
  for _, l in ipairs(d.listeners) do
    if l.ev == "CursorClick" then
      pcall(l.cb, { GetUIPos=function() return 1,1 end,
                    GetPressUIPos=function() return 1,1 end,
                    GetUIPosDelta=function() return 0,0 end,
                    dragging=false, touchId=-1 })
      return true
    end
  end
  return false
end

print("")
print("=== 交互验证 ===")

check("初始预算 0 / 4", budgetText() == "预算 0 / 4", tostring(budgetText()))
check("初始已选为空", findCtrlByText("（还没选人）") ~= nil)
check("卡片 + 按钮共 8 个可点", #buttons == 8, string.format("实际 %d 个", #buttons))

--[[ ★ 逐个点卡片：预算应该 1 -> 2 -> 3 -> 4，第 5 张被拒绝。

     之前这个测试一次点完所有按钮，最后落在「出战」上，
     预算变成 nil（被提示文字占用），断言形同虚设。
     这里改成按顺序点、逐次断言，才能真正验证业务逻辑。
]]--
local expect = { "预算 1 / 4", "预算 2 / 4", "预算 3 / 4", "预算 4 / 4" }
for i, want in ipairs(expect) do
  clickButtonAt(i)
  pump()
  check(string.format("点第 %d 张卡 -> %s", i, want),
      budgetText() == want, tostring(budgetText()))
end

-- 第 5 张应被拒绝（队伍上限 4）
clickButtonAt(5)
pump()
check("超过 4 人被拒绝", budgetText() == "预算 4 / 4", tostring(budgetText()))

-- 平均等级应该算出来了（不再显示 Lv.--）
check("平均等级已计算", findCtrlByText("Lv.--") == nil,
    "选中后应显示具体等级")

-- 清空（按钮顺序：6 张卡片 -> 清空 -> 出战）
clickButtonAt(7)
pump()
check("清空后预算归零", budgetText() == "预算 0 / 4", tostring(budgetText()))
check("清空后已选为空", findCtrlByText("（还没选人）") ~= nil)

-- 没人时出战应给出提示
clickButtonAt(8)
pump()
check("空队伍出战被拦下", findCtrlByText("请先选择角色") ~= nil,
    tostring(budgetText()))

-- 图片形状：圆形头像（6 个）
local masked = 0
for _, c in ipairs(E.controls) do
  local d = E.dataOf(c)
  if d and d.fields and d.fields.enableMask == true then masked = masked + 1 end
end
check("6 个头像圆形裁剪", masked == 6,
    string.format("enableMask 控件 %d 个", masked))

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

OnDestroy()

print("")
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end
