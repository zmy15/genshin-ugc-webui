--[[============================================================================
  DEMO · 角色面板（综合测试页 —— 验证 R16/R17 新能力）

  目的：用一个真实的复杂界面，验证新封装的裁剪/换图能力在实战中是否可用。

  ┌────────────────────────────────────────────────────────────────────┐
  │  角色面板                                    Lv.42   12,480 金     │ 顶栏
  ├────────────────────────────────────────────────────────────────────┤
  │  ┌──────┐  夜兰                                              ★★★★★ │
  │  │ 圆形 │  水元素 · 弓                                              │
  │  │ 头像 │  ┌──────────────────────────────────────┐               │
  │  └──────┘  │ HP  ████████████████░░░░░░  18,420   │               │ 进度条
  │            │ ATK ██████████████░░░░░░░░   1,280   │               │
  │            │ DEF ████████░░░░░░░░░░░░░░     640   │               │
  ├────────────────────────────────────────────────────────────────────┤
  │  技能                                                              │
  │  ┌────────┐ ┌────────┐ ┌────────┐                                 │
  │  │  ◆ 圆环│ │  ▲ 三角│ │  ● 圆形│   ← 图片控件 + SetImage         │
  │  │  普通  │ │  元素  │ │  爆发  │                                  │
  │  └────────┘ └────────┘ └────────┘                                 │
  ├────────────────────────────────────────────────────────────────────┤
  │  圣遗物（★ 卡片用 overflow:hidden 裁剪，内容溢出被切掉）            │
  │  ┌────────────┐ ┌────────────┐                                    │
  │  │▓▓▓▓▓▓▓▓▓▓▓▓│ │▓▓▓▓▓▓▓▓▓▓▓▓│   ← 顶部色带（溢出裁剪测试）      │
  │  │ 生之花     │ │ 死之羽     │                                    │
  ├────────────────────────────────────────────────────────────────────┤
  │  装饰：菱形 ◆   星 ★   圆环 ○   三角 ▲      ← 字符 vs 图片 对照    │
  └────────────────────────────────────────────────────────────────────┘

  ★ 本页重点验证：
    1. 圆形裁剪（border-radius:50%）—— 头像
    2. 矩形裁剪（overflow:hidden）  —— 圣遗物卡片，内容故意溢出
    3. 图片控件 + SetImage          —— 技能图标用真实形状图
    4. 裁剪与内边距/子元素共存       —— 裁剪容器里有嵌套内容
    5. 大量控件下的稳定性            —— 逐帧 flush 不新建

  ⚠️ 部署：挂到客户端控件上（与 demo_shop 相同位置）
=============================================================================]]

local PREFABS = {
  container = 1073741933,
  textbox   = 1073741934,
  button    = 1073741935,
  image     = 1073741938,   -- ★ 裁剪功能必需
}

local ENABLE_LOOP = true
local LOOP_FPS    = 30

--=============================================================================
-- 加载 webui
--=============================================================================

local webui
do
  local ok, m = pcall(require, "webui")
  if ok and m then
    webui = m
  else
    printerr("[PANEL] require('webui') 失败")
    printerr("[PANEL]   ok = " .. tostring(ok))
    printerr("[PANEL]   m  = " .. tostring(m))

    local MODS = { "webui_util", "webui_dom", "webui_html", "webui_css",
                   "webui_color", "webui_style", "webui_transition",
                   "webui_layout", "webui_render", "webui_clip", "webui_event" }
    for _, name in ipairs(MODS) do
      local o2, m2 = pcall(require, name)
      printerr(string.format("[PANEL]   require('%-18s') -> %s  %s",
          name, tostring(o2), o2 and "OK" or tostring(m2)))
    end
    return
  end
end

print("[PANEL] webui " .. tostring(webui.VERSION))

local say = print
local dom = webui.dom          -- ★ 必须取出来；findById 要用它遍历

local function warn(...)
  local n = select('#', ...)
  local t = {}
  for i = 1, n do t[i] = tostring((select(i, ...))) end
  local m = "[PANEL][warn] " .. table.concat(t, " ")
  if type(printerr) == "function" then pcall(printerr, m) else print(m) end
end

--=============================================================================
-- 数据
--=============================================================================

local HERO = {
  name  = "夜兰",
  elem  = "水",
  weapon= "弓",
  level = 42,
  stars = 5,
  hp    = { cur = 18420, max = 24000 },
  atk   = { cur =  1280, max =  2000 },
  def   = { cur =   640, max =  1200 },
}

