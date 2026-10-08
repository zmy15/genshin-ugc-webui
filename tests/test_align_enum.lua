--[[ test_align_enum.lua —— ★ 守 R23：水平对齐枚举的真名

     ⚠️⚠️ 这是本仓库【最重要的一条枚举回归】。

     真机实测（R23，2026-10-09）：
       Enum.TextHorizontalAlignment        = 子表
       Enum.TextHorizontalAlignment.Middle = 可用 ✅
       Enum.TextHorizontalAlignmentMiddle  = nil   ❌（文档写的就是这个）

     库原先用扁平名 + pcall，失败被静默吞掉 ->
     text-align:center 从 R21 起【一直是失效的】，没人发现。

     ★ 本测试用 enum_kit 构造【忠实于真机】的 Enum（扁平名为 nil），
       所以能真正拦住这类 bug。
       ⚠️ 若把 enum_kit 改回"文档形态"，本测试会立刻变绿而失去意义 ——
          那正是当初测试没拦住的原因（§七「测试替身必须忠实」）。
]]

local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;" .. _root .. "/?.lua;"
             .. _root .. "/tests/?.lua;" .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')
local enumkit    = require('enum_kit')

local PREFABS = { container=1073741933, textbox=1073741934,
                  button=1073741935, image=1073741938 }
local E = EngineMock.new(PREFABS)

game  = E.game
Color = { FromRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
          FromRGB =function(r,g,b) return {r=r,g=g,b=b} end }
-- ★★ 关键：用【真机形态】的 Enum（扁平名故意为 nil）
Enum = enumkit.build({
  EaseType = { Linear="Linear", InQuad="InQuad" },
  CursorEventType = {
    CursorClick="CursorClick", CursorDown="CursorDown", CursorUp="CursorUp",
    CursorEnter="CursorEnter", CursorExit="CursorExit",
    CursorBeginDrag="CursorBeginDrag", CursorDrag="CursorDrag",
    CursorEndDrag="CursorEndDrag",
  },
})

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass=pass+1; print(string.format("  [OK] %-48s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-48s %s", name, detail or "")) end
end

--=============================================================================
print("=== 0. 先确认 Enum 被造成【真机形态】 ===")
--=============================================================================
check("Enum.TextHorizontalAlignment 是子表",
    type(Enum.TextHorizontalAlignment) == "table")
check("★ 扁平名 TextHorizontalAlignmentMiddle 为 nil（真机如此）",
    Enum.TextHorizontalAlignmentMiddle == nil,
    tostring(Enum.TextHorizontalAlignmentMiddle))
check("子表形式取值可用",
    Enum.TextHorizontalAlignment.Middle == "Enum.TextHorizontalAlignment.Middle",
    tostring(Enum.TextHorizontalAlignment.Middle))
check("pairs(Enum) 为空（顶层不可遍历，同真机）", (function()
  local n = 0
  for _ in pairs(Enum) do n = n + 1 end
  return n == 0
end)())

--=============================================================================
print("\n=== 1. ★ text-align:center 必须真的写进控件 ===")
--=============================================================================
local root = E.makeControl("container", nil)
script = { object = root }
local webui = require('webui')
local ui = webui.new({ root=root, prefabs=PREFABS, handlers={} })

ui:render([[
<style>
.ctr { position:absolute; left:40px; top:40px; width:400px; height:50px;
       font-size:20px; color:#ffffff; background-color:#2a3550;
       text-align:center; }
.rgt { position:absolute; left:40px; top:120px; width:400px; height:50px;
       font-size:20px; color:#ffffff; background-color:#2a3550;
       text-align:right; }
.lft { position:absolute; left:40px; top:200px; width:400px; height:50px;
       font-size:20px; color:#ffffff; background-color:#2a3550;
       text-align:left; }
</style>
<div class="ctr" id="c">居中</div>
<div class="rgt" id="r">右对齐</div>
<div class="lft" id="l">左对齐</div>
]])

local function ctrlOf(id)
  local nd = nil
  require('webui_dom').walk(ui.doc, function(n)
    if n:isElement() and n.attrs and n.attrs.id == id then nd = n end
  end)
  local e = nd and ui.rendered.live[nd]
  return e and e.control
end

local C, R, L = ctrlOf("c"), ctrlOf("r"), ctrlOf("l")

check("拿到三个控件", C and R and L)

local okC, whyC = enumkit.assertCentered(C)
check("★ text-align:center -> horizontalAlignment = Middle",
    okC, tostring(whyC))

check("text-align:right -> Right",
    R and tostring(R.horizontalAlignment):find("Right", 1, true) ~= nil,
    R and tostring(R.horizontalAlignment))

check("text-align:left -> Left",
    L and tostring(L.horizontalAlignment):find("Left", 1, true) ~= nil,
    L and tostring(L.horizontalAlignment))

--=============================================================================
print("\n=== 2. ★ 换帧后仍保持（不能被 diff 缓存吃掉） ===")
--=============================================================================
--[[ 库按 last.__align 做 diff，只在"变化时"写入。
     首帧写过之后，后续帧不会再写 —— 若首次写入失败（旧代码那样），
     缓存里却已记成"已写 Middle"，于是【永远不再重试】。
     这正是旧 bug 难以自愈的原因。 ]]--
for _ = 1, 10 do ui:flush() end
local okC2 = enumkit.assertCentered(C)
check("★ 连续 10 帧 flush 后仍是 Middle", okC2)

--=============================================================================
print("\n=== 3. ★ 动态切换对齐也要生效 ===")
--=============================================================================
--[[ ⚠️ setStyle 是【DOM 节点】的方法，不是控件的方法。
      控件只有字段。这里取回节点来改。 ]]--
local function nodeOf(id)
  local nd = nil
  require('webui_dom').walk(ui.doc, function(n)
    if n:isElement() and n.attrs and n.attrs.id == id then nd = n end
  end)
  return nd
end

local cNode = nodeOf("c")
cNode:setStyle("text-align", "right")
ui:flush()
check("改样式为 right 后立即生效",
    tostring(C.horizontalAlignment):find("Right", 1, true) ~= nil,
    tostring(C.horizontalAlignment))

cNode:setStyle("text-align", "center")
ui:flush()
local okC3 = enumkit.assertCentered(C)
check("★ 改回 center 后恢复 Middle", okC3,
    tostring(C.horizontalAlignment))

print("")
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end