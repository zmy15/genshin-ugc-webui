# -*- coding: utf-8 -*-
"""
Parse the Genshin UGC "客户端控件API文档" into a structured Markdown document.

Source: plaintext extracted from textMap.json (key = mhtakr07vej4)
Output: <repo>/docs\\client_control_api.md  (+ intermediate JSON)
"""
import json, re, io, os

SRC = r"<article.txt>"
OUT = r"<repo>\ugc_out"
os.makedirs(OUT, exist_ok=True)

t = io.open(SRC, encoding="utf-8-sig").read().replace("\u200b", "")

# =============================================================== helpers
def emit_table(rows, header=("函数/方法", "返回值", "说明")):
    """rows: list of 3-tuples (may be short)"""
    out = ["| " + " | ".join(header) + " |",
           "|" + "---|" * len(header)]
    for r in rows:
        r = list(r) + [""] * (len(header) - len(r))
        cells = [str(c).replace("|", "\\|").strip() for c in r[:len(header)]]
        out.append("| " + " | ".join(cells) + " |")
    return "\n".join(out)


L = []          # markdown lines
def w(s=""):
    L.append(s)

# =============================================================== 一、术语约定
m = re.search(r"一、术语约定(.*?)二、API 范围", t, re.S)
glossary_raw = m.group(1)
glossary_raw = glossary_raw.split("不代表实际接口和字段名称。")[-1]

GLOSSARY = [
    ("脚本", "Script"), ("信号", "ServerSignal"), ("自定义变量", "CustomVariable"),
    ("脚本内的参数", "Param"), ("补间动画", "Tween"), ("进度", "fillAmount"),
    ("基础", "Basic"), ("拉伸", "Stretch"), ("边缘羽化", "soft edge"),
    ("90度环绕", "Radial90"), ("180度环绕", "Radial180"), ("360度环绕", "Radial360"),
    ("客户端控件运行时ID", "ClientControlID"), ("客户端控件运行时ID列表", "ClientControlIDList"),
    ("关卡时停", "LevelTimePaused"), ("容器节点", "ContainerControl"),
    ("文本框", "TextBoxControl"), ("文本视窗", "TextWindowControl"),
    ("图片", "ImageControl"), ("界面动效", "UIAnimationControl"),
    ("全屏动效", "FullscreenUIAnimationControl"), ("按键提示", "KeyHintControl"),
    ("网格视窗", "GridScrollerControl"), ("光标检测区域", "CursorEventArea"),
    ("模板引用控件", "ReferenceControl"), ("预设按钮", "PresetButton"),
    ("存活", "alive"), ("启用", "enable"), ("激活", "active"), ("可见", "visible"),
    ("隔离手柄导航", "IsolateNavigation"),
    ("屏蔽按键事件穿透", "disableKeyEventPassthrough"),
    ("屏蔽区域内点击事件穿透", "disableCursorEventPassthrough"),
    ("显示常驻光标", "showCursor"), ("可被光标射线检测", "Raycast Target"),
]

w("# 原神 UGC · 客户端控件 Lua UI 脚本公共 API 文档")
w()
w("> 来源：米游社 UGC Wiki · `mhtakr07vej4`（更新于 2026-09-14）")
w("> 本文档介绍客户端 Lua UI 脚本公共 API，包括接口签名、类型、字段、函数、方法和枚举。")
w()
w("## 目录")
w()
w("- [一、术语约定](#一术语约定)")
w("- [二、API 范围](#二api-范围)")
w("- [三、运行环境](#三运行环境)")
w("- [四、具体介绍](#四具体介绍)")
w("  - [1. 脚本生命周期](#1-脚本生命周期)")
w("  - [2. 逐帧控制方法](#2-逐帧控制方法)")
w("  - [3. 全局 API](#3-全局-api)")
w("  - [4. Color](#4-color)")
w("  - [5. Script](#5-script)")
w("  - [6. game](#6-game)")
w("  - [7. Tween](#7-tween)")
w("  - [8. TweenSequence](#8-tweensequence)")
w("  - [9. ServerSignal](#9-serversignal)")
w("  - [10. EnumItem](#10-enumitem)")
w("  - [11. 枚举系统](#11-枚举系统)")
w("  - [12. 客户端控件](#12-客户端控件)")
w("  - [13. ClientUIBaseControl](#13-clientuibasecontrol)")
w("  - [14. ClientUIImageControl](#14-clientuiimagecontrol)")
w("  - [15. ClientUITextBoxControl](#15-clientuitextboxcontrol)")
w("  - [16. ClientUITextWindowControl](#16-clientuitextwindowcontrol)")
w("  - [17. ClientUIPresetButtonControl](#17-clientuipresetbuttoncontrol)")
w("  - [18. ClientUICursorEventAreaControl](#18-clientuicursoreventareacontrol)")
w("  - [19. CursorEventData](#19-cursoreventdata)")
w("  - [20. ClientUIGridScrollerControl](#20-clientuigridscrollercontrol)")
w("  - [21. ClientUIKeyHintControl](#21-clientuikeyhintcontrol)")
w("  - [22. ClientUIAnimationControl](#22-clientuianimationcontrol)")
w("  - [23. ClientUIFullscreenAnimationControl](#23-clientuifullscreenanimationcontrol)")
w("  - [24. ClientUIContainerControl](#24-clientuicontainercontrol)")
w("  - [25. ClientUIReferenceControl](#25-clientuireferencecontrol)")
w("  - [26. 按键输入](#26-按键输入)")
w()

# ---------------------------------------------------------------- 一
w("## 一、术语约定")
w()
w("本部分为 API 专有名词的中英文对照约定，**不代表实际接口和字段名称**。")
w()
w(emit_table(GLOSSARY, ("中文名词", "英文名词")))
w()

# ---------------------------------------------------------------- 二、三
w("## 二、API 范围")
w()
w("本页覆盖：脚本生命周期、全局函数、颜色、Script、game、服务器信号、补间动画、"
  "输入事件、手柄导航、全部客户端控件类型及枚举。")
w()
w("## 三、运行环境")
w()
w("- **Lua 版本**：Lua 5.3")
w()
w("以下标准库能力**不可用**：")
w()
w("- `string.dump`")
w("- `io.*`")
w("- `coroutine.*`")
w("- 除 `os.time`、`os.date`、`os.clock`、`os.difftime` 外的 `os.*`")
w("- 除 `debug.traceback` 外的 `debug.*`")
w()
w("以下为标准库补充的方法：")
w()
w("- `math.isnan(n)` 和 `math.isinf(n)`")
w()

# ---------------------------------------------------------------- 四
w("## 四、具体介绍")
w()

w("### 1. 脚本生命周期")
w()
w("运行时按**固定名称**查找并调用下列生命周期回调函数。")
w()
w(emit_table([
    ("`OnInit()`", "无", "脚本初始化时调用"),
    ("`OnStart()`", "无", "脚本启动时调用"),
    ("`OnEnable()`", "无", "脚本启用时调用"),
    ("`OnDisable()`", "无", "脚本停用时调用"),
    ("`OnUpdate(dt)`", "`dt: number`", "脚本逐帧更新时调用，**不受关卡时停影响**"),
    ("`OnLevelUpdate(dt)`", "`dt: number`", "关卡逐帧更新时调用，**受关卡时停影响**"),
    ("`OnDestroy()`", "无", "脚本销毁时调用"),
], ("函数", "参数", "功能")))
w()

w("### 2. 逐帧控制方法")
w()
w(emit_table([
    ("`script:EnableUpdate(enabled: boolean)`", "—",
     "控制当前脚本的逐帧更新；`false` 关闭，`true` 重新启用"),
], ("方法", "返回值", "说明")))
w()

