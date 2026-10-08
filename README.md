# genshin-ugc-webui

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Lua 5.3](https://img.shields.io/badge/Lua-5.3-2C2D72.svg?logo=lua&logoColor=white)](.github/workflows/tests.yml)

**用 Lua 在原神「千星奇域」（UGC）里渲染 HTML / CSS 风格的界面。**

一个纯 Lua 实现的轻量 WebUI 引擎 —— 把 HTML/CSS 解析、布局、渲染到游戏的客户端控件上。
零外部依赖，可在游戏沙箱内运行。

![功能展示](docs/img/1.png)

<div align="center">

*① 真机运行效果 —— 形状 / 裁剪 / flex / 事件，一屏内展示全部已验证能力*
</div>

---

## 这是什么

原神 UGC 的客户端控件 API 只提供基础控件（文本框、容器、按钮、图片）。
本项目在其上实现一套 **HTML/CSS 子集**，让你用熟悉的写法做界面：

```html
<div class="card">
  <div class="avatar"></div>
  <div class="name">若娜瓦</div>
  <div class="bar"><div class="fill"></div></div>
</div>
```
```css
.card   { width: 260px; height: 168px; overflow: hidden; }
.avatar { width: 130px; height: 130px; border-radius: 50%; }
.bar    { width: 440px; height: 16px; background-color: #2a3050; }
.fill   { width: 300px; height: 16px; background-color: #4ad07a; }
```

支持的 `overflow:hidden` 矩形裁剪、`border-radius` 圆形裁剪、
`flex` 布局、`transform`、`transition`、`:hover` 伪类、`z-index` 等。

---

## 能力概览

| 类别 | 支持 |
|---|---|
| **布局** | 盒模型、`flex`（含 `wrap` / `grow` / `shrink` / `column` 对齐）、绝对定位、百分比 / `px` / `em` |
| **样式** | CSS 选择器、层叠、继承、特指度、`:hover` / `:active` |
| **视觉** | 纯色块、文字、**圆形裁剪**、**矩形裁剪**、**任意形状裁剪**、`transform`、`transition`、`z-index` |
| **交互** | `onclick` / `onmouseenter` / `ondrag` 等 8 种光标事件、**键盘事件**（`keys`） |
| **游戏** | **`onTick(dt)` 逐帧逻辑钩子** —— 每帧先跑逻辑再渲染（物理 / 碰撞） |
| **图片** | 运行时 `SetImage` 换图、`imageColor` 染色 |

### 引擎做不到的

自定义字体、粗体/斜体、富文本、圆角/边框/阴影（只能预配图片）。

详见 [`docs/引擎能力与限制.md`](docs/引擎能力与限制.md)（权威版）。

---

## 快速开始

> 📖 完整版见 **[lib/webui/QUICKSTART.md](lib/webui/QUICKSTART.md)**
> —— 含示例代码、四步部署（导入脚本 / 建 `Root` 并挂脚本 / 设缩放 `1.01` /
> 建控件模板填 `prefabs`）与全部截图。

### 功能展示

`deploy/demo_feature.lua` 是一屏之内展示全部已验证能力的示例页，
也用于拍摄 README 顶部的那张截图：

| 区块 | 展示的能力 |
|---|---|
| 顶栏 / 标题 | 盒模型、flex（`justify-content: space-between`）、文字渲染 |
| 圆形头像 | `border-radius: 50%` 圆形裁剪（图片控件 + 圆形遮罩） |
| 形状行 | 六种预置形状：方 / 圆 / 三角 / 四角星 / 五角星 / 圆环（`SetImage` + `imageColor` 染色） |
| 裁剪区 | `overflow:hidden` 矩形裁剪 —— 内部色块宽 420px 超出容器 300px，溢出部分被切掉 |
| 组件区 | flex 行布局、进度条、按钮 `onclick` / `onmouseenter` 事件 |


## 开发


### 示例：小恐龙跳跃游戏

`deploy/demo_dino.lua` —— 用 `keys` 键盘绑定 + `onTick` 游戏循环做的
Chrome 离线小恐龙（跳跃 / 碰撞 / 重开 / 速度递增）。

```lua
app = webui.mount{
  html = HTML, css = CSS,
  keys = {
    jump   = onJump,      -- KeyboardJumpKeyDown
    jumpUp = onJumpUp,    -- KeyboardJumpKeyUp
  },
  onTick = function(dt) ... end,   -- 每帧先跑逻辑，再渲染
}
```

### 测试

```bash
cd <repo>
lua tests/test_html.lua      # 单个
for f in tests/test_*.lua; do lua "$f" || echo "FAIL $f"; done   # 全部
```

**32 个套件全部通过**（全部位于 `tests/`）。路径自包含，任何目录都能跑。


### 真机验证

`deploy/probe.lua` 是**统一探针**，改一行切换测试模块：

```lua
local ACTIVE = "key"   -- ★ 当前只有 key 一个模块
```

| 模块 | 内容 |
|---|---|
| `key` | ★ 键盘事件（`AddKeyEventListener` 能否用 —— 做跳跃类游戏的前提） |

> 历史上还有 `text` / `clip` / `mask` / `glyph` / `mount` 五个模块，
> 2026-10-07 精简时移除。它们的**结论、设计意图与重建要点**归档在
> [`docs/探针模块归档.md`](docs/探针模块归档.md) ——
> 要复验 R15~R19 的历史结论时按那里重建。

探针头部固化了**历史结论**和**硬性约束清单**，写新验证前先读。

---

## 关键约束（真机实测）

写代码前务必知道这几条 —— 都是踩过的坑：

| 约束 | 说明 |
|---|---|
| **文字框高 ≥ 字号 × 1.9** | 框太矮时引擎的**字号自适应会把字压没**，症状是"文字凭空消失"，而日志全对 |
| **文本框必须显式写 `background-color`** | 不写时引擎给**默认深色底**；字色若也是深色 → **文字看不见**（真机实测对比度仅 3） |
| **要居中必须写 `text-align`** | 默认 `left` → 文字贴框左边（实测左右边距差 470px）；框居中 ≠ 文字居中 |
| **裁剪容器不设 `background-color`** | 它的填充不受自身遮罩约束，会溢出到裁剪区外 |
| **容器高度要装得下内容** | 溢出内容**仍可见但失去父背景** → 看起来"某块背景颜色不同" |
| **新控件 `active` 默认 `false`** | 不调 `SetActive(true)` 则完全不可见，但字段写入照常成功 |
| **自定义字段不可写** | 控件上无法存状态；需用外部表或 `GetChildren()` |
| **字段按控件类型封死** | 容器/按钮写 `bgColor`/`text` 静默失败 |
| **`fontSize` 必须整数** | 浮点写入失败 |
| **`OnUpdate` 不驱动** | 逐帧靠递归 `TweenSequence`；库里等 Root 的重试也走这条路 |
| **枚举名不能照文档猜** | 真名是 `Enum.ImageSource.StaticReference` |
| **根控件缩放要设 `1.01`** | 编辑器里的手工设置。设成 `1.00` 时界面**四周留一圈缝**；库改不了 `localScale` |
| **必须有名为 `Root` 的容器节点** | 且**要把脚本挂在它下面**。库靠 `game.FindClientUIRoot("Root")` 找挂载点，缺了或名字不对 → **界面空白且无日志** |

完整的权威清单见 [`docs/引擎能力与限制.md`](docs/引擎能力与限制.md)。

---

## 文档

| 文档 | 内容 |
|---|---|
| [引擎能力与限制.md](docs/引擎能力与限制.md) | ★ 权威版。能力、约束、坐标、方法学、部署机制 |
| [研究总览.md](docs/研究总览.md) | ★ 入口。成果、历程、结论摘要 |
| [client_control_api.md](docs/client_control_api.md) | 官方 API 文档整理（75 表） |
| [GAPS.md](docs/GAPS.md) | 未实现功能 + 优先级 |
| [webui_feasibility.md](docs/webui_feasibility.md) | 早期可行性分析 |
| [真机复用问题复盘.md](docs/真机复用问题复盘.md) | 控件复用 bug 排查 |
| [lib/webui/README.md](lib/webui/README.md) | 库使用文档 |


---

## 目录结构

```
lib/webui/        ★ 库本体（12 个模块）。
                    文件名即部署名（webui_util.lua 等），整目录可直接拷进游戏工程
  ├── webui.lua         对外 API（入口）
  ├── webui_html.lua    HTML 解析
  ├── webui_css.lua     CSS 解析 + 选择器匹配
  ├── webui_style.lua   层叠 / 继承 / 计算样式
  ├── webui_layout.lua  盒模型 + flex
  ├── webui_render.lua  控件池 + diff 渲染
  ├── webui_clip.lua    图片控件（遮罩 / 换图 / 染色）
  └── ...
deploy/           示例与探针
  ├── my_page.lua   ★ 用户视角的完整示例（队伍配置），install 的起始页模板
  ├── probe.lua     统一真机探针（改 ACTIVE 选模块）
  ├── demo_feature.lua  功能展示页（形状 / 裁剪 / flex，用于截图）
  ├── demo_min.lua      最小示例（82 行）
  ├── demo_panel.lua    角色面板
  └── demo_shop.lua     装备商店
docs/             文档（引擎能力、API、Gaps 等）
tests/            32 个测试套件
tools/            构建、验证、mock
  ├── install.py        ★ 一键安装到游戏工程（库 + 起始页 + 说明）
  └── build.lua          可选：打成一个单文件（给"粘贴源码"场景）
```

---

## 开源协议

[MIT](LICENSE) © 2026 zmy15 —— 可自由使用、修改、分发、商用，
只需保留版权声明与协议全文。软件按"原样"提供，不含任何担保。
