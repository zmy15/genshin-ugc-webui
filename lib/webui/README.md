# webui —— 用 HTML/CSS 在千星奇域里画界面

在《原神》千星奇域 UGC 环境中，用 Lua 渲染 HTML/CSS 风格的界面。

```
3,500+ 行 Lua / 12 个模块 / 零外部依赖 / 19 个测试套件
```

---

## 快速开始

```lua
local webui = require('webui')

local PREFABS = {
  container = 1073741933,   -- 编辑器里配好的模板索引
  textbox   = 1073741934,
  button    = 1073741935,
}

function OnStart()
  local ui = webui.new({
    root     = script.object,
    prefabs  = PREFABS,
    handlers = {
      onClick = function(info)
        print("点击了", info.x, info.y)
      end,
    },
  })

  ui:render([[
    <style>
      .panel { width: 400px; padding: 20px; background-color: #222; }
      .title { height: 30px; font-size: 20px; color: #fff; }
      .row   { display: flex; gap: 12px; }
      .btn   { width: 120px; height: 40px; background-color: #3a7bd5;
               color: #fff; transition: background-color 0.2s; }
      .btn:hover { background-color: #5a9be5; }
    </style>
    <div class="panel">
      <div class="title">设置面板</div>
      <div class="row">
        <div class="btn" onclick="onClick">确定</div>
        <div class="btn" onclick="onClick">取消</div>
      </div>
    </div>
  ]])

  ui:startLoop(30)     -- 开始逐帧刷新（30fps）
end
```

**注意：** 事件名（`onClick`）要和 HTML 里的 `onclick="onClick"` 对应。

---

## 部署

千星的多文件 `require` 规则：

- 文件放 `external_lua_file/`
- **同目录、无 `.lua` 后缀、不支持子目录**
- 有缓存，`_ENV` 隔离

所以模块**直接就是扁平化命名**（不需要任何构建步骤）：

```
webui.lua              ← 入口，require('webui')
webui_util.lua         ← require('webui_util')
webui_dom.lua
webui_html.lua
webui_css.lua
webui_color.lua
webui_style.lua
webui_transition.lua
webui_layout.lua
webui_render.lua
webui_event.lua
```

**部署就是复制**（无需改名、无需改写 require）：

```bash
python tools/install.py "<external_lua_file 路径>"     # 库 + 起始页 + 使用说明
lua tools/build_external.lua "<external_lua_file 路径>"  # 只装库
```

因为 `lib/webui/` 里的文件名已经是扁平形式，直接把整个文件夹拷进去
就能被真机 `require` 到 —— 真机的规则是「同目录 + 文件名原样」，
`require('webui_util')` 找的就是 `webui_util.lua`。

**⚠️ 新增模块时必须同步导入到编辑器**，否则依赖它的模块会 `require` 失败。

---

## 支持的功能

### 布局

| 特性 | 状态 |
|---|---|
| 盒模型（margin / padding / border-box） | ✅ |
| `display: block / inline / inline-block / flex / none` | ✅ |
| **flex 单行**（`justify-content` / `align-items` / `gap`） | ✅ |
| **`flex-wrap` 多行** | ✅ |
| **`flex-grow` / `flex-shrink` / `flex-basis`** | ✅ |
| `position: absolute / relative / fixed` | ✅ |
| 百分比 / `px` / `em` / `rem` 单位 | ✅ |
| `min-width` / `max-width` / `min-height` / `max-height` | ✅ |
| 外边距折叠（简化：相邻取较大者） | ✅ |

### 样式

| 特性 | 状态 |
|---|---|
| CSS 选择器（tag / `.class` / `#id` / 后代 / 子代） | ✅ |
| **`:hover` / `:active` 伪类** | ✅ |
| 特指度、层叠、继承 | ✅ |
| `background-color` / `color` / `font-size` / `opacity` | ✅ |
| `text-align` | ✅ |
| **`transform: translate / scale / rotate`** | ✅ |
| **`transition`**（映射到 `game.Tween`） | ✅ |
| **`z-index`**（映射到 `SetSiblingIndex`） | ✅ |
| **`overflow: hidden`**（矩形裁剪，图片控件遮罩） | ✅ |
| **`border-radius: 50%`**（圆形裁剪，图片控件遮罩） | ✅ |
| 内联 `style="..."` | ✅ |

