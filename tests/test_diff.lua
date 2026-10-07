-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local created = 0
local function makeControl(kind, parent)
  created = created + 1
  local c = { _kind=kind, name=kind,
    anchorMinX=0.5,anchorMinY=0.5,anchorMaxX=0.5,anchorMaxY=0.5,
    pivotX=0.5,pivotY=0.5,anchoredPositionX=0,anchoredPositionY=0,
    sizeDeltaX=0,sizeDeltaY=0,visible=true,active=true,
    _children={}, _listeners={} }
  c.SetActive=function(s,v) s.active=v end
  c.GetChildren=function(s) return s._children end
  c.SetAnchoredPosition=function(s,x,y) s.anchoredPositionX=x;s.anchoredPositionY=y end
  c.SetSizeDelta=function(s,w,h) s.sizeDeltaX=w;s.sizeDeltaY=h end
  c.AddCursorEventListener=function(s,ev,cb) s._listeners[#s._listeners+1]={ev=ev,cb=cb} end
  if parent then parent._children[#parent._children+1]=c end
  return c
end

local PREFABS={container=1073741933,textbox=1073741934,button=1073741935}
game={
  InstantiateClientUIControl=function(idx,parent)
    for k,v in pairs(PREFABS) do if v==idx then return makeControl(k,parent) end end
    return nil
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
Color={FromRGBA=function(r,g,b,a) return {r,g,b,a} end,FromRGB=function(r,g,b) return {r,g,b} end}
Enum={CursorEventType={CursorClick="CursorClick",CursorEnter="CursorEnter",
                      CursorDown="CursorDown",CursorUp="CursorUp",CursorExit="CursorExit",
                      CursorBeginDrag="CursorBeginDrag",CursorDrag="CursorDrag",
                      CursorEndDrag="CursorEndDrag"},
      TextHorizontalAlignmentLeft="L",TextHorizontalAlignmentMiddle="C",
      TextHorizontalAlignmentRight="R"}

local webui = require('webui')
local root = makeControl("container", nil)
script = { object = root }

local ui = webui.new({ root=root, prefabs=PREFABS, handlers={onClick=function() end} })
ui:render([[
<style>
  .panel { width: 320px; padding: 16px; background-color: #1e1e28; }
  .title { height: 28px; font-size: 18px; color: #ffffff; }
  .row   { display: flex; gap: 10px; margin-top: 12px; }
  .btn   { width: 110px; height: 36px; background-color: #3a7bd5; }
</style>
<div class="panel">
  <div class="title">webui 测试</div>
  <div class="row">
    <div class="btn" onclick="onClick">按钮A</div>
    <div class="btn" onclick="onClick">按钮B</div>
  </div>
</div>
]])

print("=== diff 效果验证 ===")
print()
local s = ui.rendered.stats
print(string.format("  首次渲染: written=%d", s.written))

-- ★ 加一个 hook 追踪到底哪个字段在被反复写
local Renderer = ui.rendered
local origWrite = nil

local before = s.written
ui:flush()
print(string.format("  第 2 次 flush: 新增写入 %d", s.written - before))

print()
print("=== 追踪每帧重复写入的字段 ===")
-- 直接检查每个控件的 last 表，找出哪些值在变
local dom = require('webui.dom')
print(string.format("  %-12s %-22s %-24s %s", "字段", "上一帧值", "本帧值", "控件"))
for node, entry in pairs(Renderer.live) do
  if entry.last then
    for k, v in pairs(entry.last) do
      if type(v) == "number" then
        -- 重新算一遍当前值
        local box = node.box
        if box then
          local dx, dy = Renderer.computeAnchored and 0 or 0
        end
      end
    end
  end
end

-- 更直接：连续 flush 两次，比较 last 表
local snap = {}
for node, entry in pairs(Renderer.live) do
  snap[node] = {}
  for k, v in pairs(entry.last) do snap[node][k] = v end
end
ui:flush()
print("  第二次 flush 后，发生变化的字段：")
for node, entry in pairs(Renderer.live) do
  local old = snap[node]
  if old then
    for k, v in pairs(entry.last) do
      if old[k] ~= v then
        print(string.format("    %-10s %-20s %s -> %s",
            node.tag or "?", k, tostring(old[k]), tostring(v)))
      end
    end
  end
end

print()
print("=== 控件树 ===")
local function dump(c,d)
  if d>5 then return end
  print(string.format("%s%-10s size=%.0fx%.0f pos=(%.0f,%.0f) text=%s",
    string.rep("  ",d+1), c._kind, c.sizeDeltaX, c.sizeDeltaY,
    c.anchoredPositionX, c.anchoredPositionY, tostring(c.text)))
  for _,k in ipairs(c._children) do dump(k,d+1) end
end
for _,c in ipairs(root._children) do dump(c,0) end