local ELEM_COLOR = {
  ["水"] = "#4a90d9", ["火"] = "#e05a3a", ["冰"] = "#5ab8e0",
  ["雷"] = "#a86ae0", ["风"] = "#5ad0a0", ["岩"] = "#d0a840",
}

-- 技能：用图片控件显示真实形状图
local SKILLS = {
  { name = "普通攻击", shape = 100006, tag = "圆环", color = "#8fb8e0" },
  { name = "元素战技", shape = 100003, tag = "三角", color = "#5ad0a0" },
  { name = "元素爆发", shape = 100002, tag = "圆形", color = "#e0a85a" },
}

-- 圣遗物：卡片用 overflow:hidden，顶部色带故意溢出
local RELICS = {
  { name = "生之花", set = "沉沦之心", lv = 20, color = "#7ac050" },
  { name = "死之羽", set = "沉沦之心", lv = 16, color = "#e05a3a" },
}

local state = {
  selSkill = 1,
}

--=============================================================================
-- 样式
--=============================================================================

local CSS = [[
<style>
  /* ---------- 整页 ---------- */
  #root {
    width: 1000px; height: 900px;
    background-color: #12141c;
    display: flex; flex-direction: column;
    padding: 10px;
    box-sizing: border-box;
  }

  /* ---------- 顶栏 ---------- */
  .topbar {
    display: flex; align-items: center;
    width: 100%; height: 52px;
    background-color: #1c2030;
    padding: 0 16px;
    box-sizing: border-box;
    margin-bottom: 12px;
  }
  .title  { color: #e8ecf5; font-size: 18px; height: 34px; width: 120px; }
  .grow   { flex-grow: 1; }
  .gold   { color: #f0c860; font-size: 16px; height: 31px; width: 130px; }
  .lv     { color: #9aa8c0; font-size: 15px; height: 29px; width: 80px; }

  /* ---------- 角色卡 ---------- */
  /* ★ 高度必须装得下内容（2026-10-07 修）

       内容核算：
         hero-name  38 + margin 0  =  38
         hero-sub   27 + margin 6  =  33
         stars      31 + margin 10 =  41
         stat ×3   (32 + 4) × 3    = 108
         ─────────────────────────────
         合计 220px

       .hero 高度需 >= 220 + padding(14×2) = 248
       之前写 210 -> 溢出 24px -> 最后一行 DEF 掉到卡片外，
       而卡片背景色不覆盖溢出区 -> 看起来"上下背景颜色不同"。

       ⚠️ 这类问题很隐蔽：元素没有 overflow:hidden 时，
          溢出内容仍可见，只是失去父容器的背景。 */
  .hero {
    display: flex; align-items: flex-start;
    width: 100%; height: 250px;
    background-color: #1c2030;
    padding: 14px;
    box-sizing: border-box;
    margin-bottom: 10px;
  }

  /* ★ 圆形裁剪：头像。必须是正方形，否则会裁成椭圆

       ⚠️ 裁剪容器【不要设 background-color】——
          它的底色会溢出到裁剪区之外（真机实测：圆外跑出暗色月牙）。
          底色应由内部的子元素承载。
          库已做防护（裁剪容器跳过 imageColor），但按最佳实践也不该设。 */
  .avatar {
    width: 130px; height: 130px;
    border-radius: 50%;
    margin-right: 20px;
  }
  /* 头像内容（承载颜色，被父裁成圆） */
  .avatar-inner {
    width: 130px; height: 130px;
    background-color: #4a6fa8;
  }

  /* ⚠️ 高度必须装得下子元素（共 220px），否则内容溢出到父卡片之外，
       表现为"溢出部分失去父容器背景色"。 */
  .hero-info { width: 780px; height: 222px; }

  .hero-name  { color: #ffffff; font-size: 20px; width: 200px; height: 38px; }
  .hero-sub   { color: #9aa8c0; font-size: 14px; width: 200px; height: 27px; margin-bottom: 6px; }
  .stars      { color: #f0c860; font-size: 16px; width: 160px; height: 31px; margin-bottom: 10px; }

  /* ---------- 属性条 ---------- */
  .stat      { display: flex; align-items: center; width: 100%; height: 32px; margin-bottom: 4px; }
  .stat-lbl  { width: 60px;  height: 27px; color: #c8d4e8; font-size: 14px; }
  .bar-bg    { width: 440px; height: 16px; background-color: #2a3050; margin-right: 14px; }
  .bar-fill  { height: 16px; }
  .stat-val  { width: 120px; height: 27px; color: #e8ecf5; font-size: 14px; }

  .hp   { background-color: #4ad07a; }
  .atk  { background-color: #e0a040; }
  .def  { background-color: #4a90d9; }

  /* ---------- 区块标题 ---------- */
  .sec {
    width: 100%; height: 27px;
    color: #8fa0c0; font-size: 14px;
    margin-bottom: 6px; width: 600px; }

  /* ---------- 技能（图片控件） ---------- */
  .skills { display: flex; width: 100%; height: 140px; margin-bottom: 10px; }

  .skill {
    width: 130px; height: 132px;
    display: flex; flex-direction: column; align-items: center;
    background-color: #1c2030;
    margin-right: 12px;
    padding-top: 8px;
    box-sizing: border-box;
  }
  .skill.on { background-color: #2a3555; }

  /* ★ 技能图标：图片控件，用 SetImage 换形状
     必须给它 background-color —— 否则 chooseKind 会选成 textbox，
     而 textbox 没有 SetImage，形状就设不上（试跑时踩过）。 */
  .skill-icon {
    width: 80px; height: 80px;
    background-color: #12141c;
    margin-bottom: 6px;
  }
  .skill-name { color: #c8d4e8; font-size: 13px; width: 120px; height: 25px; text-align: center; }

  /* ---------- 圣遗物（矩形裁剪） ---------- */
  .relics { display: flex; width: 100%; height: 168px; margin-bottom: 10px; }

  /* ★ 矩形裁剪：卡片内容故意溢出，看是否被切掉

       ⚠️ 裁剪容器【不设 background-color】—— 它的底色会溢出到裁剪区外
          （真机实测：圆外跑出暗色月牙）。

       ⚠️⚠️ 底色也不能用一个"与父等高"的兄弟层来画 ——
          那会把后续兄弟挤出父容器，被裁剪掉（实测：色带和文字全丢）。
          正确做法：底色画在【唯一的内层容器】上，其他内容放在它里面。 */
  .relic {
    width: 260px; height: 168px;
    overflow: hidden;
    margin-right: 16px;
  }
  /* 内层容器：铺满并承载底色，其余内容都放在它里面 */
  .relic-card {
    width: 260px; height: 168px;
    background-color: #1c2030;
  }
  /* 这个色带比卡片宽，故意溢出 —— 若裁剪生效，超出部分应被切掉 */
  .relic-band {
    width: 400px; height: 60px;
    background-color: #7ac050;
  }
  .relic-body { width: 240px; height: 100px; padding: 10px; }

  .relic-name { color: #ffffff; font-size: 15px; width: 200px; height: 29px; }
  .relic-set  { color: #9aa8c0; font-size: 13px; width: 200px; height: 25px; }
  .relic-lv   { color: #f0c860; font-size: 13px; width: 100px; height: 25px; }

  /* ---------- 字符 vs 图片 对照 ---------- */
  .deco { display: flex; align-items: center; width: 100%; height: 52px; }
  .deco-lbl { color: #8fa0c0; font-size: 14px; width: 120px; height: 27px; }
  .glyph { color: #e8ecf5; font-size: 20px; width: 70px; height: 38px; text-align: center; }
  .deco-img { width: 40px; height: 40px; margin-right: 14px; }
</style>
]]

--=============================================================================
-- 页面构建
--=============================================================================

local function pct(cur, max)
  if not max or max <= 0 then return 0 end
  local p = cur / max
  if p < 0 then p = 0 elseif p > 1 then p = 1 end
  return p
end

local function buildStats()
  local rows = {
    { lbl = "HP",  cur = HERO.hp.cur,  max = HERO.hp.max,  cls = "hp"  },
    { lbl = "ATK", cur = HERO.atk.cur, max = HERO.atk.max, cls = "atk" },
    { lbl = "DEF", cur = HERO.def.cur, max = HERO.def.max, cls = "def" },
  }
  local out = {}
  for _, r in ipairs(rows) do
    local p = pct(r.cur, r.max)
    -- 底条 460px，按比例算填充宽度
    local w = math.floor(460 * p)
    if w < 2 then w = 2 end
    out[#out+1] = string.format([[
      <div class="stat">
        <div class="stat-lbl">%s</div>
        <div class="bar-bg"><div class="bar-fill %s" style="width:%dpx"></div></div>
        <div class="stat-val">%s</div>
      </div>]], r.lbl, r.cls, w, tostring(r.cur))
  end
  return table.concat(out)
end

local function buildSkills()
  local out = {}
  for i, s in ipairs(SKILLS) do
    local on = (state.selSkill == i) and " on" or ""
    out[#out+1] = string.format([[
      <div class="skill%s" id="skill%d">
        <div class="skill-icon" id="icon%d" data-image="1"></div>
        <div class="skill-name">%s</div>
      </div>]], on, i, i, s.name)
  end
  return table.concat(out)
end

local function buildRelics()
  local out = {}
  for i, r in ipairs(RELICS) do
    out[#out+1] = string.format([[
      <div class="relic" id="relic%d">
        <div class="relic-card">
          <div class="relic-band" style="background-color:%s"></div>
          <div class="relic-body">
            <div class="relic-name">%s</div>
            <div class="relic-set">%s</div>
            <div class="relic-lv">+%d</div>
          </div>
        </div>
      </div>]], i, r.color, r.name, r.set, r.lv)
  end
  return table.concat(out)
end

local function buildDeco()
  -- 左边字符，右边图片，直观对照
  local out = {}
  out[#out+1] = [[<div class="deco">]]
  out[#out+1] = [[<div class="deco-lbl">字符方案</div>]]
  for _, g in ipairs({ "◆", "★", "○", "▲", "■" }) do
    out[#out+1] = string.format([[<div class="glyph">%s</div>]], g)
  end
  out[#out+1] = [[</div>]]

  out[#out+1] = [[<div class="deco">]]
  out[#out+1] = [[<div class="deco-lbl">图片方案</div>]]
  for i, id in ipairs({ 100004, 100005, 100002, 100003, 100001 }) do
    out[#out+1] = string.format(
      [[<div class="deco-img" id="deco%d" data-image="1"></div>]], i)
  end
  out[#out+1] = [[</div>]]
  return table.concat(out)
end

local function buildPage()
  local elemColor = ELEM_COLOR[HERO.elem] or "#ffffff"
  local stars = string.rep("★", HERO.stars) .. string.rep("☆", 5 - HERO.stars)

  return CSS .. string.format([[
<div id="root">

  <div class="topbar">
    <div class="title">角色面板</div>
    <div class="grow"></div>
    <div class="lv">Lv.%d</div>
    <div class="grow"></div>
    <div class="gold">12,480 金</div>
  </div>

  <div class="hero">
    <div class="avatar" id="avatar">
      <div class="avatar-inner"></div>
    </div>
    <div class="hero-info">
      <div class="hero-name">%s</div>
      <div class="hero-sub">%s元素 · %s</div>
      <div class="stars">%s</div>
      %s
    </div>
  </div>

  <div class="sec">技能</div>
  <div class="skills">%s</div>

  <div class="sec">圣遗物（卡片裁剪：色带溢出应被切掉）</div>
  <div class="relics">%s</div>

  <div class="sec">形状对照</div>
  %s

</div>]],
    HERO.level,
    HERO.name, HERO.elem, HERO.weapon, stars,
    buildStats(),
    buildSkills(),
    buildRelics(),
    buildDeco()
  )
end

--=============================================================================
-- 图片控件绑定
--
--   ★ 关键：DOM 里只写空 div，形状图要在渲染后用 SetImage 设置。
--     因为 webui 的 CSS 目前不解析 background-image，
--     图片控件的形状由应用层显式指定（封装的 clip.setImage）。
--=============================================================================

local clip

--[[ 按 id 在 DOM 里找元素。

     ★ dom.lua 没有 getElementById（已核查），
       所以用 D.walk 遍历，按 node.id 匹配。
]]--
local function findById(doc, id)
  local found = nil
  if not doc then return nil end
  if not dom or type(dom.walk) ~= "function" then
    warn("dom.walk 不可用，无法按 id 查找节点")
    return nil
  end

  -- ★ 不吞异常：遍历失败要报出来，否则会表现为"找不到节点"这种误导性症状
  local ok, err = pcall(function()
    dom.walk(doc, function(n)
      if not found and n:isElement() and n.id == id then found = n end
    end)
  end)
  if not ok then
    warn("遍历 DOM 失败: " .. tostring(err))
    return nil
  end
  return found
end

local function bindImages(ui)
  --[[ ★ 模块名要用【扁平写法】webui_clip，不是 webui.clip

       真机 require 规则只认 external_lua_file 里的扁平文件名。
       build_external.lua 会自动改写【库内部】的 require，
       但本文件是独立 demo，不经改写 —— 必须自己写对。

       实测教训：写 webui.clip 会得到
         "failed to load script 'webui_clip'" 之外的空返回，
         表现为「图片形状已设置 0 个」，图形全都不显示。
  ]]--
  if not clip then
    local ok, m = pcall(require, "webui_clip")
    if not ok then
      ok, m = pcall(require, "webui.clip")   -- 兼容本地环境
    end
    if ok then clip = m end
  end
  if not clip then
    warn("webui_clip 加载失败，图片形状无法设置")
    return 0
  end

  local count = 0

  local function setShape(nodeId, shapeId, color)
    local node = findById(ui.doc, nodeId)
    if not node then
      warn("找不到节点 #" .. nodeId)
      return false
    end
    local entry = ui.rendered and ui.rendered.live and ui.rendered.live[node]
    if not entry or not entry.control then
      warn("节点 #" .. nodeId .. " 还没有对应控件")
      return false
    end

    --[[ ★ 先确认控件类型正确。

         教训：这里若默默失败，表现只是"形状没出来"，很难定位。
         真机上 textbox 没有 SetImage —— 说明该元素没被选成 image 类型，
         通常是漏了 background-color 或 data-image="1"。
    ]]--
    if type(entry.control.SetImage) ~= "function" then
      warn(string.format(
          "节点 #%s 的控件是 %s 类型，没有 SetImage —— 请给它加 data-image=\"1\"",
          nodeId, tostring(entry.kind)))
      return false
    end

    local ok, err = clip.setImage(entry.control, shapeId)
    if not ok then
      warn("setImage(" .. nodeId .. ", " .. tostring(shapeId) .. ") 失败: "
           .. tostring(err))
      return false
    end
    if color and #color >= 7 then
      local r = tonumber(color:sub(2,3), 16) or 255
      local g = tonumber(color:sub(4,5), 16) or 255
      local b = tonumber(color:sub(6,7), 16) or 255
      clip.tint(entry.control, r, g, b, 255)
    end
    count = count + 1
    return true
  end

  -- 技能图标
  for i, s in ipairs(SKILLS) do
    setShape("icon" .. i, s.shape, s.color)
  end

  -- 对照区图片
  local decoShapes = { 100004, 100005, 100002, 100003, 100001 }
  local decoColors = { "#a86ae0", "#f0c860", "#4a90d9", "#5ad0a0", "#c8d4e8" }
  for i, id in ipairs(decoShapes) do
    setShape("deco" .. i, id, decoColors[i])
  end

  return count
end

--=============================================================================
-- 生命周期
--=============================================================================

local root
local ui
local loopSeq
local bound = false
local retryCount = 0
local frame = 0

local function startLoop()
  if not ENABLE_LOOP then return end
  if type(game.TweenSequence) ~= "function" then
    warn("game.TweenSequence 不可用，逐帧循环关闭")
    return
  end

  local function tick()
    frame = frame + 1
    if ui then
      local ok, err = pcall(function() ui:flush() end)
      if not ok then
        -- 只在首次报错，避免刷屏
        if frame < 5 then warn("flush 失败: " .. tostring(err)) end
      end
    end

    loopSeq = game.TweenSequence()
    loopSeq:AppendInterval(1 / LOOP_FPS)
    loopSeq:AppendCallback(tick)
    loopSeq:Play()
  end

  tick()
end

local function boot()
  root = game.FindClientUIRoot("Root")
  if not root then return false end

  ui = webui.new({
    root    = root,
    prefabs = PREFABS,
    handlers = {},
  })

  local ok, err = pcall(function()
    ui:render(buildPage())
  end)
  if not ok then
    printerr("[PANEL] 渲染失败: " .. tostring(err))
    return true   -- 已处理，不再重试
  end

  print(string.format("[PANEL] 渲染完成 DOM=%d",
      ui.doc and #(ui.doc.children or {}) or 0))

  -- 绑定图片形状
  local okBind, nImg = pcall(bindImages, ui)
  if not okBind then
    warn("图片绑定异常（不影响其他功能）: " .. tostring(nImg))
    nImg = 0
  else
    print(string.format("[PANEL] 图片形状已设置 %d 个（技能图标 3 + 对照 5 = 8）",
        nImg or 0))
  end
  bound = true

  -- 报告裁剪是否生效
  if ui.rendered and ui.rendered.live then
    local masked, total = 0, 0
    for _, e in pairs(ui.rendered.live) do
      total = total + 1
      if e.clipShape then masked = masked + 1 end
    end
    print(string.format("[PANEL] 控件 %d 个，其中启用裁剪 %d 个", total, masked))
    print(string.format("[PANEL]   头像(圆形裁剪) + 圣遗物卡片(矩形裁剪) 应为 3 个"))
  end

  --[[ ★ 诊断：报告关键文字元素的控件状态

       目的：定位"图形正常但文字不显示"。
         textbox 控件若 text 有值、尺寸正常、active=true，
         却仍不显示 -> 问题在引擎/层级，而不在数据传递。

       本段只打印必要信息，不修改任何状态。
  ]]--
  do
    local CHECK = {
      { "角色面板", "title" }, { "Lv.42", "lv" }, { "12,480 金", "gold" },
      { "夜兰", "hero-name" }, { "★★★★★", "stars" },
      { "HP数值", "stat-val" },
      { "技能名", "skill-name" }, { "卡片名", "relic-name" },
      { "字符方案", "deco-lbl" }, { "字符", "glyph" },
    }
    local dom2 = webui.dom
    local found = {}

    if dom2 and type(dom2.walk) == "function" and ui.doc then
      pcall(function()
        dom2.walk(ui.doc, function(n)
          if n:isElement() and n.attrs and n.attrs.class then
            for _, item in ipairs(CHECK) do
              local cls = item[2]
              -- class 可能多个，逐个比
              for c in n.attrs.class:gmatch("%S+") do
                if c == cls and not found[cls] then found[cls] = n end
              end
            end
          end
        end)
      end)
    end

    print("[PANEL] ---- 关键文字元素诊断 ----")
    for _, item in ipairs(CHECK) do
      local label, cls = item[1], item[2]
      local node = found[cls]
      if not node then
        print(string.format("[PANEL]   %-10s .%-11s 找不到元素", label, cls))
      else
        local e = ui.rendered.live[node]
        if not e then
          print(string.format("[PANEL]   %-10s .%-11s 无控件", label, cls))
        else
          local c = e.control
          local okT, txt = pcall(function() return c.text end)
          local okW, w = pcall(function() return c.sizeDeltaX end)
          local okH, h = pcall(function() return c.sizeDeltaY end)
          local okV, v = pcall(function() return c.visible end)
          local okA, a = pcall(function() return c.active end)
          local okX, px = pcall(function() return c.anchoredPositionX end)
          local okY, py = pcall(function() return c.anchoredPositionY end)
          print(string.format(
            "[PANEL]   %-10s .%-11s kind=%-8s size=%sx%s pos=(%s,%s) vis=%s act=%s text=%s",
            label, cls, tostring(e.kind),
            tostring(okW and w or "?"), tostring(okH and h or "?"),
            tostring(okX and px or "?"), tostring(okY and py or "?"),
            tostring(okV and v or "?"), tostring(okA and a or "?"),
            okT and (txt and ("'" .. tostring(txt) .. "'") or "nil") or "ERR"))
        end
      end
    end
    print("[PANEL] ------------------------------")
  end

  startLoop()
  return true
end

function OnInit()
  -- 无需参数
end

function OnStart()
  print("[PANEL] OnStart")
  if boot() then return end
  print("[PANEL] 未找到 Root，进入重试")
  script:EnableUpdate(true)
end

function OnUpdate(dt)
  if bound then return end
  if boot() then
    bound = true
    script:EnableUpdate(false)
    return
  end
  retryCount = retryCount + 1
  if retryCount >= 120 then
    printerr("[PANEL] 等待 Root 超时（120 帧）")
    script:EnableUpdate(false)
  end
end

function OnDestroy()
  if loopSeq then pcall(function() loopSeq:Kill(false) end) end
  print(string.format("[PANEL] 结束，共 %d 帧", frame))
end