w("### 3. 全局 API")
w()
w("#### (1) 类型查询")
w()
w(emit_table([
    ("`typeof(value)`", "`string`", "返回运行时类型名称；用于识别宿主对象"),
], ("函数", "返回值", "说明")))
w()
w("#### (2) 日志和调试")
w()
w(emit_table([
    ("`print(...)`", "—", "将传入值写入普通级别日志；该函数不阻断运行"),
    ("`printerr(...)`", "—", "将传入值写入错误级别日志；该函数不抛出 Lua 错误，也不阻断运行"),
    ("`debug.traceback([message[, level]])`", "`string`",
     "生成并返回调用栈文本；`message` 添加文本开头的说明，`level` 指定调用栈起始层级；"
     "该函数仅返回文本，不自动写入日志"),
    ("`game.PrintClientUITree()`", "—", "将当前客户端控件树按父子层级写入日志"),
], ("函数", "返回值", "说明")))
w()
w("#### (3) 数值检查")
w()
w("处理摇杆、坐标或补间动画参数等外部数值时，可用这两个函数进行有限数校验。")
w()
w(emit_table([
    ("`math.isnan(n)`", "`boolean`", "判断数值是否为 NaN"),
    ("`math.isinf(n)`", "`boolean`", "判断数值是否为正负无穷"),
], ("函数", "返回值", "说明")))
w()
w("#### (4) 全局变量")
w()
w(emit_table([
    ("`script`", "`Script`", "当前脚本"),
    ("`Enum`", "`Enum`", "枚举"),
], ("名称", "类型", "说明")))
w()

# ---------------------------------------------------------------- 4 Color
w("### 4. Color")
w()
w("#### (1) 构造函数")
w()
w(emit_table([
    ("`Color(r: number, g: number, b: number, a: number?)`", "`ColorValue`",
     "由 0–255 RGBA 创建颜色；`a` 可省略，也可传 `nil`。传 `nil` 时等同于 255（不透明）"),
], ("构造函数", "返回值", "说明")))
w()
w("#### (2) 函数")
w()
w(emit_table([
    ("`Color.FromRGB(r: number, g: number, b: number)`", "`ColorValue`", "由 0–255 RGB 创建颜色"),
    ("`Color.FromRGBA(r: number, g: number, b: number, a: number?)`", "`ColorValue`",
     "由 0–255 RGBA 创建颜色；`a` 可省略或传 `nil`。传 `nil` 时等同于 255（不透明）"),
    ("`Color.ToRGBA(colorValue: ColorValue)`", "`r, g, b, a: number`",
     "将颜色拆分为 0-255 的 RGBA 四个值"),
], ("函数", "返回值", "说明")))
w()

# ---------------------------------------------------------------- 5 Script
w("### 5. Script")
w()
w("表示脚本实例。运行时通过全局变量 `script` 提供当前脚本实例。")
w()
w("#### (1) 字段")
w()
w(emit_table([
    ("`alive`", "`boolean`", "**只读**", "脚本实例是否存活"),
    ("`scriptMappingId`", "`integer`", "**只读**", "脚本映射 ID"),
    ("`object`", "`any`", "**只读**", "脚本所挂载的宿主对象"),
    ("`path`", "`string`", "**只读**", "脚本路径"),
    ("`enabled`", "`boolean`", "**读写**", "脚本启用状态"),
], ("字段", "类型", "访问", "说明")))
w()
w("#### (2) 方法")
w()
w(emit_table([
    ("`script:GetParam(paramName: string)`", "`any`",
     "按变量名称 `paramName` 读取当前脚本内对应变量的参数"),
    ("`script:Invoke(funcName: string, ...: any)`", "—",
     "在 UI 脚本内定义的全局方法（脚本内环境）；调用当前脚本中名称为 `funcName` 的函数；"
     "参数应使用运行时支持的可传递类型"),
    ("`script:EnableUpdate(enabled: boolean)`", "—",
     "控制当前脚本的 Tick 更新；`false` 关闭，`true` 重新启用"),
    ("`script:RegisterServerSignalHandler(signalName: string, callback: fun(signalName: string, signalParams: any[]))`",
     "—", "注册 `signalName` 对应的服务器信号监听；回调参数依次为信号名称和信号参数数组"),
    ("`script:UnregisterServerSignalHandler(signalName: string)`", "—",
     "移除 `signalName` 对应的服务器信号监听"),
    ("`script:RegisterCustomVariableChangedHandler(entityType: CustomVariableEntityType, customVariableName: string, callback: fun(entityType: CustomVariableEntityType, customVariableName: string))`",
     "—", "监听 `entityType` 和 `customVariableName` 对应的全局自定义变量变化；"
     "回调仅提供实体类型和变量名称，**当前值需通过 `game.GetGlobalCustomVariableValue` 读取**"),
    ("`script:UnregisterCustomVariableChangedHandler(entityType: CustomVariableEntityType, customVariableName: string)`",
     "—", "移除 `entityType` 和 `customVariableName` 对应的自定义变量监听"),
], ("方法", "返回值", "说明")))
w()

# ---------------------------------------------------------------- 6 game
w("### 6. game")
w()
w("`game` 是客户端运行时提供的全局表。**以下函数均使用点号调用**。")
w()
w("#### (1) UI 与层级")
w()
w(emit_table([
    ("`game.InstantiateClientUIControl(controlPrefabIndex: integer, parent: ClientUIBaseControl)`",
     "`ClientUIBaseControl`", "根据已配置的控件模板索引，在 `parent` 下创建控件实例"),
    ("`game.DestroyClientUIControl(control: ClientUIBaseControl)`", "—", "销毁指定客户端控件实例"),
    ("`game.GetClientUIControl(controlId: integer)`", "`ClientUIBaseControl`",
     "按客户端控件运行时 ID 获取控件"),
    ("`game.FindClientUIRoot(nodeName: string)`", "`ClientUIBaseControl`",
     "查找名称为 `nodeName` 的 UI 根控件"),
    ("`game.GetClientUIRoots()`", "`ClientUIBaseControl[]`",
     "获取全部 UI 根控件。即实际显示的客户端控件容器画布中的默认容器节点"),
    ("`game.GetUICanvasSize()`", "`x, y: number`", "获取 UI 画布宽高"),
    ("`game.GetCursorUIPos()`", "`x, y: number`", "获取光标 UI 坐标"),
], ("函数", "返回值", "说明")))
w()
w("#### (2) 输入与聚焦")
w()
w("读取摇杆轴值后，可按交互需求应用有限数检查、死区、范围钳制与坐标系转换。")
w()
w(emit_table([
    ("`game.GetDevice()`", "`Device`", "获取当前输入设备类型"),
    ("`game.SetControllerFocus(control: ClientUIBaseControl)`", "—", "设置手柄当前聚焦控件"),
    ("`game.GetControllerFocus()`", "`ClientUIBaseControl`", "获取当前聚焦控件"),
    ("`game.GetControllerLeftStickAxis()`", "`horizontal, vertical: number`", "获取左摇杆轴值"),
    ("`game.GetControllerRightStickAxis()`", "`horizontal, vertical: number`", "获取右摇杆轴值"),
], ("函数", "返回值", "说明")))
w()
w("#### (3) 补间动画、服务器信号与自定义变量")
w()
w(emit_table([
    ("`game.Tween(object: any, tweenDataTable: table, duration: number)`", "`Tween`",
     "按目标字段和持续时间为对象创建补间动画。传入参数分别为传入对象、"
     "传入对象的 tweenable 字段名为键，目标值为值组成的 table，持续时间"),
    ("`game.TweenSequence()`", "`TweenSequence`", "创建空的补间动画序列"),
    ("`game.ServerSignal(signalName: string)`", "`ServerSignal`",
     "使用服务器约定的信号名称 `signalName` 创建服务器信号"),
    ("`game.GetGlobalCustomVariableValue(entityType: CustomVariableEntityType, customVariableName: string)`",
     "`any`", "读取 `entityType` 和 `customVariableName` 对应的全局自定义变量，"
     "支持复杂变量结构（列表、字典、结构体）"),
], ("函数", "返回值", "说明")))
w()
w("#### (4) 关卡、音效与本地化")
w()
w(emit_table([
    ("`game.PauseLevelTime(pause: boolean)`", "—",
     "单人模式下设置关卡时停状态；`true` 开启，`false` 关闭；**不暂停脚本自身**"),
    ("`game.IsLevelTimePaused()`", "`boolean`", "查询是否处于关卡时停"),
    ("`game.PlayAudio2D(audioId: integer)`", "`integer`", "按已配置的音效 ID 播放 2D 音效，并返回音效实例 ID"),
    ("`game.StopAudio(audioInstanceId: integer)`", "—", "停止指定音效实例"),
    ("`game.IsAudioAlive(audioInstanceId: integer)`", "`boolean`", "查询音效实例是否存活"),
    ("`game.GetLanguageType()`", "`LanguageType`", "获取当前语言"),
    ("`game.GetStageMode()`", "`StageMode`", "获取当前关卡模式"),
    ("`game.IsTestPlay()`", "`boolean`", "查询当前是否处于测试游玩状态"),
    ("`game.GetText(textMapId: string)`", "`string`", "按已配置的文本映射 ID 获取本地化文本"),
], ("函数", "返回值", "说明")))
w()

