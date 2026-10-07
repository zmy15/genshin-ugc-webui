# 在千星奇域 UGC 里用 HTML/CSS/JS 画界面 —— 实现路径评估

> 评估日期：基于官方《客户端控件 API 文档》(`mhtakr07vej4`) + 真机观察契约
> 结论先行：**可行，但不能直接跑浏览器引擎。必须自建一个"翻译层"——把 HTML/CSS 子集编译成控件树。**

---

## 一、先说结论

| 问题 | 答案 |
|---|---|
| 能不能直接用 HTML/CSS/JS？ | ❌ 不能。沙箱没有 DOM、没有浏览器引擎、不能加载 C 扩展 |
| 能不能做出"写 HTML 就能渲染"的库？ | ✅ 可以。自己写解析器 + 布局器 + 渲染器 |
| JS 部分呢？ | ⚠️ 建议**不引入 JS**，或只做极小子集。理由见第五节 |
| 最大的技术障碍是什么？ | `overflow: hidden`（容器裁剪）没有对应原语 |
| 工作量量级？ | 核心可用约 3–5k 行 Lua；完整 flex + 文本排版要 10k+ |

---

## 二、环境硬约束（真机已验证）

这些不是猜测，来自 Fengari 模拟器的真机探针记录（7.0.50）：

```text
_VALUES:  _VERSION == nil
裁剪掉:    io / package / loadfile / load / dofile
          coroutine / string.dump / string.pack / string.unpack
          collectgarbage
保留:      utf8 ✓
          os.time / os.date / os.clock / os.difftime ✓
          debug.traceback ✓
          math.isnan / math.isinf / math.modf / math.ult ✓
require:   ✓ 可用！路径 "子目录/文件名"（无 .lua），独立 _ENV，带缓存
```

### 对架构的三个决定性影响

**1. `require` 可用 —— 已由使用者确认 ✅**

> **2026 更新：使用者已实测确认 `require` 可用。** 库可以拆多文件，按下面的模块化架构做。

先前证据分歧记录（供追溯）：官方文档只列了不可用项（`string.dump` / `io.*` / `coroutine.*` / 部分 `os.*` / 部分 `debug.*`），未提 `require`；模拟器真机探针（7.0.50）说可用；社区 FAQ 有说法称不可用。**实测结果与模拟器探针一致。**

真机回归中记录的 `require` 行为：

- 路径 `子目录/文件名`（**无 `.lua`** 后缀）
- 类定义（`__index` / `setmetatable`）、闭包与 upvalue 均保持
- 嵌套 require，模块表身份保持（`rawequal`）
- 每个模块独立 `_ENV`，`script` 是模块自己的身份
- 路径别名共享缓存
- 模块**不执行** `OnInit`/`OnStart`
- 失败报错：`failed to load script '…'`

库可以组织成：

```lua
local html   = require('webui/html')
local css    = require('webui/css')
local layout = require('webui/layout')
local render = require('webui/render')
```

> 建议仍在源码组织上保持模块边界清晰，便于日后需要时合并成单文件分发。

**2. 没有 `coroutine` → 解析器不能写成协程式**

这点两方证据一致。很多 Lua 解析器（LPeg 风格）依赖 coroutine 做增量解析。这里必须写成**纯状态机或递归下降**。递归下降在 Lua 里受 C stack 限制，深层嵌套 HTML 可能爆栈——需要迭代式解析器。

**3. 每个挂载脚本可能是一台独立 Lua VM**

真机确认各挂载脚本是**独立 Lua state**（跨脚本 `Invoke` 的 table 身份不保持）。含义：

- 库状态不能靠全局变量跨脚本共享
- 若 `require` 可用，同一 VM 内模块是单例
- 想做"全局样式表"，得挂在某个具体脚本上

---

## 三、渲染原语盘点：什么能画，什么画不了

### 能画的（读写字段）

