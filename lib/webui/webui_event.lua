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

--[[ 判断某个 UI 坐标落在哪个元素的 box 内（从后往前，模拟 z 序）]]--
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

--[[ 把光标 UI 坐标转成库内部坐标 ]]--
function E.toLocal(uiX, uiY)
  local util = require('webui_util')
  local _, ch = util.canvasSize()
  return uiX, ch - uiY
end

--[[ 判断一个光标坐标是否落在某节点的盒子里 ]]--
function E.hitBox(box, uiX, uiY)
  if not box then return false end
  local x, y = E.toLocal(uiX, uiY)
  return x >= box.x and x <= box.x + box.w
     and y >= box.y and y <= box.y + box.h
end

--[[ 取光标在某个盒子内的相对位置（0..1）
     用于进度条 / 滑块的拖拽换算 ]]--
function E.ratioInBox(box, uiX, uiY, horizontal)
  if not box or box.w <= 0 or box.h <= 0 then return 0 end
  local x, y = E.toLocal(uiX, uiY)
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

return E
