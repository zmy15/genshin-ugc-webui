--[[============================================================================
  webui/event.lua  ——  事件绑定与派发

  ⚠️ 真机实测（R14）：
    - 只有 ClientUIPresetButtonControl 和 ClientUICursorEventAreaControl
      有 AddCursorEventListener
    - 容器节点需要 showCursor = true 才生效
    - 8 种事件：CursorDown/Up/Enter/Exit/Click/BeginDrag/Drag/EndDrag
    - CursorEventData: GetUIPos / GetPressUIPos / GetUIPosDelta / dragging / touchId

  HTML 属性 -> 光标事件 映射：
    onclick       -> CursorClick
    onmousedown   -> CursorDown
    onmouseup     -> CursorUp
    onmouseenter  -> CursorEnter
    onmouseleave  -> CursorExit
    ondragstart   -> CursorBeginDrag
    ondrag        -> CursorDrag
    ondragend     -> CursorEndDrag
    ondraggable   -> 启用拖拽事件（配合上面几个）
==============================================================================]]

local util = require('webui_util')

local E = {}

-- HTML 属性名 -> 事件类型名
E.ATTR_TO_EVENT = {
  onclick      = "CursorClick",
  onmousedown  = "CursorDown",
  onmouseup    = "CursorUp",
  onmouseenter = "CursorEnter",
  onmouseleave = "CursorExit",
  ondragstart  = "CursorBeginDrag",
  ondrag       = "CursorDrag",
  ondragend    = "CursorEndDrag",
}

-- 按键属性 -> 按键事件（暂支持少数）
E.KEY_ATTR_TO_EVENT = {
  onkeydown = nil,   -- 需要指定具体键，暂不自动绑定
}

--=============================================================================
-- 伪类状态（:hover / :active）
--
--   引擎只给光标事件，不提供 CSS 伪类。
--   库在这里维护节点的交互状态标志，css.lua 的匹配器读取它们，
--   从而实现 :hover / :active。
--
--   事件 -> 状态：
--     CursorEnter -> node._hover = true
--     CursorExit  -> node._hover = false
--     CursorDown  -> node._pressed = true
--     CursorUp    -> node._pressed = false
--
--   状态变化后需要重新计算样式，由 onStateChange 回调通知 init.lua。
--=============================================================================

local stateChangeHook = nil

function E.setStateHook(fn)
  stateChangeHook = fn
end

local function notify(node)
  if stateChangeHook then
    pcall(stateChangeHook, node)
  end
end

local PSEUDO_EVENTS = {
  CursorEnter = function(node)
    if node._hover then return false end
    node._hover = true
    return true
  end,
  CursorExit = function(node)
    if not node._hover and not node._pressed then return false end
    node._hover = false
    node._pressed = false      -- 离开时也清掉按下态，避免卡住
    return true
  end,
  CursorDown = function(node)
    if node._pressed then return false end
    node._pressed = true
    return true
  end,
  CursorUp = function(node)
    if not node._pressed then return false end
    node._pressed = false
    return true
  end,
}

--[[ 内部：处理一次伪类状态变更 ]]--
function E.updatePseudo(node, eventName)
  local fn = PSEUDO_EVENTS[eventName]
  if not fn then return false end
  local changed = fn(node)
  if changed then notify(node) end
  return changed
end

--=============================================================================
-- 绑定
--=============================================================================

