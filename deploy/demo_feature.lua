--[[============================================================================
  DEMO · 功能展示页（用于 README 截图）

  目的：一屏之内把 webui 当前【已真机验证可用】的能力都摆出来，
        既要能跑通，也要截出来好看。

  页面布局（画布 1600x900，居中一块 1360x780 的卡片）：
  ┌────────────────────────────────────────────────────────────────────────┐
  │  genshin-ugc-webui                    纯 Lua · 零依赖 · 运行于游戏沙箱 │ 顶栏
  ├────────────────────────────────────────────────────────────────────────┤
  │  ┌────────┐  用 Lua 渲染 HTML / CSS                                     │
  │  │ 圆形头像│  flex 布局 · 圆形与矩形裁剪 · 图片换色 · 过渡动画            │ 标题区
  │  └────────┘                                                             │
  ├────────────────────────────────────────────────────────────────────────┤
  │  ◆ 六种预置形状（图片控件 + SetImage）                                  │
  │  ┌────┐┌────┐┌────┐┌────┐┌────┐┌────┐                                   │
  │  │方  ││圆  ││三角││四角││五角││圆环│                                   │ 形状行
  │  └────┘└────┘└────┘└────┘└────┘└────┘                                   │
  ├────────────────────────────────────────────────────────────────────────┤
  │  ◆ 裁剪：圆形（border-radius:50%）与矩形（overflow:hidden）             │
  │  ┌──────────┐  ┌────────────────┐                                       │
  │  │  圆形裁剪 │  │ 矩形裁剪，内容 │  ← 内部色块故意超出，被切掉           │ 裁剪区
  │  │   (头像)  │  │ 溢出后被切掉   │                                       │
  │  └──────────┘  └────────────────┘                                       │
  ├────────────────────────────────────────────────────────────────────────┤
  │  ◆ flex 布局 + 进度条 + 按钮（onclick / :hover）                        │ 组件区
  │  HP  ████████████████░░░░░░░░  18,420                                  │
  │  ATK ████████████░░░░░░░░░░░░   1,280                                  │
  │  ┌────────┐ ┌────────┐                                                 │
  │  │  确定  │ │  取消  │                                                 │
  │  └────────┘ └────────┘                                                 │
  └────────────────────────────────────────────────────────────────────────┘

  ★ 本页用到的、已在真机验证过的能力：
    1. 盒模型 + flex（row / column、justify-content、align-items、gap）
    2. border-radius:50% 圆形裁剪（图片控件 + 圆形遮罩图）
    3. overflow:hidden 矩形裁剪（内容溢出被切）
    4. 图片控件 SetImage（六种预置形状）
    5. imageColor 染色（同一张图染成不同颜色）
    6. 文字渲染（★ 所有文字框高 >= 字号 × 1.9，否则真机上字会消失）
    7. onclick / onmouseenter 事件绑定

  ⚠️ require 必须写【扁平名】webui_clip，不能写 webui.clip ——
     真机把 require 名原样当文件名（webui_clip.lua）。
==============================================================================]]

local PREFABS = {
  container = 1073741933,
  textbox   = 1073741934,
  button    = 1073741935,
  image     = 1073741938,   -- ★ 裁剪与形状必需
}

local ENABLE_LOOP = true
local LOOP_FPS    = 30

--=============================================================================
-- 加载 webui
--=============================================================================

local webui
do
  local ok, m = pcall(require, "webui")
  if ok and m then
    webui = m
  else
    printerr("[DEMO] require('webui') 失败")
    printerr("[DEMO]   ok = " .. tostring(ok))
    printerr("[DEMO]   m  = " .. tostring(m))

    local MODS = { "webui_util", "webui_dom", "webui_html", "webui_css",
                   "webui_color", "webui_style", "webui_transition",
                   "webui_layout", "webui_render", "webui_clip", "webui_event" }
    for _, name in ipairs(MODS) do
      local o2, m2 = pcall(require, name)
      printerr(string.format("[DEMO]   require('%-18s') -> %s  %s",
          name, tostring(o2), o2 and "OK" or tostring(m2)))
    end
    return
  end
end

local clip = nil

--=============================================================================
-- 运行状态
--=============================================================================

local root       = nil
local ui         = nil
local loopSeq    = nil
local frame      = 0
local bound      = false
local retryCount = 0
local clickCount = 0