| 原语 | API | 映射到 CSS |
|---|---|---|
| 位置 | `anchoredPositionX/Y` | `left/top` / `translate` |
| 尺寸 | `sizeDeltaX/Y` | `width/height` |
| 锚点 | `anchorMinX/Y` `anchorMaxX/Y` | `left/right/top/bottom` 拉伸、百分比 |
| 中心点 | `pivotX/Y` | `transform-origin` |
| 缩放 | `localScaleX/Y/Z` | `transform: scale()` |
| 旋转 | `localRotationX/Y/Z` | `transform: rotate()` |
| 层级 | `SetSiblingIndex(n)` | `z-index`（仅同级） |
| 显隐 | `visible` / `active` | `visibility` / `display` |
| 颜色 | `imageColor` `fontColor` `bgColor` | `background-color` `color` |
| 透明度 | 上述颜色的 alpha | `opacity` |
| 图片 | `SetImage(source, id)` | `background-image` |
| 文本 | `text` `fontSize` `horizontalAlignment` | 文本属性 |
| 进度条 | `fillAmount`（水平/垂直/径向） | 少见，可做 loading |
| 裁剪 | `enableMask` + `reverseMaskArea` | ⚠️ 见下 |

### 画不了的（会导致 CSS 子集残缺）

| 缺失能力 | 影响的 CSS |
|---|---|
| **容器级裁剪** | `overflow: hidden` —— 最严重的缺失 |
| 任意路径绘制 | 所有 `canvas` 式绘图、`border` 除矩形外 |
| 逐字形自由定位 | 精确文本排版、`letter-spacing` |
| 自定义字体 | `@font-face` |
| 位图上传 | 只能用编辑器里已配置的图片资源 id |
| 全局 z-index | 只有同级 sibling 顺序 |
| 原生 flex/grid | 全部布局算法要自己写 |

### `overflow: hidden` 的严重性

> **真机实测结论**：
>
> | 控件 | 画纯色块 | 裁子节点 |
> |---|---|---|
> | **图片控件** | 无 `bgColor`，但有 `imageColor` 可染色 | ✅ **按图片 alpha 裁剪**（形状任意） |
> | **文本框** | ✅ `bgColor` 直接可用 | ❌ **完全不能裁** |
>
> **「纯色」和「能裁剪」仍需分属两种控件** —— 但两者都可用，只是分工不同。

后果：

- 矩形滚动列表（`overflow-y: auto`）—— 可用矩形裁剪实现，也可走原生视窗控件
- 纯色面板裁掉溢出内容 —— ✅ 用图片控件 + 矩形遮罩
- 圆形/圆角元素（头像框、技能环、雷达）—— ✅ 原生支持，GPU 加速
- `ClientUIGridScrollerControl` / `ClientUITextWindowControl` **原生自带矩形裁剪和滚动**

**绕行方案**：把 `overflow` 语义映射到图片控件遮罩。

```
div { background:#333 }                        -> 文本框 bgColor ✅
div { border-radius:50%; overflow:hidden }     -> 图片控件 + 圆图当遮罩 + enableMask ✅
div { overflow: hidden }                       -> 图片控件 + 矩形图当遮罩 + enableMask ✅
div { overflow-y: auto }                       -> ClientUITextWindowControl（文本）
ul  { overflow-y: auto }                       -> ClientUIGridScrollerControl（列表项）
```

---

## 四、CSS 子集映射表