# ---------------------------------------------------------------- 7 Tween
w("### 7. Tween")
w()
w("补间动画类，用于对目标对象的 Tweenable 字段进行插值。")
w()
w("#### (1) 创建")
w()
w(emit_table([
    ("`game.Tween(object: any, tweenDataTable: table, duration: number)`", "`Tween`",
     "按目标字段和持续时间为对象创建补间动画。传入参数分别为传入对象、"
     "传入对象的 tweenable 字段名为键，目标值为值组成的 table，持续时间"),
], ("函数", "返回值", "说明")))
w()
w("#### (2) 方法")
w()
w(emit_table([
    ("`Tween:SetEase(easeType: EaseType)`", "`Tween`", "设置缓动类型并返回当前实例"),
    ("`Tween:SetRelative(relative: boolean)`", "`Tween`",
     "设置 `tweenDataTable` 中目标值的解释方式；`false` 表示绝对目标值，`true` 表示相对当前值的增量"),
    ("`Tween:Play()`", "`Tween`", "开始播放并返回当前实例"),
    ("`Tween:Pause()`", "—", "暂停并保留当前进度"),
    ("`Tween:Resume()`", "—", "从暂停处继续播放"),
    ("`Tween:Restart()`", "—", "回到初始状态并重新播放"),
    ("`Tween:Complete()`", "—", "立即切换到结束状态并完成"),
    ("`Tween:Kill(complete: boolean)`", "—",
     "销毁实例；`true` 表示先切换到结束状态并触发完成回调，`false` 表示保持当前状态结束且不触发完成回调"),
    ("`Tween:SetOnComplete(onComplete: fun())`", "`Tween`", "设置全部循环完成后的回调并返回当前实例"),
    ("`Tween:SetOnStepComplete(onStepComplete: fun())`", "`Tween`", "设置步骤完成回调并返回当前实例"),
    ("`Tween:SetLoops(times: integer)`", "`Tween`", "设置循环次数并返回当前实例；**负数表示无限循环**"),
], ("方法", "返回值", "说明")))
w()

# ---------------------------------------------------------------- 8 TweenSequence
w("### 8. TweenSequence")
w()
w("将多个补间动画、间隔和回调编排到同一时间线上。")
w()
w("#### (1) 创建")
w()
w(emit_table([
    ("`game.TweenSequence()`", "`TweenSequence`", "创建空的补间动画序列"),
], ("函数", "返回值", "说明")))
w()
w("#### (2) 方法")
w()
w(emit_table([
    ("`TweenSequence:Append(tween: Tween)`", "`TweenSequence`", "在序列末尾接入补间动画"),
    ("`TweenSequence:AppendInterval(interval: number)`", "`TweenSequence`", "在序列末尾接入指定秒数的等待时间"),
    ("`TweenSequence:AppendCallback(callback: fun())`", "`TweenSequence`", "在序列末尾接入回调"),
    ("`TweenSequence:Join(tween: Tween)`", "`TweenSequence`",
     "与当前队尾步骤同时播放；该步骤以最晚结束者为准"),
    ("`TweenSequence:Insert(time: number, tween: Tween)`", "`TweenSequence`", "在指定时间点插入并行补间动画"),
    ("`TweenSequence:InsertCallback(time: number, callback: fun())`", "`TweenSequence`", "在指定时间点插入回调"),
    ("`TweenSequence:Play()`", "`TweenSequence`", "开始播放并返回当前实例"),
    ("`TweenSequence:Pause()`", "—", "暂停序列"),
    ("`TweenSequence:Resume()`", "—", "继续播放序列"),
    ("`TweenSequence:Restart()`", "—", "回到初始状态并重新播放"),
    ("`TweenSequence:Complete()`", "—", "立即完成整个序列"),
    ("`TweenSequence:Kill(complete: boolean)`", "—",
     "销毁序列；`true` 表示先完成，`false` 表示保持当前状态结束"),
    ("`TweenSequence:SetOnComplete(onComplete: fun())`", "`TweenSequence`", "设置整个序列完成回调并返回当前实例"),
    ("`TweenSequence:SetOnStepComplete(onStepComplete: fun())`", "`TweenSequence`", "设置步骤完成回调并返回当前实例"),
    ("`TweenSequence:SetLoops(times: integer)`", "`TweenSequence`", "设置循环次数并返回当前实例；**负数表示无限循环**"),
], ("方法", "返回值", "说明")))
w()

# ---------------------------------------------------------------- 9 ServerSignal
w("### 9. ServerSignal")
w()
w("创建并向服务器发送信号。参数按服务器约定依次添加。")
w()
w("#### (1) 创建")
w()
w(emit_table([
    ("`game.ServerSignal(signalName: string)`", "`ServerSignal`",
     "使用服务器约定的信号名称 `signalName` 创建服务器信号"),
], ("函数", "返回值", "说明")))
w()
w("#### (2) 方法")
w()
w(emit_table([
    ("`ServerSignal:AddParam(paramType: ParamType, paramValue: any)`", "—",
     "`paramType` 指定参数类型，`paramValue` 指定参数值"),
    ("`ServerSignal:SendSignal()`", "—", "发送已构建的服务器信号"),
    ("`ServerSignal:AddInt(intValue: integer)`", "—", "添加整数参数"),
    ("`ServerSignal:AddIntList(intListValue: integer[])`", "—", "添加整数列表参数"),
    ("`ServerSignal:AddFloat(floatValue: number)`", "—", "添加浮点数参数"),
    ("`ServerSignal:AddFloatList(floatListValue: number[])`", "—", "添加浮点数列表参数"),
    ("`ServerSignal:AddString(stringValue: string)`", "—", "添加字符串参数"),
    ("`ServerSignal:AddStringList(stringListValue: string[])`", "—", "添加字符串列表参数"),
    ("`ServerSignal:AddVector3(vector3Value: table)`", "—",
     "添加三维向量参数；传入以 x,y,z 为键，目标值为值组成的 table"),
    ("`ServerSignal:AddVector3List(vector3ListValue: table[])`", "—",
     "添加三维向量列表参数；传入以 x,y,z 为键，目标值为值组成的 table 列表"),
    ("`ServerSignal:AddBool(boolValue: boolean)`", "—", "添加布尔值参数"),
    ("`ServerSignal:AddBoolList(boolListValue: boolean[])`", "—", "添加布尔值列表参数"),
    ("`ServerSignal:AddGuid(guidValue: integer)`", "—", "添加 GUID 参数"),
    ("`ServerSignal:AddGuidList(guidListValue: integer[])`", "—", "添加 GUID 列表参数"),
    ("`ServerSignal:AddEntity(entityValue: integer)`", "—", "添加实体参数"),
    ("`ServerSignal:AddEntityList(entityListValue: integer[])`", "—", "添加实体列表参数"),
    ("`ServerSignal:AddPrefabId(prefabIdValue: integer)`", "—", "添加元件 ID 参数"),
    ("`ServerSignal:AddPrefabIdList(prefabIdListValue: integer[])`", "—", "添加元件 ID 列表参数"),
    ("`ServerSignal:AddConfigId(configIdValue: integer)`", "—", "添加配置 ID 参数"),
    ("`ServerSignal:AddConfigIdList(configIdListValue: integer[])`", "—", "添加配置 ID 列表参数"),
], ("方法", "返回值", "说明")))
w()

