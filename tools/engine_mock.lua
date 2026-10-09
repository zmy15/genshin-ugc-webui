--[[ 真机仿真 mock

     ★ 严格模拟真机的三个限制（均经真机探针确认）：

       1. 只有引擎预定义字段可写，【自定义字段一律静默写失败】
          探针证据（probe_field.lua）：
            __webuiParent 写=false 读=true 值=nil
            myCustomFlag  写=false 读=true 值=nil
            bgColor       写=true  读=true 值=...   ← 预定义字段正常

       2. 字段按控件类型封死
          容器/按钮没有 bgColor/text/fontColor

       3. 无 reparent API，控件固定在创建时的父下
          但 GetChildren() 可用，能反查真实父子关系

     ⚠️ 之前的 mock 用普通 table，自定义字段随便写，
        所以完全测不出「库依赖自定义字段」这个致命 bug。
        这个 mock 就是为了在本地拦住这类问题。
]]--

local EngineMock = {}

--[[ 创建一套仿真环境。
     返回 { game=..., controls={...}, created=..., dataOf=fn }
]]--
function EngineMock.new(prefabs)
  local created = 0
  local controls = {}
  local dataMap = {}      -- proxy -> 内部数据
  local externalRoots = {}  -- ★ 模拟"编辑器里搭好的"根控件
  local tweenCalls = 0    -- ★ game.Tween 被 Play 的次数（R28）
  local tweenSeqs = {}    -- ★ 创建过的 tween 对象
  local lastTween = nil   -- ★ 最近一次 Play 的 { control, props, duration }
  local sentSignals = {}  -- ★ 客户端发出的服务器信号 { name=, params= }
  local handlers = {}     -- ★ 注册过的服务器信号监听 { [name] = {cb1, cb2} }
  local sendHook = nil    -- ★ 模拟"发送时抛异常"（真机上是 pcall 失败的来源）

  local COMMON = {
    anchorMinX=1, anchorMinY=1, anchorMaxX=1, anchorMaxY=1,
    pivotX=1, pivotY=1,
    anchoredPositionX=1, anchoredPositionY=1,
    sizeDeltaX=1, sizeDeltaY=1,
    visible=1, active=1, name=1,
    localScaleX=1, localScaleY=1, localRotationZ=1,
    localRotationX=1, localRotationY=1,
    canControllerFocus=1,
  }
  local PER_KIND = {
    textbox   = { bgColor=1, text=1, fontColor=1, fontSize=1,
                  horizontalAlignment=1, verticalAlignment=1,
                  outlineColor=1, lineSpacing=1 },
    container = { },
    button    = { interactable=1, raycastTarget=1, clickAudioId=1 },
    area      = { raycastTarget=1 },
    --[[ ★ 图片控件（R16 真机实测补全）

         ⚠️ 关键：image 类型【没有】bgColor / text ——
            这正是"字段按类型封死"的体现。
             写 bgColor 会静默失败（真机行为）。
         有 imageColor / enableMask 等字段。
    ]]--
    image     = { imageColor=1, imageType=1, enableMask=1,
                  reverseMaskArea=1, enableSoftEdge=1, softEdgeMode=1,
                  softEdgeWidthX=1, softEdgeWidthY=1,
                  horizontalSoftRange=1, verticalSoftRange=1,
                  fillType=1, fillHorizontalType=1, fillVerticalType=1,
                  fillRadial90Type=1, fillRadialType=1, fillAmount=1 },
  }

  --[[ ★ 只读字段：真机上写不进去。

       R16 实测：imageType 写=false，读回仍是原值。
       而 imageId / imageSource 也是只读 —— 换图必须走 SetImage 方法。
  ]]--
  local READONLY = {
    image = { imageId=1, imageSource=1, imageType=1 },
  }

  local function makeControl(kind, parent)
    created = created + 1
    local data = {
      kind = kind,
      fields = { active = true, visible = true },
      children = {},
      listeners = {},
      keyListeners = {},        -- ★ 按键监听（AddKeyEventListener）
    }

    --[[ ★★★ 文本框有【引擎默认背景色】（R21 真机实证，2026-10-08）

         CSS 里不写 background-color 时，真机的文本框【不是透明的】，
         而是画一层默认深色底（截图量得约 #535353）。
         若字色也是深色 -> 字与底同色 -> **文字完全看不见**。

         ⚠️ 这正是 R21 在真机上踩的坑（对比度只有 3）。
            如果 mock 让 bgColor 停在 nil，本地就【永远测不出】
            "忘了写背景色"这个 bug —— 属于「测试替身必须忠实」
            那条方法学（见 docs/引擎能力与限制.md §七）。

         ★ 真机量到的近似值：(83,83,83) 的字段值 / 截图上呈现为 (49,48,48)
           （截图受渲染与抗锯齿影响，这里取声明侧的 #535353）。
    ]]--
    if kind == "textbox" then
      data.fields.bgColor = { r = 83, g = 83, b = 83, a = 255 }
    end

    --[[ ★★★ 图片控件的"未贴图"状态是【可见的默认外观】（R29 补）

         ⚠️ 为什么必须模拟：真机上 image 控件从模板实例化后，
            【本来就会显示模板自带的图】，不是"什么都不显示"。
            我们用的方形图 100001 是【白→灰渐变】——
            所以一个【没被 SetImage + 没被染色】的矩形控件，
            在屏幕上就是【一块白】。

         这正是用户报的「固定间隔出现一个白色障碍」的成因：
           生成障碍发生在 onTick 里，而控件要等同一帧的 flush 才建出来
           -> 那一帧的 reimage 查不到控件，静默跳过
           -> flush 建出的新控件没图没色 = 白块。

         ★ 若 mock 让 imageId 停在 nil（无图 = 透明），
           本地就【永远测不出】这个 bug —— 与 §"测试替身必须忠实"
           是同一个方法学问题（对照 textbox 默认底色的处理）。

         ★ mock 的表示：imageId = nil 视为"模板默认图"，
           即渲染出来是白色。渲染器/应用层必须把它换成 100001 + 染色。 ]]--
    if kind == "image" then
      data.fields.imageId = nil          -- 模板默认图（视觉上 = 白）
      data.fields.imageColor = nil       -- 未染色 -> 显示原色（白）
    end

    local allowed = {}
    for k in pairs(COMMON) do allowed[k] = true end
    for k in pairs(PER_KIND[kind] or {}) do allowed[k] = true end

    local METHODS = {
      GetChildren = function() return data.children end,
      SetActive = function(_, v) data.fields.active = v end,
      SetVisible = function(_, v) data.fields.visible = v end,
      SetAnchoredPosition = function(_, x, y)
        data.fields.anchoredPositionX = x
        data.fields.anchoredPositionY = y
      end,
      SetSizeDelta = function(_, w, h)
        data.fields.sizeDeltaX = w
        data.fields.sizeDeltaY = h
      end,
      SetSiblingIndex = function() return true end,
      SetAnchorMin = function(_, x, y)
        data.fields.anchorMinX = x; data.fields.anchorMinY = y
      end,
      SetAnchorMax = function(_, x, y)
        data.fields.anchorMaxX = x; data.fields.anchorMaxY = y
      end,
      SetPivot = function(_, x, y)
        data.fields.pivotX = x; data.fields.pivotY = y
      end,
      GetChild = function(_, n)
        for _, c in ipairs(data.children) do
          if dataMap[c] and dataMap[c].fields.name == n then return c end
        end
        return nil
      end,
      FindChild = function(_, n) return nil end,
      AddCursorEventListener = function(_, ev, cb)
        data.listeners[#data.listeners+1] = { ev=ev, cb=cb }
      end,
      RemoveAllCursorEventListeners = function()
        data.listeners = {}
      end,

      --[[ ★ 按键事件（client_control_api.md 第 762 行）

           AddKeyEventListener(eventType, callback)

           ⚠️ 真机行为（文档第 1317 行）：
              按键事件被 Lua 回调【标记为已处理】后，同容器内其他按键
              不再响应本次事件。所以这里照实模拟：
              回调返回 true 之外的【任何值】都算"未处理"。
              返回 true 才吞掉事件 —— 探针必须一律 return false。

           ★ 注意：真机上这个方法只在【容器节点】上有，mock 不做限制，
             以免把"探针忘了判断控件类型"这类问题掩盖掉。
      ]]--
      AddKeyEventListener = function(_, ev, cb)
        data.keyListeners[#data.keyListeners+1] = { ev=ev, cb=cb }
      end,
      RemoveKeyEventListener = function(_, ev, cb)
        for i = #data.keyListeners, 1, -1 do
          local L = data.keyListeners[i]
          if L.ev == ev and L.cb == cb then table.remove(data.keyListeners, i) end
        end
      end,
      RemoveKeyEventListeners = function(_, ev)
        for i = #data.keyListeners, 1, -1 do
          if data.keyListeners[i].ev == ev then table.remove(data.keyListeners, i) end
        end
      end,
      RemoveAllKeyEventListeners = function()
        data.keyListeners = {}
      end,

      --[[ ★ 图片控件方法（R16 真机实测）

           SetImage(imageSource, imageId)

           ★ 真机行为：参数类型不对会【抛异常】：
               bad argument #2 to 'SetImage' (ImageSource expected, got nil)
             所以这里也做类型校验，让本地就能测出参数顺序错误。
      ]]--
      SetImage = function(_, imageSource, imageId)
        if imageSource == nil then
          error("bad argument #1 to 'SetImage' (ImageSource expected, got nil)", 2)
        end
        if type(imageId) ~= "number" then
          error("bad argument #2 to 'SetImage' (integer expected, got "
                .. type(imageId) .. ")", 2)
        end
        data.fields.imageId = imageId
        data.fields.imageSource = imageSource
      end,

      SetFillUnused = function() end,
      SetFillHorizontal = function() end,
      SetFillVertical = function() end,
      SetFillRadial90 = function() end,
      SetFillRadial180 = function() end,
      SetFillRadial360 = function() end,
      SetSoftEdgeWidth = function(_, x, y)
        data.fields.softEdgeWidthX = x
        data.fields.softEdgeWidthY = y
      end,
    }

    local proxy = {}
    setmetatable(proxy, {
      __index = function(_, k)
        if allowed[k] then return data.fields[k] end
        if METHODS[k] then return METHODS[k] end
        return nil            -- ★ 其他字段/方法一律不存在
      end,
      __newindex = function(_, k, v)
        -- ★ 只读字段：静默失败（真机行为 —— 写了不报错，但也写不进去）
        local ro = READONLY[kind]
        if ro and ro[k] then return end

        if allowed[k] then
          data.fields[k] = v
        end
        -- ★ 自定义字段：静默失败（真机行为，不报错也写不进）
      end,
    })

    if parent then
      local pd = dataMap[parent]
      if pd then pd.children[#pd.children+1] = proxy end
    end

    dataMap[proxy] = data
    controls[#controls+1] = proxy
    return proxy
  end

  --[[ ★ 关于 game 的类型（真机实测，2026-10-07）：

       probe 诊断模块在真机上读回：
         type(game)   = table
         typeof(game) = table
         type(script) = table     （但 typeof(script) = Script）

       => game 就是普通 table，这里【照实】返回普通 table，
          不做任何 userdata 包装。

       ⚠️ 曾经为了复现"type(game)=='table' 会短路"这个假设，
          把 game 包成 type() 返回 "userdata" 的代理 —— 后来真机实测
          推翻了该假设（见 docs/引擎能力与限制.md §7.1），
          且那种包装会污染 io.stdout 的元表，已撤销。

       ★ 真正需要模拟的真机约束是【OnUpdate 不被驱动】：
          见 tests/test_mount.lua 第 7 节，那里刻意一次都不调 update()。
  ]]--
  --[[ 画布尺寸：默认 1600x900（真机 2560x1440 屏幕上的实测值）。

     ★ 多屏幕比例适配需要能改这个值来验算（16:10 / 4:3 / 21:9）。
       用 setCanvas(w, h) 改，GetUICanvasSize 会返回新值。
]]--
local canvasW, canvasH = 1600, 900

local gameTable = {
    InstantiateClientUIControl = function(idx, parent)
      for k, v in pairs(prefabs) do
        if v == idx then return makeControl(k, parent) end
      end
      return nil
    end,
    DestroyClientUIControl = function() end,
    GetUICanvasSize = function() return canvasW, canvasH end,

    --[[ ★ 真机 API（client_control_api.md 第 209-210 行）

         FindClientUIRoot(name)  —— 按名称找 UI 根控件
         GetClientUIRoots()      —— 取全部根控件

         真机上这些根控件来自【编辑器里搭好的控件树】，
         不由脚本创建。mock 里用一个"外部根"来模拟：
         测试可用 setRoots{...} 注入。
    ]]--
    FindClientUIRoot = function(name)
      for _, r in ipairs(externalRoots) do
        local d = dataMap[r]
        if d and d.fields.name == name then return r end
      end
      return nil
    end,
    GetClientUIRoots = function()
      local out = {}
      for i, r in ipairs(externalRoots) do out[i] = r end
      return out
    end,

    --[[ ★★ game.Tween —— 属性平滑过渡（R28 补）

         API（client_control_api.md 第 249-274 行）：
            game.Tween(control, { field = target }, duration)
                  :SetEase(Enum.EaseTypeXxx)
                  :SetRelative(bool)
                  :SetOnComplete(fn)
                  :Play()

         ⚠️ 为什么必须补进 mock（"测试替身必须忠实"）：
            渲染器在属性声明了 CSS transition 时【改用 game.Tween】
            做插值（render.lua 的 setColor 分支）：
              if tr and tr.duration > 0 and type(game.Tween) == "function"
           若 mock 没有 game.Tween，那段代码【永远不执行】——
            本地全绿，真机才走 Tween 路径。

         ★ mock 的简化：不做真实插值（那需要逐帧驱动器），
           而是【在 Play() 时直接写入目标值】——
           对"最终颜色对不对"这类断言足够，
           且能证明"代码确实走了 Tween 分支而不是直写"。
           用 E.tweenCalls 可以查证走了几次。 ]]--
    Tween = function(control, props, duration)
      local tw = {}
      local d = dataMap[control]
      tw._played = false
      tw._props = props
      tw._duration = duration
      function tw:SetEase() return self end
      function tw:SetRelative() return self end
      function tw:SetOnComplete(fn) self._onComplete = fn; return self end
      function tw:SetLoops() return self end
      function tw:SetDelay() return self end
      function tw:Play()
        self._played = true
        tweenCalls = tweenCalls + 1
        lastTween = { control = control, props = props, duration = duration }
        -- 直接落到目标值（mock 不做逐帧插值）
        if d then
          for k, v in pairs(props) do d.fields[k] = v end
        end
        if self._onComplete then pcall(self._onComplete) end
        return self
      end
      function tw:Kill() return self end
      tweenSeqs[#tweenSeqs + 1] = tw
      return tw
    end,

    --[[ ★★ game.ServerSignal —— 客户端 -> 服务端的唯一通道（client_control_api.md §9）

         API（文档第 305-338 行）：
            game.ServerSignal(signalName) -> ServerSignal
            sig:AddInt(n) / AddString(s) / AddFloat(f) / AddBool(b) / ...
            sig:AddParam(paramType, paramValue)   -- 通用形式
            sig:SendSignal()

         ⚠️ 为什么必须补进 mock（"测试替身必须忠实"，见
            docs/引擎能力与限制.md §七）：

           webui_signal 的全部逻辑都建立在"发送真的发生了、
           参数真的按顺序进了列表"之上。若 mock 没有 game.ServerSignal，
           那条路径【本地永远不执行】—— 本地全绿、真机才走，
           与 R28 补 game.Tween 之前的状态一模一样。

         ★ 真实模型：参数按【调用顺序】追加进一个列表，
           引擎不校验类型/个数，也不报错 —— 所以"顺序错了"
           在真机上【完全静默】。mock 照实实现，好让
           webui_signal 的签名校验在本地就能被测出来。

         ★ 注意与控件的区别：这里【允许】自定义字段吗？
           不允许。真机的 ServerSignal 也是宿主对象，
           自定义字段写不进去 —— 所以 webui_signal 不能用
           "在信号对象上挂标记"这类写法。
    ]]--
    ServerSignal = function(signalName)
      if type(signalName) ~= "string" then
        -- 真机：类型不对会抛异常（bad argument）
        error("bad argument #1 to 'ServerSignal' (string expected, got "
              .. type(signalName) .. ")", 2)
      end
      local params = {}
      local sig = {}

      -- 通用形式：AddParam(paramType, paramValue)
      function sig:AddParam(paramType, paramValue)
        params[#params + 1] = paramValue
      end

      -- ★ 各类型便捷方法：真机上它们只是"带类型标记的 AddParam"，
      --   mock 里统一成 push，只保留【调用顺序】这一关键语义。
      local TYPES = {
        "Int", "IntList", "Float", "FloatList", "String", "StringList",
        "Vector3", "Vector3List", "Bool", "BoolList",
        "Guid", "GuidList", "Entity", "EntityList",
        "PrefabId", "PrefabIdList", "ConfigId", "ConfigIdList",
      }
      for _, t in ipairs(TYPES) do
        sig["Add" .. t] = function(_, v)
          params[#params + 1] = v
        end
      end

      function sig:SendSignal()
        if sendHook then sendHook(signalName, params) end
        -- ★ 深拷贝一份存下来：真机上发送后信号对象就没用了，
        --   若测试拿到的是同一个 table，后续改动会污染历史记录。
        local snap = {}
        for i = 1, #params do
          local v = params[i]
          if type(v) == "table" then
            local c = {}
            for k, vv in pairs(v) do c[k] = vv end
            snap[i] = c
          else
            snap[i] = v
          end
        end
        sentSignals[#sentSignals + 1] = { name = signalName, params = snap }
        return true
      end

      return sig
    end,
  }

  --[[ ★ 关于 game 的类型（实测结论，2026-10-07）：

       probe 诊断模块在真机上读回：
         type(game)   = table
         typeof(game) = table
         type(script) = table     （但 typeof(script) = Script）

       => game 就是普通 table，所以这里【照实】返回普通 table，
          不做任何 userdata 包装。

       ⚠️ 曾经为了复现一个"type(game)=='table' 会短路"的假设，
          把 game 用 debug.setmetatable 包成 userdata —— 后来真机实测
          推翻了那个假设（见 docs/引擎能力与限制.md §7.1），
          而且那种包装会污染 io.stdout 的元表，已撤销。

       ★ 真正需要模拟的真机约束是【OnUpdate 不被驱动】：
         见 tests/test_mount.lua 第 7 节，那里刻意一次都不调 update()。
  ]]--
  local game = gameTable

  return {
    game = game,
    controls = controls,
    --[[ ★ 注册"外部根控件"（模拟编辑器里搭好的控件树）

         测试里这样用：
           local root = E.makeControl("container", nil)
           root.name = "Root"
           E.setRoots({ root })
           -- 之后 game.FindClientUIRoot("Root") 就能找到
    ]]--
    setRoots = function(list)
      externalRoots = list or {}
    end,

    --[[ ★ 设置画布尺寸（多屏幕比例测试用）

           trueW/trueH 为 nil 时读回当前值。
           注意：真机返回浮点（1599.9998），这里也能传小数。 ]]--
    setCanvas = function(w, h)
      if w then canvasW = w end
      if h then canvasH = h end
      return canvasW, canvasH
    end,
    getCanvas = function() return canvasW, canvasH end,

    createdCount = function() return created end,
    makeControl = makeControl,
    dataOf = function(c) return dataMap[c] end,

    --[[ ★★ game.Tween 的观测接口（R28）

         用途：验证「声明了 CSS transition 的属性确实走了 Tween 分支」。
         真机上过渡由引擎插值，mock 只记调用并直接落值 ——
         但"有没有走这条路"是可验证的（这正是关键）。 ]]--
    tweenCount = function() return tweenCalls end,
    lastTween  = function() return lastTween end,
    resetTween = function()
      tweenCalls, tweenSeqs, lastTween = 0, {}, nil
    end,

    --[[ ★ 模拟按下某个按键：把所有绑定了该 eventType 的回调叫一遍。

         真机行为（文档第 1317 行）：某个回调返回 true = 标记已处理
         -> 同容器内其他按键不再响应本次事件。
         这里照实实现，好让"回调误返回 true 会吞掉事件"这个坑
         在本地就能被测出来。

         用法：E.fireKey(e, Enum.KeyEventType.KeyboardJumpKeyDown, data)
    ]]--
    fireKey = function(ctrl, ev, payload)
      local d = dataMap[ctrl]
      if not d then return false end
      for _, L in ipairs(d.keyListeners) do
        if L.ev == ev then
          local handled = L.cb(payload)
          if handled == true then return true end   -- 已处理，不再往下发
        end
      end
      return false
    end,
    keyListenerCount = function(ctrl)
      local d = dataMap[ctrl]
      return d and #d.keyListeners or 0
    end,

    --[[ ★★ game.ServerSignal 的观测接口

         用途：验证「SendSignal 真的发出了、参数顺序真的对」。
         真机上顺序错了完全静默（引擎不校验），所以这里必须能读回
         实际发出去的参数列表 —— 只断言"我们打算发什么"会误导
         （见 docs/引擎能力与限制.md §七 "探针必须读回实际值"）。
    ]]--
    sent = function()
      return sentSignals
    end,
    sentCount = function(name)
      if not name then return #sentSignals end
      local n = 0
      for i = 1, #sentSignals do
        if sentSignals[i].name == name then n = n + 1 end
      end
      return n
    end,
    lastSent = function(name)
      for i = #sentSignals, 1, -1 do
        local s = sentSignals[i]
        if not name or s.name == name then return s end
      end
      return nil
    end,
    resetSent = function() sentSignals = {} end,

    --[[ ★ 让下一次发送抛异常，用于验证"发送失败要被计到统计里"。
         真机上 SetImage 这类参数错误会抛异常，SendSignal 也走 pcall。 ]]--
    setSendHook = function(fn) sendHook = fn end,

    --[[ ★★ 模拟【服务端 -> 客户端】的信号回调。

         ⚠️ 真机形态（文档第 193 行）：
            script:RegisterServerSignalHandler(name, function(signalName, params))
                                              ^^^^^^ 回调参数是【两个】：
                                              信号名 + 参数数组

         这里照实调用 handler(signalName, params)，好让
         "回调签名写错（只声明一个参数）" 这类问题在本地就暴露。 ]]--
    fireSignal = function(name, params)
      local list = handlers[name]
      if not list then return 0 end
      local n = 0
      for i = 1, #list do
        -- ★ 照真机：两个参数。params 为空时给空表（不是 nil）
        list[i](name, params or {})
        n = n + 1
      end
      return n
    end,

    --[[ ★ 注册表：lib/webui/webui_signal 通过它挂到 script 上。

         为什么不让 mock 直接持有 script：真机上 script 是【宿主对象】，
         由引擎按固定名称在【入口脚本的环境】里查找生命周期函数
         （见 webui.lua 里 mount 的长注释）。mock 这里提供一个
         能被注入到全局 script 的替身。 ]]--
    scriptStub = function()
      return {
        RegisterServerSignalHandler = function(_, name, cb)
          if type(name) ~= "string" then
            error("bad argument #1 to 'RegisterServerSignalHandler'", 2)
          end
          if type(cb) ~= "function" then
            error("bad argument #2 to 'RegisterServerSignalHandler'", 2)
          end
          handlers[name] = handlers[name] or {}
          table.insert(handlers[name], cb)
        end,
        UnregisterServerSignalHandler = function(_, name)
          handlers[name] = nil
        end,
        _handlerCount = function(_, name)
          return handlers[name] and #handlers[name] or 0
        end,
      }
    end,
    -- 工具：统计沿父链可见的控件数
    visibleCount = function()
      local n = 0
      for _, c in ipairs(controls) do
        local d = dataMap[c]
        if d and d.fields.active then
          -- 沿父链检查
          local vis, depth = true, 0
          local p = nil
          for _, c2 in ipairs(controls) do
            local d2 = dataMap[c2]
            if d2 then
              for _, kid in ipairs(d2.children) do
                if kid == c then p = c2 end
              end
            end
          end
          while p and depth < 30 do
            local pd = dataMap[p]
            if not pd or not pd.fields.active then vis = false break end
            local pp = nil
            for _, c2 in ipairs(controls) do
              local d2 = dataMap[c2]
              if d2 then
                for _, kid in ipairs(d2.children) do
                  if kid == p then pp = c2 end
                end
              end
            end
            p = pp
            depth = depth + 1
          end
          if vis then n = n + 1 end
        end
      end
      return n
    end,
  }
end

return EngineMock
