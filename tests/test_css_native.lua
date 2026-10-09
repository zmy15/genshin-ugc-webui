-- 测试 CSS 对齐原生浏览器的行为
--
-- ★ 这个套件守住"像写原生 CSS 一样写"的那些关键语义：
--     视口单位 / calc() / auto margin 居中 / 外边距折叠 /
--     box-sizing / flex align-items
--
-- 每个断言都写明【原生 CSS 的期望值】，便于对照。
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

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-40s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-40s %s", name, detail or "")) end
end
local function near(a, b, eps) return math.abs((a or 0) - (b or 0)) <= (eps or 0.5) end

--[[ 布局一个片段并返回节点表。

     ★ 视口基准默认 1600x900（= 设计尺寸），vw/vh 按它换算。 ]]--
local function page(body, cssSrc, W, H)
  W, H = W or 1600, H or 900
  local doc = html.parse(body)
  local sheets = {}
  if cssSrc then sheets[1] = css.parse(cssSrc) end
  style.apply(doc, sheets)
  layout.compute(doc, W, H)
  return doc
end

--[[ 取第 n 个元素（先序） ]]--
local function nth(doc, n) return dom.elements(doc)[n] end

--=============================================================================
print("=== 1. 视口单位 vw / vh / vmin / vmax ===")
--=============================================================================

--[[ 原生：100vw = 视口宽，100vh = 视口高。
     本库的"视口" = 逻辑设计尺寸（1600x900），因为布局在设计坐标系里算。 ]]--
do
  local d = page('<div id="a">A</div><div id="b">B</div><div id="c">C</div><div id="d">D</div>', [[
    #a { width: 100vw; height: 20px; }
    #b { width: 50vw;  height: 20px; }
    #c { width: 100vh; height: 20px; }
    #d { width: 10vmin; height: 20px; }
  ]])
  check("100vw = 1600", near(nth(d,1).box.w, 1600), string.format("%.0f", nth(d,1).box.w))
  check("50vw = 800",   near(nth(d,2).box.w, 800),  string.format("%.0f", nth(d,2).box.w))
  check("100vh = 900",  near(nth(d,3).box.w, 900),  string.format("%.0f", nth(d,3).box.w))

  -- vmin = min(1600,900)/100*10 = 90
  check("10vmin = 90",  near(nth(d,4).box.w, 90),   string.format("%.0f", nth(d,4).box.w))

  -- vmax = max(1600,900)/100*10 = 160
  local d2 = page('<div id="e">E</div>', '#e { width: 10vmax; height: 20px; }')
  check("10vmax = 160", near(nth(d2,1).box.w, 160), string.format("%.0f", nth(d2,1).box.w))

  -- 高度方向的 vh
  local d3 = page('<div id="f">F</div>', '#f { width: 100px; height: 50vh; }')
  check("50vh 高度 = 450", near(nth(d3,1).box.h, 450), string.format("%.0f", nth(d3,1).box.h))

  -- vw 随设计尺寸变化
  local d4 = page('<div id="g">G</div>', '#g { width: 100vw; height: 20px; }', 800, 600)
  check("视口变 800 时 100vw = 800", near(nth(d4,1).box.w, 800),
        string.format("%.0f", nth(d4,1).box.w))
end

--=============================================================================
print()
print("=== 2. calc() 四则运算 ===")
--=============================================================================

do
  -- 纯 px
  local d = page('<div id="a">A</div>', '#a { width: calc(100px + 50px); height: 20px; }')
  check("calc(100px + 50px) = 150", near(nth(d,1).box.w, 150),
        string.format("%.0f", nth(d,1).box.w))

  -- 混合百分比与 px（原生最常见的用法）
  local d2 = page('<div id="w"><div id="b">B</div></div>', [[
    #w { width: 800px; }
    #b { width: calc(50% - 100px); height: 20px; }
  ]])
  check("calc(50% - 100px) = 300", near(nth(d2,2).box.w, 300),
        string.format("%.0f", nth(d2,2).box.w))

  -- 视口单位参与运算
  local d3 = page('<div id="c">C</div>', '#c { width: calc(100vw - 200px); height: 20px; }')
  check("calc(100vw - 200px) = 1400", near(nth(d3,1).box.w, 1400),
        string.format("%.0f", nth(d3,1).box.w))

  -- 括号 + 除法
  local d4 = page('<div id="e">E</div>', '#e { width: calc((100vw - 200px) / 2); height: 20px; }')
  check("calc((100vw - 200px) / 2) = 700", near(nth(d4,1).box.w, 700),
        string.format("%.0f", nth(d4,1).box.w))

  -- 乘法
  local d5 = page('<div id="f">F</div>', '#f { width: calc(100px * 3); height: 20px; }')
  check("calc(100px * 3) = 300", near(nth(d5,1).box.w, 300),
        string.format("%.0f", nth(d5,1).box.w))

  -- 多层括号
  local d6 = page('<div id="g">G</div>', '#g { width: calc((100px + 100px) * 2); height: 20px; }')
  check("calc((100px + 100px) * 2) = 400", near(nth(d6,1).box.w, 400),
        string.format("%.0f", nth(d6,1).box.w))

  -- 百分比单独出现在 calc 里
  local d7 = page('<div id="h"><div id="i">I</div></div>', [[
    #h { width: 400px; }
    #i { width: calc(25%); height: 20px; }
  ]])
  check("calc(25%) = 100（父宽 400）", near(nth(d7,2).box.w, 100),
        string.format("%.0f", nth(d7,2).box.w))