# ---------------------------------------------------------------- 10 EnumItem
w("### 10. EnumItem")
w()
w("#### (1) 字段")
w()
w(emit_table([
    ("`Name`", "`string`", "**只读**", "枚举值名称"),
    ("`FullName`", "`string`", "**只读**", "枚举值完整名称"),
    ("`EnumType`", "`string`", "**只读**", "枚举类型名称"),
], ("字段", "类型", "访问", "说明")))
w()

# ---------------------------------------------------------------- 11 枚举系统
w("### 11. 枚举系统")
w()

ENUMS = [
    ("(1) `Enum.EaseType`", "缓动类型", [
        ("Linear", "线性"), ("InSine", "正弦缓入"), ("OutSine", "正弦缓出"), ("InOutSine", "正弦缓入缓出"),
        ("InQuad", "二次缓入"), ("OutQuad", "二次缓出"), ("InOutQuad", "二次缓入缓出"),
        ("InCubic", "三次缓入"), ("OutCubic", "三次缓出"), ("InOutCubic", "三次缓入缓出"),
        ("InQuart", "四次缓入"), ("OutQuart", "四次缓出"), ("InOutQuart", "四次缓入缓出"),
        ("InQuint", "五次缓入"), ("OutQuint", "五次缓出"), ("InOutQuint", "五次缓入缓出"),
        ("InExpo", "指数缓入"), ("OutExpo", "指数缓出"), ("InOutExpo", "指数缓入缓出"),
        ("InCirc", "圆形缓入"), ("OutCirc", "圆形缓出"), ("InOutCirc", "圆形缓入缓出"),
        ("InBack", "回弹缓入"), ("OutBack", "回弹缓出"), ("InOutBack", "回弹缓入缓出"),
        ("InElastic", "弹性缓入"), ("OutElastic", "弹性缓出"), ("InOutElastic", "弹性缓入缓出"),
        ("InBounce", "弹跳缓入"), ("OutBounce", "弹跳缓出"), ("InOutBounce", "弹跳缓入缓出"),
    ]),
    ("(2) `Enum.CustomVariableEntityType`", "自定义变量实体类型", [
        ("Level", "关卡"), ("PlayerSelf", "玩家自身"), ("AvatarSelf", "角色自身"),
    ]),
    ("(3) `Enum.Device`", "输入设备", [
        ("KeyboardAndMouse", "键鼠"), ("Mobile", "移动端触屏"),
        ("Controller", "主机手柄"), ("MobileController", "移动端手柄"),
    ]),
    ("(4) `Enum.StageMode`", "关卡模式", [
        ("Beyond", "超限模式"), ("Classic", "经典模式"),
    ]),
    ("(5) `Enum.LanguageType`", "语言类型", [
        ("LanguageNone", "未指定"), ("LanguageEng", "英语"), ("LanguageChs", "简体中文"),
        ("LanguageCht", "繁体中文"), ("LanguageFra", "法语"), ("LanguageDeu", "德语"),
        ("LanguageSpa", "西班牙语"), ("LanguagePor", "葡萄牙语"), ("LanguageRus", "俄语"),
        ("LanguageJpn", "日语"), ("LanguageKor", "韩语"), ("LanguageTha", "泰语"),
        ("LanguageVie", "越南语"), ("LanguageInd", "印度尼西亚语"),
        ("LanguageTur", "土耳其语"), ("LanguageIta", "意大利语"),
    ]),
    ("(6) `Enum.ParamType`", "服务器信号参数类型", [
        ("Entity", "实体"), ("EntityList", "实体列表"),
        ("Int", "整数"), ("IntList", "整数列表"),
        ("Bool", "布尔值"), ("BoolList", "布尔值列表"),
        ("Float", "浮点数"), ("FloatList", "浮点数列表"),
        ("String", "字符串"), ("StringList", "字符串列表"),
        ("Vector3", "三维向量"), ("Vector3List", "三维向量列表"),
        ("Guid", "GUID"), ("GuidList", "GUID 列表"),
        ("ConfigId", "配置 ID"), ("PrefabId", "元件 ID"),
        ("ConfigIdList", "配置 ID 列表"), ("PrefabIdList", "元件 ID 列表"),
    ]),
    ("(7) `Enum.CursorEventType`", "光标事件类型", [
        ("CursorDown", "光标按下"), ("CursorUp", "光标抬起"),
        ("CursorEnter", "光标进入检测区域"), ("CursorExit", "光标离开检测区域"),
        ("CursorDrag", "光标拖拽"), ("CursorBeginDrag", "开始拖拽"),
        ("CursorEndDrag", "结束拖拽"), ("CursorClick", "完成点击"),
    ]),
    ("(8) `Enum.ScrollDirection`", "滚动方向", [
        ("Horizontal", "水平滚动"), ("Vertical", "垂直滚动"),
    ]),
    ("(9) `Enum.ScrollLayoutConstraint`", "滚动布局约束", [
        ("AutoWrap", "自动换行布局"), ("Fixed", "固定行数或列数布局"),
    ]),
    ("(10) `Enum.ScrollAlignType`", "滚动对齐方式", [
        ("Bottom", "底部对齐"), ("Center", "居中对齐"), ("Top", "顶部对齐"),
    ]),
    ("(11) `Enum.ControllerNavigationDir`", "手柄导航方向", [
        ("Up", "向上"), ("Down", "向下"), ("Left", "向左"), ("Right", "向右"),
    ]),
    ("(12) `Enum.ControllerNavigationEventType`", "手柄导航事件类型", [
        ("Confirm", "确认"), ("Cancel", "取消"),
        ("Focus", "进入聚焦"), ("LostFocus", "退出聚焦"),
        ("RightStickUp", "右摇杆向上"), ("RightStickDown", "右摇杆向下"),
        ("RightStickRight", "右摇杆向右"), ("RightStickLeft", "右摇杆向左"),
        ("LeftStickUp", "左摇杆向上"), ("LeftStickDown", "左摇杆向下"),
        ("LeftStickRight", "左摇杆向右"), ("LeftStickLeft", "左摇杆向左"),
    ]),
    ("(13) `Enum.ControllerNavigationMode`", "手柄导航模式", [
        ("None", "无导航"), ("NearestControl", "导航至最近控件"), ("Specified", "导航至指定控件"),
    ]),
    ("(14) `Enum.TextHorizontalAlignment`", "文本水平对齐", [
        ("Left", "左对齐"), ("Middle", "水平居中"), ("Right", "右对齐"),
    ]),
    ("(15) `Enum.TextVerticalAlignment`", "文本垂直对齐", [
        ("Top", "顶部对齐"), ("Middle", "垂直居中"), ("Bottom", "底部对齐"),
    ]),
    ("(16) `Enum.ImageType`", "图片类型", [
        ("Basic", "基础"), ("Stretch", "拉伸"),
    ]),
    ("(17) `Enum.ImageSource`", "图片来源", [
        ("StaticReference", "静态引用"), ("Item", "道具"), ("Equipment", "装备"),
        ("Skill", "技能"), ("UnitStatus", "单位状态"), ("Faction", "阵营"),
        ("Currency", "货币"), ("Prefab", "元件"),
    ]),
    ("(18) `Enum.ImageFillType`", "图片填充方式", [
        ("Unused", "不使用填充"), ("Horizontal", "水平"), ("Vertical", "垂直"),
        ("Radial90", "90度环绕"), ("Radial180", "180度环绕"), ("Radial360", "360度环绕"),
    ]),
    ("(19) `Enum.ImageFillHorizontalType`", "水平填充方向", [
        ("Left", "从左侧开始"), ("Right", "从右侧开始"),
    ]),
    ("(20) `Enum.ImageFillVerticalType`", "垂直填充方向", [
        ("Bottom", "从底部开始"), ("Top", "从顶部开始"),
    ]),
    ("(21) `Enum.ImageFillRadial90Type`", "90度环绕起点", [
        ("BottomLeft", "左下"), ("TopLeft", "左上"),
        ("TopRight", "右上"), ("BottomRight", "右下"),
    ]),
    ("(22) `Enum.ImageFillRadialType`", "180/360度环绕起点", [
        ("Bottom", "底部"), ("Left", "左侧"), ("Top", "顶部"), ("Right", "右侧"),
    ]),
    ("(23) `Enum.ImageMaskSoftEdgeMode`", "边缘羽化模式", [
        ("Percentage", "按比例设置边缘羽化"), ("Pixel", "按像素设置边缘羽化"),
    ]),
    ("(24) `Enum.UIAnimationLayer`", "界面动效层级", [
        ("AboveAllControls", "所有控件之上"), ("BelowAllControls", "所有控件之下"),
    ]),
]

