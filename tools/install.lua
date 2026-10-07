--[[============================================================================
  install.lua  ——  一键把 webui 装进千星工程的 external_lua_file 目录

  为什么需要这个：
    "直接复制就能用"这件事本身有几个坑，手工做很容易漏：

      ① 库文件必须【扁平化重命名】才能被真机 require
         require('webui.util')  ->  同目录的 webui_util.lua
         （真机不支持子目录，也不认 .lua 后缀以外的写法）
         直接复制 lib/webui/ 整个文件夹进去是【不能用的】。

      ② 光有库没有页面代码，进游戏是空白的。
         所以要连同一个"起始页"一起放进去。

      ③ 使用说明必须和代码版本一致。
         旧版的 README 讲的是老 API（webui.new），照它写会踩坑。

    本脚本把这三件事一次做完，产物就是【能直接导入编辑器】的目录。

  用法：
    lua tools/install.lua "<external_lua_file 目录>"

  例如：
    lua tools/install.lua "C:/.../Beyond_Local_Save_Level/1073741828/external_lua_file"

  可选参数：
    --no-sample    不放起始页（只要库）
    --name=xxx     起始页文件名（默认 main.lua）
    --force        覆盖已存在的同名文件（默认也覆盖，保留此参数仅为兼容）
==============================================================================]]

-- 库模块（顺序无关，但保持与其它构建脚本一致便于维护）
local MODULES = {
  "util", "dom", "html", "css", "color", "style", "transition", "layout",
  "render", "clip", "event", "init",
}

local LIB_DIR = "lib/webui"

--=============================================================================
-- 参数解析
--=============================================================================

local OUT_DIR   = nil
local WANT_SAMPLE = true
local SAMPLE_NAME = "main.lua"

for _, a in ipairs(arg or {}) do
  if a == "--no-sample" then
    WANT_SAMPLE = false
  elseif a:match("^%-%-name=") then
    SAMPLE_NAME = a:match("^%-%-name=(.+)$")
  elseif not a:match("^%-%-") and OUT_DIR == nil then
    OUT_DIR = a
  end
end

if not OUT_DIR or OUT_DIR == "" then
  print("用法: lua tools/install.lua \"<external_lua_file 目录>\" [--no-sample] [--name=main.lua]")
  print()
  print("作用: 把库扁平化 + 起始页 + 使用说明 一次装好，")
  print("      产物可直接在编辑器里导入。")
  print()
  print("例如:")
  print([[  lua tools/install.lua "C:/.../Beyond_Local_Save_Level/1073741828/external_lua_file"]])
  os.exit(1)
end

-- 统一成不带尾分隔符的形式（真机 require 用的是同目录相对名）
OUT_DIR = OUT_DIR:gsub("[/\\]+$", "")

--=============================================================================
-- 小工具
--=============================================================================

local function readFile(path)
  local f = io.open(path, "r")
  if not f then return nil, "打不开 " .. path end
  local s = f:read("*a")
  f:close()
  return s
end

local function writeFile(path, content)
  local f = io.open(path, "wb")
  if not f then return false, "无法写入 " .. path end
  f:write(content)
  f:close()
  return true
end

local function join(dir, name)
  return dir .. "/" .. name
end

--[[ 把 require('webui.xxx') 改写成 require('webui_xxx')。

     ★ 必须用【斜杠】分隔目录：真机的 require 规则是"同目录 + 文件名"，
       扁平化之后名字里不能再有点（webui.util 会被当成点号路径而找不到）。
]]--
local function rewrite(src)
  src = src:gsub("require%s*%(%s*['\"]webui%.([%w_]+)['\"]%s*%)",
                 "require('webui_%1')")
  return src
end

