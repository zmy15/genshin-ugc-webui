--[[============================================================================
  webui/html.lua  ——  HTML 解析器

  设计要点：
    - 【非递归】使用显式栈，避免深层嵌套爆 C stack
    - 不使用 coroutine（真机禁用）
    - 容错优先：不抛异常，遇到问题尽量恢复

  支持：
    - 标签、属性（双引号/单引号/无引号）
    - 自闭合标签 <br/> <img/>
    - 注释 <!-- -->
    - 文本节点
    - <style> 与 <script> 的内容原样保留

  不支持：
    - DOCTYPE 之外的特殊指令（会被跳过）
    - CDATA
==============================================================================]]

local D    = require('webui.dom')
local util = require('webui.util')

local H = {}

-- 这些标签没有闭合标签
local VOID_TAGS = {
  area=true, base=true, br=true, col=true, embed=true, hr=true,
  img=true, input=true, link=true, meta=true, param=true,
  source=true, track=true, wbr=true,
}

-- 这些标签的内容不解析（原样文本）
local RAW_TAGS = { script=true, style=true }

-- 自动闭合规则：遇到某些标签时，隐式关闭栈顶的某些标签
local AUTO_CLOSE = {
  p   = { p=true, div=true, ul=true, ol=true, li=true, h1=true, h2=true,
          h3=true, h4=true, h5=true, h6=true, table=true, section=true },
  li  = { li=true },
  td  = { td=true, th=true },
  th  = { td=true, th=true },
  tr  = { tr=true, td=true, th=true },
  dt  = { dt=true, dd=true },
  dd  = { dt=true, dd=true },
}

--=============================================================================
-- 属性解析
--=============================================================================

--[[ 解析属性串："a=1 b='2' c=3 d" -> {a="1", b="2", c="3", d=""} ]]--
local function parseAttrs(s)
  local attrs = {}
  local i, n = 1, #s
  while i <= n do
    -- 跳空白
    while i <= n and s:sub(i, i):match("[%s/]") do i = i + 1 end
    if i > n then break end

    -- 读名字
    local nameStart = i
    while i <= n do
      local c = s:sub(i, i)
      if c:match("[%s=/>]") then break end
      i = i + 1
    end
    local name = s:sub(nameStart, i - 1)
    if name == "" then
      i = i + 1
    else
      -- 跳过名字后的空白
      while i <= n and s:sub(i, i):match("%s") do i = i + 1 end

      local value = ""
      if s:sub(i, i) == "=" then
        i = i + 1
        while i <= n and s:sub(i, i):match("%s") do i = i + 1 end
        local q = s:sub(i, i)
        if q == '"' or q == "'" then
          i = i + 1
          local vs = i
          while i <= n and s:sub(i, i) ~= q do i = i + 1 end
          value = s:sub(vs, i - 1)
          i = i + 1
        else
          local vs = i
          while i <= n and not s:sub(i, i):match("[%s>]") do i = i + 1 end
          value = s:sub(vs, i - 1)
        end
      end
      attrs[name:lower()] = value
    end
  end
  return attrs
end

--=============================================================================
-- 主解析
--=============================================================================

