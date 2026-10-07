-- 测试 color + style
-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path
local html  = require('webui.html')
local css   = require('webui.css')
local style = require('webui.style')
local color = require('webui.color')
local dom   = require('webui.dom')

print("=== 1. 颜色解析 ===")
local cases = {
  "#f00", "#ff0000", "#ff000080", "rgb(1,2,3)", "rgba(1,2,3,0.5)",
  "red", "transparent", "  #ABC  ", "rgb(100%,0%,0%)", "notacolor", "",
}
for _, s in ipairs(cases) do
  local c = color.parse(s)
  print(string.format("  %-18s -> %s", "["..s.."]", c and color.toHex(c) or "nil"))
end

print("\n=== 2. 长度解析 ===")
for _, s in ipairs{"14px", "50%", "auto", "2em", "10", "none"} do
  local l = style.parseLength(s)
  print(string.format("  %-8s -> n=%.1f unit=%s auto=%s none=%s",
      s, l.n, l.unit, tostring(l.auto), tostring(l.none)))
end

print("\n=== 3. 层叠：特指度决定胜出 ===")
local doc = html.parse([[
  <div id="a" class="b"><span id="t">X</span></div>
]])
local sheets = { css.parse([[
  div { color: red; font-size: 10px }
  .b { color: green }
  #a { color: blue }
  #a span { font-size: 20px }
  span { color: orange }
]]) }
style.apply(doc, sheets)

local els = dom.elements(doc)
for _, e in ipairs(els) do
  local s = e.style
  print(string.format("  <%s id=%s cls=%s> color=%s fontSize=%s",
      e.tag, tostring(e.id), table.concat(e.classList, ","),
      color.toHex(s._color), tostring(s._fontSize)))
end
print("  期望: div#a.b -> blue (id 胜出)")
print("        span#t  -> orange (span 规则胜出)")

print("\n=== 4. 继承 ===")
local doc2 = html.parse([[
  <div style="color: #123456; font-size: 20px">
    <span>继承的文本</span>
  </div>
]])
style.apply(doc2, {})
local els2 = dom.elements(doc2)
local span = els2[2]
print("  div  color =", color.toHex(els2[1].style._color),
      " fontSize =", els2[1].style._fontSize)
print("  span color =", color.toHex(span.style._color),
      " fontSize =", span.style._fontSize, " <- 应继承父的")

print("\n=== 5. 默认值 ===")
local doc3 = html.parse([[<div>x</div>]])
style.apply(doc3, {})
local d3 = dom.elements(doc3)[1]
print("  display =", d3.style.display)
print("  position =", d3.style.position)
print("  fontSize =", d3.style._fontSize)
print("  color =", color.toHex(d3.style._color))
print("  bgColor =", color.toHex(d3.style._bgColor), "(应为全透明)")
print("  opacity =", tostring(d3.style._opacity))

print("\n=== 6. 简写展开 ===")
local doc4 = html.parse([[<div style="margin: 1px 2px 3px 4px; padding: 5px">x</div>]])
style.apply(doc4, {})
local d4 = dom.elements(doc4)[1]
for _, k in ipairs{"margin-top","margin-right","margin-bottom","margin-left","padding-top"} do
  print(string.format("  %-16s = %s", k, tostring(d4.style[k])))
end

print("\n=== 7. !important ===")
local doc5 = html.parse([[<div id="a" class="b">x</div>]])
style.apply(doc5, { css.parse([[
  div { color: red }
  .b { color: green !important }
  #a { color: blue }
]]) })
print("  color =", color.toHex(dom.elements(doc5)[1].style._color), "(应为绿，important 胜出)")

print("\n=== 8. opacity 解析 ===")
for _, v in ipairs{"1", "0.5", "50%", "0", "abc"} do
  local d = html.parse('<div style="opacity:'..v..'">x</div>')
  style.apply(d, {})
  print(string.format("  opacity:%-5s -> %.2f", v, dom.elements(d)[1].style._opacity))
end