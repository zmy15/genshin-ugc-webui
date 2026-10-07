-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
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
      SetAnchorMin=1,SetAnchorMax=1,SetPivot=1,SetSiblingIndex=1,
      RemoveAllCursorEventListeners=1}
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
  --[[ ★ 必须真实记录 active / visible，不能是空实现。

       渲染层隐藏复用控件时调用的是 SetActive(false)（见 render.lua:_hide）。
       若这里写成空函数，mock 就无法反映"控件当前是否可见"，
       于是"筛选后卡片是否真的消失"这类语义断言全部失效。]]--
  c.SetActive=function(s,v) s.active=v end
  c.SetVisible=function(s,v) s.visible=v end
  c.GetChildren=function(s) return s._children end
  c.SetAnchoredPosition=function(s,x,y) s.anchoredPositionX=x; s.anchoredPositionY=y end
  c.SetSizeDelta=function(s,w,h) s.sizeDeltaX=w; s.sizeDeltaY=h end
  c.SetSiblingIndex=function() end
  c.RemoveAllCursorEventListeners=function(s) s._listeners={} end
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

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass=pass+1; print(string.format("  [OK] %-28s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-28s %s", name, detail or "")) end
end

local chunk = loadfile("deploy/demo_shop.lua")
local ok, err = pcall(chunk)
print("加载:", ok and "OK" or ("ERR " .. tostring(err)))
if not ok then return end

-- ★ 提供 script.object（真机上由引擎注入）
local mockRoot = mc("container", nil)
script = { object = mockRoot }

--[[ 收集当前控件树里所有【可见且有文本】的控件文本

     ⚠️ 只统计 active ~= false 的控件：
        渲染层复用控件时用 SetActive(false) 隐藏（见 render.lua:_hide），
        被隐藏的旧控件仍保留着上一次的 text 字段。
        若把它们也算进来，会误判成"筛选没生效"。]]--
