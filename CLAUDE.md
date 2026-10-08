# genshin-ugc-webui

用 Lua 在原神「千星奇域」（UGC）里渲染 HTML/CSS 风格的界面。
纯 Lua 实现，零外部依赖，运行在游戏沙箱内。

## 目录

```
lib/webui/   库本体（13 模块）—— 交付物，改动要谨慎。
             ★ 文件名即真机部署名（webui_util.lua / webui_render.lua …），
               整个目录可直接拷进游戏工程，不需要构建改名。
deploy/      示例与统一真机探针 probe.lua
docs/        文档（引擎能力与限制.md = 引擎边界；小恐龙游戏实现.md = 游戏设计）
tests/       44 个测试套件
tools/       安装 / 打包 / 验证 / 真机仿真 mock
```

## 常用命令

```bash
# 跑全部测试（从仓库根执行）
for f in tests/test_*.lua; do lua "$f" >/dev/null 2>&1 || echo "FAIL $f"; done

# 打包单文件（给"粘贴源码"场景）
lua tools/build.lua

# 部署到游戏工程（库文件名已是真机可直接用的扁平形式，部署即复制）
python tools/install.py "<external_lua_file 路径>"        # 库 + 起始页 + 使用说明
lua tools/build_external.lua "<external_lua_file 路径>" # 只装库（转调 install.py）

# 部署校验（含 .gil 同步检查）
lua tools/verify_external.lua "<external_lua_file 路径>"
```

## 硬性约束（写代码前必读）

这些全是真机实测踩出来的，违反会导致**静默失败**（不报错但不对）：

| 约束 | 后果 |
|---|---|
| **文字框高 ≥ 字号 × 1.9** | 框太矮 → 引擎字号自适应把字压没，**文字凭空消失** |
| **文本框必须显式写 `background-color`** | 不写 → 引擎给**默认深色底**；字色若也是深色 → **文字看不见**（实测对比度 3） |
| **要居中必须写 `text-align`** | 默认 `left` → 文字贴框左边（实测左右边距差 470px） |
| **★★ 枚举名一律运行时取，禁止照文档写死** | 已踩三例：`Enum.ImageSource.StaticReference`（R16）、**`Enum.TextHorizontalAlignment.Middle` —— 文档写的扁平名 `…AlignmentMiddle` 在真机上是 `nil`**（R23）。配上 `pcall` 就成了「写入失败但静默」，`text-align:center` 因此失效好几轮。**必须显式取 + 取不到就 `warn`**。测试替身也要照**真机形态**造（见 `tests/enum_kit.lua`） |
| **多控件拼图：矩形必须 `position:absolute`** | 否则 inline 的 `left/top` 无效 → 全堆成一列（实测宽 47px，应为 176px） |
| **多控件拼图：相邻矩形要外扩 1px** | 真机色块实际宽比声明值略小 → 相邻块之间露 1.25~4.38px 背景缝 |
| **★★ 文本框模板自带圆角（半径 ≥8px）** | 8px 的色块被画成**圆形**；33 个矩形里 **88% 变形**。圆角来自模板，代码改不了（6 个 radius 字段写入全失败）→ **拼像素图必须用 `image` 控件**（模板是方的） |
| **拼图用 image 时不能写 `background-color`** | 写了会被 `chooseKind` 选回 **textbox** → 圆角又回来 |
| **★★ 游戏可解性要自己算** | 障碍高度/跳跃高度/碰撞盒一改就可能**死局**，而且不报错。实测「大仙人掌+高飞鸟」的公共安全区只有 **15px**（等同死局）→ **一波只能出一种障碍**。见 `docs/小恐龙游戏实现.md` §3 |
| **裁剪容器不设 `background-color`** | 填充不受自身遮罩约束 → 溢出到裁剪区外 |
| **容器高度要装得下内容** | 溢出内容**仍可见但失去父背景** → "背景颜色不同" |
| **新控件 `active` 默认 `false`** | 必须 `SetActive(true)`，否则不可见但字段写入成功 |
| **自定义字段不可写** | 控件无法存状态，只能用外部表或 `GetChildren()`。★ 这**包括**"标记控件是否已还池"—— 写 `ctrl._orphan` 是**空检查**（读回恒为 nil），要用 `rendered:isOrphan(ctrl)` |
| **复用控件会继承上一个主人的外观** | 还池只 `SetActive(false)`，`imageColor`/`text` 都不清 → 新主人没写就露馅。库已在 `_take` 里复位（染色→**全透明**，不是白色） |
| **字段按控件类型封死** | 容器/按钮写 `bgColor`/`text` 静默失败 |
| **`fontSize` 必须整数** | 浮点写入失败 |
| **`OnUpdate` 不驱动** | 逐帧靠递归 `TweenSequence` |
| **真机读 `.gil` 不是文件夹** | 复制文件不生效，须编辑器导入 |
| **根控件缩放必须 `1.01`** | 编辑器里手工设。`1.00` 时界面**四周留一圈缝**；库改不了 `localScale` |
| **必须有名为 `Root` 的容器节点 + 脚本挂在其下** | 库靠 `FindClientUIRoot("Root")` 找挂载点；缺了/名字不对 → **界面空白且无日志** |
| **★★ 隐藏但以后要点击的界面，不能用 `display:none`** | 子树被跳过 → 控件不建 → **事件根本不绑定**。"显示出来"后按钮点了毫无反应且无日志。要用 class 移出画布隐藏（`node:hide()` 同样是 `display:none`，且 `show()` 救不回来）。见 `docs/引擎能力与限制.md` §9.1 |

