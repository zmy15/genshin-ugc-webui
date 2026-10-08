# webui 项目 · 文件清单

> 最后更新：2026-10-07

---

## 一、库（`lib/webui/`）

**交付物本体。13 个模块，约 5400 行。**

> ★ 文件名**就是**真机部署名（`webui_util.lua` 对应 `require('webui_util')`），
> 整个目录可直接拷进游戏工程，不需要构建改名。

| 文件 | 行数 | 职责 |
|---|---|---|
| `webui.lua` | 844 | 对外 API（`mount` / `new` / `render` / `flush` / `startLoop`） |
| `webui_util.lua` | 222 | 字符串、数值、画布尺寸工具 |
| `webui_dom.lua` | 255 | DOM 节点、class 管理、运行时样式 |
| `webui_html.lua` | 213 | HTML 解析器 |
| `webui_css.lua` | 289 | CSS 解析 + 选择器匹配 + 特指度 |
| `webui_color.lua` | 156 | 颜色解析（hex / rgb / 命名色） |
| `webui_style.lua` | 483 | 层叠、继承、默认样式、transform、裁剪形状推导 |
| `webui_transition.lua` | 166 | `transition` 简写/长写法解析 |
| `webui_layout.lua` | 604 | 盒模型 + flex（含 wrap / grow / shrink / column 对齐） |
| `webui_render.lua` | 867 | 控件池、diff 渲染、双层架构、z-index、**裁剪容器** |
| **`webui_clip.lua`** | 175 | ★ **图片控件：遮罩 / 换图 / 染色**（运行时探测枚举） |
| `webui_event.lua` | 198 | 事件绑定、伪类状态、坐标换算 |
| **`webui_signal.lua`** | 1349 | ★ **服务器信号**：签名声明与校验、参数编解码、发送队列 + 冷却、接收缓冲、字节预算、极简 JSON |
| `README.md` | — | **使用文档（入口）** |

---

## 二、示例与探针（`deploy/`）

| 文件 | 说明 |
|---|---|
| **`probe.lua`** | ★ **统一真机探针**（改 `ACTIVE` 选模块，见 §五） |
| **`demo_dino.lua`** | ★ **小恐龙跳跃游戏**（真机验证通过）—— 演示 `keys` 键盘 + `onTick` 游戏循环 + **像素图形拼接**（16 个矩形拼出恐龙，绕开文本框圆角）；含三种仙人掌 / 两种飞行高度的翼龙 / 地面装饰；**左上角退出按钮 + 结算窗口**（暂停计时、上报时长与最高分） |
| `demo_panel.lua` | **角色面板** —— 综合验证圆形/矩形裁剪、`SetImage` 换形状、文字渲染 |
| **`demo_signal.lua`** | ★ **按钮发信号** —— 三个按钮分别演示 `emit` / `emitNow` / 字符串参数，含发送结果回显（区分"发出去了"和"被拦下"） |
| `demo_shop.lua` | 装备商店 —— 10 卡片、页签、筛选、购物车、结算、transition |

挂载方式：编辑器里挂到 `ProbeRoot`。

---

## 三、构建与验证（根目录）

| 文件 | 用途 |
|---|---|
| `install.py` | ★ **一键安装到游戏工程**（库 + 起始页 + 使用说明） |
| `build_external.lua` | 只装库到 `external_lua_file`（`install.py` 的薄封装） |
| `build.lua` | 打包成单文件（`bundle/webui.lua`），供"粘贴源码"场景；`--check` 与磁盘产物逐行比对，过期则 exit 1 |
| `verify_external.lua` | 模拟真机 require 规则，验证部署正确性（含 `.gil` 同步检查） |
| `engine_mock.lua` | ★ **真机仿真 mock** —— 严格模拟"自定义字段不可写"等限制 |

> `lib/webui/` 的文件名**就是**真机部署名（`webui_util.lua` / `require('webui_util')`），
> 所以部署退化成"复制"，不再需要改名或改写 require。

### 用法

