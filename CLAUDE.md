# genshin-ugc-webui

用 Lua 在原神「千星奇域」（UGC）里渲染 HTML/CSS 风格的界面。
纯 Lua 实现，零外部依赖，运行在游戏沙箱内。

## 目录

```
lib/webui/   库本体（12 模块）—— 交付物，改动要谨慎
deploy/      示例与统一真机探针 probe.lua
docs/        文档（引擎能力与限制.md 是权威版）
tests/       20 个测试套件
tools/       构建 / 验证 / 真机仿真 mock
```

## 常用命令

```bash
# 跑全部测试（从仓库根执行）
for f in tests/test_*.lua; do lua "$f" >/dev/null 2>&1 || echo "FAIL $f"; done

# 打包单文件
lua tools/build.lua

# 部署并验证（含 .gil 同步检查）
lua tools/build_external.lua "<external_lua_file 路径>"
lua tools/verify_external.lua "<external_lua_file 路径>"
```

## 硬性约束（写代码前必读）

这些全是真机实测踩出来的，违反会导致**静默失败**（不报错但不对）：

| 约束 | 后果 |
|---|---|
| **文字框高 ≥ 字号 × 1.9** | 框太矮 → 引擎字号自适应把字压没，**文字凭空消失** |
| **裁剪容器不设 `background-color`** | 填充不受自身遮罩约束 → 溢出到裁剪区外 |
| **容器高度要装得下内容** | 溢出内容**仍可见但失去父背景** → "背景颜色不同" |
| **新控件 `active` 默认 `false`** | 必须 `SetActive(true)`，否则不可见但字段写入成功 |
| **自定义字段不可写** | 控件无法存状态，只能用外部表或 `GetChildren()` |
| **字段按控件类型封死** | 容器/按钮写 `bgColor`/`text` 静默失败 |
| **`fontSize` 必须整数** | 浮点写入失败 |
| **`OnUpdate` 不驱动** | 逐帧靠递归 `TweenSequence` |
| **枚举名不能照文档猜** | 真名 `Enum.ImageSource.StaticReference` |
| **真机读 `.gil` 不是文件夹** | 复制文件不生效，须编辑器导入 |

完整清单与证据：`docs/引擎能力与限制.md`

## 改动指南

- **改库** → 跑全部测试；涉及布局/渲染的改动要同时看 `docs/引擎能力与限制.md` 的约束
- **加真机验证** → 往 `deploy/probe.lua` 加模块（改 `ACTIVE` 切换），**不要新建探针文件**
- **改文档** → 权威版是 `docs/引擎能力与限制.md`；不要保留已被推翻的结论
- **新增库文件** → 同步 `tools/build.lua` 和 `tools/build_external.lua` 的 `MODULES` 列表

## 测试

20 个套件，路径自包含（任何目录可跑）。关键回归：

- `test_layout` — 盒模型 / flex（含 column 宽度语义、margin 计算）
- `test_clip` — 裁剪容器 / 换图 / 遮罩
- `test_real` — 真机仿真（用 `tools/engine_mock.lua`，严格模拟真机限制）
- `test_probe` — 统一探针自检

## 真机探针

```bash
# 改 deploy/probe.lua 顶部一行：
local ACTIVE = "clip"   -- text / clip / mask / glyph / all
```

模块含义见文件头部注释（那里也固化了历史结论和约束清单）。
