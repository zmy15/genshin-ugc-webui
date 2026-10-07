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
  if cond then pass=pass+1; print(string.format("  [OK] %-28s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-28s %s", name, detail or "")) end
end

local function build(src)
  local doc = html.parse(src)
  local sheets = {}
  for _, s in ipairs(html.extractStyles(doc)) do
    if s ~= "" then sheets[#sheets+1] = css.parse(s) end
  end
  style.apply(doc, sheets)
  layout.compute(doc, 800, 600)
  return doc
end

local function kids(box)
  local out = {}
  for _, c in ipairs(box.children) do if c:isElement() then out[#out+1] = c end end
  return out
end

local function findBox(doc)
  local b = nil
  for _, e in ipairs(dom.elements(doc)) do if e:hasClass("box") then b = e end end
  return b
end

print("=== 1. flex-wrap: nowrap（默认，不换行）===")
local d1 = build([[
<style>
  .box { display:flex; width:300px; }
  .i { width:120px; height:20px; }
</style>
<div class="box"><div class="i"></div><div class="i"></div><div class="i"></div></div>
]])
local b1 = findBox(d1)
local k1 = kids(b1)
-- 3×120=360 > 300，nowrap 会收缩到 100 各
check("同一行", math.abs(k1[1].box.y - k1[2].box.y) < 0.1,
    string.format("y1=%.0f y2=%.0f", k1[1].box.y, k1[2].box.y))
check("收缩到 100", math.abs(k1[1].box.w - 100) < 1,
    string.format("w=%.1f", k1[1].box.w))

print()
print("=== 2. flex-wrap: wrap（换行）===")
local d2 = build([[
<style>
  .box { display:flex; flex-wrap:wrap; width:300px; }
  .i { width:120px; height:20px; }
</style>
<div class="box"><div class="i"></div><div class="i"></div><div class="i"></div></div>
]])
local b2 = findBox(d2)
local k2 = kids(b2)
-- 120+120=240 <= 300，第三个换行
check("前两个同行", math.abs(k2[1].box.y - k2[2].box.y) < 0.1,
    string.format("y1=%.0f y2=%.0f", k2[1].box.y, k2[2].box.y))
check("第三个换行", k2[3].box.y > k2[1].box.y + 15,
    string.format("y3=%.0f (>y1=%.0f)", k2[3].box.y, k2[1].box.y))
check("宽度保持 120", math.abs(k2[1].box.w - 120) < 1,
    string.format("w=%.1f", k2[1].box.w))

print()
print("=== 3. wrap + gap ===")
local d3 = build([[
<style>
  .box { display:flex; flex-wrap:wrap; gap:20px; width:300px; }
  .i { width:120px; height:20px; }
</style>
<div class="box"><div class="i"></div><div class="i"></div><div class="i"></div></div>
]])
local b3 = findBox(d3)
local k3 = kids(b3)
-- 120 + 20 + 120 = 260 <= 300；再加 20+120=400 > 300 -> 换行
check("gap 生效，仍是两行", k3[3].box.y > k3[1].box.y + 15,
    string.format("y1=%.0f y3=%.0f", k3[1].box.y, k3[3].box.y))

print()
print("=== 4. wrap + flex-grow 每行独立 ===")
-- ⚠️ 用 110px 让每行只放 2 个（110+110=220 ≤ 300，加第三个 330 > 300）
local d4 = build([[
<style>
  .box { display:flex; flex-wrap:wrap; width:300px; }
  .a { width:110px; height:20px; flex-grow:1; }
  .b { width:110px; height:20px; }
</style>
<div class="box"><div class="a"></div><div class="b"></div></div>
]])
local b4 = findBox(d4)
local k4 = kids(b4)
-- 第一行：a(110) + b(110) = 220，剩 80 给 a -> a=190
check("第一行 a 撑开", math.abs(k4[1].box.w - 190) < 1,
    string.format("a=%.1f (期望 190)", k4[1].box.w))
check("第一行 b 不变", math.abs(k4[2].box.w - 110) < 1,
    string.format("b=%.1f", k4[2].box.w))

print()
print("=== 4b. 恰好填满不换行（CSS 规范）===")
local d4b = build([[
<style>
  .box { display:flex; flex-wrap:wrap; width:300px; }
  .i { width:100px; height:20px; }
</style>
<div class="box"><div class="i"></div><div class="i"></div><div class="i"></div></div>
]])
local b4b = findBox(d4b)
local k4b = kids(b4b)
check("100×3 == 300 不换行", math.abs(k4b[3].box.y - k4b[1].box.y) < 0.1,
    string.format("y1=%.0f y3=%.0f", k4b[1].box.y, k4b[3].box.y))

print()
print("=== 5. 容器高度应包含所有行 ===")
local d5 = build([[
<style>
  .box { display:flex; flex-wrap:wrap; width:300px; }
  .i { width:120px; height:40px; }
</style>
<div class="box"><div class="i"></div><div class="i"></div><div class="i"></div></div>
]])
local b5 = findBox(d5)
-- 两行 × 40 = 80
check("容器高 = 80", math.abs(b5.box.h - 80) < 1,
    string.format("h=%.1f (期望 80)", b5.box.h))

print()
print("=== 6. align-items: center 逐行居中 ===")
local d6 = build([[
<style>
  .box { display:flex; flex-wrap:wrap; align-items:center; width:300px; }
  .i { width:120px; height:30px; }
  .t { width:120px; height:10px; }
</style>
<div class="box"><div class="t"></div><div class="i"></div></div>
]])
local b6 = findBox(d6)
local k6 = kids(b6)
check("矮项垂直居中", math.abs((k6[1].box.y - b6.box.contentY) - 10) < 1,
    string.format("偏移=%.1f (期望 10)", k6[1].box.y - b6.box.contentY))

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end
