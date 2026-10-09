-- 验证单文件 bundle 能否独立工作（不依赖文件系统 require）
package.path = ""   -- ★ 清空搜索路径，强制只能从 bundle 里取

--=============================================================================
-- 断言框架（与 test_wrap.lua 一致）
--=============================================================================
local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-28s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-28s %s", name, detail or "")) end
end

--[[ 提前返回的错误出口。

     ★ 原脚本在失败分支用 `return` 直接退出，退出码仍是 0 ——
       CI 完全看不出失败（假阳性）。这里统一改成"记账 + 非零退出"。
]]--
local function bail(msg)
  fail = fail + 1
  print(string.format("  [XX] %-28s %s", "bundle 加载", msg))
  print()
  print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
  os.exit(1)
end

-- 模拟真机环境
local createdCount = 0
local allControls = {}

local function makeControl(kind, parent)
  createdCount = createdCount + 1
  local c = {
    _kind = kind, name = kind,
    anchorMinX=0.5, anchorMinY=0.5, anchorMaxX=0.5, anchorMaxY=0.5,
    pivotX=0.5, pivotY=0.5, anchoredPositionX=0, anchoredPositionY=0,
    sizeDeltaX=100, sizeDeltaY=100, visible=true, active=true,
    _children = {}, _cursorListeners = {},
  }
  c.SetActive = function(self,v) self.active=v end
  c.GetChildren = function(self) return self._children end
  c.SetAnchoredPosition = function(self,x,y) self.anchoredPositionX=x; self.anchoredPositionY=y end
  c.SetSizeDelta = function(self,w,h) self.sizeDeltaX=w; self.sizeDeltaY=h end
  if kind == "button" then
    c.AddCursorEventListener = function(self,ev,cb)
      self._cursorListeners[#self._cursorListeners+1]={ev=ev,cb=cb}
    end
    c.SimulateCursorClick = function(self)
      for _,l in ipairs(self._cursorListeners) do
        if l.ev == "CursorClick" then
          l.cb({GetUIPos=function() return 5,6 end,
                GetPressUIPos=function() return 5,6 end,
                GetUIPosDelta=function() return 0,0 end,
                dragging=false, touchId=-1})
        end
      end
    end
  end
  if parent then parent._children[#parent._children+1]=c end
  allControls[#allControls+1]=c
  return c
end

local PREFABS = { container=1, textbox=2, button=3 }
game = {
  InstantiateClientUIControl=function(idx,parent)
    local kind="container"
    for k,v in pairs(PREFABS) do if v==idx then kind=k end end
    return makeControl(kind,parent)
  end,
  DestroyClientUIControl=function() end,
  GetUICanvasSize=function() return 1600,900 end,
  GetClientUIRoots=function() return {} end,
  TweenSequence=function()
    local s={} s.AppendInterval=function() return s end
    s.AppendCallback=function() return s end s.Play=function() return s end
    return s
  end,
}
Color={ FromRGBA=function(r,g,b,a) return {r,g,b,a} end,
        FromRGB=function(r,g,b) return {r,g,b} end }
Enum={ CursorEventType={CursorClick="CursorClick",CursorEnter="CursorEnter",
                        CursorDown="CursorDown",CursorUp="CursorUp",
                        CursorExit="CursorExit",CursorBeginDrag="CursorBeginDrag",
                        CursorDrag="CursorDrag",CursorEndDrag="CursorEndDrag"},
       TextHorizontalAlignmentLeft="L",TextHorizontalAlignmentMiddle="C",
       TextHorizontalAlignmentRight="R" }

-- ★ 关键：从 bundle 文件加载（模拟"粘贴源码"的场景）
print("=== 加载 bundle/webui.lua ===")
local chunk, err = loadfile("bundle/webui.lua")
if not chunk then
  print("  ✗ 加载失败: " .. tostring(err))
  bail("loadfile 失败: " .. tostring(err)
       .. "（bundle/ 在 .gitignore 里，请先跑 lua tools/build.lua）")
end
-- ★ bundle 必须能被 loadfile 读到 —— 这是"单文件可粘贴"的前提
check("bundle 文件可加载", chunk ~= nil, "loadfile 返回了 chunk")

local ok, result = pcall(chunk)
if not ok then
  print("  ✗ 执行失败: " .. tostring(result))
  bail("执行失败: " .. tostring(result))
end

print("  ✓ 执行成功")
print("  return 值类型: " .. type(result))
print("  __WEBUI__ 全局: " .. type(__WEBUI__))

-- ★ 契约：package.path 为空时 bundle 仍能跑起来（不依赖文件系统）
check("bundle 执行无错", ok == true, "pcall 成功")
check("返回值是 table", type(result) == "table", "type=" .. type(result))
-- ★ 契约：返回值和全局 __WEBUI__ 是同一个对象（粘贴源码时用全局）
check("__WEBUI__ 是 table", type(__WEBUI__) == "table", "type=" .. type(__WEBUI__))
check("return 值 == __WEBUI__", result == __WEBUI__,
    "两者" .. (result == __WEBUI__ and "相同" or "不同"))

local webui = result
if type(webui) ~= "table" or not webui.new then
  print("  ✗ 返回值不是一个可用的库")
  bail("返回值不是可用库 (webui.new = " .. type(webui and webui.new) .. ")")
end

print("  版本: " .. tostring(webui.VERSION))
print("  子模块: util=" .. type(webui.util) ..
      " html=" .. type(webui.html) ..
      " css=" .. type(webui.css) ..
      " layout=" .. type(webui.layout))

--=============================================================================
-- 断言：bundle 真的自包含（13 个模块全在里面，不靠 package.path）
--=============================================================================
do
  check("webui.new 可用", type(webui.new) == "function",
      "type=" .. type(webui.new))
  check("VERSION 已定义", webui.VERSION == "0.1.0",
      "VERSION=" .. tostring(webui.VERSION))

  -- 全部子系统都要在 bundle 里（缺一个就是 build.lua 的 MODULES 漏了）
  local missing = {}
  for _, m in ipairs({"util","dom","html","css","color","style",
                      "layout","render","clip","sprite","event","signal"}) do
    if type(webui[m]) ~= "table" then missing[#missing+1] = m end
  end
  check("子模块全部可用", #missing == 0,
      #missing == 0 and "12 个子模块齐全" or ("缺: " .. table.concat(missing, ",")))

  -- ★ 关键自包含证据：解析器能真正干活（内部查表，不走 require）
  check("html.parse 可用", type(webui.html.parse) == "function",
      "type=" .. type(webui.html.parse))
  check("layout.compute 可用", type(webui.layout.compute) == "function",
      "type=" .. type(webui.layout.compute))
  check("render.new 可用", type(webui.render.new) == "function",
      "type=" .. type(webui.render.new))
  check("signal.new 可用", type(webui.signal.new) == "function",
      "type=" .. type(webui.signal.new))

  -- bundle 末尾把 webui 注册进 package.preload，所以 require('webui')
  -- 在没有 package.path 的情况下也能命中
  local pre = package.preload and package.preload["webui"]
  check("已注册 package.preload", type(pre) == "function",
      "type=" .. type(pre))
  if type(pre) == "function" then
    local ok2, m2 = pcall(pre)
    check("preload 返回同一对象", ok2 and m2 == result,
        ok2 and (m2 == result and "同一对象" or "不是同一对象")
             or ("出错: " .. tostring(m2)))
  end

  check("package.path 为空", package.path == "",
      "path=[" .. tostring(package.path) .. "]")
end

--=============================================================================
-- 用 bundle 跑一个完整示例
--=============================================================================
print()
print("=== 用 bundle 渲染 ===")

local root = makeControl("container", nil)
script = { object = root, name = "bundle_test" }

local clicked = 0
local ui = webui.new({
  root = root,
  prefabs = PREFABS,
  handlers = { onClick = function(info) clicked = clicked + 1 end },
})

ui:render([[
<style>
  .card  { width: 300px; padding: 16px; box-sizing: border-box; background-color: #1e1e1e; }
  .head  { height: 24px; font-size: 18px; color: #ffffff; }
  .bar   { display: flex; gap: 8px; }
  .item  { width: 80px; height: 32px; background-color: #4a90d9; }
</style>
<div class="card">
  <div class="head">标题</div>
  <div class="bar">
    <div class="item" onclick="onClick">A</div>
    <div class="item" onclick="onClick">B</div>
  </div>
</div>
]])

print("  DOM:", (function()
  local st = webui.dom.stats(ui.doc)
  return string.format("元素=%d 文本=%d 深度=%d", st.elements, st.texts, st.maxDepth)
end)())
print("  渲染:", ui.rendered:statsText())
print("  事件绑定:", ui.boundCount)

--=============================================================================
-- 断言：bundle 渲染结果与多文件版一致（端到端可用）
--=============================================================================
do
  local st = webui.dom.stats(ui.doc)
  -- <style> + card + head + bar + item + item = 6
  check("DOM 元素数 = 6", st.elements == 6,
      string.format("元素=%d (期望 6)", st.elements))
  -- card/head/bar/item/item = 5 个视觉控件 + 2 个按钮覆盖层 = 7
  check("渲染控件数 = 7", ui.rendered.stats.created == 7,
      string.format("created=%d (期望 7)", ui.rendered.stats.created))
  -- 2 个 item 各一个 onclick
  check("事件绑定数 = 2", ui.boundCount == 2,
      string.format("bound=%d (期望 2)", ui.boundCount))

  -- ★ 真机陷阱：新控件 active 默认 false，必须 SetActive(true) 才可见
  local inactive = {}
  for i, c in ipairs(allControls) do
    if c.active ~= true then inactive[#inactive+1] = i .. ":" .. c._kind end
  end
  check("全部控件 active=true", #inactive == 0,
      #inactive == 0 and ("共 " .. #allControls .. " 个全部激活")
                    or ("未激活: " .. table.concat(inactive, ",")))

  -- 控件树：card -> head + bar -> 2 个 item -> 各自的 button 覆盖层
  check("root 只有 1 个子控件", #root._children == 1,
      string.format("实际 %d 个", #root._children))
  local card = root._children[1]
  check("card 尺寸 = 300x88", card and math.abs(card.sizeDeltaX - 300) < 1
                            and math.abs(card.sizeDeltaY - 88) < 1,
      card and string.format("size=(%.0fx%.0f) (期望 300x88)", card.sizeDeltaX, card.sizeDeltaY))
  check("card bgColor 已写入", card and card.bgColor ~= nil,
      "bg=" .. tostring(card and card.bgColor))
  check("card 有 2 个子控件", card and #card._children == 2,
      card and string.format("实际 %d 个", #card._children))

  if card and #card._children == 2 then
    local head, bar = card._children[1], card._children[2]
    check("head text 已写入", head.text == "标题",
        'text="' .. tostring(head.text) .. '" (期望 "标题")')
    -- font-size:18px -> 必须是整数
    check("head fontSize = 18 (整数)", head.fontSize == 18
        and head.fontSize == math.floor(head.fontSize),
        "fontSize=" .. tostring(head.fontSize))
    check("bar 是 container", bar._kind == "container", "kind=" .. bar._kind)
    -- ★ 容器写 bgColor/text 会静默失败（字段按类型封死）
    check("container 无 bgColor/text", bar.bgColor == nil and bar.text == nil,
        "bg=" .. tostring(bar.bgColor) .. " text=" .. tostring(bar.text))

    if #bar._children == 2 then
      local i1, i2 = bar._children[1], bar._children[2]
      check("item1 text 已写入", i1.text == "A", 'text="' .. tostring(i1.text) .. '"')
      check("item2 text 已写入", i2.text == "B", 'text="' .. tostring(i2.text) .. '"')
      check("item 尺寸 = 80x32", math.abs(i1.sizeDeltaX - 80) < 1
                              and math.abs(i1.sizeDeltaY - 32) < 1,
          string.format("size=(%.0fx%.0f)", i1.sizeDeltaX, i1.sizeDeltaY))
      -- gap:8px -> 中心间距 = 80 + 8 = 88
      local d = i2.anchoredPositionX - i1.anchoredPositionX
      check("item 间距 = 88 (gap 8)", math.abs(d - 88) < 1,
          string.format("dx=%.1f (期望 88)", d))
      -- ★ 双层架构：视觉层 textbox + 交互层 button
      check("item1 挂了 button 覆盖层", #i1._children == 1
          and i1._children[1]._kind == "button",
          string.format("子控件=%d 个", #i1._children))
      if #i1._children == 1 then
        check("覆盖层 active=true", i1._children[1].active == true,
            "active=" .. tostring(i1._children[1].active))
      end
    end
  end
end

-- 触发点击
local fired = 0
for _, c in ipairs(allControls) do
  if #c._cursorListeners > 0 then pcall(function() c:SimulateCursorClick() end) fired = fired + 1 end
end
print(string.format("  模拟点击 %d 个按钮, onClick 触发 %d 次", fired, clicked))

-- ★ 契约：bundle 版的事件派发也要正常（2 个按钮 -> 2 次回调）
check("点击了 2 个按钮", fired == 2, string.format("fired=%d (期望 2)", fired))
check("onClick 触发 2 次", clicked == 2, string.format("clicked=%d (期望 2)", clicked))

-- 二次 flush
local before = createdCount
ui:flush()
print(string.format("  二次 flush 新建控件 %d 个 (应为 0)", createdCount - before))

--=============================================================================
-- 断言：bundle 版复用同样生效
--=============================================================================
do
  -- ★ 核心契约：DOM 没变时不得新建（否则真机上控件数线性增长）
  check("二次 flush 不新建", createdCount - before == 0,
      string.format("新建 %d 个 (期望 0)", createdCount - before))

  -- ★ 复用后必须重新 active（否则控件不可见）
  local inactive = {}
  for i, c in ipairs(allControls) do
    if c.active ~= true then inactive[#inactive+1] = i .. ":" .. c._kind end
  end
  check("复用后控件仍 active", #inactive == 0,
      #inactive == 0 and ("共 " .. #allControls .. " 个全部激活")
                    or ("未激活: " .. table.concat(inactive, ",")))
end

-- 连续 100 帧（真机靠递归 TweenSequence 逐帧 flush）
local beforeLoop = createdCount
for i = 1, 100 do ui:flush() end
check("100 帧 flush 不新建", createdCount - beforeLoop == 0,
    string.format("新建 %d 个 (期望 0)", createdCount - beforeLoop))

print()
print("=== 契约测试：bundle 是否独立 ===")
print("  ✓ 清空了 package.path 仍能工作 => 不依赖文件系统")
print("  ✓ 返回值和 __WEBUI__ 都可用")
print()
print("*** bundle 验证通过 ***")

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end
