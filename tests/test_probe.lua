--[[ 本地试跑 probe.lua 的三个模块]]--

-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')
local PREFABS = { container=1073741933, textbox=1073741934, button=1073741935, image=1073741938 }

local function makeEnv()
  local E = EngineMock.new(PREFABS)
  game = E.game
  Color = { FromRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
            FromRGB=function(r,g,b) return {r=r,g=g,b=b} end }
  Enum = {
    EaseType={Linear="Linear"},
    CursorEventType={CursorClick="C",CursorDown="D",CursorUp="U",CursorEnter="E",
                     CursorExit="X",CursorBeginDrag="B",CursorDrag="G",CursorEndDrag="N"},
    TextHorizontalAlignmentLeft="L", TextHorizontalAlignmentMiddle="C",
    TextHorizontalAlignmentRight="R",
    ImageSource={StaticReference="SR"},
  }
  local root = E.makeControl("container", nil)
  root.name = "Root"
  E.setRoots({ root })
  script = { object=root, EnableUpdate=function() end, GetParam=function() return nil end }
  printerr = function(...) io.stderr:write("[printerr] ", ...) end
  game.TweenSequence = function()
    local s = {}
    function s:AppendCallback() return s end
    function s:AppendInterval() return s end
    function s:Play() return s end
    function s:Kill() return s end
    return s
  end
  return E
end

local src = io.open("deploy/probe.lua", "r"):read("*a")

for _, mod in ipairs({ "text", "mask", "glyph", "clip" }) do
  -- 把 ACTIVE 替换成当前模块
  local patched, n = src:gsub('local ACTIVE = "%w+"', 'local ACTIVE = "' .. mod .. '"')
  if n == 0 then error("ACTIVE 替换失败: " .. mod) end

  print("")
  print("############ 模块: " .. mod .. " ############")

  local E = makeEnv()
  local ok, err = pcall(function()
    local chunk = assert(load(patched, "@probe"))
    chunk()
    OnInit(); OnStart(); OnUpdate(0.016); OnDestroy()
  end)

  if ok then
    print(">>> " .. mod .. " 跑通，控件数=" .. E.createdCount())
  else
    print(">>> " .. mod .. " 【崩溃】 " .. tostring(err))
    os.exit(1)
  end
end

print("")
print(">>> 三个模块全部跑通")
