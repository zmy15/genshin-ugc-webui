--[[============================================================================
  webui/style.lua  ——  层叠 / 继承 / 计算样式

  流程：
    1. 收集每个元素匹配的规则（含内联样式，视为最高特指度）
    2. 按 特指度 -> 顺序 -> !important 决定胜出值
    3. 处理继承（可继承属性从父节点取）
    4. 填入默认值
    5. 归一化：长度/颜色/关键字转成内部表示

  输出：node.style = {
    display, position, width, height, ...
    _color = {r,g,b,a}, _bgColor = {...}
  }
==============================================================================]]

local css   = require('webui.css')
local color = require('webui.color')
local util  = require('webui.util')
local dom   = require('webui.dom')

local S = {}

--=============================================================================
-- 可继承属性
--=============================================================================

local INHERITED = {
  color = true,
  ["font-size"] = true,
  ["font-weight"] = true,
  ["text-align"] = true,
  ["line-height"] = true,
  visibility = true,
}

--=============================================================================
-- 默认值（按 display 类型区分）
--=============================================================================

local DEFAULTS = {
  -- 盒模型
  display           = "block",
  position          = "static",
  width             = "auto",
  height            = "auto",
  top               = "auto",
  right             = "auto",
  bottom            = "auto",
  left              = "auto",
  margin            = "0",
  ["margin-top"]    = "0",
  ["margin-right"]  = "0",
  ["margin-bottom"] = "0",
  ["margin-left"]   = "0",
  padding           = "0",
  ["padding-top"]   = "0",
  ["padding-right"] = "0",
  ["padding-bottom"]= "0",
  ["padding-left"]  = "0",
  ["box-sizing"]    = "content-box",

  -- 定位锚点（内部扩展，用于百分比宽高）
  ["min-width"]     = "auto",
  ["max-width"]     = "none",
  ["min-height"]    = "auto",
  ["max-height"]    = "none",

  -- 视觉
  color             = "#000000",
  ["background-color"] = "transparent",
  ["background-image"] = "none",
  opacity           = "1",
  visibility        = "visible",
  ["border-radius"] = "0",
  ["border-width"]  = "0",
  ["border-color"]  = "transparent",
  overflow          = "visible",

  -- 文本
  ["font-size"]     = "14px",
  ["font-weight"]   = "normal",
  ["text-align"]    = "left",
  ["vertical-align"]= "middle",
  ["line-height"]   = "1.2",
  ["white-space"]   = "normal",

  -- 布局
  ["flex-direction"] = "row",
  ["flex-wrap"]     = "nowrap",
  ["justify-content"] = "flex-start",
  ["align-items"]   = "stretch",
  ["flex-grow"]     = "0",
  ["flex-shrink"]   = "1",
  ["flex-basis"]    = "auto",
  gap               = "0",
  ["z-index"]       = "auto",

  -- 变换（映射到引擎的 anchoredPosition / localScale / localRotation）
  transform         = "none",
  ["transform-origin"] = "50% 50%",

  -- 过渡
  transition        = "none",
  ["transition-property"] = "",
  ["transition-duration"] = "",
  ["transition-timing-function"] = "",
  ["transition-delay"] = "",
}

--=============================================================================
-- 值归一化
--=============================================================================

--[[ 长度：返回 { n=数值, unit="px"|"%"|"em", auto=bool } ]]--
function S.parseLength(v)
  if type(v) == "number" then return { n = v, unit = "px" } end
  if type(v) ~= "string" then return { n = 0, unit = "px" } end
  local s = util.trim(v):lower()

  if s == "auto" then return { n = 0, unit = "px", auto = true } end
  if s == "none" then return { n = 0, unit = "px", none = true } end

  -- ⚠️ Lua 的 pattern 不支持 "|" 交替，必须分开写
  local n, unit

  -- 百分比
  n, unit = s:match("^([%-%d%.]+)%s*%%$")
  if n then
    return { n = util.toNumber(n) or 0, unit = "%" }
  end

  -- px
  n = s:match("^([%-%d%.]+)px$")
  if n then
    return { n = util.toNumber(n) or 0, unit = "px" }
  end

  -- em / rem
  n = s:match("^([%-%d%.]+)rem$")
  if n then
    return { n = util.toNumber(n) or 0, unit = "em" }
  end
  n = s:match("^([%-%d%.]+)em$")
  if n then
    return { n = util.toNumber(n) or 0, unit = "em" }
  end

  -- 无单位数值
  n = util.toNumber(s)
  if n then return { n = n, unit = "px" } end

  -- 无法解析，当作 0
  return { n = 0, unit = "px" }
