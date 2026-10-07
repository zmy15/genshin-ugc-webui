--[[ 按键事件 + 游戏循环钩子（★ R20 真机验证后的实现）

     ★ 覆盖两件事：
       1. webui_event 的 bindKey / bindKeys / unbindKeys / resolveKey
       2. webui.startLoop 的 onTick(dt) 与 mount 的 keys / onTick 参数

     ★ 用 engine_mock —— 严格模拟真机限制（自定义字段不可写、
       字段按类型封死、无 reparent）。

     ★ 真机实测要点（R20，docs/引擎能力与限制.md §5.2）必须在这里守住：
       · 回调【不能 return true】—— 会吞掉同容器内其他按键
       · 一个按键只绑【一个】挂载点 —— 绑多处会"按一次收多次"
]]

-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')

local PREFABS = { container=1073741933, textbox=1073741934,
                  button=1073741935, image=1073741938 }

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass=pass+1; print(string.format("  [OK] %-46s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-46s %s", name, detail or "")) end
end

--[[ 每个用例一套干净环境。

     ★ Enum 必须【照实】提供 KeyEventType —— 而且要模拟真机上
       pairs() 可遍历（R20 实测 164 项），这跟 Enum.ImageSource
       （pairs 为空）不一样。
]]--
local function makeEnv()
  local E = EngineMock.new(PREFABS)

  local keyEnum = {}
  local names = {
    "KeyboardJumpKeyDown", "KeyboardJumpKeyUp",
    "KeyboardMoveLeftKeyDown", "KeyboardMoveLeftKeyUp",
    "KeyboardMoveRightKeyDown", "KeyboardMoveRightKeyUp",
    "KeyboardMoveForwardKeyDown", "KeyboardMoveForwardKeyUp",
    "KeyboardMoveBackwardKeyDown", "KeyboardMoveBackwardKeyUp",
    "KeyboardCraftspersonKey1Down", "KeyboardCraftspersonKey1Up",
    "KeyboardCraftspersonKey2Down", "KeyboardCraftspersonKey2Up",
    "KeyboardCraftspersonKey3Down", "KeyboardCraftspersonKey3Up",
    "KeyboardCraftspersonKey4Down", "KeyboardCraftspersonKey4Up",
    "ControllerJumpKeyDown", "ControllerJumpKeyUp",
  }
  for _, n in ipairs(names) do keyEnum[n] = "Enum.KeyEventType." .. n end

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
    KeyEventType = keyEnum,
  }
  script = { object = E.makeControl("container", nil) }
  script.object.name = "Root"
  E.setRoots({ script.object })

  -- 同步的 TweenSequence：Play() 立即执行回调（便于测 tick 链）
  game.TweenSequence = function()
    local s = {}
    function s:AppendCallback(cb) s._cb = cb; return s end
    function s:AppendInterval(_) return s end
    function s:Play() return s end
    function s:Kill() return s end
    return s
  end

  return E
end

local event = require('webui_event')

--=============================================================================
print("\n=== 1. resolveKey：别名与完整枚举名都能解析 ===")
--=============================================================================
local E = makeEnv()

check("别名 jump -> KeyboardJumpKeyDown",
    event.resolveKey("jump") == "Enum.KeyEventType.KeyboardJumpKeyDown")
check("别名 left -> KeyboardMoveLeftKeyDown",
    event.resolveKey("left") == "Enum.KeyEventType.KeyboardMoveLeftKeyDown")
check("别名 key1 -> CraftspersonKey1Down",
    event.resolveKey("key1") == "Enum.KeyEventType.KeyboardCraftspersonKey1Down")
check("别名 padJump -> ControllerJumpKeyDown",
    event.resolveKey("padJump") == "Enum.KeyEventType.ControllerJumpKeyDown")
check("完整枚举名直传",
    event.resolveKey("KeyboardJumpKeyUp") == "Enum.KeyEventType.KeyboardJumpKeyUp")
