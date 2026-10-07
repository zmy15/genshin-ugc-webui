--[[ 验证安装产物在"纯净环境"下能真的跑起来。

     模拟真机的行为：
       - 只有一个扁平目录，没有 package.path 里的 lib/
       - require 只能按"同目录 + 文件名"解析（这里用自定义 loader 模拟）
       - 然后 dofile 起始页，跑生命周期

     这是"复制导入就能用"的最终验收：如果这里过不了，
     说明交到用户手里的东西是跑不起来的。
]]--

local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local TARGET = arg and arg[1]

--[[ ★ 不传参数时自己造一个临时安装目录。

     这样它才能进 `for f in tests/test_*.lua` 的常规全量跑。
     需要手动准备环境的测试不算回归测试 ——
     忘了准备就永远失败，反而会让人把整个套件跑红当噪音忽略。
]]--
local CLEANUP = nil
local FROM_INSTALLER = false   -- 目录是不是 install.py 产出的
local RAW_COPY = false         -- 是不是"纯复制"场景（手动拷库 + 页面）

-- 跨平台的文件系统辅助（CI 是 Linux，本地是 Windows）
local FS = require('fs_util')

if not TARGET then
  -- 用仓库内的临时目录（tests/ 可写），跑完删掉
  TARGET = (_root .. "/tests/_install_tmp"):gsub("//", "/")
  CLEANUP = TARGET
  FROM_INSTALLER = true

  -- 先清掉上一次的残留
  FS.rmdir(TARGET)
  FS.mkdir(TARGET)

  --[[ ★ 临时目录必须真的建出来了。

       踩过：这里原来用 `mkdir "..." 2>nul`（Windows 写法），
       在 CI 的 ubuntu 上静默失败，install.py 于是正确地报
       "目标目录不存在" —— 测试看上去是安装器坏了，其实是测试自己没建目录。
       先明确验证一次，别让这种问题伪装成"被测代码有问题"。
  ]]--
  local probe = TARGET .. "/.probe"
  FS.write(probe, "x")
  if not FS.exists(probe) then
    print("!! 临时目录建不出来: " .. TARGET)
    print("   平台: " .. (FS.IS_WINDOWS and "Windows" or "Unix"))
    print("   检查 tests/fs_util.lua 的 mkdir 是否覆盖了当前平台。")
    os.exit(1)
  end

  --[[ 调安装器。

       ★ 安装器是 Python 写的（tools/install.py）。
         它内部按自身位置解析 lib/ 等源文件，所以传绝对路径最稳。
         解释器按常见名字试：python / python3 / py -3。
  ]]--
  local installPy = _root .. "/tools/install.py"
  local candidates = { "python", "python3", "py -3" }

  local rc = nil
  local usedExe = nil
  for _, exe in ipairs(candidates) do
    -- ★ 用 FS.SILENT 而不是写死 ">nul"：后者在 Linux 上不是重定向
    local probe = os.execute(exe .. " --version" .. FS.SILENT)
    if probe == 0 or probe == true then
      usedExe = exe
      rc = os.execute(string.format('%s "%s" "%s"', exe, installPy, TARGET))
      break
    end
  end

  if not usedExe then
    print("!! 找不到 Python 解释器，无法自动安装。")
    print("   安装器现在是 tools/install.py（Python 写的）。")
    print("   请先确保 python / python3 在 PATH 上。")
    os.exit(1)
  end

  if rc ~= 0 and rc ~= true then
    print("!! 无法自动安装到临时目录，请手动运行：")
    print('   ' .. usedExe .. ' tools/install.py "' .. TARGET .. '"')
    os.exit(1)
  end
  print("(自动安装到临时目录: " .. TARGET .. "，解释器: " .. usedExe .. ")")
