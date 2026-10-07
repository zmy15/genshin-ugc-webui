# 快速开始

用 Lua 在原神「千星奇域」（UGC）里渲染 HTML / CSS 风格的界面。

> 本文件从仓库根 `README.md` 的「快速开始」一节独立出来，
> 方便随 `lib/webui/` 一起分发到游戏工程。

---

## 写一个页面

只需给 HTML / CSS，以及当 JS 用的 Lua 事件处理。剩下的
（找根控件、渲染、绑事件、逐帧循环、等 Root 重试）都由库接管：

```lua
local webui = require('webui')

-- ★ 注意写法：必须先 local 声明，再赋值。
--   `local app = webui.mount{...}` 会让 on 表里的闭包看不到 app（恒为 nil），
--   因为 Lua 的 local 在整条赋值语句执行完之前对内部闭包不可见。
--
--   ★ onReady 里也一样看不到（它比 mount 返回更早触发），
--     要用它的第二个参数：onReady = function(ui, app) ... end
local app
app = webui.mount{
  root    = "Root",
  prefabs = { container=1073741933, textbox=1073741934,
              button=1073741935,    image=1073741938 },
  html = [[<div class="card" id="c" onclick="tap">你好</div>]],
  css  = [[
    .card { width:260px; height:60px; background-color:#222; font-size:16px; }
    .card:hover { background-color:#333; }
  ]],
  on = {
    tap = function() app:setText("c", "被点了") end,
  },
}

-- 引擎按固定名字找这几个函数，必须转接一次（3 行）
function OnStart()    app:start()  end
function OnUpdate(dt) app:update() end
function OnDestroy()  app:stop()   end
```

完整可跑示例见 [`deploy/demo_min.lua`](../../deploy/demo_min.lua)（82 行，
其中大半是 HTML/CSS）。**不写 mount 也可以** —— 用 `webui.new` 手动
控制每一步，见 [`deploy/demo_feature.lua`](../../deploy/demo_feature.lua)。

<details>
<summary>mount 到底替你做了什么</summary>

| 原来要手写 | 现在 |
|---|---|
| `game.FindClientUIRoot("Root")` | `root = "Root"` |
| `webui.new{...}` + `ui:render()` | `html` / `css` 两个字段 |
| `handlers` 表 | `on` 表 |
| 写 `startLoop`（递归 `TweenSequence`） | `loop`（默认开） |
| `OnStart` 里找 Root + `OnUpdate` 里重试 120 帧 | `app:start()` / `app:update()` |
| `OnDestroy` 里 `Kill` 循环 | `app:stop()` |
| 手写 `refreshCounter` 改文字 | `app:setText(id, text)` |

`app:setText` / `app:setStyle` 内部走 **DOM**（`node:setText`）而不是
直接写控件 —— 渲染器每帧都会用 DOM 文本覆盖控件，直接改 `control.text`
会在下一帧被打回原值（真机踩过：日志在涨、界面恒为 0）。
</details>


## 部署到游戏

### ① 导入脚本

**部署就是复制** —— 把 `lib/webui/` 里的文件全部复制到你的项目文件夹下，
然后在「千星沙箱」里**批量导入**：

<div align="center">

![部署](../../docs/img/2.png)

*「千星沙箱」客户端脚本导入*
</div>

### ② 创建容器节点 `Root`，并把 `main.lua` 挂在它下面

这是**最容易漏的一步**。库要靠 `game.FindClientUIRoot("Root")` 找到挂载点，
所以编辑器里必须有**一个名叫 `Root` 的客户端控件容器**，
并且**把 `main.lua` 挂到这个节点上**（脚本不挂上，进游戏什么都不会发生）。

**第一步：新建客户端控件容器**

在「界面控件组管理 → 客户端控件容器」里新建一个容器节点：

<div align="center">

![客户端控件容器](../../docs/img/root_create.png)

*在「界面控件组管理」里新建容器，名字叫 `Root`*
</div>

> ⚠️ 名字**必须是 `Root`**（区分大小写）。
> 想用别的名字也行，但要同步改 `main.lua` 里的 `root = "Root"`。

**第二步：把脚本挂到该节点上**

选中 `Root` 节点 → 切到「**脚本**」页签 → 挂上 `main`：

<div align="center">

![把脚本挂到 Root](../../docs/img/root_script.png)

*选中 `Root` → 「脚本」页签 → 挂载 `main`*
</div>

### ③ 设置容器的位置与缩放

选中 `Root`，在「变换」面板里设成下表的值：

| 字段 | 值 |
|---|---|
| 位置 | `X 800` / `Y 450`（1600×900 画布的中心） |
| 大小 | `W 1600` / `H 900` |
| **缩放比例** | **`X 1.01` / `Y 1.01`** ← 关键 |

**⚠️ 缩放必须是 `1.01`，不能是 `1.00`** —— 否则界面四周会留一圈缝
（控件渲染区域比画布小一点）。

<div align="center">

![根控件变换设置](../../docs/img/root_scale.png)

*「变换」面板：注意缩放是 `1.01`，不是 `1.00`*
</div>

### ④ 建控件模板，把索引填进 `prefabs`

库不直接画界面 —— 它是**实例化编辑器里预先建好的控件模板**。
所以要先把四种模板建出来，再把它们的**索引号**填进 `main.lua`。

**第一步：建四个客户端控件模板**

打开「界面控件组管理 → **界面控件组库** → **客户端控件模板**」，
建出这四种：

<div align="center">

![客户端控件模板](../../docs/img/template_list.png)

*「界面控件组库 → 客户端控件模板」：容器节点 / 文本框 / 预设按钮 / 图片*
</div>

| 模板 | 用途 | 必需？ |
|---|---|---|
| **容器节点** | 布局容器（无外观，只组织子控件） | ✅ |
| **文本框** | 所有文字与色块 | ✅ |
| **预设按钮** | 点击 / 悬停等交互层 | ✅ |
| **图片** | 圆形 / 矩形裁剪、形状图 | ⚠️ 裁剪功能必需 |

**第二步：读出每个模板的索引号**

点开模板，标题下方那一行「索引 `1073741xxx`」就是它：

<div align="center">

![容器节点的索引](../../docs/img/template_index.png)

*以「容器节点」为例：索引 `1073741933`（点右侧图标可复制）*
</div>

**第三步：填进 `prefabs`**

```lua
prefabs = {
  container = 1073741933,   -- ← 换成你自己模板的索引
  textbox   = 1073741934,
  button    = 1073741935,
  image     = 1073741938,   -- 圆形/矩形裁剪必需；不填头像出不来
},
```

> ⚠️ 索引**只在编辑器里能看到**，库无法自己发现，必须手工填。
> **填错不会报错**，只是 `InstantiateClientUIControl` 返回 `nil`、
> 控件建不出来 —— 界面上什么都没有时，先回来查这里。
>
> 想确认填得对不对，可以把 `prefabs` 原样喂给 `deploy/probe.lua`
> 的 `mount` 诊断模块（见库内 `probe.lua` 头部注释），它会逐个实测能否建出控件。

上面四步做完，进游戏就能看到 `main.lua` 的初始界面了。


---

## 相关文档

| 文档 | 内容 |
|---|---|
| [lib/webui/README.md](README.md) | 库的完整 API、支持的功能、架构 |
| [docs/引擎能力与限制.md](../../docs/引擎能力与限制.md) | ★ 权威版。能力、约束、坐标、方法学、部署机制 |
| [README.md](../../README.md) | 仓库总览 |