不支持的选择器（`[attr]` / `:first-child` / `+` / `~` / `@media`）会让**整条规则作废**（避免误匹配）。

### 裁剪（R17 新增）

`overflow: hidden` 与 `border-radius` 通过**图片控件遮罩**实现：

```html
<div class="card">          <!-- 超出部分被裁掉 -->
  <div class="big"></div>
</div>
<div class="avatar"></div>  <!-- 圆形裁剪 -->
```
```css
.card   { width:200px; height:100px; overflow:hidden; }
.avatar { width:80px;  height:80px;  border-radius:50%; }
```

**原理**（真机实证）：
- 引擎的 `enableMask` 按**图片 alpha** 裁子控件，形状随图片变化
- 矩形裁剪用矩形图（`100001`），圆形裁剪用圆图（`100002`）
- **等比适配不变形** —— 圆图在 2:1 的父控件里仍是正圆

**前提**：`prefabs.image` 必须配置图片控件模板索引：

```lua
local ui = webui.new({
  root = root,
  prefabs = {
    container = 1073741933,
    textbox   = 1073741934,
    button    = 1073741935,
    image     = 1073741938,   -- ★ 裁剪功能必需
  },
})
```

**限制**：预置资源里没有"圆角矩形图"，所以 `border-radius: 8px` 这类
**非 50% 值会退化为圆形裁剪**。想要圆角矩形，需在编辑器里配一张圆角图。

**裁剪容器可以放文字**（R18 实测 11/11 通过）。两种写法都支持：

```html
<!-- ① 文字直接放在裁剪容器里 -->
<div class="card" style="overflow:hidden">卡片文字</div>

<!-- ② 文字放在子元素里（推荐，可独立设样式） -->
<div class="card" style="overflow:hidden">
  <div class="title">生之花</div>
  <div class="sub">沉沦之心 +20</div>
</div>
```

> 原理：图片控件**自身**没有 `text` 字段，但它的**子控件**可以有。
> 库会在裁剪元素自带直接文字时，自动挂一个 `textbox` 子控件承载。

**注意**：`textbox` 在真机上没有 `SetImage`。要画形状图（且不想裁剪）
必须显式声明 `data-image="1"`：

```html
<div id="icon1" data-image="1"></div>
```

### 交互

| 事件 | 状态 |
|---|---|
| `onclick` / `onmousedown` / `onmouseup` | ✅ |
| `onmouseenter` / `onmouseleave` | ✅ |
| `ondragstart` / `ondrag` / `ondragend` | ✅ |

回调收到：

```lua
{
  event = "CursorClick",   -- 事件名
  node  = <DOM 节点>,
  x, y,                    -- 当前 UI 坐标（左下原点）
  pressX, pressY,          -- 按下时坐标
  dx, dy,                  -- 本次位移
  dragging, touchId,
  box   = { x, y, w, h },  -- 元素布局盒（左上原点）
}
```

**坐标转换辅助：**

```lua
webui.event.toLocal(uiX, uiY)             -- UI 坐标 -> 库内部坐标
webui.event.hitBox(box, uiX, uiY)         -- 命中检测
webui.event.ratioInBox(box, uiX, uiY)     -- 元素内相对位置 0..1（滑块用）
```

### 运行时更新

```lua
node:setStyle("background-color", "#f00")   -- 设置样式（跨 flush 保留）
node:setBg(74, 144, 217)                    -- 背景色
node:setColor(255, 255, 255)                -- 文字色
node:setWidth(120)                          -- 宽度
node:setText("新文字")                       -- 文字（覆盖 DOM 文本）
node:addClass("on") / removeClass / toggleClass
node:hide() / show()                        -- display:none，不占位
node:clearStyles()                          -- 回退到 CSS 值
```

