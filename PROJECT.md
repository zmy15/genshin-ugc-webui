# webui 项目 · 文件清单

> 最后更新：2026-10-07

---

## 一、库（`lib/webui/`）

**交付物本体。12 个模块，4,800+ 行。**

| 文件 | 行数 | 职责 |
|---|---|---|
| `init.lua` | 274 | 对外 API（`new` / `render` / `flush` / `startLoop`） |
| `util.lua` | 265 | 字符串、数值、画布尺寸工具 |
| `dom.lua` | 316 | DOM 节点、class 管理、运行时样式 |
| `html.lua` | 266 | HTML 解析器 |
| `css.lua` | 350 | CSS 解析 + 选择器匹配 + 特指度 |
| `color.lua` | 180 | 颜色解析（hex / rgb / 命名色） |
| `style.lua` | 621 | 层叠、继承、默认样式、transform、裁剪形状推导 |
| `transition.lua` | 207 | `transition` 简写/长写法解析 |
| `layout.lua` | 694 | 盒模型 + flex（含 wrap / grow / shrink / column 对齐） |
| `render.lua` | 1159 | 控件池、diff 渲染、双层架构、z-index、**裁剪容器** |
| **`clip.lua`** | 246 | ★ **图片控件：遮罩 / 换图 / 染色**（运行时探测枚举） |
| `event.lua` | 250 | 事件绑定、伪类状态、坐标换算 |
| `README.md` | — | **使用文档（入口）** |

---

## 二、示例与探针（`deploy/`）

| 文件 | 说明 |
|---|---|
| **`probe.lua`** | ★ **统一真机探针**（改 `ACTIVE` 选模块，见 §五） |
| `demo_panel.lua` | **角色面板** —— 综合验证圆形/矩形裁剪、`SetImage` 换形状、文字渲染 |
| `demo_shop.lua` | 装备商店 —— 10 卡片、页签、筛选、购物车、结算、transition |

挂载方式：编辑器里挂到 `ProbeRoot`。

---

## 三、构建与验证（根目录）

| 文件 | 用途 |
|---|---|
| `build.lua` | 打包成单文件（`bundle/webui.lua`），供单文件部署 |
| `build_external.lua` | **扁平化输出到 `external_lua_file`**（多文件 require 部署） |
| `verify_external.lua` | 模拟真机 require 规则，验证部署正确性 |
| `engine_mock.lua` | ★ **真机仿真 mock** —— 严格模拟"自定义字段不可写"等限制 |

### 用法

```bash
# 部署到千星（多文件 require）
lua build_external.lua "<external_lua_file 路径>"
lua verify_external.lua "<external_lua_file 路径>"

# 打包成单文件
lua build.lua
```

### ⚠️ 部署铁律：真机读 `.gil`，不是文件夹

```
关卡目录/
  ├── <关卡ID>.gil          ← ★ 真机实际读的脚本内容
  └── external_lua_file/    ← 复制文件到这里【不够】
```

- **`Copy-Item` 不会更新 `.gil`** —— 必须让**编辑器导入**
- **新增文件**（如 `webui_clip.lua`）尤其容易漏
- 症状：**「本地验证全过 + 真机报 `failed to load script`」**

**每次跑真机前先执行：**

```bash
lua verify_external.lua "<external_lua_file 路径>"
```

它会检查每个模块的内容**是否已进入 `.gil`**，并明确提示哪个缺失：

```
========== 关卡文件同步检查 ==========
    clip         已在 .gil 中
    render       已在 .gil 中
  ✓ 全部模块已同步到关卡文件
```

> 此坑在 R16 白跑过一轮，详见 `ugc_out/引擎能力与限制.md` §八。

---

## 四、测试（19 个套件）

```bash
lua test_xxx.lua
```