| CSS | 可行性 | 实现方式 |
|---|---|---|
| `display: block` | ✅ | 容器 + 顺序子节点 |
| `display: flex` | ⚠️ 需自写 | 手写 flex 算法（主轴/交叉轴/换行） |
| `display: inline` | ⚠️ 需自写 | 行盒布局 |
| `display: none` | ✅ | `SetActive(false)` |
| `position: absolute` | ✅ | `anchoredPosition` 直接对应 |
| `position: relative` | ✅ | 父容器 + 偏移 |
| `position: fixed` | ✅ | 挂到根节点 |
| `width/height: px` | ✅ | `sizeDelta` |
| `width/height: %` | ✅ | `anchorMin/Max` 天然是百分比模型 |
| `margin` / `padding` | ⚠️ 需自写 | 布局算法里手动计算 |
| `left/top/right/bottom` | ✅ | 锚点 + anchoredPosition |
| `background-color` | ✅ | 图片 `imageColor` |
| `color` / `font-size` | ✅ | TextBox 字段 |
| `text-align` | ✅ | `horizontalAlignment` |
| `opacity` | ✅ | 颜色 alpha |
| `border-radius` | ⚠️ | 依赖图片资源本身是圆角图 |
| `border` | ⚠️ | 用 4 个细长图片拼，或圆角图 |
| `transform: translate/scale/rotateZ` | ✅ | 对应字段 |
| `transform: rotateX/Y` | ❌ | 字段可写但显示未实现 |
| `z-index` | ⚠️ | 映射 `SetSiblingIndex`，仅同级有效 |
| `overflow: hidden` | ❌ | **无解** |
| `box-shadow` | ❌ | 需图片资源 |
| `transition` / `animation` | ✅ | 用 `game.Tween` / `TweenSequence` |
| `:hover` `:active` | ✅ | `AddCursorEventListener` |
| `@media` | ⚠️ | 可用 `game.GetUICanvasSize()` 手动响应式 |

---

## 五、为什么建议不要引入 JS

理论路径：Lua 里跑一个 JS 解释器。

**不推荐，理由：**

1. **没有现成实现**。纯 Lua 的 JS 解释器基本不存在可用品。
2. **没有 `coroutine`**，而 JS 的 `async/await`、生成器、事件循环语义**天然依赖协程**。自己实现事件循环只能靠 `OnUpdate` 轮询，语义已经变形。
3. **性能**。每帧要跑 JS 解释器 + 布局 + 渲染，而 `OnUpdate` 是逐帧调用的。控件数量一多，帧预算直接爆掉。
4. **调试成本**。三层嵌套（Lua → JS → 你的 API）出错时极难定位。

**建议的替代方案**：既然目标语言是 Lua，直接做一个 **Lua 的声明式 UI DSL**，比套 JS 更自然：

```lua
-- 这是建议的实际用法
local ui = require('webui')

ui.mount(script.object, [[
  <div class="panel">
    <h1>标题</h1>
    <button onclick="onClick">点我</button>
  </div>
]], {
  onClick = function() print("clicked") end
})
```

保留 HTML 的**书写形态**（易读、AI 友好、可从网页工具导出），但事件绑定走 Lua 闭包。这样：
- 拿到 HTML 的可读性和 AI 生成友好度
- 避免 JS 引擎的全部开销
- 事件系统直接用 Lua 函数

如果你确实需要 JS，建议做成**受限表达式子集**（只求值，不控制流），比如 `onclick="count += 1"`。

---

## 六、推荐架构

```
┌─────────────────────────────────────────┐
│  你的 HTML 字符串                        │
└────────────────┬────────────────────────┘
                 │ 1. 解析（迭代式，不用 coroutine）
┌────────────────▼────────────────────────┐
│  html.lua   → DOM 树（Lua table）        │
│  css.lua    → 样式表 + 选择器匹配        │
│                + 层叠/继承/优先级        │
└────────────────┬────────────────────────┘
                 │ 2. 布局计算
┌────────────────▼────────────────────────┐
│  layout.lua → 每个节点的 盒子 + 绝对坐标 │
│   盒模型 / flex / 行盒 / 文本测量        │
└────────────────┬────────────────────────┘
                 │ 3. 差异对比 → 最小写入
┌────────────────▼────────────────────────┐
│  render.lua → diff 后写控件字段          │
│   复用控件池 / SetSiblingIndex 排序      │
└────────────────┬────────────────────────┘
                 │ 4. 事件回流
┌────────────────▼────────────────────────┐
│  event.lua  → 光标/按键/手柄 → 回调      │
└─────────────────────────────────────────┘
```

### 关键设计点

**0. 坐标系要翻转（最容易出错的地方）**

⚠️ **HTML 原点在左上、Y 向下；千星原点在左下、Y 向上。**

不能直接把 DOM/CSS 的坐标复制过来。布局器输出的坐标必须做一次变换：

```lua
-- 布局器内部按 HTML 习惯算（左上原点，Y 向下），输出时翻转
local function to_engine(x, y, canvas_h, node_h)
  return x, canvas_h - y - node_h      -- Y 轴翻转 + 减自身高度
end
```

