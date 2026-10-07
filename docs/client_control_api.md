# 原神 UGC · 客户端控件 Lua UI 脚本公共 API 文档

> 来源：米游社 UGC Wiki · `mhtakr07vej4`（更新于 2026-09-14）
> 本文档介绍客户端 Lua UI 脚本公共 API，包括接口签名、类型、字段、函数、方法和枚举。

## 目录

- [一、术语约定](#一术语约定)
- [二、API 范围](#二api-范围)
- [三、运行环境](#三运行环境)
- [四、具体介绍](#四具体介绍)
  - [1. 脚本生命周期](#1-脚本生命周期)
  - [2. 逐帧控制方法](#2-逐帧控制方法)
  - [3. 全局 API](#3-全局-api)
  - [4. Color](#4-color)
  - [5. Script](#5-script)
  - [6. game](#6-game)
  - [7. Tween](#7-tween)
  - [8. TweenSequence](#8-tweensequence)
  - [9. ServerSignal](#9-serversignal)
  - [10. EnumItem](#10-enumitem)
  - [11. 枚举系统](#11-枚举系统)
  - [12. 客户端控件](#12-客户端控件)
  - [13. ClientUIBaseControl](#13-clientuibasecontrol)
  - [14. ClientUIImageControl](#14-clientuiimagecontrol)
  - [15. ClientUITextBoxControl](#15-clientuitextboxcontrol)
  - [16. ClientUITextWindowControl](#16-clientuitextwindowcontrol)
  - [17. ClientUIPresetButtonControl](#17-clientuipresetbuttoncontrol)
  - [18. ClientUICursorEventAreaControl](#18-clientuicursoreventareacontrol)
  - [19. CursorEventData](#19-cursoreventdata)
  - [20. ClientUIGridScrollerControl](#20-clientuigridscrollercontrol)
  - [21. ClientUIKeyHintControl](#21-clientuikeyhintcontrol)
  - [22. ClientUIAnimationControl](#22-clientuianimationcontrol)
  - [23. ClientUIFullscreenAnimationControl](#23-clientuifullscreenanimationcontrol)
  - [24. ClientUIContainerControl](#24-clientuicontainercontrol)
  - [25. ClientUIReferenceControl](#25-clientuireferencecontrol)
  - [26. 按键输入](#26-按键输入)

## 一、术语约定

本部分为 API 专有名词的中英文对照约定，**不代表实际接口和字段名称**。

| 中文名词 | 英文名词 |
|---|---|
| 脚本 | Script |
| 信号 | ServerSignal |
| 自定义变量 | CustomVariable |
| 脚本内的参数 | Param |
| 补间动画 | Tween |
| 进度 | fillAmount |
| 基础 | Basic |
| 拉伸 | Stretch |
| 边缘羽化 | soft edge |
| 90度环绕 | Radial90 |
| 180度环绕 | Radial180 |
| 360度环绕 | Radial360 |
| 客户端控件运行时ID | ClientControlID |
| 客户端控件运行时ID列表 | ClientControlIDList |
| 关卡时停 | LevelTimePaused |
| 容器节点 | ContainerControl |
| 文本框 | TextBoxControl |
| 文本视窗 | TextWindowControl |
| 图片 | ImageControl |
| 界面动效 | UIAnimationControl |
| 全屏动效 | FullscreenUIAnimationControl |
| 按键提示 | KeyHintControl |
| 网格视窗 | GridScrollerControl |
| 光标检测区域 | CursorEventArea |
| 模板引用控件 | ReferenceControl |
| 预设按钮 | PresetButton |
| 存活 | alive |
| 启用 | enable |
| 激活 | active |
| 可见 | visible |
| 隔离手柄导航 | IsolateNavigation |
| 屏蔽按键事件穿透 | disableKeyEventPassthrough |
| 屏蔽区域内点击事件穿透 | disableCursorEventPassthrough |
| 显示常驻光标 | showCursor |
| 可被光标射线检测 | Raycast Target |

## 二、API 范围

本页覆盖：脚本生命周期、全局函数、颜色、Script、game、服务器信号、补间动画、输入事件、手柄导航、全部客户端控件类型及枚举。

## 三、运行环境

- **Lua 版本**：Lua 5.3

以下标准库能力**不可用**：

- `string.dump`
- `io.*`
- `coroutine.*`
- 除 `os.time`、`os.date`、`os.clock`、`os.difftime` 外的 `os.*`
- 除 `debug.traceback` 外的 `debug.*`

以下为标准库补充的方法：

- `math.isnan(n)` 和 `math.isinf(n)`

## 四、具体介绍

### 1. 脚本生命周期

运行时按**固定名称**查找并调用下列生命周期回调函数。

| 函数 | 参数 | 功能 |
|---|---|---|
| `OnInit()` | 无 | 脚本初始化时调用 |
| `OnStart()` | 无 | 脚本启动时调用 |
| `OnEnable()` | 无 | 脚本启用时调用 |
| `OnDisable()` | 无 | 脚本停用时调用 |
| `OnUpdate(dt)` | `dt: number` | 脚本逐帧更新时调用，**不受关卡时停影响** |
| `OnLevelUpdate(dt)` | `dt: number` | 关卡逐帧更新时调用，**受关卡时停影响** |
| `OnDestroy()` | 无 | 脚本销毁时调用 |

### 2. 逐帧控制方法

| 方法 | 返回值 | 说明 |
|---|---|---|
| `script:EnableUpdate(enabled: boolean)` | — | 控制当前脚本的逐帧更新；`false` 关闭，`true` 重新启用 |

### 3. 全局 API

#### (1) 类型查询

| 函数 | 返回值 | 说明 |
|---|---|---|
| `typeof(value)` | `string` | 返回运行时类型名称；用于识别宿主对象 |

#### (2) 日志和调试

| 函数 | 返回值 | 说明 |
|---|---|---|
| `print(...)` | — | 将传入值写入普通级别日志；该函数不阻断运行 |
| `printerr(...)` | — | 将传入值写入错误级别日志；该函数不抛出 Lua 错误，也不阻断运行 |
| `debug.traceback([message[, level]])` | `string` | 生成并返回调用栈文本；`message` 添加文本开头的说明，`level` 指定调用栈起始层级；该函数仅返回文本，不自动写入日志 |
| `game.PrintClientUITree()` | — | 将当前客户端控件树按父子层级写入日志 |

#### (3) 数值检查

处理摇杆、坐标或补间动画参数等外部数值时，可用这两个函数进行有限数校验。

| 函数 | 返回值 | 说明 |
|---|---|---|
| `math.isnan(n)` | `boolean` | 判断数值是否为 NaN |
| `math.isinf(n)` | `boolean` | 判断数值是否为正负无穷 |

#### (4) 全局变量

| 名称 | 类型 | 说明 |
|---|---|---|
| `script` | `Script` | 当前脚本 |
| `Enum` | `Enum` | 枚举 |

### 4. Color

#### (1) 构造函数

| 构造函数 | 返回值 | 说明 |
|---|---|---|
| `Color(r: number, g: number, b: number, a: number?)` | `ColorValue` | 由 0–255 RGBA 创建颜色；`a` 可省略，也可传 `nil`。传 `nil` 时等同于 255（不透明） |

#### (2) 函数

| 函数 | 返回值 | 说明 |
|---|---|---|
| `Color.FromRGB(r: number, g: number, b: number)` | `ColorValue` | 由 0–255 RGB 创建颜色 |
| `Color.FromRGBA(r: number, g: number, b: number, a: number?)` | `ColorValue` | 由 0–255 RGBA 创建颜色；`a` 可省略或传 `nil`。传 `nil` 时等同于 255（不透明） |
| `Color.ToRGBA(colorValue: ColorValue)` | `r, g, b, a: number` | 将颜色拆分为 0-255 的 RGBA 四个值 |

### 5. Script

表示脚本实例。运行时通过全局变量 `script` 提供当前脚本实例。

#### (1) 字段

| 字段 | 类型 | 访问 | 说明 |
|---|---|---|---|
| `alive` | `boolean` | **只读** | 脚本实例是否存活 |
| `scriptMappingId` | `integer` | **只读** | 脚本映射 ID |
| `object` | `any` | **只读** | 脚本所挂载的宿主对象 |
| `path` | `string` | **只读** | 脚本路径 |
| `enabled` | `boolean` | **读写** | 脚本启用状态 |

#### (2) 方法

| 方法 | 返回值 | 说明 |
|---|---|---|
| `script:GetParam(paramName: string)` | `any` | 按变量名称 `paramName` 读取当前脚本内对应变量的参数 |
| `script:Invoke(funcName: string, ...: any)` | — | 在 UI 脚本内定义的全局方法（脚本内环境）；调用当前脚本中名称为 `funcName` 的函数；参数应使用运行时支持的可传递类型 |
| `script:EnableUpdate(enabled: boolean)` | — | 控制当前脚本的 Tick 更新；`false` 关闭，`true` 重新启用 |
| `script:RegisterServerSignalHandler(signalName: string, callback: fun(signalName: string, signalParams: any[]))` | — | 注册 `signalName` 对应的服务器信号监听；回调参数依次为信号名称和信号参数数组 |
| `script:UnregisterServerSignalHandler(signalName: string)` | — | 移除 `signalName` 对应的服务器信号监听 |
| `script:RegisterCustomVariableChangedHandler(entityType: CustomVariableEntityType, customVariableName: string, callback: fun(entityType: CustomVariableEntityType, customVariableName: string))` | — | 监听 `entityType` 和 `customVariableName` 对应的全局自定义变量变化；回调仅提供实体类型和变量名称，**当前值需通过 `game.GetGlobalCustomVariableValue` 读取** |
| `script:UnregisterCustomVariableChangedHandler(entityType: CustomVariableEntityType, customVariableName: string)` | — | 移除 `entityType` 和 `customVariableName` 对应的自定义变量监听 |

### 6. game

`game` 是客户端运行时提供的全局表。**以下函数均使用点号调用**。

#### (1) UI 与层级

| 函数 | 返回值 | 说明 |
|---|---|---|
| `game.InstantiateClientUIControl(controlPrefabIndex: integer, parent: ClientUIBaseControl)` | `ClientUIBaseControl` | 根据已配置的控件模板索引，在 `parent` 下创建控件实例 |
| `game.DestroyClientUIControl(control: ClientUIBaseControl)` | — | 销毁指定客户端控件实例 |
| `game.GetClientUIControl(controlId: integer)` | `ClientUIBaseControl` | 按客户端控件运行时 ID 获取控件 |
| `game.FindClientUIRoot(nodeName: string)` | `ClientUIBaseControl` | 查找名称为 `nodeName` 的 UI 根控件 |
| `game.GetClientUIRoots()` | `ClientUIBaseControl[]` | 获取全部 UI 根控件。即实际显示的客户端控件容器画布中的默认容器节点 |
| `game.GetUICanvasSize()` | `x, y: number` | 获取 UI 画布宽高 |
| `game.GetCursorUIPos()` | `x, y: number` | 获取光标 UI 坐标 |

#### (2) 输入与聚焦

读取摇杆轴值后，可按交互需求应用有限数检查、死区、范围钳制与坐标系转换。

| 函数 | 返回值 | 说明 |
|---|---|---|
| `game.GetDevice()` | `Device` | 获取当前输入设备类型 |
| `game.SetControllerFocus(control: ClientUIBaseControl)` | — | 设置手柄当前聚焦控件 |
| `game.GetControllerFocus()` | `ClientUIBaseControl` | 获取当前聚焦控件 |
| `game.GetControllerLeftStickAxis()` | `horizontal, vertical: number` | 获取左摇杆轴值 |
| `game.GetControllerRightStickAxis()` | `horizontal, vertical: number` | 获取右摇杆轴值 |

#### (3) 补间动画、服务器信号与自定义变量

| 函数 | 返回值 | 说明 |
|---|---|---|
| `game.Tween(object: any, tweenDataTable: table, duration: number)` | `Tween` | 按目标字段和持续时间为对象创建补间动画。传入参数分别为传入对象、传入对象的 tweenable 字段名为键，目标值为值组成的 table，持续时间 |
| `game.TweenSequence()` | `TweenSequence` | 创建空的补间动画序列 |
| `game.ServerSignal(signalName: string)` | `ServerSignal` | 使用服务器约定的信号名称 `signalName` 创建服务器信号 |
| `game.GetGlobalCustomVariableValue(entityType: CustomVariableEntityType, customVariableName: string)` | `any` | 读取 `entityType` 和 `customVariableName` 对应的全局自定义变量，支持复杂变量结构（列表、字典、结构体） |

#### (4) 关卡、音效与本地化

| 函数 | 返回值 | 说明 |
|---|---|---|
| `game.PauseLevelTime(pause: boolean)` | — | 单人模式下设置关卡时停状态；`true` 开启，`false` 关闭；**不暂停脚本自身** |
| `game.IsLevelTimePaused()` | `boolean` | 查询是否处于关卡时停 |
| `game.PlayAudio2D(audioId: integer)` | `integer` | 按已配置的音效 ID 播放 2D 音效，并返回音效实例 ID |
| `game.StopAudio(audioInstanceId: integer)` | — | 停止指定音效实例 |
| `game.IsAudioAlive(audioInstanceId: integer)` | `boolean` | 查询音效实例是否存活 |
| `game.GetLanguageType()` | `LanguageType` | 获取当前语言 |
| `game.GetStageMode()` | `StageMode` | 获取当前关卡模式 |
| `game.IsTestPlay()` | `boolean` | 查询当前是否处于测试游玩状态 |
| `game.GetText(textMapId: string)` | `string` | 按已配置的文本映射 ID 获取本地化文本 |

### 7. Tween

补间动画类，用于对目标对象的 Tweenable 字段进行插值。

#### (1) 创建

| 函数 | 返回值 | 说明 |
|---|---|---|
| `game.Tween(object: any, tweenDataTable: table, duration: number)` | `Tween` | 按目标字段和持续时间为对象创建补间动画。传入参数分别为传入对象、传入对象的 tweenable 字段名为键，目标值为值组成的 table，持续时间 |

#### (2) 方法

| 方法 | 返回值 | 说明 |
|---|---|---|
| `Tween:SetEase(easeType: EaseType)` | `Tween` | 设置缓动类型并返回当前实例 |
| `Tween:SetRelative(relative: boolean)` | `Tween` | 设置 `tweenDataTable` 中目标值的解释方式；`false` 表示绝对目标值，`true` 表示相对当前值的增量 |
| `Tween:Play()` | `Tween` | 开始播放并返回当前实例 |
| `Tween:Pause()` | — | 暂停并保留当前进度 |
| `Tween:Resume()` | — | 从暂停处继续播放 |
| `Tween:Restart()` | — | 回到初始状态并重新播放 |
| `Tween:Complete()` | — | 立即切换到结束状态并完成 |
| `Tween:Kill(complete: boolean)` | — | 销毁实例；`true` 表示先切换到结束状态并触发完成回调，`false` 表示保持当前状态结束且不触发完成回调 |
| `Tween:SetOnComplete(onComplete: fun())` | `Tween` | 设置全部循环完成后的回调并返回当前实例 |
| `Tween:SetOnStepComplete(onStepComplete: fun())` | `Tween` | 设置步骤完成回调并返回当前实例 |
| `Tween:SetLoops(times: integer)` | `Tween` | 设置循环次数并返回当前实例；**负数表示无限循环** |

### 8. TweenSequence

将多个补间动画、间隔和回调编排到同一时间线上。

#### (1) 创建

| 函数 | 返回值 | 说明 |
|---|---|---|
| `game.TweenSequence()` | `TweenSequence` | 创建空的补间动画序列 |

#### (2) 方法

| 方法 | 返回值 | 说明 |
|---|---|---|
| `TweenSequence:Append(tween: Tween)` | `TweenSequence` | 在序列末尾接入补间动画 |
| `TweenSequence:AppendInterval(interval: number)` | `TweenSequence` | 在序列末尾接入指定秒数的等待时间 |
| `TweenSequence:AppendCallback(callback: fun())` | `TweenSequence` | 在序列末尾接入回调 |
| `TweenSequence:Join(tween: Tween)` | `TweenSequence` | 与当前队尾步骤同时播放；该步骤以最晚结束者为准 |
| `TweenSequence:Insert(time: number, tween: Tween)` | `TweenSequence` | 在指定时间点插入并行补间动画 |
| `TweenSequence:InsertCallback(time: number, callback: fun())` | `TweenSequence` | 在指定时间点插入回调 |
| `TweenSequence:Play()` | `TweenSequence` | 开始播放并返回当前实例 |
| `TweenSequence:Pause()` | — | 暂停序列 |
| `TweenSequence:Resume()` | — | 继续播放序列 |
| `TweenSequence:Restart()` | — | 回到初始状态并重新播放 |
| `TweenSequence:Complete()` | — | 立即完成整个序列 |
| `TweenSequence:Kill(complete: boolean)` | — | 销毁序列；`true` 表示先完成，`false` 表示保持当前状态结束 |
| `TweenSequence:SetOnComplete(onComplete: fun())` | `TweenSequence` | 设置整个序列完成回调并返回当前实例 |
| `TweenSequence:SetOnStepComplete(onStepComplete: fun())` | `TweenSequence` | 设置步骤完成回调并返回当前实例 |
| `TweenSequence:SetLoops(times: integer)` | `TweenSequence` | 设置循环次数并返回当前实例；**负数表示无限循环** |

### 9. ServerSignal

创建并向服务器发送信号。参数按服务器约定依次添加。

#### (1) 创建

| 函数 | 返回值 | 说明 |
|---|---|---|
| `game.ServerSignal(signalName: string)` | `ServerSignal` | 使用服务器约定的信号名称 `signalName` 创建服务器信号 |

#### (2) 方法

| 方法 | 返回值 | 说明 |
|---|---|---|
| `ServerSignal:AddParam(paramType: ParamType, paramValue: any)` | — | `paramType` 指定参数类型，`paramValue` 指定参数值 |
| `ServerSignal:SendSignal()` | — | 发送已构建的服务器信号 |
| `ServerSignal:AddInt(intValue: integer)` | — | 添加整数参数 |
| `ServerSignal:AddIntList(intListValue: integer[])` | — | 添加整数列表参数 |
| `ServerSignal:AddFloat(floatValue: number)` | — | 添加浮点数参数 |
| `ServerSignal:AddFloatList(floatListValue: number[])` | — | 添加浮点数列表参数 |
| `ServerSignal:AddString(stringValue: string)` | — | 添加字符串参数 |
| `ServerSignal:AddStringList(stringListValue: string[])` | — | 添加字符串列表参数 |
| `ServerSignal:AddVector3(vector3Value: table)` | — | 添加三维向量参数；传入以 x,y,z 为键，目标值为值组成的 table |
| `ServerSignal:AddVector3List(vector3ListValue: table[])` | — | 添加三维向量列表参数；传入以 x,y,z 为键，目标值为值组成的 table 列表 |
| `ServerSignal:AddBool(boolValue: boolean)` | — | 添加布尔值参数 |
| `ServerSignal:AddBoolList(boolListValue: boolean[])` | — | 添加布尔值列表参数 |
| `ServerSignal:AddGuid(guidValue: integer)` | — | 添加 GUID 参数 |
| `ServerSignal:AddGuidList(guidListValue: integer[])` | — | 添加 GUID 列表参数 |
| `ServerSignal:AddEntity(entityValue: integer)` | — | 添加实体参数 |
| `ServerSignal:AddEntityList(entityListValue: integer[])` | — | 添加实体列表参数 |
| `ServerSignal:AddPrefabId(prefabIdValue: integer)` | — | 添加元件 ID 参数 |
| `ServerSignal:AddPrefabIdList(prefabIdListValue: integer[])` | — | 添加元件 ID 列表参数 |
| `ServerSignal:AddConfigId(configIdValue: integer)` | — | 添加配置 ID 参数 |
| `ServerSignal:AddConfigIdList(configIdListValue: integer[])` | — | 添加配置 ID 列表参数 |

### 10. EnumItem

#### (1) 字段

| 字段 | 类型 | 访问 | 说明 |
|---|---|---|---|
| `Name` | `string` | **只读** | 枚举值名称 |
| `FullName` | `string` | **只读** | 枚举值完整名称 |
| `EnumType` | `string` | **只读** | 枚举类型名称 |

### 11. 枚举系统

#### (1) `Enum.EaseType`

缓动类型

| 枚举名 | 说明 |
|---|---|
| `Enum.EaseTypeLinear` | 线性 |
| `Enum.EaseTypeInSine` | 正弦缓入 |
| `Enum.EaseTypeOutSine` | 正弦缓出 |
| `Enum.EaseTypeInOutSine` | 正弦缓入缓出 |
| `Enum.EaseTypeInQuad` | 二次缓入 |
| `Enum.EaseTypeOutQuad` | 二次缓出 |
| `Enum.EaseTypeInOutQuad` | 二次缓入缓出 |
| `Enum.EaseTypeInCubic` | 三次缓入 |
| `Enum.EaseTypeOutCubic` | 三次缓出 |
| `Enum.EaseTypeInOutCubic` | 三次缓入缓出 |
| `Enum.EaseTypeInQuart` | 四次缓入 |
| `Enum.EaseTypeOutQuart` | 四次缓出 |
| `Enum.EaseTypeInOutQuart` | 四次缓入缓出 |
| `Enum.EaseTypeInQuint` | 五次缓入 |
| `Enum.EaseTypeOutQuint` | 五次缓出 |
| `Enum.EaseTypeInOutQuint` | 五次缓入缓出 |
| `Enum.EaseTypeInExpo` | 指数缓入 |
| `Enum.EaseTypeOutExpo` | 指数缓出 |
| `Enum.EaseTypeInOutExpo` | 指数缓入缓出 |
| `Enum.EaseTypeInCirc` | 圆形缓入 |
| `Enum.EaseTypeOutCirc` | 圆形缓出 |
| `Enum.EaseTypeInOutCirc` | 圆形缓入缓出 |
| `Enum.EaseTypeInBack` | 回弹缓入 |
| `Enum.EaseTypeOutBack` | 回弹缓出 |
| `Enum.EaseTypeInOutBack` | 回弹缓入缓出 |
| `Enum.EaseTypeInElastic` | 弹性缓入 |
| `Enum.EaseTypeOutElastic` | 弹性缓出 |
| `Enum.EaseTypeInOutElastic` | 弹性缓入缓出 |
| `Enum.EaseTypeInBounce` | 弹跳缓入 |
| `Enum.EaseTypeOutBounce` | 弹跳缓出 |
| `Enum.EaseTypeInOutBounce` | 弹跳缓入缓出 |

#### (2) `Enum.CustomVariableEntityType`

自定义变量实体类型

| 枚举名 | 说明 |
|---|---|
| `Enum.CustomVariableEntityTypeLevel` | 关卡 |
| `Enum.CustomVariableEntityTypePlayerSelf` | 玩家自身 |
| `Enum.CustomVariableEntityTypeAvatarSelf` | 角色自身 |

#### (3) `Enum.Device`

输入设备

| 枚举名 | 说明 |
|---|---|
| `Enum.DeviceKeyboardAndMouse` | 键鼠 |
| `Enum.DeviceMobile` | 移动端触屏 |
| `Enum.DeviceController` | 主机手柄 |
| `Enum.DeviceMobileController` | 移动端手柄 |

#### (4) `Enum.StageMode`

关卡模式

| 枚举名 | 说明 |
|---|---|
| `Enum.StageModeBeyond` | 超限模式 |
| `Enum.StageModeClassic` | 经典模式 |

#### (5) `Enum.LanguageType`

语言类型

| 枚举名 | 说明 |
|---|---|
| `Enum.LanguageTypeLanguageNone` | 未指定 |
| `Enum.LanguageTypeLanguageEng` | 英语 |
| `Enum.LanguageTypeLanguageChs` | 简体中文 |
| `Enum.LanguageTypeLanguageCht` | 繁体中文 |
| `Enum.LanguageTypeLanguageFra` | 法语 |
| `Enum.LanguageTypeLanguageDeu` | 德语 |
| `Enum.LanguageTypeLanguageSpa` | 西班牙语 |
| `Enum.LanguageTypeLanguagePor` | 葡萄牙语 |
| `Enum.LanguageTypeLanguageRus` | 俄语 |
| `Enum.LanguageTypeLanguageJpn` | 日语 |
| `Enum.LanguageTypeLanguageKor` | 韩语 |
| `Enum.LanguageTypeLanguageTha` | 泰语 |
| `Enum.LanguageTypeLanguageVie` | 越南语 |
| `Enum.LanguageTypeLanguageInd` | 印度尼西亚语 |
| `Enum.LanguageTypeLanguageTur` | 土耳其语 |
| `Enum.LanguageTypeLanguageIta` | 意大利语 |

#### (6) `Enum.ParamType`

服务器信号参数类型

| 枚举名 | 说明 |
|---|---|
| `Enum.ParamTypeEntity` | 实体 |
| `Enum.ParamTypeEntityList` | 实体列表 |
| `Enum.ParamTypeInt` | 整数 |
| `Enum.ParamTypeIntList` | 整数列表 |
| `Enum.ParamTypeBool` | 布尔值 |
| `Enum.ParamTypeBoolList` | 布尔值列表 |
| `Enum.ParamTypeFloat` | 浮点数 |
| `Enum.ParamTypeFloatList` | 浮点数列表 |
| `Enum.ParamTypeString` | 字符串 |
| `Enum.ParamTypeStringList` | 字符串列表 |
| `Enum.ParamTypeVector3` | 三维向量 |
| `Enum.ParamTypeVector3List` | 三维向量列表 |
| `Enum.ParamTypeGuid` | GUID |
| `Enum.ParamTypeGuidList` | GUID 列表 |
| `Enum.ParamTypeConfigId` | 配置 ID |
| `Enum.ParamTypePrefabId` | 元件 ID |
| `Enum.ParamTypeConfigIdList` | 配置 ID 列表 |
| `Enum.ParamTypePrefabIdList` | 元件 ID 列表 |

#### (7) `Enum.CursorEventType`

光标事件类型

| 枚举名 | 说明 |
|---|---|
| `Enum.CursorEventTypeCursorDown` | 光标按下 |
| `Enum.CursorEventTypeCursorUp` | 光标抬起 |
| `Enum.CursorEventTypeCursorEnter` | 光标进入检测区域 |
| `Enum.CursorEventTypeCursorExit` | 光标离开检测区域 |
| `Enum.CursorEventTypeCursorDrag` | 光标拖拽 |
| `Enum.CursorEventTypeCursorBeginDrag` | 开始拖拽 |
| `Enum.CursorEventTypeCursorEndDrag` | 结束拖拽 |
| `Enum.CursorEventTypeCursorClick` | 完成点击 |

#### (8) `Enum.ScrollDirection`

滚动方向

| 枚举名 | 说明 |
|---|---|
| `Enum.ScrollDirectionHorizontal` | 水平滚动 |
| `Enum.ScrollDirectionVertical` | 垂直滚动 |

#### (9) `Enum.ScrollLayoutConstraint`

滚动布局约束

| 枚举名 | 说明 |
|---|---|
| `Enum.ScrollLayoutConstraintAutoWrap` | 自动换行布局 |
| `Enum.ScrollLayoutConstraintFixed` | 固定行数或列数布局 |

#### (10) `Enum.ScrollAlignType`

滚动对齐方式

| 枚举名 | 说明 |
|---|---|
| `Enum.ScrollAlignTypeBottom` | 底部对齐 |
| `Enum.ScrollAlignTypeCenter` | 居中对齐 |
| `Enum.ScrollAlignTypeTop` | 顶部对齐 |

#### (11) `Enum.ControllerNavigationDir`

手柄导航方向

| 枚举名 | 说明 |
|---|---|
| `Enum.ControllerNavigationDirUp` | 向上 |
| `Enum.ControllerNavigationDirDown` | 向下 |
| `Enum.ControllerNavigationDirLeft` | 向左 |
| `Enum.ControllerNavigationDirRight` | 向右 |

#### (12) `Enum.ControllerNavigationEventType`

手柄导航事件类型

| 枚举名 | 说明 |
|---|---|
| `Enum.ControllerNavigationEventTypeConfirm` | 确认 |
| `Enum.ControllerNavigationEventTypeCancel` | 取消 |
| `Enum.ControllerNavigationEventTypeFocus` | 进入聚焦 |
| `Enum.ControllerNavigationEventTypeLostFocus` | 退出聚焦 |
| `Enum.ControllerNavigationEventTypeRightStickUp` | 右摇杆向上 |
| `Enum.ControllerNavigationEventTypeRightStickDown` | 右摇杆向下 |
| `Enum.ControllerNavigationEventTypeRightStickRight` | 右摇杆向右 |
| `Enum.ControllerNavigationEventTypeRightStickLeft` | 右摇杆向左 |
| `Enum.ControllerNavigationEventTypeLeftStickUp` | 左摇杆向上 |
| `Enum.ControllerNavigationEventTypeLeftStickDown` | 左摇杆向下 |
| `Enum.ControllerNavigationEventTypeLeftStickRight` | 左摇杆向右 |
| `Enum.ControllerNavigationEventTypeLeftStickLeft` | 左摇杆向左 |

#### (13) `Enum.ControllerNavigationMode`

手柄导航模式

| 枚举名 | 说明 |
|---|---|
| `Enum.ControllerNavigationModeNone` | 无导航 |
| `Enum.ControllerNavigationModeNearestControl` | 导航至最近控件 |
| `Enum.ControllerNavigationModeSpecified` | 导航至指定控件 |

#### (14) `Enum.TextHorizontalAlignment`

文本水平对齐

| 枚举名 | 说明 |
|---|---|
| `Enum.TextHorizontalAlignmentLeft` | 左对齐 |
| `Enum.TextHorizontalAlignmentMiddle` | 水平居中 |
| `Enum.TextHorizontalAlignmentRight` | 右对齐 |

#### (15) `Enum.TextVerticalAlignment`

文本垂直对齐

| 枚举名 | 说明 |
|---|---|
| `Enum.TextVerticalAlignmentTop` | 顶部对齐 |
| `Enum.TextVerticalAlignmentMiddle` | 垂直居中 |
| `Enum.TextVerticalAlignmentBottom` | 底部对齐 |

#### (16) `Enum.ImageType`

图片类型

| 枚举名 | 说明 |
|---|---|
| `Enum.ImageTypeBasic` | 基础 |
| `Enum.ImageTypeStretch` | 拉伸 |

#### (17) `Enum.ImageSource`

图片来源

| 枚举名 | 说明 |
|---|---|
| `Enum.ImageSourceStaticReference` | 静态引用 |
| `Enum.ImageSourceItem` | 道具 |
| `Enum.ImageSourceEquipment` | 装备 |
| `Enum.ImageSourceSkill` | 技能 |
| `Enum.ImageSourceUnitStatus` | 单位状态 |
| `Enum.ImageSourceFaction` | 阵营 |
| `Enum.ImageSourceCurrency` | 货币 |
| `Enum.ImageSourcePrefab` | 元件 |

#### (18) `Enum.ImageFillType`

图片填充方式

| 枚举名 | 说明 |
|---|---|
| `Enum.ImageFillTypeUnused` | 不使用填充 |
| `Enum.ImageFillTypeHorizontal` | 水平 |
| `Enum.ImageFillTypeVertical` | 垂直 |
| `Enum.ImageFillTypeRadial90` | 90度环绕 |
| `Enum.ImageFillTypeRadial180` | 180度环绕 |
| `Enum.ImageFillTypeRadial360` | 360度环绕 |

#### (19) `Enum.ImageFillHorizontalType`

水平填充方向

| 枚举名 | 说明 |
|---|---|
| `Enum.ImageFillHorizontalTypeLeft` | 从左侧开始 |
| `Enum.ImageFillHorizontalTypeRight` | 从右侧开始 |

#### (20) `Enum.ImageFillVerticalType`

垂直填充方向

| 枚举名 | 说明 |
|---|---|
| `Enum.ImageFillVerticalTypeBottom` | 从底部开始 |
| `Enum.ImageFillVerticalTypeTop` | 从顶部开始 |

#### (21) `Enum.ImageFillRadial90Type`

90度环绕起点

| 枚举名 | 说明 |
|---|---|
| `Enum.ImageFillRadial90TypeBottomLeft` | 左下 |
| `Enum.ImageFillRadial90TypeTopLeft` | 左上 |
| `Enum.ImageFillRadial90TypeTopRight` | 右上 |
| `Enum.ImageFillRadial90TypeBottomRight` | 右下 |

#### (22) `Enum.ImageFillRadialType`

180/360度环绕起点

| 枚举名 | 说明 |
|---|---|
| `Enum.ImageFillRadialTypeBottom` | 底部 |
| `Enum.ImageFillRadialTypeLeft` | 左侧 |
| `Enum.ImageFillRadialTypeTop` | 顶部 |
| `Enum.ImageFillRadialTypeRight` | 右侧 |

#### (23) `Enum.ImageMaskSoftEdgeMode`

边缘羽化模式

| 枚举名 | 说明 |
|---|---|
| `Enum.ImageMaskSoftEdgeModePercentage` | 按比例设置边缘羽化 |
| `Enum.ImageMaskSoftEdgeModePixel` | 按像素设置边缘羽化 |

#### (24) `Enum.UIAnimationLayer`

界面动效层级

| 枚举名 | 说明 |
|---|---|
| `Enum.UIAnimationLayerAboveAllControls` | 所有控件之上 |
| `Enum.UIAnimationLayerBelowAllControls` | 所有控件之下 |

### 12. 客户端控件

#### (1) 继承关系

所有具体控件都继承 `ClientUIBaseControl`：

| 类型 | 控件名 |
|---|---|
| `ClientUIImageControl` | 图片 |
| `ClientUITextBoxControl` | 文本框 |
| `ClientUITextWindowControl` | 文本视窗 |
| `ClientUIPresetButtonControl` | 预设按钮 |
| `ClientUICursorEventAreaControl` | 光标检测区域 |
| `ClientUIGridScrollerControl` | 网格视窗 |
| `ClientUIKeyHintControl` | 按键提示 |
| `ClientUIAnimationControl` | 界面动效 |
| `ClientUIFullscreenAnimationControl` | 全屏动效 |
| `ClientUIContainerControl` | 容器节点 |
| `ClientUIReferenceControl` | 模板引用控件 |

### 13. ClientUIBaseControl

客户端控件基类，提供层级、布局、脚本访问、输入监听与手柄导航。

#### (1) 字段

| 字段 | 类型 | 访问 | 说明 |
|---|---|---|---|
| `alive` | `boolean` | 只读 | 控件是否存活 |
| `id` | `integer` | 只读 | 运行时 ID |
| `prefabIndex` | `integer` | 只读 | 控件模板索引 |
| `active` | `boolean` | 只读 | 激活状态；`true` 时控件可见且挂载脚本逻辑运行，`false` 时控件不可见且脚本逻辑停止运行。默认为 `false`。 |
| `activeInHierarchy` | `boolean` | 只读 | 计入全部父级后的实际激活状态 |
| `visible` | `boolean` | 只读 | **仅控制可见性，不改变激活状态或脚本逻辑运行状态** |
| `name` | `string` | 读写 | 控件名称 |
| `parent` | `ClientUIBaseControl` | 读写 | 父控件 |
| `anchoredPositionX, anchoredPositionY` | `number` | 读写 | 位置、Tweenable |
| `sizeDeltaX, sizeDeltaY` | `number` | 读写 | 大小差异、Tweenable |
| `anchorMinX, anchorMinY` | `number` | 读写 | 最小锚点、Tweenable |
| `anchorMaxX, anchorMaxY` | `number` | 读写 | 最大锚点、Tweenable |
| `pivotX, pivotY` | `number` | 读写 | 中心、Tweenable |
| `localScaleX, localScaleY, localScaleZ` | `number` | 读写 | 缩放、Tweenable |
| `localRotationX, localRotationY, localRotationZ` | `number` | 读写 | 旋转、Tweenable |
| `canControllerFocus` | `boolean` | 读写 | 可被手柄导航摇杆聚焦 |

#### (2) 层级与可见性

> ⚠️ 复用列表生成的列表项**不保证同级排序结果稳定**。

| 方法 | 返回值 | 说明 |
|---|---|---|
| `GetChildren()` | `ClientUIBaseControl[]` | 获取直接子控件 |
| `GetChild(name)` | `ClientUIBaseControl` | 获取当前控件中名称为 `name` 的直接子控件 |
| `FindChild(path)` | `ClientUIBaseControl` | 按路径查找子控件 |
| `SetActive(active)` | — | 设置激活状态；关闭后控件不可见且挂载脚本逻辑停止运行 |
| `SetVisible(visible)` | — | **仅设置可见性**，不改变激活状态，也不停止脚本逻辑 |
| `GetSiblingIndex()` | `integer` | 获取同级排序索引；返回值范围为 0 到父控件的子控件数量减一 |
| `SetSiblingIndex(index)` | `boolean` | 设置同级排序索引；`index` 范围为 0 到父控件的子控件数量减一；数值越大通常越靠后、显示越靠上 |
| `SetAsFirstSibling()` | `boolean` | 移到同级首位 |
| `SetAsLastSibling()` | `boolean` | 移到同级末位 |

#### (3) 布局与变换

父子层级中的位移、缩放、可见性、Alpha、镜像与裁剪效果由运行时 UI 层级共同决定；使用组合布局时应验证实际显示结果。

| 方法 | 返回值 | 说明 |
|---|---|---|
| `GetAnchoredPosition()` | `x, y` | 无父层级时，以画布左下为原点获取位置；存在父层级时，获取与父层级中心的相对偏移 |
| `SetAnchoredPosition(x, y)` | — | 无父层级时，以画布左下为原点设置位置；存在父层级时，设置与父层级中心的相对偏移 |
| `GetSizeDelta()` | `x, y` | 获取大小 |
| `SetSizeDelta(x, y)` | — | 设置大小 |
| `GetAnchorMin()` | `x, y` | 获取最小锚点 |
| `SetAnchorMin(x, y)` | — | 设置最小锚点 |
| `GetAnchorMax()` | `x, y` | 获取最大锚点 |
| `SetAnchorMax(x, y)` | — | 设置最大锚点 |
| `GetPivot()` | `x, y` | 获取中心 |
| `SetPivot(x, y)` | — | 设置中心 |
| `GetLocalScale()` | `x, y, z` | 获取缩放 |
| `SetLocalScale(x, y, z)` | — | 设置缩放 |
| `GetLocalRotation()` | `x, y, z` | 获取旋转 |
| `SetLocalRotation(x, y, z)` | — | 设置旋转 |

#### (4) 脚本访问

> ⚠️ 返回的脚本实例可能因销毁而不再存活，使用前检查 `script.alive`。

| 方法 | 返回值 | 说明 |
|---|---|---|
| `GetScriptByPath(scriptPath)` | `Script` | 按路径获取挂载脚本 |
| `GetScript(scriptMappingId)` | `Script` | 按脚本映射 ID 获取脚本 |
| `GetScripts()` | `Script[]` | 获取控件上全部脚本 |

#### (5) 键鼠/手柄按键事件

| 方法 | 返回值 | 说明 |
|---|---|---|
| `AddKeyEventListener(eventType, callback)` | — | 注册指定按键事件监听；回调返回 `boolean`；移除单个监听时需保留该回调引用。同一个容器中，如果交互按键事件被 Lua 回调响应并标记为已处理，容器内的其他按键不会也响应此次按键事件 |
| `RemoveKeyEventListener(eventType, callback)` | — | 移除指定按键事件和回调的监听；回调必须与注册时的引用相同 |
| `RemoveKeyEventListeners(eventType)` | — | 移除指定按键事件的全部监听 |
| `RemoveAllKeyEventListeners()` | — | 移除全部按键事件监听 |

#### (6) 手柄导航事件

| 方法 | 返回值 | 说明 |
|---|---|---|
| `AddNavigationEventListener(eventType, callback)` | — | 注册指定手柄导航事件监听 |
| `RemoveNavigationEventListener(eventType, callback)` | — | 移除指定手柄导航事件和回调的监听 |
| `RemoveNavigationEventListeners(eventType)` | — | 移除指定手柄导航事件的全部监听 |
| `RemoveAllNavigationEventListeners()` | — | 移除全部手柄导航事件监听 |

#### (7) 手柄导航配置

| 方法 | 返回值 | 说明 |
|---|---|---|
| `SetControllerNavigation(navigationDir, navigationMode, navigationTarget)` | — | 设置指定方向的导航模式和目标控件；目标可以为 `nil` |
| `GetControllerNavigation(navigationDir)` | `navigationMode, navigationTarget` | 获取指定方向的导航模式和目标控件 |

### 14. ClientUIImageControl

图片控件，用于显示图片并控制颜色、遮罩与填充效果。

#### (1) 字段

| 字段 | 类型 | 访问 | 说明 |
|---|---|---|---|
| `imageSource` | `ImageSource` | 只读 | 图片来源 |
| `imageId` | `integer` | 只读 | 图片 ID |
| `imageColor` | `ColorValue` | 读写 | 图片颜色、Tweenable |
| `imageType` | `ImageType` | 读写 | 基础或拉伸类型 |
| `enableMask` | `boolean` | 读写 | 是否启用遮罩 |
| `enableSoftEdge` | `boolean` | 读写 | 是否启用边缘羽化 |
| `softEdgeMode` | `ImageMaskSoftEdgeMode` | 读写 | 边缘羽化模式 |
| `softEdgeWidthX` | `number` | 读写 | 水平边缘羽化宽度、Tweenable |
| `softEdgeWidthY` | `number` | 读写 | 垂直边缘羽化宽度、Tweenable |
| `horizontalSoftRange` | `number` | 读写 | 水平边缘羽化范围、Tweenable |
| `verticalSoftRange` | `number` | 读写 | 垂直边缘羽化范围、Tweenable |
| `reverseMaskArea` | `boolean` | 读写 | 是否反转遮罩区域 |
| `fillType` | `ImageFillType` | 读写 | 当前填充方式 |
| `fillHorizontalType` | `ImageFillHorizontalType` | 读写 | 水平填充方向 |
| `fillVerticalType` | `ImageFillVerticalType` | 读写 | 垂直填充方向 |
| `fillRadial90Type` | `ImageFillRadial90Type` | 读写 | 90度环绕起点 |
| `fillRadialType` | `ImageFillRadialType` | 读写 | 180度环绕和 360度环绕的起点 |
| `fillAmount` | `number` | 读写 | 进度、Tweenable |

#### (2) 方法

| 方法 | 返回值 | 说明 |
|---|---|---|
| `SetImage(imageSource, imageId)` | — | 设置图片来源与图片 ID |
| `SetSoftEdgeWidth(widthX, widthY)` | — | 设置水平与垂直边缘羽化宽度 |
| `SetFillUnused()` | — | 设置为不使用填充 |
| `SetFillHorizontal(fillHorizontalType, fillAmount)` | — | 设置水平填充 |
| `SetFillVertical(fillVerticalType, fillAmount)` | — | 设置垂直填充 |
| `SetFillRadial90(fillRadial90Type, fillAmount)` | — | 设置 90度环绕填充 |
| `SetFillRadial180(fillRadialType, fillAmount)` | — | 设置 180度环绕填充 |
| `SetFillRadial360(fillRadialType, fillAmount)` | — | 设置 360度环绕填充 |

### 15. ClientUITextBoxControl

文本框控件，用于显示普通文本。

#### (1) 字段

| 字段 | 类型 | 访问 | 说明 |
|---|---|---|---|
| `text` | `string` | 读写 | 显示文本 |
| `fontSize` | `integer` | 读写 | 字号，Tweenable |
| `fontColor` | `ColorValue` | 读写 | 字色，Tweenable |
| `bgColor` | `ColorValue` | 读写 | 背景色，Tweenable |
| `enableOutline` | `boolean` | 读写 | 是否启用描边 |
| `outlineColor` | `ColorValue` | 读写 | 描边色，Tweenable |
| `horizontalAlignment` | `TextHorizontalAlignment` | 读写 | 水平对齐 |
| `verticalAlignment` | `TextVerticalAlignment` | 读写 | 垂直对齐 |
| `adaptiveFontSize` | `boolean` | 读写 | 字号自适应 |
| `minimumFontSize` | `integer` | 读写 | 字号自适应的最小字号，Tweenable |

### 16. ClientUITextWindowControl

文本视窗控件，用于显示可滚动的文本。

#### (1) 字段

| 字段 | 类型 | 访问 | 说明 |
|---|---|---|---|
| `interactable` | `boolean` | 读写 | 是否可交互；与 `showScrollBar` 同时为 `false` 时，手柄无法滚动文本视窗 |
| `showScrollBar` | `boolean` | 读写 | 是否显示滚动条 |
| `text` | `string` | 读写 | 显示文本 |
| `fontSize` | `integer` | 读写 | 字号，Tweenable |
| `fontColor` | `ColorValue` | 读写 | 字色，Tweenable |
| `bgColor` | `ColorValue` | 读写 | 背景色，Tweenable |
| `enableOutline` | `boolean` | 读写 | 是否启用描边 |
| `outlineColor` | `ColorValue` | 读写 | 描边色，Tweenable |
| `horizontalAlignment` | `TextHorizontalAlignment` | 读写 | 水平对齐 |
| `verticalAlignment` | `TextVerticalAlignment` | 读写 | 垂直对齐 |
| `adaptiveFontSize` | `boolean` | 读写 | 字号自适应 |
| `minimumFontSize` | `integer` | 读写 | 字号自适应的最小字号，Tweenable |

### 17. ClientUIPresetButtonControl

预设按钮控件，提供按钮交互与光标事件监听。

#### (1) 字段

| 字段 | 类型 | 访问 | 说明 |
|---|---|---|---|
| `interactable` | `boolean` | 读写 | 是否可交互 |
| `clickAudioId` | `integer` | 读写 | 点击音效 ID |
| `raycastTarget` | `boolean` | 读写 | 可被光标射线检测 |

#### (2) 方法

| 方法 | 返回值 | 说明 |
|---|---|---|
| `AddCursorEventListener(eventType, callback)` | — | 注册指定光标事件监听；回调接收 `CursorEventData` |
| `RemoveCursorEventListener(eventType, callback)` | — | 移除指定光标事件和回调的监听 |
| `RemoveCursorEventListeners(eventType)` | — | 移除指定光标事件的全部监听 |
| `RemoveAllCursorEventListeners()` | — | 移除全部光标事件监听 |
| `SimulateCursorClick()` | — | 按顺序模拟 `CursorDown`、`CursorUp` 与 `CursorClick` |

### 18. ClientUICursorEventAreaControl

光标检测区域控件，检测该控件区域内的光标事件。

#### (1) 字段

| 字段 | 类型 | 访问 | 说明 |
|---|---|---|---|
| `raycastTarget` | `boolean` | 读写 | 可被光标射线检测 |

#### (2) 方法

| 方法 | 返回值 | 说明 |
|---|---|---|
| `AddCursorEventListener(eventType, callback)` | — | 注册指定光标事件监听；回调接收 `CursorEventData` |
| `RemoveCursorEventListener(eventType, callback)` | — | 移除指定光标事件和回调的监听 |
| `RemoveCursorEventListeners(eventType)` | — | 移除指定光标事件的全部监听 |
| `RemoveAllCursorEventListeners()` | — | 移除全部光标事件监听 |
| `SimulateCursorClick()` | — | 按顺序模拟 `CursorDown`、`CursorUp` 与 `CursorClick` |

### 19. CursorEventData

#### (1) 字段

| 字段 | 类型 | 访问 | 说明 |
|---|---|---|---|
| `dragging` | `boolean` | 只读 | 当前是否在拖拽 |
| `touchId` | `integer` | 只读 | 触点 ID |

#### (2) 方法

| 方法 | 返回值 | 说明 |
|---|---|---|
| `CursorEventData:GetUIPos()` | `x, y: number` | 以画布左下角为原点，获取当前屏幕 UI 坐标。坐标比例和布局坐标一致 |
| `CursorEventData:GetPressUIPos()` | `x, y: number` | 获取按下时的屏幕 UI 坐标 |
| `CursorEventData:GetUIPosDelta()` | `x, y: number` | 获取本次事件的屏幕 UI 位移 |

### 20. ClientUIGridScrollerControl

网格视窗控件，用于显示和滚动复用列表项。

#### (1) 字段

| 字段 | 类型 | 访问 | 说明 |
|---|---|---|---|
| `itemCount` | `integer` | 只读 | 列表项数量 |
| `itemPrefabIndex` | `integer` | 读写 | 列表项控件模板索引 |
| `raycastTarget` | `boolean` | 读写 | 可被光标射线检测 |
| `showScrollBar` | `boolean` | 读写 | 是否显示滚动条 |
| `interactable` | `boolean` | 读写 | 是否可交互 |
| `scrollDirection` | `ScrollDirection` | 只读 | 滚动方向 |
| `layoutConstraint` | `ScrollLayoutConstraint` | 只读 | 列表项布局约束 |
| `layoutConstraintFixedCount` | `number` | 只读 | 固定布局时每行或每列的列表项数量 |
| `scrollProgress` | `number` | 读写 | 滚动进度、Tweenable |

#### (2) 方法

> 列表项索引以运行时传入和返回的 `index` 为准。

| 方法 | 返回值 | 说明 |
|---|---|---|
| `RefreshItems(itemCount, refreshCallback)` | — | 刷新列表项并逐项调用回调；刷新回调形式为 `fun(control: ClientUIBaseControl, index: integer)`，参数依次为当前列表项控件和列表项索引 |
| `GetItemIndex(control)` | `integer` | 获取列表项控件的索引 |
| `GetItemSize()` | `x, y: number` | 获取列表项宽度与高度 |
| `GetItemSpacing()` | `x, y: number` | 获取列表项的水平与垂直间距 |
| `GetPadding()` | `top, bottom, left, right: number` | 获取内容区域的上、下、左、右内边距 |
| `ScrollToItemAt(index, scrollAlignType)` | — | 滚动到索引为 `index` 的列表项，并按 `scrollAlignType` 对齐 |
| `GetContentLength()` | `number` | 获取滚动内容在滚动方向上的长度 |

### 21. ClientUIKeyHintControl

按键提示控件，根据当前输入设备显示对应按键。

#### (1) 字段

| 字段 | 类型 | 访问 | 说明 |
|---|---|---|---|
| `keyboardKeyCode` | `KeyboardKeyCode` | 读写 | 键鼠按键枚举值 |
| `controllerKeyCode` | `ControllerKeyCode` | 读写 | 手柄按键枚举值 |

### 22. ClientUIAnimationControl

界面动效控件，用于播放或停止已配置的动效。

#### (1) 字段

| 字段 | 类型 | 访问 | 说明 |
|---|---|---|---|
| `animationId` | `integer` | 读写 | 动效 ID |
| `playSoundEffect` | `boolean` | 读写 | 是否播放动效音效 |
| `layer` | `UIAnimationLayer` | 读写 | 动效层级 |

#### (2) 方法

| 方法 | 返回值 | 说明 |
|---|---|---|
| `PlayAnimation()` | — | 播放界面动效 |
| `StopAnimation()` | — | 停止界面动效 |

### 23. ClientUIFullscreenAnimationControl

全屏动效控件，用于显示覆盖界面的已配置动效。

#### (1) 字段

| 字段 | 类型 | 访问 | 说明 |
|---|---|---|---|
| `animationId` | `integer` | 读写 | 动效 ID |
| `playSoundEffect` | `boolean` | 读写 | 是否播放动效音效 |

### 24. ClientUIContainerControl

容器节点控件，用于组织子控件。

#### (1) 字段

| 字段 | 类型 | 访问 | 说明 |
|---|---|---|---|
| `isolateNavigation` | `boolean` | 读写 | 是否隔离手柄导航 |
| `disableKeyEventPassthrough` | `boolean` | 读写 | 是否屏蔽按键事件穿透 |
| `disableCursorEventPassthrough` | `boolean` | 读写 | 是否屏蔽区域内点击事件穿透 |
| `showCursor` | `boolean` | 读写 | 是否显示常驻光标；**CursorEvent 相关方法都需设置该参数为真后才可正常使用** |

### 25. ClientUIReferenceControl

模板引用控件，用于引用已配置的控件模板。

#### (1) 字段

| 字段 | 类型 | 访问 | 说明 |
|---|---|---|---|
| `referencedPrefabIndex` | `integer` | 只读 | 引用控件模板索引 |

### 26. 按键输入

#### (1) `Enum.KeyboardKeyCode`

| 枚举名 | 说明 | 默认物理键 |
|---|---|---|
| `Enum.KeyboardKeyCodeCraftspersonKey1` | 奇匠按键1 | `1` |
| `Enum.KeyboardKeyCodeCraftspersonKey2` | 奇匠按键2 | `2` |
| `Enum.KeyboardKeyCodeCraftspersonKey3` | 奇匠按键3 | `3` |
| `Enum.KeyboardKeyCodeCraftspersonKey4` | 奇匠按键4 | `4` |
| `Enum.KeyboardKeyCodeCraftspersonKey5` | 奇匠按键5 | `5` |
| `Enum.KeyboardKeyCodeCraftspersonKey6` | 奇匠按键6 | `6` |
| `Enum.KeyboardKeyCodeCraftspersonKey7` | 奇匠按键7 | `7` |
| `Enum.KeyboardKeyCodeCraftspersonKey8` | 奇匠按键8 | `8` |
| `Enum.KeyboardKeyCodeCraftspersonKey9` | 奇匠按键9 | `9` |
| `Enum.KeyboardKeyCodeCraftspersonKey10` | 奇匠按键10 | `0` |
| `Enum.KeyboardKeyCodeCraftspersonKey11` | 奇匠按键11 | `U` |
| `Enum.KeyboardKeyCodeCraftspersonKey12` | 奇匠按键12 | `Z` |
| `Enum.KeyboardKeyCodeCraftspersonKey13` | 奇匠按键13 | `Y` |
| `Enum.KeyboardKeyCodeCraftspersonKey14` | 奇匠按键14 | `G` |
| `Enum.KeyboardKeyCodeCraftspersonKey15` | 奇匠按键15 | `H` |
| `Enum.KeyboardKeyCodeCraftspersonKey16` | 奇匠按键16 | `I` |
| `Enum.KeyboardKeyCodeCraftspersonKey17` | 奇匠按键17 | `O` |
| `Enum.KeyboardKeyCodeCraftspersonKey18` | 奇匠按键18 | `P` |
| `Enum.KeyboardKeyCodeCraftspersonKey19` | 奇匠按键19 | `J` |
| `Enum.KeyboardKeyCodeCraftspersonKey20` | 奇匠按键20 | `K` |
| `Enum.KeyboardKeyCodeCraftspersonKey21` | 奇匠按键21 | `L` |
| `Enum.KeyboardKeyCodeCraftspersonKey22` | 奇匠按键22 | `V` |
| `Enum.KeyboardKeyCodeCraftspersonKey23` | 奇匠按键23 | `F5` |
| `Enum.KeyboardKeyCodeCraftspersonKey24` | 奇匠按键24 | `F6` |
| `Enum.KeyboardKeyCodeCraftspersonKey25` | 奇匠按键25 | `F7` |
| `Enum.KeyboardKeyCodeCraftspersonKey26` | 奇匠按键26 | `F8` |
| `Enum.KeyboardKeyCodeCraftspersonKey27` | 奇匠按键27 | `F9` |
| `Enum.KeyboardKeyCodeCraftspersonKey28` | 奇匠按键28 | `F10` |
| `Enum.KeyboardKeyCodeCraftspersonKey29` | 奇匠按键29 | ``` |
| `Enum.KeyboardKeyCodeCraftspersonKey30` | 奇匠按键30 | `-` |
| `Enum.KeyboardKeyCodeCraftspersonKey31` | 奇匠按键31 | `=` |
| `Enum.KeyboardKeyCodeCraftspersonKey32` | 奇匠按键32 | `[` |
| `Enum.KeyboardKeyCodeCraftspersonKey33` | 奇匠按键33 | `,` |
| `Enum.KeyboardKeyCodeCraftspersonKey34` | 奇匠按键34 | `.` |
| `Enum.KeyboardKeyCodeCraftspersonKey35` | 奇匠按键35 | `/` |
| `Enum.KeyboardKeyCodeCraftspersonKey36` | 奇匠按键36 | `↑` |
| `Enum.KeyboardKeyCodeCraftspersonKey37` | 奇匠按键37 | `↓` |
| `Enum.KeyboardKeyCodeCraftspersonKey38` | 奇匠按键38 | `←` |
| `Enum.KeyboardKeyCodeCraftspersonKey39` | 奇匠按键39 | `→` |
| `Enum.KeyboardKeyCodeCraftspersonKey40` | 奇匠按键40 | `右Ctrl` |
| `Enum.KeyboardKeyCodeCraftspersonKey41` | 奇匠按键41 | `右Shift` |
| `Enum.KeyboardKeyCodeCraftspersonKey42` | 奇匠按键42 | `Backspace` |
| `Enum.KeyboardKeyCodeCraftspersonKey43` | 奇匠按键43 | `CapsLock` |
| `Enum.KeyboardKeyCodeMoveForwardKey` | 向前移动 | `W` |
| `Enum.KeyboardKeyCodeMoveBackwardKey` | 向后移动 | `S` |
| `Enum.KeyboardKeyCodeMoveLeftKey` | 向左移动 | `A` |
| `Enum.KeyboardKeyCodeMoveRightKey` | 向右移动 | `D` |
| `Enum.KeyboardKeyCodeSwitchToWalkOrRunKey` | 切换行走/奔跑状态 | `左Ctrl` |
| `Enum.KeyboardKeyCodeSprintKey` | 冲刺 | `鼠标右键` |
| `Enum.KeyboardKeyCodeJumpKey` | 跳跃 | `Space` |
| `Enum.KeyboardKeyCodeDropKey` | 落下 | `X` |
| `Enum.KeyboardKeyCodeOpenShortcutWheelKey` | 呼出快捷轮盘 | `Tab` |
| `Enum.KeyboardKeyCodeInteractKey` | 拾取/交互 | `F` |
| `Enum.KeyboardKeyCodeNormalAttackKey` | 普通攻击 | `鼠标左键` |
| `Enum.KeyboardKeyCodeCharacterSkill1Key` | 角色技能1 | `E` |
| `Enum.KeyboardKeyCodeCharacterSkill2Key` | 角色技能2 | `Q` |
| `Enum.KeyboardKeyCodeCharacterSkill3Key` | 角色技能3 | `R` |
| `Enum.KeyboardKeyCodeCharacterSkill4Key` | 角色技能4 | `T` |
| `Enum.KeyboardKeyCodeNone` | 无 | `无` |

#### (2) `Enum.ControllerKeyCode`

| 枚举名 | 说明 | 默认物理键 |
|---|---|---|
| `Enum.ControllerKeyCodeCraftspersonKey1` | 奇匠按键1 | `十字键左` |
| `Enum.ControllerKeyCodeCraftspersonKey2` | 奇匠按键2 | `十字键下` |
| `Enum.ControllerKeyCodeCraftspersonKey3` | 奇匠按键3 | `LT` |
| `Enum.ControllerKeyCodeCraftspersonKey4` | 奇匠按键4 | `LB + Y` |
| `Enum.ControllerKeyCodeCraftspersonKey5` | 奇匠按键5 | `LB + X` |
| `Enum.ControllerKeyCodeCraftspersonKey6` | 奇匠按键6 | `LB + A` |
| `Enum.ControllerKeyCodeCraftspersonKey7` | 奇匠按键7 | `LB + 十字键上` |
| `Enum.ControllerKeyCodeCraftspersonKey8` | 奇匠按键8 | `LB + 十字键右` |
| `Enum.ControllerKeyCodeCraftspersonKey9` | 奇匠按键9 | `LB + 十字键左` |
| `Enum.ControllerKeyCodeCraftspersonKey10` | 奇匠按键10 | `LB + 十字键下` |
| `Enum.ControllerKeyCodeCraftspersonKey11` | 奇匠按键11 | `LB + RB` |
| `Enum.ControllerKeyCodeCraftspersonKey12` | 奇匠按键12 | `LB + LT` |
| `Enum.ControllerKeyCodeCraftspersonKey13` | 奇匠按键13 | `LB + RT` |
| `Enum.ControllerKeyCodeCraftspersonKey14` | 奇匠按键14 | `LB + LS(按下)` |
| `Enum.ControllerKeyCodeSprintKey` | 冲刺 | `RB` |
| `Enum.ControllerKeyCodeJumpKey` | 跳跃 | `A` |
| `Enum.ControllerKeyCodeInteractKey` | 拾取/交互 | `X` |
| `Enum.ControllerKeyCodeNormalAttackKey` | 普通攻击 | `B` |
| `Enum.ControllerKeyCodeCharacterSkill1Key` | 角色技能1 | `RT` |
| `Enum.ControllerKeyCodeCharacterSkill2Key` | 角色技能2 | `Y` |
| `Enum.ControllerKeyCodeCharacterSkill3Key` | 角色技能3 | `十字键上` |
| `Enum.ControllerKeyCodeCharacterSkill4Key` | 角色技能4 | `十字键右` |
| `Enum.ControllerKeyCodeMenuConfirmKey` | 菜单确认 | `—（由手柄导航配置决定）` |
| `Enum.ControllerKeyCodeMenuBackKey` | 菜单返回 | `—（由手柄导航配置决定）` |
| `Enum.ControllerKeyCodeNone` | 无 | `无` |

#### (3) `Enum.KeyEventType`

键鼠事件枚举名为 `Keyboard<Key>Down` / `Keyboard<Key>Up`，手柄事件枚举名为 `Controller<Key>Down` / `Controller<Key>Up`。

<details>
<summary>展开全部按键事件枚举（共 164 项）</summary>

| 枚举名 | 说明 |
|---|---|
| `Enum.KeyEventTypeKeyboardCraftspersonKey1Down` | 键鼠：奇匠按键1（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey1Up` | 键鼠：奇匠按键1（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey2Down` | 键鼠：奇匠按键2（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey2Up` | 键鼠：奇匠按键2（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey3Down` | 键鼠：奇匠按键3（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey3Up` | 键鼠：奇匠按键3（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey4Down` | 键鼠：奇匠按键4（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey4Up` | 键鼠：奇匠按键4（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey5Down` | 键鼠：奇匠按键5（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey5Up` | 键鼠：奇匠按键5（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey6Down` | 键鼠：奇匠按键6（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey6Up` | 键鼠：奇匠按键6（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey7Down` | 键鼠：奇匠按键7（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey7Up` | 键鼠：奇匠按键7（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey8Down` | 键鼠：奇匠按键8（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey8Up` | 键鼠：奇匠按键8（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey9Down` | 键鼠：奇匠按键9（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey9Up` | 键鼠：奇匠按键9（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey10Down` | 键鼠：奇匠按键10（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey10Up` | 键鼠：奇匠按键10（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey11Down` | 键鼠：奇匠按键11（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey11Up` | 键鼠：奇匠按键11（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey12Down` | 键鼠：奇匠按键12（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey12Up` | 键鼠：奇匠按键12（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey13Down` | 键鼠：奇匠按键13（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey13Up` | 键鼠：奇匠按键13（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey14Down` | 键鼠：奇匠按键14（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey14Up` | 键鼠：奇匠按键14（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey15Down` | 键鼠：奇匠按键15（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey15Up` | 键鼠：奇匠按键15（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey16Down` | 键鼠：奇匠按键16（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey16Up` | 键鼠：奇匠按键16（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey17Down` | 键鼠：奇匠按键17（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey17Up` | 键鼠：奇匠按键17（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey18Down` | 键鼠：奇匠按键18（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey18Up` | 键鼠：奇匠按键18（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey19Down` | 键鼠：奇匠按键19（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey19Up` | 键鼠：奇匠按键19（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey20Down` | 键鼠：奇匠按键20（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey20Up` | 键鼠：奇匠按键20（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey21Down` | 键鼠：奇匠按键21（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey21Up` | 键鼠：奇匠按键21（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey22Down` | 键鼠：奇匠按键22（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey22Up` | 键鼠：奇匠按键22（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey23Down` | 键鼠：奇匠按键23（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey23Up` | 键鼠：奇匠按键23（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey24Down` | 键鼠：奇匠按键24（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey24Up` | 键鼠：奇匠按键24（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey25Down` | 键鼠：奇匠按键25（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey25Up` | 键鼠：奇匠按键25（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey26Down` | 键鼠：奇匠按键26（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey26Up` | 键鼠：奇匠按键26（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey27Down` | 键鼠：奇匠按键27（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey27Up` | 键鼠：奇匠按键27（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey28Down` | 键鼠：奇匠按键28（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey28Up` | 键鼠：奇匠按键28（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey29Down` | 键鼠：奇匠按键29（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey29Up` | 键鼠：奇匠按键29（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey30Down` | 键鼠：奇匠按键30（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey30Up` | 键鼠：奇匠按键30（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey31Down` | 键鼠：奇匠按键31（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey31Up` | 键鼠：奇匠按键31（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey32Down` | 键鼠：奇匠按键32（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey32Up` | 键鼠：奇匠按键32（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey33Down` | 键鼠：奇匠按键33（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey33Up` | 键鼠：奇匠按键33（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey34Down` | 键鼠：奇匠按键34（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey34Up` | 键鼠：奇匠按键34（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey35Down` | 键鼠：奇匠按键35（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey35Up` | 键鼠：奇匠按键35（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey36Down` | 键鼠：奇匠按键36（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey36Up` | 键鼠：奇匠按键36（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey37Down` | 键鼠：奇匠按键37（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey37Up` | 键鼠：奇匠按键37（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey38Down` | 键鼠：奇匠按键38（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey38Up` | 键鼠：奇匠按键38（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey39Down` | 键鼠：奇匠按键39（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey39Up` | 键鼠：奇匠按键39（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey40Down` | 键鼠：奇匠按键40（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey40Up` | 键鼠：奇匠按键40（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey41Down` | 键鼠：奇匠按键41（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey41Up` | 键鼠：奇匠按键41（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey42Down` | 键鼠：奇匠按键42（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey42Up` | 键鼠：奇匠按键42（抬起） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey43Down` | 键鼠：奇匠按键43（按下） |
| `Enum.KeyEventTypeKeyboardCraftspersonKey43Up` | 键鼠：奇匠按键43（抬起） |
| `Enum.KeyEventTypeKeyboardMoveForwardKeyDown` | 键鼠：向前移动（按下） |
| `Enum.KeyEventTypeKeyboardMoveForwardKeyUp` | 键鼠：向前移动（抬起） |
| `Enum.KeyEventTypeKeyboardMoveBackwardKeyDown` | 键鼠：向后移动（按下） |
| `Enum.KeyEventTypeKeyboardMoveBackwardKeyUp` | 键鼠：向后移动（抬起） |
| `Enum.KeyEventTypeKeyboardMoveLeftKeyDown` | 键鼠：向左移动（按下） |
| `Enum.KeyEventTypeKeyboardMoveLeftKeyUp` | 键鼠：向左移动（抬起） |
| `Enum.KeyEventTypeKeyboardMoveRightKeyDown` | 键鼠：向右移动（按下） |
| `Enum.KeyEventTypeKeyboardMoveRightKeyUp` | 键鼠：向右移动（抬起） |
| `Enum.KeyEventTypeKeyboardSwitchToWalkOrRunKeyDown` | 键鼠：切换行走/奔跑状态（按下） |
| `Enum.KeyEventTypeKeyboardSwitchToWalkOrRunKeyUp` | 键鼠：切换行走/奔跑状态（抬起） |
| `Enum.KeyEventTypeKeyboardSprintKeyDown` | 键鼠：冲刺（按下） |
| `Enum.KeyEventTypeKeyboardSprintKeyUp` | 键鼠：冲刺（抬起） |
| `Enum.KeyEventTypeKeyboardJumpKeyDown` | 键鼠：跳跃（按下） |
| `Enum.KeyEventTypeKeyboardJumpKeyUp` | 键鼠：跳跃（抬起） |
| `Enum.KeyEventTypeKeyboardDropKeyDown` | 键鼠：落下（按下） |
| `Enum.KeyEventTypeKeyboardDropKeyUp` | 键鼠：落下（抬起） |
| `Enum.KeyEventTypeKeyboardOpenShortcutWheelKeyDown` | 键鼠：呼出快捷轮盘（按下） |
| `Enum.KeyEventTypeKeyboardOpenShortcutWheelKeyUp` | 键鼠：呼出快捷轮盘（抬起） |
| `Enum.KeyEventTypeKeyboardInteractKeyDown` | 键鼠：拾取/交互（按下） |
| `Enum.KeyEventTypeKeyboardInteractKeyUp` | 键鼠：拾取/交互（抬起） |
| `Enum.KeyEventTypeKeyboardNormalAttackKeyDown` | 键鼠：普通攻击（按下） |
| `Enum.KeyEventTypeKeyboardNormalAttackKeyUp` | 键鼠：普通攻击（抬起） |
| `Enum.KeyEventTypeKeyboardCharacterSkill1KeyDown` | 键鼠：角色技能1（按下） |
| `Enum.KeyEventTypeKeyboardCharacterSkill1KeyUp` | 键鼠：角色技能1（抬起） |
| `Enum.KeyEventTypeKeyboardCharacterSkill2KeyDown` | 键鼠：角色技能2（按下） |
| `Enum.KeyEventTypeKeyboardCharacterSkill2KeyUp` | 键鼠：角色技能2（抬起） |
| `Enum.KeyEventTypeKeyboardCharacterSkill3KeyDown` | 键鼠：角色技能3（按下） |
| `Enum.KeyEventTypeKeyboardCharacterSkill3KeyUp` | 键鼠：角色技能3（抬起） |
| `Enum.KeyEventTypeKeyboardCharacterSkill4KeyDown` | 键鼠：角色技能4（按下） |
| `Enum.KeyEventTypeKeyboardCharacterSkill4KeyUp` | 键鼠：角色技能4（抬起） |
| `Enum.KeyEventTypeControllerCraftspersonKey1Down` | 手柄：奇匠按键1（按下） |
| `Enum.KeyEventTypeControllerCraftspersonKey1Up` | 手柄：奇匠按键1（抬起） |
| `Enum.KeyEventTypeControllerCraftspersonKey2Down` | 手柄：奇匠按键2（按下） |
| `Enum.KeyEventTypeControllerCraftspersonKey2Up` | 手柄：奇匠按键2（抬起） |
| `Enum.KeyEventTypeControllerCraftspersonKey3Down` | 手柄：奇匠按键3（按下） |
| `Enum.KeyEventTypeControllerCraftspersonKey3Up` | 手柄：奇匠按键3（抬起） |
| `Enum.KeyEventTypeControllerCraftspersonKey4Down` | 手柄：奇匠按键4（按下） |
| `Enum.KeyEventTypeControllerCraftspersonKey4Up` | 手柄：奇匠按键4（抬起） |
| `Enum.KeyEventTypeControllerCraftspersonKey5Down` | 手柄：奇匠按键5（按下） |
| `Enum.KeyEventTypeControllerCraftspersonKey5Up` | 手柄：奇匠按键5（抬起） |
| `Enum.KeyEventTypeControllerCraftspersonKey6Down` | 手柄：奇匠按键6（按下） |
| `Enum.KeyEventTypeControllerCraftspersonKey6Up` | 手柄：奇匠按键6（抬起） |
| `Enum.KeyEventTypeControllerCraftspersonKey7Down` | 手柄：奇匠按键7（按下） |
| `Enum.KeyEventTypeControllerCraftspersonKey7Up` | 手柄：奇匠按键7（抬起） |
| `Enum.KeyEventTypeControllerCraftspersonKey8Down` | 手柄：奇匠按键8（按下） |
| `Enum.KeyEventTypeControllerCraftspersonKey8Up` | 手柄：奇匠按键8（抬起） |
| `Enum.KeyEventTypeControllerCraftspersonKey9Down` | 手柄：奇匠按键9（按下） |
| `Enum.KeyEventTypeControllerCraftspersonKey9Up` | 手柄：奇匠按键9（抬起） |
| `Enum.KeyEventTypeControllerCraftspersonKey10Down` | 手柄：奇匠按键10（按下） |
| `Enum.KeyEventTypeControllerCraftspersonKey10Up` | 手柄：奇匠按键10（抬起） |
| `Enum.KeyEventTypeControllerCraftspersonKey11Down` | 手柄：奇匠按键11（按下） |
| `Enum.KeyEventTypeControllerCraftspersonKey11Up` | 手柄：奇匠按键11（抬起） |
| `Enum.KeyEventTypeControllerCraftspersonKey12Down` | 手柄：奇匠按键12（按下） |
| `Enum.KeyEventTypeControllerCraftspersonKey12Up` | 手柄：奇匠按键12（抬起） |
| `Enum.KeyEventTypeControllerCraftspersonKey13Down` | 手柄：奇匠按键13（按下） |
| `Enum.KeyEventTypeControllerCraftspersonKey13Up` | 手柄：奇匠按键13（抬起） |
| `Enum.KeyEventTypeControllerCraftspersonKey14Down` | 手柄：奇匠按键14（按下） |
| `Enum.KeyEventTypeControllerCraftspersonKey14Up` | 手柄：奇匠按键14（抬起） |
| `Enum.KeyEventTypeControllerSprintKeyDown` | 手柄：冲刺（按下） |
| `Enum.KeyEventTypeControllerSprintKeyUp` | 手柄：冲刺（抬起） |
| `Enum.KeyEventTypeControllerJumpKeyDown` | 手柄：跳跃（按下） |
| `Enum.KeyEventTypeControllerJumpKeyUp` | 手柄：跳跃（抬起） |
| `Enum.KeyEventTypeControllerInteractKeyDown` | 手柄：拾取/交互（按下） |
| `Enum.KeyEventTypeControllerInteractKeyUp` | 手柄：拾取/交互（抬起） |
| `Enum.KeyEventTypeControllerNormalAttackKeyDown` | 手柄：普通攻击（按下） |
| `Enum.KeyEventTypeControllerNormalAttackKeyUp` | 手柄：普通攻击（抬起） |
| `Enum.KeyEventTypeControllerCharacterSkill1KeyDown` | 手柄：角色技能1（按下） |
| `Enum.KeyEventTypeControllerCharacterSkill1KeyUp` | 手柄：角色技能1（抬起） |
| `Enum.KeyEventTypeControllerCharacterSkill2KeyDown` | 手柄：角色技能2（按下） |
| `Enum.KeyEventTypeControllerCharacterSkill2KeyUp` | 手柄：角色技能2（抬起） |
| `Enum.KeyEventTypeControllerCharacterSkill3KeyDown` | 手柄：角色技能3（按下） |
| `Enum.KeyEventTypeControllerCharacterSkill3KeyUp` | 手柄：角色技能3（抬起） |
| `Enum.KeyEventTypeControllerCharacterSkill4KeyDown` | 手柄：角色技能4（按下） |
| `Enum.KeyEventTypeControllerCharacterSkill4KeyUp` | 手柄：角色技能4（抬起） |
| `Enum.KeyEventTypeControllerMenuConfirmKeyDown` | 手柄：菜单确认（按下） |
| `Enum.KeyEventTypeControllerMenuConfirmKeyUp` | 手柄：菜单确认（抬起） |
| `Enum.KeyEventTypeControllerMenuBackKeyDown` | 手柄：菜单返回（按下） |
| `Enum.KeyEventTypeControllerMenuBackKeyUp` | 手柄：菜单返回（抬起） |

</details>

---

## 附：速查表

### 生命周期回调调用顺序

```
OnInit -> OnStart -> OnEnable -> (OnUpdate / OnLevelUpdate 逐帧) -> OnDisable -> OnDestroy
```

### `active` vs `visible`

| 属性 | 可见性 | 脚本逻辑 |
|---|---|---|
| `active = false` | 不可见 | **停止运行** |
| `visible = false` | 不可见 | 继续运行 |

### 常见易错点

| # | 易错点 |
|---|---|
| 1 | `GetScript*` 拿到的脚本实例可能已销毁，用前必须检查 `script.alive` |
| 2 | CursorEvent 系列方法需先设 `showCursor = true`（`ClientUIContainerControl`） |
| 3 | 复用列表生成的列表项不保证同级排序稳定 |
| 4 | `Tween:SetLoops` 传负数 = 无限循环 |
| 5 | `Tween:SetRelative(true)` 为相对增量，`false` 为绝对目标值 |
| 6 | 自定义变量变化回调只给实体类型和变量名，当前值需调 `game.GetGlobalCustomVariableValue` |
| 7 | 按键事件被 Lua 回调标记已处理后，同容器内其他按键不再响应本次事件 |
| 8 | `SetActive` 停止脚本逻辑，`SetVisible` 不会 |
| 9 | `game.PauseLevelTime` 不暂停脚本自身 |
| 10 | `os.*` / `debug.*` / `io.*` / `coroutine.*` 大部分不可用 |

### `Tween` 链式调用

`SetEase` / `SetRelative` / `Play` / `SetOnComplete` / `SetOnStepComplete` / `SetLoops`
均返回实例本身，可链式书写：

```lua
game.Tween(control, { anchoredPositionX = 100, fillAmount = 1 }, 0.5)
  :SetEase(Enum.EaseTypeOutQuad)
  :SetRelative(false)
  :SetOnComplete(function() print("done") end)
  :Play()
```
