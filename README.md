# genshin-ugc-webui

**用 Lua 在原神「千星奇域」（UGC）里渲染 HTML / CSS 风格的界面。**

一个纯 Lua 实现的轻量 WebUI 引擎 —— 把 HTML/CSS 解析、布局、渲染到游戏的客户端控件上。
零外部依赖，可在游戏沙箱内运行。

---

## 这是什么

原神 UGC 的客户端控件 API 只提供基础控件（文本框、容器、按钮、图片）。
本项目在其上实现一套 **HTML/CSS 子集**，让你用熟悉的写法做界面：

```html
<div class="card">
  <div class="avatar"></div>
  <div class="name">夜兰</div>
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
| **交互** | `onclick` / `onmouseenter` / `ondrag` 等 8 种光标事件 |
| **图片** | 运行时 `SetImage` 换图、`imageColor` 染色 |

### 引擎做不到的

自定义字体、粗体/斜体、富文本、圆角/边框/阴影（只能预配图片）。

详见 [`docs/引擎能力与限制.md`](docs/引擎能力与限制.md)（权威版）。

---

## 目录结构

```
lib/webui/        ★ 库本体（12 个模块，4800+ 行）
  ├── init.lua      对外 API
  ├── html.lua      HTML 解析
  ├── css.lua       CSS 解析 + 选择器匹配
  ├── style.lua     层叠 / 继承 / 计算样式
  ├── layout.lua    盒模型 + flex
  ├── render.lua    控件池 + diff 渲染
  ├── clip.lua      图片控件（遮罩 / 换图 / 染色）
  └── ...
deploy/           示例与探针
  ├── probe.lua     ★ 统一真机探针（改 ACTIVE 选模块）
  ├── demo_panel.lua   角色面板
  └── demo_shop.lua    装备商店
docs/             文档（引擎能力、API、Gaps 等）
tests/            20 个测试套件
tools/            构建、验证、mock
```

---

## 快速开始

### 跑测试

```bash
cd <repo>
lua tests/test_html.lua      # 单个
for f in tests/test_*.lua; do lua "$f" || echo "FAIL $f"; done   # 全部
```

**20 个套件全部通过。** 路径自包含，任何目录都能跑。

### 打包

```bash
lua tools/build.lua                 # -> bundle/webui.lua（单文件）
lua tools/build_external.lua <目标目录>   # 扁平化多文件
```

### 部署到游戏

```bash
lua tools/verify_external.lua "<external_lua_file 路径>"
```

> ⚠️ **部署铁律**：真机读的是关卡文件 `.gil`，**不是文件夹**。
> 复制文件进去**不生效**，必须让**编辑器导入**。
> 症状是「本地验证全过 + 真机报 `failed to load script`」。
> `verify_external.lua` 会检查同步状态。详见 `docs/引擎能力与限制.md` §八。

### 真机验证

`deploy/probe.lua` 是**统一探针**，改一行切换测试模块：

```lua
local ACTIVE = "clip"   -- text / clip / mask / glyph / all
```

| 模块 | 内容 |
|---|---|
| `text` | 文字渲染定位（框高/字号对照） |
| `clip` | 裁剪容器（imageColor 对照） |
| `mask` | 遮罩形状 / 换图 / 矩形裁剪 |
| `glyph` | 几何字符 / 无缝方案 |

探针头部固化了**历史结论**和**硬性约束清单**，写新验证前先读。

---

## 关键约束（真机实测）

写代码前务必知道这几条 —— 都是踩过的坑：

| 约束 | 说明 |
|---|---|
| **文字框高 ≥ 字号 × 1.9** | 框太矮时引擎的**字号自适应会把字压没**，症状是"文字凭空消失"，而日志全对 |
| **裁剪容器不设 `background-color`** | 它的填充不受自身遮罩约束，会溢出到裁剪区外 |
| **容器高度要装得下内容** | 溢出内容**仍可见但失去父背景** → 看起来"某块背景颜色不同" |
| **新控件 `active` 默认 `false`** | 不调 `SetActive(true)` 则完全不可见，但字段写入照常成功 |
| **自定义字段不可写** | 控件上无法存状态；需用外部表或 `GetChildren()` |
| **字段按控件类型封死** | 容器/按钮写 `bgColor`/`text` 静默失败 |
| **`fontSize` 必须整数** | 浮点写入失败 |
| **`OnUpdate` 不驱动** | 逐帧靠递归 `TweenSequence` |
| **枚举名不能照文档猜** | 真名是 `Enum.ImageSource.StaticReference` |

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

## 开发历程（14 个真机 bug）

项目靠**真机探针 + 像素测量**逐步推进，修掉的 bug 包括：

**早期（库联调）**
1. 按钮不显示 → **双层架构**（textbox 视觉 + button 交互）
2. 点击后界面不变 → 运行时样式 `_inline`
3. 越用越卡 → 按字段失效缓存
4. 文字不更新 → `node:setText()`
5. 动态列表后控件全不可见 → 复用后 `SetActive(true)`
6. 样式表无限增长 → 重置 + `_extraSheets`
7. 监听器累积 → `RemoveAllCursorEventListeners`
8. 每帧重建全部控件 → 用 `domChanged` 区分路径
9. 控件复用完全失效 → 改用 `GetChildren()` 反查（自定义字段写不进）

**能力探索期**
10. 几何字符度量 → 引擎字体 advance 是 1.59em（非全角）
11. 遮罩形状 → 由**图片 alpha** 决定，不限圆形
12. `SetImage` → 运行时换图**可用**（字段只读但有 Setter）
13. **矩形裁剪 → 用矩形图当遮罩即可实现 `overflow:hidden`**

**深度联调期**
14. 文字消失 / 头像变椭圆 / 白竖条 / 暗色月牙 / 裁剪白边
    → 4 个布局与裁剪 bug（见 `docs/引擎能力与限制.md` §4.5）

---

## 测试方法学（血泪教训）

| 原则 | 说明 |
|---|---|
| **探针必须读回实际值** | 只打印"我打算设什么"会误导 |
| **一次只改一个变量** | 否则无法定位 |
| **测试替身必须忠实** | mock 不模拟真机限制 → 全是假阳性 |
| **未见过的现象先量像素，不猜** | 连续猜错 3 轮，每次都是像素测量给出答案 |
| **别用截图反推行号** | 用**交错设计**让模式自证，比反推可靠 |
| **一处 bug 常有多个症状** | 修完一个点、多个症状一起消失 = 找到根因 |