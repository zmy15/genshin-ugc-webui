-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

--[[ 真机仿真测试：验证控件复用

     ★ 这个测试用 engine_mock.lua（严格模拟真机限制），
       目的是在本地拦住「库依赖自定义字段」这类问题。

       历史教训：
         之前的 mock 用普通 table，自定义字段随便写，
         所以完全测不出真机上 reused=0 的问题 ——
         害我在真机上白白跑了好几轮。
]]--

local EngineMock = require('engine_mock')

local PREFABS = { container=1073741933, textbox=1073741934, button=1073741935 }
local E = EngineMock.new(PREFABS)

-- 注入到全局（真机上这些是引擎提供的）
game   = E.game
Color  = { FromRGBA = function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
           FromRGB  = function(r,g,b) return {r=r,g=g,b=b} end }
Enum   = {
  EaseType = { Linear="Linear", InQuad="InQuad", OutQuad="OutQuad", InOutQuad="InOutQuad" },
  EaseTypeLinear = "Linear",
  CursorEventType = {
    CursorClick="CursorClick", CursorDown="CursorDown", CursorUp="CursorUp",
    CursorEnter="CursorEnter", CursorExit="CursorExit",
    CursorBeginDrag="CursorBeginDrag", CursorDrag="CursorDrag",
    CursorEndDrag="CursorEndDrag",
  },
  TextHorizontalAlignmentLeft="L",
  TextHorizontalAlignmentMiddle="C",
  TextHorizontalAlignmentRight="R",
}

local webui = require('webui')
local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass=pass+1; print(string.format("  [OK] %-38s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-38s %s", name, detail or "")) end
end

local root = E.makeControl("container", nil)
script = { object = root }

local ui = webui.new({ root=root, prefabs=PREFABS, handlers={} })

local function page(n)
  local cards = {}
  for i = 1, n do
    cards[#cards+1] = string.format([[
<div class="card" id="c%d">
  <div class="nm">N%d</div>
  <div class="foot"><div class="grow"></div><div class="btn">B</div></div>
</div>]], i, i)
  end
  return [[<style>
    .card{width:200px;height:100px;padding:10px;background-color:#22222e;}
    .nm{width:180px;height:24px;color:#fff;}
    .foot{display:flex;align-items:center;width:180px;height:32px;}
    .grow{flex-grow:1;height:24px;}
    .btn{width:66px;height:28px;background-color:#4a90d9;}
  </style>]] .. table.concat(cards)
end

print("=== 0. 前置：mock 应拒绝自定义字段（模拟真机）===")
do
  local c = E.makeControl("textbox", root)
  c.__testField = "X"
  check("自定义字段写不进去", c.__testField == nil,
      "读到: " .. tostring(c.__testField))
  c.text = "OK"
  check("引擎字段可写", c.text == "OK", "读到: " .. tostring(c.text))
  local kids = root:GetChildren()
  check("GetChildren 可用", type(kids) == "table" and #kids > 0,
      #kids .. " 个子")
end

print()
print("=== 1. 首次渲染 ===")
ui:render(page(3))
local c1 = E.createdCount()
check("创建了控件", c1 > 0, "created=" .. c1)

print()
print("=== 2. 重复渲染应复用（核心：验证不依赖自定义字段）===")
local c2 = E.createdCount()
ui:render(page(3))
check("第2次不新建", E.createdCount() == c2,
    string.format("created %d -> %d", c2, E.createdCount()))

for i = 1, 5 do ui:render(page(3)) end
check("再 5 次也不新建", E.createdCount() == c2,
    string.format("created %d -> %d", c2, E.createdCount()))

print()
print("=== 3. 数量变化时复用率应高 ===")
local c3 = E.createdCount()
for i = 1, 20 do ui:render(page((i % 4) + 1)) end
local grew = E.createdCount() - c3
check("20 次增减新建 <= 20", grew <= 20, string.format("新建 %d 个", grew))

print()
print("=== 4. 所有控件应可见（父链正确）===")
ui:render(page(3))
local liveCount = 0
for _ in pairs(ui.rendered.live) do liveCount = liveCount + 1 end
local vis = E.visibleCount()
check("控件沿父链可见", vis >= liveCount * 0.9,
    string.format("live=%d 可见=%d", liveCount, vis))

print()
print("=== 5. 逐帧 flush 应稳定 ===")
local c4 = E.createdCount()
for i = 1, 100 do ui:flush() end
check("100 帧 flush 不新建", E.createdCount() == c4,
    string.format("created %d -> %d", c4, E.createdCount()))

print()
print("=== 6. 父链必须正确（坐标才能对）===")
local bad = 0
local function walk(node, parentCtrl)
  if not node:isElement() then return end
  local entry = ui.rendered.live[node]
  if entry then
    -- 用引擎 API 验证：该控件的实际父是否为 parentCtrl
    local kids = parentCtrl:GetChildren()
    local found = false
    for i = 1, #kids do if kids[i] == entry.control then found = true end end
    if not found then bad = bad + 1 end
    parentCtrl = entry.control
  end
  for i = 1, #node.children do walk(node.children[i], parentCtrl) end
end
for i = 1, #ui.doc.children do walk(ui.doc.children[i], ui.rendered.root) end
check("父链全对", bad == 0, string.format("%d 个控件父不对", bad))

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end