--[[ 解析 HTML 文本，返回 root 节点 ]]--
function H.parse(src)
  if type(src) ~= "string" then src = "" end

  local root = D.newRoot()
  local stack = { root }        -- 显式栈，栈顶是当前父节点
  local textBuf = {}

  local function flushText()
    if #textBuf == 0 then return end
    local raw = table.concat(textBuf)
    textBuf = {}
    -- 折叠空白（HTML 语义）：连续空白 -> 单个空格
    local collapsed = raw:gsub("%s+", " ")
    -- 只有空白则丢弃
    if collapsed:match("^%s*$") then return end
    stack[#stack]:append(D.newText(collapsed))
  end

  local function topTag()
    local t = stack[#stack]
    if t and t.tag then return t.tag end
    return nil
  end

  local i, n = 1, #src
  while i <= n do
    local lt = src:find("<", i, true)

    -- 没有更多 '<'：剩余全是文本
    if not lt then
      textBuf[#textBuf + 1] = src:sub(i)
      break
    end

    -- '<' 之前的文本
    if lt > i then
      textBuf[#textBuf + 1] = src:sub(i, lt - 1)
    end

    -- 注释
    if src:sub(lt, lt + 3) == "<!--" then
      local close = src:find("-->", lt + 4, true)
      if close then
        i = close + 3
      else
        i = n + 1
      end

    -- DOCTYPE / 处理指令：跳过
    elseif src:sub(lt, lt + 1) == "<!" or src:sub(lt, lt + 1) == "<?" then
      local close = src:find(">", lt + 2, true)
      i = close and (close + 1) or (n + 1)

    -- 闭合标签
    elseif src:sub(lt, lt + 1) == "</" then
      local close = src:find(">", lt + 2, true)
      if not close then break end
      local name = util.trim(src:sub(lt + 2, close - 1)):lower()
      -- 去掉可能的属性残留
      name = name:match("^([%w%-_:]+)") or name

      flushText()
      -- 从栈顶往下找匹配的标签
      local found = nil
      for k = #stack, 2, -1 do
        if stack[k].tag == name then found = k break end
      end
      if found then
        -- 弹到该位置（含）
        for k = #stack, found, -1 do stack[k] = nil end
      end
      -- 没找到就忽略这个闭合标签（容错）
      i = close + 1

    -- 开标签
    else
      local gt = src:find(">", lt + 1, true)
      if not gt then break end

      local inner = src:sub(lt + 1, gt - 1)

      -- 解析标签名
      local tagName = inner:match("^%s*([%w%-_:]+)")
      if not tagName then
        -- 不是合法标签，当作文本
        textBuf[#textBuf + 1] = src:sub(lt, gt)
        i = gt + 1
      else
        tagName = tagName:lower()
        local selfClosing = inner:sub(-1) == "/" and not VOID_TAGS[tagName]
        local attrStr = inner:sub(#tagName + 1)
        if selfClosing then attrStr = attrStr:sub(1, -2) end
        local attrs = parseAttrs(attrStr)

        flushText()

        -- 自动闭合
        local rules = AUTO_CLOSE[tagName]
        if rules then
          local t = topTag()
          if t and rules[t] then
            stack[#stack] = nil
          end
        end

        local el = D.newElement(tagName)
        el.attrs = attrs
        if attrs.id then el.id = attrs.id end
        if attrs.class then
          for cls in attrs.class:gmatch("[^%s]+") do el:addClass(cls) end
        end

        stack[#stack]:append(el)
        i = gt + 1

        if VOID_TAGS[tagName] or selfClosing then
          -- 不入栈
        elseif RAW_TAGS[tagName] then
          -- 原样读到对应闭合标签
          local closeTag = "</" .. tagName
          local ci = src:find(closeTag, i, true)
          if ci then
            local content = src:sub(i, ci - 1)
            if content ~= "" then el:append(D.newText(content)) end
            local cg = src:find(">", ci, true)
            i = cg and (cg + 1) or (n + 1)
          else
            el:append(D.newText(src:sub(i)))
            i = n + 1
          end
        else
          stack[#stack + 1] = el
        end
      end
    end
  end

  flushText()
  return root
end

--=============================================================================
-- 从 DOM 中提取 <style> 内容
--=============================================================================

function H.extractStyles(root)
  local out = {}
  D.walk(root, function(n)
    if n:isElement() and n.tag == "style" then
      local buf = {}
      for i = 1, #n.children do
        local c = n.children[i]
        if c:isText() then buf[#buf + 1] = c.text end
      end
      out[#out + 1] = table.concat(buf, "")
    end
  end)
  return out
end

H.VOID_TAGS = VOID_TAGS
H.parseAttrs = parseAttrs

return H
