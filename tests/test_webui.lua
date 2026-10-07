--[[============================================================================
  模拟千星引擎环境，端到端测试整个 webui 库
  用真机实测的行为（R1-R14）来构建 mock
==============================================================================]]

-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

--=============================================================================
-- Mock 引擎
--=============================================================================

local createdCount = 0
local destroyedCount = 0
local allControls = {}

local function makeControl(kind, parent)
  createdCount = createdCount + 1
  local c = {
    _kind = kind,
    name = kind,
    -- 布局字段
    anchorMinX=0.5, anchorMinY=0.5, anchorMaxX=0.5, anchorMaxY=0.5,
    pivotX=0.5, pivotY=0.5,
    anchoredPositionX=0, anchoredPositionY=0,
    sizeDeltaX=100, sizeDeltaY=100,
    visible=true, active=true,
    -- 视觉
    imageColor=nil, bgColor=nil, fontColor=nil, text=nil, fontSize=14,
    horizontalAlignment=nil,
    -- 遮罩
    enableMask=false, reverseMaskArea=false,
    -- 光标
    showCursor=false,
    _children = {},
    _cursorListeners = {},
    _parent = parent,
  }

  -- 按类型限制可用字段（模拟真机"字段按类型封死"）
  if kind ~= "textbox" then
    c.bgColor = nil; c.text = nil; c.fontColor = nil
  end
  if kind ~= "image" then
    c.imageColor = nil; c.enableMask = nil; c.reverseMaskArea = nil
  end

  -- 方法
  c.SetActive = function(self, v) self.active = v end
  c.SetVisible = function(self, v) self.visible = v end
  c.GetChildren = function(self) return self._children end
  c.SetAnchoredPosition = function(self, x, y) self.anchoredPositionX=x; self.anchoredPositionY=y end
  c.SetSizeDelta = function(self, w, h) self.sizeDeltaX=w; self.sizeDeltaY=h end
  c.RemoveAllCursorEventListeners = function(self) self._cursorListeners = {} end

  -- 只有 button / area 有光标事件
  if kind == "button" or kind == "area" then
    c.AddCursorEventListener = function(self, ev, cb)
      self._cursorListeners[#self._cursorListeners+1] = {ev=ev, cb=cb}
    end
    c.SimulateCursorClick = function(self)
      for _, l in ipairs(self._cursorListeners) do
        if l.ev == "CursorClick" then
          l.cb({ GetUIPos = function() return 10, 20 end,
                 GetPressUIPos = function() return 10, 20 end,
                 GetUIPosDelta = function() return 0, 0 end,
                 dragging = false, touchId = -1 })
        end
      end
    end
  end

  if parent then parent._children[#parent._children+1] = c end
  allControls[#allControls+1] = c
  return c
end

-- 模板索引（模拟编辑器里配好的模板）
local PREFABS = { container = 1, textbox = 2, button = 3, image = 4 }

game = {
  InstantiateClientUIControl = function(idx, parent)
    local kind = "container"
    for k, v in pairs(PREFABS) do if v == idx then kind = k end end
    return makeControl(kind, parent)
  end,
  DestroyClientUIControl = function(c) destroyedCount = destroyedCount + 1 end,
  GetUICanvasSize = function() return 1600, 900 end,
  GetClientUIRoots = function() return {} end,
  TweenSequence = function()
    local s = {}
    s.AppendInterval = function() return s end
    s.AppendCallback = function() return s end
    s.Play = function() return s end
    return s
  end,
}

Color = {
  FromRGBA = function(r,g,b,a) return string.format("C(%d,%d,%d,%d)",r,g,b,a) end,
  FromRGB  = function(r,g,b)   return string.format("C(%d,%d,%d,255)",r,g,b) end,
}

Enum = {
  CursorEventType = {
    CursorDown="CursorDown", CursorUp="CursorUp", CursorEnter="CursorEnter",
    CursorExit="CursorExit", CursorClick="CursorClick",
    CursorBeginDrag="CursorBeginDrag", CursorDrag="CursorDrag",
    CursorEndDrag="CursorEndDrag",
  },
  TextHorizontalAlignmentLeft="L", TextHorizontalAlignmentMiddle="C",
  TextHorizontalAlignmentRight="R",
}

--=============================================================================
-- 测试
--=============================================================================

local webui = require('webui')

--=============================================================================
-- 断言框架（与 test_wrap.lua 一致）
--=============================================================================
local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-28s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-28s %s", name, detail or "")) end
end

-- 根控件
local root = makeControl("container", nil)
script = { object = root, name = "webui_test" }

print("========== 端到端测试 ==========")
print()

local clicked = 0
local hovered = 0

local ui = webui.new({
  root = root,
  prefabs = PREFABS,
  handlers = {
    onClick = function(info)
      clicked = clicked + 1
      print(string.format("  >>> onClick 触发! 坐标=(%.0f,%.0f) 第 %d 次",
          info.x or -1, info.y or -1, clicked))
    end,
    onEnter = function(info)
      hovered = hovered + 1
    end,
  },
})

local htmlSrc = [[
<style>
  .panel { width: 400px; padding: 20px; background-color: #222222; }
  .title { height: 38px; font-size: 20px; color: #ffffff; }
  .row   { display: flex; gap: 12px; }
  .btn   { width: 120px; height: 40px; background-color: #3a7bd5; }
</style>
<div class="panel">
  <div class="title">设置面板</div>
  <div class="row">
    <div class="btn" onclick="onClick" onmouseenter="onEnter">确定</div>
    <div class="btn" onclick="onClick">取消</div>
  </div>
</div>
]]

ui:render(htmlSrc)

print("  DOM 统计:", (function()
  local dom = require('webui_dom')
  local st = dom.stats(ui.doc)
  return string.format("元素=%d 文本=%d 深度=%d", st.elements, st.texts, st.maxDepth)
end)())
print("  渲染统计:", ui.rendered:statsText())
print("  事件绑定数:", ui.boundCount)
print("  创建的引擎控件数:", createdCount)
print()

--=============================================================================
-- 断言：首次渲染的契约
--=============================================================================
do
  local dom = require('webui_dom')
  local st = dom.stats(ui.doc)
  -- HTML 里 6 个元素：<style> / panel / title / row / btn / btn
  -- ★ 量出来的值，不是猜的（<style> 本身也算一个元素）
  check("DOM 元素数 = 6", st.elements == 6,
      string.format("元素=%d (期望 6)", st.elements))

  -- 需求：HTML 有内容就必须真的建出控件来
  -- （历史上踩过"一个控件都没建出来、画面空白但日志正常"）
  check("控件数 > 0 且创建成功", ui.rendered.stats.created > 0,
      string.format("created=%d", ui.rendered.stats.created))

  -- 5 个 DOM 元素 -> 5 个视觉控件 + 2 个按钮覆盖层 = 7
  check("控件数 = 7", ui.rendered.stats.created == 7,
      string.format("created=%d (期望 7)", ui.rendered.stats.created))

  -- live 应与创建的视觉控件数一致（覆盖层不算 node）
  local live = 0
  for _ in pairs(ui.rendered.live) do live = live + 1 end
  check("live 控件 = 5", live == 5, string.format("live=%d (期望 5)", live))

  -- 2 个 btn 各有 onclick -> 2 条；再加 1 条 onmouseenter = 3
  check("事件绑定数 = 3", ui.boundCount == 3,
      string.format("bound=%d (期望 3)", ui.boundCount))

  -- ★ 真机陷阱：新控件 active 默认 false，必须 SetActive(true) 才可见。
  --   所有建出来的控件都必须是 active，否则界面上什么都看不到。
  local inactive = {}
  for i, c in ipairs(allControls) do
    if c.active ~= true then inactive[#inactive+1] = i .. ":" .. c._kind end
  end
  check("全部控件 active=true", #inactive == 0,
      #inactive == 0 and ("共 " .. #allControls .. " 个全部激活")
                    or ("未激活: " .. table.concat(inactive, ",")))

  -- 根控件也被渲染器设为铺满画布
  check("根控件铺满画布", math.abs(root.sizeDeltaX - 1600) < 1
                      and math.abs(root.sizeDeltaY - 900) < 1,
      string.format("size=(%.0fx%.0f) (期望 1600x900)", root.sizeDeltaX, root.sizeDeltaY))
end
print()

print("========== 控件树 ==========")
local function dumpControl(c, depth)
  depth = depth or 0
  if depth > 6 then return end
  local pad = string.rep("  ", depth + 1)
  print(string.format("%s%-10s pos=(%.0f,%.0f) size=(%.0fx%.0f) %s%s",
      pad, c._kind,
      c.anchoredPositionX, c.anchoredPositionY,
      c.sizeDeltaX, c.sizeDeltaY,
      c.bgColor and ("bg=" .. c.bgColor .. " ") or "",
      c.text and ('text="' .. c.text .. '"') or ""))
  for _, k in ipairs(c._children) do dumpControl(k, depth+1) end
end
for _, c in ipairs(root._children) do dumpControl(c, 0) end

--=============================================================================
-- 断言：控件树结构 + 字段写入
--=============================================================================
do
  -- 控件树的根：root 下只有一个 panel
  check("root 只有 1 个子控件", #root._children == 1,
      string.format("实际 %d 个", #root._children))

  local panel = root._children[1]
  -- .panel 有 background-color -> 必须是 textbox（容器没有 bgColor 字段）
  check("panel 是 textbox", panel._kind == "textbox", "kind=" .. panel._kind)

  -- .panel { width:400px; padding:20px } -> 400 宽
  check("panel 宽 = 400", math.abs(panel.sizeDeltaX - 400) < 1,
      string.format("w=%.1f (期望 400)", panel.sizeDeltaX))

  -- 高 = title 38 + row 40 + 上下 padding 40 = 118
  check("panel 高 = 118", math.abs(panel.sizeDeltaY - 118) < 1,
      string.format("h=%.1f (期望 118)", panel.sizeDeltaY))

  -- background-color: #222222 -> bgColor 必须真的写进去了
  -- （写错控件类型会静默失败，所以这条很关键）
  check("panel bgColor 已写入", panel.bgColor ~= nil,
      "bg=" .. tostring(panel.bgColor))

  -- 布局原点在左下、Y 向上；子控件位置 = 父中心 + anchoredPosition。
  -- panel.box = (0,0,400,118)（左上原点），中心 = (200,59)
  -- 父是根控件（画布 1600x900），中心 = (800,450)
  --   dx = 200 - 800   = -600
  --   dy = 450 - 59    =  391   （Y 翻转）
  check("panel 锚点位置正确", math.abs(panel.anchoredPositionX - (-600)) < 1
                           and math.abs(panel.anchoredPositionY - 391) < 1,
      string.format("pos=(%.1f,%.1f) (期望 -600,391)", panel.anchoredPositionX, panel.anchoredPositionY))

  -- panel 有 2 个子元素：title 和 row
  check("panel 有 2 个子控件", #panel._children == 2,
      string.format("实际 %d 个", #panel._children))

  local title = panel._children[1]
  local row   = panel._children[2]

  -- .title 有文字 -> textbox
  check("title 是 textbox", title._kind == "textbox", "kind=" .. title._kind)
  -- ★ 文字必须真的写进去（写错控件类型会静默失败）
  check("title text 已写入", title.text == "设置面板",
      'text="' .. tostring(title.text) .. '" (期望 "设置面板")')
  -- .title { height:38px } 宽度被 panel 内容区撑满：400-40=360
  check("title 高 = 38", math.abs(title.sizeDeltaY - 38) < 1,
      string.format("h=%.1f (期望 38)", title.sizeDeltaY))
  check("title 宽 = 360", math.abs(title.sizeDeltaX - 360) < 1,
      string.format("w=%.1f (期望 360)", title.sizeDeltaX))
  -- font-size: 20px -> ★ 真机要求整数
  check("title fontSize = 20", title.fontSize == 20,
      "fontSize=" .. tostring(title.fontSize))
  check("fontSize 是整数", type(title.fontSize) == "number"
                        and title.fontSize == math.floor(title.fontSize),
      "fontSize=" .. tostring(title.fontSize))

  -- ★ 真机硬约束：文字框高 >= 字号 × 1.9，否则引擎把字压没（文字凭空消失）
  --   本用例的 .title{height:38px;font-size:20px} -> 比值 1.90，达标。
  --   （原夹具是 30px/20px = 1.50，违反约束，会让"设置面板"在真机上消失，
  --     已按 docs/引擎能力与限制.md §4.4 调高到 38px。）
  local ratio = title.sizeDeltaY / (title.fontSize or 1)
  check("title 框高/字号 >= 1.9（真机硬约束）", ratio >= 1.9,
      string.format("比值=%.2f (要求 >= 1.9)", ratio))
  check("title 字号为正整数", title.fontSize == 20
                          and title.fontSize == math.floor(title.fontSize),
      string.format("fontSize=%s 比值=%.2f", tostring(title.fontSize), ratio))

  -- .row { display:flex } 无文字无背景 -> 容器（容器不显示，装子控件）
  check("row 是 container", row._kind == "container", "kind=" .. row._kind)

  -- ★ 真机陷阱：容器写 bgColor/text 会静默失败（字段按类型封死）
  check("container 无 bgColor 字段", row.bgColor == nil,
      "bg=" .. tostring(row.bgColor))
  check("container 无 text 字段", row.text == nil,
      "text=" .. tostring(row.text))

  -- flex + gap:12px，两侧 120 -> 总宽 252；容器宽度应为内容宽度
  check("row 有 2 个子控件", #row._children == 2,
      string.format("实际 %d 个", #row._children))

  local b1, b2 = row._children[1], row._children[2]
  -- .btn 有文字+背景 -> textbox
  check("btn1 是 textbox", b1._kind == "textbox", "kind=" .. b1._kind)
  check("btn1 尺寸 = 120x40", math.abs(b1.sizeDeltaX - 120) < 1
                           and math.abs(b1.sizeDeltaY - 40) < 1,
      string.format("size=(%.0fx%.0f)", b1.sizeDeltaX, b1.sizeDeltaY))
  check("btn1 text 已写入", b1.text == "确定", 'text="' .. tostring(b1.text) .. '"')
  check("btn1 bgColor 已写入", b1.bgColor ~= nil, "bg=" .. tostring(b1.bgColor))
  check("btn2 text 已写入", b2.text == "取消", 'text="' .. tostring(b2.text) .. '"')

  -- gap:12px -> 两个按钮中心间距 = 120 + 12 = 132
  local d = b2.anchoredPositionX - b1.anchoredPositionX
  check("btn 间距 = 132 (gap 12)", math.abs(d - 132) < 1,
      string.format("dx=%.1f (期望 132)", d))
  -- 同一行 -> Y 相同
  check("两个 btn 同一行", math.abs(b1.anchoredPositionY - b2.anchoredPositionY) < 0.1,
      string.format("y1=%.1f y2=%.1f", b1.anchoredPositionY, b2.anchoredPositionY))

  -- ★★ 双层架构：可点击元素 = 视觉层(textbox) + 交互层(button 覆盖)
  --    因为没有一个控件同时具备"可见外观"和"可点击"。
  check("btn1 挂了 button 覆盖层", #b1._children == 1
       and b1._children[1]._kind == "button",
      string.format("子控件=%d 个", #b1._children))
  if #b1._children == 1 then
    local hot = b1._children[1]
    -- 覆盖层必须铺满视觉层，否则点击热区对不上
    check("覆盖层铺满视觉层", math.abs(hot.sizeDeltaX - b1.sizeDeltaX) < 1
                           and math.abs(hot.sizeDeltaY - b1.sizeDeltaY) < 1,
        string.format("hot=(%.0fx%.0f) vs 视觉层=(%.0fx%.0f)",
            hot.sizeDeltaX, hot.sizeDeltaY, b1.sizeDeltaX, b1.sizeDeltaY))
    -- 覆盖层居中于父
    check("覆盖层居中于父", math.abs(hot.anchoredPositionX) < 0.1
                         and math.abs(hot.anchoredPositionY) < 0.1,
        string.format("pos=(%.1f,%.1f)", hot.anchoredPositionX, hot.anchoredPositionY))
    -- ★ 覆盖层也必须 active，否则点击收不到
    check("覆盖层 active=true", hot.active == true, "active=" .. tostring(hot.active))
  end

  -- ★ 只有 button/area 有光标事件；textbox 没有（双层架构的原因）
  check("textbox 无光标监听接口", type(b1.AddCursorEventListener) ~= "function",
      "type=" .. type(b1.AddCursorEventListener))
end
print()
print("========== 触发事件 ==========")
-- 找到带 onclick 的控件并模拟点击
local fired = 0
for _, c in ipairs(allControls) do
  if #c._cursorListeners > 0 then
    pcall(function() c:SimulateCursorClick() end)
    fired = fired + 1
  end
end
print(string.format("  向 %d 个控件发送了模拟点击", fired))
print(string.format("  onClick 触发 %d 次", clicked))

--=============================================================================
-- 断言：事件派发
--=============================================================================
do
  -- HTML 里 2 个 onclick -> 2 个按钮覆盖层接了 CursorClick
  check("2 个控件接了点击事件", fired == 2,
      string.format("fired=%d (期望 2)", fired))
  check("onClick 触发 2 次", clicked == 2,
      string.format("clicked=%d (期望 2)", clicked))

  -- ★ 回归：复用控件不能累积监听器（历史上第 10 次渲染会有 10 个监听）
  local maxL = 0
  for _, c in ipairs(allControls) do
    if #c._cursorListeners > maxL then maxL = #c._cursorListeners end
  end
  check("单个控件监听数 <= 2", maxL <= 2,
      string.format("最大 %d 个 (btn1 有 2 个属性: onclick+onmouseenter)", maxL))
end

print()
print("========== 二次渲染（diff 测试）==========")
local before = createdCount
ui:flush()
print(string.format("  再次 flush: 新建控件 %d 个 (应为 0，说明复用了)",
    createdCount - before))
print("  ", ui.rendered:statsText())

--=============================================================================
-- 断言：flush 复用（不新建）
--=============================================================================
do
  -- ★ 核心契约：DOM 没变时 flush 必须复用，不能每帧重建
  --   否则真机上会越来越卡（历史上踩过 created 持续增长）
  check("flush 不新建控件", createdCount - before == 0,
      string.format("新建 %d 个 (期望 0)", createdCount - before))

  -- live 数保持不变
  local live = 0
  for _ in pairs(ui.rendered.live) do live = live + 1 end
  check("flush 后 live 仍为 5", live == 5, string.format("live=%d", live))

  -- ★ 复用后必须重新 active（真机陷阱：复用后不 SetActive 就不可见）
  local inactive = {}
  for i, c in ipairs(allControls) do
    if c.active ~= true then inactive[#inactive+1] = i .. ":" .. c._kind end
  end
  check("复用后控件仍 active", #inactive == 0,
      #inactive == 0 and ("共 " .. #allControls .. " 个全部激活")
                    or ("未激活: " .. table.concat(inactive, ",")))
end

print()
print("========== 修改内容后重渲染 ==========")
ui:render([[
<style>
  .panel { width: 400px; padding: 20px; background-color: #222222; }
  .title { height: 38px; font-size: 20px; color: #ffffff; }
</style>
<div class="panel">
  <div class="title">新标题</div>
</div>
]])
print("  ", ui.rendered:statsText())
local live = 0
for _ in pairs(ui.rendered.live) do live = live + 1 end
print(string.format("  存活控件 %d 个 (应为 2: panel + title)", live))

--=============================================================================
-- 断言：内容变化后的控件回收 + 存活数
--=============================================================================
do
  -- panel + title 两个元素
  check("重渲染后 live = 2", live == 2,
      string.format("live=%d (期望 2: panel + title)", live))

  -- 旧的 panel 被复用（不是新建），文字被更新
  local panel = root._children[1]
  check("panel 被复用未新建", panel == allControls[2],
      panel == allControls[2] and "复用第 2 号控件"
                              or "不是原来那个控件")
  check("title 文字已更新", panel._children[1].text == "新标题",
      'text="' .. tostring(panel._children[1].text) .. '" (期望 "新标题")')

  -- ★ 被弃用的控件必须 SetActive(false)，否则会残留在画面上
  --   （两个按钮的 button 覆盖层已被回收）
  local stale = 0
  for _, c in ipairs(allControls) do
    if c._kind == "button" and c.active then
      -- 注意：仍然在树里的按钮才是活的；这里两个 btn 都已从 DOM 移除
      stale = stale + 1
    end
  end
  check("弃用的按钮已停用", stale == 0,
      string.format("仍 active 的 button = %d 个 (期望 0)", stale))

  -- ★ 回收时必须清监听器，否则复用后会重复触发
  local staleL = 0
  for _, c in ipairs(allControls) do
    if not c.active and #c._cursorListeners > 0 then staleL = staleL + 1 end
  end
  check("停用控件的监听已清空", staleL == 0,
      string.format("%d 个停用控件仍有监听", staleL))
end

print()
print("========== 性能：多轮 flush ==========")
local beforePerf = createdCount
local t0 = os.clock()
for i = 1, 100 do ui:flush() end
local t1 = os.clock()
print(string.format("  100 次 flush 耗时 %.1fms (每次 %.2fms)",
    (t1-t0)*1000, (t1-t0)*10))

--=============================================================================
-- 断言：逐帧 flush 稳定性（真机靠递归 TweenSequence 驱动，每帧都会 flush）
--=============================================================================
do
  -- ★ 核心契约：连续 100 帧不得新建控件（否则真机上控件数线性增长）
  check("100 帧 flush 不新建", createdCount - beforePerf == 0,
      string.format("新建 %d 个 (期望 0)", createdCount - beforePerf))
  local live2 = 0
  for _ in pairs(ui.rendered.live) do live2 = live2 + 1 end
  check("100 帧后 live 稳定", live2 == 2, string.format("live=%d", live2))
end

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end