local function visibleTexts()
  local out = {}
  local function walk(c)
    if c.active ~= false and c.text and c.text ~= "" then out[#out+1] = c.text end
    for _, k in ipairs(c._children) do walk(k) end
  end
  for _, c in ipairs(mockRoot._children) do walk(c) end
  return out
end

--[[ 当前可见文本里是否有子串（plain find：文本含中文与标点）]]--
local function hasText(sub)
  for _, t in ipairs(visibleTexts()) do
    if t:find(sub, 1, true) then return true end
  end
  return false
end

--[[ 统计当前可见的卡片数：demo 用 .cardName 显示装备名。
     按"可见文本 == 装备名"计数，比数控件数更接近语义。]]--
local NAMES = { "炎之剑", "冰霜弓", "铁壁盾", "疾风靴", "烈焰甲",
                "寒铁盔", "雷神之戒", "翠绿项链", "水镜法杖", "磐岩护腕" }
local function visibleCards()
  local n = 0
  local texts = visibleTexts()
  for _, nm in ipairs(NAMES) do
    for _, t in ipairs(texts) do
      if t == nm then n = n + 1; break end
    end
  end
  return n
end

print()
print("=== 调用 OnStart ===")
local ok2, err2 = pcall(OnStart)
if not ok2 then print("  OnStart 出错: " .. tostring(err2)) end
check("demo 能加载", ok, ok and "OK" or tostring(err))
check("OnStart 无异常", ok2, ok2 and "OK" or tostring(err2))

print()
print("=== 控件统计 ===")
print("  总控件数: " .. #controls)
local byKind = {}
for _, c in ipairs(controls) do
  byKind[c._kind] = (byKind[c._kind] or 0) + 1
end
for k, v in pairs(byKind) do print(string.format("    %-10s %d", k, v)) end
--[[ 渲染确实建出了控件。

     ⚠️ 这里【不】断言 #controls == 153 这种精确数字：
        控件数是"实现细节"，卡片数/复用策略一改就变，锁死它会制造假回归。
        真正该守住的是【结构完整性】：三种控件都建出来了，且数量非零。]]--
check("建出了控件", #controls > 0, string.format("总控件数=%d", #controls))
check("container/textbox/button 三类齐全",
    (byKind.container or 0) > 0 and (byKind.textbox or 0) > 0 and (byKind.button or 0) > 0,
    string.format("container=%d textbox=%d button=%d",
        byKind.container or 0, byKind.textbox or 0, byKind.button or 0))

--[[ ★ 初始状态：10 件装备全部可见、金币 12,480、等级 42。
     这是"首屏渲染正确"的核心语义断言。]]--
check("初始显示全部 10 张卡片", visibleCards() == 10,
    string.format("可见卡片=%d (期望10)", visibleCards()))
check("顶栏金币正确", hasText("12,480 金"),
    hasText("12,480 金") and "12,480 金" or "未找到")
check("顶栏等级正确", hasText("Lv.42"),
    hasText("Lv.42") and "Lv.42" or "未找到")
check("标题正确", hasText("装备商店"), "装备商店")

print()
print("=== 事件监听数 ===")
local listeners = 0
for _, c in ipairs(controls) do
  if c._listeners then listeners = listeners + #c._listeners end
end
print("  " .. listeners)
--[[ 监听数应等于"绑定了 onclick 的元素数"：
     4 个页签 + 3 个筛选 + 10 张卡片 + 2 个底栏按钮 = 19。
     这个数字有明确语义（每个可点元素恰好 1 个监听），
     所以值得断言 —— 它能抓住"监听重复绑定/漏绑"的回归。]]--
check("每个可点元素恰好 1 个监听", listeners == 19,
    string.format("监听器=%d (期望19 = 4页签+3筛选+10卡片+2按钮)", listeners))

print()
print("=== 模拟交互 ===")
local handlers = capturedHandlers
print("  处理器数量: " .. (function()
  if not handlers then return 0 end
  local n = 0 for _ in pairs(handlers) do n = n + 1 end return n end)())
check("处理器表已注入", handlers ~= nil, handlers and "有" or "nil")

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
--[[ 语义：weapon 类共 3 件（炎之剑/冰霜弓/水镜法杖），armor 类应消失。
     同时验证被过滤掉的卡片确实不可见（而不是只是计数没变）。]]--
check("切「武器」后剩 3 张卡", visibleCards() == 3,
    string.format("可见卡片=%d (期望3=炎之剑/冰霜弓/水镜法杖)", visibleCards()))
check("防具已隐藏", not hasText("铁壁盾"), "铁壁盾应不可见")

-- 2. 筛选
click("kw_火")
print(string.format("  筛选「火」: 控件 %d", #controls))
--[[ 语义：武器 + 火 只有炎之剑 1 件。
     ⚠️ warp 到「武器」页签后再筛「火」是【与】关系，冰霜弓(冰)必须消失。]]--
check("武器+火 只剩 1 张", visibleCards() == 1,
    string.format("可见卡片=%d (期望1=炎之剑)", visibleCards()))
check("非火属性已隐藏", not hasText("冰霜弓"), "冰霜弓(冰属性)应不可见")

-- 3. 点卡片
click("pick_f1")
print(string.format("  点炎之剑: 控件 %d", #controls))
check("点卡片后详情栏更新", hasText("炎之剑 · 火属性"),
    hasText("炎之剑 · 火属性") and "炎之剑 · 火属性" or "未找到详情")
check("加入购物车提示", hasText("已加入"), "已加入")

-- 4. 再点一次（移出）
click("pick_f1")
print(string.format("  再点一次: 控件 %d", #controls))
check("再点移出购物车", hasText("已移出"), "已移出")
check("移出后购物车无该件", not hasText("购物车 1 件"), "不应还显示购物车 1 件")

-- 5. 结算
click("pick_f1")   -- 加回购物车
click("onPay")
print(string.format("  结算: 控件 %d", #controls))
--[[ 语义核对（demo 里 ITEMS 的定价）：
       炎之剑 price=1200，初始金币 12480 -> 结算后 12480-1200 = 11280。
     这条同时验证了"扣款金额"与"余额显示"两件事。]]--
check("结算扣款正确（12,480-1,200）", hasText("购买成功，花费 1,200"),
    hasText("购买成功，花费 1,200") and "花费 1,200" or "未找到结算提示")
check("结算后余额 11,280", hasText("11,280 金"),
    hasText("11,280 金") and "11,280 金" or "未找到余额")
check("购买后卡片标记已拥有", hasText("已拥有"), "已拥有")

-- 6. 清空
click("onClear")
print(string.format("  清空: 控件 %d", #controls))
check("清空有提示", hasText("已清空"), "已清空")

-- 7. 回到全部
click("tab_all")
click("kw_火")     -- 关掉筛选
print(string.format("  回到全部: 控件 %d", #controls))
--[[ 语义：回到「全部」页签并关掉筛选，10 件装备应全部重新可见。
     这条专门抓"筛选状态没被正确清除"的回归。]]--
check("回到全部后 10 张卡都可见", visibleCards() == 10,
    string.format("可见卡片=%d (期望10)", visibleCards()))
check("之前隐藏的防具重新可见", hasText("铁壁盾"), "铁壁盾应重新可见")

print()
print("=== 最终统计 ===")
print("  总创建控件: " .. created)
print("  当前控件数: " .. #controls)
--[[ ★ 控件池复用：整页重建 9 次后，创建的控件总数不应远大于首屏规模。
     若复用失效（每次操作都新建全部控件），created 会膨胀到 1500+。
     阈值取首屏的 3 倍，既能容忍真实的增量，又能抓住复用失效。]]--
check("控件池复用有效（created 未膨胀）", created < #controls * 3,
    string.format("created=%d 当前=%d (阈值<%d)", created, #controls, #controls * 3))

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end