for title, desc, items in ENUMS:
    # title looks like "(1) `Enum.EaseType`"
    enum_name = re.search(r"`([^`]+)`", title).group(1)   # Enum.EaseType
    w(f"#### {title}")
    w()
    w(f"{desc}")
    w()
    # source concatenates type + member (e.g. Enum.EaseTypeLinear) -- keep it faithful
    w(emit_table([(f"`{enum_name}{k}`", v) for k, v in items], ("枚举名", "说明")))
    w()

# ---------------------------------------------------------------- 12 客户端控件
w("### 12. 客户端控件")
w()
w("#### (1) 继承关系")
w()
w("所有具体控件都继承 `ClientUIBaseControl`：")
w()
w(emit_table([
    ("`ClientUIImageControl`", "图片"),
    ("`ClientUITextBoxControl`", "文本框"),
    ("`ClientUITextWindowControl`", "文本视窗"),
    ("`ClientUIPresetButtonControl`", "预设按钮"),
    ("`ClientUICursorEventAreaControl`", "光标检测区域"),
    ("`ClientUIGridScrollerControl`", "网格视窗"),
    ("`ClientUIKeyHintControl`", "按键提示"),
    ("`ClientUIAnimationControl`", "界面动效"),
    ("`ClientUIFullscreenAnimationControl`", "全屏动效"),
    ("`ClientUIContainerControl`", "容器节点"),
    ("`ClientUIReferenceControl`", "模板引用控件"),
], ("类型", "控件名")))
w()

# ---------------------------------------------------------------- 13 Base
w("### 13. ClientUIBaseControl")
w()
w("客户端控件基类，提供层级、布局、脚本访问、输入监听与手柄导航。")
w()
w("#### (1) 字段")
w()
w(emit_table([
    ("`alive`", "`boolean`", "只读", "控件是否存活"),
    ("`id`", "`integer`", "只读", "运行时 ID"),
    ("`prefabIndex`", "`integer`", "只读", "控件模板索引"),
    ("`active`", "`boolean`", "只读",
     "激活状态；`true` 时控件可见且挂载脚本逻辑运行，`false` 时控件不可见且脚本逻辑停止运行。默认为 `false`。"),
    ("`activeInHierarchy`", "`boolean`", "只读", "计入全部父级后的实际激活状态"),
    ("`visible`", "`boolean`", "只读",
     "**仅控制可见性，不改变激活状态或脚本逻辑运行状态**"),
    ("`name`", "`string`", "读写", "控件名称"),
    ("`parent`", "`ClientUIBaseControl`", "读写", "父控件"),
    ("`anchoredPositionX, anchoredPositionY`", "`number`", "读写", "位置、Tweenable"),
    ("`sizeDeltaX, sizeDeltaY`", "`number`", "读写", "大小差异、Tweenable"),
    ("`anchorMinX, anchorMinY`", "`number`", "读写", "最小锚点、Tweenable"),
    ("`anchorMaxX, anchorMaxY`", "`number`", "读写", "最大锚点、Tweenable"),
    ("`pivotX, pivotY`", "`number`", "读写", "中心、Tweenable"),
    ("`localScaleX, localScaleY, localScaleZ`", "`number`", "读写", "缩放、Tweenable"),
    ("`localRotationX, localRotationY, localRotationZ`", "`number`", "读写", "旋转、Tweenable"),
    ("`canControllerFocus`", "`boolean`", "读写", "可被手柄导航摇杆聚焦"),
], ("字段", "类型", "访问", "说明")))
w()
w("#### (2) 层级与可见性")
w()
w("> ⚠️ 复用列表生成的列表项**不保证同级排序结果稳定**。")
w()
w(emit_table([
    ("`GetChildren()`", "`ClientUIBaseControl[]`", "获取直接子控件"),
    ("`GetChild(name)`", "`ClientUIBaseControl`", "获取当前控件中名称为 `name` 的直接子控件"),
    ("`FindChild(path)`", "`ClientUIBaseControl`", "按路径查找子控件"),
    ("`SetActive(active)`", "—",
     "设置激活状态；关闭后控件不可见且挂载脚本逻辑停止运行"),
    ("`SetVisible(visible)`", "—",
     "**仅设置可见性**，不改变激活状态，也不停止脚本逻辑"),
    ("`GetSiblingIndex()`", "`integer`",
     "获取同级排序索引；返回值范围为 0 到父控件的子控件数量减一"),
    ("`SetSiblingIndex(index)`", "`boolean`",
     "设置同级排序索引；`index` 范围为 0 到父控件的子控件数量减一；数值越大通常越靠后、显示越靠上"),
    ("`SetAsFirstSibling()`", "`boolean`", "移到同级首位"),
    ("`SetAsLastSibling()`", "`boolean`", "移到同级末位"),
], ("方法", "返回值", "说明")))
w()
w("#### (3) 布局与变换")
w()
w("父子层级中的位移、缩放、可见性、Alpha、镜像与裁剪效果由运行时 UI 层级共同决定；"
  "使用组合布局时应验证实际显示结果。")
