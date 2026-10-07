--[[============================================================================
  webui/dom.lua  ——  DOM 节点树

  节点类型：
    "element"  普通元素
    "text"     文本节点
    "root"     文档根

  每个节点上会挂载（由其它模块填充）：
    node.style    计算后的样式表（style.lua 填）
    node.box      布局结果（layout.lua 填）
    node.control  对应的引擎控件（render.lua 填）
==============================================================================]]

local util = require('webui.util')

local D = {}

local Node = {}
Node.__index = Node

--=============================================================================
-- 创建
--=============================================================================

function D.newElement(tag)
  local n = setmetatable({}, Node)
  n.kind        = "element"
  n.tag         = tag:lower()
  n.id          = nil
  n.classList   = {}          -- 字符串数组
  n.classSet    = {}          -- 集合，便于 O(1) 查询
  n.attrs       = {}          -- 属性表（字符串值）
  n.children    = {}
  n.parent      = nil
  n.uid         = util.nextId("e")
  -- 以下由其它模块填充
  n.style       = nil
  n.box         = nil
  n.control     = nil
  n.handlers    = nil         -- 元素上的事件处理器名（onclick 等）
  return n
end

function D.newText(text)
  local n = setmetatable({}, Node)
  n.kind     = "text"
  n.text     = text
  n.children = {}
  n.parent   = nil
  n.uid      = util.nextId("t")
  return n
end

function D.newRoot()
  local n = setmetatable({}, Node)
  n.kind     = "root"
  n.tag      = "#root"
  n.children = {}
  n.parent   = nil
  n.uid      = util.nextId("r")
  return n
end

--=============================================================================
-- 树操作
--=============================================================================