官方《Lua 编码实现》指南也明确写了这条，并强调「不逐行翻译 HTML DOM/CSS/JavaScript」。

**1. 控件池复用 —— 官方推荐就是这个模式**

官方指南建议：**「少量基础模板 + Lua 实例化/修改属性」**，用 `game.InstantiateClientUIControl` 建控件，再由 Lua 设布局/文本/图片/可见性。

而且它警告：**在 UI 侧（存档/模板）直接定义复杂控件树或属性，导出或真机导入时可能不兼容**。

这等于说：我这套「Lua 建树」的方案正好踩在官方推荐路径上。控件池是必须的——`Instantiate` / `Destroy` 都不便宜。

**1b. 响应式基准是手机 16:9**

官方布局基准：**以手机 16:9 完整可见为准，PC 等比放大/留边**。所以 `@media` 或自适应应该按这个来。

另外提示：**缩放容器不要再加全屏不透明兄弟节点**（会遮挡）。

**2. Diff 渲染**

不要每帧重建整棵树。布局算完后与上一帧比对，只写变化的字段。

**3. 文本测量是难点**

要自己算换行，需要字形宽度。没有字体 API，只能：
- 用等宽近似（`fontSize × 0.5` 每字符）
- 或按 CJK 全宽、ASCII 半宽估算
- 或提供 `measureText` 钩子让用户覆盖

另外官方建议：**文本框开 `adaptiveFontSize = true`** 并设最小字号，处理多设备字号差异。但注意 `fontSize` / `minimumFontSize` **必须是整数** —— 真机上 `38 * 0.62 = 23.56` 会直接报 `bad argument #2 to 'fontSize' (integer expected, got number)`。所以你的 CSS `font-size: 1.2rem` 之类必须取整。

**3b. 文本溢出的行为**

文本框有自动换行，但**富文本未实现**。这意味着 `<b>` `<span style=...>` 混排做不到，一个文本框只有一种样式。需要混排时只能用多个文本框手动拼，或者改用 `ClientUITextWindowControl`。

**4. 层级排序的坑**

官方文档明确：**复用列表生成的列表项不保证同级排序结果稳定**。所以 z-index 语义在 grid scroller 里不可靠，文档里要标注。

---

## 七、工作量评估

| 模块 | 行数（Lua） | 难度 |
|---|---|---|
| HTML 解析器 | 400–600 | ★★ |
| CSS 解析器 + 选择器 | 500–800 | ★★ |
| 层叠/继承/优先级 | 300–500 | ★★★ |
| 盒模型 + 绝对定位 | 300–400 | ★★ |
| flex 布局 | 600–1000 | ★★★★ |
| 行盒/文本排版 | 500–900 | ★★★★ |
| 文本测量 | 200–400 | ★★★ |
| 渲染 + diff + 控件池 | 500–800 | ★★★ |
| 事件系统 | 300–500 | ★★★ |
| **合计** | **3.6k–5.9k** | |

MVP（只支持 `block` + `absolute` + 基础样式，不支持 flex/文本换行）约 **1.5k 行**可跑通。

---

## 八、渐进路线建议

**Phase 1 — 最小可用（1.5k 行）**
支持 `<div>` / `<span>` / `<img>` / `<button>`，`position: absolute` + 尺寸 + 颜色 + 文本。足以做面板、卡片、HUD。

**Phase 2 — 布局（+1.5k 行）**
加盒模型、`margin/padding`、简单 flex（单行）、文本自动换行。

**Phase 3 — 交互（+0.8k 行）**
光标事件、`:hover`/`:active`、按键、手柄导航、Tween 过渡动画。

**Phase 4 — 完善**
多行 flex、grid 映射到 `ClientUIGridScrollerControl`、虚拟列表。

---

## 九、另一个选择：先做设计工具

