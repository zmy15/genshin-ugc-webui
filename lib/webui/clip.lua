--[[============================================================================
  webui/clip.lua  ——  图片控件：裁剪 / 换图 / 染色

  ★ 本模块封装 R16/R17 真机验证的图片能力：

    1. 矩形裁剪（overflow:hidden）
       图片控件 + 【矩形图】当遮罩 + enableMask = true
       -> 塞进去的子控件，超出部分被裁掉
       ★ R17 实证：子块 400x200 进父 200x100，实测被裁成 285x143

    2. 任意形状裁剪（border-radius:50% 等）
       遮罩形状 = 图片的 alpha
       ★ R16/R17 实证：圆图裁出正圆、三角图裁出三角、矩形图裁出矩形

    3. 运行时换图
       img:SetImage(Enum.ImageSource.StaticReference, 图片ID)
       ★ R16 实证：6 种形状切换，5/6 读回确认改变

    4. 染色
       img.imageColor = Color.FromRGBA(...)
       ★ 渐变图（白->灰）染色后保留明暗层次

  ⚠️ 关键约束（真机实测）：
     - 图片控件有 imageColor / enableMask / reverseMaskArea
     - 【没有】bgColor / text（字段按类型封死，写会静默失败）
     - 圆角 border-radius 字段【不存在】（6 个候选字段写入全部失败）
       -> 圆角只能靠"圆图/圆角图当遮罩"实现
     - Enum 顶层 pairs() 遍历为空（元表），但 Enum.ImageSource 可直接索引
=============================================================================]]

local C = {}

--=============================================================================
-- 预置图片资源（用户已建，见 ugc_out/引擎能力与限制.md §6.2）
--
--   渐变设计（白->灰），专为 imageColor 染色准备。
--=============================================================================

C.SHAPES = {
  SQUARE    = 100001,   -- 正方形：矩形裁剪遮罩 / 底板
  CIRCLE    = 100002,   -- 圆形：头像框 / 圆形裁剪
  TRIANGLE  = 100003,   -- 三角形：方向指示
  STAR4     = 100004,   -- 四角星
  STAR5     = 100005,   -- 五角星：评级
  RING      = 100006,   -- 圆环：技能环 / 进度环底
}

--=============================================================================
-- 运行时探测 Enum.ImageSource（★ 不硬编码枚举名）
--
--   教训（R16）：照文档写 Enum.ImageSource.ImageSourceStaticReference
--   得到 nil；真名是 Enum.ImageSource.StaticReference。
--   所以这里做容错探测，避免库在真机上因枚举名不符而失效。
--=============================================================================

local cachedSource = nil
local probedSource = false

--[[ 取 "静态引用" 的 ImageSource 枚举值。

     多路容错：
       ① Enum.ImageSource.StaticReference   （R16 确认的真名）
       ② Enum.ImageSourceImageStaticReference（文档写法，可能不存在）
       ③ 任意含 "static" 的键
       ④ 都不行则返回 nil（调用方退化处理）
]]--
function C.imageSource()
  if probedSource then return cachedSource end
  probedSource = true

  if type(Enum) ~= "table" then return nil end

  local tbl = rawget(Enum, "ImageSource")
  if type(tbl) ~= "table" then return nil end

  -- ① 精确名（真机实测的正确写法）
  local v = rawget(tbl, "StaticReference")
  if v ~= nil then
    cachedSource = v
    return cachedSource
  end

  -- ② 文档写法（可能不存在，仅兜底）
  v = rawget(tbl, "ImageSourceStaticReference")
  if v ~= nil then
    cachedSource = v
    return cachedSource
  end

  -- ③ 模糊匹配含 static 的键
  for k, val in pairs(tbl) do
    if tostring(k):lower():find("static") then
      cachedSource = val
      return cachedSource
    end
  end

  return nil
end

--=============================================================================
-- 设置图片
--=============================================================================

--[[ 给图片控件设置形状图。

     ctrl   图片控件
     shapeId  图片 ID（见 C.SHAPES）
     返回 ok, err

     ★ 用 pcall 包裹：真机上参数错误会抛异常（R16 踩过）。
]]--
function C.setImage(ctrl, shapeId)
  if not ctrl then return false, "ctrl 为 nil" end
  if type(ctrl.SetImage) ~= "function" then
    return false, "该控件没有 SetImage 方法（不是图片控件？）"
  end

  local src = C.imageSource()
  if src == nil then
    return false, "拿不到 Enum.ImageSource 值"
  end

  local ok, err = pcall(function()
    ctrl:SetImage(src, shapeId)
  end)
  return ok, err
