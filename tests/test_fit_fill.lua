-- 测试 fitfill 模块的【核心主张】（R35）
--
-- ★ 主张：把 designSize 设成【当前画布尺寸】后
--     ① 库的留边归零（offsetX = offsetY = 0）
--     ② 连留边条控件都不建（_backdrop 为空）
--     ③ 100vw x 100vh 的块正好等于画布
--
--   于是"块色 == 画布"，屏幕四边剩下的必然是【画布之外】的区域
--   —— 这正是 fitfill 用来回答"画布铺满了没有"的原理。
--
-- ★ 这是一条【纯逻辑 + 渲染集成】的验算，不需要真机：
--     真机只是把"画布尺寸"换成设备实际值，结论形式不变。
--
-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
             .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')
local util       = require('webui_util')
local dom        = require('webui_dom')

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-40s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-40s %s", name, detail or "")) end
end
local function near(a, b, eps) return math.abs((a or 0) - (b or 0)) <= (eps or 0.5) end

local PREFABS = { container=1073741933, textbox=1073741934,
                  button=1073741935, image=1073741938 }

--[[ 建一个"designSize = 画布"的 ui，并铺一块 100vw x 100vh 的色。
     返回 ui 与那个块节点的 box。 ]]--
local function buildFill(cw, ch)
  local E = EngineMock.new(PREFABS)
  E.setCanvas(cw, ch)

  _G.game  = E.game
  _G.Color = { FromRGBA = function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
               FromRGB  = function(r,g,b) return {r=r,g=g,b=b} end }
  _G.Enum  = {
    EaseType = { Linear="Linear" },
    CursorEventType = {
      CursorClick="CursorClick", CursorDown="CursorDown", CursorUp="CursorUp",
      CursorEnter="CursorEnter", CursorExit="CursorExit",
      CursorBeginDrag="CursorBeginDrag", CursorDrag="CursorDrag",
      CursorEndDrag="CursorEndDrag",
    },
    ImageSource = { StaticReference = "Enum.ImageSource.StaticReference" },
    TextHorizontalAlignment = { Left="L", Middle="C", Right="R" },
    TextVerticalAlignment   = { Top="T", Middle="M", Bottom="B" },
  }
  util.resetCanvasCache()

  local webui = require('webui')
  local root = E.makeControl("container", nil)
  root.name = "Root"
  _G.script = { object = root }

  -- ★ 这就是 fitfill.uiOptsFor() 做的事：designSize = 当前画布
  local ui = webui.new{
    root = root, prefabs = PREFABS, handlers = {},
    designSize = { cw, ch }, fit = "letterbox", fitBg = "#000000",
  }
  ui:setHTML([[<div class="fill"></div>]])
  ui:addCSS([[
    .fill { position: absolute; left: 0px; top: 0px;
            width: 100vw; height: 100vh; background-color: #20c060; }
  ]])
  ui:flush()

  local fill
  dom.walk(ui.doc, function(n)
    if n:isElement() and n.attrs and n.attrs.class == "fill" then fill = n end
  end)

  return E, ui, fill
end

--=============================================================================
print("=== 1. designSize == 画布 -> 留边必须归零 ===")
--=============================================================================

--[[ 三个真实画布尺寸都验。★ 手机那一档是历史上出问题的那台设备。 ]]--
local CANVASES = {
  { "16:9 PC   1600x900",  1600,  900 },
  { "宽屏 PC   2184x900",  2184,  900 },
  { "手机      2532x1170", 2532, 1170 },
}

for _, c in ipairs(CANVASES) do
  local name, cw, ch = c[1], c[2], c[3]
  local E, ui, fill = buildFill(cw, ch)
  local f = ui.rendered.fit

  check(name .. " 留边 X 归零", near(f.offsetX, 0),
        string.format("offX=%.2f", f.offsetX))
  check(name .. " 留边 Y 归零", near(f.offsetY, 0),
        string.format("offY=%.2f", f.offsetY))

  -- ★★ 关键：留边为 0 时【不该建任何留边条】
  check(name .. " 不建留边条",
        ui.rendered._backdrop == nil,
        ui.rendered._backdrop and ("n=" .. #ui.rendered._backdrop) or "nil")

  -- 块应当正好等于画布
  check(name .. " 100vw/100vh = 画布",
        fill and near(fill.box.w, cw) and near(fill.box.h, ch),
        fill and string.format("%.1fx%.1f (画布 %gx%g)",
                              fill.box.w, fill.box.h, cw, ch) or "nil")
end

--=============================================================================
print()
print("=== 2. 反例：designSize != 画布 -> 留边【不】为零（对照） ===")
--=============================================================================

--[[ ★ 这条是"变异测试"：如果实现被改成"永远归零"，
     这里会失败 —— 保证第 1 节测的是真行为，不是恒真。 ]]--
do
  local E = EngineMock.new(PREFABS)
  E.setCanvas(2184, 900)
  _G.game  = E.game
  _G.Color = { FromRGBA = function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
               FromRGB  = function(r,g,b) return {r=r,g=g,b=b} end }
  _G.Enum  = {
    EaseType = { Linear="Linear" },
    CursorEventType = {
      CursorClick="CursorClick", CursorDown="CursorDown", CursorUp="CursorUp",
      CursorEnter="CursorEnter", CursorExit="CursorExit",
      CursorBeginDrag="CursorBeginDrag", CursorDrag="CursorDrag",
      CursorEndDrag="CursorEndDrag",
    },
    ImageSource = { StaticReference = "Enum.ImageSource.StaticReference" },
    TextHorizontalAlignment = { Left="L", Middle="C", Right="R" },
    TextVerticalAlignment   = { Top="T", Middle="M", Bottom="B" },
  }
  util.resetCanvasCache()
  local webui = require('webui')
  local root = E.makeControl("container", nil)
  root.name = "Root"
  _G.script = { object = root }

  -- design 1600x900 放进 2184x900 画布 -> 必须留边 292
  local ui = webui.new{
    root = root, prefabs = PREFABS, handlers = {},
    designSize = { 1600, 900 }, fit = "letterbox", fitBg = "#000000",
  }
  ui:setHTML([[<div class="p"></div>]])
  ui:addCSS([[.p { width: 100px; height: 100px; background-color: #888888; }]])
  ui:flush()

  local f = ui.rendered.fit
  check("1600 设计 @ 2184 画布 -> 留边 292", near(f.offsetX, 292, 1),
        string.format("offX=%.1f", f.offsetX))
  check("此时【会】建留边条", ui.rendered._backdrop ~= nil,
        ui.rendered._backdrop and ("n=" .. #ui.rendered._backdrop) or "nil")

  --[[ ★★ 数值意图：这正是"两侧没填充"的算术来源 ——
       画布比设计宽 584，居中后左右各 292。 ]]--
  check("留边 = (画布-设计)/2 = 292",
        near((2184 - 1600) / 2, f.offsetX, 1), "")
end

--=============================================================================
print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
os.exit(fail == 0 and 0 or 1)