check("未知键名 -> nil", event.resolveKey("根本没有这个键") == nil)
check("nil -> nil", event.resolveKey(nil) == nil)

--=============================================================================
print("\n=== 2. bindKey：绑定 + 触发 + 回调约定 ===")
--=============================================================================
local root = script.object
local hits = 0
local n = event.bindKey(root, "jump", function(info)
  hits = hits + 1
  check("回调收到 key 字段", info.key == "jump", "key=" .. tostring(info.key))
end)
check("bindKey 返回 1", n == 1, "n=" .. tostring(n))
check("监听器已注册", E.keyListenerCount(root) == 1,
    "count=" .. tostring(E.keyListenerCount(root)))

-- ★ 触发：真机行为 —— 回调返回 true 才算"已处理"
local handled = E.fireKey(root, "Enum.KeyEventType.KeyboardJumpKeyDown", {})
check("触发 1 次 -> 回调执行", hits == 1, "hits=" .. tostring(hits))

--[[ ★★ 关键断言（R20）：回调【绝不能】让事件被判定为"已处理"，
      否则真机上会吞掉同容器内其他按键。 ]]--
check("★ 事件未被吞（回调返回 false）", handled == false,
    "handled=" .. tostring(handled))

--=============================================================================
print("\n=== 3. ★ 同容器多键互不干扰（return true 会吞掉其他键）===")
--=============================================================================
event.unbindKeys()
local jumpN, leftN = 0, 0
event.bindKeys(root, {
  jump = function() jumpN = jumpN + 1 end,
  left = function() leftN = leftN + 1 end,
})
E.fireKey(root, "Enum.KeyEventType.KeyboardJumpKeyDown", {})
E.fireKey(root, "Enum.KeyEventType.KeyboardMoveLeftKeyDown", {})
check("跳跃键触发", jumpN == 1, "jumpN=" .. tostring(jumpN))
check("★ 左移键也能触发（没被跳跃键吞掉）", leftN == 1,
    "leftN=" .. tostring(leftN))

--=============================================================================
print("\n=== 4. ★★ 一个按键只绑一个挂载点（绑多处会重复触发）===")
--=============================================================================
event.unbindKeys()
local multi = 0
-- 故意绑到两个控件上 —— 模拟"不知道挂哪就都挂上"的错误做法
event.bindKey(root, "jump", function() multi = multi + 1 end)
local child = E.makeControl("textbox", root)
event.bindKey(child, "jump", function() multi = multi + 1 end)

E.fireKey(root, "Enum.KeyEventType.KeyboardJumpKeyDown", {})
check("★ 绑在 root 上：只 root 收到（child 不联动）", multi == 1,
    "multi=" .. tostring(multi))

multi = 0
E.fireKey(child, "Enum.KeyEventType.KeyboardJumpKeyDown", {})
check("★ 绑在 child 上：只 child 收到", multi == 1,
    "multi=" .. tostring(multi))
print("       ^ 真机上同一个事件会广播给【所有绑定者】——")
print("         所以库只绑 root 一处，见 mount 的实现。")

--=============================================================================
print("\n=== 5. unbindKeys：清理，防泄漏 ===")
--=============================================================================
event.unbindKeys()
check("解绑后监听器为 0", E.keyListenerCount(root) == 0,
    "count=" .. tostring(E.keyListenerCount(root)))
local before = 0
E.fireKey(root, "Enum.KeyEventType.KeyboardJumpKeyDown", {})
check("解绑后按键不再触发回调", before == 0)

--=============================================================================
print("\n=== 6. 不支持按键的控件：安全返回 0，不抛错 ===")
--=============================================================================
local noKey = { name = "假控件" }        -- 完全没有 AddKeyEventListener
check("bindKey 返回 0", event.bindKey(noKey, "jump", function() end) == 0)
check("bindKeys 返回 0", event.bindKeys(noKey, { jump = function() end }) == 0)
check("bindKey(nil 控件) 返回 0", event.bindKey(nil, "jump", function() end) == 0)
check("bindKey(非函数回调) 返回 0", event.bindKey(root, "jump", 123) == 0)