end

--[[ 数值（无单位，如 opacity / line-height / z-index）]]--
function S.parseNumber(v, dflt)
  if type(v) == "number" then return v end
  local n = util.toNumber(v)
  if n then return n end
  return dflt
end

--[[ opacity：支持 0-1 与百分比 ]]--
local function parseOpacity(v)
  if type(v) ~= "string" then return 1 end
  local s = util.trim(v)
  if s:sub(-1) == "%" then
    local n = util.toNumber(s:sub(1, -2))
    if n then return util.clamp(n / 100, 0, 1) end
  end
  local n = util.toNumber(s)
  if n then return util.clamp(n, 0, 1) end
  return 1
end

--=============================================================================
-- transform 解析
--
--   支持：translate / translateX / translateY
--         scale / scaleX / scaleY
--         rotate / rotateZ
--         matrix 的 a,b,c,d 部分（可选，暂不实现旋转分量）
--
--   不支持：rotateX / rotateY（引擎二维仿真不渲染三维投影）、skew、perspective
--
--   输出：{ tx, ty, sx, sy, rotZ }
--=============================================================================

--[[ 解析一个长度或百分比，返回 { n, unit } ]]--
local function parseTransformValue(s)
  return S.parseLength(s)
end

function S.parseTransform(v, baseW, baseH, fontSize)
  local out = { tx = 0, ty = 0, sx = 1, sy = 1, rotZ = 0, unsupported = {} }
  if type(v) ~= "string" then return out end

  local s = util.trim(v)
  if s == "" or s == "none" then return out end

  -- 逐个提取函数调用
  for rawName, args in s:gmatch("([%a]+)%s*%(([^%)]*)%)") do
    local fname = rawName:lower()
    -- 拆分参数
    local parts = {}
    for p in args:gmatch("[^,]+") do
      parts[#parts+1] = util.trim(p)
    end

    local function len(str, base)
      local l = parseTransformValue(str)
      if l.unit == "%" then return (base or 0) * l.n / 100 end
      if l.unit == "em" then return l.n * (fontSize or 14) end
      return l.n
    end

    if fname == "translate" then
      out.tx = out.tx + len(parts[1] or "0", baseW)
      out.ty = out.ty + len(parts[2] or "0", baseH)

    elseif fname == "translatex" then
      out.tx = out.tx + len(parts[1] or "0", baseW)

    elseif fname == "translatey" then
      out.ty = out.ty + len(parts[1] or "0", baseH)

    elseif fname == "scale" then
      local a = util.toNumber(parts[1] or "1") or 1
      local b = util.toNumber(parts[2] or parts[1] or "1") or a
      out.sx = out.sx * a
      out.sy = out.sy * b

    elseif fname == "scalex" then
      out.sx = out.sx * (util.toNumber(parts[1] or "1") or 1)

    elseif fname == "scaley" then
      out.sy = out.sy * (util.toNumber(parts[1] or "1") or 1)

    elseif fname == "rotate" or fname == "rotatez" then
      -- 支持 deg / rad / 无单位（按 deg）
      -- ⚠️ toNumber("45deg") 返回 nil，必须先把单位剥掉
      local a = util.trim(parts[1] or "0")
      local n, unit
      n, unit = a:match("^([%-%d%.]+)%s*(%a*)$")
      n = util.toNumber(n) or 0
      unit = (unit or ""):lower()
      if unit == "rad" then
        out.rotZ = out.rotZ + n * 180 / math.pi
      elseif unit == "turn" then
        out.rotZ = out.rotZ + n * 360
      elseif unit == "grad" then
        out.rotZ = out.rotZ + n * 0.9
      else
        -- deg 或无单位
        out.rotZ = out.rotZ + n
      end

    elseif fname == "rotatex" or fname == "rotatey"
        or fname == "skew" or fname == "skewx" or fname == "skewy"
        or fname == "perspective" or fname == "matrix" or fname == "matrix3d" then
      -- 引擎不支持：记下来，便于诊断
      out.unsupported[#out.unsupported + 1] = fname
    end
  end

  return out
end

--=============================================================================
-- 简写属性展开
--=============================================================================

--[[ margin: a b c d -> 四个方向 ]]--
local function expandBox(decls, base)
  local shorthand = decls[base]
  if not shorthand then return end
  local parts = {}
  for p in util.trim(shorthand.value):gmatch("[^%s]+") do
    parts[#parts + 1] = p
  end
  if #parts == 0 then return end

  local t, r, b, l
  if #parts == 1 then
    t, r, b, l = parts[1], parts[1], parts[1], parts[1]
  elseif #parts == 2 then
    t, r, b, l = parts[1], parts[2], parts[1], parts[2]
  elseif #parts == 3 then
    t, r, b, l = parts[1], parts[2], parts[3], parts[2]
  else
    t, r, b, l = parts[1], parts[2], parts[3], parts[4]
  end

  local imp = shorthand.important
  -- 只有当四边没有单独指定时才展开（简化处理：总是展开，单独属性后写会覆盖）
  decls[base .. "-top"]    = decls[base .. "-top"]    or { value = t, important = imp }
  decls[base .. "-right"]  = decls[base .. "-right"]  or { value = r, important = imp }
  decls[base .. "-bottom"] = decls[base .. "-bottom"] or { value = b, important = imp }
  decls[base .. "-left"]   = decls[base .. "-left"]   or { value = l, important = imp }
end

--=============================================================================
-- 不参与渲染的标签（head 类内容）
--=============================================================================

--[[ 这些标签在浏览器里也不显示，布局/渲染时应当跳过 ]]--
local NON_RENDERED = {
  style    = true,
  script   = true,
  head     = true,
  title    = true,
  meta     = true,
  link     = true,
  base     = true,
}

function S.isNonRendered(tag)
  return NON_RENDERED[tag] == true
end

--=============================================================================
-- 主流程
--=============================================================================

--[[ 计算单个元素的样式表（不处理继承，继承在 normalize 阶段做）]]--
local function computeOwn(el, sheets)
  local result = {}

  -- ★ 记录哪些属性是"被显式指定"的。
  --   关键：默认值也填进了 result，若不区分，
  --   normalize 阶段就无法判断某属性该不该继承。
  local explicit = {}

  -- 1. 默认值
  for k, v in pairs(DEFAULTS) do result[k] = v end

  -- ★ 不参与渲染的标签（style/script/head）：直接 display:none
  if NON_RENDERED[el.tag] then
    result.display = "none"
    explicit.display = true
    return result, explicit
  end

  -- 2. 匹配的规则（已按特指度升序）
  local rules = css.collectRules(el, sheets)

  -- 3. 作者样式 -> 内联样式（内联最高）
  local function applyDecls(decls)
    -- 展开简写
    expandBox(decls, "margin")
    expandBox(decls, "padding")

    for prop, d in pairs(decls) do
      local wasImp = explicit["!" .. prop]           -- 之前是否 !important
      if d.important then
        result[prop] = d.value
        explicit[prop] = true
        explicit["!" .. prop] = true
      elseif not wasImp then
        -- 非 important 的值覆盖同级别的，但不覆盖已标记 important 的
        result[prop] = d.value
        explicit[prop] = true
      end
    end
  end

  for i = 1, #rules do
    applyDecls(rules[i].decls, false)
  end

  -- 内联样式（更高优先级）
  local inlineText = el.attrs and el.attrs.style
  if inlineText then
    local inlineDecls = css.parseInline(inlineText)
    expandBox(inlineDecls, "margin")
    expandBox(inlineDecls, "padding")
    for prop, d in pairs(inlineDecls) do
      if d.important or not explicit["!" .. prop] then
        result[prop] = d.value
        explicit[prop] = true
        if d.important then explicit["!" .. prop] = true end
      end
    end
  end

  -- ★ 运行时样式覆盖（由脚本设置，优先级最高，且能跨 flush 保留）
  --
  --   用法：
  --     node._inline = { ["background-color"] = "#4a90d9", color = "#fff" }
  --
  --   ⚠️ 没有这个机制时，脚本改了 node.style._bgColor，
  --      下一次 flush 会被 style.apply 重新计算并覆盖掉 —— 这是实际踩过的坑。
  if el._inline then
    for prop, v in pairs(el._inline) do
      result[prop] = v
      explicit[prop] = true
    end
  end

  -- ★ 显示/隐藏覆盖（node:setVisible）
  if el._displayOverride then
    result.display = el._displayOverride
    explicit.display = true
  end

  return result, explicit
end

--[[ 归一化：字符串值 -> 内部表示
     explicit: 该元素"被显式指定"的属性集合（用于判断继承） ]]--
local function normalize(el, raw, parentStyle, explicit)
  explicit = explicit or {}
  local st = {}

  -- 字符串原样保留（布局器会用）
  for k, v in pairs(raw) do
    if type(v) == "string" then
      local lk = k:lower()
      st[lk] = v
    end
  end

  -- ★ 继承：只有当该属性【未被显式指定】时才从父节点取
  for prop in pairs(INHERITED) do
    local isExplicit = explicit[prop] == true
    local v = st[prop]
    if (not isExplicit) or v == nil or v == "inherit" then
      if parentStyle and parentStyle[prop] ~= nil then
        st[prop] = parentStyle[prop]
      else
        st[prop] = DEFAULTS[prop]
      end
    end
  end

  -- 颜色
  st._color = color.parse(st.color) or { r = 0, g = 0, b = 0, a = 255 }
  st._bgColor = color.parse(st["background-color"]) or { r = 0, g = 0, b = 0, a = 0 }
  st._borderColor = color.parse(st["border-color"]) or { r = 0, g = 0, b = 0, a = 0 }

  -- 保留父节点已解析好的颜色对象，供文本节点继承
  if parentStyle then
    if not explicit.color and parentStyle._color then st._color = parentStyle._color end
  end

  -- opacity：与继承的透明度相乘
  local op = parseOpacity(st.opacity)
  if parentStyle and parentStyle._opacity and not explicit.opacity then
    op = op * parentStyle._opacity
  end
  st._opacity = op

  -- 字体大小（支持百分比与 em 相对父级）
  local fsLen = S.parseLength(st["font-size"])
  local parentFs = (parentStyle and parentStyle._fontSize) or 14
  local fs
  if fsLen.unit == "%" then
    fs = parentFs * fsLen.n / 100
  elseif fsLen.unit == "em" then
    fs = parentFs * fsLen.n
  else
    fs = fsLen.n
  end
  st._fontSize = util.toFontSize(fs, 14)

  -- 行高
  st._lineHeight = (function()
    local v = st["line-height"]
    local n = util.toNumber(v)
    if n then return n * st._fontSize end   -- 无单位倍数
    local l = S.parseLength(v)
    if l.unit == "em" then return l.n * st._fontSize end
    return l.n
  end)()

  st._textAlign = st["text-align"]
  st._fontWeight = st["font-weight"]

  --[[ 裁剪形状（★ R16/R17 真机验证的能力）

       CSS 属性 -> 遮罩形状图 ID：
         border-radius:50% / 非零  -> 圆形图（100002）
         overflow:hidden           -> 矩形图（100001）

       优先级：border-radius 优先于 overflow ——
         因为圆角元素通常也要裁切，用圆图能一次满足两者。

       _clipShape 为 nil 表示无需裁剪。
       ⚠️ 这里不 require clip.lua 以避免循环依赖，直接写常量；
         渲染层会用 clip.lua 的 API 去配遮罩。
  ]]--
  do
    local radiusShape = nil
    local rv = st["border-radius"]
    if rv and rv ~= "0" and rv ~= "0px" and rv ~= "0%" and rv ~= "" then
      radiusShape = 100002      -- CIRCLE
    end

    --[[ ★ 显式声明为图片控件：方便应用层用 SetImage 换形状。

         为什么需要这个开关：
           chooseKind 默认按"有无背景色"选 textbox，
           而 textbox 在真机上【没有 SetImage】。
           想画形状图（技能图标、装饰图形）就必须显式声明。

         ⚠️ 取的是【HTML 属性】而不是 CSS 属性 ——
            HTML 属性不会变成样式表的键（实测：attrs 里有，style 里没有）。
         用法：<div data-image="1" id="icon1"></div>
    ]]--
    local attrs = el and el.attrs
    local wantsImage = (attrs and (attrs["data-image"] == "1"
                                   or attrs["data-image"] == "")) or false

    if radiusShape then
      st._clipShape = radiusShape
      st._clipReverse = false
    elseif (st.overflow == "hidden" or st.overflow == "scroll"
            or st.overflow == "auto") then
      st._clipShape = 100001    -- SQUARE（矩形裁剪）
      st._clipReverse = false
    else
      st._clipShape = nil
      st._clipReverse = nil
    end

    -- 显式图片元素：即使没有裁剪，也走 image 类型
    if wantsImage and not st._clipShape then
      st._forceImage = true
    else
      st._forceImage = nil
    end
  end

  -- transform（translate / scale / rotateZ）
  --   宽高基准用元素自身的显式宽高（百分比 transform 才有意义），
  --   这里先按 0 处理，布局完成后再由 layout 兜底重算百分比。
  st._transform = S.parseTransform(st.transform, 0, 0, st._fontSize)
  st._zIndex = (function()
    local n = util.toNumber(st["z-index"])
    return n    -- nil 表示 auto
  end)()

  -- transition（延迟到 transition.lua 解析，避免循环依赖）
  st._rawTransition = st.transition
  st._rawTransitionLong = {
    property = st["transition-property"],
    duration = st["transition-duration"],
    timing   = st["transition-timing-function"],
    delay    = st["transition-delay"],
  }

  return st
end

--[[ 应用样式到整棵 DOM 树 ]]--
function S.apply(root, sheets)
  sheets = sheets or {}

  -- 第一遍：计算自身样式（含 explicit 标记）
  --
  --   ★ 顺便赋 _order（DOM 先序号）。
  --     控件池的回收需要按 DOM 顺序压入，而 self.live 是哈希表无法保序，
  --     所以在这里一次性记下顺序（dom.walk 是稳定的先序遍历）。
  local own, exps = {}, {}
  local order = 0
  dom.walk(root, function(n)
    if n:isElement() then
      order = order + 1
      n._order = order
      local r, e = computeOwn(n, sheets)
      own[n] = r
      exps[n] = e
    end
  end)

  -- 第二遍：自顶向下做继承 + 归一化
  local function process(node, parentStyle)
    local myStyle = nil
    if node:isElement() then
      myStyle = normalize(node, own[node] or {}, parentStyle, exps[node])
      node.style = myStyle
    elseif node:isText() then
      -- 文本节点继承父样式（只取文本相关）
      local inherited = {}
      if parentStyle then
        inherited._color = parentStyle._color
        inherited._fontSize = parentStyle._fontSize
        inherited._lineHeight = parentStyle._lineHeight
        inherited._textAlign = parentStyle._textAlign
        inherited._fontWeight = parentStyle._fontWeight
      end
      inherited._opacity = 1
      node.style = inherited
    end

    for i = 1, #node.children do
      process(node.children[i], myStyle or parentStyle)
    end
  end

  for i = 1, #root.children do
    process(root.children[i], nil)
  end

  return root
end

--[[ 取元素的最终字号（考虑继承）]]--
function S.fontSizeOf(node)
  if node and node.style and node.style._fontSize then
    return node.style._fontSize
  end
  return 14
end

S.DEFAULTS = DEFAULTS
S.INHERITED = INHERITED

return S
