-- 测试布局引擎
-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path
local html   = require('webui.html')
local css    = require('webui.css')
local style  = require('webui.style')
local layout = require('webui.layout')
local dom    = require('webui.dom')

local function run(name, src, cssSrc, W, H)
  W, H = W or 800, H or 600
  local doc = html.parse(src)
  local sheets = {}
  if cssSrc then sheets[1] = css.parse(cssSrc) end
  style.apply(doc, sheets)
  layout.compute(doc, W, H)
  print("=== " .. name .. " ===")
  print(layout.dump(doc))
  print()
  return doc
end

-- 1. 基本 block 堆叠
run("1. block 堆叠", [[
  <div style="width:100%; height:50px"></div>
  <div style="width:100%; height:30px"></div>
]], nil)

-- 2. 固定尺寸 + 内边距
run("2. 固定尺寸 + padding", [[
  <div style="width:200px; height:100px; padding:10px"></div>
]], nil)

-- 3. 百分比宽高
run("3. 百分比", [[
  <div style="width:50%; height:50%"></div>
]], nil)

-- 4. 绝对定位
run("4. absolute", [[
  <div style="position:absolute; left:100px; top:50px; width:80px; height:40px"></div>
  <div style="position:absolute; right:20px; bottom:30px; width:60px; height:60px"></div>
]], nil)

-- 5. flex row
run("5. flex row", [[
  <div style="display:flex; flex-direction:row; gap:10px; width:100%; height:100px">
    <div style="width:50px; height:50px"></div>
    <div style="width:50px; height:50px"></div>
    <div style="width:50px; height:50px"></div>
  </div>
]], nil)

-- 6. flex justify
run("6. flex center", [[
  <div style="display:flex; justify-content:center; width:100%; height:100px">
    <div style="width:50px; height:50px"></div>
  </div>
]], nil)

-- 7. flex column
run("7. flex column", [[
  <div style="display:flex; flex-direction:column; gap:5px; width:100%">
    <div style="width:100px; height:30px"></div>
    <div style="width:100px; height:30px"></div>
  </div>
]], nil)

-- 8. 嵌套 + auto 高度
run("8. 嵌套 auto 高度", [[
  <div style="width:300px">
    <div style="height:40px"></div>
    <div style="height:60px"></div>
  </div>
]], nil)

-- 9. 文本测量
run("9. 文本节点", [[
  <div style="width:200px; font-size:20px">Hello World</div>
]], nil)

-- 10. margin
run("10. margin", [[
  <div style="margin: 10px; height:30px"></div>
  <div style="margin: 20px 5px; height:30px"></div>
]], nil)

-- 11. 综合
run("11. 综合（面板+按钮）", [[
  <div class="panel">
    <div class="title">标题</div>
    <div class="row">
      <div class="btn">按钮A</div>
      <div class="btn">按钮B</div>
    </div>
  </div>
]], [[
  .panel { width: 400px; padding: 20px; background-color:#222; }
  .title { height: 30px; font-size: 18px; color: #fff; }
  .row { display:flex; gap:10px; }
  .btn { width: 100px; height: 36px; background-color:#444; }
]], 800, 600)

--[[ ★★ flex column 必须尊重子项的显式 width（2026-10-07 修）

     原 bug：flex-direction:column 时无条件把子项宽度设为父容器宽度，
             子项 CSS 里写的 width 被完全忽略。

     真机表现（很隐蔽）：
       #root { display:flex; flex-direction:column }
         .avatar { width:130px }  -> 被算成 980px（父内容宽）
         border-radius:50% 按 980:130 适配 -> 圆形被横向拉成扁椭圆
       同理 overflow:hidden 的卡片变宽 -> 子元素不再溢出 -> 裁剪看不出效果

     正确语义：显式指定 width 的子项保持自身宽度；
               未指定的才在 align-items:stretch 下拉伸。
]]--
print("=== flex column 宽度语义 ===")
do
  local doc = html.parse([[
    <div id="root">
      <div class="fixed" id="fx"></div>
      <div class="auto" id="au"></div>
    </div>
  ]])
  local sheets = { css.parse([[
    #root { display:flex; flex-direction:column; width:1000px; height:600px; }
    .fixed { width:130px; height:130px; }
    .auto  { height:40px; }
  ]]) }
  style.apply(doc, sheets)
  layout.compute(doc, 1600, 900)

  local function find(n, id)
    if n.id == id then return n end
    for i = 1, #n.children do
      local r = find(n.children[i], id)
      if r then return r end
    end
  end

  local fx = find(doc, "fx")
  local au = find(doc, "au")

  local okW = fx and fx.box and math.abs(fx.box.w - 130) < 0.5
  -- ★ #root 没写 padding，所以内容宽 = 1000
  local okS = au and au.box and math.abs(au.box.w - 1000) < 2
  local okH = fx and fx.box and math.abs(fx.box.h - 130) < 0.5

  print(string.format("  %s 显式 width 被尊重:       .fixed w=%.1f (期望130)",
      okW and "[OK]" or "[XX]", fx and fx.box and fx.box.w or -1))
  print(string.format("  %s 未指定宽度被 stretch:   .auto  w=%.1f (期望1000)",
      okS and "[OK]" or "[XX]", au and au.box and au.box.w or -1))
  print(string.format("  %s 高度不受影响:           .fixed h=%.1f (期望130)",
      okH and "[OK]" or "[XX]", fx and fx.box and fx.box.h or -1))
  print()
end

--[[ ★★ intrinsicWidth 不能包含 margin（2026-10-07 修）

     原 bug：intrinsicWidth 把 margin 也算进 extraW，
             而 flex 调用方又加了一次 margin，
             导致元素宽度多出一个 margin 的量。

     真机表现（很隐蔽）：
       .avatar { width:130px; margin-right:20px }
         -> 布局宽度算成 150
         -> 子元素 .avatar-inner 只有 130
         -> 父右侧露出 20px（控件默认白底）
         -> 屏幕上出现一条白色竖条
]]--
print("=== intrinsicWidth 不含 margin ===")
do
  local doc = html.parse([[<div class="a" id="a"></div>]])
  style.apply(doc, { css.parse([[
    .a { width:130px; height:130px; margin-right:20px; }
  ]]) })
  local a = nil
  local function walk(n)
    if n.id == "a" then a = n return end
    for i = 1, #n.children do walk(n.children[i]) end
  end
  walk(doc)

  local iw = a and layout.intrinsicWidth(a, 1000, 500)
  local ok = iw and math.abs(iw - 130) < 0.5
  print(string.format("  %s intrinsicWidth = %.0f (期望130，不含margin=20)",
      ok and "[OK]" or "[XX]", iw or -1))
  print()
end

print("=== 性能：1000 个节点 ===")
local parts = {}
for i = 1, 200 do
  parts[i] = '<div style="width:100%;height:5px"></div>'
end
local bigSrc = table.concat(parts)
local t0 = os.clock()
local doc = html.parse(bigSrc)
local t1 = os.clock()
style.apply(doc, {})
local t2 = os.clock()
layout.compute(doc, 800, 600)
local t3 = os.clock()
local st = dom.stats(doc)
print(string.format("  %d 元素  解析 %.1fms  样式 %.1fms  布局 %.1fms  总计 %.1fms",
    st.elements, (t1-t0)*1000, (t2-t1)*1000, (t3-t2)*1000, (t3-t0)*1000))