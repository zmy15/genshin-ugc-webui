--[[============================================================================
  test_pool_reset.lua  ——  ★★★ 控件池复用：外观复位 + isOrphan 账本（R31）

     ══════════════════════════════════════════════════════════════════════
     这个套件守两个【库级】缺陷（都在小恐龙 R29 排查中被确认）
     ══════════════════════════════════════════════════════════════════════

       缺陷 ①  复用控件会【继承上一个主人的外观】

         控件池是共享的：节点隐藏 -> 控件还池 -> 别的节点取走。
         而还池只调了 SetActive(false)，**外观字段一个都没清**。

         于是新主人若【没自己写】这个字段，就会显示旧主人的样子：
           · image.imageColor  旧主人染成红/白 -> 新主人也是红/白
           · textbox.text      旧主人的文字残留到新主人身上

         ★ 这正是「白色方块」那一类 bug 的库级成因之一：
           应用层必须"每帧都记得重写"，漏一次就露馅。

         修法：_take 交付前调 _resetReused（复位成"最不会骗人"的状态）。

       缺陷 ②  `control._orphan` 是【自定义字段】，真机写不进去

         渲染器还池时写 `control._orphan = true`，
         但本项目硬性约束：控件无法存自定义状态（写=静默失败）。
         所以应用层读它**永远是 nil** ->
         `if not ctrl._orphan then 用它 end` 这个"检查"【恒为真】= 空检查。

         真机后果：拿缓存的旧引用继续写 -> 写到池里【别人的】控件上
         -> 别人的没染上、自己的没染上 -> 白块 / 串色，且不报错。

         修法：渲染器自己记账 `_pooled`，对外提供 `rendered:isOrphan(ctrl)`。

     ══════════════════════════════════════════════════════════════════════
     ⚠️ 为什么用 engine_mock
     ══════════════════════════════════════════════════════════════════════

       缺陷 ② 只有在「自定义字段写不进去」的 mock 上才会暴露。
       普通 table 的 mock 会让 `_orphan` 看起来工作正常 ——
       正是本项目反复强调的「测试替身必须忠实」。
============================================================================]]

-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')
local webui      = require('webui')

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass=pass+1; print(string.format("  [OK] %-52s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-52s %s", name, detail or "")) end
end

local PREFABS = { container=1073741933, textbox=1073741934,
                  button=1073741935, image=1073741938 }

local function mkEnv()
  local E = EngineMock.new(PREFABS)
  game = E.game
  Color = { FromRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
            FromRGB=function(r,g,b) return {r=r,g=g,b=b} end }
  Enum = {
    EaseType={Linear="L"},
    CursorEventType={CursorClick="C",CursorDown="D",CursorUp="U",CursorEnter="E",
                     CursorExit="X",CursorBeginDrag="B",CursorDrag="G",CursorEndDrag="N"},
    ImageSource={StaticReference="SR"},
    TextHorizontalAlignmentLeft="L", TextHorizontalAlignmentMiddle="C",
    TextHorizontalAlignmentRight="R",
  }
  local root = E.makeControl("container", nil)
  root.name = "Root"; E.setRoots({ root })
  script = { object=root, EnableUpdate=function() end }
  printerr = function() end
  local pending = nil
  game.TweenSequence = function() local s={}
    function s:AppendCallback(cb) pending=cb; return s end
    function s:AppendInterval() return s end
    function s:Play() return s end
    function s:Kill() return s end
    return s end
  local r = webui.render.new(root, { prefabs = PREFABS })
  return E, root, r
end

--=============================================================================
print("=== 1. ★★★ 缺陷①：复用不得继承上一个主人的外观 ===")
--=============================================================================
do
  local E, root, r = mkEnv()

  -- ①-a image 染色
  do
    local c = r:_take("image", root)
    c.imageColor = Color.FromRGBA(255, 0, 0, 255)   -- 旧主人染成红
    r:_hide(c); r.pool["image"] = { c }; r._pooled[c] = true

    local reused = r:_take("image", root)
    local col = reused.imageColor
    local isRed = col and col.r == 255 and col.g == 0 and col.b == 0
    check("★★★ image 不继承旧主人的染色（红）", not isRed,
        string.format("r=%s g=%s b=%s", tostring(col and col.r),
            tostring(col and col.g), tostring(col and col.b)))
    --[[ ★★ 复位值必须是【全透明】而不是白色。

         ⚠️ 复位的语义是"新主人还没设置"。
            若复位成白色，一个忘了染色的控件就是【一块白】——
            会被误判成渲染故障（正是最难查的那种）。
            复位成透明则是"看不见"：漏了内容，但不会画错东西。 ]]
    check("★★ 复位成【全透明】而不是白色（避免造出白块）",
        col and (col.a == 0 or (col.r == 0 and col.g == 0 and col.b == 0)),
        string.format("a=%s", tostring(col and col.a)))
  end

  -- ①-b textbox 文字
  do
    local c = r:_take("textbox", root)
    c.text = "上一个主人的文字"
    r:_hide(c); r.pool["textbox"] = { c }; r._pooled[c] = true

    local reused = r:_take("textbox", root)
    check("★★★ textbox 不残留旧主人的文字",
        reused.text == nil or reused.text == "",
        string.format("text=%q", tostring(reused.text)))
  end

  -- ①-c 不能误伤：正常复用仍应拿到控件
  do
    local c = r:_take("container", root)
    r:_hide(c); r.pool["container"] = { c }; r._pooled[c] = true
    local reused = r:_take("container", root)
    check("★ 复位不影响复用本身（仍能拿到控件）", reused ~= nil)
    check("★ 复用的是同一个控件对象（池语义未变）", reused == c)
  end
