--[[============================================================================
  DEMO · 最小示例（封装后的写法）

  对比：以前写一个页面要 500~700 行样板（找 Root / PREFABS / 渲染 /
  事件 / 循环 / 四个生命周期函数），现在只有下面这些 ——
  页面部分就是纯 HTML + CSS，Lua 只用来当 JS 写交互。

  ┌──────────────────────────────────────────┐
  │  计数器                                   │
  │  已点击 0 次                              │
  │  ┌────────┐ ┌────────┐                    │
  │  │  +1    │ │  归零  │                    │
  │  └────────┘ └────────┘                    │
  └──────────────────────────────────────────┘

  ★ 本文件里唯一"非页面"的东西，就是底部那 3 行生命周期接线。
    那是引擎的硬性约定（它按固定名字找 OnInit/OnStart/OnUpdate/OnDestroy），
    但库已经把里面的活全干完了 —— 你只需要转发给它。
==============================================================================]]

local webui = require('webui')

--=============================================================================
-- 页面：纯 HTML + CSS
--=============================================================================

local HTML = [[
<div class="stage">
  <div class="card">
    <div class="title">计数器</div>
    <div class="count" id="count">已点击 0 次</div>
    <div class="row">
      <div class="btn" id="btn-inc" onclick="inc"
           onmouseenter="hoverOn" onmouseleave="hoverOff">+1</div>
      <div class="btn ghost" id="btn-reset" onclick="reset"
           onmouseenter="hoverOn" onmouseleave="hoverOff">归零</div>
    </div>
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
  width: 420px; height: 300px;
  background-color: #1b1e2a;
  padding: 28px;
}
/* ★ 文字框高必须 >= 字号 x 1.9，否则真机上字会被压没 */
.title { width: 364px; height: 34px; font-size: 16px; color: #7fd1ff; }
.count { width: 364px; height: 48px; font-size: 22px; color: #ffffff; margin-top: 10px; }
.row   { width: 364px; height: 60px; display: flex; gap: 14px; margin-top: 20px; }
.btn {
  width: 160px; height: 56px;
  background-color: #3a7bd5;
  font-size: 16px; color: #ffffff;
}
/* ★ 必须真的写 :hover 才会变色（只声明一个类名不会生效） */
.btn:hover { background-color: #2f6ab8; }
.ghost { background-color: #3a4055; }
.ghost:hover { background-color: #4a5268; }
]]

--=============================================================================
-- 交互：Lua 当 JS 用
--=============================================================================

local count = 0

-- ★ 写法要点：先 local 声明，再赋值。
--   `local app = webui.mount{...}` 会让 on 里的闭包看不到 app（恒为 nil），
--   因为 Lua 的 local 在整条赋值语句执行完之前，对内部闭包不可见。
--   症状：点击后什么都不发生，日志也不报错。
local app
app = webui.mount{
  root    = "Root",
  -- 控件模板索引：只在编辑器里配置，库无法自己发现，所以必须显式给出
  prefabs = {
    container = 1073741933,
    textbox   = 1073741934,
    button    = 1073741935,
    image     = 1073741938,
  },
  html = HTML,
  css  = CSS,

  on = {
    inc = function()
      count = count + 1
      app:setText("count", "已点击 " .. count .. " 次")
    end,

    reset = function()
      count = 0
      app:setText("count", "已点击 0 次")
    end,

    hoverOn  = function() end,   -- :hover 由 CSS 负责，这里只留个钩子
    hoverOff = function() end,
  },
}

--=============================================================================
-- 生命周期接线（引擎的硬性约定，3 行）
--=============================================================================

function OnStart()    app:start()  end
function OnUpdate(dt) app:update() end
function OnDestroy()  app:stop()   end
