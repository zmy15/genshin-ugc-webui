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
local sprite = require('webui_sprite')
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
M.sprite = sprite
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
     所以用 TweenSequence 递归实现。

     ★ onTick(dt) —— 游戏逻辑钩子（2026-10-08 新增）。

       原来这个循环【只做 flush()】，没有任何地方能挂游戏逻辑
       （重力、跳跃、障碍移动、碰撞检测）。做小恐龙这类玩法时
       只能自己再起一条 TweenSequence，两条循环各跑各的，
       时序对不齐。

       现在把逻辑钩子接进同一条循环，保证：
         onTick(dt) 先跑（更新状态）-> 再 flush()（渲染）

       这正是「先改数据再渲染」的正确顺序。

     ⚠️ dt 是【固定步长】（1/fps），不是真实帧间隔 ——
        因为 TweenSequence 的 AppendInterval 是固定值。
        用固定步长做物理反而更好（结果可复现、不受掉帧影响）。 ]]--
function Instance:startLoop(fps, onTick)
  if self.ticking then return self end
  self.ticking = true

  if type(onTick) == "function" then
    self.onTick = onTick
  end

  local interval = 1.0 / (fps or 50)
  local self_ = self

  local function tick()
    if not self_.ticking then return end

    -- ① 先跑游戏逻辑（更新 DOM 上的状态）
    if type(self_.onTick) == "function" then
      util.try(function() self_.onTick(interval) end)
    end

    -- ② 再渲染（重新布局 + diff 写入）
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

--[[ 设置/替换逐帧逻辑钩子（循环已在跑时也能换） ]]--
function Instance:setTick(fn)
  self.onTick = fn
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

       local app
       app = webui.mount{
         root    = "Root",
         prefabs = { container=1073741933, textbox=1073741934,
                     button=1073741935,    image=1073741938 },
         html    = "<div class=\"card\">你好</div>",
         css     = ".card { width:200px; height:60px; background-color:#333; }",
         -- ★ onReady 触发时上面的 `local app` 还没被赋值，
         --   所以它必须用第二个参数，不能用外层闭包。
         onReady = function(ui, app) app:setText("t", "就绪") end,
         on      = {
           onOk = function(e) ... end,   -- 对应 HTML 里 onclick="onOk"
         },
         -- ★ 键盘（R20 真机验证，2026-10-08）：做游戏必用
         keys = {
           jump = function() ... end,    -- KeyboardJumpKeyDown
           left = function() ... end,    -- KeyboardMoveLeftKeyDown
         },
         -- ★ 游戏逻辑钩子：每帧【先跑 onTick(dt) 再渲染】
         onTick = function(dt) ... end,
       }

       function OnStart()    app:start()  end
       function OnUpdate(dt) app:update() end
       function OnDestroy()  app:stop()   end

     ★ 关于 keys（真机实测要点，详见 docs/引擎能力与限制.md §5.2）：
        · 只绑在【root 一个挂载点】上 —— 同一个事件会被每个绑定它的
          控件各收一遍，绑多处会导致"按一次跳 3 次"
        · 键名可用语义别名（jump / left / right / key1~4 / padJump）
          或完整枚举名（KeyboardJumpKeyDown）
        · 回调一律返回 false，不会吞掉同容器内其他按键

     ★ 关于 onTick(dt)：
        · dt 是【固定步长】(1/fps)，不是真实帧间隔 —— 做物理反而更好
          （结果可复现，不受掉帧影响）
        · 顺序保证：onTick 先更新状态 -> 再 flush() 渲染
        · 不传 onTick 时，循环行为与从前完全一致（只 flush）

     ★ 为什么 prefabs 仍要求显式传：
       控件模板索引只在编辑器里配置，库无从发现，猜错会静默失败
       （控件建不出来但不报错）。宁可让开发者写一次，也不要埋这个坑。

     ★ 事件模型（Lua 当 JS 用）：
       HTML 里写 onclick="onOk"，on 表里写 on = { onOk = function(e) end }。
       与原来 handlers 的语义一致，只是搬进了 mount 参数。

     ★★ 三个钩子的触发时机（写错就是「界面不出来、还没日志」）：

       onReady(ui, app)   —— 渲染完成、事件已绑，
                            但【调用方的 app 此时还没被赋值】（mount 尚未返回）。
                             所以这个回调里只能用第二个参数 app。
       onStart(ui, app)   —— 由 App:start() 调用，app 一定已就绪。
       onUnmount(ui, app) —— 由 App:stop() 调用。

       规律：需要「用渲染好的 DOM 做事」用 onReady；
             只想「初次刷一遍数据」用 onStart 最省心。
