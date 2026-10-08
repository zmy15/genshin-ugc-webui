--[[============================================================================
  build_external.lua  ——  把库部署到 external_lua_file 目录（只装库）

  ★ 这个脚本现在只是 install.py 的薄封装，保留旧命令名以免既有文档/习惯失效。

    为什么不再需要"构建"：
      lib/webui/ 里的文件名与 require 已经是真机可直接用的扁平形式
      （webui_util.lua / require('webui_util')），
      所以"部署"退化成"复制" —— 不需要改名，也不需要改写 require。

      真机的 require 规则是"同目录 + 文件名原样"：
        require('webui_util') 找的就是 webui_util.lua
      所以整个文件夹拷进去就能用。

    区别：
      install.py          装库 + 起始页 + 使用说明（推荐给新用户）
      build_external.lua  只装库（本脚本，适合只更新库文件的场景）

  用法：
    lua tools/build_external.lua "<目标目录>" [--check]

    --check  只检查源文件是否齐全，不写文件
==============================================================================]]

-- 脚本自身所在目录（仓库的 tools/），用于定位 install.py 与 lib/
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local TOOLS_DIR = _here:match("^(.*)/[^/]+$") or "."

local target = nil
local checkOnly = false

for _, a in ipairs(arg or {}) do
  if a == "--check" then
    checkOnly = true
  elseif not a:match("^%-%-") and target == nil then
    target = a
  end
end

if not target or target == "" then
  print("用法: lua tools/build_external.lua \"<external_lua_file 目录>\" [--check]")
  print()
  print("例如:")
  print([[  lua tools/build_external.lua "<游戏关卡目录>/external_lua_file"]])
  print()
  print("提示: 想连起始页和使用说明一起装，用 tools/install.py")
  os.exit(1)
end

local LIB_FILES = {
  "webui.lua",
  "webui_util.lua", "webui_dom.lua", "webui_html.lua", "webui_css.lua",
  "webui_color.lua", "webui_style.lua", "webui_transition.lua",
  "webui_layout.lua", "webui_render.lua", "webui_clip.lua",
  "webui_sprite.lua", "webui_event.lua", "webui_signal.lua",
}

--=============================================================================
-- --check：只校验源文件可读
--=============================================================================

if checkOnly then
  local libDir = TOOLS_DIR .. "/../lib/webui"
  print("---- 检查源文件（--check，不写目标）----")
  print()

  local missing = 0
  for _, n in ipairs(LIB_FILES) do
    local f = io.open(libDir .. "/" .. n, "rb")
    if f then
      f:close()
      print(string.format("  ok  lib/webui/%s", n))
    else
      missing = missing + 1
      print(string.format("  x   缺 lib/webui/%s", n))
    end
  end

  print()
  if missing > 0 then
    print(string.format("!! 缺 %d 个库文件", missing))
    os.exit(1)
  end
  print("全部库文件就位")
  print()
  print("（真实部署请去掉 --check）")
  os.exit(0)
end

--=============================================================================
-- 转交给 install.py（--no-sample 表示只装库）
--=============================================================================

--[[ 安装器是 Python 写的，这里 shell out 过去。

     ★ 用 install.py 的【绝对路径】调用：
       它内部按脚本位置解析 lib/ 等源文件，
       所以从任何工作目录执行都能找到，不受 cwd 影响。

     python 解释器按常见名字依次尝试：
       python / python3 / py -3
     找不到时给出明确提示，而不是静默失败。
]]--
local installPy = TOOLS_DIR .. "/install.py"

local function quote(s)
  return '"' .. tostring(s):gsub('"', '\\') .. '"'
end

-- 组装"用某个解释器执行 install.py"的完整命令
--
-- ★ 传 --no-sample --no-guide：本脚本的契约是"只装库"。
--   若只传 --no-sample，说明文件还是会写进去，
--   而那份说明会让读者去改 main.lua —— 但库模式下并没有这个文件。
local function buildCmd(exe, prefixArgs)
  local cmd = exe
  for _, a in ipairs(prefixArgs or {}) do cmd = cmd .. " " .. a end
  return cmd .. " " .. quote(installPy) .. " " .. quote(target)
      .. " --no-sample --no-guide"
end

--[[ 依次尝试常见解释器名，用 `--version` 探测是否可用。

     python / python3 / py -3
]]--
print("---- 转交 install.py（只装库）----")
print()

local candidates = {
  { "python" },
  { "python3" },
  { "py", { "-3" } },
}

local chosen = nil
for _, c in ipairs(candidates) do
  local probeExe = c[1]
  for _, a in ipairs(c[2] or {}) do probeExe = probeExe .. " " .. a end

  local okProbe = os.execute(probeExe .. " --version >nul 2>&1")
  if okProbe == 0 or okProbe == true then
    chosen = buildCmd(c[1], c[2])
    break
  end
end

if not chosen then
  print("!! 找不到 Python 解释器。")
  print("   安装器现在是用 Python 写的，请先确保 python 或 python3 在 PATH 上。")
  print()
  print("   或直接手动执行:")
  print(string.format('     python %s "%s" --no-sample --no-guide', installPy, target))
  os.exit(1)
end

local rc = os.execute(chosen)
if rc ~= 0 and rc ~= true then
  print()
  print("!! 安装失败")
  os.exit(1)
end
