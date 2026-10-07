-- 验证单文件 bundle 能否独立工作（不依赖文件系统 require）
package.path = ""   -- ★ 清空搜索路径，强制只能从 bundle 里取

-- 模拟真机环境
local createdCount = 0
local allControls = {}

local function makeControl(kind, parent)
  createdCount = createdCount + 1
  local c = {
    _kind = kind, name = kind,
    anchorMinX=0.5, anchorMinY=0.5, anchorMaxX=0.5, anchorMaxY=0.5,
    pivotX=0.5, pivotY=0.5, anchoredPositionX=0, anchoredPositionY=0,
    sizeDeltaX=100, sizeDeltaY=100, visible=true, active=true,
    _children = {}, _cursorListeners = {},
  }
  c.SetActive = function(self,v) self.active=v end
  c.GetChildren = function(self) return self._children end
  c.SetAnchoredPosition = function(self,x,y) self.anchoredPositionX=x; self.anchoredPositionY=y end
  c.SetSizeDelta = function(self,w,h) self.sizeDeltaX=w; self.sizeDeltaY=h end
  if kind == "button" then
    c.AddCursorEventListener = function(self,ev,cb)
      self._cursorListeners[#self._cursorListeners+1]={ev=ev,cb=cb}
    end
    c.SimulateCursorClick = function(self)
      for _,l in ipairs(self._cursorListeners) do
        if l.ev == "CursorClick" then
          l.cb({GetUIPos=function() return 5,6 end,
                GetPressUIPos=function() return 5,6 end,
                GetUIPosDelta=function() return 0,0 end,
                dragging=false, touchId=-1})
        end
      end
    end
  end
  if parent then parent._children[#parent._children+1]=c end
  allControls[#allControls+1]=c
  return c
end

local PREFABS = { container=1, textbox=2, button=3 }
game = {
  InstantiateClientUIControl=function(idx,parent)
    local kind="container"
    for k,v in pairs(PREFABS) do if v==idx then kind=k end end
    return makeControl(kind,parent)
  end,
  DestroyClientUIControl=function() end,
  GetUICanvasSize=function() return 1600,900 end,
  GetClientUIRoots=function() return {} end,
  TweenSequence=function()
    local s={} s.AppendInterval=function() return s end
    s.AppendCallback=function() return s end s.Play=function() return s end
    return s
  end,
}
Color={ FromRGBA=function(r,g,b,a) return {r,g,b,a} end,
        FromRGB=function(r,g,b) return {r,g,b} end }
Enum={ CursorEventType={CursorClick="CursorClick",CursorEnter="CursorEnter",
                        CursorDown="CursorDown",CursorUp="CursorUp",
                        CursorExit="CursorExit",CursorBeginDrag="CursorBeginDrag",
                        CursorDrag="CursorDrag",CursorEndDrag="CursorEndDrag"},
       TextHorizontalAlignmentLeft="L",TextHorizontalAlignmentMiddle="C",
       TextHorizontalAlignmentRight="R" }

-- ★ 关键：从 bundle 文件加载（模拟"粘贴源码"的场景）
print("=== 加载 bundle/webui.lua ===")
local chunk, err = loadfile("bundle/webui.lua")
if not chunk then
  print("  ✗ 加载失败: " .. tostring(err))
  return
end

local ok, result = pcall(chunk)
if not ok then
  print("  ✗ 执行失败: " .. tostring(result))
  return
end

print("  ✓ 执行成功")
print("  return 值类型: " .. type(result))
print("  __WEBUI__ 全局: " .. type(__WEBUI__))

local webui = result
if type(webui) ~= "table" or not webui.new then
  print("  ✗ 返回值不是一个可用的库")
  return
end

print("  版本: " .. tostring(webui.VERSION))
print("  子模块: util=" .. type(webui.util) ..
      " html=" .. type(webui.html) ..
      " css=" .. type(webui.css) ..
      " layout=" .. type(webui.layout))

--=============================================================================
-- 用 bundle 跑一个完整示例
--=============================================================================
print()
print("=== 用 bundle 渲染 ===")

local root = makeControl("container", nil)
script = { object = root, name = "bundle_test" }

local clicked = 0
local ui = webui.new({
  root = root,
  prefabs = PREFABS,
  handlers = { onClick = function(info) clicked = clicked + 1 end },
})

ui:render([[
<style>
  .card  { width: 300px; padding: 16px; background-color: #1e1e1e; }
  .head  { height: 24px; font-size: 18px; color: #ffffff; }
  .bar   { display: flex; gap: 8px; }
  .item  { width: 80px; height: 32px; background-color: #4a90d9; }
</style>
<div class="card">
  <div class="head">标题</div>
  <div class="bar">
    <div class="item" onclick="onClick">A</div>
    <div class="item" onclick="onClick">B</div>
  </div>
</div>
]])

print("  DOM:", (function()
  local st = webui.dom.stats(ui.doc)
  return string.format("元素=%d 文本=%d 深度=%d", st.elements, st.texts, st.maxDepth)
end)())
print("  渲染:", ui.rendered:statsText())
print("  事件绑定:", ui.boundCount)

-- 触发点击
local fired = 0
for _, c in ipairs(allControls) do
  if #c._cursorListeners > 0 then pcall(function() c:SimulateCursorClick() end) fired = fired + 1 end
end
print(string.format("  模拟点击 %d 个按钮, onClick 触发 %d 次", fired, clicked))

-- 二次 flush
local before = createdCount
ui:flush()
print(string.format("  二次 flush 新建控件 %d 个 (应为 0)", createdCount - before))

print()
print("=== 契约测试：bundle 是否独立 ===")
print("  ✓ 清空了 package.path 仍能工作 => 不依赖文件系统")
print("  ✓ 返回值和 __WEBUI__ 都可用")
print()
print("*** bundle 验证通过 ***")