--[[============================================================================
  DEMO · 装备商店（复杂示例）
==============================================================================

  刻意堆了尽量多的功能，用来验证库在真实场景下的表现。

  页面结构：
    ┌──────────────────────────────────────────────────────────────┐
    │  装备商店                             12,480 金   Lv.42     │  顶栏
    ├──────────────────────────────────────────────────────────────┤
    │  [全部][武器][防具][饰品]         筛选 [火][冰][雷]         │  页签
    ├──────────────────────────────────────────────────────────────┤
    │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐               │
    │  │ 炎之剑  │ │ 冰霜弓  │ │ 铁壁盾  │ │ 疾风靴  │               │  卡片
    │  │[火]★★★★☆│ │[冰]★★★☆☆│ │[岩]★★☆☆☆│ │[风]★★★★☆│               │  网格
    │  │ 攻击+120│ │ 攻击 +95│ │ 攻击 +0 │ │ 攻击 +30│               │  (wrap)
    │  │ 1,200 →│ │   860 →│ │   420 →│ │ 已拥有 │               │
    │  └────────┘ └────────┘ └────────┘ └────────┘               │
    ├──────────────────────────────────────────────────────────────┤
    │  已选  炎之剑 · 火属性 · 攻击 +120 · ★★★★☆          1,200  │  详情
    ├──────────────────────────────────────────────────────────────┤
    │  购物车 2 件，合计 2,060            [ 清空 ]  [ 结算 ]      │  底栏
    └──────────────────────────────────────────────────────────────┘

  验证的能力：
    ✓ 五层嵌套布局
    ✓ flex-wrap 网格自动换行
    ✓ flex-grow 两端对齐
    ✓ 数据驱动列表重建
    ✓ 页签 / 筛选 / 选中 三种状态联动
    ✓ class 切换 + transition 过渡
    ✓ hover 效果
    ✓ 逐帧循环 + diff

  ⚠️ 列表更新策略：
      卡片数量会变，必须重建 DOM。做法是【整页重新 setHTML】——
      因为 webui 的 setHTML 会重建 DOM 树，而 render 层的控件池
      会复用同位置的控件（diff），所以代价可控。

================================================================================
  部署：挂到 ProbeRoot，进游戏
============================================================================================================================================]]

local PREFABS = {
  container = 1073741933,
  textbox   = 1073741934,
  button    = 1073741935,
}

local ENABLE_LOOP = true
local LOOP_FPS    = 30

--=============================================================================

--=============================================================================
-- 加载 webui 库
--
--   ⚠️ 不要把 require 的错误吞掉 —— 真机排查时看不到原因会浪费很多轮。
--      这里把真实错误打印出来。
--=============================================================================

local webui
do
  local ok, m = pcall(require, "webui")
  if ok and m then
    webui = m
  else
    printerr("[DEMO] require('webui') 失败")
    printerr("[DEMO]   返回值 ok   = " .. tostring(ok))
    printerr("[DEMO]   返回值 m    = " .. tostring(m))

    -- 逐个模块试，定位是哪个模块挂了
    local MODS = { "webui_util", "webui_dom", "webui_html", "webui_css",
                   "webui_color", "webui_style", "webui_transition",
                   "webui_layout", "webui_render", "webui_event" }
    for _, name in ipairs(MODS) do
      local o2, m2 = pcall(require, name)
      printerr(string.format("[DEMO]   require('%-18s') -> %s  %s",
          name, tostring(o2),
          o2 and "OK" or tostring(m2)))
    end
    return
  end
end

print("[DEMO] webui " .. tostring(webui.VERSION))

local say = print
local dom = webui.dom

local function warn(...)
  local n = select('#', ...)
  local t = {}
  for i = 1, n do t[i] = tostring((select(i, ...))) end
  local m = "[DEMO][warn] " .. table.concat(t, " ")
  if type(printerr) == "function" then pcall(printerr, m) else print(m) end
end

--=============================================================================
-- 数据
--=============================================================================

