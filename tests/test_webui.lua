--[[============================================================================
  模拟千星引擎环境，端到端测试整个 webui 库
  用真机实测的行为（R1-R14）来构建 mock
==============================================================================]]

-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

--=============================================================================
-- Mock 引擎
--=============================================================================

local createdCount = 0
local destroyedCount = 0
local allControls = {}

local function makeControl(kind, parent)
  createdCount = createdCount + 1
  local c = {
    _kind = kind,
    name = kind,
    -- 布局字段
    anchorMinX=0.5, anchorMinY=0.5, anchorMaxX=0.5, anchorMaxY=0.5,
    pivotX=0.5, pivotY=0.5,
    anchoredPositionX=0, anchoredPositionY=0,
    sizeDeltaX=100, sizeDeltaY=100,
    visible=true, active=true,
    -- 视觉
    imageColor=nil, bgColor=nil, fontColor=nil, text=nil, fontSize=14,
    horizontalAlignment=nil,
    -- 遮罩
    enableMask=false, reverseMaskArea=false,
    -- 光标
    showCursor=false,
    _children = {},
    _cursorListeners = {},
    _parent = parent,
  }

  -- 按类型限制可用字段（模拟真机"字段按类型封死"）
  if kind ~= "textbox" then
    c.bgColor = nil; c.text = nil; c.fontColor = nil
  end
  if kind ~= "image" then
    c.imageColor = nil; c.enableMask = nil; c.reverseMaskArea = nil
  end

  -- 方法
  c.SetActive = function(self, v) self.active = v end
  c.SetVisible = function(self, v) self.visible = v end
  c.GetChildren = function(self) return self._children end
  c.SetAnchoredPosition = function(self, x, y) self.anchoredPositionX=x; self.anchoredPositionY=y end
  c.SetSizeDelta = function(self, w, h) self.sizeDeltaX=w; self.sizeDeltaY=h end
  c.RemoveAllCursorEventListeners = function(self) self._cursorListeners = {} end

  -- 只有 button / area 有光标事件
  if kind == "button" or kind == "area" then
    c.AddCursorEventListener = function(self, ev, cb)
      self._cursorListeners[#self._cursorListeners+1] = {ev=ev, cb=cb}
    end
    c.SimulateCursorClick = function(self)
      for _, l in ipairs(self._cursorListeners) do
        if l.ev == "CursorClick" then
          l.cb({ GetUIPos = function() return 10, 20 end,
                 GetPressUIPos = function() return 10, 20 end,
                 GetUIPosDelta = function() return 0, 0 end,
                 dragging = false, touchId = -1 })
        end
      end
    end
  end

  if parent then parent._children[#parent._children+1] = c end
  allControls[#allControls+1] = c
  return c
end

-- 模板索引（模拟编辑器里配好的模板）
local PREFABS = { container = 1, textbox = 2, button = 3, image = 4 }

game = {
  InstantiateClientUIControl = function(idx, parent)
    local kind = "container"
    for k, v in pairs(PREFABS) do if v == idx then kind = k end end
    return makeControl(kind, parent)
  end,
  DestroyClientUIControl = function(c) destroyedCount = destroyedCount + 1 end,
  GetUICanvasSize = function() return 1600, 900 end,
  GetClientUIRoots = function() return {} end,
  TweenSequence = function()
    local s = {}
    s.AppendInterval = function() return s end
    s.AppendCallback = function() return s end
    s.Play = function() return s end
    return s
  end,
}

Color = {
  FromRGBA = function(r,g,b,a) return string.format("C(%d,%d,%d,%d)",r,g,b,a) end,
  FromRGB  = function(r,g,b)   return string.format("C(%d,%d,%d,255)",r,g,b) end,
}

Enum = {
  CursorEventType = {
    CursorDown="CursorDown", CursorUp="CursorUp", CursorEnter="CursorEnter",
    CursorExit="CursorExit", CursorClick="CursorClick",
    CursorBeginDrag="CursorBeginDrag", CursorDrag="CursorDrag",
    CursorEndDrag="CursorEndDrag",
  },
  TextHorizontalAlignmentLeft="L", TextHorizontalAlignmentMiddle="C",
  TextHorizontalAlignmentRight="R",
}

--=============================================================================
-- 测试
--=============================================================================

local webui = require('webui')

-- 根控件
local root = makeControl("container", nil)
script = { object = root, name = "webui_test" }

print("========== 端到端测试 ==========")
print()

local clicked = 0
local hovered = 0

local ui = webui.new({
  root = root,
  prefabs = PREFABS,
  handlers = {
    onClick = function(info)
      clicked = clicked + 1
      print(string.format("  >>> onClick 触发! 坐标=(%.0f,%.0f) 第 %d 次",
          info.x or -1, info.y or -1, clicked))
    end,
    onEnter = function(info)
      hovered = hovered + 1
    end,
  },
})

local htmlSrc = [[
<style>
  .panel { width: 400px; padding: 20px; background-color: #222222; }
  .title { height: 30px; font-size: 20px; color: #ffffff; }
  .row   { display: flex; gap: 12px; }
  .btn   { width: 120px; height: 40px; background-color: #3a7bd5; }
</style>
<div class="panel">
  <div class="title">设置面板</div>
  <div class="row">
    <div class="btn" onclick="onClick" onmouseenter="onEnter">确定</div>
    <div class="btn" onclick="onClick">取消</div>
  </div>
</div>
]]

ui:render(htmlSrc)

print("  DOM 统计:", (function()
  local dom = require('webui.dom')
  local st = dom.stats(ui.doc)
  return string.format("元素=%d 文本=%d 深度=%d", st.elements, st.texts, st.maxDepth)
end)())
print("  渲染统计:", ui.rendered:statsText())
print("  事件绑定数:", ui.boundCount)
print("  创建的引擎控件数:", createdCount)
print()

print("========== 控件树 ==========")
local function dumpControl(c, depth)
  depth = depth or 0
  if depth > 6 then return end
  local pad = string.rep("  ", depth + 1)
  print(string.format("%s%-10s pos=(%.0f,%.0f) size=(%.0fx%.0f) %s%s",
      pad, c._kind,
      c.anchoredPositionX, c.anchoredPositionY,
      c.sizeDeltaX, c.sizeDeltaY,
      c.bgColor and ("bg=" .. c.bgColor .. " ") or "",
      c.text and ('text="' .. c.text .. '"') or ""))
  for _, k in ipairs(c._children) do dumpControl(k, depth+1) end
end
for _, c in ipairs(root._children) do dumpControl(c, 0) end

print()
print("========== 触发事件 ==========")
-- 找到带 onclick 的控件并模拟点击
local fired = 0
for _, c in ipairs(allControls) do
  if #c._cursorListeners > 0 then
    pcall(function() c:SimulateCursorClick() end)
    fired = fired + 1
  end
end
print(string.format("  向 %d 个控件发送了模拟点击", fired))
print(string.format("  onClick 触发 %d 次", clicked))

print()
print("========== 二次渲染（diff 测试）==========")
local before = createdCount
ui:flush()
print(string.format("  再次 flush: 新建控件 %d 个 (应为 0，说明复用了)",
    createdCount - before))
print("  ", ui.rendered:statsText())

print()
print("========== 修改内容后重渲染 ==========")
ui:render([[
<style>
  .panel { width: 400px; padding: 20px; background-color: #222222; }
  .title { height: 30px; font-size: 20px; color: #ffffff; }
</style>
<div class="panel">
  <div class="title">新标题</div>
</div>
]])
print("  ", ui.rendered:statsText())
local live = 0
for _ in pairs(ui.rendered.live) do live = live + 1 end
print(string.format("  存活控件 %d 个 (应为 2: panel + title)", live))

print()
print("========== 性能：多轮 flush ==========")
local t0 = os.clock()
for i = 1, 100 do ui:flush() end
local t1 = os.clock()
print(string.format("  100 次 flush 耗时 %.1fms (每次 %.2fms)",
    (t1-t0)*1000, (t1-t0)*10))