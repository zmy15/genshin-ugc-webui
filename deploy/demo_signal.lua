--[[============================================================================
  DEMO · 按钮发信号（服务器信号最小可跑示例）

  做的就一件事：**点按钮 -> 发一条服务器信号**。

  ┌──────────────────────────────────────────────┐
  │  服务器信号示例                                │
  │  状态：就绪                                    │
  │  已发送 0 条                                   │
  │  ┌──────────┐ ┌──────────┐ ┌──────────┐      │
  │  │ 购买 x1  │ │ 购买 x10 │ │  聊天    │      │
  │  └──────────┘ └──────────┘ └──────────┘      │
  └──────────────────────────────────────────────┘

  ---------------------------------------------------------------------------
  ★ 三个按钮分别演示三种"发信号"的写法：

    · 购买 x1   -> app:emit(...)    进队列，本帧渲染前统一发（默认，推荐）
    · 购买 x10  -> app:emitNow(...) 立即发（实时性要求高时用）
    · 聊天      -> app:emit(...)    发字符串参数

  ★★ 为什么参数要写进 signals（而不是随手 emit）：

    引擎【不校验任何东西】——
      参数个数错 / 顺序错 / 类型错 / 信号名拼错，全都是静默的
      （表现统一为"什么都没发生"）。
    把约定写成签名表，库就会替你校验，错了会在日志里 warn 出来。
    见 docs/引擎能力与限制.md §5.3。

  ---------------------------------------------------------------------------
  ⚠️ 部署前必读（否则点了没反应，且没有任何报错）：

    1. 【信号名必须先在服务端脚本里注册】
       本文件用的名字是 buy_item / chat。服务端没有同名信号的话，
       客户端发出去不会有任何反应 —— 这不是库的问题。

    2. 【prefabs 的四个索引要换成你自己的】
       索引只在编辑器里能看到，库无法自己发现。
       填错不报错，只是控件建不出来（界面空白）。

    3. 【编辑器里要有名为 Root 的容器，并把脚本挂在它下面】
       另外根控件缩放要设 1.01（1.00 时界面四周留一圈缝）。

  ---------------------------------------------------------------------------
  这条日志是"到底发出去没有"的唯一判据（真机上看不到信号本身）：

      [webui] signal: 帧12 发3 失败0 收0 重放0 丢弃0 合并0 队列0 缓冲0 ...
                                 ^^^^                              ^^^^
                                 已发出                            还在排队

  想随时看，就把 SHOW_REPORT 改成 true（每 30 帧打一行）。
==============================================================================]]

local webui = require('webui')

-- 每 30 帧打一行信号统计（排查"到底发出去没有"用，平时关掉）
local SHOW_REPORT = false

--=============================================================================
-- 页面：纯 HTML + CSS
--=============================================================================

local HTML = [[
<div class="stage">
  <div class="card">
    <div class="title">服务器信号示例</div>
    <div class="status" id="status">状态：就绪</div>
    <div class="count"  id="count">已发送 0 条</div>

    <div class="row">
      <div class="btn" id="b1" onclick="buyOne"
           onmouseenter="hoverOn" onmouseleave="hoverOff">购买 x1</div>
      <div class="btn" id="b2" onclick="buyTen"
           onmouseenter="hoverOn" onmouseleave="hoverOff">购买 x10</div>
      <div class="btn alt" id="b3" onclick="say"
           onmouseenter="hoverOn" onmouseleave="hoverOff">聊天</div>
    </div>

    <div class="hint">点按钮即发送信号，看下方返回值</div>
  </div>
</div>
]]