w()
w(emit_table([
    ("`GetAnchoredPosition()`", "`x, y`",
     "无父层级时，以画布左下为原点获取位置；存在父层级时，获取与父层级中心的相对偏移"),
    ("`SetAnchoredPosition(x, y)`", "—",
     "无父层级时，以画布左下为原点设置位置；存在父层级时，设置与父层级中心的相对偏移"),
    ("`GetSizeDelta()`", "`x, y`", "获取大小"),
    ("`SetSizeDelta(x, y)`", "—", "设置大小"),
    ("`GetAnchorMin()`", "`x, y`", "获取最小锚点"),
    ("`SetAnchorMin(x, y)`", "—", "设置最小锚点"),
    ("`GetAnchorMax()`", "`x, y`", "获取最大锚点"),
    ("`SetAnchorMax(x, y)`", "—", "设置最大锚点"),
    ("`GetPivot()`", "`x, y`", "获取中心"),
    ("`SetPivot(x, y)`", "—", "设置中心"),
    ("`GetLocalScale()`", "`x, y, z`", "获取缩放"),
    ("`SetLocalScale(x, y, z)`", "—", "设置缩放"),
    ("`GetLocalRotation()`", "`x, y, z`", "获取旋转"),
    ("`SetLocalRotation(x, y, z)`", "—", "设置旋转"),
], ("方法", "返回值", "说明")))
w()
w("#### (4) 脚本访问")
w()
w("> ⚠️ 返回的脚本实例可能因销毁而不再存活，使用前检查 `script.alive`。")
w()
w(emit_table([
    ("`GetScriptByPath(scriptPath)`", "`Script`", "按路径获取挂载脚本"),
    ("`GetScript(scriptMappingId)`", "`Script`", "按脚本映射 ID 获取脚本"),
    ("`GetScripts()`", "`Script[]`", "获取控件上全部脚本"),
], ("方法", "返回值", "说明")))
w()
w("#### (5) 键鼠/手柄按键事件")
w()
w(emit_table([
    ("`AddKeyEventListener(eventType, callback)`", "—",
     "注册指定按键事件监听；回调返回 `boolean`；移除单个监听时需保留该回调引用。"
     "同一个容器中，如果交互按键事件被 Lua 回调响应并标记为已处理，容器内的其他按键不会也响应此次按键事件"),
    ("`RemoveKeyEventListener(eventType, callback)`", "—",
     "移除指定按键事件和回调的监听；回调必须与注册时的引用相同"),
    ("`RemoveKeyEventListeners(eventType)`", "—", "移除指定按键事件的全部监听"),
    ("`RemoveAllKeyEventListeners()`", "—", "移除全部按键事件监听"),
], ("方法", "返回值", "说明")))
w()
w("#### (6) 手柄导航事件")
w()
w(emit_table([
    ("`AddNavigationEventListener(eventType, callback)`", "—", "注册指定手柄导航事件监听"),
    ("`RemoveNavigationEventListener(eventType, callback)`", "—", "移除指定手柄导航事件和回调的监听"),
    ("`RemoveNavigationEventListeners(eventType)`", "—", "移除指定手柄导航事件的全部监听"),
    ("`RemoveAllNavigationEventListeners()`", "—", "移除全部手柄导航事件监听"),
], ("方法", "返回值", "说明")))
w()
w("#### (7) 手柄导航配置")
w()
w(emit_table([
    ("`SetControllerNavigation(navigationDir, navigationMode, navigationTarget)`", "—",
     "设置指定方向的导航模式和目标控件；目标可以为 `nil`"),
    ("`GetControllerNavigation(navigationDir)`", "`navigationMode, navigationTarget`",
     "获取指定方向的导航模式和目标控件"),
], ("方法", "返回值", "说明")))
w()

# ---------------------------------------------------------------- 14 Image
w("### 14. ClientUIImageControl")
w()
w("图片控件，用于显示图片并控制颜色、遮罩与填充效果。")
w()
w("#### (1) 字段")
w()
w(emit_table([
    ("`imageSource`", "`ImageSource`", "只读", "图片来源"),
    ("`imageId`", "`integer`", "只读", "图片 ID"),
    ("`imageColor`", "`ColorValue`", "读写", "图片颜色、Tweenable"),
    ("`imageType`", "`ImageType`", "读写", "基础或拉伸类型"),
    ("`enableMask`", "`boolean`", "读写", "是否启用遮罩"),
    ("`enableSoftEdge`", "`boolean`", "读写", "是否启用边缘羽化"),
    ("`softEdgeMode`", "`ImageMaskSoftEdgeMode`", "读写", "边缘羽化模式"),
    ("`softEdgeWidthX`", "`number`", "读写", "水平边缘羽化宽度、Tweenable"),
    ("`softEdgeWidthY`", "`number`", "读写", "垂直边缘羽化宽度、Tweenable"),
    ("`horizontalSoftRange`", "`number`", "读写", "水平边缘羽化范围、Tweenable"),
    ("`verticalSoftRange`", "`number`", "读写", "垂直边缘羽化范围、Tweenable"),
    ("`reverseMaskArea`", "`boolean`", "读写", "是否反转遮罩区域"),
    ("`fillType`", "`ImageFillType`", "读写", "当前填充方式"),
    ("`fillHorizontalType`", "`ImageFillHorizontalType`", "读写", "水平填充方向"),
    ("`fillVerticalType`", "`ImageFillVerticalType`", "读写", "垂直填充方向"),
    ("`fillRadial90Type`", "`ImageFillRadial90Type`", "读写", "90度环绕起点"),
    ("`fillRadialType`", "`ImageFillRadialType`", "读写", "180度环绕和 360度环绕的起点"),
    ("`fillAmount`", "`number`", "读写", "进度、Tweenable"),
], ("字段", "类型", "访问", "说明")))
w()
w("#### (2) 方法")
w()
w(emit_table([
    ("`SetImage(imageSource, imageId)`", "—", "设置图片来源与图片 ID"),
    ("`SetSoftEdgeWidth(widthX, widthY)`", "—", "设置水平与垂直边缘羽化宽度"),
    ("`SetFillUnused()`", "—", "设置为不使用填充"),
    ("`SetFillHorizontal(fillHorizontalType, fillAmount)`", "—", "设置水平填充"),
    ("`SetFillVertical(fillVerticalType, fillAmount)`", "—", "设置垂直填充"),
    ("`SetFillRadial90(fillRadial90Type, fillAmount)`", "—", "设置 90度环绕填充"),
    ("`SetFillRadial180(fillRadialType, fillAmount)`", "—", "设置 180度环绕填充"),
    ("`SetFillRadial360(fillRadialType, fillAmount)`", "—", "设置 360度环绕填充"),
], ("方法", "返回值", "说明")))
w()

# ---------------------------------------------------------------- 15 TextBox
w("### 15. ClientUITextBoxControl")
w()
w("文本框控件，用于显示普通文本。")
w()
w("#### (1) 字段")
w()
w(emit_table([
    ("`text`", "`string`", "读写", "显示文本"),
    ("`fontSize`", "`integer`", "读写", "字号，Tweenable"),
    ("`fontColor`", "`ColorValue`", "读写", "字色，Tweenable"),
    ("`bgColor`", "`ColorValue`", "读写", "背景色，Tweenable"),
    ("`enableOutline`", "`boolean`", "读写", "是否启用描边"),
    ("`outlineColor`", "`ColorValue`", "读写", "描边色，Tweenable"),
    ("`horizontalAlignment`", "`TextHorizontalAlignment`", "读写", "水平对齐"),
    ("`verticalAlignment`", "`TextVerticalAlignment`", "读写", "垂直对齐"),
    ("`adaptiveFontSize`", "`boolean`", "读写", "字号自适应"),
    ("`minimumFontSize`", "`integer`", "读写", "字号自适应的最小字号，Tweenable"),
], ("字段", "类型", "访问", "说明")))
w()

# ---------------------------------------------------------------- 16 TextWindow
w("### 16. ClientUITextWindowControl")
w()
w("文本视窗控件，用于显示可滚动的文本。")
w()
w("#### (1) 字段")
w()
w(emit_table([
    ("`interactable`", "`boolean`", "读写",
     "是否可交互；与 `showScrollBar` 同时为 `false` 时，手柄无法滚动文本视窗"),
    ("`showScrollBar`", "`boolean`", "读写", "是否显示滚动条"),
    ("`text`", "`string`", "读写", "显示文本"),
    ("`fontSize`", "`integer`", "读写", "字号，Tweenable"),
    ("`fontColor`", "`ColorValue`", "读写", "字色，Tweenable"),
    ("`bgColor`", "`ColorValue`", "读写", "背景色，Tweenable"),
    ("`enableOutline`", "`boolean`", "读写", "是否启用描边"),
    ("`outlineColor`", "`ColorValue`", "读写", "描边色，Tweenable"),
    ("`horizontalAlignment`", "`TextHorizontalAlignment`", "读写", "水平对齐"),
    ("`verticalAlignment`", "`TextVerticalAlignment`", "读写", "垂直对齐"),
    ("`adaptiveFontSize`", "`boolean`", "读写", "字号自适应"),
    ("`minimumFontSize`", "`integer`", "读写", "字号自适应的最小字号，Tweenable"),
], ("字段", "类型", "访问", "说明")))
w()

