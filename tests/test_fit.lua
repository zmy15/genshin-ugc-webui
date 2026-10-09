-- 测试多屏幕比例适配（等比缩放 + 留边）
--
-- ★ 纯数值验算：不依赖引擎，把 webui_fit 的算法钉死。
--   任何改动导致比例算错都会在这里立刻暴露。
--
-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
             .. _root .. "/tools/?.lua;" .. package.path

local fit = require('webui_fit')
local util = require('webui_util')

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-34s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-34s %s", name, detail or "")) end
end

--[[ 近似相等（浮点容差）]]--
local function near(a, b, eps)
  eps = eps or 0.01
  return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= eps
end

local DW, DH = 1600, 900    -- 设计尺寸（16:9）

--=============================================================================
print("=== 1. 各屏幕比例的核心数值 ===")
--=============================================================================

--[[ 用一批真实屏幕尺寸验算。
     期望值都是手算出来的，写在这里当"黄金值"。

     算法：k = min(cw/dw, ch/dh)
           scaled = design * k
           offset = (canvas - scaled) / 2
]]--
local CASES = {
  -- 名称,            画布 w, 画布 h, 期望 k,  期望留边X, 期望留边Y
  { "16:9  2560x1440", 2560, 1440, 1.600,   0,     0    },
  { "16:10 2560x1600", 2560, 1600, 1.600,   0,    80    },
  { "16:10 1920x1200", 1920, 1200, 1.200,   0,    60    },
  { "4:3   1920x1440", 1920, 1440, 1.200,   0,   180    },
  { "4:3   1600x1200", 1600, 1200, 1.000,   0,   150    },
  { "21:9  3440x1440", 3440, 1440, 1.600, 440,     0    },
  { "3:2   2160x1440", 2160, 1440, 1.350,   0,   112.5  },
}

for _, c in ipairs(CASES) do
  local name, cw, ch, ek, eox, eoy = c[1], c[2], c[3], c[4], c[5], c[6]
  local f = fit.compute(DW, DH, cw, ch)

  check(name .. " k", near(f.k, ek),
        string.format("k=%.4f (期望 %.4f)", f.k, ek))
  check(name .. " 留边X", near(f.offsetX, eox),
        string.format("ox=%.2f (期望 %.2f)", f.offsetX, eox))
  check(name .. " 留边Y", near(f.offsetY, eoy),
        string.format("oy=%.2f (期望 %.2f)", f.offsetY, eoy))

  -- 不变量：缩放后内容必须【完整装进】画布，且至少有一边贴边
  local fitsW = f.scaledW <= cw + 0.01
  local fitsH = f.scaledH <= ch + 0.01
  local touchW = near(f.scaledW, cw, 0.01)
  local touchH = near(f.scaledH, ch, 0.01)
  check(name .. " 装得下且贴边", fitsW and fitsH and (touchW or touchH),
        string.format("%.1fx%.1f in %dx%d", f.scaledW, f.scaledH, cw, ch))

  -- 不变量：留边不能是负的
  check(name .. " 留边非负", f.offsetX >= -0.01 and f.offsetY >= -0.01, "")
end

--=============================================================================
print()
print("=== 2. 等比性（绝不允许拉伸） ===")
--=============================================================================

--[[ ★★ 最关键的不变量：
     缩放后宽高比必须与设计宽高比【完全一致】。
     一旦用了"宽高各自撑满"，这个比值就会变 —— 像素精灵被压扁。 ]]--
local ratios = {
  { 2560, 1440 }, { 2560, 1600 }, { 1920, 1440 },
  { 1600, 1200 }, { 3440, 1440 }, { 2160, 1440 },
}
local designRatio = DW / DH
for _, r in ipairs(ratios) do
  local f = fit.compute(DW, DH, r[1], r[2])
  local outRatio = f.scaledW / f.scaledH
  check(string.format("等比 %dx%d", r[1], r[2]),
        near(outRatio, designRatio, 0.0001),
        string.format("比值 %.5f (设计 %.5f)", outRatio, designRatio))
end

--=============================================================================
print()
print("=== 3. 坐标反变换（命中检测的关键） ===")
--=============================================================================

--[[ 画布坐标 -> 设计坐标：design = (canvas - offset) / k

     这是点击正确性的数学基础。取 16:10 (2560x1600)：
       k = 1.6, offsetY = 80
       内容区中心 画布(1280, 800) -> 设计(800, 450)  ← 设计画布中心
]]--
do
  local f = fit.compute(DW, DH, 2560, 1600)

  -- 内容区左上角：画布 (0,80) -> 设计 (0,0)
  local x, y = fit.toDesign(f, 0, 80)
  check("16:10 内容左上 -> 设计原点", near(x, 0) and near(y, 0),
        string.format("%.2f,%.2f", x, y))

  -- 内容区中心 -> 设计中心
  x, y = fit.toDesign(f, 1280, 800)
  check("16:10 画布中心 -> 设计中心", near(x, 800) and near(y, 450),
        string.format("%.2f,%.2f", x, y))

  -- 内容区右下角：画布 (2560, 1520) -> 设计 (1600, 900)
  x, y = fit.toDesign(f, 2560, 1520)
  check("16:10 内容右下 -> 设计右下", near(x, 1600) and near(y, 900),
        string.format("%.2f,%.2f", x, y))

  -- 往返一致性：screen -> design -> screen
  local sx, sy = fit.toScreen(f, 800, 450)
  check("16:10 往返一致", near(sx, 1280) and near(sy, 800),
        string.format("%.2f,%.2f", sx, sy))

  -- insideContent：留边区内不算命中
  check("16:10 留边内(顶部)不算命中", fit.insideContent(f, 1280, 40) == false, "")
  check("16:10 内容区内算命中",       fit.insideContent(f, 1280, 800) == true,  "")
