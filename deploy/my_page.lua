--[[============================================================================
  我的第一个页面 —— 千星奇域 UGC × webui

  ────────────────────────────────────────────────────────────────────────────
  这个文件就是"库放进工程之后，自己要写的全部内容"。
  除了底部 3 行生命周期接线，其余全是 HTML / CSS / 事件处理。
  ────────────────────────────────────────────────────────────────────────────

  ┌────────────────────────────────────────────────────────────┐
  │  队伍配置                                    预算 0 / 4     │
  ├────────────────────────────────────────────────────────────┤
  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐      │
  │  │ 夜兰  ◆  │ │ 胡桃  ◆  │ │ 钟离  ◆  │ │ 万叶  ◆  │      │
  │  │ 水 · 弓  │ │ 火 · 枪  │ │ 岩 · 枪  │ │ 风 · 剑  │      │
  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘      │
  ├────────────────────────────────────────────────────────────┤
  │  已选队伍                                                  │
  │  [夜兰] [胡桃] [钟离] [万叶]        ← 点卡片增减           │
  ├────────────────────────────────────────────────────────────┤
  │  平均等级 ████████████░░░░  Lv.86                          │
  │                                                            │
  │  ┌────────┐ ┌────────┐                                    │
  │  │  清空  │ │  出战  │                                    │
  │  └────────┘ └────────┘                                    │
  └────────────────────────────────────────────────────────────┘

  用到的能力：
    盒模型 · flex（row / 居中 / gap）· 圆形裁剪（border-radius:50%）
    图片形状（data-image + SetImage）· :hover 伪类 · onclick 事件
    运行时改文字与样式

  ⚠️ 部署前记得在【编辑器】里导入外部脚本 —— 真机读的是 .gil 不是文件夹。
==============================================================================]]

local webui = require('webui')

--[[ ★★ app 必须在这里先声明（有 3 个坑，前两个是写法，第三个是库的时序）：

       ┌ ① 不能写成 `local app = webui.mount{...}`
       │    那样 mount 参数里 on 表的闭包看不到 app（恒为 nil）
       │    —— Lua 的 local 在整条赋值语句执行完之前，对闭包不可见。
       │
       ├ ② 声明必须在【所有用到 app 的函数之前】
       │     若某个函数写在 `local app` 之前，它里面的 app 会被解析成
       │     【全局变量】并永远是 nil（之后再赋局部值也救不回来），
       │     表现为 setText 静默失败、界面不更新。
       │
       └ ③ onReady 触发时，上面这个 app 【仍然还没被赋值】
             —— 因为 onReady 是在 mount 内部跑的，mount 得先返回。
             实测症状：抛 "attempt to index a nil value (upvalue 'app')"，
             错误被库的 util.try 的 pcall 吞掉，于是
             【界面一片空白，日志里什么也没有】，最难查。

             解法：onReady = function(ui, app) ... end
                   接住第二个参数（见本文件底部 onReady 处的说明）。

       正确顺序：这里 local app → 下面写各个函数 → 最后 app = webui.mount{...}
]]--
local app

--=============================================================================
-- 数据
--=============================================================================

local CHARS = {
  { id = "yL", name = "夜兰", el = "水", wp = "弓", lv = 90, color = "#4a9fe0" },
  { id = "ht", name = "胡桃", el = "火", wp = "枪", lv = 88, color = "#e0603a" },
  { id = "zl", name = "钟离", el = "岩", wp = "枪", lv = 90, color = "#d4a950" },
  { id = "wy", name = "万叶", el = "风", wp = "剑", lv = 84, color = "#4ad0b8" },
  { id = "gl", name = "甘雨", el = "冰", wp = "弓", lv = 82, color = "#7fd1ff" },
  { id = "lx", name = "雷电", el = "雷", wp = "枪", lv = 90, color = "#a97fe0" },
}

local selected = {}          -- 已选角色 id 集合
local selectedOrder = {}     -- 保持选择顺序（用于显示）

local function isSelected(id) return selected[id] == true end

