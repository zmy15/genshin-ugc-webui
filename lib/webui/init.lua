--[[============================================================================
  webui/init.lua  ——  入口模块

  用 Lua 在千星奇域 UGC 里渲染 HTML/CSS 风格的界面。

  用法：
    local webui = require('webui')
    local ui = webui.new({ root = 挂载的控件, handlers = {...} })
    ui:render(htmlText, cssText)
    ui:startLoop()

  目录结构：
    webui/init.lua     本文件，对外 API
    webui/dom.lua      DOM 节点树
    webui/html.lua     HTML 解析器
    webui/css.lua      CSS 解析器 + 选择器匹配
    webui/style.lua    层叠/继承/默认样式
    webui/layout.lua   盒模型布局计算
    webui/render.lua   控件池 + diff 渲染
    webui/event.lua    事件绑定与派发
    webui/color.lua    颜色解析
    webui/util.lua     通用工具

  ⚠️ 运行环境约束（真机实测）：
    - Lua 5.3，但 io/package/load/coroutine/string.dump/pack/unpack 均不可用
    - OnUpdate 不被驱动，逐帧靠 TweenSequence 递归实现
    - 代码只用 Lua 5.1 就有的语言特性，保证兼容
==============================================================================]]

local util   = require('webui.util')
local dom    = require('webui.dom')
local html   = require('webui.html')
local css    = require('webui.css')
local color  = require('webui.color')
local style  = require('webui.style')
local layout = require('webui.layout')
local render = require('webui.render')
local clip   = require('webui.clip')
local event  = require('webui.event')

local M = {}

M.VERSION = "0.1.0"

-- 复用内部模块，方便单独测试与调试
M.util   = util
M.dom    = dom
M.html   = html
M.css    = css
M.color  = color
M.style  = style
M.layout = layout
M.render = render
M.clip   = clip
M.event  = event

--[[----------------------------------------------------------------------------
  一个 WebUI 实例 = 一棵 DOM 树 + 一套样式 + 一棵控件树
------------------------------------------------------------------------------]]
local Instance = {}
Instance.__index = Instance

function M.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Instance)

  self.rootControl = opts.root        -- 挂载的根控件（必须提供）
  self.handlers    = opts.handlers or {}
  self.stylesheets = {}
  self.doc         = nil
  self.rendered    = nil              -- render 模块的句柄
  self.ticking     = false
  self.prefabs     = opts.prefabs     -- { container=, textbox=, button=, image= }
  self.boundCount  = 0

  if not self.rootControl then
    util.warn("webui.new: 未提供 root 控件，渲染会失败")
  end

  return self
end

--[[ 设置 HTML 内容，重新构建 DOM
     会自动提取 <style> 标签里的 CSS ]]--
