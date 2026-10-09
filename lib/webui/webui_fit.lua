--[[============================================================================
  webui/fit.lua  ——  多屏幕比例适配（等比缩放 + 留边）

  ============================================================================
  为什么需要这个模块
  ============================================================================

  页面是按固定逻辑分辨率（设计尺寸）写的，比如 1600x900（16:9）。
  真机屏幕比例可能是：

      16:9   2560x1440   -> 正好铺满
      16:10  2560x1600   -> 上下留边
      4:3    1920x1440   -> 上下留边
      21:9   3440x1440   -> 左右留边

  ★★ 绝对不能用"拉伸铺满"（宽高各自撑满）：像素精灵会被非等比压扁，
     8px 的格子变成 7.3px，接缝和内缩立刻回来（见 引擎能力与限制.md）。
     必须【等比缩放 + 留边】。

  ============================================================================
  算法
  ============================================================================

      k = min(canvasW / designW, canvasH / designH)      -- 取小者，保证装得下
      scaledW = designW * k
      scaledH = designH * k
      offsetX = (canvasW - scaledW) / 2                  -- 居中
      offsetY = (canvasH - scaledH) / 2

  | 屏幕       | 设计尺寸  | k              | 缩放后    | 留边          |
  |-----------|----------|----------------|----------|---------------|
  | 2560x1440 | 1600x900 | 1.600          | 2560x1440| 无            |
  | 2560x1600 | 1600x900 | 1.600          | 2560x1440| 上下各 80     |
  | 1920x1440 | 1600x900 | 1.200          | 1920x1080| 上下各 180    |
  | 3440x1440 | 1600x900 | 1.600          | 2560x1440| 左右各 440    |

  ★ 采用【任意倍】而非整数倍：整数倍在 2560x1440 上 k 会掉到 1，
    画面缩成居中小窗，视觉代价不可接受。任意倍下像素精灵有轻微采样，
    但不失真、不出接缝，优于拉伸变形。

  ============================================================================
  用法
  ============================================================================

      local fit = require('webui_fit')

      local f = fit.compute(1600, 900, canvasW, canvasH)
      -- f = { k=1.6, offsetX=0, offsetY=80, scaledW=2560, scaledH=1440 }

      -- 光标坐标反变换（缩放 + 偏移）
      local x, y = fit.toDesign(f, uiX, uiY)

  ⚠️ 本模块是纯计算，不碰控件。渲染层负责把 k / offset 写进控件字段。
==============================================================================]]

local util = require('webui_util')

local F = {}

--=============================================================================
-- 计算
--=============================================================================

--[[ 算出适配参数。

     designW/designH: 页面写的逻辑分辨率（如 1600x900）
     canvasW/canvasH: 真实画布尺寸（game.GetUICanvasSize()）

     返回：
       k        缩放系数（等比，任意倍）
       offsetX  缩放后内容左边距（画布坐标）
       offsetY  缩放后内容上边距（画布坐标）
       scaledW  缩放后内容宽
       scaledH  缩放后内容高
     ]]--
function F.compute(designW, designH, canvasW, canvasH)
  designW = util.toNumber(designW) or 1600
  designH = util.toNumber(designH) or 900
  canvasW = util.toNumber(canvasW) or 1600
  canvasH = util.toNumber(canvasH) or 900

  if designW <= 0 then designW = 1600 end
  if designH <= 0 then designH = 900 end
  if canvasW <= 0 then canvasW = designW end
  if canvasH <= 0 then canvasH = designH end

  -- 等比：取较小的那个比例，保证内容完整装进画布（letterbox）
  local kx = canvasW / designW
  local ky = canvasH / designH
  local k = kx < ky and kx or ky

  if not util.isFinite(k) or k <= 0 then k = 1 end

  local scaledW = designW * k
  local scaledH = designH * k

  -- 居中
  local offsetX = (canvasW - scaledW) / 2
  local offsetY = (canvasH - scaledH) / 2

  return {
    k        = k,
    offsetX  = offsetX,
    offsetY  = offsetY,
    scaledW  = scaledW,
    scaledH  = scaledH,
    designW  = designW,
    designH  = designH,
    canvasW  = canvasW,
    canvasH  = canvasH,
  }
end

--[[ 判断两组适配参数是否等价（避免每帧重复写控件字段）]]--
function F.same(a, b)
  if not a or not b then return false end
  local EPS = 0.01
  return math.abs(a.k - b.k) < EPS
     and math.abs(a.offsetX - b.offsetX) < EPS
     and math.abs(a.offsetY - b.offsetY) < EPS
end

--=============================================================================
-- 坐标变换
--
-- ⚠️ 这是适配最容易漏掉的一环：
--    画面被 scale 之后，引擎给的光标坐标是【屏幕坐标】，
--    而布局盒子的坐标是【设计坐标】。命中检测必须先把光标
--    反变换回设计坐标，否则缩放后点击全部错位。
--
--    反变换：design = (screen - offset) / k
--=============================================================================

--[[ 屏幕/画布坐标 -> 设计坐标

     输入是库内部约定（左上原点、Y 向下）的坐标。]]--
function F.toDesign(f, x, y)
  if not f then return x, y end
  local k = f.k
  if not k or k <= 0 then k = 1 end
  return (x - f.offsetX) / k, (y - f.offsetY) / k
end

--[[ 设计坐标 -> 屏幕/画布坐标（反向）]]--
function F.toScreen(f, x, y)
  if not f then return x, y end
  local k = f.k or 1
  return x * k + f.offsetX, y * k + f.offsetY
end

--[[ 光标是否落在内容区（留边区内不算命中）]]--
function F.insideContent(f, x, y)
  if not f then return true end
  if x < f.offsetX or x > f.offsetX + f.scaledW then return false end
  if y < f.offsetY or y > f.offsetY + f.scaledH then return false end
  return true
end

--=============================================================================
-- 诊断
--=============================================================================

function F.describe(f)
  if not f then return "fit(nil)" end
  return string.format(
    "fit(design %gx%g -> canvas %gx%g, k=%.4f, scaled %.1fx%.1f, offset %.1f,%.1f)",
    f.designW, f.designH, f.canvasW, f.canvasH,
    f.k, f.scaledW, f.scaledH, f.offsetX, f.offsetY)
end

return F