local function findExternalRequires(src)
  local bad = {}
  for m in src:gmatch("require%s*%(%s*['\"]([^'\"]+)['\"]%s*%)") do
    if m:sub(1, 6) ~= "webui." and m ~= "webui" and m:sub(1, 6) ~= "webui_" then
      bad[#bad + 1] = m
    end
  end
  return bad
end

--=============================================================================
-- 0. 检查目标目录可用
--=============================================================================

local function dirExists(dir)
  -- 用一个只读探针判断（Lua 没有直接的 isdir）
  local f = io.open(join(dir, "."), "r")
  if f then f:close(); return true end
  -- 退而求其次：试着列目录（真机上 dir 不可用时返回 nil）
  return false
end

print("================================================================")
print(" webui 安装器")
print("================================================================")
print("目标目录: " .. OUT_DIR)
print()

--=============================================================================
-- 1. 安装库（扁平化）
--=============================================================================

print("---- [1/3] 安装库 ----")
print()

local problems = {}
local installed = 0

for _, name in ipairs(MODULES) do
  local src, err = readFile(LIB_DIR .. "/" .. name .. ".lua")
  if not src then
    problems[#problems + 1] = err
    print(string.format("  x %-10s %s", name, err))
  else
    -- 库不应该依赖 webui 之外的模块
    local bad = findExternalRequires(src)
    if #bad > 0 then
      problems[#problems + 1] = name .. " 依赖外部模块: " .. table.concat(bad, ", ")
    end

    local out = rewrite(src)
    local outName = (name == "init") and "webui.lua" or ("webui_" .. name .. ".lua")

    local ok, werr = writeFile(join(OUT_DIR, outName), out)
    if not ok then
      problems[#problems + 1] = werr
      print(string.format("  x %-20s %s", outName, werr))
    else
      installed = installed + 1
      print(string.format("  + %-20s %6d 字节", outName, #out))
    end
  end
end

print()
print(string.format("  库文件: %d/%d 个已安装", installed, #MODULES))

--=============================================================================
-- 2. 安装起始页
--=============================================================================

print()
print("---- [2/3] 安装起始页 ----")
print()

if WANT_SAMPLE then
  local sample, serr = readFile("deploy/my_page.lua")
  if not sample then
    problems[#problems + 1] = "找不到起始页模板 deploy/my_page.lua: " .. tostring(serr)
    print("  x 找不到 deploy/my_page.lua")
  else
    --[[ ★ 起始页里的 require 要改写成扁平名。

         页面用 pcall(require, "webui_clip") 再回落到 "webui.clip"，
         两种都留着没关系 —— 真机走前者，本地仓库走后者。
         但为了干净，这里统一改成扁平名。
    ]]--
    local out = sample:gsub('pcall%(require, "webui%.clip"%)', 'pcall(require, "webui_clip")')

    local ok, werr = writeFile(join(OUT_DIR, SAMPLE_NAME), out)
    if not ok then
      problems[#problems + 1] = werr
      print("  x " .. werr)
    else
      print(string.format("  + %-20s %6d 字节", SAMPLE_NAME, #out))
      print()
      print("  ★ 这个就是你要改的文件。")
      print("     里面除了底部 3 行生命周期接线，其余全是 HTML / CSS / 事件处理。")
    end
  end
else
  print("  (--no-sample：跳过)")
end

--=============================================================================
-- 3. 安装使用说明
--=============================================================================

print()
print("---- [3/3] 安装使用说明 ----")
print()

--[[ 说明文件名。

     ★ 用 ASCII 名而不是中文名：
       Lua 的 io.open 在 Windows 上写中文文件名会变成乱码
       （实测「使用说明.md」被写成「浣跨敤璇存槑.md」——
        UTF-8 字节被当成 GBK 解释了）。
       README 是通用惯例，任何人一看就懂，也避开这个坑。
]]--
local GUIDE_NAME = "README-webui.md"

local guide, gerr = readFile("tools/install_guide.md")
if not guide then
  problems[#problems + 1] = "找不到说明模板 tools/install_guide.md: " .. tostring(gerr)
  print("  x 找不到 tools/install_guide.md")
else
  -- 把说明里的占位符换成实际的起始页文件名
  guide = guide:gsub("@SAMPLE@", SAMPLE_NAME)

  local ok, werr = writeFile(join(OUT_DIR, GUIDE_NAME), guide)
  if not ok then
    problems[#problems + 1] = werr
    print("  x " .. werr)
  else
    print(string.format("  + %-20s %6d 字节", GUIDE_NAME, #guide))
  end
end

--=============================================================================
-- 收尾
--=============================================================================

print()
print("================================================================")

if #problems > 0 then
  print(" 安装过程中有问题：")
  for _, p in ipairs(problems) do print("   - " .. p) end
  print("================================================================")
  os.exit(1)
end

print(" 安装完成")
print("================================================================")
print()
print("接下来（必须做，否则进游戏看不到东西）：")
print("  1. 打开千星编辑器，把 external_lua_file 里的脚本【导入】到关卡")
print("     真机读的是关卡文件 .gil，不是这个文件夹 ——")
print("     只复制文件不导入是不生效的。")
print("  2. 给容器 / 文本框 / 按钮 / 图片各建一个控件模板，")
print("     把它们在编辑器里显示的索引号填进 " .. SAMPLE_NAME .. " 的 prefabs。")
print("  3. 进游戏就能看到起始页了。")
print()
print("想改成自己的界面：只改 " .. SAMPLE_NAME .. " 里的 HTML / CSS / 事件即可。")