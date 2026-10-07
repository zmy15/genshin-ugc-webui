--[[============================================================================
  webui/transition.lua  ——  CSS transition 支持

  原理：
    CSS transition 要求属性"平滑过渡"。引擎的 game.Tween 正好能做这件事，
    但它 tween 的是【控件字段】，而我们的渲染器每帧都会写字段。

    所以做法是：
      1. 渲染器发现某属性值变了
      2. 若该属性声明了 transition，就不直接写，而是创建一个 Tween
      3. Tween 期间由引擎负责插值，渲染器【暂停写该字段】
      4. Tween 结束后恢复直接写

  支持：
    transition: <property> <duration> [<timing>] [<delay>][, ...]
    transition-property: all | none | <prop>[, ...]
    transition-duration: <time>[, ...]
    transition-timing-function: linear|ease|ease-in|ease-out|ease-in-out
    transition-delay: <time>[, ...]

  可过渡的属性（映射到引擎 tweenable 字段）：
    background-color -> bgColor
    color            -> fontColor
    opacity          -> 颜色 alpha
    width / height   -> sizeDeltaX / sizeDeltaY
    left / top       -> anchoredPositionX / anchoredPositionY
    transform        -> localScaleX/Y, localRotationZ
    font-size        -> fontSize

  ⚠️ 引擎的 Tweenable 字段（官方文档标 Tweenable 的）：
     anchoredPositionX/Y, sizeDeltaX/Y, anchorMin/Max, pivot,
     localScaleX/Y/Z, localRotationX/Y/Z,
     imageColor, fontColor, bgColor, outlineColor, fontSize,
     minimumFontSize, fillAmount, softEdgeWidthX/Y,
     horizontalSoftRange, verticalSoftRange, scrollProgress
==============================================================================]]

local util = require('webui.util')

local T = {}

--=============================================================================
-- 解析
--=============================================================================

--[[ "0.3s" / "300ms" / "0" -> 秒 ]]--
local function parseTime(s)
  if not s then return nil end
  s = util.trim(s):lower()
  local n, unit = s:match("^([%-%d%.]+)%s*(%a*)$")
  if not n then return nil end
  n = util.toNumber(n)
  if not n then return nil end
  if unit == "ms" then return n / 1000 end
  if unit == "s" or unit == "" then return n end
  return n
end

--[[ CSS 缓动关键字 -> 引擎 EaseType 名 ]]--
local TIMING_MAP = {
  linear     = "Linear",
  ease       = "InOutQuad",     -- 近似
  ["ease-in"]  = "InQuad",
  ["ease-out"] = "OutQuad",
  ["ease-in-out"] = "InOutQuad",
}

local function parseTiming(s)
  if not s then return "Linear" end
  s = util.trim(s):lower()
  local m = TIMING_MAP[s]
  if m then return m end
  -- cubic-bezier(...) 不支持，退化为 Linear
  return "Linear"
end

--[[ 按逗号拆分（不考虑括号内的逗号，够用）]]--
local function splitComma(s)
  local out = {}
  for one in s:gmatch("[^,]+") do
    out[#out + 1] = util.trim(one)
  end
  return out
end

--[[ 解析 transition 简写：`background-color 0.3s ease 0.1s, color 0.2s` ]]--
local function parseShorthand(v)
  local out = {}
  if type(v) ~= "string" then return out end
  for _, item in ipairs(splitComma(v)) do
    if item ~= "" then
      local parts = {}
      for p in item:gmatch("[^%s]+") do parts[#parts + 1] = p end
      local prop, dur, timing, delay
      for _, p in ipairs(parts) do
        local t = parseTime(p)
        if not prop and not t then
          prop = p:lower()
        elseif not dur and t then
          dur = t
        elseif not timing and not t and p:match("[%a%-]") then
          timing = p
        elseif t and not delay then
          delay = t
        end
      end
      out[#out + 1] = {
        property = prop or "all",
        duration = dur or 0,
        timing   = parseTiming(timing),
        delay    = delay or 0,
      }
    end
  end
  return out
end

--[[ 解析长写法（transition-property / -duration / ...）]]--
local function parseLonghand(st)
  local props    = splitComma(st["transition-property"] or "")
  local durs     = splitComma(st["transition-duration"] or "")
  local timings  = splitComma(st["transition-timing-function"] or "")
  local delays   = splitComma(st["transition-delay"] or "")

  if #props == 0 then return nil end

  local out = {}
  for i = 1, #props do
    local p = props[i]:lower()
    if p ~= "" then
      out[#out + 1] = {
        property = p,
        -- 少于属性数时循环使用（CSS 规范行为）
        duration = parseTime(durs[((i - 1) % math.max(1, #durs)) + 1]) or 0,
        timing   = parseTiming(timings[((i - 1) % math.max(1, #timings)) + 1]),
        delay    = parseTime(delays[((i - 1) % math.max(1, #delays)) + 1]) or 0,
      }
    end
  end
  return out
end

--[[ 解析一个元素的 transition 声明，返回 { [prop]=entry } ]]--
function T.parse(st)
  if not st then return nil end

  local list = nil

  -- 简写优先
  local sh = st.transition
  if sh and sh ~= "none" and util.trim(sh) ~= "" then
    list = parseShorthand(sh)
  end
  -- 长写法（若简写没给）
  if (not list or #list == 0) and st["transition-property"] then
    list = parseLonghand(st)
  end

  if not list or #list == 0 then return nil end

  -- 展开成 prop -> entry
  local map = {}
  for _, e in ipairs(list) do
    if e.property and e.property ~= "none" then
      map[e.property] = e
    end
  end
  if next(map) == nil then return nil end
  return map
end

--=============================================================================
-- 属性 -> 引擎字段 的映射
--
--   每个 CSS 属性可能对应【一个或多个】引擎字段。
--   返回 { {field=, from=, to=}, ... } 或 nil（不可过渡）
--=============================================================================

--[[
  取某属性在"从 oldVal 到 newVal"时，需要 tween 的引擎字段与目标值。

  参数：
    prop     CSS 属性名
    field    引擎字段名（已由 render.lua 决定）
    oldVal   上一帧的值
    newVal   本帧的值

  返回：targetTable 或 nil
]]--
function T.fieldsFor(prop, field, oldVal, newVal)
  -- 直接可 tween 的字段（值与引擎字段同构）
  if prop == "background-color" and field == "bgColor" then
    if type(newVal) == "table" then
      return { bgColor = newVal }
    end
  elseif prop == "color" and field == "fontColor" then
    if type(newVal) == "table" then
      return { fontColor = newVal }
    end
  end
  return nil
end

T.parseShorthand = parseShorthand
T.parseTime = parseTime

return T