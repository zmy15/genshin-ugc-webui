-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
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

     ⚠️⚠️ 判据必须用 `GetChildren()` 反查（2026-10-09 修）

        这段原来是读 `c.__webuiParent` 的 —— 那是【空检查】：
          · `__webuiParent` 是【自定义字段】，真机写入静默失败
            （探针实证：docs/真机复用问题复盘.md 第二节）
          · 本测试的 mock 用普通 table，恰好允许写它 ->
            于是断言"看起来在检查"，其实只验证了 mock 自己的记账，
            **完全没有验证库的行为**
          · 实测：把库的 isChildOf 改成恒 true（不做父匹配），
            本测试仍然全绿（突变测试发现）

        ★ 真机上唯一可用的父子关系 API 是 `GetChildren()`（L1 的教训），
          所以断言也必须走它 —— 否则测的不是真机那条路径。
]]--
local function parentErrors(tag)
  local bad = {}
  local function walkNode(node, parentCtrl)
    if not node:isElement() then return end
    local entry = ui.rendered.live[node]
    if entry then
      local c = entry.control
      -- ★ 用 GetChildren() 反查真实父子（与库同一机制）
      local isChild = false
      if parentCtrl then
        local ok, kids = pcall(function() return parentCtrl:GetChildren() end)
        if ok and type(kids) == "table" then
          for i = 1, #kids do
            if kids[i] == c then isChild = true break end
          end
        end
      end
      if not isChild then
        bad[#bad+1] = string.format("%s: 实际父≠期望父（kind=%s）",
            tostring(node.id or node.tag), tostring(c._kind))
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
print("=== 6. ★★ 控件池的【压入顺序】不变量 ===")
--[[ ⚠️⚠️ 为什么需要这条（2026-10-09，突变测试发现缺口）

       上面 1~5 节都是在**真实场景**下验证"父链没出错"。
       但突变测试证明：把「预回收按 DOM 逆序压池」改成**正序**，
       上面全部断言仍然全绿 —— 因为那个场景恰好没暴露顺序问题。

       而这条不变量是**真机实测踩出来的**（见文件开头的 bug 说明）：
       池是 LIFO（table.remove 取尾），所以
         压入顺序必须 = DOM 先序的【逆序】
       才能让"弹出顺序 == 构建顺序"，从而命中同父的控件。
       顺序反了 -> 取到的控件父链错位 -> 坐标全乱（真机：界面只剩一个黑块）。

       ★ 所以这里【直接验不变量】，不依赖某个场景是否恰好暴露它。 ]]
do
  -- 造一个"父下有多个同 kind 子控件"的结构，触发一轮完整还池
  ui:render(page(3))
  local rendered = ui.rendered
  local liveCount = 0
  for _ in pairs(rendered.live) do liveCount = liveCount + 1 end

  -- 触发 domChanged 预回收：清空 DOM 再重建
  ui:render("<div id='empty'></div>")
  local pooled = 0
  for _, list in pairs(rendered.pool) do pooled = pooled + #list end
  check("★ 还池后有控件进池（说明回收路径真的跑到了）",
      pooled > 0, pooled .. " 个控件在池里")

  -- ★ 核心：池里同一 kind 的顺序，必须是 DOM 先序的逆序
  --   等价判据：重新渲染同结构时，新建数应为 0（全部命中复用）
  local before = created
  ui:render(page(3))
  check("★★ 重建同结构【零新建】（= 弹序与构建序一致）",
      created - before == 0,
      string.format("新建 %d 个（>0 说明池序与构建序不一致）", created - before))
end

print()
print("=== 5. 复用率仍然要高 ===")
local c1 = created
for i = 1, 20 do ui:render(page((i % 3) + 2)) end
check("20 次渲染新建 <= 20", created - c1 <= 20,
    string.format("新建 %d 个", created - c1))

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end
