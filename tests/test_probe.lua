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

  --[[ ★ TweenSequence 桩。

       ⚠️ 不能做成"同步立即执行回调" —— perf 模块靠 [回调里再次
          AppendCallback] 递归驱动 480 帧（4 档 x 120 帧），
          同步执行会【无限递归爆栈】。

       这里改成【入队】：Play() 把回调放进 pending，
       由测试显式 step() 逐步驱动，既能控制帧数，也不会爆栈。 ]]
  pendingCallbacks = {}
  game.TweenSequence = function()
    local s = { cb = nil }
    function s:AppendCallback(cb) s.cb = cb; return s end
    function s:AppendInterval() return s end
    function s:Play()
      if s.cb then pendingCallbacks[#pendingCallbacks + 1] = s.cb end
      return s
    end
    function s:Kill() return s end
    return s
  end
  return E
end

--[[ 驱动 N 帧：把当前队列里的回调各跑一次（回调内可能再入队） ]]--
local function stepFrames(n)
  for _ = 1, n do
    local batch = pendingCallbacks
    pendingCallbacks = {}
    for _, cb in ipairs(batch) do cb() end
  end
end

local src = io.open("deploy/probe.lua", "r"):read("*a")

--[[ ★ 当前 probe.lua 有 key / perf 两个模块（text/mask/glyph/clip/mount 已移除，
     归档在 docs/探针模块归档.md）。将来加了新模块，往这个列表里补名字。 ]]--
for _, mod in ipairs({ "key", "perf" }) do
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

    --[[ ★ perf 模块必须【真的把 4 档跑完】才算跑通 ——
         否则"没崩溃"毫无意义（它本来就是个异步循环）。

         4 档 x 120 帧 = 480 帧，再留点余量。 ]]--
    if mod == "perf" then
      local before = E.createdCount()
      print(string.format("  >> 压测前控件数: %d", before))

      --[[ ★ 捕获 perf 的日志输出，断言【4 档真的都跑完了】。

           只断言"控件数"是不够的 —— 曾有个 bug 让 li 从 0 开始
           （Lua 表 1-based），结果第一帧就"以为跑完了"，
           打印一张空判读表，而控件数照样是 165，测试照样通过。
           所以必须断言【每档都记录到了结果】。 ]]--
      local logs = {}
      local realPrint = print
      print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[#parts+1] = tostring((select(i, ...))) end
        logs[#logs+1] = table.concat(parts, " ")
      end
      stepFrames(600)
      print = realPrint

      local joined = table.concat(logs, "\n")
      local lvCount = 0
      for _ in joined:gmatch("%[L%d[^%]]*%]") do lvCount = lvCount + 1 end
      print(string.format("  >> 记录的档位结果数: %d（应为 4）", lvCount))
      if lvCount ~= 4 then
        error(string.format(
          "perf 没有跑完 4 档（实际记录 %d 档）—— 判读表是空的", lvCount))
      end

      -- 判读表必须有 4 行数据（L1..L4）
      local hasVerdict = joined:find("✅") ~= nil or joined:find("⚠️") ~= nil
                     or joined:find("❌") ~= nil
      if not hasVerdict then
        error("perf 判读表没有产出任何判定")
      end

      print(string.format("  >> 驱动 600 帧后控件数: %d", E.createdCount()))
      if E.createdCount() < 100 then
        error("perf 模块没有真的建出压测方块（期望 >=100，实际 "
              .. E.createdCount() .. "）")
      end
      print(string.format("  >> 剩余待执行回调: %d（应为 0，说明循环已自然结束）",
          #pendingCallbacks))
      if #pendingCallbacks > 0 then
        error("perf 循环没有自然结束，仍在续期（剩余 "
              .. #pendingCallbacks .. "）")
      end
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
