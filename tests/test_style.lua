-- 测试 color + style
-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path
local html  = require('webui_html')
local css   = require('webui_css')
local style = require('webui_style')
local color = require('webui_color')
local dom   = require('webui_dom')

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-28s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-28s %s", name, detail or "")) end
end

print("=== 1. 颜色解析 ===")
-- {输入, 期望的 toHex 结果（false = 期望解析失败返回 nil）}
local cases = {
  {"#f00",           "#ff0000ff"},
  {"#ff0000",        "#ff0000ff"},
  {"#ff000080",      "#ff000080"},
  {"rgb(1,2,3)",     "#010203ff"},
  {"rgba(1,2,3,0.5)", "#01020380"},
  {"red",            "#ff0000ff"},
  {"transparent",    "#00000000"},
  {"  #ABC  ",       "#aabbccff"},
  {"rgb(100%,0%,0%)", "#ff0000ff"},
  {"notacolor",      false},
  {"",               false},
}
for _, c in ipairs(cases) do
  local s, want = c[1], c[2]
  local got = color.parse(s)
  local hex = got and color.toHex(got) or nil
  print(string.format("  %-18s -> %s", "["..s.."]", hex or "nil"))
  if want == false then
    check("非法色应失败 ["..s.."]", got == nil)
  else
    check("颜色 ["..s.."]", hex == want, "-> " .. tostring(hex))
  end
end

print("\n=== 2. 长度解析 ===")
-- {输入, n, unit, auto, none}
local lenCases = {
  {"14px", 14, "px", nil, nil},
  {"50%",  50, "%",  nil, nil},
  {"auto",  0, "px", true, nil},
  {"2em",   2, "em", nil, nil},
  {"10",   10, "px", nil, nil},
  {"none",  0, "px", nil, true},
}
for _, c in ipairs(lenCases) do
  local l = style.parseLength(c[1])
  print(string.format("  %-8s -> n=%.1f unit=%s auto=%s none=%s",
      c[1], l.n, l.unit, tostring(l.auto), tostring(l.none)))
  check("长度 " .. c[1],
      math.abs(l.n - c[2]) < 0.001 and l.unit == c[3]
      and (l.auto and true or nil) == (c[4] and true or nil)
      and (l.none and true or nil) == (c[5] and true or nil))
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
check("id 特指度胜出 -> blue",
    color.toHex(els[1].style._color) == "#0000ffff",
    color.toHex(els[1].style._color))
check("span 自身规则胜出 -> orange",
    color.toHex(els[2].style._color) == "#ffa500ff",
    color.toHex(els[2].style._color))
check("div fontSize = 10", els[1].style._fontSize == 10, tostring(els[1].style._fontSize))
check("span fontSize = 20 (#a span 胜出)",
    els[2].style._fontSize == 20, tostring(els[2].style._fontSize))

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
check("span 继承 color", color.toHex(span.style._color) == "#123456ff")
check("span 继承 fontSize", span.style._fontSize == 20, tostring(span.style._fontSize))

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
check("display 默认 block", d3.style.display == "block", tostring(d3.style.display))
check("position 默认 static", d3.style.position == "static", tostring(d3.style.position))
check("fontSize 默认 14", d3.style._fontSize == 14, tostring(d3.style._fontSize))
check("color 默认黑", color.toHex(d3.style._color) == "#000000ff")
check("bgColor 默认全透明", color.toHex(d3.style._bgColor) == "#00000000",
    color.toHex(d3.style._bgColor))
check("opacity 默认 1", d3.style._opacity == 1, tostring(d3.style._opacity))

print("\n=== 6. 简写展开 ===")
local doc4 = html.parse([[<div style="margin: 1px 2px 3px 4px; padding: 5px">x</div>]])
style.apply(doc4, {})
local d4 = dom.elements(doc4)[1]
-- 简写展开的四值顺序：上 右 下 左
local expect = {["margin-top"]="1px", ["margin-right"]="2px",
                ["margin-bottom"]="3px", ["margin-left"]="4px", ["padding-top"]="5px"}
for _, k in ipairs{"margin-top","margin-right","margin-bottom","margin-left","padding-top"} do
  print(string.format("  %-16s = %s", k, tostring(d4.style[k])))
  check("简写 " .. k, d4.style[k] == expect[k],
      tostring(d4.style[k]) .. " (期望 " .. expect[k] .. ")")
end

print("\n=== 7. !important ===")
local doc5 = html.parse([[<div id="a" class="b">x</div>]])
style.apply(doc5, { css.parse([[
  div { color: red }
  .b { color: green !important }
  #a { color: blue }
]]) })
print("  color =", color.toHex(dom.elements(doc5)[1].style._color), "(应为绿，important 胜出)")
check("!important 胜出 -> 绿",
    color.toHex(dom.elements(doc5)[1].style._color) == "#008000ff",
    color.toHex(dom.elements(doc5)[1].style._color))

print("\n=== 8. opacity 解析 ===")
-- {输入, 期望值}
for _, c in ipairs{{"1",1}, {"0.5",0.5}, {"50%",0.5}, {"0",0}, {"abc",1}} do
  local v, want = c[1], c[2]
  local d = html.parse('<div style="opacity:'..v..'">x</div>')
  style.apply(d, {})
  local got = dom.elements(d)[1].style._opacity
  print(string.format("  opacity:%-5s -> %.2f", v, got))
  check("opacity " .. v, math.abs(got - want) < 0.001,
      string.format("%.2f (期望 %.2f)", got, want))
end

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end
