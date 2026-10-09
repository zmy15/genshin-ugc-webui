--[[============================================================================
  build.lua  ——  把 webui 多文件模块打包成单个 Lua 文件

  用途：编辑器里脚本是"粘贴源码"，多文件 require 的路径映射需要确认；
        打成单文件最稳妥。

  注意：本文件刻意【不用】长括号字符串来生成代码，
        因为生成内容里的长括号结束符会被 Lua 提前消费（这是第一版的 bug）。

  用法：
    lua build.lua            -> 生成 bundle/webui.lua
    lua build.lua --check    -> 不写文件；把【重新生成的内容】与磁盘上现有的
                                bundle/webui.lua 逐行比对，检测产物是否过期。

  退出码（--check）：
    0 = 一致，或磁盘上还没有产物（bundle/ 未构建过，谈不上"过期"）
    1 = 不一致 —— 磁盘产物已过期，请重新构建
==============================================================================]]

local MODULES = {
  "util", "dom", "html", "css", "color", "style", "transition", "layout", "render",
  "clip", "sprite", "fit", "event", "signal", "init",
}

local LIB_DIR  = "lib/webui"
local OUT_FILE = "bundle/webui.lua"

--[[ 逻辑模块名 -> 实际文件名。

     ★ lib/webui/ 采用【真机可直接用】的扁平命名：
         webui.lua（入口，对应逻辑名 init）
         webui_util.lua / webui_clip.lua / ...
       这样整个文件夹拷进游戏工程就能跑，不需要构建改名。
       打包脚本这里跟着映射一下即可。
]]--
local function srcNameOf(logical)
  if logical == "init" then return "webui.lua" end
  return "webui_" .. logical .. ".lua"
end

--=============================================================================

local function readFile(path)
  local f = io.open(path, "r")
  if not f then return nil, "打不开 " .. path end
  local s = f:read("*a")
  f:close()
  return s
end

local function writeFile(path, content)
  local f = io.open(path, "w")
  if not f then return false, "无法写入 " .. path end
  f:write(content)
  f:close()
  return true
end

--[[ 把 require 改写成内部查表。

     lib/webui 现在是扁平命名，所以两种都要处理：
       require('webui_xxx')  -> __webui_require('xxx')
       require('webui')      -> __webui_require('init')
]]--
local function rewriteRequires(src)
  src = src:gsub("require%s*%(%s*['\"]webui_([%w_]+)['\"]%s*%)",
                 "__webui_require('%1')")
  src = src:gsub("require%s*%(%s*['\"]webui['\"]%s*%)",
                 "__webui_require('init')")
  return src
end

