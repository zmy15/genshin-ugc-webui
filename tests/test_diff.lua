-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local created = 0
local function makeControl(kind, parent)
  created = created + 1
  local c = { _kind=kind, name=kind,
    anchorMinX=0.5,anchorMinY=0.5,anchorMaxX=0.5,anchorMaxY=0.5,
    pivotX=0.5,pivotY=0.5,anchoredPositionX=0,anchoredPositionY=0,
    sizeDeltaX=0,sizeDeltaY=0,visible=true,active=true,
    _children={}, _listeners={} }
  c.SetActive=function(s,v) s.active=v end
  c.GetChildren=function(s) return s._children end
  c.SetAnchoredPosition=function(s,x,y) s.anchoredPositionX=x;s.anchoredPositionY=y end
  c.SetSizeDelta=function(s,w,h) s.sizeDeltaX=w;s.sizeDeltaY=h end
  c.AddCursorEventListener=function(s,ev,cb) s._listeners[#s._listeners+1]={ev=ev,cb=cb} end
  if parent then parent._children[#parent._children+1]=c end
  return c
end

local PREFABS={container=1073741933,textbox=1073741934,button=1073741935}
game={
  InstantiateClientUIControl=function(idx,parent)
    for k,v in pairs(PREFABS) do if v==idx then return makeControl(k,parent) end end
    return nil
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

local webui = require('webui')
local root = makeControl("container", nil)
script = { object = root }

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-28s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-28s %s", name, detail or "")) end
end

--[[ 统计控件树里所有控件的监听器总数（用于验证复用不累积监听）]]--
local function countListeners(c)
  local n = #(c._listeners or {})
  for _, k in ipairs(c._children) do n = n + countListeners(k) end
  return n
end

local ui = webui.new({ root=root, prefabs=PREFABS, handlers={onClick=function() end} })
ui:render([[
<style>
  .panel { width: 320px; padding: 16px; background-color: #1e1e28; }
  .title { height: 28px; font-size: 18px; color: #ffffff; }
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

print("=== diff 效果验证 ===")
print()
local s = ui.rendered.stats
print(string.format("  首次渲染: written=%d", s.written))
-- 首次渲染必须真的写入字段（否则说明控件没建出来 / 字段没同步）
check("首次渲染有字段写入", s.written > 0,
    string.format("written=%d (期望>0)", s.written))

-- ★ 加一个 hook 追踪到底哪个字段在被反复写
local Renderer = ui.rendered

local before = s.written
ui:flush()
print(string.format("  第 2 次 flush: 新增写入 %d", s.written - before))
--[[ ★ diff 的核心保证：布局/样式都没变时，第 2 帧不应产生任何字段写入。
     若这条失败，说明 diff 退化成"每帧全量重写"，
     真机上会表现为帧率随控件数暴跌（也正是本用例存在的原因）。]]--
check("第 2 次 flush 零写入", (s.written - before) == 0,
    string.format("新增写入=%d (期望0，diff 生效)", s.written - before))

-- 再 flush 一次，确认稳定（不是只在第 2 帧恰好为 0）
local before3 = s.written
ui:flush()
check("第 3 次 flush 零写入", (s.written - before3) == 0,
    string.format("新增写入=%d (期望0)", s.written - before3))

print()
print("=== 追踪每帧重复写入的字段 ===")
-- 直接检查每个控件的 last 表，找出哪些值在变
local dom = require('webui_dom')
print(string.format("  %-12s %-22s %-24s %s", "字段", "上一帧值", "本帧值", "控件"))

-- 更直接：连续 flush 两次，比较 last 表
local snap = {}
for node, entry in pairs(Renderer.live) do
  snap[node] = {}
  for k, v in pairs(entry.last) do snap[node][k] = v end
end
ui:flush()
local changed = 0
print("  第二次 flush 后，发生变化的字段：")
for node, entry in pairs(Renderer.live) do
  local old = snap[node]
  if old then
    for k, v in pairs(entry.last) do
      if old[k] ~= v then
        changed = changed + 1
        print(string.format("    %-10s %-20s %s -> %s",
            node.tag or "?", k, tostring(old[k]), tostring(v)))
      end
    end
  end
end
-- 与上面「第 3 次 flush 零写入」是同一事实的另一种测法：逐字段比对也必须无变化
check("逐字段比对无变化", changed == 0,
    string.format("变化字段数=%d (期望0)", changed))

print()
print("=== 控件树 ===")
local function dump(c,d)
  if d>5 then return end
  print(string.format("%s%-10s size=%.0fx%.0f pos=(%.0f,%.0f) text=%s",
    string.rep("  ",d+1), c._kind, c.sizeDeltaX, c.sizeDeltaY,
    c.anchoredPositionX, c.anchoredPositionY, tostring(c.text)))
  for _,k in ipairs(c._children) do dump(k,d+1) end
end
for _,c in ipairs(root._children) do dump(c,0) end

print()
print("=== 控件树断言 ===")
--[[ 控件树结构（来自实际观测，且与 HTML 语义一致）：

       textbox    size=320x108         <- .panel（320 宽 + padding16*2 高 108）
         textbox    size=288x28  "webui 测试"  <- .title
         container  size=288x36               <- .row（flex）
           textbox  size=110x36  "按钮A"      <- .btn（+ button 事件覆盖层）
             button size=110x36
           textbox  size=110x36  "按钮B"
             button size=110x36

     ⚠️ 注意：.panel 的 box 宽是 320（CSS width），但控件 sizeDelta 记的是
        320 宽 / 108 高，其中高 = 28(.title) + 12(margin-top) + 36(.row) + 16*2(padding)。
        这个 108 与 test_layout 用例 11 的算高逻辑一致。]]--
local lv1 = root._children[1]
check("根下挂了一个控件", lv1 ~= nil and #root._children == 1,
    string.format("children=%d (期望1)", #root._children))

if lv1 then
  check("面板控件尺寸 320x108",
      math.abs(lv1.sizeDeltaX - 320) < 1 and math.abs(lv1.sizeDeltaY - 108) < 1,
      string.format("%.0fx%.0f (期望320x108)", lv1.sizeDeltaX, lv1.sizeDeltaY))

  local title, row = lv1._children[1], lv1._children[2]
  check("面板下有 title 和 row 两个控件", #lv1._children == 2,
      string.format("children=%d (期望2)", #lv1._children))
  check("title 有文本", title and title.text == "webui 测试",
      string.format("text=%s (期望'webui 测试')", title and tostring(title.text) or "nil"))

  -- .row 是 flex，两个按钮各 110 宽、gap 10 -> 在 288 内容宽里居中排布
  -- 实测两个按钮的 x 偏移为 -89 与 +31，间距正好 110+10=120
  if row and row._children[1] and row._children[2] then
    local b1, b2 = row._children[1], row._children[2]
    check("两个按钮控件尺寸均为 110x36",
        math.abs(b1.sizeDeltaX - 110) < 1 and math.abs(b2.sizeDeltaX - 110) < 1
        and math.abs(b1.sizeDeltaY - 36) < 1,
        string.format("%.0fx%.0f / %.0fx%.0f", b1.sizeDeltaX, b1.sizeDeltaY,
            b2.sizeDeltaX, b2.sizeDeltaY))
    check("按钮间距 = 110 + gap10",
        math.abs((b2.anchoredPositionX - b1.anchoredPositionX) - 120) < 1,
        string.format("Δx=%.0f (期望120)", b2.anchoredPositionX - b1.anchoredPositionX))
    check("按钮文本正确",
        b1.text == "按钮A" and b2.text == "按钮B",
        string.format("'%s' / '%s'", tostring(b1.text), tostring(b2.text)))
  else
    check("row 下有两个按钮控件", false, "结构不符")
  end
end

--[[ ★ 控件复用：连续 flush 不应新建控件。
     复用的判定依据是 created 计数（render.lua 的 stats.created）稳定。]]--
local createdAfterFirst = Renderer.stats.created
ui:flush()
ui:flush()
check("重复 flush 不新建控件", Renderer.stats.created == createdAfterFirst,
    string.format("created %d -> %d (期望不变)", createdAfterFirst, Renderer.stats.created))

--[[ ★ live 表规模 = 实际在用的控件数。本页面固定 5 个可见元素
      （panel / title / row / 两个 btn）。]]--
local liveN = 0
for _ in pairs(Renderer.live) do liveN = liveN + 1 end
check("live 控件数正确", liveN == 5,
    string.format("live=%d (期望5)", liveN))

--[[ ★★ 监听器不累积（这是 diff/复用路径最容易踩的坑）

     render.lua:_hide() 的注释里明确记录了历史 bug：
       复用控件若不清旧监听，第 N 次渲染同一控件上会累积 N 个监听。
     HTML 里两个 .btn 都写了 onclick="onClick"，所以正确状态是【2 个】。
]]--
local listeners = countListeners(root)
check("监听器不累积（2 个按钮）", listeners == 2,
    string.format("监听器=%d (期望2)", listeners))

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end