end

--=============================================================================
print("")
print("=== 2. ★★★ 缺陷②：isOrphan 账本（真机唯一可用机制）===")
--=============================================================================
do
  local E, root, r = mkEnv()

  local c = r:_take("image", root)
  check("★ 取出后 isOrphan = false（不在池里）", r:isOrphan(c) == false)

  -- 还池
  r:_hide(c)
  r.pool["image"] = { c }
  r._pooled[c] = true
  check("★★ 还池后 isOrphan = true", r:isOrphan(c) == true)

  local c2 = r:_take("image", root)
  check("★★ 再取出后 isOrphan = false（账本被划掉）", r:isOrphan(c2) == false)
  check("★ 账本不残留（同一个对象）", c2 == c)

  check("★ isOrphan(nil) 保守返回 true", r:isOrphan(nil) == true)
end

--=============================================================================
print("")
print("=== 3. ★★★ `_orphan` 自定义字段在真机语义下【写不进去】 ===")
--=============================================================================
--[[ ⚠️ 这一节是缺陷②的【根因证据】：

     若 `_orphan` 能写进去，那应用层用它判断就没问题。
     但引擎只允许预定义字段（见 CLAUDE.md 的硬性约束），
     自定义字段写入【静默失败】-> 读回永远是 nil。

     => 任何依赖 `control._orphan` 的判断都是空判断。 ]]
do
  local E, root, r = mkEnv()
  local c = r:_take("image", root)

  c._orphan = true
  check("★★ 自定义字段 _orphan 写入后读回【不是 true】（真机语义）",
      c._orphan ~= true,
      "读回 = " .. tostring(c._orphan) .. "（证明该字段不可用）")

  -- 因此必须用渲染器的账本
  r.pool["image"] = { c }; r._pooled[c] = true
  check("★★ 账本机制仍能正确反映'在池里'", r:isOrphan(c) == true)
end

--=============================================================================
print("")
print("=== 4. 源码级：库不得再依赖自定义字段做状态 ===")
--=============================================================================
local renderSrc = io.open(_root .. "/lib/webui/webui_render.lua", "r"):read("*a")

check("★★ 渲染器不再写 control._orphan",
  renderSrc:find("e.control._orphan = true", 1, true) == nil
  and renderSrc:find("e.hot._orphan = true", 1, true) == nil)
check("★★ 存在 _pooled 账本", renderSrc:find("self._pooled", 1, true) ~= nil)
check("★★ 对外暴露 isOrphan", renderSrc:find("function Renderer:isOrphan", 1, true) ~= nil)
check("★★ 交付前调用 _resetReused",
  renderSrc:find("self:_resetReused(c, kind)", 1, true) ~= nil)

--=============================================================================
print("")
print("=== 5. 端到端：真实渲染多轮后，复用的控件外观正确 ===")
--=============================================================================
do
  local E, root, r = mkEnv()

  --[[ 渲染两类 image 节点：
       · 有 background-color 的（会被染色）
       · 没有的（不该染，且不该继承别人的颜色）
       交替渲染，逼出"复用 + 不写字段"的组合。 ]]
  local html = [[
<div id="a" style="position:absolute;left:0px;top:0px;width:50px;height:50px;background-color:#ff0000"></div>
<div id="b" style="position:absolute;left:100px;top:0px;width:50px;height:50px"></div>
]]
  local ui = webui.mount and nil
  -- 直接用底层 API：style.apply + layout.compute + renderer:update
  local dom = require('webui_dom')
  local htmlMod = require('webui_html')
  local style = require('webui_style')
  local layout = require('webui_layout')

  local doc = htmlMod.parse(html)
  -- 强制这两个元素走 image 分支（模拟 data-image）
  dom.walk(doc, function(n)
    if n:isElement() and n.attrs and n.attrs.id then
      if not n.attrs["data-image"] then n.attrs["data-image"] = "1" end
    end
  end)

  local function render()
    style.apply(doc, nil)
    layout.compute(doc, 1600, 900)
    r:update(doc, false)
  end

  local ok = pcall(render)
  check("★ 能完成一轮真实渲染", ok)

  if ok then
    -- 收集当前 image 控件
    local function imageStates()
      local out = {}
      for node, entry in pairs(r.live) do
        if entry.kind == "image" then
          local col = entry.control.imageColor
          out[#out + 1] = {
            id = node.attrs and node.attrs.id,
            r = col and col.r, g = col and col.g, b = col and col.b, a = col and col.a,
          }
        end
      end
      return out
    end

    -- 隐藏 a（让它的控件还池），再渲染 —— b 可能复用到 a 的控件
    local aNode = nil
    dom.walk(doc, function(n)
      if n:isElement() and n.attrs and n.attrs.id == "a" then aNode = n end
    end)
    if aNode then aNode:hide() end
    local ok2 = pcall(render)

    --[[ ★ 判据：#b 现在占着那个被复用的控件。
          它【没有】background-color，所以不该是红色 ——
          若继承，就会是 #ff0000。 ]]
    local bState = nil
    for _, st in ipairs(imageStates()) do
      if st.id == "b" then bState = st end
    end
    check("★ 渲染后 #b 仍存在", bState ~= nil)
    if bState then
      local isRed = bState.r == 255 and bState.g == 0 and bState.b == 0
      check("★★★ 复用到旧控件时 #b 没继承 #a 的红色",
          not isRed,
          string.format("#b = (%s,%s,%s)", tostring(bState.r),
              tostring(bState.g), tostring(bState.b)))
    end
  end
end

print("")
print(string.format(">>> 通过 %d / 失败 %d", pass, fail))
if fail > 0 then os.exit(1) end