else
  --[[ 传了目录参数：判断它是"安装器产物"还是"纯复制"。

       ★ 这个区分很重要。
         lib/webui/ 现在已经改成真机可直接用的扁平命名，
         所以用户【手动拷 lib/webui/*.lua】也应该能跑 ——
         那是本次改动要保证的核心能力，必须单独验证。

         纯复制不会有 README-webui.md（那是 install.py 额外放的），
         所以不能把"必须有 README"当成本场景的失败。
  ]]--
  local g = io.open(TARGET .. "/README-webui.md", "r")
  if g then g:close(); FROM_INSTALLER = true else RAW_COPY = true end
end
TARGET = TARGET:gsub("[/\\]+$", "")

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-32s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-32s %s", name, detail or "")) end
end

print("=== 验证安装产物: " .. TARGET .. " ===")
print("  场景: " .. (RAW_COPY and "纯复制（手动拷 lib/webui/*.lua + 起始页）"
                              or "安装器产物（install.py）"))
print("")

--=============================================================================
-- 1. 文件清单
--=============================================================================

local REQUIRED = {
  "webui.lua", "webui_util.lua", "webui_dom.lua", "webui_html.lua",
  "webui_css.lua", "webui_color.lua", "webui_style.lua", "webui_transition.lua",
  "webui_layout.lua", "webui_render.lua", "webui_clip.lua", "webui_event.lua",
}
for _, n in ipairs(REQUIRED) do
  local f = io.open(TARGET .. "/" .. n, "r")
  if f then f:close() end
  check("存在 " .. n, f ~= nil)
end

local sample = io.open(TARGET .. "/main.lua", "r")
if sample then sample:close() end
check("存在起始页 main.lua", sample ~= nil)

--=============================================================================
-- 2. 模拟真机的 require：同目录 + 扁平文件名，不支持子目录
--=============================================================================

local loaded = {}
local realRequire = require

-- 用一个只认"扁平同名文件"的 loader，模拟真机
local function gameRequire(name)
  if loaded[name] then return loaded[name] end
  -- 真机：require('webui_util') -> 同目录 webui_util（自动补 .lua）
  local path = TARGET .. "/" .. name:gsub("%.", "/") .. ".lua"
  local f = io.open(path, "rb")
  if not f then
    -- 真机不支持子目录：点号不会变成路径，直接失败
    error("failed to load script '" .. name .. "'", 2)
  end
  local src = f:read("*a")
  f:close()

  loaded[name] = true
  local chunk, err = load(src, "@" .. path)
  if not chunk then error(err, 2) end
  local mod = chunk()
  loaded[name] = mod or true
  return loaded[name]
end

-- 让 package.loaded 里没有旧缓存，确保真的走我们的 loader
for _, n in ipairs(REQUIRED) do
  local key = n:gsub("%.lua$", "")
  package.loaded[key] = nil
end

_G.require = gameRequire

--=============================================================================
-- 3. 搭 mock 环境
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

--=============================================================================
-- 4. 加载起始页并跑生命周期
--=============================================================================

print("")
print("--- 用真机风格的 require 加载起始页 ---")

local chunk, cerr = loadfile(TARGET .. "/main.lua")
check("起始页能编译", chunk ~= nil, tostring(cerr))

local ok, err = pcall(chunk)
check("起始页能执行（require 全部命中）", ok,
    ok and "OK" or tostring(err))

if ok then
  check("定义了 OnStart",  type(OnStart)  == "function")
  check("定义了 OnUpdate", type(OnUpdate) == "function")
  check("定义了 OnDestroy",type(OnDestroy)== "function")

  OnStart()
  OnUpdate(0.016)
  pump()

  check("建出了控件", E.createdCount() > 0, "created=" .. E.createdCount())

  -- 交互：点第一张卡，预算应变化
  local function budget()
    for _, c in ipairs(E.controls) do
      local d = E.dataOf(c)
      local f = d and d.fields or {}
      if f.text and tostring(f.text):find("预算", 1, true) then return tostring(f.text) end
    end
    return nil
  end

  local b0 = budget()
  check("初始预算 0 / 4", b0 == "预算 0 / 4", tostring(b0))

  local clicked = 0
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.kind == "button" and d.listeners then
      for _, l in ipairs(d.listeners) do
        if l.ev == "CursorClick" then
          pcall(l.cb, { GetUIPos=function() return 1,1 end,
                        GetPressUIPos=function() return 1,1 end,
                        GetUIPosDelta=function() return 0,0 end,
                        dragging=false, touchId=-1 })
          clicked = clicked + 1
          break   -- 只点一个
        end
      end
      if clicked > 0 then break end
    end
  end
  pump()
  check("点击被派发", clicked > 0)
  check("点击后预算变为 1 / 4", budget() == "预算 1 / 4",
      string.format("%s -> %s", tostring(b0), tostring(budget())))

  -- 图片形状
  local masked = 0
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.fields and d.fields.enableMask == true then masked = masked + 1 end
  end
  check("头像圆形裁剪已配置", masked >= 6, string.format("%d 个", masked))

  -- 文字硬约束
  local bad, n = 0, 0
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.kind == "textbox" then
      local f = d.fields or {}
      if f.text and f.text ~= "" and f.fontSize and f.fontSize > 0 and f.sizeDeltaY then
        n = n + 1
        if f.sizeDeltaY / f.fontSize < 1.9 then bad = bad + 1 end
      end
    end
  end
  check("文字框高 >= 字号 x1.9", bad == 0, string.format("检查 %d 个，违反 %d", n, bad))

  OnDestroy()
end

-- 说明文件（只有 install.py 的产物才有；纯复制场景不做要求）
-- ★ 名字必须是 ASCII：Lua 的 io.open 在 Windows 上写中文文件名会乱码
--   （实测「使用说明.md」变成「浣跨敤璇存槑.md」）
local g = io.open(TARGET .. "/README-webui.md", "r")
if FROM_INSTALLER then
  check("存在 README-webui.md", g ~= nil)
else
  print(string.format("  [--] %-32s %s", "README-webui.md",
      "纯复制场景不要求（install.py 才会放）"))
end
if g then
  local txt = g:read("*a"); g:close()
  check("说明里没有未替换的占位符", not txt:find("@SAMPLE@", 1, true),
      txt:find("@SAMPLE@", 1, true) and "仍有 @SAMPLE@" or "干净")
  check("说明里写了起始页文件名", txt:find("main.lua", 1, true) ~= nil
        or txt:find(SAMPLE_NAME or "main.lua", 1, true) ~= nil)

  --[[ ★ 编码检查：内容必须还是 UTF-8 中文，不能变成问号或乱码字节。

       踩过：Windows 上用 Set-Content / Get-Content 往返中文会把
       UTF-8 按 GBK 重新编码，文件名与内容一起坏掉。
       这里直接看字节：中文应出现 UTF-8 的三字节序列（EF/Ex 开头）。
  ]]--
  check("说明内容含 UTF-8 中文", txt:find("\228\189\191\231\148\168", 1, true) ~= nil,
      "找 '使用' 的 UTF-8 字节")
end

-- 起始页里的中文也要完好
do
  local f = io.open(TARGET .. "/main.lua", "r")
  if f then
    local t = f:read("*a"); f:close()
    -- 「队伍配置」的 UTF-8 字节
    check("起始页内容含 UTF-8 中文",
        t:find("\233\152\159\228\188\141", 1, true) ~= nil,
        "找 '队伍' 的 UTF-8 字节")
  end
end

-- 目录里不应有非 ASCII 文件名（中文名会乱码）
do
  local names = FS.listdir(TARGET)
  local weird = {}
  for _, line in ipairs(names) do
    -- 文件名里出现 0x80 以上字节 => 非 ASCII
    local hasHigh = false
    for i = 1, #line do
      if line:byte(i) > 127 then hasHigh = true; break end
    end
    if hasHigh then weird[#weird + 1] = line end
  end
  check("没有非 ASCII 文件名", #weird == 0,
      #weird > 0 and table.concat(weird, ", ") or "全部 ASCII")
end

print("")
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))

-- 清理自动创建的临时目录
if CLEANUP then
  FS.rmdir(CLEANUP)
end

if fail > 0 then os.exit(1) end
print(">>> 安装产物可直接使用 ✓")
