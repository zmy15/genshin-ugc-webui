--[[============================================================================
  webui/color.lua  ——  颜色解析

  支持：
    #rgb  #rrggbb  #rrggbbaa
    rgb(r,g,b)  rgba(r,g,b,a)
    transparent
    常用具名色
    inherit（由调用方处理）

  输出：{ r=0-255, g=0-255, b=0-255, a=0-255 }
==============================================================================]]

local util = require('webui.util')

local C = {}

local NAMED = {
  transparent   = {0,0,0,0},
  black         = {0,0,0,255},
  white         = {255,255,255,255},
  red           = {255,0,0,255},
  green         = {0,128,0,255},
  lime          = {0,255,0,255},
  blue          = {0,0,255,255},
  yellow        = {255,255,0,255},
  cyan          = {0,255,255,255},
  aqua          = {0,255,255,255},
  magenta       = {255,0,255,255},
  fuchsia       = {255,0,255,255},
  gray          = {128,128,128,255},
  grey          = {128,128,128,255},
  silver        = {192,192,192,255},
  maroon        = {128,0,0,255},
  olive         = {128,128,0,255},
  navy          = {0,0,128,255},
  teal          = {0,128,128,255},
  purple        = {128,0,128,255},
  orange        = {255,165,0,255},
  pink          = {255,192,203,255},
  brown         = {165,42,42,255},
  gold          = {255,215,0,255},
  darkgray      = {169,169,169,255},
  darkgrey      = {169,169,169,255},
  lightgray     = {211,211,211,255},
  lightgrey     = {211,211,211,255},
  dimgray       = {105,105,105,255},
  dimgrey       = {105,105,105,255},
  whitesmoke    = {245,245,245,255},
  gainsboro     = {220,220,220,255},
  tomato        = {255,99,71,255},
  crimson       = {220,20,60,255},
  dodgerblue    = {30,144,255,255},
  skyblue       = {135,206,235,255},
  royalblue     = {65,105,225,255},
  steelblue     = {70,130,180,255},
  seagreen      = {46,139,87,255},
  forestgreen   = {34,139,34,255},
  goldenrod     = {218,165,32,255},
  chocolate     = {210,105,30,255},
  slategray     = {112,128,144,255},
  slategrey     = {112,128,144,255},
}

--=============================================================================

local function hex2(s)
  return tonumber(s, 16)
end

--[[ 解析颜色字符串，返回 {r,g,b,a} 或 nil ]]--
function C.parse(str)
  if type(str) ~= "string" then return nil end
  local s = util.trim(str):lower()
  if s == "" then return nil end

  -- 具名色
  local named = NAMED[s]
  if named then
    return { r = named[1], g = named[2], b = named[3], a = named[4] }
  end

  -- #hex
  local hex = s:match("^#(%x+)$")
  if hex then
    if #hex == 3 then
      local r = hex2(hex:sub(1,1)) * 17
      local g = hex2(hex:sub(2,2)) * 17
      local b = hex2(hex:sub(3,3)) * 17
      return { r = r, g = g, b = b, a = 255 }
    elseif #hex == 4 then
      local r = hex2(hex:sub(1,1)) * 17
      local g = hex2(hex:sub(2,2)) * 17
      local b = hex2(hex:sub(3,3)) * 17
      local a = hex2(hex:sub(4,4)) * 17
      return { r = r, g = g, b = b, a = a }
    elseif #hex == 6 then
      return {
        r = hex2(hex:sub(1,2)),
        g = hex2(hex:sub(3,4)),
        b = hex2(hex:sub(5,6)),
        a = 255,
      }
    elseif #hex == 8 then
      return {
        r = hex2(hex:sub(1,2)),
        g = hex2(hex:sub(3,4)),
        b = hex2(hex:sub(5,6)),
        a = hex2(hex:sub(7,8)),
      }
    end
    return nil
  end

  -- rgb() / rgba()
  local fn, args = s:match("^(rgba?)%s*%((.-)%)$")
  if fn then
    local parts = {}
    for p in args:gmatch("[^,]+") do parts[#parts + 1] = util.trim(p) end
    if #parts < 3 then return nil end

    local function chan(v)
      local n = util.toNumber((v:gsub("%%$", "")))
      if not n then return nil end
      if v:sub(-1) == "%" then n = n * 255 / 100 end
      return util.clamp(util.round(n), 0, 255)
    end

    local r = chan(parts[1])
    local g = chan(parts[2])
    local b = chan(parts[3])
    if not r or not g or not b then return nil end

    local a = 255
    if parts[4] then
      local av = parts[4]
      local n = util.toNumber(av)
      if n then
        if av:sub(-1) == "%" then n = n / 100 end
        a = util.clamp(util.round(n * 255), 0, 255)
      end
    end
    return { r = r, g = g, b = b, a = a }
  end

  return nil
end

--[[ 转成引擎 ColorValue ]]--
function C.toEngine(c, fallback)
  if not c then c = fallback end
  if not c then return nil end
  local v
  local ok = pcall(function() v = Color.FromRGBA(c.r, c.g, c.b, c.a or 255) end)
  if ok and v ~= nil then return v end
  pcall(function() v = Color.FromRGB(c.r, c.g, c.b) end)
  return v
end

--[[ 应用透明度倍率（用于 opacity 属性）]]--
function C.withOpacity(c, mul)
  if not c then return nil end
  local a = c.a or 255
  return { r = c.r, g = c.g, b = c.b, a = util.clamp(util.round(a * mul), 0, 255) }
end

function C.toHex(c)
  if not c then return "#00000000" end
  return string.format("#%02x%02x%02x%02x", c.r, c.g, c.b, c.a or 255)
end

function C.equals(a, b)
  if a == b then return true end
  if not a or not b then return false end
  return a.r == b.r and a.g == b.g and a.b == b.b and (a.a or 255) == (b.a or 255)
end

C.NAMED = NAMED

return C
