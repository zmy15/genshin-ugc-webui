--[[ 本地试跑 probe.lua 的三个模块]]--

-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
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
    --[[ ★ 键盘事件枚举（模拟真机 Enum 的用法：可显式索引）。
         探针的 key 模块靠它测 AddKeyEventListener 这条路。 ]]--
    KeyEventType = {
      KeyboardJumpKeyDown="KJmpD", KeyboardJumpKeyUp="KJmpU",
      KeyboardMoveLeftKeyDown="KMvLD", KeyboardMoveLeftKeyUp="KMvLU",
      KeyboardMoveRightKeyDown="KMvRD", KeyboardMoveRightKeyUp="KMvRU",
      KeyboardMoveForwardKeyDown="KMvFD", KeyboardMoveForwardKeyUp="KMvFU",
      KeyboardMoveBackwardKeyDown="KMvBD", KeyboardMoveBackwardKeyUp="KMvBU",
      KeyboardCraftspersonKey1Down="KC1D", KeyboardCraftspersonKey1Up="KC1U",
      KeyboardCraftspersonKey2Down="KC2D", KeyboardCraftspersonKey2Up="KC2U",
      KeyboardCraftspersonKey3Down="KC3D", KeyboardCraftspersonKey3Up="KC3U",
      KeyboardCraftspersonKey4Down="KC4D", KeyboardCraftspersonKey4Up="KC4U",
    },
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

--[[ ★ 当前 probe.lua 只有 key 一个模块（text/mask/glyph/clip/mount 已移除，
     归档在 docs/探针模块归档.md）。将来加了新模块，往这个列表里补名字。 ]]--
for _, mod in ipairs({ "key" }) do
  -- 把 ACTIVE 替换成当前模块
  local patched, n = src:gsub('local ACTIVE = "%w+"', 'local ACTIVE = "' .. mod .. '"')
  if n == 0 then error("ACTIVE 替换失败: " .. mod) end

  print("")
  print("############ 模块: " .. mod .. " ############")

  local E = makeEnv()
  local ok, err = pcall(function()
    local chunk = assert(load(patched, "@probe"))
    chunk()
    OnInit(); OnStart(); OnUpdate(0.016)

    --[[ ★ key 模块必须【真的按键】才算跑通 ——
         否则只是"没崩溃"，而探针的核心（回调能否收到按键）
         根本没被执行到。这是「测试替身必须忠实」的要求。 ]]--
    if mod == "key" then
      local root = game.FindClientUIRoot("Root")
      local nListeners = E.keyListenerCount(root)
      print("  >> root 上已注册按键监听: " .. nListeners .. " 个")
      if nListeners == 0 then
        error("key 模块没有在 root 上注册任何按键监听")
      end

      -- 模拟按 3 次跳跃键（Down/Up）
      local hitDown, hitUp = 0, 0
      for i = 1, 3 do
        if E.fireKey(root, Enum.KeyEventType.KeyboardJumpKeyDown, { type = "JumpDown" }) then
          hitDown = hitDown + 1
        end
        if E.fireKey(root, Enum.KeyEventType.KeyboardJumpKeyUp, { type = "JumpUp" }) then
          hitUp = hitUp + 1
        end
      end
      print(string.format("  >> 模拟跳跃键 3 次: Down 被吞 %d 次, Up 被吞 %d 次", hitDown, hitUp))

      --[[ ★ 关键断言：回调必须一律 return false。
           若返回 true，fireKey 会报告"已被处理" —— 那在真机上
           就会吞掉同容器内其他按键（文档第 1317 行）。 ]]--
      if hitDown > 0 or hitUp > 0 then
        error(string.format("按键回调错误地返回了 true（Down 吞 %d, Up 吞 %d）—— "
              .. "真机上会吞掉同容器内其他按键", hitDown, hitUp))
      end

      -- 判读表已把统计打到日志里（见上面的【判读表】段落）
      print("  >> 按键回调未被吞，符合预期")
    end

    OnDestroy()
  end)

  if ok then
    print(">>> " .. mod .. " 跑通，控件数=" .. E.createdCount())
  else
    print(">>> " .. mod .. " 【崩溃】 " .. tostring(err))
    os.exit(1)
  end
end

print("")
print(">>> 探针模块全部跑通")