end

--=============================================================================
print()
print("=== 3. margin: auto 水平居中（原生最常用写法） ===")
--=============================================================================

do
  -- 两边 auto -> 居中：父 600，子 200 -> x = 200
  local d = page('<div id="w"><div id="b">B</div></div>', [[
    #w { width: 600px; height: 100px; }
    #b { width: 200px; height: 50px; margin: 0 auto; }
  ]])
  check("margin:0 auto 居中 x=200", near(nth(d,2).box.x, 200),
        string.format("%.0f", nth(d,2).box.x))

  -- 只 margin-left:auto -> 靠右：x = 600-200 = 400
  local d2 = page('<div id="w"><div id="b">B</div></div>', [[
    #w { width: 600px; height: 100px; }
    #b { width: 200px; height: 50px; margin-left: auto; }
  ]])
  check("margin-left:auto 靠右 x=400", near(nth(d2,2).box.x, 400),
        string.format("%.0f", nth(d2,2).box.x))

  -- 只 margin-right:auto -> 靠左：x = 0
  local d3 = page('<div id="w"><div id="b">B</div></div>', [[
    #w { width: 600px; height: 100px; }
    #b { width: 200px; height: 50px; margin-right: auto; }
  ]])
  check("margin-right:auto 靠左 x=0", near(nth(d3,2).box.x, 0),
        string.format("%.0f", nth(d3,2).box.x))

  -- 经典组合：max-width + margin auto（响应式卡片）
  local d4 = page('<div id="w"><div id="b">B</div></div>', [[
    #w { width: 800px; height: 100px; }
    #b { max-width: 300px; width: 100%; height: 50px; margin: 0 auto; }
  ]])
  check("max-width300 + auto 居中 x=250", near(nth(d4,2).box.x, 250),
        string.format("%.0f", nth(d4,2).box.x))

  -- 根级子节点也要支持
  local d5 = page('<div id="b">B</div>', '#b { width: 200px; height: 50px; margin: 0 auto; }')
  check("根级元素 auto 居中 x=700", near(nth(d5,1).box.x, 700),
        string.format("%.0f", nth(d5,1).box.x))
end

--=============================================================================
print()
print("=== 4. 外边距折叠（相邻兄弟取较大者） ===")
--=============================================================================

do
  -- mb=30, mt=10 -> 间距 max(30,10) = 30 -> 第二个 y = 20+30 = 50
  local d = page('<div id="w"><div id="a">A</div><div id="b">B</div></div>', [[
    #w { width: 800px; }
    #a { height: 20px; margin-bottom: 30px; }
    #b { height: 20px; margin-top: 10px; }
  ]])
  check("mb30 + mt10 -> 间距 30, y=50", near(nth(d,3).box.y, 50),
        string.format("%.0f", nth(d,3).box.y))

  -- 反过来 mt 更大：mb=10, mt=30 -> 间距 30
  local d2 = page('<div id="w"><div id="a">A</div><div id="b">B</div></div>', [[
    #w { width: 800px; }
    #a { height: 20px; margin-bottom: 10px; }
    #b { height: 20px; margin-top: 30px; }
  ]])
  check("mb10 + mt30 -> 间距 30, y=50", near(nth(d2,3).box.y, 50),
        string.format("%.0f", nth(d2,3).box.y))

  -- 绝不能是相加（40）
  check("间距不是相加（40）", not near(nth(d2,3).box.y, 60, 0.1),
        string.format("y=%.0f", nth(d2,3).box.y))

  -- 根级子节点同样折叠
  local d3 = page('<div id="a">A</div><div id="b">B</div>', [[
    #a { height: 20px; margin-bottom: 30px; }
    #b { height: 20px; margin-top: 10px; }
  ]])
  check("根级子节点也折叠 y=50", near(nth(d3,2).box.y, 50),
        string.format("%.0f", nth(d3,2).box.y))

  -- 父的 auto 高度要把最后一个 margin-bottom 算进去
  local d4 = page('<div id="w"><div id="a">A</div></div>',
    '#w { width: 800px; } #a { height: 20px; margin-top: 5px; margin-bottom: 15px; }')
  -- 内容高 = 5 + 20 + 15 = 40
  check("父高度含首尾 margin = 40", near(nth(d4,1).box.h, 40),
        string.format("%.0f", nth(d4,1).box.h))