local ITEMS = {
  { id="f1", name="炎之剑",   cat="weapon",  attr="火", atk=120, price=1200, star=4, owned=false },
  { id="i1", name="冰霜弓",   cat="weapon",  attr="冰", atk= 95, price= 860, star=3, owned=false },
  { id="a1", name="铁壁盾",   cat="armor",   attr="岩", atk=  0, price= 420, star=2, owned=false },
  { id="b1", name="疾风靴",   cat="armor",   attr="风", atk= 30, price=1500, star=4, owned=true  },
  { id="a2", name="烈焰甲",   cat="armor",   attr="火", atk= 10, price= 980, star=3, owned=false },
  { id="a3", name="寒铁盔",   cat="armor",   attr="冰", atk=  5, price= 640, star=2, owned=false },
  { id="t1", name="雷神之戒", cat="trinket", attr="雷", atk= 75, price=2100, star=5, owned=false },
  { id="t2", name="翠绿项链", cat="trinket", attr="草", atk= 40, price=1100, star=3, owned=false },
  { id="f2", name="水镜法杖", cat="weapon",  attr="水", atk=140, price=1800, star=5, owned=false },
  { id="a4", name="磐岩护腕", cat="armor",   attr="岩", atk= 20, price= 720, star=3, owned=true  },
}

local TABS = {
  { id="tab_all",     val="all",     label="全部" },
  { id="tab_weapon",  val="weapon",  label="武器" },
  { id="tab_armor",   val="armor",   label="防具" },
  { id="tab_trinket", val="trinket", label="饰品" },
}

local KWS = { "火", "冰", "雷" }

local ATTR_COLOR = {
  ["火"]="#e05a3a", ["冰"]="#5ab8e0", ["岩"]="#d0a840",
  ["风"]="#5ad0a0", ["雷"]="#a86ae0", ["草"]="#7ac050",
  ["水"]="#4a90d9",
}

--=============================================================================
-- 状态
--=============================================================================

local state = {
  gold     = 12480,
  level    = 42,
  cat      = "all",
  keyword  = "",
  selected = nil,
  cart     = {},
  msg      = "",
}

--=============================================================================
-- 工具
--=============================================================================

local function starStr(n)
  local s = ""
  for i = 1, 5 do s = s .. (i <= n and "★" or "☆") end
  return s
end

local function comma(n)
  n = math.floor(n or 0)
  local s = tostring(n)
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  out = out:gsub("^,", "")
  return out
end

local function findItem(id)
  for _, x in ipairs(ITEMS) do if x.id == id then return x end end
end