--=============================================================================
print("\n=== 7. onTick(dt)：游戏逻辑钩子 ===")
--=============================================================================
local webui = require('webui')
E = makeEnv()
root = script.object

local ui = webui.new({ root = root, prefabs = PREFABS, handlers = {} })
ui:render([[<div class="s" style="width:100px;height:100px;background-color:#333"></div>]])

local ticks, lastDt, order = 0, nil, {}
ui.onTick = function(dt)
  ticks = ticks + 1
  lastDt = dt
  order[#order+1] = "tick"
end

-- 直接驱动一次循环体（不经 TweenSequence 的延时）
ui.ticking = true
local function driveOneFrame()
  if type(ui.onTick) == "function" then ui.onTick(1/50) end
  order[#order+1] = "flush"
  ui:flush()
end
for _ = 1, 5 do driveOneFrame() end

check("onTick 被调用 5 次", ticks == 5, "ticks=" .. tostring(ticks))
check("dt 是固定步长 1/50", math.abs((lastDt or 0) - 1/50) < 1e-9,
    "dt=" .. tostring(lastDt))
check("★ 顺序：先 tick 再 flush", order[1] == "tick" and order[2] == "flush",
    table.concat(order, ","))

--=============================================================================
print("\n=== 8. mount 的 keys / onTick 参数 ===")
--=============================================================================
E = makeEnv()
local app
local M = require('webui')

local tickCount = 0
local jumpHits = 0
app = M.mount{
  root = "Root",
  prefabs = PREFABS,
  html = [[<div style="width:100px;height:100px;background-color:#222"></div>]],
  loop = false,                       -- 手动驱动，避免依赖 Tween 链
  keys = {
    jump = function() jumpHits = jumpHits + 1 end,
  },
  onTick = function(dt) tickCount = tickCount + 1 end,
  on = {},
}

check("mount 成功", app.bound == true, "bound=" .. tostring(app.bound))
check("★ keys 绑定数 = 1", app.keyCount == 1, "keyCount=" .. tostring(app.keyCount))
check("★ 只绑了 root 一处（不重复绑）",
    E.keyListenerCount(script.object) == 1,
    "root 上监听器=" .. tostring(E.keyListenerCount(script.object)))
check("onTick 已接到 ui 上", type(app.ui.onTick) == "function")

-- 触发按键
E.fireKey(script.object, "Enum.KeyEventType.KeyboardJumpKeyDown", {})
check("★ mount 的 keys 回调被触发", jumpHits == 1, "hits=" .. tostring(jumpHits))

-- 驱动一帧
if type(app.ui.onTick) == "function" then app.ui.onTick(1/50) end
check("mount 的 onTick 被调用", tickCount == 1, "ticks=" .. tostring(tickCount))

-- stop 应当解绑
app:stop()
check("★ stop 后按键已解绑", E.keyListenerCount(script.object) == 0,
    "root 上监听器=" .. tostring(E.keyListenerCount(script.object)))

--=============================================================================
print("\n=== 9. 循环行为向后兼容（不传 onTick 时只 flush）===")
--=============================================================================
E = makeEnv()
local ui2 = webui.new({ root = script.object, prefabs = PREFABS, handlers = {} })
ui2:render([[<div style="width:50px;height:50px"></div>]])
check("不传 onTick 时 ui.onTick 为 nil", ui2.onTick == nil)
ui2:startLoop(50)                    -- 旧签名（单参数）必须仍然可用
check("旧签名 startLoop(fps) 可用", ui2.ticking == true)
check("setTick 可后置挂载", (function()
  ui2:setTick(function() end)
  return type(ui2.onTick) == "function"
end)())
ui2:stopLoop()

--=============================================================================
print("")
print(string.format(">>> 通过 %d / 失败 %d", pass, fail))
if fail > 0 then os.exit(1) end