end

--=============================================================================
print()
print("=== 5. box-sizing（严格对齐原生） ===")
--=============================================================================

do
  -- content-box（默认）：width 只算内容区，外框 = width + padding
  local d = page('<div id="a">A</div>', '#a { width: 200px; height: 60px; padding: 20px; }')
  check("content-box 外框 240x100", near(nth(d,1).box.w, 240) and near(nth(d,1).box.h, 100),
        string.format("%.0fx%.0f", nth(d,1).box.w, nth(d,1).box.h))
  check("content-box 内容区 200x60",
        near(nth(d,1).box.contentW, 200) and near(nth(d,1).box.contentH, 60),
        string.format("%.0fx%.0f", nth(d,1).box.contentW, nth(d,1).box.contentH))

  -- border-box：width 含 padding，外框就是 200
  local d2 = page('<div id="b">B</div>',
    '#b { width: 200px; height: 60px; padding: 20px; box-sizing: border-box; }')
  check("border-box 外框 200x60", near(nth(d2,1).box.w, 200) and near(nth(d2,1).box.h, 60),
        string.format("%.0fx%.0f", nth(d2,1).box.w, nth(d2,1).box.h))
  check("border-box 内容区 160x20",
        near(nth(d2,1).box.contentW, 160) and near(nth(d2,1).box.contentH, 20),
        string.format("%.0fx%.0f", nth(d2,1).box.contentW, nth(d2,1).box.contentH))

  -- ★ 两种模式必须【不同】（守住"不再静默失效"）
  check("两种 box-sizing 结果不同",
        not near(nth(d,1).box.w, nth(d2,1).box.w),
        string.format("content=%.0f border=%.0f", nth(d,1).box.w, nth(d2,1).box.w))

  -- 子元素内容区起点让开 padding
  local d3 = page('<div id="c"><div id="d">D</div></div>',
    '#c { width: 200px; padding: 20px; box-sizing: border-box; } #d { height: 10px; }')
  check("子元素起点让开 padding (20,20)",
        near(nth(d3,2).box.x, 20) and near(nth(d3,2).box.y, 20),
        string.format("%.0f,%.0f", nth(d3,2).box.x, nth(d3,2).box.y))
  check("center-box 子元素宽 = 内容区 160", near(nth(d3,2).box.w, 160),
        string.format("%.0f", nth(d3,2).box.w))
end

--=============================================================================
print()
print("=== 6. flex align-items（含默认 stretch） ===")
--=============================================================================