local function filteredItems()
  local out = {}
  for _, it in ipairs(ITEMS) do
    local okCat = (state.cat == "all") or (it.cat == state.cat)
    local okKw  = (state.keyword == "") or (it.attr == state.keyword)
    if okCat and okKw then out[#out + 1] = it end
  end
  return out
end

local function cartTotal()
  local sum = 0
  for _, id in ipairs(state.cart) do
    local it = findItem(id)
    if it then sum = sum + it.price end
  end
  return sum
end

local function inCart(id)
  for _, x in ipairs(state.cart) do if x == id then return true end end
  return false
end

--=============================================================================
-- 生成 HTML
--=============================================================================

local function cardHTML(item)
  local attrBg = ATTR_COLOR[item.attr] or "#555566"
  local isSel  = (state.selected == item.id) and " sel" or ""
  local picked = inCart(item.id)

  local price = item.owned and "已拥有"
             or (picked and "已加入" or comma(item.price))
  local btnCls = item.owned and "buyBtn owned" or "buyBtn"
  local btnTxt = item.owned and "已拥有" or (picked and "取消" or "加入")

  return string.format([[
<div class="card%s" id="card_%s" onclick="pick_%s">
  <div class="cardName">%s</div>
  <div class="cardRow">
    <div class="cardAttr" style="background-color:%s">%s</div>
    <div class="cardStar">%s</div>
  </div>
  <div class="cardAtk">攻击 +%d</div>
  <div class="cardFoot">
    <div class="cardPrice">%s</div>
    <div class="cardGrow"></div>
    <div class="%s">%s</div>
  </div>
</div>]], isSel, item.id, item.id,
    item.name, attrBg, item.attr, starStr(item.star),
    item.atk, price, btnCls, btnTxt)
end

local function buildPage()
  -- 卡片区
  local cards = {}
  local list = filteredItems()
  for _, it in ipairs(list) do cards[#cards + 1] = cardHTML(it) end
  local gridInner = table.concat(cards)

  -- 空状态
  if #list == 0 then
    gridInner = '<div class="empty">没有符合条件的装备</div>'
  end

  -- 页签
  local tabBuf = {}
  for i, t in ipairs(TABS) do
    if i > 1 then tabBuf[#tabBuf+1] = '<div class="tabGap"></div>' end
    tabBuf[#tabBuf+1] = string.format(
      '<div class="tab%s" id="%s" onclick="%s">%s</div>',
      state.cat == t.val and " on" or "", t.id, t.id, t.label)
  end
  local tabsHTML = table.concat(tabBuf)

  -- 筛选词
  local kwBuf = {}
  for i, k in ipairs(KWS) do
    if i > 1 then kwBuf[#kwBuf+1] = '<div class="kwGap"></div>' end
    kwBuf[#kwBuf+1] = string.format(
      '<div class="kw%s" id="kw_%s" onclick="kw_%s">%s</div>',
      state.keyword == k and " on" or "", k, k, k)
  end
  local kwsHTML = table.concat(kwBuf)

  -- 详情
  local detailText, detailGold = "未选择", ""
  if state.selected then
    local it = findItem(state.selected)
    if it then
      detailText = string.format("%s · %s属性 · 攻击 +%d · %s",
          it.name, it.attr, it.atk, starStr(it.star))
      detailGold = "售价 " .. comma(it.price)
    end
  end

  -- 底栏
  local msg = state.msg
  if msg == "" and #state.cart > 0 then
    msg = string.format("购物车 %d 件，合计 %s",
        #state.cart, comma(cartTotal()))
  end

  return string.format([[
<style>
  .app { width:920px; background-color:#16161e; }

  .topbar   { display:flex; align-items:center; width:920px; height:64px;
              padding:0 20px; background-color:#1e1e2a; }
  .appTitle { width:300px; height:30px; font-size:22px; color:#ffffff; }
  .topGrow  { flex-grow:1; height:30px; }
  .goldBox  { width:160px; height:30px; font-size:17px; color:#f0c860; }
  .lvBox    { width:110px; height:30px; font-size:17px; color:#8ac4ff; }

  .tabbar { display:flex; align-items:center; width:920px; height:52px;
            padding:0 20px; background-color:#1a1a24; }
  .tab { width:92px; height:34px; font-size:15px; color:#9a9ab0;
         background-color:#262632;
         transition: background-color 0.16s ease-out, color 0.16s ease-out; }
  .tab:hover { background-color:#32324a; color:#d0d0e0; }
  .tab.on    { background-color:#4a90d9; color:#ffffff; }
  .tabGap { width:8px; height:34px; }
  .tabGrow { flex-grow:1; height:34px; }

  .kwLabel { width:60px; height:30px; font-size:14px; color:#7a7a90; }
  .kw { width:64px; height:30px; font-size:14px; color:#9a9ab0;
        background-color:#262632;
        transition: background-color 0.16s ease-out, color 0.16s ease-out; }
  .kw:hover { background-color:#32324a; color:#d0d0e0; }
  .kw.on    { background-color:#d0703a; color:#ffffff; }
  .kwGap { width:6px; height:30px; }

  .listArea { width:920px; padding:16px 20px; background-color:#16161e; }
  .grid { display:flex; flex-wrap:wrap; width:880px; gap:14px; }
  .empty { width:880px; height:40px; font-size:15px; color:#6a6a80; }

  .card { width:206px; height:138px; padding:12px; background-color:#22222e;
          transition: background-color 0.16s ease-out; }
  .card:hover { background-color:#2c2c40; }
  .card.sel   { background-color:#2a3550; }

  .cardName { width:182px; height:24px; font-size:16px; color:#ffffff; }
  .cardRow  { display:flex; align-items:center; width:182px; height:24px; }
  .cardAttr { width:46px; height:20px; font-size:12px; color:#ffffff; }
  .cardStar { width:130px; height:20px; font-size:13px; color:#f0c860; }
  .cardAtk  { width:182px; height:22px; font-size:13px; color:#9a9ab0; }

  .cardFoot  { display:flex; align-items:center; width:182px; height:32px; }
  .cardPrice { width:96px; height:24px; font-size:15px; color:#f0c860; }
  .cardGrow  { flex-grow:1; height:24px; }
  .buyBtn { width:66px; height:28px; font-size:13px; color:#ffffff;
            background-color:#4a90d9;
            transition: background-color 0.16s ease-out; }
  .buyBtn:hover { background-color:#5aa0e9; }
  .buyBtn.owned { background-color:#3a3a4a; color:#7a7a90; }

  .detail { display:flex; align-items:center; width:920px; height:46px;
            padding:0 20px; background-color:#1a1a24; }
  .detailLabel { width:60px; height:26px; font-size:14px; color:#7a7a90; }
  .detailText  { flex-grow:1; height:26px; font-size:15px; color:#d0d0e0; }
  .detailGold  { width:160px; height:26px; font-size:15px; color:#f0c860; }

  .bottom { display:flex; align-items:center; width:920px; height:62px;
            padding:0 20px; background-color:#1e1e2a; }
  .msg { width:400px; height:26px; font-size:14px; color:#6ad48a; }
  .bottomGrow { flex-grow:1; height:40px; }
  .btnClear { width:96px; height:40px; font-size:15px; color:#c8c8d8;
              background-color:#3a3a4a;
              transition: background-color 0.16s ease-out; }
  .btnClear:hover { background-color:#48485c; }
  .btnGap { width:12px; height:40px; }
  .btnPay { width:116px; height:40px; font-size:15px; color:#ffffff;
            background-color:#3a9d5d;
            transition: background-color 0.16s ease-out; }
  .btnPay:hover { background-color:#4ab06d; }
</style>

<div class="app">
  <div class="topbar">
    <div class="appTitle">装备商店</div>
    <div class="topGrow"></div>
    <div class="goldBox">%s 金</div>
    <div class="lvBox">Lv.%d</div>
  </div>

  <div class="tabbar">
    %s
    <div class="tabGrow"></div>
    <div class="kwLabel">筛选</div>
    %s
  </div>

  <div class="listArea">
    <div class="grid">%s</div>
  </div>

  <div class="detail">
    <div class="detailLabel">已选</div>
    <div class="detailText">%s</div>
    <div class="detailGold">%s</div>
  </div>

  <div class="bottom">
    <div class="msg">%s</div>
    <div class="bottomGrow"></div>
    <div class="btnClear" onclick="onClear">清空</div>
    <div class="btnGap"></div>
    <div class="btnPay" onclick="onPay">结算</div>
  </div>
</div>]],
  comma(state.gold), state.level,
  tabsHTML, kwsHTML, gridInner,
  detailText, detailGold, msg)
end

--=============================================================================
-- 事件
--=============================================================================

local ui
local ROOT
local clickCount = 0
local reportCount = 0

local handlers = {}

--[[ 重绘：重建 HTML -> 重新渲染 ]]--
local function redraw()
  local ok, err = pcall(function()
    ui:render(buildPage())
  end)
  if not ok then warn("重绘失败: " .. tostring(err)) end
end

-- 页签
for _, t in ipairs(TABS) do
  handlers[t.id] = function()
    clickCount = clickCount + 1
    state.cat = t.val
    state.selected = nil
    state.msg = ""
    say(string.format("[TAB] #%d -> %s", clickCount, t.label))
    redraw()
  end
end

-- 筛选词
for _, k in ipairs(KWS) do
  handlers["kw_" .. k] = function()
    clickCount = clickCount + 1
    state.keyword = (state.keyword == k) and "" or k
    state.msg = ""
    say(string.format("[FILTER] #%d -> %s", clickCount,
        state.keyword == "" and "全部" or state.keyword))
    redraw()
  end
end

-- 卡片点击：已拥有不可操作；否则加入/移出购物车 + 选中
for _, it in ipairs(ITEMS) do
  handlers["pick_" .. it.id] = function()
    clickCount = clickCount + 1
    if it.owned then
      say(string.format("[PICK] #%d %s（已拥有）", clickCount, it.name))
      state.selected = it.id
      state.msg = it.name .. " 已拥有"
      redraw()
      return
    end

    state.selected = it.id
    if inCart(it.id) then
      for i = #state.cart, 1, -1 do
        if state.cart[i] == it.id then table.remove(state.cart, i) end
      end
      state.msg = "已移出：" .. it.name
      say(string.format("[CART-] #%d %s", clickCount, it.name))
    else
      state.cart[#state.cart + 1] = it.id
      state.msg = "已加入：" .. it.name
      say(string.format("[CART+] #%d %s", clickCount, it.name))
    end
    redraw()
  end
end

handlers.onClear = function()
  clickCount = clickCount + 1
  state.cart = {}
  state.selected = nil
  state.msg = "已清空"
  say(string.format("[CLEAR] #%d", clickCount))
  redraw()
end

handlers.onPay = function()
  clickCount = clickCount + 1
  local n = #state.cart
  local sum = cartTotal()

  if n == 0 then
    state.msg = "购物车是空的"
    say(string.format("[PAY] #%d 空购物车", clickCount))
  elseif state.gold < sum then
    state.msg = "金币不足"
    say(string.format("[PAY] #%d 金币不足（需 %d，有 %d）",
        clickCount, sum, state.gold))
  else
    state.gold = state.gold - sum
    for _, id in ipairs(state.cart) do
      local it = findItem(id)
      if it then it.owned = true end
    end
    state.msg = string.format("购买成功，花费 %s", comma(sum))
    say(string.format("[PAY] #%d 成功，花费 %d，余额 %d",
        clickCount, sum, state.gold))
    state.cart = {}
    state.selected = nil
  end
  redraw()
end

--=============================================================================
-- 生命周期
--=============================================================================

function OnStart()
  say("[DEMO] OnStart")

  ROOT = script.object
  if not ROOT then
    local roots = game.GetClientUIRoots()
    if roots and #roots > 0 then ROOT = roots[1] end
  end
  if not ROOT then warn("找不到根控件"); return end
  say("[DEMO] 根控件已获取")

  pcall(function()
    ROOT:SetAnchorMin(0.5, 0.5); ROOT:SetAnchorMax(0.5, 0.5)
    ROOT:SetPivot(0.5, 0.5)
    ROOT:SetSizeDelta(1600, 900)
    ROOT:SetAnchoredPosition(0, 0)
    ROOT:SetActive(true); ROOT:SetVisible(true)
  end)

  local ok, err = pcall(function()
    ui = webui.new({ root = ROOT, prefabs = PREFABS, handlers = handlers })
  end)
  if not ok then warn("webui.new 失败: " .. tostring(err)); return end

  local rok, rerr = pcall(function() ui:render(buildPage()) end)
  if not rok then warn("渲染失败: " .. tostring(rerr)); return end

  say("[DEMO] 渲染完成")
  local st = dom.stats(ui.doc)
  say(string.format("   DOM: 元素=%d 文本=%d 深度=%d",
      st.elements, st.texts, st.maxDepth))
  say("   " .. ui.rendered:statsText())
  say(string.format("   事件绑定: %d（卡片 %d 项）",
      ui.boundCount, #filteredItems()))

  if ENABLE_LOOP then
    pcall(function() ui:startLoop(LOOP_FPS) end)
    say("[DEMO] 循环 @" .. LOOP_FPS .. "fps")
  end

  local function report()
    reportCount = reportCount + 1
    say(string.format("[TICK] #%d 操作=%d 页签=%s 筛选=%s 购物车=%d %s",
        reportCount, clickCount, state.cat,
        state.keyword == "" and "-" or state.keyword,
        #state.cart, ui.rendered:statsText()))
    pcall(function()
      local seq = game.TweenSequence()
      if seq then
        seq:AppendInterval(4.0); seq:AppendCallback(report); seq:Play()
      end
    end)
  end
  pcall(function()
    local seq = game.TweenSequence()
    if seq then
      seq:AppendInterval(4.0); seq:AppendCallback(report); seq:Play()
    end
  end)

  say("")
  say("[DEMO] ===== 测试点 =====")
  say("  1. 点页签「武器/防具/饰品」 -> 卡片列表过滤")
  say("  2. 点筛选「火/冰/雷」       -> 只显示该属性")
  say("  3. 点卡片                   -> 卡片变蓝 + 详情栏更新")
  say("  4. 再点同一张卡片           -> 移出购物车")
  say("  5. 卡片 hover               -> 背景变亮")
  say("  6. 点「结算」               -> 扣金币，卡片变「已拥有」")
  say("  7. 点「清空」               -> 购物车清零")
end

function OnUpdate(dt) end

function OnDestroy()
  say("[DEMO] 结束 操作=" .. clickCount)
  if ui then pcall(function() ui:stopLoop() end) end
end