local function warn(...)
  local n = select('#', ...)
  local parts = {}
  for i = 1, n do parts[i] = tostring((select(i, ...))) end
  local msg = "[DEMO] " .. table.concat(parts, " ")
  if type(printerr) == "function" then printerr(msg) else print(msg) end
end

--=============================================================================
-- 页面内容
--=============================================================================

--[[ 颜色约定：深色底 + 高对比文字，截图里更清晰。 ]]--

local function buildPage()
  return [[
<style>
  /* ---------- 根容器：铺满，深色背景 ---------- */
  .stage {
    width: 1600px; height: 900px;
    background-color: #12141c;
    display: flex;
    justify-content: center;
    align-items: center;
  }

  /* ---------- 主卡片 ---------- */
  .panel {
    width: 1360px; height: 780px;
    background-color: #1b1e2a;
    padding: 28px;
  }

  /* ---------- 顶栏 ---------- */
  .topbar {
    width: 1304px; height: 52px;
    background-color: #232838;
    padding: 10px 14px;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .brand  { width: 420px; height: 32px; font-size: 16px; color: #7fd1ff; }
  .tagline{ width: 380px; height: 32px; font-size: 13px; color: #8892a8; }

  /* ---------- 标题区 ---------- */
  .hero {
    width: 1304px; height: 128px;
    margin-top: 18px;
    display: flex;
    align-items: center;
    gap: 22px;
  }
  /* ★ 圆形裁剪：这里是 image 控件 + 圆形遮罩
       ⚠️ border-radius 必须真的写出来 —— 它才会被解析成 _clipShape(CIRCLE)。
          光有 background-color 会走 textbox（真机 textbox 没有 SetImage）。 */
  .avatar {
    width: 112px; height: 112px;
    background-color: #2e6fb7;
    border-radius: 50%;
  }
  .hero-text { width: 900px; height: 112px; }
  .hero-h1   { width: 900px; height: 40px; font-size: 21px; color: #ffffff; }
  .hero-sub  { width: 900px; height: 30px; font-size: 14px; color: #9aa6bd; margin-top: 8px; }
  .hero-sub2 { width: 900px; height: 30px; font-size: 14px; color: #7fd1ff; }

  /* ---------- 区块标题 ---------- */
  .sect {
    width: 1304px; height: 30px;
    font-size: 14px; color: #e8edf7;
    margin-top: 16px;
  }

  /* ---------- 形状行 ---------- */
  .shapes {
    width: 1304px; height: 96px;
    display: flex;
    gap: 18px;
    margin-top: 8px;
  }
  /* ★ 预置形状：必须 data-image="1" 才会被选成 image 控件
       （否则有 background-color 就走 textbox，而 textbox 没有 SetImage） */
  .shape-box {
    width: 96px; height: 96px;
    background-color: #2a3044;
  }
  .shape-lbl {
    width: 1304px; height: 26px;
    font-size: 12px; color: #8892a8;
    margin-top: 6px;
  }

  /* ---------- 裁剪区 ---------- */
  .clips {
    width: 1304px; height: 168px;
    display: flex;
    gap: 24px;
    margin-top: 8px;
  }
  /* ★ 圆形裁剪 */
  .clip-circle {
    width: 168px; height: 168px;
    background-color: #3f8ae0;
    border-radius: 50%;
  }
  /* ★ 矩形裁剪：overflow:hidden 需要有背景色（否则填充不受遮罩约束） */
  .clip-rect {
    width: 300px; height: 168px;
    background-color: #262b3d;
    overflow: hidden;
    padding: 16px;
  }
  /* 这两块故意做出容器范围，验证被裁掉 */
  .overflow-a {
    width: 420px; height: 56px;
    background-color: #d9534f;
  }
  .overflow-b {
    width: 420px; height: 56px;
    background-color: #4ad07a;
    margin-top: 12px;
  }
  .clip-note { width: 700px; height: 168px; font-size: 13px; color: #9aa6bd; }
  /* ★ 库没有自动换行，文字必须自己拆成多行短句，
       否则会溢出容器（溢出内容仍可见但会失去父背景 -> 看起来"背景颜色不同"）。
       这里每行都控制在容器宽度内。 */
  .clip-line { width: 700px; height: 26px; font-size: 13px; color: #9aa6bd; margin-top: 4px; }
  .clip-line-hi { width: 700px; height: 26px; font-size: 13px; color: #7fd1ff; margin-top: 4px; }

  /* ---------- 进度条 ---------- */
  .stats {
    width: 560px; height: 132px;
    margin-top: 10px;
  }
  .stat-row {
    width: 560px; height: 40px;
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .stat-name { width: 56px; height: 32px; font-size: 14px; color: #e8edf7; }
  .bar {
    width: 360px; height: 18px;
    background-color: #2a3044;
  }
  .bar-fill { height: 18px; }
  .fill-hp  { width: 288px; background-color: #4ad07a; }
  .fill-atk { width: 224px; background-color: #ffb648; }
  .fill-def { width: 144px; background-color: #5aa9ff; }
  .stat-val { width: 110px; height: 32px; font-size: 14px; color: #ffffff; }

  /* ---------- 按钮 ---------- */
  .btns {
    width: 560px; height: 60px;
    display: flex;
    gap: 14px;
    margin-top: 8px;
  }
  .btn {
    width: 150px; height: 52px;
    background-color: #3a7bd5;
    font-size: 15px; color: #ffffff;
  }
  /* ★ 必须真的写 :hover 选择器才会变色。
       只声明一个 .btn-hover 类是不够的 —— 类名不会自己生效。
       库的 :hover 依赖 event.lua 维护的 node._hover，
       而它由 onmouseenter/onmouseleave 绑定的
       CursorEnter/CursorExit 驱动，所以这两个属性都要写。 */
  .btn:hover { background-color: #2f6ab8; }

  /* ---------- 右侧图例 ---------- */
  .right-col { width: 700px; height: 480px; }
  .legend    { width: 700px; height: 26px; font-size: 13px; color: #9aa6bd; margin-top: 4px; }
  .legend-hi { width: 700px; height: 26px; font-size: 13px; color: #7fd1ff; margin-top: 4px; }
  .counter   { width: 700px; height: 30px; font-size: 14px; color: #4ad07a; margin-top: 10px; }
</style>

<div class="stage">
  <div class="panel">

    <!-- 顶栏 -->
    <div class="topbar">
      <div class="brand">genshin-ugc-webui</div>
      <div class="tagline">纯 Lua · 零外部依赖 · 运行于游戏沙箱</div>
    </div>

    <!-- 标题区（圆形裁剪头像） -->
    <div class="hero">
      <div class="avatar" id="avatar"></div>
      <div class="hero-text">
        <div class="hero-h1">用 Lua 渲染 HTML / CSS 风格的界面</div>
        <div class="hero-sub">盒模型与 flex 布局 · 圆形与矩形裁剪 · 图片换形与染色</div>
        <div class="hero-sub2">21 个测试套件 · GitHub Actions CI · 全部能力均经真机验证</div>
      </div>
    </div>

    <!-- 形状 -->
    <div class="sect">◆ 预置形状（图片控件 + SetImage）</div>
    <div class="shapes">
      <div class="shape-box" id="sh-square"   data-image="1"></div>
      <div class="shape-box" id="sh-circle"   data-image="1"></div>
      <div class="shape-box" id="sh-triangle" data-image="1"></div>
      <div class="shape-box" id="sh-star4"    data-image="1"></div>
      <div class="shape-box" id="sh-star5"    data-image="1"></div>
      <div class="shape-box" id="sh-ring"     data-image="1"></div>
    </div>
    <div class="shape-lbl">正方形 · 圆形 · 三角形 · 四角星 · 五角星 · 圆环</div>

    <!-- 裁剪 -->
    <div class="sect">◆ 裁剪：圆形（border-radius:50%）与矩形（overflow:hidden）</div>
    <div class="clips">
      <div class="clip-circle" id="clip-circle"></div>
      <div class="clip-rect">
        <div class="overflow-a"></div>
        <div class="overflow-b"></div>
      </div>
      <div class="clip-note">
        <div class="clip-line">左：圆形遮罩裁出正圆（border-radius:50%）。</div>
        <div class="clip-line">中：矩形裁剪容器内的色块宽 420px，</div>
        <div class="clip-line">　　超出容器 300px，溢出部分被切掉 ——</div>
        <div class="clip-line-hi">　　所以右侧看不到红绿两色的延伸。</div>
      </div>
    </div>

    <!-- 进度条 + 按钮 -->
    <div class="sect">◆ flex 布局 · 进度条 · 按钮事件</div>
    <div class="clips">
      <div class="stats">
        <div class="stat-row">
          <div class="stat-name">HP</div>
          <div class="bar"><div class="bar-fill fill-hp"></div></div>
          <div class="stat-val">18,420</div>
        </div>
        <div class="stat-row">
          <div class="stat-name">ATK</div>
          <div class="bar"><div class="bar-fill fill-atk"></div></div>
          <div class="stat-val">1,280</div>
        </div>
        <div class="stat-row">
          <div class="stat-name">DEF</div>
          <div class="bar"><div class="bar-fill fill-def"></div></div>
          <div class="stat-val">640</div>
        </div>
      </div>
      <div class="right-col">
        <div class="btns">
          <div class="btn" id="btn-ok"   onclick="onOk"    onmouseenter="onHover" onmouseleave="onLeave">确定</div>
          <div class="btn" id="btn-cancel" onclick="onCancel" onmouseenter="onHover" onmouseleave="onLeave">取消</div>
        </div>
        <div class="counter" id="counter">已点击：0 次</div>
        <div class="legend">事件：onclick / onmouseenter（鼠标移入会变深）</div>
        <div class="legend-hi">文字框高均 ≥ 字号 × 1.9（真机硬约束）</div>
      </div>
    </div>

  </div>
</div>
]]
end

--=============================================================================
-- 图片绑定（形状 / 裁剪 / 染色）
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

local function bindImages(u)
  --[[ ★ 模块名用【扁平写法】webui_clip。
       真机把 require 名原样当文件名，所以必须是 webui_clip.lua 这个名字。 ]]--
  if not clip then
    local ok, m = pcall(require, "webui_clip")
    if not ok then
      ok, m = pcall(require, "webui.clip")   -- 兼容本地环境
    end
    if ok then clip = m end
  end
  if not clip then
    warn("webui_clip 加载失败，形状无法设置")
    return 0
  end

  local count = 0

  local function controlOf(id)
    local node = findById(u.doc, id)
    if not node then warn("找不到节点 #" .. id); return nil end
    local entry = u.rendered and u.rendered.live and u.rendered.live[node]
    if not entry or not entry.control then
      warn("节点 #" .. id .. " 还没有控件")
      return nil
    end
    return entry.control
  end

  -- 设置形状图（可带染色）
  local function setShape(id, shapeId, r, g, b)
    local ctrl = controlOf(id)
    if not ctrl then return false end
    if type(ctrl.SetImage) ~= "function" then
      warn(string.format("节点 #%s 不是 image 控件（缺 background-color 或 data-image）", id))
      return false
    end
    if not clip.setImage(ctrl, shapeId) then
      warn("SetImage 失败: #" .. id)
      return false
    end
    if r then clip.tint(ctrl, r, g, b, 255) end
    count = count + 1
    return true
  end

  -- 圆形裁剪
  local function setCircleClip(id, shapeId)
    local ctrl = controlOf(id)
    if not ctrl then return false end
    if not clip.asClip(ctrl, { shapeId = shapeId }) then
      warn("配置裁剪失败: #" .. id)
      return false
    end
    count = count + 1
    return true
  end

  local S = clip.SHAPES

  -- 六种预置形状，各染一个颜色，便于区分
  setShape("sh-square",   S.SQUARE,   0x5a, 0xa9, 0xff)
  setShape("sh-circle",   S.CIRCLE,   0x4a, 0xd0, 0x7a)
  setShape("sh-triangle", S.TRIANGLE, 0xff, 0xb6, 0x48)
  setShape("sh-star4",    S.STAR4,    0xd9, 0x8c, 0xff)
  setShape("sh-star5",    S.STAR5,    0xff, 0xd7, 0x4a)
  setShape("sh-ring",     S.RING,     0x7f, 0xd1, 0xff)

  -- 圆形裁剪（头像 + 大圆）
  setCircleClip("avatar", S.CIRCLE)
  setCircleClip("clip-circle", S.CIRCLE)

  return count
end

--=============================================================================
-- 事件处理器
--=============================================================================

--[[ 刷新计数文字。

     ⚠️ 必须走 node:setText()（写 DOM），不能直接写 control.text。

     真机踩过：直接改控件的 text 字段，下一帧 flush 时会被渲染器
     用 DOM 里的文本覆盖回去（render.lua 每帧都执行
     `tset("text", dom.textOf(node))`），表现为"点了没反应"——
     日志里计数一直在涨，界面却始终显示 0。

     dom.lua 的 Node:setText 注释里已经把这条写死了：
       「直接改 control.text 会在下一帧被 DOM 文本覆盖，必须走这个 API」
]]--
local function refreshCounter()
  if not ui or not ui.doc then return end
  local node = findById(ui.doc, "counter")
  if not node then return end
  if type(node.setText) ~= "function" then return end
  pcall(function()
    node:setText(string.format("已点击：%d 次", clickCount))
  end)
end

local HANDLERS = {
  onOk = function()
    clickCount = clickCount + 1
    print(string.format("[DEMO] 确定 被点击，累计 %d 次", clickCount))
    refreshCounter()
  end,
  onCancel = function()
    clickCount = clickCount + 1
    print(string.format("[DEMO] 取消 被点击，累计 %d 次", clickCount))
    refreshCounter()
  end,
  onHover = function()
    print("[DEMO] 鼠标移入按钮")
  end,
  onLeave = function()
    print("[DEMO] 鼠标移出按钮")
  end,
}

--=============================================================================
-- 逐帧循环（真机 OnUpdate 不驱动，靠 TweenSequence 递归）
--=============================================================================

local function startLoop()
  if not ENABLE_LOOP then return end
  if type(game.TweenSequence) ~= "function" then
    warn("game.TweenSequence 不可用，逐帧循环关闭")
    return
  end

  local function tick()
    frame = frame + 1
    if ui then
      local ok, err = pcall(function() ui:flush() end)
      if not ok and frame < 5 then warn("flush 失败: " .. tostring(err)) end
    end
    loopSeq = game.TweenSequence()
    loopSeq:AppendInterval(1 / LOOP_FPS)
    loopSeq:AppendCallback(tick)
    loopSeq:Play()
  end

  tick()
end

--=============================================================================
-- 启动
--=============================================================================

local function boot()
  root = game.FindClientUIRoot("Root")
  if not root then return false end

  ui = webui.new({
    root     = root,
    prefabs  = PREFABS,
    handlers = HANDLERS,
  })

  local ok, err = pcall(function()
    ui:render(buildPage())
  end)
  if not ok then
    printerr("[DEMO] 渲染失败: " .. tostring(err))
    return true
  end

  print("[DEMO] 渲染完成")

  local okBind, n = pcall(bindImages, ui)
  if not okBind then
    warn("图片绑定异常: " .. tostring(n))
    n = 0
  end
  print(string.format("[DEMO] 图片绑定调用成功 %d 次（形状 6 + 裁剪 2 = 8）", n or 0))
  bound = true

  --[[ 统计控件与遮罩。

       ★ 这里统计的是【真正启用了 enableMask 的控件数】，它和
         "bindImages 调用次数"不是一回事：
           形状行那 6 个只是换图（不裁剪），不计入 masked；
           裁剪容器由两处产生 —— 显式的 asClip（头像/大圆）与
           样式层 overflow:hidden 自动配的矩形裁剪。
  ]]--
  if ui.rendered and ui.rendered.live then
    local total, masked = 0, 0
    for _, e in pairs(ui.rendered.live) do
      total = total + 1
      if e.clipShape then masked = masked + 1 end
    end
    print(string.format("[DEMO] 控件 %d 个，其中启用遮罩 %d 个（应 3：头像 + 大圆 + 矩形）",
        total, masked))
  end

  startLoop()
  return true
end

function OnInit()
  -- 无需参数
end

function OnStart()
  print("[DEMO] OnStart")
  if boot() then return end
  print("[DEMO] 未找到 Root，进入重试")
  script:EnableUpdate(true)
end

function OnUpdate(dt)
  if bound then return end
  if boot() then
    bound = true
    script:EnableUpdate(false)
    return
  end
  retryCount = retryCount + 1
  if retryCount >= 120 then
    printerr("[DEMO] 等待 Root 超时（120 帧）")
    script:EnableUpdate(false)
  end
end

function OnDestroy()
  if loopSeq then pcall(function() loopSeq:Kill(false) end) end
  print(string.format("[DEMO] 结束，共 %d 帧", frame))
end
