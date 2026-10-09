-- 测试 CSS Grid 布局
--
-- ★ 每个断言都写明【原生 CSS 的期望值】。
--   算法在 lib/webui/webui_grid.lua（纯计算），本套件验的是端到端结果。
--
-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
             .. _root .. "/tools/?.lua;" .. package.path

local html   = require('webui_html')
local css    = require('webui_css')
local style  = require('webui_style')
local layout = require('webui_layout')
local dom    = require('webui_dom')
local G      = require('webui_grid')

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-42s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-42s %s", name, detail or "")) end
end
local function near(a, b, eps) return math.abs((a or 0) - (b or 0)) <= (eps or 0.5) end

local function page(body, cssSrc, W, H)
  local doc = html.parse(body)
  style.apply(doc, { css.parse(cssSrc) })
  layout.compute(doc, W or 1600, H or 900)
  return doc
end
local function nth(doc, n) return dom.elements(doc)[n] end

--=============================================================================
print("=== 1. 轨道模板解析（纯函数） ===")
--=============================================================================

do
  local t = G.parseTracks("1fr 1fr 1fr", 600)
  check("1fr 1fr 1fr -> 3 条 fr", #t == 3 and t[1].kind == "fr" and t[3].value == 1,
        string.format("n=%d kind=%s", #t, t[1] and t[1].kind or "?"))

  t = G.parseTracks("100px 1fr", 600)
  check("混合 px + fr", #t == 2 and t[1].kind == "px" and t[1].value == 100
        and t[2].kind == "fr", "")

  t = G.parseTracks("repeat(4, 1fr)", 600)
  check("repeat(4, 1fr) -> 4 条", #t == 4, string.format("n=%d", #t))

  t = G.parseTracks("repeat(2, 100px 1fr)", 600)
  check("repeat(2, 100px 1fr) -> 4 条", #t == 4 and t[1].kind == "px" and t[2].kind == "fr",
        string.format("n=%d", #t))

  t = G.parseTracks("25% auto", 600)
  check("百分比 + auto", #t == 2 and t[1].kind == "%" and t[2].kind == "auto", "")

  t = G.parseTracks("none", 600)
  check("none -> nil", t == nil, "")

  t = G.parseTracks("", 600)
  check("空串 -> nil", t == nil, "")

  -- ★ 上限保护：超大 repeat 不能把内存撑爆
  t = G.parseTracks("repeat(99999, 1fr)", 600)
  check("超大 repeat 有上限保护", t ~= nil and #t <= 200, string.format("n=%d", t and #t or -1))
end

--=============================================================================
print()
print("=== 2. grid-column / grid-row 定位解析 ===")
--=============================================================================

do
  local p = G.parseLine("2")
  check('"2" -> start=2 占1格', p.start == 2 and p.span == 1, "")

  p = G.parseLine("2 / 4")
  check('"2 / 4" -> start=2 end=4', p.start == 2 and p.endLine == 4, "")

  p = G.parseLine("span 2")
  check('"span 2" -> span=2', p.span == 2 and p.start == nil, "")

  p = G.parseLine("1 / span 2")
  check('"1 / span 2" -> start=1 span=2', p.start == 1 and p.span == 2, "")

  p = G.parseLine("auto")
  check('"auto" -> nil', p == nil, "")

  p = G.parseLine("")
  check("空串 -> nil", p == nil, "")
end

--=============================================================================
print()
print("=== 3. 自动排列 ===")
--=============================================================================

do
  -- 3 列，5 项 -> 前 3 个占满第一行，后 2 个占第二行
  local d = page([[
    <div id="g">
      <div id="a">a</div><div id="b">b</div><div id="c">c</div>
      <div id="e">e</div><div id="f">f</div>
    </div>]],
    '#g{display:grid;grid-template-columns:repeat(3,1fr);width:600px}#g>div{height:20px}')
  check("3 列自动换行：第1项 x=0,y=0", near(nth(d,2).box.x,0) and near(nth(d,2).box.y,0),
        string.format("%.0f,%.0f", nth(d,2).box.x, nth(d,2).box.y))
  check("第3项在 x=400", near(nth(d,4).box.x, 400), string.format("%.0f", nth(d,4).box.x))
  check("第4项换行 y=20", near(nth(d,5).box.y, 20), string.format("%.0f", nth(d,5).box.y))
  check("第4项回到 x=0", near(nth(d,5).box.x, 0), string.format("%.0f", nth(d,5).box.x))
  check("容器高 = 2 行 = 40", near(nth(d,1).box.h, 40), string.format("%.0f", nth(d,1).box.h))
end

--=============================================================================
print()
print("=== 4. fr 分配与 gap ===")
--=============================================================================

do
  -- 620 宽，3 列，gap 10 -> 每列 (620-20)/3 = 200
  local d = page('<div id="g"><div>a</div><div>b</div><div>c</div></div>',
    '#g{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;width:620px}#g>div{height:40px}')
  check("3 列各 200 宽", near(nth(d,2).box.w, 200) and near(nth(d,3).box.w, 200)
        and near(nth(d,4).box.w, 200),
        string.format("%.0f/%.0f/%.0f", nth(d,2).box.w, nth(d,3).box.w, nth(d,4).box.w))
  check("列间距 10（第2列 x=210）", near(nth(d,3).box.x, 210),
        string.format("%.0f", nth(d,3).box.x))
  check("第3列 x=420", near(nth(d,4).box.x, 420), string.format("%.0f", nth(d,4).box.x))

  -- 2fr 1fr -> 400 / 200（600 宽）
  local d2 = page('<div id="g"><div>a</div><div>b</div></div>',
    '#g{display:grid;grid-template-columns:2fr 1fr;width:600px}#g>div{height:20px}')
  check("2fr/1fr -> 400/200", near(nth(d2,2).box.w, 400) and near(nth(d2,3).box.w, 200),
        string.format("%.0f/%.0f", nth(d2,2).box.w, nth(d2,3).box.w))
end

--=============================================================================
print()
print("=== 5. 固定轨道与 auto 轨道 ===")
--=============================================================================

do
  -- 100px + 1fr（500 宽）-> 100 / 400
  local d = page('<div id="g"><div>a</div><div>b</div></div>',
    '#g{display:grid;grid-template-columns:100px 1fr;width:500px}#g>div{height:30px}')
  check("100px + 1fr -> 100/400",
        near(nth(d,2).box.w, 100) and near(nth(d,3).box.w, 400),
        string.format("%.0f/%.0f", nth(d,2).box.w, nth(d,3).box.w))

  -- auto 轨道按内容撑开
  local d2 = page('<div id="g"><div id="w">abc</div><div id="b">b</div></div>',
    '#g{display:grid;grid-template-columns:auto 1fr;width:600px}#g>div{height:20px}')
  local autoW = nth(d2,2).box.w
  check("auto 轨道按内容撑开（>0 且 <600）", autoW > 0 and autoW < 600,
        string.format("%.0f", autoW))
  check("1fr 吃掉剩余", near(nth(d2,3).box.w, 600 - autoW),
        string.format("%.0f (期望 %.0f)", nth(d2,3).box.w, 600 - autoW))
end

--=============================================================================
print()
print("=== 6. span 跨轨道 ===")
--=============================================================================

do
  -- span 2 跨满两列（400 宽）
  local d = page('<div id="g"><div id="a">a</div><div id="b">b</div><div id="c">c</div></div>',
    '#g{display:grid;grid-template-columns:1fr 1fr;width:400px}'
    .. '#a{grid-column:span 2;height:20px}#b,#c{height:20px}')
  check("span 2 宽 = 400（跨两列）", near(nth(d,2).box.w, 400),
        string.format("%.0f", nth(d,2).box.w))
  check("span 后下一项另起一行 y=20", near(nth(d,3).box.y, 20),
        string.format("%.0f", nth(d,3).box.y))

  -- 显式 2/4：从第 2 条线到第 4 条线 = 第 2、3 列
  --   610 宽 / 3 列 / gap 10 -> 每列 196.67；第2列起 x=206.67，跨 2 列 = 403.33
  local d2 = page('<div id="g"><div id="a">a</div></div>',
    '#g{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;width:610px}'
    .. '#a{grid-column:2 / 4;height:30px}')
  check("2/4 -> x=206.7 宽=403.3",
        near(nth(d2,2).box.x, 206.67, 1) and near(nth(d2,2).box.w, 403.33, 1),
        string.format("%.1f/%.1f", nth(d2,2).box.x, nth(d2,2).box.w))
end

--=============================================================================
print()
print("=== 7. grid-template-rows ===")
--=============================================================================

do
  local d = page('<div id="g"><div id="a">a</div><div id="b">b</div></div>',
    '#g{display:grid;grid-template-columns:1fr;grid-template-rows:60px 40px;width:300px}')
  check("第1行高 60", near(nth(d,2).box.h, 60), string.format("%.0f", nth(d,2).box.h))
  check("第2行 y=60 高 40",
        near(nth(d,3).box.y, 60) and near(nth(d,3).box.h, 40),
        string.format("y=%.0f h=%.0f", nth(d,3).box.y, nth(d,3).box.h))
  check("容器高 = 100", near(nth(d,1).box.h, 100), string.format("%.0f", nth(d,1).box.h))
end

--=============================================================================
print()
print("=== 8. row-gap / column-gap 独立设置 ===")
--=============================================================================

do
  local d = page('<div id="g"><div>a</div><div>b</div><div>c</div><div>e</div></div>',
    '#g{display:grid;grid-template-columns:1fr 1fr;'
    .. 'row-gap:20px;column-gap:10px;width:410px}#g>div{height:30px}')
  -- (410-10)/2 = 200
  check("column-gap 10 -> 列宽 200", near(nth(d,2).box.w, 200),
        string.format("%.0f", nth(d,2).box.w))
  check("第2列 x=210", near(nth(d,3).box.x, 210), string.format("%.0f", nth(d,3).box.x))
  check("row-gap 20 -> 第二行 y=50", near(nth(d,5).box.y, 50),
        string.format("%.0f", nth(d,5).box.y))

  -- gap 简写两值：gap: 20px 10px -> row 20 / column 10
  --   3 项 2 列 -> 第3项在第 2 行（y = 30 + 20 = 50）
  local d2 = page('<div id="g"><div>a</div><div>b</div><div>c</div></div>',
    '#g{display:grid;grid-template-columns:1fr 1fr;gap:20px 10px;width:410px}#g>div{height:30px}')
  check("gap 两值 (row20/col10)",
        near(nth(d2,4).box.y, 50) and near(nth(d2,2).box.w, 200),
        string.format("y=%.0f w=%.0f", nth(d2,4).box.y, nth(d2,2).box.w))
end

--=============================================================================
print()
print("=== 9. 轨道内对齐（justify-self / align-self） ===")
--=============================================================================

do
  -- stretch 默认：项撑满格子
  local d = page('<div id="g"><div id="a">a</div></div>',
    '#g{display:grid;grid-template-columns:1fr;grid-template-rows:100px;width:200px}'
    .. '#a{background-color:#000}')
  check("默认 stretch：项高 = 100", near(nth(d,2).box.h, 100),
        string.format("%.0f", nth(d,2).box.h))

  -- 显式 height 时不被拉伸
  local d2 = page('<div id="g"><div id="a">a</div></div>',
    '#g{display:grid;grid-template-columns:1fr;grid-template-rows:100px;width:200px}'
    .. '#a{height:30px;background-color:#000}')
  check("显式 height 不被 stretch 覆盖", near(nth(d2,2).box.h, 30),
        string.format("%.0f", nth(d2,2).box.h))

  -- align-self:center
  local d3 = page('<div id="g"><div id="a">a</div></div>',
    '#g{display:grid;grid-template-columns:1fr;grid-template-rows:100px;width:200px}'
    .. '#a{height:20px;align-self:center;background-color:#000}')
  check("align-self:center -> y=40", near(nth(d3,2).box.y, 40),
        string.format("%.0f", nth(d3,2).box.y))

  -- justify-self:center（宽度 100 在 200 轨道里）
  local d4 = page('<div id="g"><div id="a">a</div></div>',
    '#g{display:grid;grid-template-columns:1fr;width:200px}'
    .. '#a{width:100px;height:20px;justify-self:center;background-color:#000}')
  check("justify-self:center -> x=50", near(nth(d4,2).box.x, 50),
        string.format("%.0f", nth(d4,2).box.x))
end

--=============================================================================
print()
print("=== 10. 回归：grid 不能破坏 flex / block ===")
--=============================================================================

do
  -- grid 容器里的块级子项不应互相影响
  local d = page('<div id="g"><div id="a">a</div></div><div id="z">z</div>',
    '#g{display:grid;grid-template-columns:1fr;width:300px;height:50px}#z{height:30px}')
  check("grid 高度不撑到兄弟元素", near(nth(d,3).box.y, 50),
        string.format("%.0f", nth(d,3).box.y))

  -- 没有 grid-template-columns 时退化成单列（不崩）
  local d2 = page('<div id="g"><div>a</div><div>b</div></div>',
    '#g{display:grid;width:300px}#g>div{height:20px}')
  check("无模板时退化成单列", near(nth(d2,2).box.w, 300) and near(nth(d2,3).box.y, 20),
        string.format("w=%.0f y=%.0f", nth(d2,2).box.w, nth(d2,3).box.y))

  -- absolute 子项不参与网格排列
  --   grid 有 2 列，只有 #a 参与排列 -> 它只占第 1 列（200 宽），
  --   #p 是 absolute，不占格子也不影响排列
  local d3 = page('<div id="g"><div id="a">a</div><div id="p">p</div></div>',
    '#g{display:grid;grid-template-columns:1fr 1fr;width:400px}'
    .. '#a{height:20px}#p{position:absolute;left:0;top:0;width:10px;height:10px}')
  check("absolute 子项不占格子（a 只占第1列）", near(nth(d3,2).box.w, 200),
        string.format("a.w=%.0f", nth(d3,2).box.w))
  check("absolute 子项按自身尺寸定位",
        near(nth(d3,3).box.w, 10) and near(nth(d3,3).box.x, 0),
        string.format("x=%.0f w=%.0f", nth(d3,3).box.x, nth(d3,3).box.w))
end

--=============================================================================
print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
os.exit(fail == 0 and 0 or 1)