# ---------------------------------------------------------------- 17 PresetButton
w("### 17. ClientUIPresetButtonControl")
w()
w("预设按钮控件，提供按钮交互与光标事件监听。")
w()
w("#### (1) 字段")
w()
w(emit_table([
    ("`interactable`", "`boolean`", "读写", "是否可交互"),
    ("`clickAudioId`", "`integer`", "读写", "点击音效 ID"),
    ("`raycastTarget`", "`boolean`", "读写", "可被光标射线检测"),
], ("字段", "类型", "访问", "说明")))
w()
w("#### (2) 方法")
w()
w(emit_table([
    ("`AddCursorEventListener(eventType, callback)`", "—",
     "注册指定光标事件监听；回调接收 `CursorEventData`"),
    ("`RemoveCursorEventListener(eventType, callback)`", "—", "移除指定光标事件和回调的监听"),
    ("`RemoveCursorEventListeners(eventType)`", "—", "移除指定光标事件的全部监听"),
    ("`RemoveAllCursorEventListeners()`", "—", "移除全部光标事件监听"),
    ("`SimulateCursorClick()`", "—",
     "按顺序模拟 `CursorDown`、`CursorUp` 与 `CursorClick`"),
], ("方法", "返回值", "说明")))
w()

# ---------------------------------------------------------------- 18 CursorEventArea
w("### 18. ClientUICursorEventAreaControl")
w()
w("光标检测区域控件，检测该控件区域内的光标事件。")
w()
w("#### (1) 字段")
w()
w(emit_table([
    ("`raycastTarget`", "`boolean`", "读写", "可被光标射线检测"),
], ("字段", "类型", "访问", "说明")))
w()
w("#### (2) 方法")
w()
w(emit_table([
    ("`AddCursorEventListener(eventType, callback)`", "—",
     "注册指定光标事件监听；回调接收 `CursorEventData`"),
    ("`RemoveCursorEventListener(eventType, callback)`", "—", "移除指定光标事件和回调的监听"),
    ("`RemoveCursorEventListeners(eventType)`", "—", "移除指定光标事件的全部监听"),
    ("`RemoveAllCursorEventListeners()`", "—", "移除全部光标事件监听"),
    ("`SimulateCursorClick()`", "—",
     "按顺序模拟 `CursorDown`、`CursorUp` 与 `CursorClick`"),
], ("方法", "返回值", "说明")))
w()

# ---------------------------------------------------------------- 19 CursorEventData
w("### 19. CursorEventData")
w()
w("#### (1) 字段")
w()
w(emit_table([
    ("`dragging`", "`boolean`", "只读", "当前是否在拖拽"),
    ("`touchId`", "`integer`", "只读", "触点 ID"),
], ("字段", "类型", "访问", "说明")))
w()
w("#### (2) 方法")
w()
w(emit_table([
    ("`CursorEventData:GetUIPos()`", "`x, y: number`",
     "以画布左下角为原点，获取当前屏幕 UI 坐标。坐标比例和布局坐标一致"),
    ("`CursorEventData:GetPressUIPos()`", "`x, y: number`", "获取按下时的屏幕 UI 坐标"),
    ("`CursorEventData:GetUIPosDelta()`", "`x, y: number`", "获取本次事件的屏幕 UI 位移"),
], ("方法", "返回值", "说明")))
w()

# ---------------------------------------------------------------- 20 GridScroller
w("### 20. ClientUIGridScrollerControl")
w()
w("网格视窗控件，用于显示和滚动复用列表项。")
w()
w("#### (1) 字段")
w()
w(emit_table([
    ("`itemCount`", "`integer`", "只读", "列表项数量"),
    ("`itemPrefabIndex`", "`integer`", "读写", "列表项控件模板索引"),
    ("`raycastTarget`", "`boolean`", "读写", "可被光标射线检测"),
    ("`showScrollBar`", "`boolean`", "读写", "是否显示滚动条"),
    ("`interactable`", "`boolean`", "读写", "是否可交互"),
    ("`scrollDirection`", "`ScrollDirection`", "只读", "滚动方向"),
    ("`layoutConstraint`", "`ScrollLayoutConstraint`", "只读", "列表项布局约束"),
    ("`layoutConstraintFixedCount`", "`number`", "只读", "固定布局时每行或每列的列表项数量"),
    ("`scrollProgress`", "`number`", "读写", "滚动进度、Tweenable"),
], ("字段", "类型", "访问", "说明")))
w()
w("#### (2) 方法")
w()
w("> 列表项索引以运行时传入和返回的 `index` 为准。")
w()
w(emit_table([
    ("`RefreshItems(itemCount, refreshCallback)`", "—",
     "刷新列表项并逐项调用回调；刷新回调形式为 `fun(control: ClientUIBaseControl, index: integer)`，"
     "参数依次为当前列表项控件和列表项索引"),
    ("`GetItemIndex(control)`", "`integer`", "获取列表项控件的索引"),
    ("`GetItemSize()`", "`x, y: number`", "获取列表项宽度与高度"),
    ("`GetItemSpacing()`", "`x, y: number`", "获取列表项的水平与垂直间距"),
    ("`GetPadding()`", "`top, bottom, left, right: number`", "获取内容区域的上、下、左、右内边距"),
    ("`ScrollToItemAt(index, scrollAlignType)`", "—",
     "滚动到索引为 `index` 的列表项，并按 `scrollAlignType` 对齐"),
    ("`GetContentLength()`", "`number`", "获取滚动内容在滚动方向上的长度"),
], ("方法", "返回值", "说明")))
w()

# ---------------------------------------------------------------- 21 KeyHint
w("### 21. ClientUIKeyHintControl")
w()
w("按键提示控件，根据当前输入设备显示对应按键。")
w()
w("#### (1) 字段")
w()
w(emit_table([
    ("`keyboardKeyCode`", "`KeyboardKeyCode`", "读写", "键鼠按键枚举值"),
    ("`controllerKeyCode`", "`ControllerKeyCode`", "读写", "手柄按键枚举值"),
], ("字段", "类型", "访问", "说明")))
w()

# ---------------------------------------------------------------- 22 Animation
w("### 22. ClientUIAnimationControl")
w()
w("界面动效控件，用于播放或停止已配置的动效。")
w()
w("#### (1) 字段")
w()
w(emit_table([
    ("`animationId`", "`integer`", "读写", "动效 ID"),
    ("`playSoundEffect`", "`boolean`", "读写", "是否播放动效音效"),
    ("`layer`", "`UIAnimationLayer`", "读写", "动效层级"),
], ("字段", "类型", "访问", "说明")))
w()
w("#### (2) 方法")
w()
w(emit_table([
    ("`PlayAnimation()`", "—", "播放界面动效"),
    ("`StopAnimation()`", "—", "停止界面动效"),
], ("方法", "返回值", "说明")))
w()

# ---------------------------------------------------------------- 23 FullscreenAnimation
w("### 23. ClientUIFullscreenAnimationControl")
w()
w("全屏动效控件，用于显示覆盖界面的已配置动效。")
w()
w("#### (1) 字段")
w()
w(emit_table([
    ("`animationId`", "`integer`", "读写", "动效 ID"),
    ("`playSoundEffect`", "`boolean`", "读写", "是否播放动效音效"),
], ("字段", "类型", "访问", "说明")))
w()

# ---------------------------------------------------------------- 24 Container
w("### 24. ClientUIContainerControl")
w()
w("容器节点控件，用于组织子控件。")
w()
w("#### (1) 字段")
w()
w(emit_table([
    ("`isolateNavigation`", "`boolean`", "读写", "是否隔离手柄导航"),
    ("`disableKeyEventPassthrough`", "`boolean`", "读写", "是否屏蔽按键事件穿透"),
    ("`disableCursorEventPassthrough`", "`boolean`", "读写", "是否屏蔽区域内点击事件穿透"),
    ("`showCursor`", "`boolean`", "读写",
     "是否显示常驻光标；**CursorEvent 相关方法都需设置该参数为真后才可正常使用**"),
], ("字段", "类型", "访问", "说明")))
w()

# ---------------------------------------------------------------- 25 Reference
w("### 25. ClientUIReferenceControl")
w()
w("模板引用控件，用于引用已配置的控件模板。")
w()
w("#### (1) 字段")
w()
w(emit_table([
    ("`referencedPrefabIndex`", "`integer`", "只读", "引用控件模板索引"),
], ("字段", "类型", "访问", "说明")))
w()

