--[[ 验证 README「快速开始」里的示例代码能真的跑起来。

     ★ 为什么值得单独一个测试：
       README 的示例曾经是错的（`local app = webui.mount{...}` 会让
       on 表里的闭包看不到 app），点按钮毫无反应但也不报错。
       文档示例一旦写错，比没有示例更糟 —— 别人照抄就中招。

     这里从 README.md 里【直接抽取】那段 lua 代码来跑，
     所以 README 一改错，这个测试就会红。
]]--

local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-30s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-30s %s", name, detail or "")) end
end

--=============================================================================
-- 从 QUICKSTART 抽取示例代码
--
--   ★ 示例代码的【唯一来源】是 lib/webui/QUICKSTART.md。
--     README 的「快速开始」只是一个指向它的链接（有意为之，避免两处维护）。
--     所以这里只读 QUICKSTART，不再保留 README 回退分支。
--=============================================================================

local SRC = { path = "lib/webui/QUICKSTART.md", section = "## 写一个页面" }

local sectionPath, section = nil, nil
do
  local fh = io.open(SRC.path, "r")
  if fh then
    local text = fh:read("*a")
    fh:close()
    -- 取该小节到下一个同级/更高级标题之间的内容
    local pat = SRC.section:gsub("([%%%.%(%)%+%-%*%?%[%]%^%$])", "%%%1")
    local body = text:match(pat .. "(.-)\n## ") or text:match(pat .. "(.*)$")
    if body and body:find("```lua") then
      sectionPath, section = SRC.path, body
    end
  end
end

check("在 QUICKSTART 找到含 lua 示例的小节", section ~= nil,
    section and sectionPath or ("未找到 " .. SRC.path .. " 的「" .. SRC.section .. "」"))

local example = nil
if section then
  example = section:match("```lua(.-)```")
end
check("该小节里有 lua 示例代码", example ~= nil,
    example and (#example .. " 字符") or "未找到")

if not example then
  print("")
  print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
  os.exit(1)
end

-- 关键的写法检查：必须是「先声明后赋值」
check("示例用先声明后赋值的写法",
    example:find("local app%s*\n%s*app%s*=%s*webui%.mount") ~= nil,
    "（`local app = webui.mount{...}` 会让闭包看不到 app）")

--=============================================================================
-- 跑这段示例
--=============================================================================

local PREFABS = {
  container = 1073741933, textbox = 1073741934,
  button    = 1073741935, image   = 1073741938,
}
local E = EngineMock.new(PREFABS)
game  = E.game
Color = { FromRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
          FromRGB=function(r,g,b) return {r=r,g=g,b=b} end }
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

-- 执行 README 里的示例（文件路径要能被 require 找到）
local chunk, cerr = loadstring and loadstring(example) or load(example, "readme-example")
check("示例能编译", chunk ~= nil, tostring(cerr))

if chunk then
  local ok, err = pcall(chunk)
  check("示例能执行", ok, ok and "OK" or tostring(err))
end

if type(OnStart) == "function" then
  OnStart()
  pump()
end

check("示例里定义了 OnStart", type(OnStart) == "function")
check("示例里定义了 OnUpdate", type(OnUpdate) == "function")
check("示例里定义了 OnDestroy", type(OnDestroy) == "function")
check("示例建出了控件", E.createdCount() > 0, "created=" .. E.createdCount())

-- 找到 #c 控件，检查点击是否让文字变化
local function textOfC()
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    local fld = d and d.fields or {}
    if fld.text == "你好" or fld.text == "被点了" then return tostring(fld.text) end
  end
  return nil
end

check("初始文字是「你好」", textOfC() == "你好", tostring(textOfC()))

-- 派发一次点击
local fired = 0
for _, c in ipairs(E.controls) do
  local d = E.dataOf(c)
  if d and d.listeners then
    for _, l in ipairs(d.listeners) do
      if l.ev == "CursorClick" then
        pcall(l.cb, { GetUIPos=function() return 1,1 end,
                      GetPressUIPos=function() return 1,1 end,
                      GetUIPosDelta=function() return 0,0 end,
                      dragging=false, touchId=-1 })
        fired = fired + 1
      end
    end
  end
end
check("点击被派发", fired > 0, string.format("触发 %d 次", fired))
pump()

check("点击后文字变成「被点了」", textOfC() == "被点了",
    string.format("实际 %s（若仍为「你好」，说明闭包捕获 app 失败）",
        tostring(textOfC())))

if type(OnDestroy) == "function" then OnDestroy() end

print("")
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end