```bash
# 部署到千星（推荐：库 + 起始页 + 使用说明）
python tools/install.py "<external_lua_file 路径>"
lua tools/verify_external.lua "<external_lua_file 路径>"

# 只装库
lua tools/build_external.lua "<external_lua_file 路径>"

# 打包成单文件
lua tools/build.lua
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

## 四、测试（43 个套件）

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
| **`test_build_check`** | ★ **`build.lua --check` 真能发现过期产物**（一致 / 过期 / 不存在 三分支 + 退出码与首个差异行断言） |
| `test_real_prefabs` | 真实模板索引 |
| **`test_clip`** | ★ **裁剪 / 换图**（遮罩容器、矩形裁剪、透明处理） |
| `test_demo_panel` | 角色面板 demo 自检 |
| **`test_input`** | ★ **按键绑定 + onTick 游戏循环钩子**（含"不能返回 true"断言） |
| **`test_demo_dino`** | ★ 小恐龙：跳跃物理 / 碰撞 / 速度上限（独立复刻状态机验数值） |
| **`test_demo_dino_run`** | ★ 小恐龙端到端：真跑 700+ 帧，验证开始/碰撞/重开/无泄漏 |
| **`test_demo_dino_style`** | ★ 文字视觉：所有文字框必须有显式背景 + 居中（守住 R21 两个坑） |
| **`test_dino_rules`** | ★ **游戏可解性**：跳跃/障碍/翼龙高度的几何约束，含与 demo 源码的常量交叉校验 |
| `test_demo_feature` | 功能展示页 demo 自检（形状 / 裁剪数 / 文字硬约束） |
| `test_probe` | 统一探针自检（`key` 模块含真实按键回调断言） |
| **`test_signal`** | ★ **服务器信号**：签名校验（个数/类型/顺序）、事件展开、接收缓冲与重放顺序、冷却限流、字节/条数预算顺延、解绑防叠加、JSON 往返 |
| **`test_demo_dino_quit`** | ★ **退出/结算窗口**：弹窗按钮必须有点击回调、暂停期间计时不走、上报整数秒+最高分、防连点、结算后重开 |
| **`test_demo_dino_style`** | ★ 文字视觉回归（含弹窗文字必须被采样到 —— 防有人改回 `display:none` 导致假阳性） |
| **`test_demo_signal`** | ★ **按钮 -> 发信号**：模拟点击三个按钮，读回引擎实际收到的参数（名/个数/顺序/类型），并验证文字反馈确实更新 |
| **`test_mount`** | ★ mount 生命周期（含 §8：信号接进逐帧循环的时序 + stop 解绑） |

**★ 标记的是关键回归测试**，各自对应真机上踩过的严重 bug。

---

## 五、真机探针（`deploy/probe.lua`）

**★ 只有一个探针文件。所有真机验证都往它里面加模块，不再新建文件。**

### 用法：改一行切换模块

```lua
local ACTIVE = "key"     -- 改这里（★ 当前只有 key 一个模块）
```

| 模块 | 内容 |
|---|---|
| **`key`** | ★ 键盘事件（`AddKeyEventListener` 能否用 —— 做跳跃类游戏的前提） |
| **`perf`** | ★ 逐帧写入上限（4 档加压：10/40/80/160 控件）—— 决定"多控件拼图"是否可行 |

> ⚠️ **已移除的模块**：`text` / `mask` / `glyph` / `clip` / `mount`
> （2026-10-07 精简）。它们的**结论、设计意图与重建要点**归档在
> `docs/探针模块归档.md`。
>
> 要复验 R15~R19 的历史结论（矩形裁剪 / 字形有缝 / 框高阈值…）时，
> **按该文档重建模块**，不要凭记忆重写。
> 若 `main.lua` 又出现"界面空白且无日志"，**优先重建 `mount`**。

探针头部固化了**历史结论索引**（R15~R19）和**硬性约束清单**，
写新验证前先读一遍，避免重复踩坑。

**本地试跑**：`lua test_probe.lua`（用 mock 验证探针模块能跑通）

---

## 六、文档（`ugc_out/`）

| 文件 | 内容 |
|---|---|
| **`研究总览.md`** | ★ 入口。成果、历程、结论摘要、下一步 |
| **`引擎能力与限制.md`** | ★ 权威版。**引擎能做什么 / 做不到什么**：能力清单、约束、坐标、控件类型、方法学、部署机制 |
| **`小恐龙游戏实现.md`** | ★ **游戏设计**：精灵尺寸、摆放几何、**可解性三约束**、组宽预算、难度曲线 |
| `client_control_api.md` / `.json` | 官方 API 文档整理（75 表 / 699 行） |
| `GAPS.md` | 未实现功能 + 优先级建议 |
| `真机复用问题复盘.md` | 控件复用 bug 的完整排查 |
| `webui_feasibility.md` | 早期可行性分析（历史价值） |
| `lib/webui/README.md` | 库使用文档（API、示例、架构） |

---

## 七、其他

| 路径 | 说明 |
|---|---|
| `LICENSE` | 开源协议（MIT © 2026 zmy15） |
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
| 部署到游戏 | `install.py` + `verify_external.lua` |
| **跑真机验证** | `deploy/probe.lua`（改 `ACTIVE` 选模块） |
| 跑测试 | `lua test_*.lua` |
| 写新测试 | 参考 `test_real.lua`（用 `engine_mock.lua`） |
