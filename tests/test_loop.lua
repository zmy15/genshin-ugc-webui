-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

--[[ 逐帧稳定性测试

     ★ 防止一个真实踩过的严重回归：
       为了修复 setHTML 场景的控件复用，我加了"预回收"，
       但它对【同一份 DOM 的 flush()】也生效了 ——
       导致逐帧循环里每帧都重建全部控件。

       真机日志（30fps，4 秒一次采样）：
         [TICK] #1  created=6080
         [TICK] #7  created=22952
         [TICK] #8  崩溃（live=0）

       本测试模拟逐帧循环，验证 created 不再增长。
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
  if kind=="button" then c.AddCursorEventListener=function(s,ev,cb)
    s._listeners=s._listeners or {}; s._listeners[#s._listeners+1]={ev=ev,cb=cb} end end
  if parent then parent._children[#parent._children+1]=c end
  alive[#alive+1]=c
  return c
end

game={ InstantiateClientUIControl=function(i,p)
    for k,v in pairs(PREFABS) do if v==i then return mc(k,p) end end end,
  DestroyClientUIControl=function() end,
  GetUICanvasSize=function() return 1600,900 end,
  GetClientUIRoots=function() return {} end,
  Tween=function() local t={} t.SetEase=function() return t end
    t.Play=function() return t end return t end,
  TweenSequence=function() local s={}
    s.AppendInterval=function() return s end
    s.AppendCallback=function() return s end
    s.Play=function() return s end return s end }
Color={FromRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
       FromRGB=function(r,g,b) return {r=r,g=g,b=b} end}
Enum={EaseType={Linear="Linear"},EaseTypeLinear="Linear",
      CursorEventType={CursorClick="CursorClick",CursorDown="CursorDown",
      CursorUp="CursorUp",CursorEnter="CursorEnter",CursorExit="CursorExit",
      CursorBeginDrag="CursorBeginDrag",CursorDrag="CursorDrag",CursorEndDrag="CursorEndDrag"},
      TextHorizontalAlignmentLeft="L",TextHorizontalAlignmentMiddle="C",
      TextHorizontalAlignmentRight="R"}

local webui = require('webui')
local dom    = require('webui_dom')

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass=pass+1; print(string.format("  [OK] %-34s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-34s %s", name, detail or "")) end
end

local root = mc("container", nil)
script = { object = root }
local ui = webui.new({ root=root, prefabs=PREFABS })

-- 一个有点规模的页面
local function makePage(n)
  local p = {}
  for i = 1, n do
    p[#p+1] = string.format([[
<div class="card" id="c%d">
  <div class="name">项目%d</div>
  <div class="row"><div class="tag">T</div><div class="val">%d</div></div>
</div>]], i, i, i*10)
  end
  return [[<style>
    .card { width:200px; height:100px; padding:10px; background-color:#22222e; }
    .name { width:180px; height:24px; font-size:16px; color:#fff; }
    .row  { display:flex; align-items:center; width:180px; height:24px; }
    .tag  { width:40px; height:20px; background-color:#4a90d9; }
    .val  { flex-grow:1; height:20px; color:#9a9ab0; }
  </style>]] .. table.concat(p)
end

print("=== 1. 首次渲染 ===")
ui:render(makePage(10))
local c0 = created
check("首次创建控件", c0 > 0, "created=" .. c0)
local live0 = 0
for _ in pairs(ui.rendered.live) do live0 = live0 + 1 end
check("live 数正确", live0 == 50, "live=" .. live0 .. " (10 卡 × 5 元素)")

print()
print("=== 2. 逐帧 flush 不应新建控件（核心回归测试）===")
local before = created
for frame = 1, 60 do
  ui:flush()
end
local after = created
check("60 帧 flush 不新建", after == before,
    string.format("created %d -> %d", before, after))

print()
print("=== 3. 逐帧 flush 写入次数应很少 ===")
local w1 = ui.rendered.stats.written
for frame = 1, 60 do ui:flush() end
local w2 = ui.rendered.stats.written
check("60 帧写入 < 50 次", (w2 - w1) < 50,
    string.format("写入 %d 次", w2 - w1))

print()
print("=== 4. 模拟 30fps 跑 5 秒（150 帧）===")
local b2 = created
for frame = 1, 150 do ui:flush() end
check("150 帧不新建", created == b2,
    string.format("created %d -> %d", b2, created))
local liveN = 0
for _ in pairs(ui.rendered.live) do liveN = liveN + 1 end
check("live 未泄漏", liveN == 50, "live=" .. liveN)

print()
print("=== 5. setHTML 后应能复用（不是每帧重建）===")
local b3 = created
ui:render(makePage(10))     -- 重新 setHTML + flush
local c3 = created
check("setHTML 后复用旧控件", c3 == b3,
    string.format("created %d -> %d", b3, c3))

print()
print("=== 6. 数量变化仍要正确 ===")
local b4 = created
ui:render(makePage(5))
check("减到 5 张不新建", created == b4, "created=" .. created)
local l5 = 0
for _ in pairs(ui.rendered.live) do l5 = l5 + 1 end
check("live 变为 25", l5 == 25, "live=" .. l5)

ui:render(makePage(20))
local l20 = 0
for _ in pairs(ui.rendered.live) do l20 = l20 + 1 end
check("扩到 100 个元素", l20 == 100, "live=" .. l20)
-- 池里此时有 50 个（从 10 张减到 5 张时回收的），需要 100 个
  -- 所以新建 100 - 50 = 50 个
  local made = created - b4
  check("按池子余量新建", made == 50,
      string.format("新建 %d 个（池里有 50 个可复用，共需 100 个）", made))

print()
print("=== 7. 再次逐帧 flush（确认没有回归）===")
local b5 = created
for frame = 1, 100 do ui:flush() end
check("100 帧不新建", created == b5,
    string.format("created %d -> %d", b5, created))

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end