--[[
  为一个控件绑定 HTML 属性上的事件。

  参数：
    node      DOM 元素（含 attrs.onclick 等）
    control   引擎控件
    handlers  函数表 { onClick = fn, ... }（属性值作为 key）

  返回：绑定的数量
]]--
function E.bind(node, control, handlers, opts)
  opts = opts or {}
  if not node or not control or not handlers then return 0 end

  local attrs = node.attrs or {}
  local bound = 0
  local fit = opts.fit        -- ★ 渲染器的适配参数（缩放/留边反变换用）

  local function tryBind(eventName, fn)
    local ev = Enum and Enum.CursorEventType and Enum.CursorEventType[eventName]
    if ev == nil then return false end
    if type(control.AddCursorEventListener) ~= "function" then return false end

    local ok = pcall(function()
      control:AddCursorEventListener(ev, function(data)
        -- ★ 先更新伪类状态（:hover / :active）
        E.updatePseudo(node, eventName)

        -- 把 CursorEventData 转成更易用的表
        local info = { event = eventName, node = node, control = control, raw = data }
        if data then
          pcall(function() info.x, info.y = data:GetUIPos() end)
          pcall(function() info.pressX, info.pressY = data:GetPressUIPos() end)
          pcall(function() info.dx, info.dy = data:GetUIPosDelta() end)
          pcall(function() info.dragging = data.dragging end)
          pcall(function() info.touchId = data.touchId end)
        end

        --[[ ★★ 适配反变换后的设计坐标（多屏幕比例）

             info.x / info.y 是【画布坐标】，直接拿去和 node.box 比
             在缩放/留边下会错位。

             info.lx / info.ly 是【设计坐标】（左上原点、Y 向下），
             与 node.box 同一坐标系 —— 应用层要做命中判断请用它。

             ★ 无适配器时 lx/ly 就等于翻转后的 x/y，向后兼容。
        ]]--
        if info.x and info.y then
          local lx, ly = E.toLocal(info.x, info.y, fit)
          info.lx, info.ly = lx, ly
        end
        -- 元素自身信息，便于命中判断
        if node.box then
          info.box = node.box
        end

        local ok2, err = pcall(fn, info)
        if not ok2 then
          util.warn("事件处理器出错 [" .. eventName .. "]: " .. tostring(err))
        end
        return true   -- 标记已处理，避免穿透
      end)
    end)
    return ok
  end

  for attr, eventName in pairs(E.ATTR_TO_EVENT) do
    local handlerName = attrs[attr]
    if handlerName and handlerName ~= "" then
      local fn = handlers[handlerName]
      if type(fn) == "function" then
        if tryBind(eventName, fn) then
          bound = bound + 1
        else
          util.warn(string.format("绑定失败: %s -> %s (控件 %s 不支持)",
              attr, eventName, tostring(control.name)))
        end
      else
        util.warn(string.format("找不到处理器 '%s'（%s 引用）", handlerName, attr))
      end
    end
  end

  return bound
end

--=============================================================================
-- 命中检测辅助
--=============================================================================

--[[ 判断某个 UI 坐标落在哪个元素的 box 内（从后往前，模拟 z 序）

     ⚠️ x, y 必须是【设计坐标】（已反变换）。
        调用方若不确定，先用 E.toLocal(uiX, uiY, fit) 转换。]]--
function E.hitTest(root, x, y)
  local best = nil
  local dom = require('webui_dom')
  dom.walk(root, function(n)
    if n:isElement() and n.box and not n.box.hidden then
      local b = n.box
      if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
        -- 越深的优先
        best = n
      end
    end
  end)
  return best
end

--=============================================================================
-- 坐标转换
--
-- ⚠️ 引擎的光标坐标是【左下原点、Y 向上】（文档："以画布左下角为原点"），
--    而库内部的布局坐标是【左上原点、Y 向下】。
--    命中检测、拖拽计算都需要转换。
--=============================================================================

--[[ 把引擎的【画布坐标】转成【设计坐标】

     ⚠️ 这里有两个独立的变换，别搞混：

       ① Y 轴翻转
          引擎：左下原点、Y 向上
          库内：左上原点、Y 向下

       ② 适配缩放（多屏幕比例）
          画面被等比缩放居中后，引擎给的光标坐标是【画布坐标】，
          而布局盒子是【设计坐标】。必须反变换回去：
              design = (canvas - offset) / k

     ★ 不做 ② 的后果：留边 / 缩放下所有点击都错位
       （偏移越大错得越多，2560x1600 上垂直方向差 80px+）。

     ★ fit 从渲染器取（rendered.fit），没有适配器时 k=1、offset=0，
       行为与旧版完全一致。
]]--
function E.toLocal(uiX, uiY, fit)
  local util = require('webui_util')
  local _, ch = util.canvasSize()

  -- ① Y 翻转（画布坐标 -> 左上原点的画布坐标）
  local x, y = uiX, ch - uiY

  -- ② 适配反变换（画布坐标 -> 设计坐标）
  if fit then
    local fitMod = require('webui_fit')
    x, y = fitMod.toDesign(fit, x, y)
  end

  return x, y
