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

local css   = require('webui_css')
local color = require('webui_color')
local util  = require('webui_util')
local dom   = require('webui_dom')

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

--[[ 长度：返回 { n=数值, unit="px"|"%"|"em"|"vw"|"vh"|"vmin"|"vmax", auto=bool } 

     ★ 支持的单位（对齐原生 CSS）：
         px / % / em / rem / vw / vh / vmin / vmax / 无单位

     ⚠️ vw/vh 等的基准是【逻辑设计尺寸】而不是真实画布 ——
        因为布局是在设计坐标系里算的（见 webui_fit.lua）。
        解析时先原样带出单位，由 layout 用 _vwBase 换算。

     ⚠️ 不认识的单位会返回 invalid=true（调用方应 warn），
        不再静默当成 0 —— "静默失效"是最难查的一类 bug。
]]--
function S.parseLength(v)
  if type(v) == "number" then return { n = v, unit = "px" } end
  if type(v) ~= "string" then return { n = 0, unit = "px" } end
  local s = util.trim(v):lower()
  if s == "" then return { n = 0, unit = "px" } end

  if s == "auto" then return { n = 0, unit = "px", auto = true } end
  if s == "none" then return { n = 0, unit = "px", none = true } end

  --[[ calc() 表达式：递归求值

       ⚠️ 结果可能是"含百分比"的（如 calc(50% - 100px)），
          这时单位返回 "%"，含义是"已经折算过的比例值"，
          需要调用方用真实基准二次换算 —— 见 S.parseLengthBase。 ]]--
  if s:sub(1, 5) == "calc(" and s:sub(-1) == ")" then
    local inner = s:sub(6, -2)
    local val, unit, ok = S.evalCalc(inner)
    if ok then return { n = val, unit = unit } end
    return { n = 0, unit = "px", invalid = true, src = v }
  end

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

  -- em / rem（rem 的基准另算，这里先标出来）
  n = s:match("^([%-%d%.]+)rem$")
  if n then
    return { n = util.toNumber(n) or 0, unit = "rem" }
  end
  n = s:match("^([%-%d%.]+)em$")
  if n then
    return { n = util.toNumber(n) or 0, unit = "em" }
  end

  -- ★ 视口单位（原生 CSS 常用；库按逻辑设计尺寸换算）
  n = s:match("^([%-%d%.]+)vw$")
  if n then return { n = util.toNumber(n) or 0, unit = "vw" } end
  n = s:match("^([%-%d%.]+)vh$")
  if n then return { n = util.toNumber(n) or 0, unit = "vh" } end
  n = s:match("^([%-%d%.]+)vmin$")
  if n then return { n = util.toNumber(n) or 0, unit = "vmin" } end
  n = s:match("^([%-%d%.]+)vmax$")
  if n then return { n = util.toNumber(n) or 0, unit = "vmax" } end

  -- 无单位数值
  n = util.toNumber(s)
  if n then return { n = n, unit = "px" } end

  --[[ 认识一下常见但未实现的单位，给出精确告警而不是静默当 0。

       ch / ex / pt / pc / in / cm / mm / q —— 这些在原生 CSS 里合法，
       本库不换算（引擎没有字体度量 API，ch/ex 无法可靠求值）。 ]]--
  local unknownUnit = s:match("^[%-%d%.]+(%a+)$")
  return { n = 0, unit = "px", invalid = true, src = v,
           unknownUnit = unknownUnit }
end

--=============================================================================
-- calc() 求值
--
--   支持：+ - * / 与括号嵌套，操作数可以是 px / % / em / rem / vw / vh。
--
--   ⚠️ 单位规则（同原生 CSS）：
--        · 加减要求同单位（px+% 在原生里合法，但结果混合单位，
--          本库简化为：以【左侧操作数的单位】为准，右侧换算成同单位）
--        · 乘除的右操作数必须是无单位数
--
--   实现：把表达式转成 token 流，用递归下降解析。
-- ==============================================================================