end

--[[ 4:3 上的反变换：
       k = 1.2, offsetY = 180
       画布(960, 720) -> 设计(800, 450) ]]--
do
  local f = fit.compute(DW, DH, 1920, 1440)
  local x, y = fit.toDesign(f, 960, 720)
  check("4:3 画布中心 -> 设计中心", near(x, 800) and near(y, 450),
        string.format("%.2f,%.2f", x, y))
end

--=============================================================================
print()
print("=== 4. 边界与异常输入 ===")
--=============================================================================

do
  -- 画布比设计小（窗口化）：k < 1，仍然等比装得下
  local f = fit.compute(DW, DH, 800, 600)
  check("小画布 k<1 等比", near(f.k, 0.5) and near(f.scaledW, 800) and near(f.scaledH, 450),
        string.format("k=%.2f %.0fx%.0f", f.k, f.scaledW, f.scaledH))
  check("小画布留边非负", f.offsetY >= 0, string.format("oy=%.1f", f.offsetY))

  -- 画布 == 设计：k=1，无留边
  f = fit.compute(DW, DH, DW, DH)
  check("完全一致 k=1 无留边",
        near(f.k, 1) and near(f.offsetX, 0) and near(f.offsetY, 0), "")

  -- nil / 0 / 负数都不该崩，且给出合理兜底
  f = fit.compute(nil, nil, nil, nil)
  check("nil 输入不崩且有兜底", type(f) == "table" and f.k > 0,
        string.format("k=%.2f", f.k))

  f = fit.compute(0, 0, 0, 0)
  check("全 0 输入不除零", type(f) == "table" and util.isFinite(f.k),
        string.format("k=%.2f", f.k))

  f = fit.compute(DW, DH, -100, -100)
  check("负数画布不产生 NaN", util.isFinite(f.k) and util.isFinite(f.offsetX), "")
end

--=============================================================================
print()
print("=== 5. 与 util.canvasSize 的契约 ===")
--=============================================================================

--[[ util.canvasSize(forceRefresh) 必须能刷新 —— 这是多分辨率适配的前提。
     原来"首次取值永久锁死"，换分辨率后布局全错。 ]]--
do
  -- 无 game 全局时必须走兜底 1600x900，不能崩
  util.resetCanvasCache()
  local w, h = util.canvasSize()
  check("无引擎时兜底 1600x900", w == 1600 and h == 900,
        string.format("%gx%g", w, h))

  -- forceRefresh 必须真的重新取（用假的 game 验证）
  local calls = 0
  local fakeW, fakeH = 2560, 1600
  _G.game = {
    GetUICanvasSize = function() calls = calls + 1; return fakeW, fakeH end,
  }

  util.resetCanvasCache()
  local w1, h1 = util.canvasSize()
  check("首次取到引擎值", w1 == 2560 and h1 == 1600, string.format("%gx%g", w1, h1))

  -- 走缓存：不该再问引擎
  local before = calls
  util.canvasSize()
  check("默认走缓存不重复问", calls == before, string.format("calls=%d", calls - before))

  -- ★ 模拟换分辨率：不刷新的话会拿到旧值（这正是原来的 bug）
  fakeW, fakeH = 1920, 1440
  local w2, h2 = util.canvasSize()
  check("不刷新仍返回旧值（缓存生效）", w2 == 2560 and h2 == 1600,
        string.format("%gx%g", w2, h2))

  -- ★ forceRefresh 必须拿到新值
  local w3, h3 = util.canvasSize(true)
  check("forceRefresh 取到新值", w3 == 1920 and h3 == 1440,
        string.format("%gx%g", w3, h3))

  -- refreshCanvasIfChanged：尺寸变了才返回 true
  fakeW, fakeH = 1280, 720
  local changed, w4, h4 = util.refreshCanvasIfChanged()
  check("尺寸变化被检测到", changed == true and w4 == 1280 and h4 == 720,
        string.format("changed=%s %gx%g", tostring(changed), w4, h4))

  -- 尺寸没变：不该报变化
  local changed2 = util.refreshCanvasIfChanged()
  check("尺寸未变不报变化", changed2 == false, "")

  -- 浮点抖动（真机给 1599.9998）不该触发重算
  fakeW, fakeH = 1280.2, 720.2
  local changed3 = util.refreshCanvasIfChanged()
  check("浮点抖动不算变化", changed3 == false, "")

  _G.game = nil
  util.resetCanvasCache()
end

--=============================================================================
print()
print("=== 6. 与设计文档中的屏幕对照表一致 ===")
--=============================================================================

--[[ 文档（引擎能力与限制.md）里写的期望值，逐条核对。
     这些数字是给用户看的，代码算错就会误导。 ]]--
do
  local doc = {
    { "16:9 2560x1440 -> 铺满",     2560, 1440, 2560, 1440, 0,   0   },
    { "16:10 2560x1600 -> 上下80",  2560, 1600, 2560, 1440, 0,   80  },
    { "4:3 1920x1440 -> 上下180",   1920, 1440, 1920, 1080, 0,   180 },
    { "21:9 3440x1440 -> 左右440",  3440, 1440, 2560, 1440, 440, 0   },
  }
  for _, d in ipairs(doc) do
    local f = fit.compute(DW, DH, d[2], d[3])
    local ok = near(f.scaledW, d[4]) and near(f.scaledH, d[5])
           and near(f.offsetX, d[6]) and near(f.offsetY, d[7])
    check(d[1], ok, string.format("%.0fx%.0f offset %.0f,%.0f",
          f.scaledW, f.scaledH, f.offsetX, f.offsetY))
  end
end

--=============================================================================
print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
os.exit(fail == 0 and 0 or 1)