end

--[[ 判断一个光标坐标是否落在某节点的盒子里

     fit：可选，渲染器的适配参数（rendered.fit）。
          ★ 传了才能正确处理缩放/留边下的命中。]]--
function E.hitBox(box, uiX, uiY, fit)
  if not box then return false end
  local x, y = E.toLocal(uiX, uiY, fit)
  return x >= box.x and x <= box.x + box.w
     and y >= box.y and y <= box.y + box.h
end

--[[ 取光标在某个盒子内的相对位置（0..1）
     用于进度条 / 滑块的拖拽换算 ]]--
function E.ratioInBox(box, uiX, uiY, horizontal, fit)
  if not box or box.w <= 0 or box.h <= 0 then return 0 end
  local x, y = E.toLocal(uiX, uiY, fit)
  local r
  if horizontal == false then
    r = (y - box.y) / box.h
  else
    r = (x - box.x) / box.w
  end
  if r < 0 then r = 0 end
  if r > 1 then r = 1 end
  return r
end

--=============================================================================
-- 全局光标门控
--=============================================================================

--[[ 确保容器开启 showCursor（CursorEvent 前提条件）]]--
function E.enableCursor(rootControl)
  if not rootControl then return false end
  local ok = pcall(function() rootControl.showCursor = true end)
  return ok
end

--=============================================================================
-- 按键事件（★ R20 真机验证，2026-10-08）
--
--   真机实测结论（探针模块 key，docs/引擎能力与限制.md §5.2）：
--     · AddKeyEventListener 在【文本框 / 根控件】上都可用
--     · Enum.KeyEventType 存在，pairs() 可遍历 164 项
--     · KeyboardJumpKeyDown/Up 可捕获，Down/Up 能成对判定
--     · ★★ 同一事件会被【每个绑定它的控件】各收一遍
--          -> 所以只绑【一个】挂载点，默认 root
--     · ★ 回调【绝不能 return true】—— 会吞掉同容器内其他按键
--          （client_control_api.md 第 1317 行）
--     · ⚠️ 回调的 data.type 读回为空 —— 按键回调的 data 结构与
--          光标事件不同，不要试图从 data 取键码；
--          「绑的是哪个枚举」本身就确定了是哪个键。
--=============================================================================

--[[ 按键名（Enum.KeyEventType 的成员名）-> 语义别名。

     用途：让页面用中文键名或简短别名绑键，而不是记长枚举名。 ]]--
E.KEY_ALIASES = {
  -- 跳跃（小恐龙等平台游戏默认用这个）
  jump        = "KeyboardJumpKeyDown",
  jumpDown    = "KeyboardJumpKeyDown",
  jumpUp      = "KeyboardJumpKeyUp",
  -- 移动
  left        = "KeyboardMoveLeftKeyDown",
  leftDown    = "KeyboardMoveLeftKeyDown",
  leftUp      = "KeyboardMoveLeftKeyUp",
  right       = "KeyboardMoveRightKeyDown",
  rightDown   = "KeyboardMoveRightKeyDown",
  rightUp     = "KeyboardMoveRightKeyUp",
  forward     = "KeyboardMoveForwardKeyDown",
  forwardUp   = "KeyboardMoveForwardKeyUp",
  backward    = "KeyboardMoveBackwardKeyDown",
  backwardUp  = "KeyboardMoveBackwardKeyUp",
  -- 奇匠按键（UGC 自定义键位）
  key1        = "KeyboardCraftspersonKey1Down",
  key1Up      = "KeyboardCraftspersonKey1Up",
  key2        = "KeyboardCraftspersonKey2Down",
  key2Up      = "KeyboardCraftspersonKey2Up",
  key3        = "KeyboardCraftspersonKey3Down",
  key3Up      = "KeyboardCraftspersonKey3Up",
  key4        = "KeyboardCraftspersonKey4Down",
  key4Up      = "KeyboardCraftspersonKey4Up",
  -- 手柄（同样实测存在于那 164 项里）
  padJump     = "ControllerJumpKeyDown",
  padJumpUp   = "ControllerJumpKeyUp",
}

