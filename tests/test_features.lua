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
  if cond then pass = pass + 1; print(string.format("  [OK] %-26s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-26s %s", name, detail or "")) end
end

-- ★ 修正：build 应从 HTML 的 <style> 里自动提取 CSS
local function build(src)
  local doc = html.parse(src)
  local sheets = {}
  for _, s in ipairs(html.extractStyles(doc)) do
    if s and s ~= "" then sheets[#sheets+1] = css.parse(s) end
  end
  style.apply(doc, sheets)
  layout.compute(doc, 800, 600)
  return doc
end

--[[ 取所有 div 元素（排除 style 等）]]--
local function divs(doc)
  local out = {}
  for _, e in ipairs(dom.elements(doc)) do
    if e.tag == "div" then out[#out+1] = e end
  end
  return out
end

print("=== 1. transform 解析 ===")
local cases = {
  {"translate(10px, 20px)",  {tx=10, ty=20}},
  {"translateX(5px)",        {tx=5, ty=0}},
  {"translateY(-3px)",       {tx=0, ty=-3}},
  {"scale(2)",               {sx=2, sy=2}},
  {"scale(2, 3)",            {sx=2, sy=3}},
  {"scaleX(1.5)",            {sx=1.5, sy=1}},
  {"rotate(45deg)",          {rotZ=45}},
  {"rotate(90)",             {rotZ=90}},
  {"translate(1px,2px) scale(2) rotate(30deg)", {tx=1,ty=2,sx=2,sy=2,rotZ=30}},
}
for _, c in ipairs(cases) do
  local t = style.parseTransform(c[1], 100, 100, 14)
  local e = c[2]
  local ok = true
  for k, v in pairs(e) do
    if math.abs((t[k] or 0) - v) > 0.01 then ok = false end
  end
  check(c[1], ok, string.format("tx=%.0f ty=%.0f sx=%.1f sy=%.1f rot=%.0f",
      t.tx, t.ty, t.sx, t.sy, t.rotZ))
end

print()
print("=== 2. 不支持的 transform 应被记录 ===")
local t2 = style.parseTransform("rotateX(30deg) skew(10deg)", 100, 100, 14)
check("rotateX/skew 记录", #t2.unsupported == 2, table.concat(t2.unsupported, ","))

print()
print("=== 3. transform 应用到渲染字段 ===")
local doc = build([[
<style>
  .a { width:80px; height:40px; transform: translate(20px, 10px); }
  .b { width:80px; height:40px; transform: scale(2); }
  .c { width:80px; height:40px; transform: rotate(45deg); }
</style>
<div class="a"></div><div class="b"></div><div class="c"></div>
]])
local d3 = divs(doc)
check("translate 节点", d3[1] and d3[1].style._transform.tx == 20,
    d3[1] and ("tx=" .. d3[1].style._transform.tx) or "无节点")
check("scale 节点", d3[2] and d3[2].style._transform.sx == 2,
    d3[2] and ("sx=" .. d3[2].style._transform.sx) or "无节点")
check("rotate 节点", d3[3] and d3[3].style._transform.rotZ == 45,
    d3[3] and ("rot=" .. d3[3].style._transform.rotZ) or "无节点")

print()
print("=== 4. z-index 解析 ===")
local doc2 = build([[
<div style="z-index:5"></div>
<div style="z-index:auto"></div>
]])
local d2 = divs(doc2)
check("z-index:5", d2[1] and d2[1].style._zIndex == 5)
check("z-index:auto", d2[2] and d2[2].style._zIndex == nil)

print()
print("=== 5. :hover / :active 选择器 ===")
local sel = css.parseSelector(".btn:hover")
check(".btn:hover 解析", sel ~= nil and sel[1].comp.hover == true,
    sel and ("hover="..tostring(sel[1].comp.hover)) or "nil")
local sel2 = css.parseSelector(".btn:active")
check(".btn:active 解析", sel2 ~= nil and sel2[1].comp.active == true)
local sel3 = css.parseSelector(".btn:focus")
check(":focus 应被拒绝", sel3 == nil)

print()
print("=== 6. :hover 匹配依赖节点状态 ===")
local CSS3 = ".b { background-color: #111111; }\n.b:hover { background-color: #ff0000; }"
local doc3 = build("<style>" .. CSS3 .. "</style><div class=\"b\" id=\"x\"></div>")
local x = nil
for _, e in ipairs(dom.elements(doc3)) do if e.id == "x" then x = e end end
local c1 = require('webui_color')
check("未 hover 时", c1.toHex(x.style._bgColor) == "#111111ff",
    c1.toHex(x.style._bgColor))

x._hover = true
style.apply(doc3, { css.parse(CSS3) })
check("hover 后", c1.toHex(x.style._bgColor) == "#ff0000ff",
    c1.toHex(x.style._bgColor))

print()
print("=== 7. specificity 含伪类 ===")
local s1 = css.specificity(css.parseSelector(".a"))
local s2 = css.specificity(css.parseSelector(".a:hover"))
check(".a:hover 特指度更高", s2.b > s1.b,
    string.format(".a=(%d,%d,%d) .a:hover=(%d,%d,%d)", s1.a,s1.b,s1.c, s2.a,s2.b,s2.c))

print()
print("=== 8. flex-grow ===")
local doc4 = build([[
<style>
  .box { display:flex; width:500px; }
  .a { width:100px; height:20px; }
  .b { width:100px; height:20px; flex-grow:1; }
  .c { width:100px; height:20px; flex-grow:2; }
</style>
<div class="box">
  <div class="a"></div><div class="b"></div><div class="c"></div>
</div>
]])
local box = nil
for _, e in ipairs(dom.elements(doc4)) do if e:hasClass("box") then box = e end end
local kids = {}
for _, c in ipairs(box.children) do
  if c:isElement() then kids[#kids+1] = c end
end
-- 可用 500，基础 300，剩余 200
-- b grow=1, c grow=2 -> b=100+200/3=166.7, c=100+400/3=233.3
check("flex-grow 分配", math.abs(kids[2].box.w - 166.67) < 1 and math.abs(kids[3].box.w - 233.33) < 1,
    string.format("a=%.0f b=%.1f c=%.1f (期望 100/166.7/233.3)",
        kids[1].box.w, kids[2].box.w, kids[3].box.w))

print()
print("=== 9. flex-shrink ===")
local doc5 = build([[
<style>
  .box { display:flex; width:200px; }
  .a { width:150px; height:20px; }
  .b { width:150px; height:20px; }
</style>
<div class="box"><div class="a"></div><div class="b"></div></div>
]])
local box2 = nil
for _, e in ipairs(dom.elements(doc5)) do if e:hasClass("box") then box2 = e end end
local k2 = {}
for _, c in ipairs(box2.children) do if c:isElement() then k2[#k2+1]=c end end
-- 总 300，可用 200，需收缩 100，两者 shrink=1 权重相同 -> 各减 50 -> 100/100
check("flex-shrink 等分收缩",
    math.abs(k2[1].box.w - 100) < 1 and math.abs(k2[2].box.w - 100) < 1,
    string.format("a=%.0f b=%.0f (期望 100/100)", k2[1].box.w, k2[2].box.w))

print()
print("=== 10. flex-basis ===")
local doc6 = build([[
<style>
  .box { display:flex; width:400px; }
  .a { width:50px; flex-basis:200px; height:20px; }
</style>
<div class="box"><div class="a"></div></div>
]])
local box3 = nil
for _, e in ipairs(dom.elements(doc6)) do if e:hasClass("box") then box3 = e end end
local k3 = box3.children[1]
check("flex-basis 覆盖 width", math.abs(k3.box.w - 200) < 1,
    string.format("w=%.0f (期望 200，width 是 50)", k3.box.w))

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end
