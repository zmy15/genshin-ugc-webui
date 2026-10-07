-- 用真实模板索引验证 deploy_test
-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

--=============================================================================
-- 断言框架（与 test_wrap.lua 一致）
--=============================================================================
local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-28s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-28s %s", name, detail or "")) end
end

local created, controls = 0, {}

-- ★ 用真实索引
local PREFABS = {
  container = 1073741933,
  textbox   = 1073741934,
  button    = 1073741935,
}

local function makeControl(kind, parent)
  created = created + 1
  local c = {
    _kind = kind, name = kind,
    anchorMinX=0.5, anchorMinY=0.5, anchorMaxX=0.5, anchorMaxY=0.5,
    pivotX=0.5, pivotY=0.5, anchoredPositionX=0, anchoredPositionY=0,
    sizeDeltaX=100, sizeDeltaY=100, visible=true, active=true,
    _children={}, _listeners={},
  }
  c.SetActive=function(s,v) s.active=v end
  c.SetVisible=function(s,v) s.visible=v end
  c.GetChildren=function(s) return s._children end
  c.SetAnchoredPosition=function(s,x,y) s.anchoredPositionX=x; s.anchoredPositionY=y end
  c.SetSizeDelta=function(s,w,h) s.sizeDeltaX=w; s.sizeDeltaY=h end
  -- ★ 库回收控件时会调用它清监听器（render.lua 的 _hide）
  c.RemoveAllCursorEventListeners=function(s) s._listeners={} end
  if kind=="button" or kind=="area" then
    c.AddCursorEventListener=function(s,ev,cb) s._listeners[#s._listeners+1]={ev=ev,cb=cb} end
    c.SimulateCursorClick=function(s)
      for _,l in ipairs(s._listeners) do
        if l.ev=="CursorClick" then
          l.cb({GetUIPos=function() return 33,55 end,
                GetPressUIPos=function() return 33,55 end,
                GetUIPosDelta=function() return 0,0 end,
                dragging=false,touchId=-1})
        end
      end
    end
  end
  if parent then parent._children[#parent._children+1]=c end
  controls[#controls+1]=c
  return c
end

game={
  InstantiateClientUIControl=function(idx,parent)
    local kind = nil
    for k,v in pairs(PREFABS) do if v==idx then kind=k end end
    -- ★ 模拟真机：索引不存在就返回 nil（这是之前失败的原因）
    if not kind then return nil end
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
Color={FromRGBA=function(r,g,b,a) return {r,g,b,a} end,FromRGB=function(r,g,b) return {r,g,b} end}
Enum={CursorEventType={CursorClick="CursorClick",CursorEnter="CursorEnter",
                      CursorDown="CursorDown",CursorUp="CursorUp",CursorExit="CursorExit",
                      CursorBeginDrag="CursorBeginDrag",CursorDrag="CursorDrag",
                      CursorEndDrag="CursorEndDrag"},
      TextHorizontalAlignmentLeft="L",TextHorizontalAlignmentMiddle="C",
      TextHorizontalAlignmentRight="R"}

local root = makeControl("container", nil)
root.name = "ProbeRoot"
script = { object = root, name = "ProbeRoot" }

print("========== 用真实索引验证 ==========")
print()

local webui = require('webui')

local clicks = 0
local ui = webui.new({
  root = root, prefabs = PREFABS,
  handlers = { onClick = function(info) clicks = clicks + 1 end },
})

ui:render([[
<style>
  .panel { width: 320px; padding: 16px; background-color: #1e1e28; }
  .title { height: 35px; font-size: 18px; color: #ffffff; }
  .row   { display: flex; gap: 10px; margin-top: 12px; }
  .btn   { width: 110px; height: 36px; background-color: #3a7bd5; }
</style>
<div class="panel">
  <div class="title">webui 测试</div>
  <div class="row">
    <div class="btn" onclick="onClick">按钮A</div>
    <div class="btn" onclick="onClick">按钮B</div>
  </div>
</div>
]])

print("  渲染: " .. ui.rendered:statsText())
print("  事件: " .. tostring(ui.boundCount))
print()

--=============================================================================
-- 断言：真机索引能真的建出控件（这是本套件的核心目的）
--=============================================================================
do
  -- ★ 核心契约：用真机索引 1073741933/34/35 必须能建出控件。
  --   索引错了会返回 nil -> created=0 -> 真机白屏（历史上就是这么挂的）
  check("真机索引能建出控件", ui.rendered.stats.created > 0,
      string.format("created=%d", ui.rendered.stats.created))
  -- panel/title/row/btnA/btnB = 5 个视觉控件 + 2 个按钮覆盖层 = 7
  check("控件数 = 7", ui.rendered.stats.created == 7,
      string.format("created=%d (期望 7)", ui.rendered.stats.created))
  local live = 0
  for _ in pairs(ui.rendered.live) do live = live + 1 end
  check("live 控件 = 5", live == 5, string.format("live=%d (期望 5)", live))

  -- ★ 契约：索引正确时不应出现任何 PREFABS 相关的告警
  --   （告警只在索引缺失/无效时出现，见下面的校验测试）
  -- 2 个 btn 各有 onclick
  check("事件绑定数 = 2", ui.boundCount == 2,
      string.format("bound=%d (期望 2)", ui.boundCount))

  -- ★ 真机陷阱：新控件 active 默认 false，必须 SetActive(true) 才可见
  local inactive = {}
  for i, c in ipairs(controls) do
    if c.active ~= true then inactive[#inactive+1] = i .. ":" .. c._kind end
  end
  check("全部控件 active=true", #inactive == 0,
      #inactive == 0 and ("共 " .. #controls .. " 个全部激活")
                    or ("未激活: " .. table.concat(inactive, ",")))
end
print()

print("========== 控件树（这是真机上应该看到的）==========")
local function dump(c, d)
  if d > 6 then return end
  local pad = string.rep("  ", d + 1)
  print(string.format("%s%-10s pos=(%.0f,%.0f) size=(%.0fx%.0f)%s%s",
      pad, c._kind,
      c.anchoredPositionX, c.anchoredPositionY,
      c.sizeDeltaX, c.sizeDeltaY,
      c.bgColor and (" bg=" .. tostring(c.bgColor)) or "",
      c.text and (' text="' .. c.text .. '"') or ""))
  for _, k in ipairs(c._children) do dump(k, d+1) end
end
for _, c in ipairs(root._children) do dump(c, 0) end

--=============================================================================
-- 断言：控件树结构 + 字段（真机上应该看到的样子）
--=============================================================================
do
  check("root 只有 1 个子控件", #root._children == 1,
      string.format("实际 %d 个", #root._children))
  local panel = root._children[1]

  -- .panel { width:320px; padding:16px } -> 宽 320
  check("panel 宽 = 320", panel and math.abs(panel.sizeDeltaX - 320) < 1,
      panel and string.format("w=%.1f (期望 320)", panel.sizeDeltaX))
  -- 高 = title 35 + margin-top 12 + row 36 + 上下 padding 32 = 115
  check("panel 高 = 115", panel and math.abs(panel.sizeDeltaY - 115) < 1,
      panel and string.format("h=%.1f (期望 115)", panel.sizeDeltaY))
  check("panel 是 textbox", panel and panel._kind == "textbox",
      panel and ("kind=" .. panel._kind))
  check("panel bgColor 已写入", panel and panel.bgColor ~= nil,
      "bg=" .. tostring(panel and panel.bgColor))
  check("panel 有 2 个子控件", panel and #panel._children == 2,
      panel and string.format("实际 %d 个", #panel._children))

  if panel and #panel._children == 2 then
    local title, row = panel._children[1], panel._children[2]
    check("title text 已写入", title.text == "webui 测试",
        'text="' .. tostring(title.text) .. '" (期望 "webui 测试")')
    -- font-size:18px -> ★ 真机要求整数
    check("title fontSize = 18 (整数)", title.fontSize == 18
        and title.fontSize == math.floor(title.fontSize),
        "fontSize=" .. tostring(title.fontSize))
    -- .title { height:35px; font-size:18px } -> 比值 1.94，达标
    -- ★ 真机硬约束：框高 >= 字号 × 1.9，否则引擎字号自适应把字压没。
    --   （原夹具是 28px/18px = 1.56，违反约束，已按 docs/引擎能力与限制.md §4.4 调到 35px。）
    local ratio = title.sizeDeltaY / (title.fontSize or 1)
    check("title 框高/字号 >= 1.9（真机硬约束）", ratio >= 1.9,
        string.format("比值=%.2f (要求 >= 1.9)", ratio))

    check("row 是 container", row._kind == "container", "kind=" .. row._kind)
    -- ★ 容器写 bgColor/text 会静默失败（字段按类型封死）
    check("container 无 bgColor/text", row.bgColor == nil and row.text == nil,
        "bg=" .. tostring(row.bgColor) .. " text=" .. tostring(row.text))
    check("row 有 2 个子控件", #row._children == 2,
        string.format("实际 %d 个", #row._children))

    if #row._children == 2 then
      local b1, b2 = row._children[1], row._children[2]
      check("btnA text 已写入", b1.text == "按钮A",
          'text="' .. tostring(b1.text) .. '"')
      check("btnB text 已写入", b2.text == "按钮B",
          'text="' .. tostring(b2.text) .. '"')
      -- .btn { width:110px; height:36px }
      check("btn 尺寸 = 110x36", math.abs(b1.sizeDeltaX - 110) < 1
                              and math.abs(b1.sizeDeltaY - 36) < 1,
          string.format("size=(%.0fx%.0f) (期望 110x36)", b1.sizeDeltaX, b1.sizeDeltaY))
      -- gap:10px -> 中心间距 = 110 + 10 = 120
      local d = b2.anchoredPositionX - b1.anchoredPositionX
      check("btn 间距 = 120 (gap 10)", math.abs(d - 120) < 1,
          string.format("dx=%.1f (期望 120)", d))

      -- ★ 双层架构：视觉层 textbox + 交互层 button 覆盖
      check("btnA 挂了 button 覆盖层", #b1._children == 1
          and b1._children[1]._kind == "button",
          string.format("子控件=%d 个", #b1._children))
      if #b1._children == 1 then
        local hot = b1._children[1]
        check("覆盖层铺满视觉层", math.abs(hot.sizeDeltaX - b1.sizeDeltaX) < 1
                               and math.abs(hot.sizeDeltaY - b1.sizeDeltaY) < 1,
            string.format("hot=(%.0fx%.0f) vs 视觉层=(%.0fx%.0f)",
                hot.sizeDeltaX, hot.sizeDeltaY, b1.sizeDeltaX, b1.sizeDeltaY))
        check("覆盖层 active=true", hot.active == true,
            "active=" .. tostring(hot.active))
        -- ★ 覆盖层必须真的接到事件（只有 button 有 AddCursorEventListener）
        check("覆盖层接了监听器", #hot._listeners > 0,
            string.format("listeners=%d", #hot._listeners))
      end
      -- ★ textbox 没有光标事件接口 —— 这才是要双层的根本原因
      check("textbox 无光标监听接口", type(b1.AddCursorEventListener) ~= "function",
          "type=" .. type(b1.AddCursorEventListener))
    end
  end
end
print()
for _, c in ipairs(controls) do
  if #c._listeners > 0 then pcall(function() c:SimulateCursorClick() end) end
end
print("  点击触发: " .. clicks .. " 次")

-- ★ 契约：两个按钮各触发一次（真机索引下事件必须能派发）
check("点击触发 2 次", clicks == 2, string.format("clicks=%d (期望 2)", clicks))

print()
print("========== 验证 PREFABS 校验逻辑 ==========")
-- 故意用错误索引，看是否给出警告
-- ★ 捕获 warn：要断言"确实 warn 了"，而不是只靠人眼看
local util = require('webui.util')
local warns = {}
local origWarn = util.warn
local function captureWarn(...)
  local n = select('#', ...)
  local t = {}
  for i = 1, n do t[i] = tostring((select(i, ...))) end
  warns[#warns+1] = table.concat(t, " ")
  return origWarn(...)
end
util.warn = captureWarn

local ui2, renderOk, renderErr = nil, nil, nil
renderOk, renderErr = pcall(function()
  ui2 = webui.new({ root = root, prefabs = { container = 999999 } })
  ui2:render([[<div style="width:100px;height:50px"></div>]])
end)
util.warn = origWarn

-- ★ 契约：索引无效时必须 warn，且【不能崩溃】
check("无效索引渲染不崩溃", renderOk == true,
    renderOk and "OK" or ("出错: " .. tostring(renderErr)))
check("无效索引有 warn", #warns > 0,
    string.format("%d 条告警", #warns))

-- ★ 契约：告警内容要能指出"PREFABS 没配"这个根因
local mentionsPrefabs = false
for _, w in ipairs(warns) do
  if w:find("PREFABS") then mentionsPrefabs = true end
end
check("告警提到 PREFABS", mentionsPrefabs,
    mentionsPrefabs and "有" or "告警里没提 PREFABS，排查会很困难")

-- ★ 契约：一个控件都建不出来（索引全错）
if ui2 then
  check("无效索引建不出控件", ui2.rendered.stats.created == 0,
      string.format("created=%d (期望 0)", ui2.rendered.stats.created))
end

print("  （上面应有 [warn] 提示索引无效）")
print()
print("*** 真实索引验证通过 ***")

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end