--[[ 把键名解析成引擎枚举值。

     ★ 禁止照文档猜枚举名（R16 教训）—— 这里用 pcall 显式取，
       取不到就返回 nil，由调用方决定降级策略。

     参数 key 可以是：
        · 语义别名（"jump" / "left" / "key1"）—— 见 E.KEY_ALIASES
        · 完整枚举名（"KeyboardJumpKeyDown"）
     返回：枚举值 或 nil ]]--
function E.resolveKey(key)
  if key == nil then return nil end
  if type(Enum) == "nil" then return nil end
  local ket = Enum.KeyEventType
  if ket == nil then return nil end

  local name = E.KEY_ALIASES[key] or key
  return (pcall(function() return ket[name] end)) and ket[name] or nil
end

--[[ 在一个控件上绑定一个按键。

    ★★ 一个按键只绑【一个】挂载点 —— 真机实测同一个事件会被
       每个绑定它的控件各收一遍（3 个控件 = 按一次收 3 次）。
       所以本函数【不做】多控件尝试，由调用方明确指定挂载点。

    ⚠️ 回调一律 `return false`，避免吞掉同容器内其他按键。

   参数：
     control   挂载控件（推荐 root；必须真的有 AddKeyEventListener）
     key       键名（别名或完整枚举名）
     fn        回调 fn(info)，info = { event=, key=, control=, raw= }
     opts      { once = 只触发一次后自动解绑 }

   返回：成功的绑定数（0 或 1） ]]--
function E.bindKey(control, key, fn, opts)
  opts = opts or {}
  if not control or type(fn) ~= "function" then return 0 end
  if type(control.AddKeyEventListener) ~= "function" then return 0 end

  local ev = E.resolveKey(key)
  if ev == nil then
    util.warn(string.format("绑定按键失败: 无法解析键名 '%s'", tostring(key)))
    return 0
  end

  -- ★ 保留回调引用，供解绑使用（文档第 763 行：移除时需同一引用）
  local cb
  cb = function(data)
    local info = {
      event   = "KeyDown",
      key     = key,
      control = control,
      raw     = data,
    }
    if opts.once then
      -- 只触发一次：先解绑再回调，避免回调里再按键导致重入
      pcall(function()
        if type(control.RemoveKeyEventListener) == "function" then
          control:RemoveKeyEventListener(ev, cb)
        end
      end)
    end
    local ok, err = pcall(fn, info)
    if not ok then
      util.warn("按键处理器出错 [" .. tostring(key) .. "]: " .. tostring(err))
    end
    -- ★★ 绝不返回 true（否则吞掉同容器内其他按键）
    return false
  end

  local ok = pcall(function() control:AddKeyEventListener(ev, cb) end)
  if not ok then
    util.warn(string.format("绑定按键失败: %s（控件 %s）",
        tostring(key), tostring(control.name)))
    return 0
  end

  -- 记下引用，供 E.unbindKeys 统一清理
  if not E._keyBindings then E._keyBindings = {} end
  E._keyBindings[#E._keyBindings + 1] = { control = control, ev = ev, cb = cb }
  return 1
end

--[[ 批量绑定：keys = { jump = fn1, left = fn2, ... } ]]--
function E.bindKeys(control, keys, opts)
  local n = 0
  if type(keys) ~= "table" then return 0 end
  -- ★ pairs 顺序未定义，但这里每项互相独立，顺序无关
  for key, fn in pairs(keys) do
    if type(fn) == "function" then
      n = n + E.bindKey(control, key, fn, opts)
    end
  end
  return n
end

--[[ 解绑全部由 E.bindKey 建立的按键监听（销毁时调用，防泄漏）。

     ⚠️ 必须用【同一个回调引用】移除（文档第 763 行）。 ]]--
function E.unbindKeys()
  local list = E._keyBindings
  if not list then return 0 end
  local n = 0
  for i = 1, #list do
    local b = list[i]
    pcall(function()
      if type(b.control.RemoveKeyEventListener) == "function" then
        b.control:RemoveKeyEventListener(b.ev, b.cb)
        n = n + 1
      elseif type(b.control.RemoveAllKeyEventListeners) == "function" then
        b.control:RemoveAllKeyEventListeners()
        n = n + 1
      end
    end)
  end
  E._keyBindings = {}
  return n
end

return E
