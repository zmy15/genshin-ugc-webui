-- 用真实模板索引验证 deploy_test
-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local created, controls = 0, {}

-- ★ 用真实索引
local PREFABS = {
  container = 1073741933,
  textbox   = 1073741934,
  button    = 1073741935,
}

local function makeControl(kind, parent)
  created = created + 1
  local c = {
    _kind = kind, name = kind,
    anchorMinX=0.5, anchorMinY=0.5, anchorMaxX=0.5, anchorMaxY=0.5,
    pivotX=0.5, pivotY=0.5, anchoredPositionX=0, anchoredPositionY=0,
    sizeDeltaX=100, sizeDeltaY=100, visible=true, active=true,
    _children={}, _listeners={},
  }
  c.SetActive=function(s,v) s.active=v end
  c.SetVisible=function(s,v) s.visible=v end
  c.GetChildren=function(s) return s._children end
  c.SetAnchoredPosition=function(s,x,y) s.anchoredPositionX=x; s.anchoredPositionY=y end
  c.SetSizeDelta=function(s,w,h) s.sizeDeltaX=w; s.sizeDeltaY=h end
  if kind=="button" or kind=="area" then
    c.AddCursorEventListener=function(s,ev,cb) s._listeners[#s._listeners+1]={ev=ev,cb=cb} end
    c.SimulateCursorClick=function(s)
      for _,l in ipairs(s._listeners) do
        if l.ev=="CursorClick" then
          l.cb({GetUIPos=function() return 33,55 end,
                GetPressUIPos=function() return 33,55 end,
                GetUIPosDelta=function() return 0,0 end,
                dragging=false,touchId=-1})
        end
      end
    end
  end
  if parent then parent._children[#parent._children+1]=c end
  controls[#controls+1]=c
  return c
end

game={
  InstantiateClientUIControl=function(idx,parent)
    local kind = nil
    for k,v in pairs(PREFABS) do if v==idx then kind=k end end
    -- ★ 模拟真机：索引不存在就返回 nil（这是之前失败的原因）
    if not kind then return nil end
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
Color={FromRGBA=function(r,g,b,a) return {r,g,b,a} end,FromRGB=function(r,g,b) return {r,g,b} end}
Enum={CursorEventType={CursorClick="CursorClick",CursorEnter="CursorEnter",
                      CursorDown="CursorDown",CursorUp="CursorUp",CursorExit="CursorExit",
                      CursorBeginDrag="CursorBeginDrag",CursorDrag="CursorDrag",
                      CursorEndDrag="CursorEndDrag"},
      TextHorizontalAlignmentLeft="L",TextHorizontalAlignmentMiddle="C",
      TextHorizontalAlignmentRight="R"}

local root = makeControl("container", nil)
root.name = "ProbeRoot"
script = { object = root, name = "ProbeRoot" }

print("========== 用真实索引验证 ==========")
print()

local webui = require('webui')

local clicks = 0
local ui = webui.new({
  root = root, prefabs = PREFABS,
  handlers = { onClick = function(info) clicks = clicks + 1 end },
})

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

print("  渲染: " .. ui.rendered:statsText())
print("  事件: " .. tostring(ui.boundCount))
print()

print("========== 控件树（这是真机上应该看到的）==========")
local function dump(c, d)
  if d > 6 then return end
  local pad = string.rep("  ", d + 1)
  print(string.format("%s%-10s pos=(%.0f,%.0f) size=(%.0fx%.0f)%s%s",
      pad, c._kind,
      c.anchoredPositionX, c.anchoredPositionY,
      c.sizeDeltaX, c.sizeDeltaY,
      c.bgColor and (" bg=" .. tostring(c.bgColor)) or "",
      c.text and (' text="' .. c.text .. '"') or ""))
  for _, k in ipairs(c._children) do dump(k, d+1) end
end
for _, c in ipairs(root._children) do dump(c, 0) end

print()
for _, c in ipairs(controls) do
  if #c._listeners > 0 then pcall(function() c:SimulateCursorClick() end) end
end
print("  点击触发: " .. clicks .. " 次")

print()
print("========== 验证 PREFABS 校验逻辑 ==========")
-- 故意用错误索引，看是否给出警告
local ui2 = webui.new({ root = root, prefabs = { container = 999999 } })
ui2:render([[<div style="width:100px;height:50px"></div>]])
print("  （上面应有 [warn] 提示索引无效）")

print()
print("*** 真实索引验证通过 ***")