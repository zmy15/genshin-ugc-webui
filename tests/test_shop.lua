-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

-- mock 引擎
local PREFABS = { container=1073741933, textbox=1073741934, button=1073741935 }
local created, controls = 0, {}
local function mc(kind, parent)
  created = created + 1
  local c = { _kind=kind, name=kind,
    anchorMinX=.5,anchorMinY=.5,anchorMaxX=.5,anchorMaxY=.5,
    pivotX=.5,pivotY=.5,anchoredPositionX=0,anchoredPositionY=0,
    sizeDeltaX=0,sizeDeltaY=0,visible=true,active=true,_children={},_listeners={} }
  setmetatable(c,{__newindex=function(t,k,v)
    local METHODS={SetActive=1,SetVisible=1,GetChildren=1,SetAnchoredPosition=1,
      SetSizeDelta=1,AddCursorEventListener=1,GetChild=1,FindChild=1,
      SetAnchorMin=1,SetAnchorMax=1,SetPivot=1,SetSiblingIndex=1}
    if METHODS[k] then rawset(t,k,v) return end
    local common={anchorMinX=1,anchorMinY=1,anchorMaxX=1,anchorMaxY=1,
      pivotX=1,pivotY=1,anchoredPositionX=1,anchoredPositionY=1,
      sizeDeltaX=1,sizeDeltaY=1,visible=1,active=1,name=1,
      localScaleX=1,localScaleY=1,localRotationZ=1,__type=1}
    local sup
    if kind=="textbox" then sup={bgColor=1,text=1,fontColor=1,fontSize=1,horizontalAlignment=1,verticalAlignment=1}
    elseif kind=="button" then sup={interactable=1,raycastTarget=1,clickAudioId=1}
    else sup={} end
    if common[k] or sup[k] then rawset(t,k,v)
    else error("cannot set "..k..", no such field",2) end
  end})
  c.SetActive=function() end
  c.SetVisible=function() end
  c.GetChildren=function(s) return s._children end
  c.SetAnchoredPosition=function() end
  c.SetSizeDelta=function() end
  c.SetSiblingIndex=function() end
  if kind=="button" then
    c.AddCursorEventListener=function(s,ev,cb) s._listeners[#s._listeners+1]={ev=ev,cb=cb} end
  end
  if parent then parent._children[#parent._children+1]=c end
  controls[#controls+1]=c
  return c
end

game={ InstantiateClientUIControl=function(i,p)
    for k,v in pairs(PREFABS) do if v==i then return mc(k,p) end end end,
  DestroyClientUIControl=function() end,
  GetUICanvasSize=function() return 1600,900 end,
  GetClientUIRoots=function() return {} end,
  Tween=function() local t={} t.SetEase=function() return t end
    t.Play=function() return t end t.SetLoops=function() return t end return t end,
  TweenSequence=function() local s={}
    s.AppendInterval=function() return s end
    s.AppendCallback=function() return s end
    s.Play=function() return s end return s end }
Color={FromRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
       FromRGB=function(r,g,b) return {r=r,g=g,b=b} end}
Enum={EaseType={Linear="Linear",InQuad="InQuad",OutQuad="OutQuad",InOutQuad="InOutQuad"},
      EaseTypeLinear="Linear",
      CursorEventType={CursorClick="CursorClick",CursorDown="CursorDown",CursorUp="CursorUp",
      CursorEnter="CursorEnter",CursorExit="CursorExit",CursorBeginDrag="CursorBeginDrag",
      CursorDrag="CursorDrag",CursorEndDrag="CursorEndDrag"},
      TextHorizontalAlignmentLeft="L",TextHorizontalAlignmentMiddle="C",
      TextHorizontalAlignmentRight="R"}

-- 加载 demo
local capturedHandlers = nil
do
  local webui = require('webui')
  local origNew = webui.new
  webui.new = function(opts)
    capturedHandlers = opts and opts.handlers
    return origNew(opts)
  end
end

local chunk = loadfile("deploy/demo_shop.lua")
local ok, err = pcall(chunk)
print("加载:", ok and "OK" or ("ERR " .. tostring(err)))
if not ok then return end

-- ★ 提供 script.object（真机上由引擎注入）
local mockRoot = mc("container", nil)
script = { object = mockRoot }

print()
print("=== 调用 OnStart ===")
local ok2, err2 = pcall(OnStart)
if not ok2 then print("  OnStart 出错: " .. tostring(err2)) end

print()
print("=== 控件统计 ===")
print("  总控件数: " .. #controls)
local byKind = {}
for _, c in ipairs(controls) do
  byKind[c._kind] = (byKind[c._kind] or 0) + 1
end
for k, v in pairs(byKind) do print(string.format("    %-10s %d", k, v)) end

print()
print("=== 事件监听数 ===")
local listeners = 0
for _, c in ipairs(controls) do
  if c._listeners then listeners = listeners + #c._listeners end
end
print("  " .. listeners)

print()
print("=== 模拟交互 ===")
local handlers = capturedHandlers
print("  处理器数量: " .. (function()
  if not handlers then return 0 end
  local n = 0 for _ in pairs(handlers) do n = n + 1 end return n end)())

local function click(name)
  if not handlers or not handlers[name] then
    print("  ✗ 没有处理器: " .. name); return false
  end
  local ok, e = pcall(handlers[name])
  if not ok then print("  ✗ 出错 " .. name .. ": " .. tostring(e)) end
  return ok
end

-- 1. 切换页签
local before = #controls
click("tab_weapon")
print(string.format("  切到「武器」: 控件 %d -> %d", before, #controls))

-- 2. 筛选
click("kw_火")
print(string.format("  筛选「火」: 控件 %d", #controls))

-- 3. 点卡片
click("pick_f1")
print(string.format("  点炎之剑: 控件 %d", #controls))

-- 4. 再点一次（移出）
click("pick_f1")
print(string.format("  再点一次: 控件 %d", #controls))

-- 5. 结算
click("pick_f1")   -- 加回购物车
click("onPay")
print(string.format("  结算: 控件 %d", #controls))

-- 6. 清空
click("onClear")
print(string.format("  清空: 控件 %d", #controls))

-- 7. 回到全部
click("tab_all")
click("kw_火")     -- 关掉筛选
print(string.format("  回到全部: 控件 %d", #controls))

print()
print("=== 最终统计 ===")
print("  总创建控件: " .. created)
print("  当前控件数: " .. #controls)