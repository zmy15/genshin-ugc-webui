-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

--[[ 控件可见性 + 复用测试

     ★ 防止两个相互矛盾的回归：

       A. 要求父精确匹配
          -> 某个位置 kind 变化导致整条子树匹配失败 -> 雪崩新建
             （实测 demo 每次操作新建 100+ 控件，越来越卡）

       B. 只按 kind 取、不检查父
          -> 控件被贴到已隐藏的旧父下 -> 界面元素消失
             （实测 live=5 时只有 2 个可见）

       正确做法：按 kind 取，但只复用【旧父仍 active】的控件。
]]--

local PREFABS = { container=1073741933, textbox=1073741934, button=1073741935 }
local created = 0

local function mc(kind, parent)
  created = created + 1
  local c = { _kind=kind, __webuiParent=parent, _children={},
    anchorMinX=.5,anchorMinY=.5,anchorMaxX=.5,anchorMaxY=.5,
    pivotX=.5,pivotY=.5,anchoredPositionX=0,anchoredPositionY=0,
    sizeDeltaX=0,sizeDeltaY=0,visible=true,active=true }
  setmetatable(c,{__newindex=function(t,k,v)
    local M={SetActive=1,SetVisible=1,GetChildren=1,SetAnchoredPosition=1,
      SetSizeDelta=1,AddCursorEventListener=1,RemoveAllCursorEventListeners=1,
      SetSiblingIndex=1,__webuiParent=1}
    if M[k] then rawset(t,k,v) return end
    local common={anchorMinX=1,anchorMinY=1,anchorMaxX=1,anchorMaxY=1,
      pivotX=1,pivotY=1,anchoredPositionX=1,anchoredPositionY=1,
      sizeDeltaX=1,sizeDeltaY=1,visible=1,active=1,name=1,
      localScaleX=1,localScaleY=1,localRotationZ=1}
    local sup={}
    if kind=="textbox" then
      sup={bgColor=1,text=1,fontColor=1,fontSize=1,horizontalAlignment=1}
    elseif kind=="button" then sup={interactable=1,raycastTarget=1,clickAudioId=1} end
    if common[k] or sup[k] then rawset(t,k,v) else error("cannot set "..k,2) end
  end})
  c.SetActive=function(s,v) rawset(s,"active",v) end
  c.SetVisible=function() end
  c.GetChildren=function(s) return s._children end
  c.SetAnchoredPosition=function() end
  c.SetSizeDelta=function() end
  c.SetSiblingIndex=function() end
  if kind=="button" then
    c.AddCursorEventListener=function() end
    c.RemoveAllCursorEventListeners=function() end
  end
  if parent then parent._children[#parent._children+1]=c end
  return c
end

game={ InstantiateClientUIControl=function(i,p)
    for k,v in pairs(PREFABS) do if v==i then return mc(k,p) end end end,
  DestroyClientUIControl=function() end,
  GetUICanvasSize=function() return 1600,900 end,
  GetClientUIRoots=function() return {} end }
Color={FromRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
       FromRGB=function(r,g,b) return {r=r,g=g,b=b} end}
Enum={CursorEventType={CursorClick="CursorClick"},EaseType={Linear="Linear"},
      TextHorizontalAlignmentLeft="L",TextHorizontalAlignmentMiddle="C",
      TextHorizontalAlignmentRight="R"}

local webui = require('webui')
local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass=pass+1; print(string.format("  [OK] %-36s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-36s %s", name, detail or "")) end
end

local root = mc("container", nil)
script = { object = root }
local ui = webui.new({ root=root, prefabs=PREFABS, handlers={} })

local function page(n)
  local cards = {}
  for i=1,n do
    cards[#cards+1] = string.format([[
<div class="card" id="c%d">
  <div class="nm">N%d</div>
  <div class="foot"><div class="grow"></div><div class="btn">B</div></div>
</div>]], i, i)
  end
  return [[<style>
    .card{width:200px;height:100px;padding:10px;background-color:#22222e;}
    .nm{width:180px;height:24px;color:#fff;}
    .foot{display:flex;align-items:center;width:180px;height:32px;}
    .grow{flex-grow:1;height:24px;}
    .btn{width:66px;height:28px;background-color:#4a90d9;}
  </style>]] .. table.concat(cards)
end

--[[ 统计：live 条目中，控件沿父链是否全程 active ]]--
local function stats()
  local live, visible, blocked = 0, 0, 0
  for _, entry in pairs(ui.rendered.live) do
    live = live + 1
    local p, ok = entry.control.__webuiParent, true
    local d = 0
    while p and d < 30 do
      if not p.active then ok = false break end
      p = p.__webuiParent
      d = d + 1
    end
    if ok then visible = visible + 1 else blocked = blocked + 1 end
  end
  return live, visible, blocked
end

print("=== 1. 首屏所有控件应可见 ===")
ui:render(page(3))
local l, v, b = stats()
check("全部可见", b == 0, string.format("live=%d 可见=%d 遮挡=%d", l, v, b))

print()
print("=== 2. 数量减少后不应有控件被遮挡 ===")
ui:render(page(1))
l, v, b = stats()
check("减少后无遮挡", b == 0, string.format("live=%d 可见=%d 遮挡=%d", l, v, b))

print()
print("=== 3. 反复增减都不应遮挡 ===")
local bad = 0
for i = 1, 15 do
  ui:render(page((i % 4) + 1))
  local _, _, bb = stats()
  if bb > 0 then bad = bad + 1 end
end
check("15 次增减无遮挡", bad == 0, string.format("%d 次出现遮挡", bad))

print()
print("=== 4. 复用率应高（created 不持续增长）===")
local c1 = created
for i = 1, 20 do ui:render(page((i % 3) + 2)) end
local grew = created - c1
check("20 次渲染新建 <= 15", grew <= 15, string.format("新建 %d 个", grew))

print()
print("=== 5. 静态渲染不应新建 ===")
ui:render(page(5))
local c2 = created
for i = 1, 10 do ui:render(page(5)) end
check("10 次相同渲染不新建", created == c2,
    string.format("created %d -> %d", c2, created))

print()
print("=== 6. flush() 逐帧路径同样稳定 ===")
local c3 = created
ui:render(page(5))
for i = 1, 100 do ui:flush() end
check("100 帧 flush 不新建", created == c3,
    string.format("created %d -> %d", c3, created))
l, v, b = stats()
check("逐帧后仍全部可见", b == 0, string.format("可见=%d 遮挡=%d", v, b))

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end