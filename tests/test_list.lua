-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

--[[ 列表重建测试
     
     ★ 这个测试是为了防止一个真实踩过的严重 bug 回归：
       _take() 从控件池取出控件后没有重新 SetActive(true)，
       导致【任何动态列表在多次更新后，所有控件都变成不可见】。

       静态页面测不出来 —— 必须实际重建列表才会暴露。
]]--

local PREFABS = { container=1073741933, textbox=1073741934, button=1073741935 }
local created, alive = 0, {}

local function mc(kind, parent)
  created = created + 1
  local c = { _kind=kind, _alive=true, __webuiParent=parent, _children={},
    anchorMinX=.5,anchorMinY=.5,anchorMaxX=.5,anchorMaxY=.5,
    pivotX=.5,pivotY=.5,anchoredPositionX=0,anchoredPositionY=0,
    sizeDeltaX=0,sizeDeltaY=0,visible=true,active=true }
  setmetatable(c,{__newindex=function(t,k,v)
    local METHODS={SetActive=1,SetVisible=1,GetChildren=1,SetAnchoredPosition=1,
      SetSizeDelta=1,AddCursorEventListener=1,SetSiblingIndex=1,__webuiParent=1}
    if METHODS[k] then rawset(t,k,v) return end
    local common={anchorMinX=1,anchorMinY=1,anchorMaxX=1,anchorMaxY=1,
      pivotX=1,pivotY=1,anchoredPositionX=1,anchoredPositionY=1,
      sizeDeltaX=1,sizeDeltaY=1,visible=1,active=1,name=1,
      localScaleX=1,localScaleY=1,localRotationZ=1}
    local sup={}
    if kind=="textbox" then
      sup={bgColor=1,text=1,fontColor=1,fontSize=1,horizontalAlignment=1}
    elseif kind=="button" then
      sup={interactable=1,raycastTarget=1,clickAudioId=1}
    end
    if common[k] or sup[k] then rawset(t,k,v)
    else error("cannot set "..k,2) end
  end})
  c.SetActive=function(s,v) rawset(s,"active",v); rawset(s,"_alive",v) end
  c.SetVisible=function() end
  c.GetChildren=function(s) return s._children end
  c.SetAnchoredPosition=function() end
  c.SetSizeDelta=function() end
  c.SetSiblingIndex=function() end
  if kind=="button" then c.AddCursorEventListener=function() end end
  if parent then parent._children[#parent._children+1]=c end
  alive[#alive+1]=c
  return c
end

game={ InstantiateClientUIControl=function(i,p)
    for k,v in pairs(PREFABS) do if v==i then return mc(k,p) end end end,
  DestroyClientUIControl=function() end,
  GetUICanvasSize=function() return 1600,900 end,
  GetClientUIRoots=function() return {} end }
Color={FromRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
       FromRGB=function(r,g,b) return {r=r,g=g,b=b} end}
Enum={CursorEventType={CursorClick="CursorClick",CursorDown="CursorDown",
      CursorUp="CursorUp",CursorEnter="CursorEnter",CursorExit="CursorExit",
      CursorBeginDrag="CursorBeginDrag",CursorDrag="CursorDrag",CursorEndDrag="CursorEndDrag"},
      TextHorizontalAlignmentLeft="L",TextHorizontalAlignmentMiddle="C",
      TextHorizontalAlignmentRight="R",EaseType={Linear="Linear"}}

local webui = require('webui')
local dom    = require('webui.dom')

local root = mc("container", nil)
script = { object = root }
local ui = webui.new({ root=root, prefabs=PREFABS })

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass=pass+1; print(string.format("  [OK] %-32s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-32s %s", name, detail or "")) end
end

local function aliveCount()
  local n=0
  for _, c in ipairs(alive) do if c._alive then n=n+1 end end
  return n
end

local function render(n, sel)
  local p = {}
  for i = 1, n do
    local cls = "c" .. ((sel and sel[i]) and " sel" or "")
    p[#p+1] = string.format('<div class="%s" id="x%d">项%d</div>', cls, i, i)
  end
  ui:render('<style>' ..
    '.c{width:60px;height:20px;background-color:#333;}' ..
    '.c.sel{background-color:#4a90d9;}' ..
    '</style>' .. table.concat(p))
end

print("=== 1. 同一份 HTML 重复渲染应完全复用 ===")
render(3)
local c1 = created
render(3)
local c2 = created
render(3)
local c3 = created
check("第2次不新建", c2 == c1, string.format("created %d -> %d", c1, c2))
check("第3次不新建", c3 == c1, string.format("created %d -> %d", c1, c3))
check("控件都活着", aliveCount() >= 3, "alive=" .. aliveCount())

print()
print("=== 2. 列表数量变化后，控件数应与卡片数匹配 ===")
for _, n in ipairs{3, 5, 8, 2, 6, 3} do
  render(n)
  local a = aliveCount()
  -- 卡片是 textbox（有背景色），根是 container
  -- 期望：alive ≈ n + 1（根）
  local expect = n + 1
  check(string.format("render(%d)", n), a == expect,
      string.format("alive=%d 期望=%d", a, expect))
end

print()
print("=== 3. 反复重建不应无限增长（泄漏检测）===")
local before = created
for i = 1, 20 do render(4) end
local after = created
check("20 次重建不新建控件", after == before,
    string.format("created %d -> %d", before, after))

print()
print("=== 4. 增删交替 ===")
for i = 1, 10 do
  render(2 + (i % 5))
end
local a = aliveCount()
check("最终控件数正确", a == (2 + (10 % 5)) + 1,
    string.format("alive=%d", a))

print()
print("=== 5. 状态变化不应导致控件数变化 ===")
render(5)
local a1 = aliveCount()
-- 选中第 2 项（换 class，不增删元素）
render(5, { [2] = true })
local a2 = aliveCount()
check("class 变化控件数不变", a1 == a2,
    string.format("%d -> %d", a1, a2))

print()
print("=== 6. 空列表 ===")
render(0)
check("空列表只剩根", aliveCount() == 1, "alive=" .. aliveCount())
render(3)
check("空列表后恢复", aliveCount() == 4, "alive=" .. aliveCount())

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end