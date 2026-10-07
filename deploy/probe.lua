--[[============================================================================
  probe.lua  ——  ★ 唯一探针（所有真机验证都写在这里）

  ══════════════════════════════════════════════════════════════════════════
  用法：改下面的 ACTIVE 变量，选一个测试模块，挂到客户端控件上跑。
        不再新增文件 —— 新验证就往对应模块里加，或新增一个 MODULES 条目。
  ══════════════════════════════════════════════════════════════════════════

  模块清单：

    "text"    文字渲染定位        —— 交错对照：字号 / 布局 / 控件数量
    "mask"    遮罩与裁剪          —— enableMask 形状 / SetImage / 矩形裁剪
    "glyph"   几何字符            —— 字符可用性 / 无缝方案
    "all"     依次跑上面全部      —— 注意会串在一起显示，仅用于快速排查

  ══════════════════════════════════════════════════════════════════════════
  历史结论索引（真机实测，详见 ugc_out/引擎能力与限制.md）
  ══════════════════════════════════════════════════════════════════════════

    R15  30 个几何字符全部渲染正常；■ 连排有 10px 缝（advance 1.59em）
         纯色块 bgColor 完全无缝（478px 单区间）
    R16  遮罩形状 = 图片 alpha，不限圆形
         SetImage(imageSource, imageId) 可运行时换图
         枚举真名 Enum.ImageSource.StaticReference（非文档写法）
         圆角 6 字段写入全部失败 -> border-radius 不可行
    R17  矩形图当遮罩 => overflow:hidden 可实现
         遮罩等比适配，圆形图在 2:1 父里仍是正圆
    R18  裁剪容器能装文字（11/11）
         图片控件自身无 text 字段，但子控件可以有

  ══════════════════════════════════════════════════════════════════════════
  硬性约束（真机实测，写探针时必须遵守）
  ══════════════════════════════════════════════════════════════════════════

    · 新控件 active 默认 false —— 不 SetActive(true) 则完全不可见
    · fontSize 必须整数（浮点写入失败）
    · 字段按类型封死：image 无 text/bgColor；container/button 无 bgColor
    · Enum 顶层 pairs() 为空（元表），但 Enum.Xxx 可直接索引
    · game.Tween 是 3 参数：Tween(obj, {field=val}, 时长)
    · 截图像素 = 画布单位 × 1.6（2560 屏 / 1600 画布）
    · 真机读 .gil，不是文件夹 —— 新增文件要在编辑器导入
=============================================================================]]

--=============================================================================
-- ★★ 选择要跑的模块（改这里）
--=============================================================================

local ACTIVE = "clip"

--=============================================================================
-- 通用配置
--=============================================================================

local PREFABS = {
  container = 1073741933,
  textbox   = 1073741934,
  button    = 1073741935,
  image     = 1073741938,
}

local ROOT_NAME = "Root"
local TAG = "[PROBE]"

local SHAPES = {
  SQUARE   = 100001,
  CIRCLE   = 100002,
  TRIANGLE = 100003,
  STAR4    = 100004,
  STAR5    = 100005,
  RING     = 100006,
}

--=============================================================================
-- 通用工具
--=============================================================================

local function log(fmt, ...) print(string.format(fmt, ...)) end

local function hr(title)
  log("------------------------------------------------------------")
  if title then log(title) end
  log("------------------------------------------------------------")
end

local function warn(...)
  local n = select('#', ...)
  local t = {}
  for i = 1, n do t[i] = tostring((select(i, ...))) end
  local m = TAG .. "[warn] " .. table.concat(t, " ")
  if type(printerr) == "function" then pcall(printerr, m) else print(m) end
end

local function safeCall(fn)
  local ok, v = pcall(fn)
  return ok and v or nil
end

