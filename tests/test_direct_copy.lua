--[[ 验证「纯复制就能用」—— 本次改造的核心能力。

     背景：
       真机的 require 规则是「同目录 + 文件名原样」：
         require('webui_util') 找的就是 webui_util.lua
       所以只要 lib/webui/ 里的**文件名本身**就是扁平名，
       用户把这个目录整个拷进工程就能跑，不需要任何构建步骤。

       本测试就是验证这一点：
         ① 把 lib/webui/*.lua 原样复制到临时目录（一个字节都不改）
         ② 把 deploy/my_page.lua 复制成 main.lua
         ③ 用【真机风格的 loader】加载并跑起来
         ④ 检查交互确实生效

     它同时是一道"防倒退"闸门：
       将来若有人把库文件改回 util.lua / 带点号的 require，
       这个测试会立刻红。

     不需要手动准备环境：自己建临时目录，跑完清理。
]]--

local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-32s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-32s %s", name, detail or "")) end
end

--=============================================================================
-- 建临时目录并"纯复制"
--=============================================================================

local FS = require('fs_util')

--[[ 库文件清单：显式列出，不靠列目录。

     ★ 为什么不用 `dir /b`：
       那是 Windows 命令，CI 跑在 ubuntu 上会返回空列表 ——
       结果"复制了 0 个文件"却看不出原因（已经踩过）。
       显式列出反而更严格：任何文件被改名，这里立刻不匹配。
]]--
local LIB_FILES = {
  "webui.lua",
  "webui_util.lua", "webui_dom.lua", "webui_html.lua", "webui_css.lua",
  "webui_color.lua", "webui_style.lua", "webui_transition.lua",
  "webui_layout.lua", "webui_render.lua", "webui_clip.lua",
  "webui_sprite.lua", "webui_fit.lua", "webui_grid.lua", "webui_event.lua", "webui_signal.lua",
}

local TMP = (_root .. "/tests/_copy_tmp"):gsub("//", "/")

FS.rmdir(TMP)
FS.mkdir(TMP)

print("=== 纯复制验证 ===")
print("  平台: " .. (FS.IS_WINDOWS and "Windows" or "Unix"))
print("  临时目录: " .. TMP)
print("")

--[[ 临时目录必须真的建出来了。

     踩过：mkdir 在另一个平台静默失败，后面一路"文件不存在"，
     却看不出是目录没建起来。这里先明确验证一次。
]]--
do
  local probe = TMP .. "/.probe"
  FS.write(probe, "x")
  local ok = FS.exists(probe)
  check("临时目录创建成功", ok, ok and TMP or "建不出来（检查 mkdir 是否跨平台）")
  if not ok then
    print()
    print(">>> 临时目录不可用，后续检查没有意义，提前退出")
    os.exit(1)
  end
end

print("---- ① 复制 lib/webui/*.lua ----")

local copiedLib = 0
local missingSrc = {}
for _, n in ipairs(LIB_FILES) do
  local s = FS.read(_root .. "/lib/webui/" .. n)
  if not s then
    missingSrc[#missingSrc + 1] = n
    print(string.format("  x %-22s 源文件不存在", n))
  else
    local wrote = FS.write(TMP .. "/" .. n, s)
    if wrote then
      copiedLib = copiedLib + 1
      print(string.format("  + %-22s %6d 字节", n, wrote))
    else
      print(string.format("  x %-22s 写入失败", n))
    end
  end
end

print("")
check("库文件全部复制", copiedLib == #LIB_FILES,
    string.format("%d/%d", copiedLib, #LIB_FILES))

-- ② 起始页
print("---- ② 复制起始页 ----")
local sampleSrc = FS.read(_root .. "/deploy/my_page.lua")
if sampleSrc then
  FS.write(TMP .. "/main.lua", sampleSrc)
  print("  + my_page.lua -> main.lua")
end
--[[ ★ 断言要查"目标文件真的写出来了"，不能只查源文件可读。

     踩过：这里原来只判断 sampleSrc ~= nil，
     结果目标目录没建起来时，这条依然显示 OK，
     后面才以"cannot open main.lua"的形式暴露，定位绕了远路。
]]--
check("起始页已复制", FS.exists(TMP .. "/main.lua"),
    sampleSrc and "已写入 main.lua" or "源文件 my_page.lua 读不到")

--=============================================================================
-- ③ 用真机风格的 loader 加载
--=============================================================================

print("")
print("---- ③ 用真机风格 require 加载 ----")

--[[ 真机语义：require 名【原样】当文件名，不做点号到路径的转换。
     本 loader 严格照此实现，所以：
       require('webui_util')  -> TMP/webui_util.lua   ✓
       require('webui.util')  -> TMP/webui.util.lua   ✗（文件不存在）
     这才是真正验证"扁平化是对的"，而不是只验证"文件在"。 ]]--
local loaded = {}
local realRequire = require

local function gameRequire(name)
  local key = tostring(name)
  if loaded[key] ~= nil then return loaded[key] end
  local path = TMP .. "/" .. key .. ".lua"
  local f = io.open(path, "rb")
  if not f then
    error("failed to load script '" .. key .. "'", 2)
  end
  local src = f:read("*a"); f:close()
  loaded[key] = true
  local chunk, err = load(src, "@" .. path)
  if not chunk then error(err, 2) end
  local mod = chunk()
  loaded[key] = mod or true
  return loaded[key]
end

-- 先自检 loader 的严格性：点号写法必须被拒
do
  local okDot = pcall(gameRequire, "webui.util")
  check("loader 严格：点号写法被拒", okDot == false,
      okDot and "竟然加载成功了（loader 不严格）" or "符合真机语义")
end

_G.require = gameRequire

--=============================================================================
-- ④ 搭 mock 并跑起来
--=============================================================================

local EngineMock = realRequire('engine_mock')
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

print("")
print("---- ④ 加载起始页并运行 ----")

local chunk, cerr = loadfile(TMP .. "/main.lua")
check("起始页可编译", chunk ~= nil, tostring(cerr))

local ok, err = pcall(chunk)
check("起始页可执行（库 require 全命中）", ok, ok and "OK" or tostring(err))

if ok then
  check("定义了 OnStart/OnUpdate/OnDestroy",
      type(OnStart) == "function" and type(OnUpdate) == "function"
      and type(OnDestroy) == "function")

  OnStart(); OnUpdate(0.016); pump()
  check("建出了控件", E.createdCount() > 0, "created=" .. E.createdCount())

  local function budget()
    for _, c in ipairs(E.controls) do
      local d = E.dataOf(c)
      local f = d and d.fields or {}
      if f.text and tostring(f.text):find("预算", 1, true) then return tostring(f.text) end
    end
    return nil
  end
  check("初始预算 0 / 4", budget() == "预算 0 / 4", tostring(budget()))

  -- 点第一张卡
  local clicked = false
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.kind == "button" and d.listeners then
      for _, l in ipairs(d.listeners) do
        if l.ev == "CursorClick" then
          pcall(l.cb, { GetUIPos=function() return 1,1 end,
                        GetPressUIPos=function() return 1,1 end,
                        GetUIPosDelta=function() return 0,0 end,
                        dragging=false, touchId=-1 })
          clicked = true
          break
        end
      end
      if clicked then break end
    end
  end
  pump()
  check("点击被派发", clicked)
  check("点击后预算变 1 / 4", budget() == "预算 1 / 4", tostring(budget()))

  local masked = 0
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.fields and d.fields.enableMask == true then masked = masked + 1 end
  end
  check("头像圆形裁剪已配置", masked >= 6, string.format("%d 个", masked))

  OnDestroy()
end

--=============================================================================
-- 收尾
--=============================================================================

FS.rmdir(TMP)

print("")
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end
print(">>> 纯复制即可用 ✓（无需任何构建步骤）")