--[[ 取某个单位在当前上下文下的换算基准。

     返回 base（每 1 单位对应多少 px），或 nil 表示纯比例单位（%）。 ]]--
local function unitBase(unit, ctx)
  ctx = ctx or {}
  if unit == "px" then return 1 end
  if unit == "em" then return ctx.fontSize or 14 end
  if unit == "rem" then return ctx.rootFontSize or (ctx.fontSize or 14) end
  if unit == "vw" then return (ctx.vw or 1600) / 100 end
  if unit == "vh" then return (ctx.vh or 900) / 100 end
  if unit == "vmin" then
    local a, b = ctx.vw or 1600, ctx.vh or 900
    return (a < b and a or b) / 100
  end
  if unit == "vmax" then
    local a, b = ctx.vw or 1600, ctx.vh or 900
    return (a > b and a or b) / 100
  end
  return nil      -- % 或未知
end

--[[ tokenize：把 "50% - 10px" 拆成 { {n=50,u="%"}, op="-" , {n=10,u="px"} } ]]--
local function calcTokens(s)
  local toks = {}
  local i, n = 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c:match("%s") then
      i = i + 1
    elseif c == "(" then
      -- 找匹配的右括号
      local depth, k = 1, i + 1
      while k <= n and depth > 0 do
        local ch = s:sub(k, k)
        if ch == "(" then depth = depth + 1
        elseif ch == ")" then depth = depth - 1 end
        k = k + 1
      end
      if depth ~= 0 then return nil end
      toks[#toks + 1] = { group = s:sub(i + 1, k - 2) }
      i = k
    elseif c == "+" or c == "-" or c == "*" or c == "/" then
      toks[#toks + 1] = { op = c }
      i = i + 1
    else
      --[[ 数值 + 可选单位

           ⚠️ 单位里必须包含 '%' —— 只写 %a* 会让 "50%" 匹配不到单位，
              于是 50% 被当成无单位的 50，calc(50% - 100px) 直接算错。
              实测踩过：整个 calc 表达式求值失败、静默变 0。 ]]--
      local num, unit = s:match("^([%-%d%.]+)%s*(%%?%a*)", i)
      if not num then return nil end
      toks[#toks + 1] = { n = util.toNumber(num), u = (unit ~= "" and unit) or nil }
      i = i + #num + #(unit or "")
    end
  end
  return toks
end

--[[ 表达式求值（递归下降）。

     ⚠️ evalExpr 与 evalTerm 互相递归，必须【先声明后赋值】：
        Lua 里 `local function f() ... end` 不会前向声明，
        `local f; f = function() ... end` 才是正确写法。 ]]--
local evalExpr

--[[ 把 token 的值统一成 { pct, px } 形式。

     ⚠️ 这是整套 calc 求值的基础表示：
         calc(50% - 100px) -> { pct=50, px=-100 }
        em/rem/vw/vh 等有确定基准的单位，在这里就直接换算进 px。 ]]--
local function toTerm(t, ctx)
  if not t then return nil end
  -- 已经是 {pct,px} 形式（表达式中间结果）
  if t.pct ~= nil and t.px ~= nil then return t end

  local u = t.u
  if u == nil or u == "px" then
    return { pct = 0, px = t.n }
  end
  if u == "%" then
    return { pct = t.n, px = 0 }
  end
  -- em / rem / vw / vh / vmin / vmax：基准已知，直接换算成 px
  local b = unitBase(u, ctx)
  if b then return { pct = 0, px = t.n * b } end
  return nil
end

local function evalPrimary(toks, pos, ctx)
  local t = toks[pos]
  if not t then return nil, pos, false end

  -- 括号：递归求值，结果已经是 {pct,px}
  if t.group then
    local v, p2, ok = S.evalCalcExpr(t.group, ctx)
    if not ok then return nil, pos, false end
    return v, pos + 1, true
  end

  -- 字面量
  if t.n then
    local term = toTerm({ n = t.n, u = t.u }, ctx)
    if not term then return nil, pos, false end
    return term, pos + 1, true
  end
  return nil, pos, false
end

--[[ 乘除：右操作数必须无单位；左操作数的两个分量同时缩放 ]]--
local function evalTerm(toks, pos, ctx)
  local left, p, ok = evalPrimary(toks, pos, ctx)
  if not ok then return nil, pos, false end

  while toks[p] and toks[p].op and (toks[p].op == "*" or toks[p].op == "/") do
    local op = toks[p].op
    local right, p2, ok2 = evalPrimary(toks, p + 1, ctx)
    if not ok2 then return nil, pos, false end

    -- 右操作数必须是无单位的纯数
    if right.pct ~= 0 then return nil, pos, false end
    local k = right.px
    if op == "/" then
      if k == 0 then return nil, pos, false end
      k = 1 / k
    end
    left = { pct = left.pct * k, px = left.px * k }
    p = p2
  end
  return left, p, true
end

--[[ 混合单位的表示

     calc(50% - 100px) 这类表达式在原生 CSS 里是合法的：
     它同时含一个"比例项"和一个"绝对项"，必须等到知道基准才能求值。

     所以内部统一表示成 { pct = 比例, px = 绝对像素 }：
         calc(50% - 100px)   ->  { pct = 50,  px = -100 }
         calc(100vw - 200px) ->  { pct = 0,   px = 1400 }   （vw 已知，直接并入 px）

     最终求值见 S.resolveCalc（需要调用方给百分比基准）。
]]--

evalExpr = function(toks, pos, ctx)
  local left, p, ok = evalTerm(toks, pos, ctx)
  if not ok then return nil, pos, false end

  while toks[p] and toks[p].op and (toks[p].op == "+" or toks[p].op == "-") do
    local op = toks[p].op
    local right, p2, ok2 = evalTerm(toks, p + 1, ctx)
    if not ok2 then return nil, pos, false end

    --[[ 加减：把两边都化成 { pct, px } 后逐项相加

          ⚠️ 这里踩过一个坑：原来把混合单位当成"右侧跟随左侧"，
             导致 calc(50% - 100px) 算成 50-100 = -50%（完全错）。
             现在两个分量分别保留，等调用方给基准再合并。 ]]--
    local lt = toTerm(left, ctx)
    local rt = toTerm(right, ctx)
    if not lt or not rt then return nil, pos, false end

    local sign = (op == "+") and 1 or -1
    left = {
      pct = lt.pct + sign * rt.pct,
      px  = lt.px  + sign * rt.px,
    }
    p = p2
  end
  return left, p, true
end

--[[ 内部：求值成 { pct, px } 表达式（供括号递归用） ]]--
function S.evalCalcExpr(expr, ctx)
  if type(expr) ~= "string" then return nil, 0, false end
  local toks = calcTokens(expr)
  if not toks or #toks == 0 then return nil, 0, false end

  local v, p, ok = evalExpr(toks, 1, ctx)
  if not ok or not v then return nil, 0, false end
  if p <= #toks then return nil, 0, false end   -- 有剩余 token = 表达式非法
  return v, p, true
end

--[[ 求值 calc 表达式。

     返回 数值, 单位, 是否成功。
     ⚠️ 若表达式含百分比、且未提供 base，则返回 unit="%"（调用方用基准换算）。
        提供了 base 就一次性算出 px。 ]]--
function S.evalCalc(expr, ctx, base)
  local v, _, ok = S.evalCalcExpr(expr, ctx)
  if not ok or not v then return nil, nil, false end

  if v.pct ~= 0 then
    if base then
      -- 基准已知：直接算出 px
      return v.px + base * v.pct / 100, "px", true
    end
    -- 基准未知：把绝对项折算进"比例"没意义，返回表达式形态
    return v.px + v.pct, "%", true
  end
  return v.px, "px", true
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