| 套件 | 覆盖 |
|---|---|
| `test_html` | HTML 解析 |
| `test_css` | CSS 选择器、特指度 |
| `test_style` | 层叠、继承 |
| `test_layout` | 盒模型、定位 |
| `test_wrap` | `flex-wrap` 多行 |
| `test_features` | `transform` / `z-index` / `:hover` / `flex-grow` |
| `test_transition` | `transition` 解析 |
| `test_webui` | 端到端渲染 |
| `test_diff` | diff 写入正确性 |
| `test_list` | 列表重建 |
| `test_loop` | ★ 逐帧稳定性（防每帧重建） |
| `test_listener` | ★ 监听器生命周期（防泄漏） |
| `test_parent` | ★ 父链正确性（防坐标错乱） |
| `test_visible` | 控件可见性 |
| **`test_real`** | ★ **真机仿真**（用 `engine_mock`） |
| `test_shop` | 装备商店端到端 |
| `test_bundle` | 打包产物自检 |
| `test_real_prefabs` | 真实模板索引 |
| **`test_clip`** | ★ **裁剪 / 换图**（遮罩容器、矩形裁剪、透明处理） |
| `test_demo_panel` | 角色面板 demo 自检 |
| `test_probe` | 统一探针自检（四个模块都能跑通） |

**★ 标记的是关键回归测试**，各自对应真机上踩过的严重 bug。

---

## 五、真机探针（`deploy/probe.lua`）

**★ 只有一个探针文件。所有真机验证都往它里面加模块，不再新建文件。**

### 用法：改一行切换模块

```lua
local ACTIVE = "clip"     -- 改这里
```

| 模块 | 内容 |
|---|---|
| **`text`** | 文字渲染定位（框高/字号对照，交错设计） |
| **`clip`** | 裁剪容器（imageColor 对照：不设 / 透明 / 红色） |
| **`mask`** | 遮罩形状 / `SetImage` 换图 / 矩形裁剪 |
| **`glyph`** | 几何字符 + 无缝方案 |
| `all` | 依次跑全部（快速排查） |

探针头部固化了**历史结论索引**（R15~R19）和**硬性约束清单**，
写新验证前先读一遍，避免重复踩坑。

**本地试跑**：`lua test_probe.lua`（用 mock 验证四个模块都能跑通）

---

## 六、文档（`ugc_out/`）

| 文件 | 内容 |
|---|---|
| **`研究总览.md`** | ★ 入口。成果、历程、结论摘要、下一步 |
| **`引擎能力与限制.md`** | ★ 权威版。能力清单、约束、坐标、控件类型、方法学、部署机制 |
| `client_control_api.md` / `.json` | 官方 API 文档整理（75 表 / 699 行） |
| `GAPS.md` | 未实现功能 + 优先级建议 |
| `真机复用问题复盘.md` | 控件复用 bug 的完整排查 |
| `webui_feasibility.md` | 早期可行性分析（历史价值） |
| `lib/webui/README.md` | 库使用文档（API、示例、架构） |

---

## 七、其他

| 路径 | 说明 |
|---|---|
| `bundle/webui.lua` | 打包产物（单文件部署用） |
| `deploy/demo_panel.lua` | 角色面板示例（综合验证裁剪/换图/文字） |
| `deploy/demo_shop.lua` | 装备商店示例 |
| `deploy/probe.lua` | ★ 统一真机探针 |
| `ugc_parse.py` / `ugc_verify.py` | 官方文档抓取与整理脚本 |
| `lua/` | 与 webui 无关（C 解释器项目的历史文件） |

---

## 八、快速定位

| 我想…… | 看这里 |
|---|---|
| 学会用这个库 | `lib/webui/README.md` |
| 了解引擎能做什么/不能做什么 | `ugc_out/引擎能力与限制.md` |
| **知道有哪些"文字/裁剪"的坑** | `引擎能力与限制.md` §4.4 / §4.5 |
| 部署到游戏（含 `.gil` 同步坑） | `引擎能力与限制.md` §八 |
| 看完整成果与历程 | `ugc_out/研究总览.md` |
| 知道还缺什么 | `ugc_out/GAPS.md` |
| 看真实例子 | `deploy/demo_panel.lua` |
| 部署到游戏 | `build_external.lua` + `verify_external.lua` |
| **跑真机验证** | `deploy/probe.lua`（改 `ACTIVE` 选模块） |
| 跑测试 | `lua test_*.lua` |
| 写新测试 | 参考 `test_real.lua`（用 `engine_mock.lua`） |
