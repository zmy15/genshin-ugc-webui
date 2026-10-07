-- 测试 HTML 解析器
-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path
local html = require('webui.html')
local dom  = require('webui.dom')

local cases = {
  {"基本嵌套", [[<div><span>hi</span></div>]]},
  {"属性",     [[<div id="a" class="x y" data-v="1">t</div>]]},
  {"自闭合",   [[<div><br/><img src="a.png"/></div>]]},
  {"注释",     [[<div><!-- 注释 -->text</div>]]},
  {"void标签", [[<div><hr><br><input type="text"></div>]]},
  {"style",    [[<style>.a{color:red}</style><div class="a">x</div>]]},
  {"自动闭合p",[[<div><p>a<p>b</div>]]},
  {"自动闭合li",[[<ul><li>a<li>b</ul>]]},
  {"未闭合容错",[[<div><span>x]]},
  {"多余闭合", [[<div></span></div>]]},
  {"深层嵌套", [[<div><div><div><div><div>deep</div></div></div></div></div>]]},
  {"单引号属性",[[<div class='a b'>x</div>]]},
  {"无引号属性",[[<div class=abc>x</div>]]},
  {"中文",     [[<div>你好世界</div>]]},
  {"空",       [[]]},
  {"纯文本",   [[hello world]]},
}

local pass, fail = 0, 0
for _, c in ipairs(cases) do
  local name, src = c[1], c[2]
  local ok, root = pcall(html.parse, src)
  if not ok then
    print(string.format("  [FAIL] %-12s 解析异常: %s", name, tostring(root)))
    fail = fail + 1
  else
    local st = dom.stats(root)
    print(string.format("  [ ok ] %-12s elements=%d texts=%d depth=%d",
        name, st.elements, st.texts, st.maxDepth))
    pass = pass + 1
  end
end
print(string.format("\n%d 通过, %d 失败", pass, fail))

-- 详细看几个
print("\n=== 详细：属性解析 ===")
local r = html.parse([[<div id="a" class="x y" data-v="1" disabled>t</div>]])
local div = dom.elements(r)[1]
print("  id =", div.id)
print("  classes =", table.concat(div.classList, ","))
print("  data-v =", div.attrs["data-v"])
print("  disabled =", tostring(div.attrs["disabled"]))

print("\n=== 详细：style 提取 ===")
local r2 = html.parse([[<style>.a{color:red}</style><div class="a">x</div>]])
local styles = html.extractStyles(r2)
print("  提取到", #styles, "个 style：", styles[1])

print("\n=== 详细：深层嵌套（测试不爆栈）===")
local deep = string.rep("<div>", 500) .. "x" .. string.rep("</div>", 500)
local ok, root = pcall(html.parse, deep)
if ok then
  local st = dom.stats(root)
  print(string.format("  500 层嵌套: OK, elements=%d, maxDepth=%d", st.elements, st.maxDepth))
else
  print("  500 层嵌套失败:", root)
end