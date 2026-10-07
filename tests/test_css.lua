-- 测试 CSS 解析器与选择器匹配
-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path
local html = require('webui.html')
local css  = require('webui.css')
local dom  = require('webui.dom')

print("=== 1. 选择器解析 ===")
local selCases = {
  "div", ".panel", "#main", "div.panel", "div.panel#main",
  "div span", "div > span", "*", ".a.b.c",
}
for _, s in ipairs(selCases) do
  local sel = css.parseSelector(s)
  if sel then
    local parts = {}
    for i = 1, #sel do
      local c = sel[i].comp
      parts[#parts+1] = string.format("[tag=%s id=%s cls=%d comb=%s]",
        tostring(c.tag), tostring(c.id), #c.classes, tostring(sel[i].combinator))
    end
    print(string.format("  %-16s -> %s", s, table.concat(parts, " ")))
  else
    print(string.format("  %-16s -> 不支持", s))
  end
end

print("\n=== 2. 属性选择器应被拒绝 ===")
for _, s in ipairs{"div[attr]", "div:hover", "div + span"} do
  local sel = css.parseSelector(s)
  print(string.format("  %-16s -> %s", s, sel and "解析了(应拒绝)" or "正确拒绝"))
end

print("\n=== 3. 样式表解析 ===")
local sheet = css.parse([[
  div { color: red; }
  .panel { background: #333; font-size: 14px; }
  #main .title { color: blue !important; }
]])
print("  规则数:", #sheet.rules)
for i, r in ipairs(sheet.rules) do
  local s = r.specificity
  print(string.format("    #%d spec=(%d,%d,%d) decls=%d", i, s.a, s.b, s.c,
      (function() local n=0 for _ in pairs(r.decls) do n=n+1 end return n end)()))
end

print("\n=== 4. 选择器匹配 ===")
local doc = html.parse([[
  <div id="main" class="app">
    <div class="panel">
      <span class="title">A</span>
    </div>
    <span>B</span>
  </div>
]])
local els = dom.elements(doc)
local tests = {
  -- 元素顺序: [1]div#main.app  [2]div.panel  [3]span.title  [4]span
  {"div",              {true, true, false, false}},
  {".panel",           {false, true, false, false}},
  {"#main",            {true, false, false, false}},
  {"div span",         {false, false, true, true}},
  {"div > span",       {false, false, true, true}},   -- [3]的父是div.panel, [4]的父是div#main
  {".panel .title",    {false, false, true, false}},
  {"#main .title",     {false, false, true, false}},
  {"*",                {true, true, true, true}},
}
for _, t in ipairs(tests) do
  local sel = css.parseSelector(t[1])
  local expect = t[2]
  local got = {}
  local allOk = true
  for i = 1, #els do
    got[i] = css.matches(els[i], sel)
    if got[i] ~= expect[i] then allOk = false end
  end
  local marks = {}
  for i = 1, #els do marks[i] = got[i] and "Y" or "n" end
  print(string.format("  %-16s -> %s  %s", t[1], table.concat(marks, ""),
      allOk and "OK" or ("期望 " .. (function()
        local m={} for i=1,#expect do m[i]=expect[i] and "Y" or "n" end
        return table.concat(m,"") end)())))
end

print("\n=== 5. 特指度排序 ===")
local doc2 = html.parse([[<div id="a" class="b">x</div>]])
local sheets = { css.parse([[
  div { color: 1 }
  .b { color: 2 }
  #a { color: 3 }
  div.b { color: 4 }
  div#a.b { color: 5 }
]]) }
local el = dom.elements(doc2)[1]
local rules = css.collectRules(el, sheets)
print("  匹配规则（按特指度升序）:")
for i, r in ipairs(rules) do
  print(string.format("    (%d,%d,%d) -> color=%s", r.specificity.a,
      r.specificity.b, r.specificity.c, r.decls.color and r.decls.color.value or "?"))
end
print("  最后胜出（应是最高的）:", rules[#rules].decls.color.value)

print("\n=== 6. 内联样式 ===")
local inl = css.parseInline("color: red; font-size: 14px !important")
print("  color =", inl.color.value, "important =", tostring(inl.color.important))
print("  font-size =", inl["font-size"].value, "important =", tostring(inl["font-size"].important))

print("\n=== 7. 注释与 at-rule ===")
local sheet3 = css.parse([[
  /* 注释 */
  div { color: red }
  @media screen { div { color: blue } }
  .x { color: green }
]])
print("  规则数(应为2):", #sheet3.rules)