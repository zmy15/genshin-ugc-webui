--[[ 验证 webui.mount：封装后开发者只写 HTML/CSS + 事件，样板由库接管。

     ★ 重点验证三件事：
       1. 只给 html/css/on，页面就能建出控件（不需要手写 root/循环）
       2. App:setText 能跨帧保持（不被渲染器用 DOM 文本覆盖）
       3. 生命周期：start/update/stop 的行为正确，
          特别是 Root 晚一帧就绪时的重试路径
]]--

local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')

local PREFABS = {
  container = 1073741933,
  textbox   = 1073741934,
  button    = 1073741935,
  image     = 1073741938,
}

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-32s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-32s %s", name, detail or "")) end
end

--=============================================================================
-- 搭一套 mock 环境（与其它 demo 测试同构）
--=============================================================================

local function setupEnv(opts)
  opts = opts or {}
  local E = EngineMock.new(PREFABS)
  game  = E.game
  Color = { FromRGBA = function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
            FromRGB  = function(r,g,b) return {r=r,g=g,b=b} end }
  Enum = {
    EaseType = { Linear="Linear", InQuad="InQuad", OutQuad="OutQuad", InOutQuad="InOutQuad" },
    CursorEventType = {
      CursorClick="CursorClick", CursorDown="CursorDown", CursorUp="CursorUp",
      CursorEnter="CursorEnter", CursorExit="CursorExit",
      CursorBeginDrag="CursorBeginDrag", CursorDrag="CursorDrag",
      CursorEndDrag="CursorEndDrag",
    },
    TextHorizontalAlignmentLeft="L",
    TextHorizontalAlignmentMiddle="C",
    TextHorizontalAlignmentRight="R",
    ImageSource = { StaticReference = "Enum.ImageSource.StaticReference" },
    ImageType = { Basic = "Enum.ImageType.Basic" },
  }

  local root = E.makeControl("container", nil)
  root.name = "Root"
  -- ★ deferRoot=true 时不注册根控件，用来模拟"Root 晚一帧才就绪"
  if not opts.deferRoot then E.setRoots({ root }) end

  local updateCalls = { on = 0 }
  script = {
    object = root,
    EnableUpdate = function(_, v) updateCalls.on = updateCalls.on + (v and 1 or 0) end,
    GetParam = function() return nil end,
  }

  local pending = {}
  game.TweenSequence = function()
    local s = {}
    function s:AppendCallback(f) pending[#pending+1] = f; return s end
    function s:AppendInterval(t) return s end
    function s:Append(t) return s end
    function s:Play() return s end
    function s:Kill() return s end
    function s:SetLoops() return s end
    return s
  end

  local function pump()
    local cur = pending
    pending = {}
    for _, f in ipairs(cur) do pcall(f) end
  end

  return E, root, pump, updateCalls
end

printerr = function(...) end

--=============================================================================
-- 1. 基本挂载：只给 html/css/on
--=============================================================================

print("=== 1. mount 基本用法 ===")
do
  local E, root, pump = setupEnv()

  local webui = require('webui')
  local clicks = 0

  local app = webui.mount{
    root    = "Root",
    prefabs = PREFABS,
    html    = [[<div class="box"><div class="t" id="txt" onclick="tap">你好</div></div>]],
    css     = [[
      .box { width: 200px; height: 80px; background-color: #222222; }
      .t   { width: 160px; height: 40px; font-size: 16px; color: #ffffff; }
    ]],
    on = { tap = function() clicks = clicks + 1 end },
  }

  check("mount 返回句柄", app ~= nil and type(app.start) == "function")
  check("已自动挂载（Root 已就绪时不等 OnStart）", app.bound == true)
  check("建出了控件", E.createdCount() > 0, "created=" .. E.createdCount())

  -- 事件应已绑定，点击能派发
  local fired = 0
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.listeners then
      for _, l in ipairs(d.listeners) do
        if l.ev == "CursorClick" then
          pcall(l.cb, { GetUIPos=function() return 1,1 end,
                        GetPressUIPos=function() return 1,1 end,
                        GetUIPosDelta=function() return 0,0 end,
                        dragging=false, touchId=-1 })
          fired = fired + 1
        end
      end
    end
  end
  check("on 表里的事件已绑定", fired > 0, string.format("触发 %d 次", fired))
  check("回调被调用", clicks == 1, "clicks=" .. clicks)

  -- 逐帧循环应已启动且稳定
  local before = E.createdCount()
  for i = 1, 30 do pump() end
  check("30 帧 flush 不新建控件", E.createdCount() - before == 0,
      string.format("新建 %d 个", E.createdCount() - before))

  app:stop()
end

--=============================================================================
-- 2. setText 必须走 DOM，能跨帧保持
--=============================================================================

print("")
print("=== 2. App:setText 跨帧保持 ===")
do
  local E, root, pump = setupEnv()

  local webui = require('webui')
  local app = webui.mount{
    root    = "Root",
    prefabs = PREFABS,
    html    = [[<div class="c" id="count">0 次</div>]],
    css     = [[.c { width: 200px; height: 40px; font-size: 16px; color: #fff; }]],
    on      = {},
  }

  local function countText()
    for _, c in ipairs(E.controls) do
      local d = E.dataOf(c)
      local f = d and d.fields or {}
      if f.text and tostring(f.text):find("次") then return tostring(f.text) end
    end
    return nil
  end

  local before = countText()
  app:setText("count", "7 次")

  --[[ ★ 关键：必须断言「DOM 被改了」，而不只是「控件显示对了」。

       只比较控件文字是抓不到 bug 的 —— 直接写 control.text 也能让
       控件显示成 7 次（直到某次 flush 把它覆盖回去）。真正要验证的是
       mount 走了正确路径：写 node._text（DOM），
       这样渲染器每帧都会把它写进控件，不会被 DOM 原文覆盖。

       所以这里查 node._text：它非空且等于新值，才说明用的是 DOM API。
  ]]--
  local domNode = nil
  do
    local dom = require('webui.dom')
    dom.walk(app.ui.doc, function(n)
      if not domNode and n:isElement() and n.attrs and n.attrs.id == "count" then
        domNode = n
      end
    end)
  end
  check("setText 写入了 DOM（node._text）", domNode and domNode._text == "7 次",
      domNode and ("_text=" .. tostring(domNode._text)) or "找不到节点")

  pump()
  local after1 = countText()
  for i = 1, 60 do pump() end
  local after60 = countText()

  check("setText 立即生效", before ~= after1,
      string.format("%s -> %s", tostring(before), tostring(after1)))
  check("setText 跨帧不被覆盖", after1 == after60 and after60 == "7 次",
      string.format("1 帧后=%s, 60 帧后=%s", tostring(after1), tostring(after60)))

  -- 再改一次，确认可反复更新（写控件的话第二次会被缓存的 DOM 原文顶回来）
  app:setText("count", "9 次")
  pump(); pump()
  check("setText 可反复更新", countText() == "9 次", tostring(countText()))

  app:stop()
end

--=============================================================================
-- 3. Root 晚一帧就绪：start 应回退到 update 重试
--=============================================================================

print("")
print("=== 3. Root 延迟就绪时的重试 ===")
do
  local E, root, pump, updateCalls = setupEnv({ deferRoot = true })

  local webui = require('webui')
  local app = webui.mount{
    root    = "Root",
    prefabs = PREFABS,
    html    = [[<div class="a">x</div>]],
    css     = [[.a { width: 100px; height: 40px; background-color: #333; }]],
    on      = {},
  }

  check("Root 未就绪时未挂载", app.bound == false)
  -- ★ 注意计数基准：mock 的根控件自身也算一次 makeControl，
  --   所以这里比的是"挂载前有没有新建控件"，而不是绝对值为 0。
  local baseCreated = E.createdCount()
  check("未就绪时不新建控件", baseCreated == 1,
      string.format("created=%d（1 = 仅 mock 根控件）", baseCreated))

  app:start()
  check("start 失败后开启了逐帧更新", updateCalls.on > 0,
      "EnableUpdate(true) 次数=" .. updateCalls.on)

  -- 让 Root 就绪，再走 update 重试
  E.setRoots({ root })
  app:update(0.016)

  check("update 重试后完成挂载", app.bound == true)
  check("重试后建出控件", E.createdCount() > baseCreated,
      string.format("created %d -> %d", baseCreated, E.createdCount()))

  app:stop()
  check("stop 后 bound 复位", app.bound == false)
end

--=============================================================================
-- 4. setStyle 运行时改样式
--=============================================================================

print("")
print("=== 4. App:setStyle ===")
do
  local E, root, pump = setupEnv()

  local webui = require('webui')
  local app = webui.mount{
    root    = "Root",
    prefabs = PREFABS,
    html    = [[<div class="b" id="box">x</div>]],
    css     = [[.b { width: 100px; height: 100px; background-color: #111111; }]],
    on      = {},
  }

  local function bgOf()
    for _, c in ipairs(E.controls) do
      local d = E.dataOf(c)
      local f = d and d.fields or {}
      if f.bgColor and type(f.bgColor) == "table" then
        return string.format("%s,%s,%s", tostring(f.bgColor.r), tostring(f.bgColor.g), tostring(f.bgColor.b))
      end
    end
    return nil
  end

  local before = bgOf()
  app:setStyle("box", "background-color", "#ff0000")
  pump(); pump()
  local after = bgOf()

  check("setStyle 改变了背景色", before ~= after,
      string.format("%s -> %s", tostring(before), tostring(after)))
  check("新颜色是红色", after == "255,0,0", tostring(after))

  app:stop()
end

print("")
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end