-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

--[[ 复用正确性测试：坐标不能错位

     ★ 真实踩过的 bug：
       控件池的压入顺序用了 pairs()（Lua 顺序未定义），
       而取用是 table.remove(list)（LIFO）。
       顺序错乱 -> 取到的控件父链不匹配 ->
       它被写入的 anchoredPosition 是【按新父】算的，
       但引擎按【它的实际旧父】渲染 -> 位置完全错乱/消失。

       实测现象：切页签后界面只剩一个黑块 + 一个按钮。

     正确做法：按 DOM 先序【逆序】压入，使弹出顺序 == 构建顺序。
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
  if cond then pass=pass+1; print(string.format("  [OK] %-38s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-38s %s", name, detail or "")) end
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

--[[ 核心检查：每个控件的父必须是它在当前树中的真实父

     判定方式：遍历 live，看控件的 __webuiParent
       是否等于【它的 DOM 节点的父节点所对应的控件】
]]--
local function parentErrors(tag)
  local bad = {}
  local function walkNode(node, parentCtrl)
    if not node:isElement() then return end
    local entry = ui.rendered.live[node]
    if entry then
      local c = entry.control
      if c.__webuiParent ~= parentCtrl then
        bad[#bad+1] = string.format("%s: 实际父=%s 期望父=%s",
            tostring(node.id or node.tag),
            tostring(c.__webuiParent and c.__webuiParent._kind),
            tostring(parentCtrl and parentCtrl._kind))
      end
      parentCtrl = c
    end
    for i = 1, #node.children do walkNode(node.children[i], parentCtrl) end
  end
  for i = 1, #ui.doc.children do walkNode(ui.doc.children[i], ui.rendered.root) end
  return bad
end

print("=== 1. 首屏父链应正确 ===")
ui:render(page(3))
local e1 = parentErrors("render(3)")
check("父链全对", #e1 == 0,
    #e1 > 0 and (e1[1] .. ( #e1 > 1 and (" (+" .. (#e1-1) .. ")") or "")) or "")

print()
print("=== 2. 减少卡片后父链应正确 ===")
ui:render(page(1))
local e2 = parentErrors("render(1)")
check("父链全对", #e2 == 0,
    #e2 > 0 and (e2[1] .. ( #e2 > 1 and (" (+" .. (#e2-1) .. ")") or "")) or "")

print()
print("=== 3. 反复增减父链都应正确 ===")
local worst = 0
for i = 1, 20 do
  ui:render(page((i % 4) + 1))
  local e = parentErrors("t" .. i)
  if #e > worst then worst = #e end
end
check("20 次增减无父链错误", worst == 0, "最多 " .. worst .. " 个错误")

print()
print("=== 4. 结构变化（kind 改变）后父链仍应正确 ===")
-- 卡片从"有背景"变"无背景"，外层 kind 从 textbox 变 container
local function pageMixed(n, withBg)
  local cards = {}
  for i=1,n do
    cards[#cards+1] = string.format(
      '<div class="%s" id="c%d"><div class="nm">N%d</div></div>',
      withBg and "cardbg" or "card", i, i)
  end
  return [[<style>
    .cardbg{width:200px;height:100px;padding:10px;background-color:#22222e;}
    .card{width:200px;height:100px;padding:10px;}
    .nm{width:180px;height:24px;color:#fff;}
  </style>]] .. table.concat(cards)
end
ui:render(pageMixed(3, true))
local e3a = parentErrors("有背景")
ui:render(pageMixed(3, false))
local e3b = parentErrors("无背景")
ui:render(pageMixed(3, true))
local e3c = parentErrors("再有背景")
check("kind 变化后父链正确", #e3a == 0 and #e3b == 0 and #e3c == 0,
    string.format("错误数 %d/%d/%d", #e3a, #e3b, #e3c))

print()
print("=== 5. 复用率仍然要高 ===")
local c1 = created
for i = 1, 20 do ui:render(page((i % 3) + 2)) end
check("20 次渲染新建 <= 20", created - c1 <= 20,
    string.format("新建 %d 个", created - c1))

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end