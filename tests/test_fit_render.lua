-- 测试多屏幕比例适配的【渲染集成】
--
-- ★ test_fit.lua 验的是纯算法（webui_fit）；本套件验的是：
--   适配参数是否真的写进了控件字段、留边底色是否建出来了、
--   以及 16:9 上是否保持向后兼容（不产生任何多余控件）。
--
-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
             .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')
local util       = require('webui_util')

-- ★ 必须包含 image：.stage 有 overflow:hidden -> chooseKind 会选 image
local PREFABS = { container=1073741933, textbox=1073741934,
                  button=1073741935, image=1073741936 }

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-36s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-36s %s", name, detail or "")) end
end
local function near(a, b, eps) return math.abs((a or 0) - (b or 0)) <= (eps or 0.01) end

--[[ 取控件上的【引擎字段】。

     ⚠️ engine_mock 里控件是个 proxy，字段要通过 E.dataOf(ctrl).fields 读。
        直接 proxy.sizeDeltaX 也能读（proxy 有 __index 转发），
        但这里统一走 dataOf，断言失败时能区分
        "没建控件" 和 "建了但字段没写"。

     _MOCK 由 setup() 设置。 ]]--
local _MOCK = nil
local function fld(c, name)
  if not c or not _MOCK then return nil end
  local rec = _MOCK.dataOf(c)
  return rec and rec.fields and rec.fields[name]
end

--[[ 建一套干净的引擎环境 + 一个 webui 实例。

     canvasW/H 决定画布；designSize 决定页面逻辑分辨率。 ]]--