local function toggle(id)
  if selected[id] then
    selected[id] = nil
    for i, v in ipairs(selectedOrder) do
      if v == id then table.remove(selectedOrder, i); break end
    end
  else
    if #selectedOrder >= 4 then return false end   -- 队伍上限 4 人
    selected[id] = true
    selectedOrder[#selectedOrder + 1] = id
  end
  return true
end

local function nameOf(id)
  for _, c in ipairs(CHARS) do
    if c.id == id then return c.name end
  end
  return "?"
end

--=============================================================================
-- 页面：HTML + CSS
--=============================================================================

local function buildHTML()
  local cards = {}
  for i, c in ipairs(CHARS) do
    cards[i] = string.format(
      '<div class="card" id="card-%s" onclick="pick" onmouseenter="hoverOn" onmouseleave="hoverOff">' ..
        '<div class="avatar" id="av-%s" data-image="1"></div>' ..
        '<div class="cname">%s</div>' ..
        '<div class="csub">%s · %s</div>' ..
      '</div>',
      c.id, c.id, c.name, c.el, c.wp)
  end

  return '<div class="stage"><div class="panel">' ..
    '<div class="head">' ..
      '<div class="head-title">队伍配置</div>' ..
      '<div class="head-budget" id="budget">预算 0 / 4</div>' ..
    '</div>' ..
    '<div class="cards">' .. table.concat(cards) .. '</div>' ..
    '<div class="sect">已选队伍</div>' ..
    '<div class="picked" id="picked">（还没选人）</div>' ..
    '<div class="sect">平均等级</div>' ..
    '<div class="row-avg">' ..
      '<div class="bar"><div class="bar-fill" id="avgfill"></div></div>' ..
      '<div class="avg-val" id="avgval">Lv.--</div>' ..
    '</div>' ..
    '<div class="btns">' ..
      '<div class="btn ghost" id="btn-clear" onclick="clearAll" onmouseenter="hoverOn" onmouseleave="hoverOff">清空</div>' ..
      '<div class="btn" id="btn-go" onclick="go" onmouseenter="hoverOn" onmouseleave="hoverOff">出战</div>' ..
    '</div>' ..
  '</div></div>'
end

local CSS = [[
.stage {
  width: 1600px; height: 900px;
  background-color: #12141c;
  display: flex; justify-content: center; align-items: center;
}
.panel {
  width: 1180px; height: 620px;
  background-color: #1b1e2a;
  padding: 26px;
}

/* ---------- 顶栏 ---------- */
.head {
  width: 1128px; height: 46px;
  display: flex; justify-content: space-between; align-items: center;
}
/* ★ 文字框高 >= 字号 x 1.9，否则真机上引擎的字号自适应会把字压没。
     18px x 1.9 = 34.2 -> 取 35。（写 34 的话比值 1.89，字会消失。） */
.head-title  { width: 300px; height: 35px; font-size: 18px; color: #ffffff; }
.head-budget { width: 260px; height: 34px; font-size: 15px; color: #7fd1ff; }

/* ---------- 角色卡片 ---------- */
.sect  { width: 1128px; height: 30px; font-size: 14px; color: #e8edf7; margin-top: 14px; }
.cards { width: 1128px; height: 210px; display: flex; gap: 18px; margin-top: 8px; }

.card {
  width: 172px; height: 200px;
  background-color: #232838;
  padding: 14px;
}
/* ★ 必须真的写 :hover，并且元素要绑 onmouseenter/onmouseleave */
.card:hover { background-color: #2e3550; }

/* 圆形裁剪：border-radius 必须真写出来，才会被选成 image 控件 */
.avatar {
  width: 96px; height: 96px;
  background-color: #3a7bd5;
  border-radius: 50%;
}
/* 角色名：16px x 1.9 = 30.4 -> 取 31（写 30 的话比值 1.88，真机上名字会消失） */
.cname { width: 144px; height: 31px; font-size: 16px; color: #ffffff; margin-top: 12px; }
.csub  { width: 144px; height: 26px; font-size: 13px; color: #9aa6bd; margin-top: 2px; }

/* ---------- 已选队伍 ---------- */
.picked {
  width: 1128px; height: 40px;
  background-color: #151824;
  padding: 7px 12px;
  font-size: 15px; color: #4ad07a;
}

/* ---------- 平均等级 ---------- */
.row-avg { width: 1128px; height: 40px; display: flex; align-items: center; gap: 14px; margin-top: 6px; }
.bar      { width: 520px; height: 18px; background-color: #2a3044; }
.bar-fill { width: 0px; height: 18px; background-color: #4ad07a; }
.avg-val  { width: 160px; height: 30px; font-size: 15px; color: #ffffff; }

/* ---------- 按钮 ---------- */
.btns { width: 1128px; height: 60px; display: flex; gap: 16px; margin-top: 16px; }
.btn {
  width: 160px; height: 54px;
  background-color: #3a7bd5;
  font-size: 16px; color: #ffffff;
}
.btn:hover { background-color: #2f6ab8; }
.ghost { background-color: #3a4055; }
.ghost:hover { background-color: #4a5268; }
]]

--=============================================================================
-- 找 DOM 节点
--=============================================================================

local function findById(doc, id)
  local found = nil
  local function walk(n)
    if found then return end
    if n.isElement and n:isElement() then
      if n.attrs and n.attrs.id == id then found = n; return end
    end
    for _, c in ipairs(n.children or {}) do walk(c) end
  end
  walk(doc)
  return found
end

--=============================================================================
-- 图片形状：圆形头像
--=============================================================================

local function bindAvatars(ui)
  -- ⚠️ 真机上 require 只认扁平文件名，所以要写 webui_clip（不是 webui.clip）
  local ok, clip = pcall(require, "webui_clip")
  if not ok then
    ok, clip = pcall(require, "webui.clip")   -- 本地仓库环境
  end
  if not ok or not clip then
    print("[我的页面] webui_clip 加载失败，头像形状跳过")
    return
  end

  local n = 0
  for _, c in ipairs(CHARS) do
    local node = findById(ui.doc, "av-" .. c.id)
    if node then
      local entry = ui.rendered and ui.rendered.live and ui.rendered.live[node]
      local ctrl = entry and entry.control
      if ctrl and type(ctrl.SetImage) == "function" then
        -- 圆形遮罩（100002），再染成角色代表色
        if clip.asClip(ctrl, { shapeId = clip.SHAPES.CIRCLE }) then
          pcall(function()
            clip.tint(ctrl,
              tonumber(c.color:sub(2, 3), 16),
              tonumber(c.color:sub(4, 5), 16),
              tonumber(c.color:sub(6, 7), 16))
          end)
          n = n + 1
        end
      end
    end
  end
  print(string.format("[我的页面] 头像形状已设置 %d 个", n))
end

--=============================================================================
-- 业务逻辑
--=============================================================================

--[[ 刷新界面。

     ★ 参数 a：由 onReady 传进来（那时外层 `local app` 还没赋值）。
       正常事件回调里不传，退回用外层的 app。 ]]--
local function refresh(a)
  a = a or app
  if not a then return end   -- 极端情况：还没挂上，静默跳过比抛错好

  -- 预算
  a:setText("budget", string.format("预算 %d / 4", #selectedOrder))

  -- 已选列表
  if #selectedOrder == 0 then
    a:setText("picked", "（还没选人）")
  else
    local names = {}
    for i, id in ipairs(selectedOrder) do names[i] = nameOf(id) end
    a:setText("picked", table.concat(names, "  ·  "))
  end

  -- 平均等级
  local sum, cnt = 0, 0
  for _, id in ipairs(selectedOrder) do
    for _, c in ipairs(CHARS) do
      if c.id == id then sum = sum + c.lv; cnt = cnt + 1 end
    end
  end
  if cnt == 0 then
    a:setText("avgval", "Lv.--")
    a:setStyle("avgfill", "width", "0px")
  else
    local avg = math.floor(sum / cnt + 0.5)
    a:setText("avgval", "Lv." .. avg)
    a:setStyle("avgfill", "width", math.floor(avg / 100 * 520) .. "px")  -- 520px = Lv.100
  end

  -- 已选卡片高亮
  for _, c in ipairs(CHARS) do
    if isSelected(c.id) then
      a:setStyle("card-" .. c.id, "background-color", "#2b3a2e")
    else
      a:setStyle("card-" .. c.id, "background-color", "#232838")
    end
  end
end

local function onPick(info)
  local id = info and info.node and info.node.attrs and info.node.attrs.id
  if not id then return end
  local cid = id:match("^card%-(.+)$")
  if not cid then return end

  if not toggle(cid) then
    print("[我的页面] 队伍已满（上限 4 人）")
    return
  end
  refresh()
end

local function onClear()
  selected = {}
  selectedOrder = {}
  refresh()
  print("[我的页面] 已清空")
end

local function onGo()
  if #selectedOrder == 0 then
    print("[我的页面] 还没选人，无法出战")
    app:setText("budget", "请先选择角色")
    return
  end
  local names = {}
  for i, id in ipairs(selectedOrder) do names[i] = nameOf(id) end
  app:setText("budget", "出战：" .. table.concat(names, " "))
  print("[我的页面] 出战 " .. table.concat(names, "、"))
end

--=============================================================================
-- 挂载
--=============================================================================

-- ★ app 已在本文件顶部声明（见那里的说明），这里只赋值。
app = webui.mount{
  root = "Root",
  -- 控件模板索引：在编辑器里为容器/文本框/按钮/图片各建一个模板并填索引。
  -- image 是裁剪与形状所必需；不填的话圆形头像出不来。
  prefabs = {
    container = 1073741933,
    textbox   = 1073741934,
    button    = 1073741935,
    image     = 1073741938,
  },

  html = buildHTML(),
  css  = CSS,

  -- 挂载完成后做一次性设置（图片形状），并刷一次初始状态。
  --
  -- ★★ 注意第二个参数 app：
  --    onReady 是在 mount【内部】触发的，此刻上面那个 `local app`
  --    还没被赋值（mount 得先返回才轮得到它）。所以这里绝不能写
  --    refresh() 里那种 app:setText(...) —— 会抛
  --      attempt to index a nil value (upvalue 'app')
  --    而这个错被库的 pcall 吞掉，症状是「界面不出来、日志还空空」。
  --
  --    要用 app 就接第二个参数，它一定可用（见 webui.lua 的 appRef）。
  onReady = function(ui, app)
    bindAvatars(ui)
    refresh(app)
  end,

  on = {
    pick     = function(info) onPick(info) end,
    clearAll = function()     onClear()    end,
    go       = function()     onGo()       end,
    hoverOn  = function() end,   -- :hover 由 CSS 负责，这里只留钩子
    hoverOff = function() end,
  },
}

--=============================================================================
-- 生命周期接线（引擎的硬性约定，3 行）
--
--   引擎按固定名字在【本文件的环境】里找这几个函数，
--   库无法替你定义（require 进来的模块有独立 _ENV）。
--=============================================================================

function OnStart()    app:start()  end
function OnUpdate(dt) app:update() end
function OnDestroy()  app:stop()   end