# ---------------------------------------------------------------- 26 按键输入
w("### 26. 按键输入")
w()

KBD_ROWS = [
    ("CraftspersonKey1", "奇匠按键1", "1"), ("CraftspersonKey2", "奇匠按键2", "2"),
    ("CraftspersonKey3", "奇匠按键3", "3"), ("CraftspersonKey4", "奇匠按键4", "4"),
    ("CraftspersonKey5", "奇匠按键5", "5"), ("CraftspersonKey6", "奇匠按键6", "6"),
    ("CraftspersonKey7", "奇匠按键7", "7"), ("CraftspersonKey8", "奇匠按键8", "8"),
    ("CraftspersonKey9", "奇匠按键9", "9"), ("CraftspersonKey10", "奇匠按键10", "0"),
    ("CraftspersonKey11", "奇匠按键11", "U"), ("CraftspersonKey12", "奇匠按键12", "Z"),
    ("CraftspersonKey13", "奇匠按键13", "Y"), ("CraftspersonKey14", "奇匠按键14", "G"),
    ("CraftspersonKey15", "奇匠按键15", "H"), ("CraftspersonKey16", "奇匠按键16", "I"),
    ("CraftspersonKey17", "奇匠按键17", "O"), ("CraftspersonKey18", "奇匠按键18", "P"),
    ("CraftspersonKey19", "奇匠按键19", "J"), ("CraftspersonKey20", "奇匠按键20", "K"),
    ("CraftspersonKey21", "奇匠按键21", "L"), ("CraftspersonKey22", "奇匠按键22", "V"),
    ("CraftspersonKey23", "奇匠按键23", "F5"), ("CraftspersonKey24", "奇匠按键24", "F6"),
    ("CraftspersonKey25", "奇匠按键25", "F7"), ("CraftspersonKey26", "奇匠按键26", "F8"),
    ("CraftspersonKey27", "奇匠按键27", "F9"), ("CraftspersonKey28", "奇匠按键28", "F10"),
    ("CraftspersonKey29", "奇匠按键29", "`"), ("CraftspersonKey30", "奇匠按键30", "-"),
    ("CraftspersonKey31", "奇匠按键31", "="), ("CraftspersonKey32", "奇匠按键32", "["),
    ("CraftspersonKey33", "奇匠按键33", ","), ("CraftspersonKey34", "奇匠按键34", "."),
    ("CraftspersonKey35", "奇匠按键35", "/"), ("CraftspersonKey36", "奇匠按键36", "↑"),
    ("CraftspersonKey37", "奇匠按键37", "↓"), ("CraftspersonKey38", "奇匠按键38", "←"),
    ("CraftspersonKey39", "奇匠按键39", "→"), ("CraftspersonKey40", "奇匠按键40", "右Ctrl"),
    ("CraftspersonKey41", "奇匠按键41", "右Shift"), ("CraftspersonKey42", "奇匠按键42", "Backspace"),
    ("CraftspersonKey43", "奇匠按键43", "CapsLock"),
    ("MoveForwardKey", "向前移动", "W"), ("MoveBackwardKey", "向后移动", "S"),
    ("MoveLeftKey", "向左移动", "A"), ("MoveRightKey", "向右移动", "D"),
    ("SwitchToWalkOrRunKey", "切换行走/奔跑状态", "左Ctrl"),
    ("SprintKey", "冲刺", "鼠标右键"), ("JumpKey", "跳跃", "Space"),
    ("DropKey", "落下", "X"), ("OpenShortcutWheelKey", "呼出快捷轮盘", "Tab"),
    ("InteractKey", "拾取/交互", "F"), ("NormalAttackKey", "普通攻击", "鼠标左键"),
    ("CharacterSkill1Key", "角色技能1", "E"), ("CharacterSkill2Key", "角色技能2", "Q"),
    ("CharacterSkill3Key", "角色技能3", "R"), ("CharacterSkill4Key", "角色技能4", "T"),
    ("None", "无", "无"),
]
CTRL_ROWS = [
    ("CraftspersonKey1", "奇匠按键1", "十字键左"), ("CraftspersonKey2", "奇匠按键2", "十字键下"),
    ("CraftspersonKey3", "奇匠按键3", "LT"), ("CraftspersonKey4", "奇匠按键4", "LB + Y"),
    ("CraftspersonKey5", "奇匠按键5", "LB + X"), ("CraftspersonKey6", "奇匠按键6", "LB + A"),
    ("CraftspersonKey7", "奇匠按键7", "LB + 十字键上"), ("CraftspersonKey8", "奇匠按键8", "LB + 十字键右"),
    ("CraftspersonKey9", "奇匠按键9", "LB + 十字键左"), ("CraftspersonKey10", "奇匠按键10", "LB + 十字键下"),
    ("CraftspersonKey11", "奇匠按键11", "LB + RB"), ("CraftspersonKey12", "奇匠按键12", "LB + LT"),
    ("CraftspersonKey13", "奇匠按键13", "LB + RT"), ("CraftspersonKey14", "奇匠按键14", "LB + LS(按下)"),
    ("SprintKey", "冲刺", "RB"), ("JumpKey", "跳跃", "A"),
    ("InteractKey", "拾取/交互", "X"), ("NormalAttackKey", "普通攻击", "B"),
    ("CharacterSkill1Key", "角色技能1", "RT"), ("CharacterSkill2Key", "角色技能2", "Y"),
    ("CharacterSkill3Key", "角色技能3", "十字键上"), ("CharacterSkill4Key", "角色技能4", "十字键右"),
    ("MenuConfirmKey", "菜单确认", "—（由手柄导航配置决定）"),
    ("MenuBackKey", "菜单返回", "—（由手柄导航配置决定）"),
    ("None", "无", "无"),
]

w("#### (1) `Enum.KeyboardKeyCode`")
w()
w(emit_table([(f"`Enum.KeyboardKeyCode{k}`", v, f"`{p}`") for k, v, p in KBD_ROWS],
             ("枚举名", "说明", "默认物理键")))
w()
w("#### (2) `Enum.ControllerKeyCode`")
w()
w(emit_table([(f"`Enum.ControllerKeyCode{k}`", v, f"`{p}`") for k, v, p in CTRL_ROWS],
             ("枚举名", "说明", "默认物理键")))
w()

# --- KeyEventType: generated from combos
w("#### (3) `Enum.KeyEventType`")
w()
w("键鼠事件枚举名为 `Keyboard<Key>Down` / `Keyboard<Key>Up`，"
  "手柄事件枚举名为 `Controller<Key>Down` / `Controller<Key>Up`。")
w()

KBD_EVT = [k for k, _, _ in KBD_ROWS if k != "None"]
CTRL_EVT = [k for k, _, _ in CTRL_ROWS if k != "None"]

evt_rows = []
for k in KBD_EVT:
    label = dict((a, b) for a, b, c in KBD_ROWS)[k]
    evt_rows.append((f"`Enum.KeyEventTypeKeyboard{k}Down`", f"键鼠：{label}（按下）"))
    evt_rows.append((f"`Enum.KeyEventTypeKeyboard{k}Up`", f"键鼠：{label}（抬起）"))
for k in CTRL_EVT:
    label = dict((a, b) for a, b, c in CTRL_ROWS)[k]
    evt_rows.append((f"`Enum.KeyEventTypeController{k}Down`", f"手柄：{label}（按下）"))
    evt_rows.append((f"`Enum.KeyEventTypeController{k}Up`", f"手柄：{label}（抬起）"))

w("<details>")
w("<summary>展开全部按键事件枚举（共 %d 项）</summary>" % len(evt_rows))
w()
w(emit_table(evt_rows, ("枚举名", "说明")))
w()
w("</details>")
w()

# ---------------------------------------------------------------- write
md = "\n".join(L)
path = os.path.join(OUT, "client_control_api.md")
io.open(path, "w", encoding="utf-8").write(md)
print("OK ->", path, len(md), "chars,", md.count("\n"), "lines")