local function setup(canvasW, canvasH, opts)
  opts = opts or {}
  local E = EngineMock.new(PREFABS)
  E.setCanvas(canvasW, canvasH)

  _G.game  = E.game
  _G.Color = { FromRGBA = function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
               FromRGB  = function(r,g,b) return {r=r,g=g,b=b} end }
  --[[ ★ Enum 必须照【真机形态】造（见 tests/enum_kit.lua 的教训）：

       Enum.TextVerticalAlignment.Middle  是子表 ✅
       Enum.TextVerticalAlignmentMiddle   扁平名是 nil ❌（真机如此）

     照文档写死扁平名会让垂直对齐静默失效。 ]]--
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
  _MOCK = E        -- ★ fld() 用它读字段

  local webui = require('webui')
  local root = E.makeControl("container", nil)
  root.name = "Root"
  _G.script = { object = root }

  local newOpts = {
    root = root, prefabs = PREFABS, handlers = {},
    -- ★ 注意：opts.designSize = false 表示"显式不传"（测向后兼容）
    designSize = opts.designSize or nil,
    fit    = opts.fit,
    fitBg  = opts.fitBg,
  }
  local ui = webui.new(newOpts)

  ui:setHTML([[
    <div class="stage">
      <div class="scene">
        <div class="score">HI 00000</div>
      </div>
    </div>
  ]])
  ui:addCSS([[
    .stage { width: 1600px; height: 900px; overflow: hidden; }
    .scene { width: 1600px; height: 900px; background-color: #f7f7f7; }
    .score { position: absolute; left: 1080px; top: 60px;
             width: 440px; height: 38px; font-size: 18px;
             color: #535353; background-color: #f7f7f7; }
  ]])
  ui:flush()

  -- 取 stage 控件（DOM 第一个元素的控件）
  local doc = ui.doc
  local stageNode = doc.children[1]
  local entry = ui.rendered.live[stageNode]

  return E, ui, stageNode, entry and entry.control
end

--=============================================================================
print("=== 1. 16:9 向后兼容：不缩放、不产生留边控件 ===")
--=============================================================================

do
  -- 不传 designSize（旧用法）
  local E, ui, node, ctrl = setup(1600, 900, { designSize = false })
  check("无 designSize 时 fit 为 nil", ui.rendered.fit == nil, "")
  local d0 = { sizeDeltaX = fld(ctrl, "sizeDeltaX"), sizeDeltaY = fld(ctrl, "sizeDeltaY") }
  check("stage 尺寸保持 1600x900",
        near(d0.sizeDeltaX, 1600) and near(d0.sizeDeltaY, 900),
        string.format("%sx%s", tostring(d0.sizeDeltaX), tostring(d0.sizeDeltaY)))

  -- 传了 designSize 但正好 16:9：k=1 无留边 -> 也不该建留边控件
  local E2, ui2, node2, ctrl2 = setup(1600, 900, { designSize = {1600, 900} })
  check("16:9 k=1", near(ui2.rendered.fit.k, 1), string.format("k=%.4f", ui2.rendered.fit.k))
  check("16:9 无留边底色控件", ui2.rendered._backdrop == nil, "")
  check("16:9 stage 尺寸不变",
        near(fld(ctrl2, "sizeDeltaX"), 1600) and near(fld(ctrl2, "sizeDeltaY"), 900),
        string.format("%sx%s", tostring(fld(ctrl2, "sizeDeltaX")),
                               tostring(fld(ctrl2, "sizeDeltaY"))))
end

--=============================================================================
print()
print("=== 2. 16:10 (2560x1600)：等比放大 + 上下留边 ===")
--=============================================================================

do
  local E, ui, node, ctrl = setup(2560, 1600, { designSize = {1600, 900}, fitBg = "#f7f7f7" })
  local f = ui.rendered.fit

  check("k = 1.6", near(f.k, 1.6), string.format("k=%.4f", f.k))
  check("上下各留 80", near(f.offsetY, 80) and near(f.offsetX, 0),
        string.format("ox=%.1f oy=%.1f", f.offsetX, f.offsetY))

  -- ★ stage 实际尺寸应该是 1600*1.6 = 2560 宽
  local dw, dh = fld(ctrl, "sizeDeltaX"), fld(ctrl, "sizeDeltaY")
  check("stage 宽度放大到 2560", near(dw, 2560), string.format("w=%s", tostring(dw)))
  check("stage 高度放大到 1440", near(dh, 1440), string.format("h=%s", tostring(dh)))

  -- ★ 垂直位置：内容中心应在画布中心
  --   stage 中心 y = 80 + 1440/2 = 800；画布中心 800 -> dy 应为 0
  local dyv = fld(ctrl, "anchoredPositionY")
  check("stage 垂直居中 dy=0", near(dyv, 0, 0.5), string.format("dy=%s", tostring(dyv)))

  -- ★ 留边底色：应该建出 2 条（上下）
  local bd = ui.rendered._backdrop
  check("建出留边底色控件", bd ~= nil and #bd == 2, bd and ("n=" .. #bd) or "nil")
  if bd and #bd == 2 then
    local tw, th = fld(bd[1], "sizeDeltaX"), fld(bd[1], "sizeDeltaY")
    check("上条 2560x80", near(tw, 2560) and near(th, 80),
          string.format("%sx%s", tostring(tw), tostring(th)))
    local bw2, bh2 = fld(bd[2], "sizeDeltaX"), fld(bd[2], "sizeDeltaY")
    check("下条 2560x80", near(bw2, 2560) and near(bh2, 80),
          string.format("%sx%s", tostring(bw2), tostring(bh2)))

    -- 上条中心 y = 40 -> 引擎 dy = 800 - 40 = 760
    local toy = fld(bd[1], "anchoredPositionY")
    check("上条位置 dy=760", near(toy, 760, 0.5), string.format("dy=%s", tostring(toy)))
    -- 下条中心 y = 80+1440+40 = 1560 -> dy = 800 - 1560 = -760
    local boy = fld(bd[2], "anchoredPositionY")
    check("下条位置 dy=-760", near(boy, -760, 0.5), string.format("dy=%s", tostring(boy)))
  end
end

--=============================================================================
print()
print("=== 3. 4:3 (1920x1440)：留边更大、k=1.2 ===")
--=============================================================================

do
  local E, ui, node, ctrl = setup(1920, 1440, { designSize = {1600, 900}, fitBg = "#f7f7f7" })
  local f = ui.rendered.fit

  check("k = 1.2", near(f.k, 1.2), string.format("k=%.4f", f.k))
  check("上下各留 180", near(f.offsetY, 180), string.format("oy=%.1f", f.offsetY))

  local dw2, dh2 = fld(ctrl, "sizeDeltaX"), fld(ctrl, "sizeDeltaY")
  check("stage 1920x1080", near(dw2, 1920) and near(dh2, 1080),
        string.format("%sx%s", tostring(dw2), tostring(dh2)))

  local bd = ui.rendered._backdrop
  check("4:3 建出 2 条留边", bd ~= nil and #bd == 2, bd and ("n=" .. #bd) or "nil")
end

--=============================================================================
print()
print("=== 4. 21:9 (3440x1440)：左右留边 ===")
--=============================================================================

do
  local E, ui, node, ctrl = setup(3440, 1440, { designSize = {1600, 900}, fitBg = "#f7f7f7" })
  local f = ui.rendered.fit

  check("k = 1.6", near(f.k, 1.6), string.format("k=%.4f", f.k))
  check("左右各留 440", near(f.offsetX, 440) and near(f.offsetY, 0),
        string.format("ox=%.1f oy=%.1f", f.offsetX, f.offsetY))

  local bd = ui.rendered._backdrop
  check("21:9 建出 2 条留边（左右）", bd ~= nil and #bd == 2, bd and ("n=" .. #bd) or "nil")
  if bd and #bd == 2 then
    local lw, lh = fld(bd[1], "sizeDeltaX"), fld(bd[1], "sizeDeltaY")
    check("左条 440x1440", near(lw, 440) and near(lh, 1440),
          string.format("%sx%s", tostring(lw), tostring(lh)))
    -- 左条中心 x = 220 -> dx = 220 - 1720 = -1500
    local lx = fld(bd[1], "anchoredPositionX")
    check("左条位置 dx=-1500", near(lx, -1500, 0.5), string.format("dx=%s", tostring(lx)))
  end
end

--=============================================================================
print()
print("=== 5. 留边底色用页面背景色 ===")
--=============================================================================

do
  local E, ui, node, ctrl = setup(2560, 1600, {
    designSize = {1600, 900}, fitBg = "#f7f7f7",
  })
  local bd = ui.rendered._backdrop
  check("留边控件已建", bd ~= nil and #bd >= 1, "")
  if bd and bd[1] then
    local c = fld(bd[1], "bgColor")
    check("颜色 = #f7f7f7",
          c and c.r == 247 and c.g == 247 and c.b == 247,
          c and string.format("rgb(%d,%d,%d)", c.r, c.g, c.b) or "nil")
  end

  -- 不传 fitBg：不该建留边控件（用户选择让游戏画面露出）
  local E2, ui2 = setup(2560, 1600, { designSize = {1600, 900} })
  check("不传 fitBg 则不建留边", ui2.rendered._backdrop == nil, "")
end

--=============================================================================
print()
print("=== 6. 换分辨率后重算（画布尺寸变化） ===")
--=============================================================================

do
  local E, ui, node, ctrl = setup(2560, 1600, {
    designSize = {1600, 900}, fitBg = "#f7f7f7",
  })
  check("初始 k=1.6", near(ui.rendered.fit.k, 1.6), "")

  -- ★ 模拟窗口化 / 换屏：画布变成 1920x1440
  E.setCanvas(1920, 1440)
  util.resetCanvasCache()        -- 应用层应调用（或由 refreshCanvasIfChanged 处理）
  ui:flush()

  check("换屏后 k 重算为 1.2", near(ui.rendered.fit.k, 1.2),
        string.format("k=%.4f", ui.rendered.fit.k))
  check("换屏后 stage 尺寸更新",
        near(fld(ctrl, "sizeDeltaX"), 1920) and near(fld(ctrl, "sizeDeltaY"), 1080),
        string.format("%sx%s", tostring(fld(ctrl, "sizeDeltaX")),
                               tostring(fld(ctrl, "sizeDeltaY"))))
end

--=============================================================================
print()
print("=== 7. 光标坐标反变换 ===")
--=============================================================================

do
  local E, ui = setup(2560, 1600, { designSize = {1600, 900}, fitBg = "#f7f7f7" })
  local event = require('webui_event')
  local f = ui.rendered.fit

  -- 画布坐标 (1280, 1600-800=800) -> 左上原点 (1280, 800)
  --   -> 设计坐标 ((1280-0)/1.6, (800-80)/1.6) = (800, 450)
  local x, y = event.toLocal(1280, 800, f)
  check("16:10 光标反变换到设计坐标",
        near(x, 800, 0.5) and near(y, 450, 0.5),
        string.format("%.1f,%.1f", x, y))

  -- 不传 fit：退化成只有 Y 翻转（旧行为）
  local x2, y2 = event.toLocal(1280, 800, nil)
  check("不传 fit 时行为不变（仅 Y 翻转）",
        near(x2, 1280) and near(y2, 800),
        string.format("%.1f,%.1f", x2, y2))
end

--=============================================================================
print()
print("=== 8. webui.mount 必须透传适配参数 ===")
--=============================================================================

--[[ ★★ 回归：mount 曾经【丢弃】designSize / fit / fitBg ——
       用户按文档传了却完全不生效，而且不报错（静默失效）。
       这里守住这条透传链。 ]]--
do
  local E = EngineMock.new(PREFABS)
  E.setCanvas(2560, 1600)

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
  _MOCK = E

  local root = E.makeControl("container", nil)
  root.name = "Root"
  E.setRoots({ root })
  _G.script = { object = root }

  local webui = require('webui')
  local app = webui.mount{
    root       = "Root",
    prefabs    = PREFABS,
    designSize = { 1600, 900 },
    fit        = "letterbox",
    fitBg      = "#f7f7f7",
    html       = [[<div class="stage">X</div>]],
    css        = [[.stage { width: 1600px; height: 900px;
                            background-color: #f7f7f7; }]],
    loop       = false,
  }

  check("mount 返回了 ui", app ~= nil and app.ui ~= nil, "")
  if app and app.ui then
    local r = app.ui.rendered
    check("mount 透传了 designSize（fit 非空）", r ~= nil and r.fit ~= nil, "")
    if r and r.fit then
      check("mount 下 k = 1.6", near(r.fit.k, 1.6), string.format("k=%.4f", r.fit.k))
      check("mount 下留边 80", near(r.fit.offsetY, 80),
            string.format("oy=%.1f", r.fit.offsetY))
    end
    check("mount 透传了 fitBg（留边已建）",
          r ~= nil and r._backdrop ~= nil, "")
  end
end

--=============================================================================
print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
os.exit(fail == 0 and 0 or 1)