end

--=============================================================================
-- 裁剪配置
--=============================================================================

--[[ 把图片控件配成「裁剪容器」。

     opts = {
       shapeId   = 遮罩形状图 ID，默认 SQUARE（矩形裁剪）
       reverse   = 反转遮罩区域，默认 false
       softEdge  = 边缘羽化宽度（可选）
       color     = 染色 {r,g,b,a}（可选）
     }

     ★ 裁剪语义（R17 实证）：
         enableMask = true           -> 按【图片 alpha】裁剪子控件
         reverseMaskArea = false     -> 保留图内，裁掉图外（默认，做 overflow:hidden 用这个）
         reverseMaskArea = true      -> 反转
]]--
function C.asClip(ctrl, opts)
  if not ctrl then return false, "ctrl 为 nil" end
  opts = opts or {}

  local shapeId = opts.shapeId or C.SHAPES.SQUARE

  -- ① 换图
  local ok, err = C.setImage(ctrl, shapeId)
  if not ok then return false, err end

  -- ② 开启遮罩
  local okMask = pcall(function() ctrl.enableMask = true end)
  if not okMask then return false, "enableMask 写入失败" end

  -- ③ 反转区域
  pcall(function() ctrl.reverseMaskArea = opts.reverse and true or false end)

  -- ④ 可选羽化
  if opts.softEdge then
    pcall(function() ctrl.enableSoftEdge = true end)
    pcall(function() ctrl.softEdgeWidthX = opts.softEdge end)
    pcall(function() ctrl.softEdgeWidthY = opts.softEdge end)
  end

  -- ⑤ 可选染色
  if opts.color and type(Color) == "table" and Color.FromRGBA then
    local c = opts.color
    pcall(function()
      ctrl.imageColor = Color.FromRGBA(c.r or 255, c.g or 255, c.b or 255, c.a or 255)
    end)
  end

  return true
end

--[[ 关闭裁剪。]]--
function C.clearClip(ctrl)
  if not ctrl then return end
  pcall(function() ctrl.enableMask = false end)
  pcall(function() ctrl.reverseMaskArea = false end)
end

--=============================================================================
-- 染色
--=============================================================================

--[[ 给图片控件染色。

     ★ 渐变图染色后保留明暗层次，所以传纯色也能得到有立体感的结果。
]]--
function C.tint(ctrl, r, g, b, a)
  if not ctrl then return false end
  if type(Color) ~= "table" or type(Color.FromRGBA) ~= "function" then
    return false
  end
  local ok = pcall(function()
    ctrl.imageColor = Color.FromRGBA(r or 255, g or 255, b or 255, a or 255)
  end)
  return ok
end

--=============================================================================
-- CSS 值 → 形状图映射
--
--   供渲染层把 border-radius / overflow 这类 CSS 属性翻译成遮罩形状。
--=============================================================================

--[[ 由 border-radius 值推断用哪张遮罩图。

     支持：
       "50%" / "9999px" / 大数值  -> 圆形
       其他非零值                  -> 暂用圆形（预置资源里没有圆角矩形图）
       "0" / nil                   -> 无（不裁剪）
]]--
function C.shapeForRadius(radius)
  if radius == nil then return nil end

  local s = tostring(radius)
  if s == "" or s == "0" or s == "0px" or s == "0%" then return nil end

  -- 50% 或很大数值 -> 圆
  if s:find("%%") then
    local n = tonumber(s:match("([%d%.]+)"))
    if n and n >= 50 then return C.SHAPES.CIRCLE end
    return C.SHAPES.CIRCLE   -- 预置资源无圆角矩形，退化为圆
  end

  local n = tonumber(s:match("([%d%.]+)"))
  if n and n > 0 then return C.SHAPES.CIRCLE end
  return nil
end

--[[ 由 overflow 值判断是否需要矩形裁剪。]]--
function C.needsRectClip(overflow)
  local v = tostring(overflow or "visible")
  return (v == "hidden" or v == "scroll" or v == "auto")
end

return C