local CSS = [[
.stage {
  width: 1600px; height: 900px;
  background-color: #12141c;
  display: flex; justify-content: center; align-items: center;
}
.card {
  width: 620px; height: 360px;
  background-color: #1b1e2a;
  padding: 28px;
}
/* ★ 每个文字框都要显式写 background-color：
     不写的话引擎会给默认深色底，字色若也深 -> 文字看不见（R21）。
   ★ 框高必须 >= 字号 x 1.9，否则引擎的字号自适应会把字压没。 */
.title  { width: 564px; height: 34px; font-size: 18px; color: #7fd1ff;
          background-color: #1b1e2a; }
.status { width: 564px; height: 30px; font-size: 16px; color: #9aa4bb;
          background-color: #1b1e2a; margin-top: 10px; }
.count  { width: 564px; height: 34px; font-size: 18px; color: #ffffff;
          background-color: #1b1e2a; margin-top: 6px; }

.row  { width: 564px; height: 62px; display: flex; gap: 14px; margin-top: 22px; }
.btn {
  width: 178px; height: 58px;
  background-color: #3a7bd5;
  font-size: 16px; color: #ffffff;
  /* ★ 要居中必须写 text-align：默认是 left，文字会贴框左边（R21） */
  text-align: center;
}
.btn:hover { background-color: #2f6ab8; }
.alt { background-color: #3a4055; }
.alt:hover { background-color: #4a5268; }

.hint { width: 564px; height: 30px; font-size: 14px; color: #6b7590;
        background-color: #1b1e2a; margin-top: 18px; }
]]

--=============================================================================
-- 交互
--=============================================================================

local sentCount = 0

-- ★ 先 local 声明再赋值。写成 `local app = webui.mount{...}` 的话，
--   on 表里的闭包看到的 app 恒为 nil（Lua 的 local 在整条赋值语句
--   执行完之前对内部闭包不可见）——症状是"点了什么都不发生"。
local app
app = webui.mount{
  root    = "Root",
  prefabs = {
    container = 1073741933,   -- ★ 换成你自己模板的索引
    textbox   = 1073741934,
    button    = 1073741935,
    image     = 1073741938,
  },
  html = HTML,
  css  = CSS,

  --===========================================================================
  -- ★ ① 声明约定：信号名 = 服务端注册的名字，参数类型【按顺序】
  --
  --     "int" / "float" / "string" / "bool" / "intlist" / "stringlist"
  --     / "vector3" / "json" 等，见 lib/webui/webui_signal.lua 顶部。
  --
  --     ⚠️ 类型写错了不会被引擎发现，但会被这里拦下（warn）。
  --        integer 和 float 是【分开】的：写 "int" 却传 1.5 会被拦。
  --===========================================================================
  signals = {
    buy_item = { "int", "int" },   -- 商品 ID, 数量
    chat     = { "string" },       -- 聊天内容
  },

  --===========================================================================
  -- ★ ② 收服务端信号（本例只发不收，占位说明写法）
  --
  --     参数已按 signals 里的签名解好，直接就是 Lua 值。
  --===========================================================================
  onSignal = {
    -- 例：服务端回执
    -- buy_item_ack = function(ok, reason)
    --   app:setText("status", ok and "购买成功" or ("失败: " .. tostring(reason)))
    -- end,
  },

  on = {
    --=======================================================================
    -- ★ ③ 按钮 -> 发信号（这就是本题要的那一段）
    --=======================================================================
    buyOne = function()
      -- app:emit 进队列，本帧渲染前统一发出去。
      -- 返回 true = 已受理（不代表服务端收到了）。
      local ok = app:emit("buy_item", 1001, 1)
      onSent(ok, "购买 x1")
    end,

    buyTen = function()
      -- emitNow 不进队列，立刻发 —— 实时性要求高时用（如开火、确认购买）。
      local ok = app:emitNow("buy_item", 1001, 10)
      onSent(ok, "购买 x10")
    end,

    say = function()
      local ok = app:emit("chat", "你好，我是客户端")
      onSent(ok, "聊天")
    end,

    hoverOn  = function() end,   -- :hover 由 CSS 负责，这里只留钩子
    hoverOff = function() end,
  },
}

--[[ 发送结果反馈到界面上。

     ★ 为什么要把返回值显示出来：
       emit 返回 false 时【一定会有一条 warn】，但真机上刷日志不方便。
       显示在界面上，"点了没反应"就能立刻区分成两种情况：
         · 显示"已发送"   -> 客户端发出去了，问题在服务端没注册同名信号
         · 显示"被拦下"   -> 参数写错了（个数/类型），日志里有原因
     这个区分能省一整轮真机排查。 ]]--
function onSent(ok, label)
  if ok then
    sentCount = sentCount + 1
    app:setText("status", "状态：已发送 " .. label)
  else
    -- 失败原因已经由库 warn 出来了（参数个数/类型不符等）
    app:setText("status", "状态：被拦下 " .. label .. "（看日志）")
  end
  app:setText("count", "已发送 " .. sentCount .. " 条")
end

--=============================================================================
-- 可选：逐帧打一行统计
--
--   ★ 这是"到底发出去没有"最可靠的判据 —— 真机上你看不到信号本身，
--     但能看到"发/失败/队列"这几个数在动。
--     "队列"一直不归零 = flush 没在跑；"失败"在涨 = 引擎侧报错了。
--=============================================================================

if SHOW_REPORT then
  local frame = 0
  app:setTick(function()
    frame = frame + 1
    if frame % 30 == 0 then
      print(app:signalReport())
    end
  end)
end

--=============================================================================
-- 生命周期接线（引擎的硬性约定，3 行）
--
--   app:stop() 里已经包含了【解绑服务器信号监听】——
--   不解绑的话，下一次 mount 会把监听叠加上去（一个信号处理两遍）。
--=============================================================================

--[[ ★ 把句柄暴露到全局，方便在真机上手动调试。

     真机上没法断点，只能靠控制台敲。有了这一行，就能随时：

         app:signalReport()                 -- 看"发了几条 / 队列里还有几条"
         app:emit("buy_item", 1001, 1)      -- 手动发一条试试
         app:signalReport().failed          -- 失败了几条

     "队列一直不归零" = flush 没在跑；"失败在涨" = 引擎侧报错了。
     这是排查"到底发出去没有"最直接的手段。 ]]--
_G.app = app

function OnStart()    app:start()  end
function OnUpdate(dt) app:update() end
function OnDestroy()  app:stop()   end