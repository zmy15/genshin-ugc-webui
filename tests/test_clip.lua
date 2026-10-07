--[[============================================================================
  test_clip.lua  ——  裁剪 / 换图 功能测试

  验证 webui/clip.lua 与渲染层的裁剪集成：

    1. clip.lua 自身：枚举探测、setImage、asClip、染色、CSS 值映射
    2. 样式层：overflow:hidden -> _clipShape = 100001（矩形图）
               border-radius:50% -> _clipShape = 100002（圆形图）
    3. 渲染层：chooseKind 对裁剪元素选 image 类型
    4. 集成：渲染后控件真的被 SetImage + enableMask

  ★ 用 engine_mock 跑（严格模拟真机限制），
    但【图片控件字段】要按真机实测补进 mock —— 见下方 PATCH 说明。
=============================================================================]]

-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')

--=============================================================================
-- 真机字段补丁
--
--   ⚠️ 原 engine_mock 没有 image 类型（R16 才确认图片控件索引与字段）。
--      这里按【真机实测结果】补上，否则测不出裁剪功能。
--      同时模拟"字段按类型封死"：image 没有 bgColor/text。
--=============================================================================

local PREFABS = {
  container = 1073741933,
  textbox   = 1073741934,
  button    = 1073741935,
  image     = 1073741938,   -- R16 确认的图片控件索引
}

local E = EngineMock.new(PREFABS)

--=============================================================================
-- 注入引擎全局（含真机实测的 Enum 结构）
--=============================================================================

game   = E.game
Color  = { FromRGBA = function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
           FromRGB  = function(r,g,b) return {r=r,g=g,b=b} end }

--[[ ★ 按 R16 真机实测的真实枚举名。
     注意是 StaticReference，不是文档写的 ImageSourceStaticReference。
]]--
Enum = {
  EaseType = { Linear="Linear", InQuad="InQuad", OutQuad="OutQuad", InOutQuad="InOutQuad" },
  CursorEventType = {
    CursorClick="CursorClick", CursorDown="CursorDown", CursorUp="CursorUp",
    CursorEnter="CursorEnter", CursorExit="CursorExit",
    CursorBeginDrag="CursorBeginDrag", CursorDrag="CursorDrag",
    CursorEndDrag="CursorEndDrag",
  },
  TextHorizontalAlignmentLeft="L",
  TextHorizontalAlignmentMiddle="C",
  TextHorizontalAlignmentRight="R",
  -- R16 实测的真实结构
  ImageSource = {
    StaticReference = "Enum.ImageSource.StaticReference",
    Item = "Enum.ImageSource.Item",
    Equipment = "Enum.ImageSource.Equipment",
  },
  ImageType = { Basic = "Enum.ImageType.Basic", Stretch = "Enum.ImageType.Stretch" },
}

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass=pass+1
    print(string.format("  [OK] %-42s %s", name, detail or ""))
  else fail=fail+1
    print(string.format("  [XX] %-42s %s", name, detail or "")) end
end

--=============================================================================
-- 给 mock 补 image 类型支持
--=============================================================================

local clip = require('webui_clip')

print("=== 1. clip.lua 基础 ===")

check("SHAPES 表存在", type(clip.SHAPES) == "table",
    "SQUARE=" .. tostring(clip.SHAPES and clip.SHAPES.SQUARE))
check("SQUARE = 100001", clip.SHAPES.SQUARE == 100001)
check("CIRCLE = 100002", clip.SHAPES.CIRCLE == 100002)

local src = clip.imageSource()
check("探测到 ImageSource", src ~= nil, "值=" .. tostring(src))
check("用的是 StaticReference（非文档写法）",
    tostring(src):find("StaticReference") ~= nil, tostring(src))

print()
print("=== 2. CSS 值映射 ===")

check("overflow:hidden 需要矩形裁剪", clip.needsRectClip("hidden") == true)
check("overflow:visible 不需要", clip.needsRectClip("visible") == false)
check("border-radius:50% -> 圆形图",
    clip.shapeForRadius("50%") == clip.SHAPES.CIRCLE)
check("border-radius:0 -> nil", clip.shapeForRadius("0") == nil)
check("border-radius:8px -> 圆形图（预置无圆角矩形）",
    clip.shapeForRadius("8px") == clip.SHAPES.CIRCLE)

print()
print("=== 3. 样式层：CSS -> _clipShape ===")

local webui = require('webui')

-- 造一个带 overflow:hidden 的节点
local function styleOf(html)
  local doc = require('webui_html').parse(html)
  require('webui_style').apply(doc, {})
  -- 找第一个元素
  local function firstEl(n)
    if n:isElement() then return n end
    for i=1,#n.children do
      local r = firstEl(n.children[i]); if r then return r end
    end
  end
  return firstEl(doc)
