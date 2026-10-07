--[[============================================================================
  webui/css.lua  ——  CSS 解析器 + 选择器匹配

  支持的选择器：
    tag            div
    .class         .panel
    #id            #main
    组合            div.panel#main
    后代            div span
    直接子          div > span
    并集            div, span
    通配            *

  支持的声明：
    property: value;
    !important

  不支持（会被忽略）：
    @media / @keyframes / 伪类 / 伪元素 / 属性选择器
==============================================================================]]

local util = require('webui.util')

local C = {}

--=============================================================================
-- 选择器解析
--=============================================================================

--[[
  一个"复合选择器" = { tag=?, id=?, classes={}, }
  一个"选择器" = 若干复合选择器 + 组合符
    { parts = { {comp=..., combinator="descendant"|"child"|nil}, ... } }
]]--

local function parseCompound(s)
  local comp = { tag = nil, id = nil, classes = {}, hover = false, active = false }
  local i, n = 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c == "*" then
      i = i + 1
    elseif c == "." then
      i = i + 1
      local st = i
      while i <= n and s:sub(i, i):match("[%w_%-]") do i = i + 1 end
      local cls = s:sub(st, i - 1)
      if cls == "" then return nil end   -- ". " 非法
      comp.classes[#comp.classes + 1] = cls
    elseif c == "#" then
      i = i + 1
      local st = i
      while i <= n and s:sub(i, i):match("[%w_%-]") do i = i + 1 end
      local id = s:sub(st, i - 1)
      if id == "" then return nil end    -- "# " 非法
      comp.id = id
    elseif c == ":" then
      -- ★ 伪类：只支持 :hover 和 :active
      --    其他伪类（:first-child / :nth-child / :focus ...）整条作废
      i = i + 1
      local st = i
      while i <= n and s:sub(i, i):match("[%w_%-]") do i = i + 1 end
      local pseudo = s:sub(st, i - 1):lower()
      if pseudo == "hover" then
        comp.hover = true
      elseif pseudo == "active" then
        comp.active = true
      else
        return nil
      end
    elseif c:match("[%w_%-]") then
      local st = i
      while i <= n and s:sub(i, i):match("[%w_%-]") do i = i + 1 end
      comp.tag = s:sub(st, i - 1):lower()
    else
      -- ⚠️ 遇到不支持的语法（[ ] ( ) 等）立即放弃整条选择器。
      --    否则 "div[attr]" 会被静默当成 "div"，导致样式错误应用。
      return nil
    end
  end
  return comp
end

--[[ 解析单个完整选择器（可能含后代/子组合符）]]--
local function parseSelector(s)
  s = util.trim(s)
  if s == "" then return nil end

  -- 按空白和 > 切分，记录组合符
  local parts = {}
  local i, n = 1, #s
  local pendingCombinator = nil

  while i <= n do
    -- 跳空白
    local sawSpace = false
    while i <= n and s:sub(i, i):match("%s") do i = i + 1; sawSpace = true end
    if i > n then break end

    if s:sub(i, i) == ">" then
      pendingCombinator = "child"
      i = i + 1
    elseif s:sub(i, i) == "+" or s:sub(i, i) == "~" then
      -- 兄弟选择器，不支持，整条规则作废
      return nil
    else
      local st = i
      while i <= n and not s:sub(i, i):match("[%s>+~]") do i = i + 1 end
      local token = s:sub(st, i - 1)
      if token ~= "" then
        local comp = parseCompound(token)
        if not comp then return nil end   -- 含不支持语法，整条作废
        parts[#parts + 1] = {
          comp = comp,
          combinator = pendingCombinator or (sawSpace and "descendant" or nil),
        }
        pendingCombinator = nil
      end
    end
  end

  if #parts == 0 then return nil end
  -- 第一个 part 的组合符无意义
  parts[1].combinator = nil
  return parts
end

--[[ 解析选择器组 "a, b, c" ]]--
local function parseSelectorList(s)
  local out = {}
  for one in s:gmatch("[^,]+") do
    local sel = parseSelector(one)
    if sel then
      out[#out + 1] = sel
    else
      -- 含不支持的选择器：整条作废，返回特殊标记
      return nil
    end
  end
  return out
end

--=============================================================================
-- 声明解析
--=============================================================================

--[[ "color: red; font-size: 14px !important" -> {color={v=...,important=...}} ]]--
local function parseDeclarations(s)
  local decls = {}
  for one in s:gmatch("[^;]+") do
    local prop, val = one:match("^%s*([%w%-]+)%s*:%s*(.-)%s*$")
    if prop and val then
      local important = false
      local v2 = val:gsub("%s*!%s*important%s*$", function()
        important = true
        return ""
      end)
      decls[prop:lower()] = {
        value = util.trim(v2),
        important = important,
      }
    end
  end
  return decls
end

--=============================================================================
-- 样式表解析
--=============================================================================

--[[ 解析 CSS 文本，返回规则列表 ]]--
function C.parse(src)
  local sheet = { rules = {} }
  if type(src) ~= "string" then return sheet end

  -- 去掉注释
  src = src:gsub("/%*.-%*/", "")

  local i, n = 1, #src
  while i <= n do
    -- 找下一个 '{'
    local brace = src:find("{", i, true)
    if not brace then break end

    local selectorText = src:sub(i, brace - 1)

    -- 跳过 at-rule（@media 等）：简单跳过整个块
    if util.trim(selectorText):sub(1, 1) == "@" then
      -- 找到匹配的 '}'（考虑嵌套）
      local depth = 1
      local k = brace + 1
      while k <= n and depth > 0 do
        local ch = src:sub(k, k)
        if ch == "{" then depth = depth + 1
        elseif ch == "}" then depth = depth - 1 end
        k = k + 1
      end
      i = k
    else
      local close = src:find("}", brace + 1, true)
      if not close then break end

      local body = src:sub(brace + 1, close - 1)
      local sels = parseSelectorList(selectorText)
      if sels then
        -- 计算特指度（取组内最高的）
        local decls = parseDeclarations(body)
        for si = 1, #sels do
          local spec = C.specificity(sels[si])
          sheet.rules[#sheet.rules + 1] = {
            selector = sels[si],
            decls = decls,
            specificity = spec,
            order = #sheet.rules + 1,
          }
        end
      end
      i = close + 1
    end
  end

  return sheet
end

--=============================================================================
-- 选择器匹配
--=============================================================================

--[[ 复合选择器是否匹配单个节点 ]]--
local function matchCompound(node, comp)
  if not node or not node:isElement() then return false end
  if comp.tag and comp.tag ~= node.tag then return false end
  if comp.id and comp.id ~= node.id then return false end
  for i = 1, #comp.classes do
    if not node:hasClass(comp.classes[i]) then return false end
  end

  -- ★ 伪类：需要节点的运行时交互状态
  --    node._hover / node._pressed 由 event.lua 在光标进入/按下时设置
  if comp.hover and not node._hover then return false end
  if comp.active and not node._pressed then return false end

  return true
end

--[[ 完整选择器是否匹配节点（从右往左匹配）]]--
local function matchSelector(node, sel)
  local parts = sel
  local pi = #parts

  -- 最右一个必须匹配当前节点
  if not matchCompound(node, parts[pi].comp) then return false end
  pi = pi - 1

  local cur = node.parent
  while pi >= 1 do
    local want = parts[pi]
    local combinator = parts[pi + 1] and parts[pi + 1].combinator or "descendant"

    if combinator == "child" then
      if not cur then return false end
      if not matchCompound(cur, want.comp) then return false end
      pi = pi - 1
      cur = cur.parent
    else
      -- 后代：向上找任意一个匹配的祖先
      local found = false
      while cur do
        if matchCompound(cur, want.comp) then
          found = true
          pi = pi - 1
          cur = cur.parent
          break
        end
        cur = cur.parent
      end
      if not found then return false end
    end
  end

  return true
end

C.matches = matchSelector

--=============================================================================
-- 特指度
--=============================================================================

--[[ 返回 {a, b, c}：a=id 数, b=class 数 + 伪类数, c=tag 数 ]]--
function C.specificity(sel)
  local a, b, c = 0, 0, 0
  for i = 1, #sel do
    local comp = sel[i].comp
    if comp.id then a = a + 1 end
    b = b + #comp.classes
    -- 伪类按 class 同级计入特指度（与 CSS 规范一致）
    if comp.hover then b = b + 1 end
    if comp.active then b = b + 1 end
    if comp.tag then c = c + 1 end
  end
  return { a = a, b = b, c = c }
end

--[[ 比较特指度：返回 -1 / 0 / 1 ]]--
function C.compareSpecificity(s1, s2)
  if s1.a ~= s2.a then return s1.a < s2.a and -1 or 1 end
  if s1.b ~= s2.b then return s1.b < s2.b and -1 or 1 end
  if s1.c ~= s2.c then return s1.c < s2.c and -1 or 1 end
  return 0
end

--=============================================================================
-- 查询：找出匹配某节点的所有规则（按特指度和顺序排序）
--=============================================================================

function C.collectRules(node, sheets)
  local hit = {}
  for si = 1, #sheets do
    local sheet = sheets[si]
    for ri = 1, #sheet.rules do
      local rule = sheet.rules[ri]
      if matchSelector(node, rule.selector) then
        hit[#hit + 1] = rule
      end
    end
  end
  -- 排序：特指度升序，同特指度按出现顺序
  table.sort(hit, function(x, y)
    local cmp = C.compareSpecificity(x.specificity, y.specificity)
    if cmp ~= 0 then return cmp < 0 end
    return x.order < y.order
  end)
  return hit
end

--=============================================================================
-- 内联样式 style="..."
--=============================================================================

function C.parseInline(styleText)
  if not styleText or styleText == "" then return {} end
  return parseDeclarations(styleText)
end

C.parseSelector = parseSelector
C.parseSelectorList = parseSelectorList
C.parseDeclarations = parseDeclarations

return C