function Instance:setHTML(src)
  self.doc = html.parse(src)

  -- ★ 标记 DOM 已变：渲染器需要预回收旧控件，否则会多建一轮
  self._domChanged = true

  --[[ 重置样式表。

      ⚠️ 不能累加！每次 setHTML 都追加一份会导致样式表无限增长 ——
         实测踩过：动态页面操作 40 次后积累 40 份重复 CSS，
         样式计算量线性上升，界面越来越卡。

      内联 <style> 从新 DOM 重新提取；addCSS 添加的额外样式表
      存在 _extraSheets 里，这里一并恢复。
  ]]--
  self.stylesheets = {}

  local styles = html.extractStyles(self.doc)
  for i = 1, #styles do
    local s = styles[i]
    if s and s ~= "" then
      self.stylesheets[#self.stylesheets + 1] = css.parse(s)
    end
  end

  -- 恢复通过 addCSS 添加的样式表
  if self._extraSheets then
    for i = 1, #self._extraSheets do
      self.stylesheets[#self.stylesheets + 1] = self._extraSheets[i]
    end
  end

  return self
end

--[[ 添加 CSS 样式表文本（跨 setHTML 保留）]]--
function Instance:addCSS(src)
  local sheet = css.parse(src)
  if not self._extraSheets then self._extraSheets = {} end
  self._extraSheets[#self._extraSheets + 1] = sheet
  self.stylesheets[#self.stylesheets + 1] = sheet
  return self
end

--[[ 一次完成 HTML + CSS + 渲染 ]]--
function Instance:render(src, cssSrc)
  if src then self:setHTML(src) end
  if cssSrc then self:addCSS(cssSrc) end
  return self:flush()
end

--[[ 重新计算样式 + 布局 + 渲染（不重新解析 HTML）]]--
function Instance:flush()
  if not self.doc then
    util.warn("webui.flush: 尚无 DOM，请先 setHTML")
    return self
  end
  if not self.rootControl then
    util.warn("webui.flush: 无 root 控件")
    return self
  end

  -- 1. 计算样式（层叠 + 继承）
  style.apply(self.doc, self.stylesheets)

  -- 2. 布局（算出每个节点的绝对位置）
  local canvasW, canvasH = util.canvasSize()
  layout.compute(self.doc, canvasW, canvasH)

  -- 3. 渲染（控件池 + diff 写入）
  if not self.rendered then
    self.rendered = render.new(self.rootControl, { prefabs = self.prefabs })
    -- 容器开启光标门控（CursorEvent 的前提）
    event.enableCursor(self.rootControl)

    -- ★ :hover / :active 状态变化时，标记需要重算样式
    local self_ = self
    event.setStateHook(function(node)
      -- 清掉该节点的运行时样式缓存，让新的计算样式生效
      -- （伪类匹配结果变了，style.apply 会算出不同结果）
      if node._inline then
        -- 运行时样式优先级最高，伪类改不了它 —— 这是预期行为
      end
      self_._styleDirty = true
      -- 让渲染器清掉该节点的字段缓存
      if not node._inlineDirty then node._inlineDirty = {} end
      node._inlineDirty["background-color"] = true
      node._inlineDirty["color"] = true
      node._inlineDirty["opacity"] = true
    end)
  end

  -- ★ 传 domChanged：只在 DOM 重新解析后为 true
  --    （若每帧都为 true，会导致每帧重建全部控件 —— 实测踩过）
  local domChanged = self._domChanged == true
  self._domChanged = false

  self.rendered:update(self.doc, domChanged)

  -- 4. 绑定事件
  self:_bindEvents()

  return self
end

--[[ 为所有带交互属性的元素绑定事件 ]]--
function Instance:_bindEvents()
  if not self.doc then return end
  local bound = 0

  local function walkNode(node)
    if node:isElement() then
      local entry = self.rendered and self.rendered.live[node]
      if entry then
        -- ★ 优先绑到 button 覆盖层（hot），因为只有它有光标事件；
        --   视觉层（textbox/container）没有 AddCursorEventListener。
        local target = entry.hot or entry.control
        if target then
          -- 只在尚未绑定时绑定（避免重复注册）
          if not node._eventsBound then
            local n = event.bind(node, target, self.handlers)
            if n > 0 then
              node._eventsBound = true
              bound = bound + n
            end
          end
        end
      end
    end
    for i = 1, #node.children do
      walkNode(node.children[i])
    end
  end

  for i = 1, #self.doc.children do
    walkNode(self.doc.children[i])
  end

  self.boundCount = bound
  return bound
end

--[[ 绑定事件处理器 ]]--
function Instance:bind(name, fn)
  self.handlers[name] = fn
  return self
end

--[[ 启动逐帧循环
     OnUpdate 在真机上不被驱动（R9/R11 实测），
     所以用 TweenSequence 递归实现。 ]]--
function Instance:startLoop(fps)
  if self.ticking then return self end
  self.ticking = true

  local interval = 1.0 / (fps or 50)
  local self_ = self

  local function tick()
    if not self_.ticking then return end

    -- 逐帧逻辑：目前是重新布局（后续可加动画/状态更新）
    util.try(function()
      self_:flush()
    end)

    -- 递归续期
    util.try(function()
      local seq = game.TweenSequence()
      if seq then
        seq:AppendInterval(interval)
        seq:AppendCallback(tick)
        seq:Play()
      end
    end)
  end

  util.try(tick)
  return self
end

--[[ 停止逐帧循环 ]]--
function Instance:stopLoop()
  self.ticking = false
  return self
end

M.Instance = Instance

return M