end

local n1 = styleOf([[<div style="width:100px;height:50px;overflow:hidden"></div>]])
check("overflow:hidden -> _clipShape = 矩形图",
    n1 and n1.style._clipShape == 100001,
    "值=" .. tostring(n1 and n1.style._clipShape))

local n2 = styleOf([[<div style="width:100px;height:100px;border-radius:50%"></div>]])
check("border-radius:50% -> _clipShape = 圆形图",
    n2 and n2.style._clipShape == 100002,
    "值=" .. tostring(n2 and n2.style._clipShape))

local n3 = styleOf([[<div style="width:100px;height:50px"></div>]])
check("普通元素 -> _clipShape = nil",
    n3 and n3.style._clipShape == nil,
    "值=" .. tostring(n3 and n3.style._clipShape))

print()
print("=== 4. 真机仿真：渲染时真的配了遮罩 ===")

-- 重建一套 mock（前面 styleOf 没动 mock）
local E2 = EngineMock.new(PREFABS)
game = E2.game

local root = E2.makeControl("container", nil)
script = { object = root }

local ui = webui.new({ root = root, prefabs = PREFABS, handlers = {} })
ui:render([[
<style>
  .card { width:200px;height:100px;background-color:#333;overflow:hidden; }
  .round { width:80px;height:80px;background-color:#4a90d9;border-radius:50%; }
</style>
<div class="card">
  <div style="width:400px;height:200px;background-color:#ff0"></div>
</div>
<div class="round"></div>
]])

-- 找带 enableMask 的控件
local masked, found = 0, {}
for _, c in ipairs(E2.controls) do
  local d = E2.dataOf(c)
  if d and d.fields and d.fields.enableMask == true then
    masked = masked + 1
    found[#found+1] = { id = d.fields.imageId, kind = d.kind }
  end
end

check("有控件被启用遮罩", masked >= 1, "共 " .. masked .. " 个")

local hasRect, hasCircle = false, false
for _, f in ipairs(found) do
  if f.id == 100001 then hasRect = true end
  if f.id == 100002 then hasCircle = true end
end
check("矩形遮罩(100001)已配置", hasRect)
check("圆形遮罩(100002)已配置", hasCircle)

print()
print("=== 5. 重复渲染不应重复 SetImage ===")

-- 数一下 SetImage 被调用几次
local setImageCalls = 0
local origInstantiate = E2.game.InstantiateClientUIControl

-- 用控件本身的方法计数
for _, c in ipairs(E2.controls) do
  local d = E2.dataOf(c)
  if d and d.fields.enableMask then
    -- 包装 SetImage
    local realCall = c.SetImage
    -- mock 的 METHODS 里若没有 SetImage 会返回 nil
    c.SetImage = function(self, s, id)
      setImageCalls = setImageCalls + 1
      local dd = E2.dataOf(self)
      if dd then dd.fields.imageId = id end
      return true
    end
  end
end

for i = 1, 5 do ui:flush() end
check("5 次 flush 后 SetImage 未重复调用", setImageCalls == 0,
    "额外调用 " .. setImageCalls .. " 次（应为 0，因形状未变）")

print()
print("=== 6. data-image 显式声明图片控件 ===")

--[[ ★ 为什么需要这个开关：

      chooseKind 默认按"有无背景色"选 textbox，
      而真机 textbox 【没有 SetImage】。
      要画形状图必须显式声明 <div data-image="1">。

      实现细节：取的是【HTML 属性】而非 CSS 属性 ——
      HTML 属性不会进入样式表键，这条踩过坑。
]]--
local n4 = styleOf([[<div style="width:50px;height:50px;background-color:#222" data-image="1"></div>]])
check("data-image=1 -> _forceImage",
    n4 and n4.style._forceImage == true,
    "值=" .. tostring(n4 and n4.style._forceImage))

local n5 = styleOf([[<div style="width:50px;height:50px;background-color:#222"></div>]])
check("无 data-image -> _forceImage = nil",
    n5 and n5.style._forceImage == nil,
    "值=" .. tostring(n5 and n5.style._forceImage))

print()
print("=== 7. ★ 裁剪容器里的文字不能丢 ===")

--[[ 回归测试：2026-10-07 真机发现。

      问题：裁剪必须用 image 控件，但 image 【没有 text 字段】，
            写 text 静默失败 -> 裁剪容器里的文字全丢。

      修法：裁剪元素若自带文字，额外挂一个 textbox 子控件承载。

      本测试确保这个修复不被改回去。
]]--
local E3 = EngineMock.new(PREFABS)
game = E3.game
local root3 = E3.makeControl("container", nil)
script = { object = root3 }

local ui3 = webui.new({ root = root3, prefabs = PREFABS, handlers = {} })
ui3:render([[
<style>
  .card { width:200px; height:80px; overflow:hidden; color:#fff; font-size:16px; }
  .rnd  { width:60px;  height:60px; border-radius:50%; color:#ffd050; font-size:14px; }
  .plain{ width:200px; height:30px; color:#fff; font-size:16px; }
</style>
<div class="card" id="card1">卡片文字</div>
<div class="rnd"  id="rnd1">圆</div>
<div class="plain" id="plain1">普通文字</div>
]])

local function entryOf(id)
  for node, e in pairs(ui3.rendered.live) do
    if node.id == id then return e, node end
  end
  return nil
end

local ec = entryOf("card1")
check("裁剪容器(#card1)是 image 类型",
    ec and ec.kind == "image", ec and ec.kind or "?")
check("裁剪容器挂了子文字控件",
    ec and ec.textChild ~= nil)
if ec and ec.textChild then
  local d = E3.dataOf(ec.textChild)
  check("子控件是 textbox", d and d.kind == "textbox", d and d.kind or "?")
  check("子控件文字正确", d and d.fields.text == "卡片文字",
      tostring(d and d.fields.text))
end

local er = entryOf("rnd1")
check("圆形裁剪容器也挂了子文字控件",
    er and er.textChild ~= nil)

local ep = entryOf("plain1")
check("普通文字(#plain1)仍是 textbox（未被误改）",
    ep and ep.kind == "textbox", ep and ep.kind or "?")
check("普通文字不挂多余子控件",
    ep and ep.textChild == nil)

print()
print("=== 8. ★ 裁剪容器不能被填充（真机发现的月牙 bug）===")

--[[ 回归测试：2026-10-07 真机发现。

      问题：裁剪容器是 image 类型，CSS 的 background-color 映射到 imageColor。
            但 enableMask 只裁【子控件】，控件的 imageColor 填充
            【不受自己的遮罩约束】—— 底色会溢出到裁剪区之外。

            表现为：圆形/圆角裁剪的外侧出现一圈异常色块
            （头像右侧跑出一条 ~28px 暗色月牙）。

      修法：裁剪容器跳过 imageColor 写入。
]]--
local E4 = EngineMock.new(PREFABS)
game = E4.game
local root4 = E4.makeControl("container", nil)
script = { object = root4 }

local ui4 = webui.new({ root = root4, prefabs = PREFABS, handlers = {} })
ui4:render([[
<style>
  /* 裁剪容器 + 有底色 -> 底色不应被写入 */
  .av    { width:80px; height:80px; border-radius:50%; background-color:#2a3550; }
  .inner { width:80px; height:80px; background-color:#4a6fa8; }
  /* 普通图片元素（不裁剪）-> 底色应正常写入 */
  .plain { width:60px; height:60px; background-color:#7ac050; }
</style>
<div class="av" id="av1"><div class="inner"></div></div>
<div class="plain" id="pl1" data-image="1"></div>
]])

local function ctrlOf(id)
  for node, e in pairs(ui4.rendered.live) do
    if node.id == id then return e.control, e end
  end
  return nil
end

local avCtrl, avEntry = ctrlOf("av1")
check("头像容器是 image 类型（要裁剪）",
    avEntry and avEntry.kind == "image", avEntry and avEntry.kind or "?")

if avCtrl then
  local ok, col = pcall(function() return avCtrl.imageColor end)
  --[[ "未填充"的两种合法表现：
       · nil          -> 从未被写入（最常见）
       · a == 0       -> 被写入但完全透明
       两者都表示裁剪容器没有底色。
  ]]--
  local notFilled = false
  local desc = "nil"
  if ok then
    if col == nil then
      notFilled = true
      desc = "nil（从未写入）"
    elseif type(col) == "table" then
      notFilled = ((col.a or 0) == 0)
      desc = string.format("a=%s", tostring(col.a))
    end
  end
  check("裁剪容器 imageColor 未被填充", notFilled, desc)
end

local plCtrl, plEntry = ctrlOf("pl1")
check("普通图片元素仍是 image", plEntry and plEntry.kind == "image")
if plCtrl then
  local ok, col = pcall(function() return plCtrl.imageColor end)
  local tinted = ok and type(col) == "table" and (col.a or 255) > 0
  check("普通图片元素底色正常写入", tinted,
      ok and (type(col) == "table"
        and string.format("rgb(%s,%s,%s)", tostring(col.r), tostring(col.g),
            tostring(col.b)) or tostring(col)))
end

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end