do
  -- ★ 默认就是 stretch：子项不写 height 时拉伸到容器高
  local d = page('<div id="a"><div id="b">B</div></div>',
    '#a { display: flex; width: 400px; height: 200px; } #b { width: 100px; }')
  check("默认 stretch：子高 = 200", near(nth(d,2).box.h, 200),
        string.format("%.0f", nth(d,2).box.h))

  -- stretch 不能覆盖显式 height
  local d2 = page('<div id="a"><div id="b">B</div></div>',
    '#a { display: flex; width: 400px; height: 200px; } #b { width: 100px; height: 30px; }')
  check("stretch 不覆盖显式 height=30", near(nth(d2,2).box.h, 30),
        string.format("%.0f", nth(d2,2).box.h))

  -- align-items: center -> 垂直居中 y = (200-20)/2 = 90
  local d3 = page('<div id="a"><div id="b">B</div></div>',
    '#a { display:flex; align-items:center; width:400px; height:200px; } #b { width:100px; height:20px; }')
  check("align-items:center y=90", near(nth(d3,2).box.y, 90),
        string.format("%.0f", nth(d3,2).box.y))

  -- align-items: flex-end -> y = 200-20 = 180
  local d4 = page('<div id="a"><div id="b">B</div></div>',
    '#a { display:flex; align-items:flex-end; width:400px; height:200px; } #b { width:100px; height:20px; }')
  check("align-items:flex-end y=180", near(nth(d4,2).box.y, 180),
        string.format("%.0f", nth(d4,2).box.y))

  -- align-self 覆盖父的 align-items
  local d5 = page('<div id="a"><div id="b">B</div><div id="c">C</div></div>', [[
    #a { display:flex; align-items:flex-start; width:400px; height:200px; }
    #b { width:100px; height:20px; }
    #c { width:100px; height:20px; align-self:center; }
  ]])
  check("align-self:center 覆盖父 flex-start",
        near(nth(d5,2).box.y, 0) and near(nth(d5,3).box.y, 90),
        string.format("b=%.0f c=%.0f", nth(d5,2).box.y, nth(d5,3).box.y))

  -- justify-content 仍然正常（回归）
  local d6 = page('<div id="a"><div id="b">B</div></div>',
    '#a { display:flex; justify-content:center; width:400px; height:50px; } #b { width:100px; height:20px; }')
  check("justify-content:center x=150", near(nth(d6,2).box.x, 150),
        string.format("%.0f", nth(d6,2).box.x))
end

--=============================================================================
print()
print("=== 7. 静态失效必须告警（不能静默当 0） ===")
--=============================================================================

do
  --[[ 捕获 util.warn 的输出，验证无法解析的值会产生告警。
       ★ 这是"静默失效"这一类最难查 bug 的防线。 ]]--
  local util = require('webui_util')
  local warned = {}
  local origWarn = util.warn
  util.warn = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts+1] = tostring((select(i, ...))) end
    warned[#warned + 1] = table.concat(parts, " ")
  end

  -- 未实现的单位（ch）必须告警
  local d = page('<div id="a">A</div>', '#a { width: 10ch; height: 20px; }')
  util.warn = origWarn

  local found = false
  for _, w in ipairs(warned) do
    if w:find("ch", 1, true) or w:find("无法解析", 1, true) then found = true end
  end
  check("未实现单位 ch 会告警", found,
        found and "" or ("warn 数=" .. #warned))
  check("无效值仍然不崩（当 0）", nth(d,1).box.w == 0,
        string.format("%.0f", nth(d,1).box.w))
end

--=============================================================================
print()
print("=== 8. transform 百分比基准（元素自身尺寸） ===")
--=============================================================================

--[[ 原生：translateX(50%) = 自身宽度的 50%。

     ⚠️ 这里踩过：样式计算阶段不知道盒子尺寸，
        只能按 0 处理 —— 于是 "50%" 被当成 50px。
        现在布局完成后用真实盒尺寸重算。 ]]--
do
  -- translateX(50%) 自身宽 200 -> tx = 100
  local d = page('<div id="a">A</div>',
    '#a { width: 200px; height: 100px; transform: translateX(50%); }')
  local t = nth(d,1).style._transform
  check("translateX(50%) 宽200 -> 100", near(t.tx, 100),
        string.format("%.1f", t.tx))

  -- translate(25%, 10%) 200x100 -> (50, 10)
  local d2 = page('<div id="b">B</div>',
    '#b { width: 200px; height: 100px; transform: translate(25%, 10%); }')
  local t2 = nth(d2,1).style._transform
  check("translate(25%,10%) 200x100 -> (50,10)",
        near(t2.tx, 50) and near(t2.ty, 10),
        string.format("%.1f,%.1f", t2.tx, t2.ty))

  -- 纯 px 不受影响（回归）
  local d3 = page('<div id="c">C</div>',
    '#c { width: 100px; height: 50px; transform: translateX(10px); }')
  local t3 = nth(d3,1).style._transform
  check("translateX(10px) -> 10（不受影响）", near(t3.tx, 10),
        string.format("%.1f", t3.tx))

  -- scale 不受百分比逻辑影响（回归）
  local d4 = page('<div id="e">E</div>',
    '#e { width: 100px; height: 50px; transform: scale(1.5); }')
  local t4 = nth(d4,1).style._transform
  check("scale(1.5) 仍为 1.5", near(t4.sx, 1.5),
        string.format("%.2f", t4.sx))
end

--=============================================================================
print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
os.exit(fail == 0 and 0 or 1)