注意到有个现成项目 [miliastra-beyond-simulator](https://github.com/1475505/miliastra-beyond-simulator)（千星沙箱模拟器），它在浏览器里模拟这套控件 + Lua 运行时。

**思路**：既然浏览器里已经有"UGC 控件 API 的模拟层"，可以反过来利用——

- 在浏览器里用**真的 HTML/CSS 引擎**做开发和预览
- 你的库在浏览器里**不翻译**，直接把 HTML 丢给浏览器渲染（所见即所得）
- 只在导出到游戏时，才走"HTML → 控件树"的编译

这样开发体验接近现代前端，导出时接受子集限制。**代价**：浏览器能渲染的 CSS 远多于游戏能表达的，会出现"预览好好的，导出崩了"。

所以更好的做法是**双向约束**：库里维护一份能力白名单，浏览器预览模式下就禁用不支持的 CSS，保证所见即所得。

---

## 十、结论与建议

1. **`require` 已实测可用** ✅ —— 库可以拆多文件，模块化架构没有障碍。
2. **不要套 JS 引擎** —— 没有 coroutine，性价比极低。做 Lua DSL 更实在。
3. **`overflow: hidden` 是真痛点** —— 需先跑探针确认 `enableMask` 能否裁子节点；若不能，滚动类 UI 必须走 `ClientUIGridScrollerControl` / `ClientUITextWindowControl`。
4. **记得翻转 Y 轴** —— HTML 左上原点 Y 向下，千星左下原点 Y 向上。官方指南也点名了这条。
5. **方案踩在官方推荐路径上** —— 官方建议「少量基础模板 + Lua 实例化/修改属性」，且警告在 UI/GIA 侧定义复杂控件树可能导出不兼容。所以「Lua 建树」是正确方向。
6. **建议先做 Phase 1 MVP** 验证控件池 + diff 渲染的性能，这是整个方案的成败关键。
7. **性能是最大风险**：`OnUpdate` 逐帧跑布局 + diff，控件数上百后要实测帧率。

### 已解决项

**P0 —— ✅ `enableMask` 能裁子节点，且形状不限圆形**

> **2026-10-07 真机实测（`probe.lua` 模块 `mask`）：**
>
> - `enableMask=true` → **按图片的 alpha 通道裁剪子控件**
> - **形状完全由图片资源决定**，不是固定圆形：
>   - 圆形图 → 裁成圆形
>   - 三角形图 → 裁成三角形
>   - 四角星图 → 裁出星形缺口
> - `reverseMaskArea=true` → 反转保留区域
> - 同一组子控件（400×400 红块进 160×160 父）随图片切换，
>   红色占比在 **15.4% / 19.3% / 29.5%** 变化，mask 关闭时为 **64.4%**
>
> **影响：**
> - **任意形状裁剪可用** → 头像框、技能环、雷达，以及任何你配得出的形状
> - **矩形裁剪【已实现】**（R17 实证）—— 用**矩形图**当遮罩，
>   子控件被正确裁成矩形，**`overflow:hidden` 可用**。
> - **等比适配不变形**：圆形图在 2:1 的父控件里仍是**正圆**
>   （实测 1/4 高度处宽/中线宽 = 0.868，理论正圆值 0.866）

**P0-b —— ★ 运行时换图：✅ 可用（R16 实证）**

> **2026-10-07 真机实测：**
> ```lua
> img:SetImage(Enum.ImageSource.StaticReference, 100002)   -- 生效
> ```
> - 签名确认为 `SetImage(imageSource, imageId)`（与官方文档一致）
> - 实测 6 种形状切换，**5/6 读回确认改变，6/6 调用成功**
> - 字段 `imageId` / `imageSource` 只读，但**方法可写**
>
> 含义：一个图片控件可动态显示任意形状/图标。

**P1 —— 决定性能上限：**

1. `game.InstantiateClientUIControl` 单帧能创建多少控件？有无上限？
2. 一个界面**最多能有多少控件**？性能拐点在哪？
3. `SetSiblingIndex` 频繁调用的开销？

**P2 —— 影响实现细节：**

4. 文本框自动换行的行为边界（长英文单词、CJK 混排）？
5. 多设备下 `adaptiveFontSize` 的实际表现？

> 已解决的 P0 项已写入 `引擎能力与限制.md` §4.3（遮罩/换图/裁剪）。