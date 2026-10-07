--[[============================================================================
  webui/util.lua  ——  通用工具

  约束：只用 Lua 5.1 就有的语言特性。
        不用 goto / 位运算 / string.pack / coroutine。
==============================================================================]]

local U = {}

--=============================================================================
-- 日志
--=============================================================================

local LOG_PREFIX = "[webui] "

function U.log(...)
  local n = select('#', ...)
  local parts = {}
  for i = 1, n do parts[i] = tostring((select(i, ...))) end
  print(LOG_PREFIX .. table.concat(parts, " "))
end

function U.warn(...)
  local n = select('#', ...)
  local parts = {}
  for i = 1, n do parts[i] = tostring((select(i, ...))) end
  -- printerr 在真机可用；退化到 print
  local msg = LOG_PREFIX .. "[warn] " .. table.concat(parts, " ")
  if type(printerr) == "function" then
    pcall(printerr, msg)
  else
    print(msg)
  end
end

--[[ 安全调用：出错不中断，返回 ok, result ]]--
function U.try(fn, ...)
  local ok, a, b, c = pcall(fn, ...)
  if not ok then
    U.warn("try 失败: " .. tostring(a))
    return false, a
  end
  return true, a, b, c
end

--=============================================================================
-- 表操作
--=============================================================================

function U.copy(t)
  local r = {}
  for k, v in pairs(t) do r[k] = v end
  return r
end

function U.shallow(t)
  local r = {}
  if not t then return r end
  for i = 1, #t do r[i] = t[i] end
  return r
end

function U.count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

function U.contains(list, v)
  for i = 1, #list do
    if list[i] == v then return true end
  end
  return false
end

--[[ 合并：后者覆盖前者（浅合并）]]--
function U.merge(dst, src)
  if not src then return dst end
  for k, v in pairs(src) do dst[k] = v end
  return dst
end

--=============================================================================
-- 字符串 / 数值
--=============================================================================

--[[ 去掉首尾空白 ]]--
function U.trim(s)
  if type(s) ~= "string" then return "" end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--[[ 数值化：失败返回 nil ]]--
function U.toNumber(s)
  if type(s) == "number" then return s end
  if type(s) ~= "string" then return nil end
  s = U.trim(s)
  if s == "" then return nil end
  local n = tonumber(s)
  return n
end

--[[ 限制范围 ]]--
function U.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function U.round(v)
  if v >= 0 then return math.floor(v + 0.5) end
  return math.ceil(v - 0.5)
end

function U.isFinite(v)
  if type(v) ~= "number" then return false end
  if math.isnan and math.isnan(v) then return false end
  if math.isinf and math.isinf(v) then return false end
  return true
end

--[[ 把值转成合法的整数字号（真机要求 fontSize 必须是 integer，否则报错）]]--
function U.toFontSize(v, dflt)
  local n = U.toNumber(v)
  if not n or not U.isFinite(n) then return dflt end
  n = U.round(n)
  if n < 1 then n = 1 end
  return n
end

--=============================================================================
-- 画布
--=============================================================================

--[[ 取画布尺寸，带缓存 + 兜底 ]]--
local _canvasW, _canvasH

function U.canvasSize()
  if _canvasW then return _canvasW, _canvasH end
  local w, h = nil, nil
  U.try(function()
    w, h = game.GetUICanvasSize()
  end)
  if not U.isFinite(w) or w <= 0 then w = 1600 end
  if not U.isFinite(h) or h <= 0 then h = 900 end
  _canvasW, _canvasH = w, h
  return w, h
end

function U.resetCanvasCache()
  _canvasW, _canvasH = nil, nil
end

--=============================================================================
-- 字符串宽度估算（用于文本排版）
--
-- 真机没有字体 API，只能估算。策略：
--   - CJK / 全角字符  -> 1.0 em
--   - ASCII 窄字符    -> 0.5 em
--   - 其他            -> 0.6 em
-- 用户可通过 U.setCharWidthHook 覆盖。
--=============================================================================

local charWidthHook = nil

function U.setCharWidthHook(fn)
  charWidthHook = fn
end

--[[ 判断字节是否是 UTF-8 多字节序列的首字节 ]]--
local function utf8_seqlen(b)
  if b < 0x80 then return 1 end
  if b < 0xC0 then return 1 end   -- 续字节，按 1 处理（容错）
  if b < 0xE0 then return 2 end
  if b < 0xF0 then return 3 end
  return 4
end

--[[ 估算单个"字"的宽度（em 为单位）]]--
local function charWidth(ch)
  if charWidthHook then
    local w = charWidthHook(ch)
    if U.isFinite(w) then return w end
  end
  local b = ch:byte(1)
  if not b then return 0 end
  if b < 0x80 then
    -- ASCII
    if ch == " " then return 0.28 end
    if ch == "i" or ch == "l" or ch == "j" or ch == "t" or ch == "f" then return 0.30 end
    if ch == "m" or ch == "w" or ch == "M" or ch == "W" then return 0.85 end
    if ch:match("[A-Z]") then return 0.65 end
    return 0.55
  end
  -- 多字节：中文/日文/韩文 视为全角；其他按 0.6
  local cp = utf8.codepoint and select(1, utf8.codepoint(ch, 1, -1)) or nil
  if cp then
    -- CJK 统一表意文字
    if cp >= 0x4E00 and cp <= 0x9FFF then return 1.0 end
    if cp >= 0x3000 and cp <= 0x303F then return 1.0 end  -- CJK 标点
    if cp >= 0xFF00 and cp <= 0xFFEF then return 1.0 end  -- 全角
    if cp >= 0xAC00 and cp <= 0xD7AF then return 1.0 end  -- 韩文
    if cp >= 0x3040 and cp <= 0x30FF then return 1.0 end  -- 假名
    return 0.6
  end
  return 1.0
end

--[[ 把字符串切成"字符"列表（按 UTF-8 边界）]]--
function U.chars(s)
  local out = {}
  local i, n = 1, #s
  while i <= n do
    local b = s:byte(i)
    local len = utf8_seqlen(b)
    if i + len - 1 > n then len = 1 end
    out[#out + 1] = s:sub(i, i + len - 1)
    i = i + len
  end
  return out
end

--[[ 估算整串的宽度（像素）]]--
function U.measureText(s, fontSize)
  if type(s) ~= "string" or s == "" then return 0 end
  fontSize = fontSize or 14
  local total = 0
  local cs = U.chars(s)
  for i = 1, #cs do
    total = total + charWidth(cs[i])
  end
  return total * fontSize
end

--=============================================================================
-- 路径 / id
--=============================================================================

local idCounter = 0
function U.nextId(prefix)
  idCounter = idCounter + 1
  return (prefix or "n") .. tostring(idCounter)
end

function U.resetIdCounter()
  idCounter = 0
end

--=============================================================================
-- 类（简单实现，避免依赖第三方）
--=============================================================================

function U.class(parent)
  local c = {}
  c.__index = c
  if parent then setmetatable(c, { __index = parent }) end
  c.new = function(...)
    local o = setmetatable({}, c)
    if o.init then o:init(...) end
    return o
  end
  return c
end

return U
