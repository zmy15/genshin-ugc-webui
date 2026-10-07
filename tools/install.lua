--[[============================================================================
  install.lua  ——  把 webui 装进千星工程的 external_lua_file 目录

  ★ 现在只是"复制"，不再做任何改名或改写。

    为什么可以这么简单：
      lib/webui/ 里的文件名与 require 已经是【真机可直接用】的扁平形式：
        lib/webui/webui.lua        <- 入口
        lib/webui/webui_util.lua   <- require('webui_util')
        lib/webui/webui_clip.lua   <- require('webui_clip')
        ...
      真机的 require 规则是"同目录 + 文件名原样"（require('webui_util')
      找的就是 webui_util.lua），所以整个文件夹拷进去就能用，
      不需要构建、不需要重命名。

  用法：
    lua tools/install.lua "<external_lua_file 目录>"

  例如：
    lua tools/install.lua "C:/.../Beyond_Local_Save_Level/1073741828/external_lua_file"

  可选：
    --no-sample       不放起始页（只要库）
    --name=xxx.lua    起始页文件名（默认 main.lua）
==============================================================================]]

-- 库文件（必须与 lib/webui 下的实际文件名一致）
local LIB_FILES = {
  "webui.lua",
  "webui_util.lua", "webui_dom.lua", "webui_html.lua", "webui_css.lua",
  "webui_color.lua", "webui_style.lua", "webui_transition.lua",
  "webui_layout.lua", "webui_render.lua", "webui_clip.lua", "webui_event.lua",
}

local LIB_DIR = "lib/webui"

local SAMPLE_SRC  = "deploy/my_page.lua"
local GUIDE_SRC   = "tools/install_guide.md"

--=============================================================================
-- 参数
--=============================================================================

local OUT_DIR     = nil
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
  print("作用: 把库 + 起始页 + 使用说明 复制过去，产物可直接在编辑器里导入。")
  print()
  print("例如:")
  print([[  lua tools/install.lua "C:/.../Beyond_Local_Save_Level/1073741828/external_lua_file"]])
  os.exit(1)
end

OUT_DIR = OUT_DIR:gsub("[/\\]+$", "")

--=============================================================================
-- 工具
--=============================================================================

local function readFile(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end

local function writeFile(p, s)
  local f = io.open(p, "wb")
  if not f then return false end
  f:write(s); f:close(); return true
end

local function join(a, b) return a .. "/" .. b end

--=============================================================================
-- 执行
--=============================================================================

print("================================================================")
print(" webui 安装器")
print("================================================================")
print("目标目录: " .. OUT_DIR)
print()

local problems = {}

--------------------------------------------------------------------------
-- 1. 库：直接复制（内容一字不改）
--------------------------------------------------------------------------
print("---- [1/3] 复制库 ----")
print()

local copied = 0
for _, name in ipairs(LIB_FILES) do
  local src = readFile(join(LIB_DIR, name))
  if not src then
    problems[#problems + 1] = "找不到 " .. join(LIB_DIR, name)
    print(string.format("  x %-22s 源文件不存在", name))
  else
    if writeFile(join(OUT_DIR, name), src) then
      copied = copied + 1
      print(string.format("  + %-22s %6d 字节", name, #src))
    else
      problems[#problems + 1] = "写不进 " .. join(OUT_DIR, name)
      print(string.format("  x %-22s 写入失败", name))
    end
  end
end

print()
print(string.format("  库文件: %d/%d", copied, #LIB_FILES))

--------------------------------------------------------------------------
-- 2. 起始页
--------------------------------------------------------------------------
print()
print("---- [2/3] 复制起始页 ----")
print()

if WANT_SAMPLE then
  local s = readFile(SAMPLE_SRC)
  if not s then
    problems[#problems + 1] = "找不到起始页模板 " .. SAMPLE_SRC
    print("  x 找不到 " .. SAMPLE_SRC)
  else
    if writeFile(join(OUT_DIR, SAMPLE_NAME), s) then
      print(string.format("  + %-22s %6d 字节", SAMPLE_NAME, #s))
      print()
      print("  ★ 这个就是要改的文件。")
      print("     除底部 3 行生命周期接线，其余全是 HTML / CSS / 事件处理。")
    else
      problems[#problems + 1] = "写不进 " .. SAMPLE_NAME
      print("  x 写入失败")
    end
  end
else
  print("  (--no-sample：跳过)")
end

--------------------------------------------------------------------------
-- 3. 使用说明
--------------------------------------------------------------------------
print()
print("---- [3/3] 复制使用说明 ----")
print()

local guide = readFile(GUIDE_SRC)
if not guide then
  problems[#problems + 1] = "找不到说明模板 " .. GUIDE_SRC
  print("  x 找不到 " .. GUIDE_SRC)
else
  -- 把占位符换成实际的起始页文件名
  guide = guide:gsub("@SAMPLE@", SAMPLE_NAME)

  --[[ 说明文件名用 ASCII。

       ★ Lua 的 io.open 在 Windows 上写中文文件名会乱码
         （实测「使用说明.md」被写成「浣跨敤璇存槑.md」）。
  ]]--
  local GUIDE_NAME = "README-webui.md"
  if writeFile(join(OUT_DIR, GUIDE_NAME), guide) then
    print(string.format("  + %-22s %6d 字节", GUIDE_NAME, #guide))
  else
    problems[#problems + 1] = "写不进 " .. GUIDE_NAME
    print("  x 写入失败")
  end
end

--------------------------------------------------------------------------
print()
print("================================================================")

if #problems > 0 then
  print(" 有问题：")
  for _, p in ipairs(problems) do print("   - " .. p) end
  print("================================================================")
  os.exit(1)
end

print(" 安装完成")
print("================================================================")
print()
print("接下来（这两步不能省，否则进游戏看不到东西）：")
print("  1. 打开千星编辑器，把 external_lua_file 里的脚本【导入】到关卡。")
print("     真机读的是关卡文件 .gil，不是这个文件夹 ——")
print("     只复制文件不导入是不生效的。")
print("  2. 给容器 / 文本框 / 按钮 / 图片各建一个控件模板，")
print("     把它们在编辑器里显示的索引号填进 " .. SAMPLE_NAME .. " 的 prefabs。")
print()
print("之后进游戏就能看到起始页。想改成自己的界面：")
print("只改 " .. SAMPLE_NAME .. " 里的 HTML / CSS / 事件即可，库不用动。")