==============================================================================]]
function M.mount(opts)
  opts = opts or {}

  local App = {}
  App.__index = App

  --[[ ★ 自引用：让 _tryMount 内部的回调能拿到【尚未返回给调用方】的 app。

       ⚠️ 为什么必须有它（真机踩过，症状是「没有任何日志」）：
          mount 的返回值要等整个函数跑完才赋给调用方的 `app`，
          但 onReady 是在 _tryMount 里就触发的 —— 此刻调用方的
          `local app` 仍然是 nil。于是 onReady 里写 `app:setText(...)`
          会抛 "attempt to index a nil value (upvalue 'app')"，
          而这个错误被 util.try 的 pcall 吞掉，只留一行 warning，
          表现为「界面不出来 + 日志空空」。
     ]]--
  local appRef = nil

  local app = setmetatable({
    ui       = nil,                       -- webui 实例
    bound    = false,                     -- 是否已挂载成功
    retry    = 0,                         -- 等待 Root 的重试次数
    maxRetry = opts.maxRetry or 120,
    rootName = opts.root or "Root",
    handlers = opts.on or {},
    logTag   = opts.logTag or "[webui]",
  }, App)

  -- 建立自引用（此后 onReady 里可直接用第二个参数，见下）
  appRef = app

  --[[ 内部：尝试挂载。
       返回 true = 已处理完（成功，或已放弃）；
       返回 false = Root 还没准备好，请稍后再试。 ]]--
  function App:_tryMount()
    if app.bound then return true end

    local root = nil
    util.try(function()
      --[[ ★ 不要用 `type(game) == "table"` 来守门。

           ★ 实测澄清（2026-10-07，probe 诊断模块读回）：
             本机 type(game) 确实是 "table"，typeof(game) 也是 "table"。
             所以【这一条不是】main.lua 空白的成因 —— 真正成因见
             beginRetry 上面那段（OnUpdate 不被驱动 + 模块 _ENV 身份）。

           但仍要保留现在的写法，理由是通用的：
             官方 API 文档把 game 说明为宿主对象，typeof() 的用途就是
             "识别宿主对象"；script 实测 typeof 为 "Script"（不是 table）。
             这类全局对象的 type() 在不同实现/版本下并不可靠，
             而【成员是否存在】才是真正决定能否调用的条件。

           即：判断"能不能用"，就只判断成员；不要判断对象本身的类型。
      ]]--
      if type(game) ~= "nil" and type(game.FindClientUIRoot) == "function" then
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

    -- ★ 游戏逻辑钩子（在 startLoop 之前设定，首帧就能跑）
    if type(opts.onTick) == "function" then
      ui.onTick = opts.onTick
    end

    local ok, err = util.try(function()
      ui:render(opts.html, opts.css)
    end)
    if not ok then
      util.warn("mount: 渲染失败 " .. tostring(err))
    end

    -- ★★ 绑定按键（R20 真机验证可用，2026-10-08）
    --
    --   ★ 只绑【一个】挂载点（root）—— 真机实测同一个事件会被
    --     每个绑定它的控件各收一遍：若同时绑 root 和子控件，
    --     按一次跳跃会跳 3 次。
    if type(opts.keys) == "table" then
      local n = event.bindKeys(root, opts.keys)
      app.keyCount = n
      if n == 0 then
        util.warn("mount: 按键绑定 0 个（键名无法解析，或控件不支持）")
      end
    end

    -- 交给调用方的钩子：挂图片形状、拿 DOM 做动态内容等。
    --
    -- ★ 第二个参数是 app 本身：onReady 触发时调用方的
    --   `local app` 还没被赋值（见 appRef 处的说明），
    --   所以要给调用方一条能立刻用上的路。
    if type(opts.onReady) == "function" then
      util.try(function() opts.onReady(ui, appRef) end)
    end

    if opts.loop ~= false then
      ui:startLoop(opts.fps, opts.onTick)
    end

    app.bound = true
    return true
  end

  -- 内部：开关 script 的逐帧更新。
  -- ★ 注意：模块里的 script 是【模块自己的身份】，
  --   打开它【不会】驱动入口脚本的 OnUpdate（见上面 beginRetry 的说明）。
  --   这里保留只是为了兼容"调用方恰好在入口环境"的情况，不作依赖。
  local function setUpdate(on)
    util.try(function()
      if type(script) ~= "nil" and type(script.EnableUpdate) == "function" then
        script:EnableUpdate(on and true or false)
      end
    end)
  end

  --[[ ★★★ 等 Root 就绪 —— 必须用【递归 TweenSequence】，不能用 OnUpdate。

       ⚠️⚠️ 这里曾经是 main.lua "界面空白 + 几乎无日志"的【真正根因】，
           排查花了好几轮。两个事实叠加造成：

           ① 真机上 `OnUpdate` 【不被驱动】
              （docs/引擎能力与限制.md §一：R9/R11 实测 tick=-1，累计 0.00 秒）

           ② 库是 require 进来的模块，有【独立 _ENV】，
              模块里的 `script` 是【模块自己的身份】，不是入口脚本的
              （docs/webui_feasibility.md：每个模块独立 _ENV，script 是模块自己的身份）

           于是 `script:EnableUpdate(true)` 打开的是【模块】的逐帧更新，
           而引擎调用的是【入口脚本 main.lua】的 OnUpdate —— 两者不是一回事。

           结果：Root 晚一帧就绪时（真机常态），
                 App:update 永远不会被调用 → mount 永远挂不上，
                 而且【什么都不打印】（只有 120 帧超时那条，也等不到）。

           ⚠️ 对照：probe.lua 能跑，是因为它在【入口脚本自己的环境】里
              调 script:EnableUpdate(true) —— 那才真的驱动了自己的 OnUpdate。

       ★ 正确做法：用递归 TweenSequence 自己驱动重试（R13 实测 698 帧 0 错误）。
         这条路径不依赖任何 _ENV 身份，与 ui:startLoop 用的是同一套机制。
  ]]--
  local retryTimer = nil

  local function stopRetry()
    if retryTimer then
      util.try(function() if retryTimer.Kill then retryTimer:Kill() end end)
      retryTimer = nil
    end
  end

  local function beginRetry()
    if retryTimer then return end          -- 已在重试中
    if app.bound then return end

    -- 同时也尝试打开引擎的逐帧更新：如果调用方【恰好】在入口脚本环境里
    -- 触发了 start()，这条也能生效（多一条路，但【不能依赖】它 ——
    -- 模块里的 script 是模块自己的身份，驱动的不是入口脚本的 OnUpdate）。
    setUpdate(true)

    local function tick()
      retryTimer = nil
      if app.bound then return end

      if app:_tryMount() then
        setUpdate(false)
        if type(opts.onStart) == "function" then
          util.try(function() opts.onStart(app.ui, app) end)
        end
        return
      end

      app.retry = app.retry + 1
      if app.retry >= app.maxRetry then
        util.warn(string.format("mount: 等待 Root 超时（%d 帧）", app.maxRetry))
        setUpdate(false)
        return
      end

      -- 续期：递归 TweenSequence（真机唯一可靠的逐帧手段）
      util.try(function()
        local seq = game.TweenSequence()
        if seq then
          seq:AppendInterval(1.0 / 50)
          seq:AppendCallback(tick)
          seq:Play()
          retryTimer = seq
        end
      end)
    end

    -- 第一帧稍等，给 Root 创建留出时间
    util.try(function()
      local seq = game.TweenSequence()
      if seq then
        seq:AppendInterval(1.0 / 50)
        seq:AppendCallback(tick)
        seq:Play()
        retryTimer = seq
      else
        tick()                            -- 没有 Tween 就立即试一次
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
    beginRetry()
    return self
  end

  --[[ 由入口脚本的 OnUpdate(dt) 调用。

       ⚠️ 真机上 OnUpdate 【不被驱动】（docs/引擎能力与限制.md：
          tick=-1，累计 0.00 秒），所以【不能】依赖它来等 Root ——
          重试已改由 beginRetry 的递归 TweenSequence 负责。

       本方法保留只为兼容手册里的 3 行接线；若它恰好被驱动，
       也只会让重试更快一点，不会有副作用。 ]]--
  function App:update(dt)
    if self.bound then return self end

    if self:_tryMount() then
      setUpdate(false)
      if type(opts.onStart) == "function" then
        util.try(function() opts.onStart(self.ui, self) end)
      end
      return self
    end

    -- 兜底：确保 Tween 重试已启动（即便调用方漏了 start()）
    beginRetry()
    return self
  end

  --[[ 由入口脚本的 OnDestroy() 调用 ]]--
  function App:stop()
    if self.ui then
      util.try(function() self.ui:stopLoop() end)
    end
    -- ★ 解绑按键监听（用同一回调引用移除，防泄漏）
    util.try(function() event.unbindKeys() end)
    -- ★ 停掉"等 Root"的重试链，避免销毁后还在跑
    stopRetry()
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
       不必等 OnStart（例：脚本在 Root 建好之后才加载）。

        ★★ 若还没就绪，【必须顺手启动 Tween 重试】：
           真机上 Root 常比脚本晚一帧就绪，而 OnUpdate 不被驱动，
           所以这里不启动的话，就只能等调用方调 start() ——
           一旦调用方漏了或时序不对，页面就永远挂不上，
           而且什么都不打印（这正是 main.lua 之前的表现）。
    ]]--
  if not app:_tryMount() then
    beginRetry()
  end

  return app
end

M.Instance = Instance

return M