function Node:append(child)
  child.parent = self
  self.children[#self.children + 1] = child
  return child
end

function Node:isElement() return self.kind == "element" end
function Node:isText()    return self.kind == "text" end
function Node:isRoot()    return self.kind == "root" end

--[[ 加类名 ]]--
function Node:addClass(cls)
  if not cls or cls == "" then return end
  if not self.classSet[cls] then
    self.classSet[cls] = true
    self.classList[#self.classList + 1] = cls
  end
end

--[[ 是否含某类名 ]]--
function Node:hasClass(cls)
  return self.classSet[cls] == true
end

--[[ 删类名 ]]--
function Node:removeClass(cls)
  if not cls or not self.classSet[cls] then return end
  self.classSet[cls] = nil
  for i = #self.classList, 1, -1 do
    if self.classList[i] == cls then table.remove(self.classList, i) end
  end
end

--[[ 切换类名：add=true 加，add=false 删，add=nil 反转 ]]--
function Node:toggleClass(cls, add)
  local has = self:hasClass(cls)
  if add == nil then add = not has end
  if add and not has then self:addClass(cls)
  elseif not add and has then self:removeClass(cls) end
end

--[[ 取属性，带默认值 ]]--
function Node:getAttr(name, dflt)
  local v = self.attrs[name]
  if v == nil then return dflt end
  return v
end

--=============================================================================
-- 运行时样式（跨 flush 保留）
--
-- ⚠️ 不能直接改 node.style._bgColor —— flush() 会重算样式把它覆盖。
--    必须走 node._inline，它由 style.apply 在最后合并，优先级最高。
--=============================================================================

--[[ 设置一条运行时样式。
     值用 CSS 写法，如 node:setStyle("background-color", "#4a90d9")
     传 nil 清除该条。 ]]--
--[[ 设置一条运行时样式。
     值用 CSS 写法，如 node:setStyle("background-color", "#4a90d9")
     传 nil 清除该条。 ]]--
function Node:setStyle(prop, value)
  if not self._inline then self._inline = {} end
  local prev = self._inline[prop]
  -- ★ 只有值真的变了才标记，否则每次 refresh 都会清缓存全量重写
  if prev == value then return self end
  if value == nil then
    self._inline[prop] = nil
  else
    self._inline[prop] = value
  end
  -- 记录【具体哪个属性】变了，渲染器只需清该属性对应的字段
  if not self._inlineDirty then self._inlineDirty = {} end
  self._inlineDirty[prop] = true
  return self
end

--[[ 批量设置：node:setStyles({ ["background-color"]="#fff", color="#000" }) ]]--
function Node:setStyles(tbl)
  if not self._inline then self._inline = {} end
  for k, v in pairs(tbl or {}) do
    self:setStyle(k, v)
  end
  return self
end

--[[ 清除所有运行时样式 ]]--
function Node:clearStyles()
  if self._inline == nil then return self end
  self._inline = nil
  if not self._inlineDirty then self._inlineDirty = {} end
  self._inlineDirty["*"] = true      -- 全部字段都需要重写
  return self
end

--[[ 便捷：设置背景色，接受 {r,g,b,a} 或 " #rrggbb " ]]--
function Node:setBg(r, g, b, a)
  if type(r) == "table" then
    a = r.a or 255; b = r.b; g = r.g; r = r.r
  end
  return self:setStyle("background-color",
      string.format("#%02x%02x%02x%02x", r, g, b, a or 255))
end

--[[ 便捷：设置文字色 ]]--
function Node:setColor(r, g, b, a)
  if type(r) == "table" then
    a = r.a or 255; b = r.b; g = r.g; r = r.r
  end
  return self:setStyle("color",
      string.format("#%02x%02x%02x%02x", r, g, b, a or 255))
end

--[[ 便捷：设置宽度（像素）]]--
function Node:setWidth(px)
  return self:setStyle("width", tostring(px) .. "px")
end

--[[ 设置文本内容（运行时覆盖 DOM 里的文本）。

    ⚠️ 直接改 control.text 会在下一帧被 DOM 文本覆盖，
       必须走这个 API —— 它写 node._text，渲染时优先级最高。
]]--
function Node:setText(t)
  if self._text == t then return self end
  self._text = t
  if not self._inlineDirty then self._inlineDirty = {} end
  self._inlineDirty["*text*"] = true
  return self
end

--[[ 显示 / 隐藏元素。

    隐藏 = display:none，会被布局器和渲染器完全跳过（不占位）。
    比 visible=false 更彻底 —— 后者仍占位。

    node:setVisible(false)  隐藏
    node:setVisible(true)   显示
]]--
function Node:setVisible(vis)
  local v = vis and "block" or "none"
  if self._displayOverride == v then return self end
  self._displayOverride = v
  if not self._inlineDirty then self._inlineDirty = {} end
  self._inlineDirty["display"] = true
  return self
end

function Node:show() return self:setVisible(true) end
function Node:hide() return self:setVisible(false) end

--=============================================================================
-- 遍历
--=============================================================================

--[[ 先序遍历，回调 fn(node, depth) ]]--
function D.walk(node, fn, depth)
  depth = depth or 0
  if not node then return end
  fn(node, depth)
  for i = 1, #node.children do
    D.walk(node.children[i], fn, depth + 1)
  end
end

--[[ 收集所有元素节点 ]]--
function D.elements(root)
  local out = {}
  D.walk(root, function(n)
    if n:isElement() then out[#out + 1] = n end
  end)
  return out
end

--[[ 收集所有节点（含文本）]]--
function D.allNodes(root)
  local out = {}
  D.walk(root, function(n) out[#out + 1] = n end)
  return out
end

--[[ 取一个元素的【直接文本子节点】拼成的字符串。

     ★ 规则与渲染层 writeControl 里的取文本逻辑保持一致：
       - node._text（脚本运行时设置）优先
       - 否则拼接所有直接文本子节点
       - 不含子元素的文字（那些由子元素自己渲染）

     用途：裁剪容器（image 类型）没有 text 字段，
           需要把文字提取出来交给额外的子文本框显示。
]]--
function D.textOf(node)
  if not node then return nil end
  if node._text ~= nil then return node._text end

  local parts, found = {}, false
  for i = 1, #node.children do
    local c = node.children[i]
    if c:isText() then
      parts[#parts + 1] = c.text
      found = true
    end
  end
  if not found then return nil end
  return table.concat(parts)
end

--[[ 统计规模，用于性能观察 ]]--
function D.stats(root)
  local s = { elements = 0, texts = 0, maxDepth = 0 }
  D.walk(root, function(n, d)
    if n:isElement() then s.elements = s.elements + 1
    elseif n:isText() then s.texts = s.texts + 1 end
    if d > s.maxDepth then s.maxDepth = d end
  end)
  return s
end

--=============================================================================
-- 调试输出
--=============================================================================

function D.dump(root, maxDepth)
  maxDepth = maxDepth or 20
  local lines = {}
  D.walk(root, function(n, d)
    if d > maxDepth then return end
    local pad = string.rep("  ", d)
    if n:isText() then
      local t = n.text
      if #t > 40 then t = t:sub(1, 40) .. "..." end
      lines[#lines + 1] = pad .. '"' .. t .. '"'
    elseif n:isElement() then
      local s = pad .. "<" .. n.tag
      if n.id then s = s .. ' id="' .. n.id .. '"' end
      if #n.classList > 0 then s = s .. ' class="' .. table.concat(n.classList, " ") .. '"' end
      s = s .. ">"
      lines[#lines + 1] = s
    else
      lines[#lines + 1] = pad .. "#root"
    end
  end)
  return table.concat(lines, "\n")
end

D.Node = Node

return D