--=============================================================================
-- 模块 1：文字渲染定位（交错对照）
--
--   目的：定位"部分文字不渲染"的真正原因。
--
--   设计：每行放 3 个控件，且行间有色带锚点：
--          #编号(20px)   小字号(14px)   大字号(30px)
--
--   判读：
--     每行 小有/大无      -> 字号阈值
--     前面的行有/后面无    -> 控件数量或顺序
--     每行两个都无        -> 整行不渲染
--     全部都有            -> 库正常
--=============================================================================

local M = {}

M.text = {}

M.text.CSS = [[
<style>
  #root {
    width: 1000px; height: 880px;
    background-color: #101218;
    display: flex; flex-direction: column;
    padding: 10px;
    box-sizing: border-box;
  }
  .row { display: flex; align-items: center; width: 100%; height: 76px; }
  .idx { color: #ffd050; font-size: 14px; width: 60px; height: 26px; }
  .sm  { color: #7ce0a0; font-size: 14px; width: 240px; height: 26px; }
  .lg  { color: #7cc0ff; font-size: 30px; width: 240px; height: 42px; }
  .sep { width: 500px; height: 3px; background-color: #3a4a6a; }

  /* ── 本轮新增：验证「框高 / 字号 >= 1.8」假设 ── */

  /* 同一字号 15px，框高不同 */
  .h22 { color: #ff9090; font-size: 15px; width: 220px; height: 22px; }  /* 比 1.47 -> 预期不显示 */
  .h28 { color: #90ff90; font-size: 15px; width: 220px; height: 28px; }  /* 比 1.87 -> 预期显示 */

  /* 同一框高 42，字号不同 */
  .s20 { color: #ffd090; font-size: 20px; width: 220px; height: 42px; }  /* 比 2.10 -> 显示? */
  .s30 { color: #9090ff; font-size: 30px; width: 220px; height: 42px; }  /* 比 1.40 -> 不显示 */
</style>
]]

function M.text.build()
  --[[ ★ 两组实验：

       第 1 组（行1~6）：字号不变(15px)，框高不同
          h22 = 15px/22高 (比 1.47)  预期不显示
          h28 = 15px/28高 (比 1.87)  预期显示

       第 2 组（行7~8）：框高不变(42px)，字号不同
          s20 = 20px/42高 (比 2.10)  预期显示
          s30 = 30px/42高 (比 1.40)  预期不显示

       若第1组 h28 显示、h22 不显示 -> 证实【框高决定】
       若第2组 s20 显示、s30 不显示 -> 证实【比值决定，而非字号绝对值】
  ]]--
  local out = { M.text.CSS, '<div id="root">\n' }

  out[#out + 1] = [[
  <div class="row" id="g1">
    <div class="idx">1a</div>
    <div class="h22">15px/22高 比值1.47</div>
    <div class="h28">15px/28高 比值1.87</div>
  </div>
  <div class="row" id="g2">
    <div class="idx">1b</div>
    <div class="h22">15px/22高 再来</div>
    <div class="h28">15px/28高 再来</div>
  </div>
  <div class="row" id="g3">
    <div class="idx">1c</div>
    <div class="h22">15px/22高 三次</div>
    <div class="h28">15px/28高 三次</div>
  </div>
  <div class="row" id="g4">
    <div class="idx">2a</div>
    <div class="s20">20px/42高 比值2.10</div>
    <div class="s30">30px/42高 比值1.40</div>
  </div>
  <div class="row" id="g5">
    <div class="idx">2b</div>
    <div class="s20">20px/42高 再来</div>
    <div class="s30">30px/42高 再来</div>
  </div>
  <div class="row" id="g6">
    <div class="idx">3a</div>
    <div class="sm">14px/26高 基准</div>
    <div class="lg">30px/42高 基准</div>
  </div>
]]
  out[#out + 1] = '</div>\n'
  return table.concat(out)
end

M.text.classes = { idx = true, sm = true, lg = true, sep = true,
                   h22 = true, h28 = true, s20 = true, s30 = true }

M.text.report = function(ui, items)
  hr("【文字定位】逐控件状态（画布坐标 + 框高比）")
  log(string.format("  %-5s %-6s %-24s %-6s %-20s %-8s %s",
      "行", "类型", "文字", "字号", "box(x,y,w,h)", "框高/字号", "kind"))
  for _, it in ipairs(items) do
    local ratio = "-"
    if it.fs and it.fs > 0 and it.bh and it.bh > 0 then
      ratio = string.format("%.2f", it.bh / it.fs)
    end
    log(string.format("  %-5s %-6s %-24s %-6s (%4.0f,%4.0f,%3.0f,%3.0f) %-8s %s",
        it.pid, it.cls,
        it.text and ("'" .. tostring(it.text) .. "'") or "nil",
        tostring(it.fs), it.bx, it.by, it.bw, it.bh,
        ratio, tostring(it.kind)))
  end
  log(string.format("  共 %d 个控件", #items))

  --[[ ★ 读 adaptiveFontSize / minimumFontSize
       这两个字段是「字号自适应」相关，怀疑是文字消失的原因。
       只读，不改 —— 先看引擎给的值是什么。
  ]]--
  hr("【字号自适应字段】")
  local seen = 0
  for _, e in pairs(ui.rendered.live) do
    local c = e.control
    local af = safeCall(function() return c.adaptiveFontSize end)
    local mf = safeCall(function() return c.minimumFontSize end)
    if af ~= nil or mf ~= nil then
      log(string.format("  adaptiveFontSize=%-6s minimumFontSize=%-6s  name=%s",
          tostring(af), tostring(mf),
          tostring(safeCall(function() return c.name end))))
      seen = seen + 1
      if seen >= 8 then break end
    end
  end
  if seen == 0 then
    log("  (文本控件上读不到这两个字段，或都为 nil)")
  end

  hr("【判读表】")
  log("  第1组 g1~g3：字号都是 15px，只是框高不同")
  log("      h22 = 15px/22高 (比值1.47)  <- 预期不显示")
  log("      h28 = 15px/28高 (比值1.87)  <- 预期显示")
  log("      ★ 若 h28 有、h22 无 -> 证实【框高决定显示】")
  log("")
  log("  第2组 g4~g5：框高都是 42px，只是字号不同")
  log("      s20 = 20px (比值2.10)  <- 预期显示")
  log("      s30 = 30px (比值1.40)  <- 预期不显示")
  log("      ★ 若 s20 有、s30 无 -> 证实【比值决定，非字号绝对值】")
  log("")
  log("  第3组 g6：基准对照 14px/26高 与 30px/42高")
  log("")
  log("  屏幕换算：截图y = 720 - 画布y × 1.6")
end

--=============================================================================
-- 模块 2：遮罩与裁剪
--
--   目的：验证 enableMask 形状、SetImage 换图、矩形裁剪。
--=============================================================================

M.mask = {}

M.mask.CSS = [[
<style>
  #root {
    width: 1000px; height: 880px;
    background-color: #101214;
    padding: 10px;
    box-sizing: border-box;
  }
  .box {
    width: 200px; height: 100px;
    background-color: #2a3a58;
    margin-bottom: 12px;
  }
  .rowc { display: flex; align-items: center; width: 100%; height: 60px; }
  .lbl { color: #ffffff; font-size: 15px; width: 120px; height: 26px; }
  .sq  { width: 160px; height: 160px; background-color: #4a3a6a; }
</style>
]]

function M.mask.build()
  -- 裁剪窗口：父 200x100，子 400x200 故意溢出
  return M.mask.CSS .. [[
<div id="root">

  <div class="rowc"><div class="lbl">裁剪窗口</div></div>
  <div class="box" id="clip1">
    <div style="width:400px;height:200px;background-color:#ffdd00"></div>
  </div>

  <div class="rowc"><div class="lbl">圆形裁剪</div></div>
  <div class="sq" id="round1"
       style="border-radius:50%">
    <div style="width:160px;height:160px;background-color:#5ad0a0"></div>
  </div>

  <div class="rowc"><div class="lbl">形状图</div></div>
  <div class="rowc">
    <div class="sq" id="shape1" data-image="1" style="width:80px;height:80px;margin-right:12px"></div>
    <div class="sq" id="shape2" data-image="1" style="width:80px;height:80px;margin-right:12px"></div>
    <div class="sq" id="shape3" data-image="1" style="width:80px;height:80px"></div>
  </div>

</div>
]]
end

M.mask.classes = { lbl = true, sq = true, box = true }

-- 渲染后绑定形状图
M.mask.after = function(ui)
  local clip = safeCall(function() return require('webui_clip') end)
             or safeCall(function() return require('webui_clip') end)
  if not clip then
    warn("webui_clip 加载失败，形状图无法设置")
    return
  end

  local dom = require('webui').dom
  local function byId(id)
    local f = nil
    pcall(function()
      dom.walk(ui.doc, function(n)
        if not f and n:isElement() and n.id == id then f = n end
      end)
    end)
    return f
  end

  local PLAN = {
    { "shape1", SHAPES.RING,     "#8fb8e0" },
    { "shape2", SHAPES.TRIANGLE, "#5ad0a0" },
    { "shape3", SHAPES.CIRCLE,   "#e0a85a" },
  }
  local n = 0
  for _, p in ipairs(PLAN) do
    local node = byId(p[1])
    local e = node and ui.rendered.live[node]
    if e then
      local ok, err = clip.setImage(e.control, p[2])
      if ok then
        n = n + 1
        if p[3] then
          local r = tonumber(p[3]:sub(2,3), 16)
          local g = tonumber(p[3]:sub(4,5), 16)
          local b = tonumber(p[3]:sub(6,7), 16)
          clip.tint(e.control, r, g, b, 255)
        end
      else
        warn("setImage(" .. p[1] .. ") 失败: " .. tostring(err))
      end
    end
  end
  log(TAG .. " 形状图已设置 " .. n .. " 个")
end

M.mask.report = function(ui, items)
  hr("【遮罩与裁剪】状态")
  local masked = 0
  if ui.rendered and ui.rendered.live then
    for _, e in pairs(ui.rendered.live) do
      if e.clipShape then masked = masked + 1 end
    end
  end
  log("  启用裁剪的控件: " .. masked)
  hr("【判读表】")
  log("  裁剪窗口：黄色子块应被【切成 200x100 矩形】（不是溢出 400x200）")
  log("  圆形裁剪：绿色子块应裁成【正圆】")
  log("  形状图：  应显示 圆环 / 三角 / 圆形，且带颜色")
end

--=============================================================================
-- 模块 3：几何字符
--
--   目的：字符可用性 + 无缝方案对照。
--=============================================================================

M.glyph = {}

M.glyph.CSS = [[
<style>
  #root {
    width: 1000px; height: 880px;
    background-color: #101214;
    padding: 10px;
    box-sizing: border-box;
  }
  .line { width: 100%; height: 44px; color: #ffffff; font-size: 26px; }
  .lbl  { width: 100%; height: 30px; color: #9aa8c0; font-size: 15px; }
  .solid { width: 460px; height: 20px; background-color: #ffffff; }
  .band  { width: 400px; height: 60px; background-color: #7ac050; }
  .card  { width: 260px; height: 60px; overflow: hidden; }
</style>
]]

function M.glyph.build()
  return M.glyph.CSS .. [[
<div id="root">

  <div class="lbl">几何字符（应全部显示为图形）</div>
  <div class="line">●○■□◆◇▲△▼▽★☆</div>
  <div class="line">✓✕→←↑↓│─┌┐└┘├┤┬┴┼</div>

  <div class="lbl">方块连排（有缝=比例字体）</div>
  <div class="line">■■■■■■■■</div>

  <div class="lbl">纯色块（应完全无缝）</div>
  <div class="solid"></div>

  <div class="lbl">矩形裁剪（绿条应被切成 260 宽）</div>
  <div class="card"><div class="band"></div></div>

</div>
]]
end

M.glyph.classes = { line = true, lbl = true, solid = true, band = true, card = true }

M.glyph.report = function(ui, items)
  hr("【几何字符】状态")
  hr("【判读表】")
  log("  1. 第一行 12 个字符应全部显示为图形（无豆腐块）")
  log("  2. 第二行 16 个框线/符号同理")
  log("  3. ■■■■■■■■ 若有缝 = 比例字体（已知有 10px 缝）")
  log("  4. 纯色块应为【一整条无缝】")
  log("  5. 绿条应被卡片切到 260 宽（矩形裁剪）")
end

--=============================================================================
-- 模块 4：裁剪容器诊断
--
--   目的：复现并定位真机上的两个异常
--     ① 头像被拉伸（声明 130x130，实测宽高比 1.55）
--     ② 矩形裁剪的色带溢出卡片边界
--
--   设计：结构完全照抄 demo_panel，并打印每个控件的
--         sizeDelta / anchoredPosition / enableMask / imageId
--=============================================================================

M.clip = {}

M.clip.CSS = [[
<style>
  #root {
    width: 1000px; height: 880px;
    background-color: #101214;
    display: flex; flex-direction: column;
    padding: 10px;
    box-sizing: border-box;
  }

  /* 头像：圆形裁剪（照抄 demo） */
  .av    { width: 130px; height: 130px; border-radius: 50%; margin-bottom: 16px; }
  .av-in { width: 130px; height: 130px; background-color: #4a6fa8; }

  /* 卡片：矩形裁剪 + 内层底色容器（照抄 demo 修复后） */
  .relic     { width: 260px; height: 168px; overflow: hidden; margin-bottom: 16px; }
  .relic-card{ width: 260px; height: 168px; background-color: #1c2030; }
  .relic-band{ width: 400px; height: 60px; background-color: #7ac050; }
  .relic-txt { width: 200px; height: 29px; color: #ffffff; font-size: 15px; }

  /* 对照组：矩形裁剪，但【不用内层容器】直接放溢出色带 */
  .plain     { width: 260px; height: 80px; overflow: hidden; margin-bottom: 16px; }
  .plain-band{ width: 400px; height: 60px; background-color: #e06040; }
</style>
]]

function M.clip.build()
  return M.clip.CSS .. [[
<div id="root">

  <div class="lbl">A 遮罩容器：不设 imageColor（当前库行为）</div>
  <div class="av" id="av1"><div class="av-in" id="avin1"></div></div>

  <div class="lbl">B 遮罩容器：imageColor 全透明</div>
  <div class="av" id="av2"><div class="av-in" id="avin2"></div></div>

  <div class="lbl">C 遮罩容器：imageColor 红色（测是否影响遮罩）</div>
  <div class="av" id="av3"><div class="av-in" id="avin3"></div></div>

  <div class="lbl">D 矩形裁剪 + 透明</div>
  <div class="relic" id="rl4">
    <div class="relic-card" id="rlc4">
      <div class="relic-band" id="rlb4"></div>
    </div>
  </div>

</div>
]]
end

M.clip.classes = { av = true, ["av-in"] = true, relic = true,
                   ["relic-card"] = true, ["relic-band"] = true,
                   ["relic-txt"] = true, plain = true, ["plain-band"] = true,
                   lbl = true }

--[[ ★ 关键实验：A/B/C 三组只差 imageColor 的设置

      目的：确定"裁剪容器的白边"是否来自遮罩图自身可见。

      A  不设 imageColor       -> 遮罩图（白色圆形）可能可见 -> 白边
      B  imageColor 全透明     -> 若白边消失且裁剪仍在 -> 这就是修法
      C  imageColor 红色       -> 若变红边 -> 证明 imageColor 影响显示但不影响遮罩

      D  矩形裁剪 + 透明       -> 验证矩形场景同样适用
]]--
M.clip.after = function(ui)
  local dom = require('webui').dom
  local function byId(id)
    local f = nil
    pcall(function()
      dom.walk(ui.doc, function(n)
        if not f and n:isElement() and n.id == id then f = n end
      end)
    end)
    return f
  end

  local function ctrl(id)
    local nd = byId(id)
    local e = nd and ui.rendered.live[nd]
    return e and e.control or nil
  end

  -- B: 全透明
  local c2 = ctrl("av2")
  if c2 then
    local ok = pcall(function()
      c2.imageColor = Color.FromRGBA(0, 0, 0, 0)
    end)
    log("[PROBE] B 组 imageColor = 全透明  " .. (ok and "OK" or "失败"))
  end

  -- C: 红色
  local c3 = ctrl("av3")
  if c3 then
    local ok = pcall(function()
      c3.imageColor = Color.FromRGBA(255, 0, 0, 255)
    end)
    log("[PROBE] C 组 imageColor = 红色    " .. (ok and "OK" or "失败"))
  end

  -- D: 矩形裁剪容器透明
  local c4 = ctrl("rl4")
  if c4 then
    pcall(function() c4.imageColor = Color.FromRGBA(0, 0, 0, 0) end)
    log("[PROBE] D 组 imageColor = 全透明  OK")
  end
end

M.clip.report = function(ui, items)
  hr("【裁剪容器诊断】逐控件真机状态")
  log(string.format("  %-10s %-9s %-16s %-16s %-9s %s",
      "id", "kind", "box(w,h)", "sizeDelta", "clip", "mask/imageId"))
  log(string.format("  %s", string.rep("-", 74)))

  local dom = require('webui').dom
  local rows = {}
  if dom and ui.doc then
    pcall(function()
      dom.walk(ui.doc, function(n)
        if not n:isElement() then return end
        local e = ui.rendered.live[n]
        if not e then return end
        local b = n.box
        local c = e.control
        rows[#rows + 1] = {
          id = n.id or (n.attrs and n.attrs.class) or "?",
          kind = e.kind,
          bw = b and b.w, bh = b and b.h,
          sw = safeCall(function() return c.sizeDeltaX end),
          sh = safeCall(function() return c.sizeDeltaY end),
          px = safeCall(function() return c.anchoredPositionX end),
          py = safeCall(function() return c.anchoredPositionY end),
          clip = e.clipShape,
          mask = safeCall(function() return c.enableMask end),
          iid = safeCall(function() return c.imageId end),
          ic = safeCall(function() return c.imageColor end),
        }
      end)
    end)
  end
  table.sort(rows, function(a, b) return tostring(a.id) < tostring(b.id) end)

  for _, r in ipairs(rows) do
    local ic = "-"
    if type(r.ic) == "table" then
      ic = string.format("a=%s", tostring(r.ic.a))
    end
    log(string.format("  %-10s %-9s %-16s %-16s %-9s mask=%-5s id=%-7s icol=%s",
        tostring(r.id), tostring(r.kind),
        r.bw and string.format("%.0fx%.0f", r.bw, r.bh) or "?",
        (r.sw and r.sh) and string.format("%.0fx%.0f", r.sw, r.sh) or "?",
        tostring(r.clip or "-"),
        tostring(r.mask), tostring(r.iid), ic))
  end
  log(string.format("  坐标: %s",
      (function()
        local t = {}
        for _, r in ipairs(rows) do
          t[#t+1] = string.format("%s=(%.0f,%.0f)", tostring(r.id),
              r.px or 0, r.py or 0)
        end
        return table.concat(t, " ")
      end)()))

  hr("【判读】")
  log("  av1   应为 130x130, clip=100002, mask=true")
  log("  avin1 应为 130x130")
  log("  rl1   应为 260x168, clip=100001, mask=true")
  log("  rlc1  应为 260x168")
  log("  rlb1  应为 400x60（宽 400 > 父 260，应被裁到 260）")
  log("  pl1   应为 260x80, clip=100001 —— 对照：无内层容器")
  log("")
  log("  ★ 屏幕换算：截图y = 720 - 画布y × 1.6，画布x × 1.6 = 截图x")
end

local function collect(ui, classSet)
  local dom = require('webui').dom
  local items = {}
  if not (dom and type(dom.walk) == "function" and ui.doc) then return items end

  pcall(function()
    dom.walk(ui.doc, function(n)
      if not n:isElement() then return end
      local cls = (n.attrs and n.attrs.class) or ""
      local hit = false
      for c in cls:gmatch("%S+") do
        if classSet[c] then hit = true break end
      end
      if not hit then return end

      local e = ui.rendered.live[n]
      if not e then return end
      local b = n.box
      local c = e.control
      items[#items + 1] = {
        cls = cls,
        pid = (n.parent and n.parent.id) or (n.parent and n.parent.tag) or "?",
        text = safeCall(function() return c.text end),
        fs = safeCall(function() return c.fontSize end),
        bx = b and b.x or -1, by = b and b.y or -1,
        bw = b and b.w or -1, bh = b and b.h or -1,
        kind = e.kind,
      }
    end)
  end)

  -- ★ pairs 顺序未定义 -> 显式排序，保证日志稳定
  table.sort(items, function(a, b)
    if a.pid ~= b.pid then return a.pid < b.pid end
    if a.cls ~= b.cls then return a.cls < b.cls end
    return (a.text or "") < (b.text or "")
  end)
  return items
end

--=============================================================================
-- 主流程
--=============================================================================

local MODULES = { text = M.text, mask = M.mask, glyph = M.glyph, clip = M.clip }

local root, ui, bound, retryCount = nil, nil, false, 0

local function runModule(name)
  local mod = MODULES[name]
  if not mod then
    warn("未知模块: " .. tostring(name))
    return false
  end

  log("")
  log("============================================================")
  log("  探针模块: " .. name)
  log("============================================================")

  local ok, err = pcall(function() ui:render(mod.build()) end)
  if not ok then
    warn("渲染失败: " .. tostring(err))
    return false
  end

  if mod.after then
    local ok2, err2 = pcall(mod.after, ui)
    if not ok2 then warn("after() 异常: " .. tostring(err2)) end
  end

  local items = collect(ui, mod.classes or {})
  if mod.report then pcall(mod.report, ui, items) end
  return true
end

local function boot()
  root = game.FindClientUIRoot(ROOT_NAME)
  if not root then return false end

  ui = require('webui').new({
    root = root,
    prefabs = PREFABS,
    handlers = {},
  })

  log("")
  log("============================================================")
  log("  probe.lua   模块 = " .. tostring(ACTIVE))
  log("  画布: " .. tostring(select(1, game.GetUICanvasSize()))
      .. " x " .. tostring(select(2, game.GetUICanvasSize())))
  log("============================================================")

  if ACTIVE == "all" then
    for _, name in ipairs({ "text", "mask", "glyph" }) do
      runModule(name)
    end
  else
    runModule(ACTIVE)
  end

  return true
end

function OnInit() end

function OnStart()
  log(TAG .. " OnStart")
  if boot() then bound = true; return end
  log(TAG .. " 未找到 " .. ROOT_NAME .. "，重试")
  script:EnableUpdate(true)
end

function OnUpdate(dt)
  if bound then return end
  if boot() then bound = true; script:EnableUpdate(false); return end
  retryCount = retryCount + 1
  if retryCount >= 120 then
    warn("等待 " .. ROOT_NAME .. " 超时")
    script:EnableUpdate(false)
  end
end

function OnDestroy() end