完整清单与证据：`docs/引擎能力与限制.md`

## 改动指南

- **改库** → 跑全部测试；涉及布局/渲染的改动要同时看 `docs/引擎能力与限制.md` 的约束
- **加真机验证** → 往 `deploy/probe.lua` 加模块（改 `ACTIVE` 切换），**不要新建探针文件**
- **改文档** → 引擎边界写 `docs/引擎能力与限制.md`（**只写能/不能做什么**）；
  游戏设计（数值/可解性/难度）写 `docs/小恐龙游戏实现.md`。不要保留已被推翻的结论
- **新增库文件** → 必须叫 `lib/webui/webui_<名字>.lua`（文件名即真机 require 名），
  并同步 `tools/build.lua` 的 `MODULES` 列表；`lib/webui/README.md` 的模块清单也要更新。
  命名不能带点：真机把 require 名原样当文件名，`webui.util` 会找不到文件。

## 测试

44 个套件，路径自包含（任何目录可跑）。关键回归：

- `test_layout` — 盒模型 / flex（含 column 宽度语义、margin 计算）
- `test_clip` — 裁剪容器 / 换图 / 遮罩
- `test_real` — 真机仿真（用 `tools/engine_mock.lua`，严格模拟真机限制）
- `test_pool_reset` — ★ **控件池复用的两个库级缺陷**（外观继承 / `isOrphan` 账本）
- `test_sprite_reassert` — ★ 拼像素图的每帧补帖图（白块回归）
- `test_probe` — 统一探针自检
- `test_build_check` — `tools/build.lua --check` 真的能发现过期产物（见下）
- `test_dino_rules` — ★ **游戏可解性**（纯数值验算 + 与 demo 源码交叉校验常量）
- `test_signal` — ★ **服务器信号**（签名校验 / 接收缓冲 / 限流 / 解绑防叠加）
- `test_mount` — ★ mount 生命周期（含 §8 信号接进逐帧循环的时序）
- `test_demo_signal` — ★ **按钮发信号**（模拟点击 → 读回引擎实收参数）
- `test_demo_dino_quit` — ★ **退出/结算窗口**（弹窗按钮可点、暂停计时、上报整数秒+分数）
- `test_demo_dino_style` — ★ 文字视觉回归（含弹窗文字必须被采样到，防 `display:none` 回归）
- `test_probe_align` — ★ align 探针自检（确认真机能拿到正确的读回表）
- `test_align_enum` — ★★ **水平对齐枚举真名**（用 `tests/enum_kit.lua` 按真机形态造 Enum，扁平名为 nil）

## 真机探针

```bash
# 改 deploy/probe.lua 顶部一行：
local ACTIVE = "perf"   -- key / perf / align
```

- `key` = 键盘事件验证（`AddKeyEventListener` 能否用）
- `perf` = 逐帧写入上限压测（4 档：10/40/80/160 控件）
- `align` = 文字居中 / 坐标系（五组对照，用于定位"文字不居中"）

历史上还有 `text` / `mask` / `glyph` / `clip` / `mount` 五个模块，
2026-10-07 精简时移除 —— 它们的**结论、设计意图与重建要点**归档在
`docs/探针模块归档.md`。**要复验历史结论（R15~R19）时按那里重建**，
不要凭记忆重写。
