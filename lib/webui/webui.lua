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

local util   = require('webui_util')
local dom    = require('webui_dom')
local html   = require('webui_html')
local css    = require('webui_css')
local color  = require('webui_color')
local style  = require('webui_style')
local layout = require('webui_layout')
local render = require('webui_render')
local clip   = require('webui_clip')
local event  = require('webui_event')

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

--=============================================================================
-- 一步挂载（把样板代码全收进库里）
--=============================================================================

--[[ 一步完成「找根控件 + 渲染 + 挂事件 + 开逐帧循环」。

     ⚠️ 存在的意义：
       原来每个页面都要手写这一段样板 —— 找 Root、建实例、render、
       bindImages、startLoop，还要处理"Root 还没准备好"时用 OnUpdate 重试。
       这些与页面内容无关：写 300 行 CSS 和写 3 行 CSS 都一模一样。
       mount 把它们收进库，开发者只需要给 HTML / CSS / 事件。

     ★★ 关于生命周期（重要，决定了本函数为什么这样设计）：

       引擎按【固定名称】在【入口脚本自己的环境】里查找
       OnInit / OnStart / OnUpdate / OnDestroy —— 见
       docs/client_control_api.md「运行时按固定名称查找并调用」。

       而本文件是 require 进来的模块，真机上每个模块有【独立 _ENV】
       （docs/webui_feasibility.md：模块不执行 OnInit/OnStart）。
       所以在 init.lua 里写 _G.OnStart 是【无效的】——
       引擎不会去模块的环境里找。

       因此 mount 只返回一个句柄，由【入口脚本】用 3 行接上生命周期；
       这 3 行是引擎的硬性约定，无法再省。

     用法（入口脚本里）：
       local webui = require('webui')

       local app = webui.mount{
         root    = "Root",
         prefabs = { container=1073741933, textbox=1073741934,
                     button=1073741935,    image=1073741938 },
         html    = "<div class=\"card\">你好</div>",
         css     = ".card { width:200px; height:60px; background-color:#333; }",
         on      = {
           onOk = function(e) ... end,   -- 对应 HTML 里 onclick="onOk"
         },
       }

       function OnStart()    app:start()  end
       function OnUpdate(dt) app:update() end
       function OnDestroy()  app:stop()   end

     ★ 为什么 prefabs 仍要求显式传：
       控件模板索引只在编辑器里配置，库无从发现，猜错会静默失败
       （控件建不出来但不报错）。宁可让开发者写一次，也不要埋这个坑。

     ★ 事件模型（Lua 当 JS 用）：
       HTML 里写 onclick="onOk"，on 表里写 on = { onOk = function(e) end }。
       与原来 handlers 的语义一致，只是搬进了 mount 参数。
==============================================================================]]
function M.mount(opts)
  opts = opts or {}

  local App = {}
  App.__index = App

  local app = setmetatable({
    ui       = nil,                       -- webui 实例
    bound    = false,                     -- 是否已挂载成功
    retry    = 0,                         -- 等待 Root 的重试次数
    maxRetry = opts.maxRetry or 120,
    rootName = opts.root or "Root",
    handlers = opts.on or {},
    logTag   = opts.logTag or "[webui]",
  }, App)

  --[[ 内部：尝试挂载。
       返回 true = 已处理完（成功，或已放弃）；
       返回 false = Root 还没准备好，请稍后再试。 ]]--
  function App:_tryMount()
    if app.bound then return true end

    local root = nil
    util.try(function()
      if type(game) == "table" and type(game.FindClientUIRoot) == "function" then
        root = game.FindClientUIRoot(app.rootName)
      end
    end)

    if not root then return false end

    local ui = M.new({
      root     = root,
      prefabs  = opts.prefabs,
      handlers = app.handlers,
    })
    app.ui = ui

    local ok, err = util.try(function()
      ui:render(opts.html, opts.css)
    end)
    if not ok then
      util.warn("mount: 渲染失败 " .. tostring(err))
    end

    -- 交给调用方的钩子：挂图片形状、拿 DOM 做动态内容等
    if type(opts.onReady) == "function" then
      util.try(function() opts.onReady(ui) end)
    end

    if opts.loop ~= false then
      ui:startLoop(opts.fps)
    end

    app.bound = true
    return true
  end

  -- 内部：开关 script 的逐帧更新（用于"等 Root"的重试）
  local function setUpdate(on)
    util.try(function()
      if type(script) == "table" and type(script.EnableUpdate) == "function" then
        script:EnableUpdate(on and true or false)
      end
    end)
  end

  --[[ 由入口脚本的 OnStart() 调用。

       挂载成功即返回；若 Root 尚未创建，则打开逐帧更新，
       交给 update() 继续重试（真机上 Root 常比脚本晚一帧就绪）。 ]]--
  function App:start()
    if self:_tryMount() then
      if type(opts.onStart) == "function" then
        util.try(function() opts.onStart(self.ui, self) end)
      end
      return self
    end
    setUpdate(true)
    return self
  end

  --[[ 由入口脚本的 OnUpdate(dt) 调用。

       ⚠️ 真机上 OnUpdate 【不被驱动】（docs/引擎能力与限制.md：
          tick=-1，累计 0.00 秒），所以这里只做"等 Root"的兜底重试；
          真正的逐帧渲染由 ui:startLoop 用递归 TweenSequence 完成。 ]]--
  function App:update(dt)
    if self.bound then return self end

    if self:_tryMount() then
      setUpdate(false)
      if type(opts.onStart) == "function" then
        util.try(function() opts.onStart(self.ui, self) end)
      end
      return self
    end

    self.retry = self.retry + 1
    if self.retry >= self.maxRetry then
      util.warn(string.format("mount: 等待 Root 超时（%d 帧）", self.maxRetry))
      setUpdate(false)
    end
    return self
  end

  --[[ 由入口脚本的 OnDestroy() 调用 ]]--
  function App:stop()
    if self.ui then
      util.try(function() self.ui:stopLoop() end)
    end
    if type(opts.onUnmount) == "function" then
      util.try(function() opts.onUnmount(self.ui, self) end)
    end
    self.bound = false
    return self
  end

  --[[ 便捷：换内容重新渲染（例如根据状态切换页面） ]]--
  function App:render(html, css)
    if not self.ui then return self end
    util.try(function() self.ui:render(html, css) end)
    return self
  end

  --[[ 便捷：运行时改某个元素的文字。

       ★ 必须走 DOM（node:setText），不能写 control.text ——
         渲染器每帧都会用 DOM 文本覆盖控件（render.lua 的 tset("text", ...)）。 ]]--
  function App:setText(id, text)
    if not self.ui or not self.ui.doc then return self end
    local found = nil
    dom.walk(self.ui.doc, function(n)
      if not found and n:isElement() and n.attrs and n.attrs.id == id then
        found = n
      end
    end)
    if found and type(found.setText) == "function" then
      util.try(function() found:setText(text) end)
    else
      util.warn("mount:setText 找不到元素 #" .. tostring(id))
    end
    return self
  end

  --[[ 便捷：运行时改某个元素的样式（内联样式优先级最高，:hover 改不动它） ]]--
  function App:setStyle(id, prop, value)
    if not self.ui or not self.ui.doc then return self end
    local found = nil
    dom.walk(self.ui.doc, function(n)
      if not found and n:isElement() and n.attrs and n.attrs.id == id then
        found = n
      end
    end)
    if found and type(found.setStyle) == "function" then
      util.try(function() found:setStyle(prop, value) end)
    else
      util.warn("mount:setStyle 找不到元素 #" .. tostring(id))
    end
    return self
  end

  --[[ ★ 若调用 mount 时 Root 已经就绪，这里直接挂上，
       不必等 OnStart（例：脚本在 Root 建好之后才加载）。 ]]--
  app:_tryMount()

  return app
end

M.Instance = Instance

return M