**⚠️ 动态状态优先用 class 切换**，这样 `transition` 才能生效：

```lua
-- ✅ 推荐：走 CSS，有过渡
node:removeClass("off"); node:addClass("on")

-- ⚠️ 会绕过 transition（值瞬间跳变）
node:setStyle("background-color", "#4a90d9")
```

**查找节点：**

```lua
webui.dom.walk(ui.doc, function(node)
  if node:isElement() and node.id == "target" then ... end
end)
```

---

## 架构

```
lib/webui/                （文件名即真机部署名，可直接整目录拷贝）
├── webui_util.lua       222 行   字符串/数值/画布工具
├── webui_dom.lua        255 行   DOM 节点、class、运行时样式
├── webui_html.lua       213 行   HTML 解析器
├── webui_css.lua        289 行   CSS 解析 + 选择器匹配
├── webui_color.lua      156 行   颜色解析（hex/rgb/named）
├── webui_style.lua      483 行   层叠/继承/默认样式/transform
├── webui_transition.lua 166 行   transition 解析
├── webui_layout.lua     604 行   盒模型 + flex（含 wrap）
├── webui_render.lua     867 行   控件池 + diff 渲染 + 双层架构
├── webui_clip.lua       175 行   图片控件（遮罩 / 换图 / 染色）
├── webui_event.lua      198 行   事件绑定 + 伪类状态 + 坐标换算
└── webui.lua            374 行   对外 API（入口）
```

### 渲染流程

```
ui:render(html)
  ├─ html.parse        -> DOM 树
  ├─ style.apply       -> 计算样式（层叠/继承）+ 赋 _order
  ├─ layout.compute    -> 每个节点的绝对位置
  └─ render.update     -> 控件池复用 + 字段 diff 写入
       └─ _bindEvents  -> 绑定光标事件
```

### 两个核心设计

**1. 双层架构**（视觉与交互分离）

```
<textbox>          ← 视觉层（有 bgColor/text）
  <button>         ← 交互层（透明，只接光标事件）
</textbox>
```

因为**没有一个控件同时具备两者**：
- 文本框：有外观，无光标事件
- 容器：无外观，无光标事件
- 预设按钮：有光标事件，无外观字段

**2. 控件池 + diff**

- 按 `kind` 池化控件，复用时**必须验证实际父匹配**（引擎无 reparent API）
- 回收时**按 DOM 先序逆序压池**（保证 LIFO 弹出顺序 == 构建顺序）
- 只在字段**值变化时**写入（颜色按分量比较，浮点用容差）

---

## 关键约束（真机实测）

> 完整清单见 `ugc_out/引擎能力与限制.md`

| 约束 | 影响 |
|---|---|
| **自定义字段一律不可写** | 控件上无法保存状态；只能存外部表或用 `GetChildren()` |
| **字段按控件类型封死** | 容器/按钮写 `bgColor`/`text` 静默失败 |
| **无 reparent API** | 控件池必须复用"父匹配"的控件 |
| `OnUpdate` 不驱动 | 逐帧靠递归 `TweenSequence` |
| **矩形裁剪可实现** | ★ R17 实证：图片控件 + 矩形图当遮罩 + `enableMask`（`overflow:hidden` 可用） |
| `imageId` 只读，但可换图 | 字段只读，**用 `img:SetImage(Enum.ImageSource.StaticReference, id)`**（R16 实证可用） |
| `fontSize` 必须整数 | 浮点会报错 |
| **★ 文字框高 ≥ 字号 × 1.9** | ★ R19 实证：框太矮时引擎的**字号自适应会把字压没** —— 症状是"文字凭空消失"，而日志全对 |
| **★ 裁剪容器不设 `background-color`** | 它的填充不受自身遮罩约束，会溢出到裁剪区外 |
| **★ 容器高度要装得下内容** | 元素无 `overflow:hidden` 时，溢出内容**仍可见但失去父背景** → 表现为"某块背景颜色不同" |

