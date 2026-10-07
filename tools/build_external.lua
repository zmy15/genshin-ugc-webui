--[[============================================================================
  build_external.lua  ——  把库部署到 external_lua_file 目录（只装库）

  ★ 这个脚本现在只是 install.lua 的薄封装，保留旧命令名以免既有文档/习惯失效。

    为什么不再需要"构建"：
      lib/webui/ 里的文件名与 require 已经是真机可直接用的扁平形式
      （webui_util.lua / require('webui_util')），
      所以"部署"退化成"复制" —— 不需要改名，也不需要改写 require。

      真机的 require 规则是"同目录 + 文件名原样"：
        require('webui_util') 找的就是 webui_util.lua
      所以整个文件夹拷进去就能用。

    区别：
      install.lua         装库 + 起始页 + 使用说明（推荐给新用户）
      build_external.lua  只装库（本脚本，适合只更新库文件的场景）

  用法：
    lua tools/build_external.lua "<目标目录>" [--check]

    --check  只检查源文件是否齐全，不写文件
==============================================================================]]

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
  print("提示: 想连起始页和使用说明一起装，用 tools/install.lua")
  os.exit(1)
end

-- 转交给 install.lua（--no-sample 表示只装库）。
--
-- 用 io.popen 执行会拿不到退出码的细节，这里直接用 os.execute 传参，
-- 目标目录用引号包住以兼容含空格/中文的路径。
local cmd = string.format('lua "%s/tools/install.lua" "%s" --no-sample',
    ".", target)

if checkOnly then
  -- 只校验源文件可读，不写目标
  local LIB_FILES = {
    "webui.lua",
    "webui_util.lua", "webui_dom.lua", "webui_html.lua", "webui_css.lua",
    "webui_color.lua", "webui_style.lua", "webui_transition.lua",
    "webui_layout.lua", "webui_render.lua", "webui_clip.lua", "webui_event.lua",
  }
  print("---- 检查源文件（--check，不写目标）----")
  print()
  local missing = 0
  for _, n in ipairs(LIB_FILES) do
    local f = io.open("lib/webui/" .. n, "rb")
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

print("---- 转交 install.lua（只装库）----")
print()
local rc = os.execute(cmd)
if rc ~= 0 and rc ~= true then
  print()
  print("!! 安装失败")
  os.exit(1)
end
