--[[============================================================================
  build_external.lua  ——  为 external_lua_file 目录生成扁平化的库文件

  背景：
    external_lua_file 目录里的 require 规则是【同目录 + 文件名】，
    不支持子目录。所以要把 webui/*.lua 扁平化成 webui_xxx.lua。

    require("webui")        -> webui.lua
    require("webui_html")   -> webui_html.lua
    ...

  做法：
    1. 把每个模块的 require('webui.xxx') 改写成 require('webui_xxx')
    2. 输出到目标目录
==============================================================================]]

local MODULES = {
  "util", "dom", "html", "css", "color", "style", "transition", "layout",
  "render", "clip", "event", "init",
}

local LIB_DIR = "lib/webui"

-- 目标目录（千星的 external_lua_file）
-- ⚠️ 路径含中文，直接写在源码里有编码风险（实测字节数不对）。
--    改为从命令行参数传入，或从下面这个【无中文】的等效短路径推导。
--
-- 用法:
--   lua build_external.lua "<目标目录>"
--
local OUT_DIR = arg and arg[1]

if not OUT_DIR or OUT_DIR == "" then
  print("用法: lua build_external.lua \"<external_lua_file 目录>\"")
  print()
  print("例如:")
  print([[  lua tools/build_external.lua "<游戏关卡目录>/external_lua_file"]])
  return
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

--[[ 把 require('webui.xxx') 改成 require('webui_xxx') ]]--
local function rewrite(src)
  -- require('webui.html')  -> require('webui_html')
  src = src:gsub("require%s*%(%s*['\"]webui%.([%w_]+)['\"]%s*%)",
                 "require('webui_%1')")
  -- require('webui')  -> require('webui')
  src = src:gsub("require%s*%(%s*['\"]webui['\"]%s*%)",
                 "require('webui')")
  return src
end

local function findRequires(src)
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

-- 校验目标目录存在
local probe = io.open(OUT_DIR .. "\\ClickCounter.lua", "r")
if not probe then
  print("!! 目标目录不可访问:")
  print("   " .. OUT_DIR)
  print("   请确认路径正确、游戏未占用")
  return
end
probe:close()
print("目标目录: OK")
print()

local problems = {}

for _, name in ipairs(MODULES) do
  local src, err = readFile(LIB_DIR .. "/" .. name .. ".lua")
  if not src then
    problems[#problems + 1] = err
    print(string.format("  x %-8s %s", name, err))
  else
    -- 检查外部依赖（只允许 webui.* 和 webui）
    local bad = {}
    for _, m in ipairs(findRequires(src)) do
      if m:sub(1, 6) ~= "webui." and m ~= "webui" then
        bad[#bad + 1] = m
      end
    end
    if #bad > 0 then
      problems[#problems + 1] = name .. " 依赖外部模块: " .. table.concat(bad, ",")
    end

    local out = rewrite(src)

    -- 水平规则：输出文件名
    local outName = (name == "init") and "webui.lua" or ("webui_" .. name .. ".lua")
    local outPath = OUT_DIR .. "\\" .. outName

    if checkOnly then
      print(string.format("  (check) %-22s <- %s", outName, name .. ".lua"))
    else
      local ok, werr = writeFile(outPath, out)
      if not ok then
        problems[#problems + 1] = werr
        print(string.format("  x %-22s %s", outName, werr))
      else
        -- 列出改写后的 require，便于核对
        local reqs = {}
        for _, m in ipairs(findRequires(out)) do
          if reqs[#reqs+1] == nil then reqs[#reqs+1] = m end
        end
        local uniq = {}
        local seen = {}
        for _, m in ipairs(reqs) do
          if not seen[m] then seen[m] = true; uniq[#uniq+1] = m end
        end
        print(string.format("  + %-22s %6d 字节   依赖: %s",
            outName, #out,
            (#uniq > 0) and table.concat(uniq, ", ") or "无"))
      end
    end
  end
end

print()
if #problems > 0 then
  print("!! 问题:")
  for _, p in ipairs(problems) do print("   - " .. p) end
else
  print("全部完成，无问题")
end
