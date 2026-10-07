-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

--[[ 监听器生命周期测试

     ★ 防止两个真实踩过的问题回归：

       1. 监听器泄漏
          控件池复用控件，每次 setHTML 后 _bindEvents 重新绑定。
          如果回收时不清旧监听，复用过的控件会累积所有历史监听。
          后果：一次点击触发多次回调。

       2. 样式表无限增长
          setHTML 累加 stylesheets，每次 render 追加一份。
          后果：样式计算量线性上升，界面越来越卡。
]]--

local PREFABS = { container=1, textbox=2, button=3 }
local created, liveListeners, totalAdds, totalRemoves = 0, 0, 0, 0

local function mc(kind, parent)
  created = created + 1
  local c = { _kind=kind, __webuiParent=parent, _children={}, _lis={},
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
    c.AddCursorEventListener=function(s,ev,cb)
      s._lis[#s._lis+1] = {ev=ev, cb=cb}
      liveListeners = liveListeners + 1
      totalAdds = totalAdds + 1
    end
    c.RemoveAllCursorEventListeners=function(s)
      liveListeners = liveListeners - #s._lis
      totalRemoves = totalRemoves + #s._lis
      s._lis = {}
    end
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
  if cond then pass=pass+1; print(string.format("  [OK] %-34s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-34s %s", name, detail or "")) end
end

local root = mc("container", nil)
script = { object = root }
local handlers = {}
for i=1,30 do handlers["pick_f"..i] = function() end end
local ui = webui.new({ root=root, prefabs=PREFABS, handlers=handlers })

local function page(n)
  local cards = {}
  for i=1,n do
    cards[#cards+1] = string.format(
      '<div class="card" id="c%d" onclick="pick_f%d"><div class="nm">N%d</div></div>',
      i, i, i)
  end
  return '<style>.card{width:100px;height:50px;padding:8px;background-color:#222;}' ..
    '.nm{width:84px;height:20px;color:#fff;}</style>' .. table.concat(cards)
end

print("=== 1. 重复渲染，监听器数量应稳定 ===")
ui:render(page(5))
local l1 = liveListeners
check("首次活监听 = 5", l1 == 5, "活监听=" .. l1)

for i = 1, 10 do ui:render(page(5)) end
local l2 = liveListeners
check("10 次后仍为 5", l2 == 5, "活监听=" .. l2)

print()
print("=== 2. 监听器收支平衡 ===")
check("加 = 减 + 活", totalAdds == totalRemoves + liveListeners,
    string.format("加=%d 减=%d 活=%d", totalAdds, totalRemoves, liveListeners))

print()
print("=== 3. 控件数稳定 ===")
local c1 = created
for i = 1, 20 do ui:render(page(5)) end
check("20 次渲染不新建", created == c1,
    string.format("created %d -> %d", c1, created))

print()
print("=== 4. 数量变化后监听器数应跟随 ===")
ui:render(page(3))
check("3 张卡 -> 3 个监听", liveListeners == 3, "活监听=" .. liveListeners)
ui:render(page(8))
check("8 张卡 -> 8 个监听", liveListeners == 8, "活监听=" .. liveListeners)
ui:render(page(0))
check("0 张卡 -> 0 个监听", liveListeners == 0, "活监听=" .. liveListeners)

print()
print("=== 5. 样式表不应无限增长 ===")
ui:render(page(5))
local s1 = #ui.stylesheets
for i = 1, 20 do ui:render(page(5)) end
local s2 = #ui.stylesheets
check("stylesheets 不增长", s1 == s2,
    string.format("%d -> %d", s1, s2))
check("stylesheets 数量合理", s2 <= 3, "共 " .. s2 .. " 份")

print()
print("=== 6. addCSS 跨 setHTML 保留 ===")
local before = #ui.stylesheets
ui:addCSS(".extra { color: #f00; }")
ui:render(page(5))
check("addCSS 后仍生效", #ui.stylesheets == before + 1,
    string.format("%d -> %d", before, #ui.stylesheets))
ui:render(page(5))
check("多次 render 不重复追加", #ui.stylesheets == before + 1,
    "共 " .. #ui.stylesheets)

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end