### 裁剪的推荐写法

```html
<!-- ✅ 裁剪容器无背景色，底色由内层容器承载 -->
<div class="card">
  <div class="card-bg">          <!-- 铺满 + 底色 -->
    <div class="band"></div>     <!-- 溢出的内容，会被裁掉 -->
    <div class="text">生之花</div>
  </div>
</div>
```
```css
.card    { width:260px; height:168px; overflow:hidden; }  /* 不要设 background */
.card-bg { width:260px; height:168px; background-color:#1c2030; }
.band    { width:400px; height:60px; background-color:#7ac050; }  /* 溢出被裁 */
```

> ⚠️ 底色层**不能是与父等高的兄弟层** —— 那会把后续兄弟挤出父容器而被裁掉。
> 底色必须画在「包住所有内容」的那一层上。

---

## 测试

```bash
lua test_html.lua        # HTML 解析
lua test_css.lua         # CSS 选择器
lua test_style.lua       # 层叠/继承
lua test_layout.lua      # 盒模型
lua test_wrap.lua        # flex-wrap
lua test_features.lua    # transform / z-index / :hover / flex-grow
lua test_transition.lua  # transition 解析
lua test_webui.lua       # 端到端
lua test_diff.lua        # diff 渲染
lua test_list.lua        # 列表重建
lua test_loop.lua        # 逐帧稳定性
lua test_listener.lua    # 监听器生命周期
lua test_parent.lua      # 父链正确性
lua test_visible.lua     # 可见性
lua test_real.lua        # ★ 真机仿真（限制严格的 mock）
lua test_shop.lua        # 装备商店端到端
lua test_clip.lua        # ★ 裁剪 / 换图（图片控件遮罩）
lua test_demo_panel.lua  # 角色面板 demo 自检
lua test_probe.lua       # ★ 统一探针自检（四个模块）
```

**`test_real.lua` 最关键** —— 它用 `engine_mock.lua`（严格模拟真机限制：
自定义字段不可写、字段按类型封死、无 reparent）跑测试，
能在本地拦住"依赖不存在的字段"这类问题。

---

## 示例

`deploy/demo_shop.lua` —— 装备商店，10 张卡片、页签、筛选、购物车、结算。

```
DOM: 134 元素 / 76 文本 / 深度 7
控件: 152 个（textbox 112 + container 22 + button 19）
事件: 19 个绑定
```

验证的能力：五层嵌套、flex-wrap 网格、flex-grow 两端对齐、
数据驱动列表重建、三种状态联动、class 切换 + transition、hover、逐帧循环 + diff。

---

## 已知限制

### 引擎做不到（无解）

自定义字体、粗体、圆角/边框/阴影、富文本。

### 引擎能做的（容易误以为做不到）

**运行时换图**：
`img:SetImage(Enum.ImageSource.StaticReference, 图片ID)`。
字段 `imageId` 只读，但有专门的 Setter 方法。

**矩形裁剪**：图片控件 + **矩形图当遮罩** + `enableMask = true`。
塞进该控件的子控件，超出部分会被裁掉 —— 即 `overflow:hidden`。

**形状裁剪可行且不限圆形**：`enableMask` 按图片 alpha 裁子控件，
**形状随图片变化且等比适配不变形**（圆图 → 正圆，三角图 → 三角，矩形图 → 矩形）。

### 库没实现（可补）

| 功能 | 说明 |
|---|---|
| `transform` 的 `rotateX/Y`、`skew`、`matrix` | 引擎二维仿真不支持 |
| `text-overflow: ellipsis` | 长文本省略号 |
| `white-space: nowrap` | 禁止换行 |
| `letter-spacing` | 字间距 |
| 文本精确换行 | 现按字符宽度估算，英文单词可能被截断 |
| `grid` 布局 | 现按 `block` 处理 |
| 圆角图片方案封装 | 需手动配图片模板 |

---

## 版本

`0.1.0` —— 首个可用版本，动态页面（含列表重建）已真机验证。