local function findExternalRequires(src)
  local out = {}
  for m in src:gmatch("require%s*%(%s*['\"]([^'\"]+)['\"]%s*%)") do
    out[#out + 1] = m
  end
  return out
end

--=============================================================================

local checkOnly = false
for _, a in ipairs(arg or {}) do
  if a == "--check" then checkOnly = true end
end

print("=== 打包 webui ===")
print()

local pieces = {}
local problems = {}

for _, name in ipairs(MODULES) do
  local path = LIB_DIR .. "/" .. srcNameOf(name)
  local src, err = readFile(path)
  if not src then
    problems[#problems + 1] = err
    print(string.format("  x %-10s %s", name, err))
  else
    local ext = findExternalRequires(src)
    local bad = {}
    for _, m in ipairs(ext) do
      -- 只允许库内部依赖：webui 或 webui_xxx
      if m ~= "webui" and m:sub(1, 6) ~= "webui_" then
        bad[#bad + 1] = m
      end
    end
    if #bad > 0 then
      problems[#problems + 1] = name .. " 依赖外部模块: " .. table.concat(bad, ",")
      print(string.format("  ! %-10s 外部依赖: %s", name, table.concat(bad, ",")))
    end

    pieces[#pieces + 1] = {
      name = name,
      src = rewriteRequires(src),
      lines = select(2, src:gsub("\n", "")) + 1,
    }
    print(string.format("  + %-10s %5d 行  %6d 字节", name,
        pieces[#pieces].lines, #src))
  end
end

print()

if #problems > 0 then
  print("!! 有问题:")
  for _, p in ipairs(problems) do print("   - " .. p) end
  print()
end

--=============================================================================
-- 生成单文件（用逐行拼接，避免长字符串陷阱）
--=============================================================================

local HEAD = "--" .. string.rep("=", 76)   -- 普通行注释，安全
local SEP  = "--" .. string.rep("-", 76)

local function L(...)
  local t = {}
  for i = 1, select('#', ...) do t[i] = tostring((select(i, ...))) end
  return table.concat(t, " ")
end

local buf = {}

-- ---- 文件头（用行注释，不用块注释，彻底避开 ]] 陷阱）----
buf[#buf+1] = HEAD
buf[#buf+1] = "-- webui.lua  ——  用 HTML/CSS 在千星奇域里渲染界面（单文件打包版）"
buf[#buf+1] = "--"
buf[#buf+1] = "-- 由 build.lua 自动生成，请勿手改。"
buf[#buf+1] = "-- 协议: MIT —— Copyright (c) 2026 zmy15（见仓库根目录 LICENSE）"
buf[#buf+1] = "-- 模块: " .. (function()
  local t = {}
  for _, p in ipairs(pieces) do t[#t+1] = p.name end
  return table.concat(t, ", ")
end)()
buf[#buf+1] = "--"
buf[#buf+1] = "-- 用法（二选一）："
buf[#buf+1] = "--   A. 编辑器支持路径映射时:"
buf[#buf+1] = "--        local webui = require('webui')"
buf[#buf+1] = "--   B. 直接粘贴源码时（推荐，最稳）:"
buf[#buf+1] = "--        local webui = __WEBUI__"
buf[#buf+1] = "--"
buf[#buf+1] = "-- 注意: 本文件末尾有 return；若粘贴进脚本，删掉最后一行即可，"
buf[#buf+1] = "--       改用全局 __WEBUI__。"
buf[#buf+1] = HEAD
buf[#buf+1] = ""

-- ---- 模块注册表 ----
buf[#buf+1] = SEP
buf[#buf+1] = "-- 模块注册表（替代 require 的文件查找）"
buf[#buf+1] = SEP
buf[#buf+1] = "local __webui_loaders = {}"
buf[#buf+1] = "local __webui_modules = {}"
buf[#buf+1] = "local __webui_loading = {}"
buf[#buf+1] = ""
buf[#buf+1] = "local function __webui_require(name)"
buf[#buf+1] = "  local m = __webui_modules[name]"
buf[#buf+1] = "  if m ~= nil then return m end"
buf[#buf+1] = "  if __webui_loading[name] then"
buf[#buf+1] = "    error('cyclic require: ' .. tostring(name))"
buf[#buf+1] = "  end"
buf[#buf+1] = "  local loader = __webui_loaders[name]"
buf[#buf+1] = "  if not loader then"
buf[#buf+1] = "    error('module not found: ' .. tostring(name))"
buf[#buf+1] = "  end"
buf[#buf+1] = "  __webui_loading[name] = true"
buf[#buf+1] = "  local result = loader()"
buf[#buf+1] = "  __webui_loading[name] = nil"
buf[#buf+1] = "  if result == nil then result = true end"
buf[#buf+1] = "  __webui_modules[name] = result"
buf[#buf+1] = "  return result"
buf[#buf+1] = "end"
buf[#buf+1] = ""

-- ---- 各模块 ----
for _, p in ipairs(pieces) do
  buf[#buf+1] = SEP
  buf[#buf+1] = "-- 模块: " .. p.name
  buf[#buf+1] = SEP
  buf[#buf+1] = "__webui_loaders['" .. p.name .. "'] = function()"
  buf[#buf+1] = p.src
  buf[#buf+1] = "end"
  buf[#buf+1] = ""
end

-- ---- 出口 ----
buf[#buf+1] = SEP
buf[#buf+1] = "-- 对外入口"
buf[#buf+1] = SEP
buf[#buf+1] = "__WEBUI__ = __webui_require('init')"
buf[#buf+1] = ""
buf[#buf+1] = "if type(require) == 'function' and type(package) == 'table'"
buf[#buf+1] = "   and type(package.preload) == 'table' then"
buf[#buf+1] = "  package.preload['webui'] = function() return __WEBUI__ end"
buf[#buf+1] = "end"
buf[#buf+1] = ""
buf[#buf+1] = "return __WEBUI__"
buf[#buf+1] = ""

local out = table.concat(buf, "\n")

--[[ --check 模式：把"重新生成的内容"与磁盘上现有的 bundle 逐行比对。

      ★ 这里曾经只打印一行"将生成 N 字节"就 return —— 从不读磁盘产物，
        所以任何情况下都 exit 0。而 .github/workflows/tests.yml 里那步
        「校验 bundle 与源码同步」把它当成了防线，于是成了一枚
        【永远不会红】的假绿勾。现在改成真比对，不一致就 exit 1。

      产物不存在时【不算过期】（bundle/ 在 .gitignore 里，全新克隆本来就没有），
      打印 [跳过] 后正常退出 —— 否则每个新克隆第一次跑 --check 都会红。
      这条分支由 tests/test_build_check.lua 覆盖。
]]--

if checkOnly then
  print("(--check 模式，不写文件)")
  print(string.format("  重新生成 %d 字节, %d 行",
      #out, select(2, out:gsub("\n", "")) + 1))

  local existing = readFile(OUT_FILE)
  if not existing then
    print("  [跳过] 磁盘上没有 " .. OUT_FILE .. "，无从比对（未构建过）")
    return
  end

  if existing == out then
    print(string.format("  [OK] 与磁盘产物一致（%d 行）",
        select(2, existing:gsub("\n", "")) + 1))
    return
  end

  -- ---- 不一致：给出能直接定位的摘要，别只丢一句"不一致" ----
  local function splitLines(s)
    local t = {}
    for line in (s .. "\n"):gmatch("(.-)\n") do t[#t + 1] = line end
    return t
  end

  local oldLines, newLines = splitLines(existing), splitLines(out)
  local total = math.max(#oldLines, #newLines)
  local diffCount, firstDiff = 0, nil
  for i = 1, total do
    if oldLines[i] ~= newLines[i] then
      diffCount = diffCount + 1
      if not firstDiff then firstDiff = i end
    end
  end

  local function clip(s)
    if s == nil then return "(无此行)" end
    if #s > 72 then return s:sub(1, 72) .. " …" end
    return s
  end

  print()
  print("  !! 磁盘产物已过期: " .. OUT_FILE .. " 与源码重新生成的结果不一致")
  print(string.format("     磁盘 %d 行   vs   重新生成 %d 行",
      #oldLines, #newLines))
  print(string.format("     差异行数 %d，首个差异在第 %d 行", diffCount, firstDiff))
  print("       磁盘: " .. clip(oldLines[firstDiff]))
  print("       新  : " .. clip(newLines[firstDiff]))
  print()
  print("     修复: lua tools/build.lua")
  os.exit(1)
end

-- 输出目录若不存在则自动创建（bundle/ 在 .gitignore 里，克隆后没有）
do
  local probe = io.open(OUT_FILE, "r")
  if probe then probe:close() else
    -- 尝试用 os.execute 创建目录（兼容 Windows 与类 Unix）
    local dir = OUT_FILE:match("^(.*)[/\\][^/\\]+$")
    if dir then
      os.execute('mkdir "' .. dir .. '" 2>nul || mkdir -p "' .. dir .. '" 2>/dev/null')
    end
  end
end

local ok, err = writeFile(OUT_FILE, out)
if not ok then
  print("!! " .. err)
  print("   请手动创建目录: " .. (OUT_FILE:match("^(.*)[/\\]") or "bundle"))
  return
end

print(string.format("  已生成 %s", OUT_FILE))
print(string.format("  %d 字节, %d 行", #out, select(2, out:gsub("\n",""))+1))

-- 自检
local chunk, loadErr = load(out, "bundle-selfcheck")
if chunk then
  print("  自检: 语法 OK")
else
  print("  !! 自检失败: " .. tostring(loadErr))
end
