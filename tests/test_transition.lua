-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path
local html   = require('webui.html')
local css    = require('webui.css')
local style  = require('webui.style')
local trans  = require('webui.transition')

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass=pass+1; print(string.format("  [OK] %-30s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-30s %s", name, detail or "")) end
end

print("=== 1. 时间解析 ===")
local tcases = {{"0.3s",0.3},{"300ms",0.3},{"1s",1},{"0",0},{"1.5s",1.5}}
for _, c in ipairs(tcases) do
  local r = trans.parseTime(c[1])
  check(c[1], r and math.abs(r - c[2]) < 0.001, "-> " .. tostring(r))
end

print()
print("=== 2. 简写解析 ===")
local l1 = trans.parseShorthand("background-color 0.3s ease-in-out")
check("单属性", #l1 == 1 and l1[1].property == "background-color"
      and math.abs(l1[1].duration - 0.3) < 0.001,
    l1[1] and string.format("%s %.2fs %s", l1[1].property, l1[1].duration, l1[1].timing))

local l2 = trans.parseShorthand("background-color 0.3s, color 0.2s linear")
check("多属性", #l2 == 2, string.format("%d 条", #l2))
check("第二条缓动", l2[2] and l2[2].timing == "Linear", l2[2] and l2[2].timing)

local l3 = trans.parseShorthand("all 0.5s")
check("all", l3[1] and l3[1].property == "all")

print()
print("=== 3. 通过 style 解析 ===")
local doc = html.parse([[
<style>
  .a { background-color:#111; transition: background-color 0.4s ease-out; }
  .b { color:#fff; transition-property: color; transition-duration: 250ms; }
  .c { background-color:#222; }
</style>
<div class="a"></div><div class="b"></div><div class="c"></div>
]])
style.apply(doc, { css.parse(html.extractStyles(doc)[1]) })

local divs = {}
for _, e in ipairs(require('webui.dom').elements(doc)) do
  if e.tag == "div" then divs[#divs+1] = e end
end

local ta = trans.parse(divs[1].style)
check(".a 有 transition", ta ~= nil and ta["background-color"] ~= nil,
    ta and ta["background-color"] and
    string.format("%s %.2fs %s", ta["background-color"].property,
        ta["background-color"].duration, ta["background-color"].timing) or "nil")

local tb = trans.parse(divs[2].style)
check(".b 长写法", tb ~= nil and tb["color"] ~= nil,
    tb and tb["color"] and string.format("duration=%.2fs", tb["color"].duration) or "nil")

local tc = trans.parse(divs[3].style)
check(".c 无 transition", tc == nil)

print()
print("=== 4. 缓动映射 ===")
for _, c in ipairs{{"linear","Linear"},{"ease","InOutQuad"},
                   {"ease-in","InQuad"},{"ease-out","OutQuad"},
                   {"ease-in-out","InOutQuad"}} do
  local l = trans.parseShorthand("color 0.3s " .. c[1])
  check(c[1], l[1].timing == c[2], "-> " .. l[1].timing)
end

print()
print("=== 5. 带 delay ===")
local l5 = trans.parseShorthand("color 0.3s ease 0.1s")
check("delay 解析", l5[1] and math.abs((l5[1].delay or 0) - 0.1) < 0.001,
    l5[1] and string.format("delay=%.2f", l5[1].delay or -1))

print()
print("=== 6. 多属性带逗号 ===")
local l6 = trans.parseShorthand("background-color 0.3s ease-in,color 0.2s linear,opacity 0.5s")
check("三条", #l6 == 3, string.format("%d 条", #l6))
for i, e in ipairs(l6) do
  print(string.format("      %d: %-18s %.2fs %s", i, e.property, e.duration, e.timing))
end

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end
