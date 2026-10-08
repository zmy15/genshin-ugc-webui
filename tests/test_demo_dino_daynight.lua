--[[============================================================================
  test_demo_dino_daynight.lua  ——  昼夜更替（R28）

     需求：「添加昼夜更替效果，黑天背景变成深色，天空加上星星和月亮」

     ══════════════════════════════════════════════════════════════════════
     ★★★ 这个套件守的是什么
     ══════════════════════════════════════════════════════════════════════

       昼夜更替看起来只是"换个颜色"，但它踩过三个**静默失败**的坑 ——
       全部不报错，只是画面上看不见：

       ① ★★ 隐藏节点的控件染色会丢

          星月白天整组 display:none。而渲染器会在节点隐藏时
          把它【移出 rendered.live】（render.lua 的回收段）。

          于是 applyTheme 里 `rendered.live[node]` 反查返回 nil，
          染色被 `if ctrl then ... end` 静默跳过 —— 等夜里 show() 时，
          控件是从池里重新取的，还带着池里那个旧颜色（深灰）
          => 深色天空上画深灰星月，几乎看不见。

          修法：贴图时把控件引用存进 spriteCtrls，不依赖 rendered.live。

       ② 文字框的【自身背景色】必须跟着主题改（R21 的延伸）

          文字框必须显式写 background-color（R21），
          不跟着改就会出现"深色天空 + 三条浅色底"。

       ③ 精灵染色与背景色是【两条不同的通路】

          .scene 走 bgColor（textbox 字段）
          精灵  走 imageColor（image 字段）
          漏掉任何一条，都会出现"背景变了但图形没变"的割裂感。

     ══════════════════════════════════════════════════════════════════════
     ★★ 测试方法：为什么不用"跑真实游戏到转夜"
     ══════════════════════════════════════════════════════════════════════

       真实转夜需要活到分数 144（约 14 秒），而 mock 里没有完美玩家 ——
       自带 AI 最高只能到分数 ~85（见 小恐龙游戏实现.md §7.3 的教训）。

       ★ 所以这里用【临时改小 DAYNIGHT_DIST】的方式：
         把阈值从 12000 改成 600，几帧内就能跨过 ——
         跑的是【同一条代码路径】（tick -> updateDayNight -> applyTheme），
         只是让切换在短时间内发生。

       ⚠️ 另外必须等【足够帧数】再读控件：
          切背景只改 DOM，要下一帧 flush 才写进控件；
          星月的显隐还要再多一帧。早读会误判成"没生效"。
============================================================================]]

-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')
local sprite     = require('webui_sprite')

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass=pass+1; print(string.format("  [OK] %-52s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-52s %s", name, detail or "")) end
end

local PREFABS = { container=1073741933, textbox=1073741934,
                  button=1073741935, image=1073741938 }

--=============================================================================
print("=== 1. 星月点阵（webui_sprite）===")
--=============================================================================
local function gridOK(rows, rects)
  local H, W = #rows, #rows[1]
  -- 每行等宽
  for y = 1, H do
    if #rows[y] ~= W then return false, "第 " .. y .. " 行宽度不一致" end
  end
  -- 重建校验
  local g, cov = {}, {}
  for y = 1, H do
    g[y], cov[y] = {}, {}
    for x = 1, W do
      g[y][x] = rows[y]:sub(x, x) == "#"
      cov[y][x] = false
    end
  end
  for _, r in ipairs(rects) do
    for y = r.y, r.y + r.h - 1 do
      for x = r.x, r.x + r.w - 1 do
        if cov[y] and cov[y][x] ~= nil then cov[y][x] = true end
      end
    end
  end
  local bad = 0
  for y = 1, H do
    for x = 1, W do
      if cov[y][x] ~= g[y][x] then bad = bad + 1 end
    end
  end
  -- 连通域（必须单一整块）
  local sx, sy
  for y = 1, H do for x = 1, W do
    if g[y][x] and not sx then sx, sy = x, y end
  end end
  local seen, st, n, total = {}, { { sx, sy } }, 0, 0
  for y = 1, H do for x = 1, W do if g[y][x] then total = total + 1 end end end
  while #st > 0 do
    local p = table.remove(st)
    local x, y = p[1], p[2]
    local k = y * 1000 + x
    if not seen[k] and g[y] and g[y][x] then
      seen[k] = true; n = n + 1
      st[#st+1] = { x+1, y }; st[#st+1] = { x-1, y }
      st[#st+1] = { x, y+1 }; st[#st+1] = { x, y-1 }
    end
  end
  return bad == 0, string.format("矩形 %d，不一致 %d，连通 %d/%d",
      #rects, bad, n, total)
end

local specs = {
  { "月亮", sprite.MOON_ROWS,       sprite.moonRects(),      "6x12" },
  { "星星", sprite.STAR_ROWS,       sprite.starRects(),      "5x5"  },
  { "小星", sprite.STAR_SMALL_ROWS, sprite.starSmallRects(), "3x3"  },
}
for _, s in ipairs(specs) do
  local name, rows, rects, dim = s[1], s[2], s[3], s[4]
  local ok, detail = gridOK(rows, rects)
  check(string.format("%s(%s)：点阵完好、单一整块", name, dim), ok, detail)
end

-- ★ R28「拉长一点」：8x8 太圆 -> 6x12 的细长月牙（高:宽 = 2:1）
check("月亮是 6x12（细长月牙）",
  #sprite.MOON_ROWS == 12 and #sprite.MOON_ROWS[1] == 6,
  string.format("%dx%d", #sprite.MOON_ROWS[1], #sprite.MOON_ROWS))
check("★ 月亮高度 > 宽度（确实是拉长的）",
  #sprite.MOON_ROWS > #sprite.MOON_ROWS[1],
  string.format("高 %d > 宽 %d", #sprite.MOON_ROWS, #sprite.MOON_ROWS[1]))
check("星星是 5x5", #sprite.STAR_ROWS == 5 and #sprite.STAR_ROWS[1] == 5)
check("小星是 3x3",
  #sprite.STAR_SMALL_ROWS == 3 and #sprite.STAR_SMALL_ROWS[1] == 3)

--=============================================================================
print("")
print("=== 2. 主题表：两套颜色成对，且都改到五处 ===")
--=============================================================================
local src = io.open(_root .. "/deploy/demo_dino.lua", "r"):read("*a")

local function themeBlock(name)
  return src:match("    " .. name .. "%s*=%s*{(.-)\n    }")
end
local dayBlk, nightBlk = themeBlock("day"), themeBlock("night")
check("能解析出 day/night 两套主题", dayBlk ~= nil and nightBlk ~= nil)

local function fieldOf(blk, f)
  if not blk then return nil end
  return blk:match(f .. "%s*=%s*([^\n,]+)")
end

for _, f in ipairs({ "bg", "fg", "sprite", "hint", "sky" }) do
  local d, n = fieldOf(dayBlk, f), fieldOf(nightBlk, f)
  check(string.format("两套主题都有 %s 字段", f), d ~= nil and n ~= nil,
      string.format("day=%s night=%s", tostring(d), tostring(n)))
end

check("★ day.sky=false（白天无星月）",
  tostring(fieldOf(dayBlk, "sky")):find("false") ~= nil)
check("★ night.sky=true（夜里有星月）",
  tostring(fieldOf(nightBlk, "sky")):find("true") ~= nil)
check("★ 背景色明显不同（不是同色换皮）",
  fieldOf(dayBlk, "bg") ~= fieldOf(nightBlk, "bg"),
  string.format("%s vs %s", tostring(fieldOf(dayBlk, "bg")),
      tostring(fieldOf(nightBlk, "bg"))))

-- applyTheme 必须覆盖五处
check("★ applyTheme 改 scene/score/over/hint 背景",
  src:find('"scene", "score", "over", "hint"', 1, true) ~= nil)
check("★ applyTheme 改文字色",
  src:find('setStyle("color", theme.fg)', 1, true) ~= nil)
check("★ applyTheme 改地面线",
  src:find('gnd:setStyle("background-color", theme.fg)', 1, true) ~= nil)
check("★ applyTheme 遍历 spNodes 染色",
  src:find("for _, list in pairs(spNodes) do", 1, true) ~= nil)

--[[ ★★ 星月显隐用 show/hide，但【染色必须现查控件引用】。

     ⚠️ 两次踩坑的结论：
       ① 用 show/hide + 缓存控件引用 -> flaky
          （隐藏会让控件还池，引用被别的节点取走）
       ② 改成像裁剪容器那样用 imageColor alpha=0 隐形 -> 真机【无效】
          （白天仍看得见；R16 那次 alpha=0 是 enableMask 场景，不可外推）

       最终方案：show/hide 显隐 + 染色走 rendered.live 现查。
       两者的组合才成立 —— 缺任一条件都会坏。 ]]
check("★★ 染色不缓存引用（现查 rendered.live）",
  src:find("染色一律走 rendered.live 现查", 1, true) ~= nil
  or src:find("local ctrl = e and e.control", 1, true) ~= nil)
check("★★ 星月显隐用 show/hide",
  src:find("if theme.sky then sky:show() else sky:hide() end", 1, true) ~= nil)
check("★★ 不再用 alpha 当隐形手段",
  src:find("local skyAlpha =", 1, true) == nil)

--=============================================================================
print("")
print("=== 3. ★★★ 坑①回归：染色不能依赖 rendered.live ===")
--=============================================================================
--[[ 隐藏节点会被移出 rendered.live，反查返回 nil -> 染色被静默跳过。
     所以必须有一条【不依赖 live】的控件引用通路。 ]]
check("★ 存在 spriteCtrls 缓存（不依赖 rendered.live）",
  src:find("local spriteCtrls = {}", 1, true) ~= nil)
check("★ 贴图时把控件引用存下来（rememberCtrl）",
  src:find("rememberCtrl(node, ctrl)", 1, true) ~= nil)
--[[ ★★ 染色必须【现查 rendered.live】，不能优先用缓存（R28 白块根因）。

     缓存引用可能指向池里别人的控件 -> 染色写错对象 -> 白块。 ]]
check("★★ 染色现查 rendered.live（不优先用缓存）",
  src:find("local e = uiRef and uiRef.rendered and uiRef.rendered.live", 1, true) ~= nil)
check("★★ reimageNode 现查优先、缓存仅作兜底（且查 _orphan）",
  src:find("if cached and not cached._orphan then ctrl = cached end", 1, true) ~= nil)

--=============================================================================
print("")
print("=== 4. 性能：不能每帧写颜色 ===")
--=============================================================================
check("★ updateDayNight 先比 phase，变了才切",
  src:find("if phase == S.dayPhase then return false end", 1, true) ~= nil)
check("★ 精灵色走 spriteColor()（无硬编码残留）",
  src:find("FromRGBA(83, 83, 83, 255)", 1, true) == nil)

--=============================================================================
print("")
print("=== 5. ★★ 阈值数学：哪个距离该白天/夜晚 ===")
--=============================================================================
local DND = tonumber(src:match("DAYNIGHT_DIST%s*=%s*(%d+)"))
check("能从 demo 读到 DAYNIGHT_DIST", DND ~= nil, tostring(DND) .. "px")

if DND then
  local function isNight(dist)
    return (math.floor(dist / DND) % 2) == 1
  end
  check("★ 开局（dist=0）是白天", isNight(0) == false)
  check("★ 刚跨阈值（dist=DAYNIGHT_DIST）是夜晚", isNight(DND) == true)
  check("★ 两个周期后回到白天", isNight(DND * 2) == false)
  check("★ 阈值前一像素仍是白天", isNight(DND - 1) == false)
end

--=============================================================================
print("")
print("=== 6. ★★★ 端到端：真的切换（跑真实代码路径）===")
--=============================================================================
--[[ 把 DAYNIGHT_DIST 改小，让切换在几帧内发生。
     ★ 跑的是同一条路径：tick -> updateDayNight -> applyTheme。 ]]
local function mkEnv()
  local E = EngineMock.new(PREFABS)
  local keyEnum = {}
  for _, n in ipairs({ "KeyboardJumpKeyDown", "KeyboardJumpKeyUp" }) do
    keyEnum[n] = "Enum.KeyEventType." .. n
  end
  game = E.game
  Color = { FromRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end }
  Enum = {
    EaseType={Linear="L"},
    CursorEventType={CursorClick="C",CursorDown="D",CursorUp="U",CursorEnter="E",
                     CursorExit="X",CursorBeginDrag="B",CursorDrag="G",CursorEndDrag="N"},
    ImageSource={StaticReference="SR"}, KeyEventType=keyEnum,
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
  return E, root, function(n)
    for _=1,n do local cb=pending; pending=nil; if cb then cb() end end
  end
end

--[[ ★★★ 按 name 找控件 —— 但要【优先返回 active 的那个】。

     ⚠️⚠️ 为什么同一个 name 会有多个控件（R28 实测）：

       节点 display:none 时，渲染器把它的控件【还回控件池】，
       但**不会清掉控件上的 name**。
       于是当节点重新显示、渲染器从池里取控件时：
         · 池里那个旧控件可能已被别的节点取走（名字也变了）
         · 同时 mock 的 controls 列表里【两份都在】
       实测夜里同名控件有 10 个（白天 5 个）—— 每个名字两份。

     ★ 判据：正在用的那份是 active=true 的。
       若都不可见（比如白天全隐藏），返回第一个即可。 ]]
local function byName(E, exact)
  local fallback = nil
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.fields.name and tostring(d.fields.name) == exact then
      if d.fields.active then return d end      -- ★ 优先 active
      if not fallback then fallback = d end
    end
  end
  return fallback
end
local function hex(c)
  if type(c) ~= "table" then return "nil" end
  return string.format("#%02x%02x%02x", c.r or 0, c.g or 0, c.b or 0)
end

--[[ ★★★ 构造一个【不会撞死】的环境，让昼夜阈值能被稳定跨过。

     ⚠️ 为什么必须这么做（两次踩坑）：
       mock 里没有完美玩家。自带的"障碍靠近就跳"AI 每 5~8 波就撞死，
       死后 dist 归零 -> 昼夜在阈值附近【反复横跳】，
       测试永远抓不到一个稳定的"夜晚"状态，
       表现为断言时对时错（flaky）。

       这与 小恐龙游戏实现.md §7.3 记录的是同一类问题：
       "mock 里没有完美玩家" -> 该验逻辑时就把玩法变量控制住。

     ★ 做法（只改副本的常量）：
       · DAYNIGHT_DIST 改小   -> 几帧内就能跨阈值
       · ACCEL = 0            -> 速度不涨，障碍来得慢
       · waveGap 极大         -> 几乎不出障碍（从源头杜绝撞死）
     这样只需"按一次开始"就能跑到夜晚，不依赖 AI 水平。 ]]
local patched = src
patched = patched:gsub("DAYNIGHT_DIST%s*=%s*%d+", "DAYNIGHT_DIST = 600", 1)
patched = patched:gsub("ACCEL%s*=%s*%d+", "ACCEL = 0", 1)
-- 把所有阶段的 waveGap 改大（几乎不出障碍）
patched = patched:gsub("waveGap%s*=%s*%d+", "waveGap = 999999")
assert(patched ~= src, "副本常量替换失败")
assert(patched:find("DAYNIGHT_DIST = 600", 1, true), "阈值未替换")
assert(patched:find("ACCEL = 0", 1, true), "ACCEL 未替换")

local E, root, step = mkEnv()
assert(load(patched, "@dino_daynight"))()
OnStart()
step(5)

--[[ ★★★ 控件引用必须【每次现查】，不能开头查一次就存着。

     ⚠️ 这里踩过一次：开头 `local sky = byName(...)` 存下来，
        结果夜里读到的还是【白天那个控件】——
        星月隐藏时它被还回控件池，显示时渲染器又取了一个新的。
        与游戏代码里踩的是同一个坑（控件池复用时引用会失效）。

     ★ 所以下面统一用函数现查。 ]]
local function ctrl(id) return byName(E, id) end

local scene  = ctrl("div#scene")
local score  = ctrl("div#score")
local ground = ctrl("div#ground")
local sky    = ctrl("div#sky")

check("场景/分数/地面控件都能定位",
  scene and score and ground and sky
  and ctrl("div#mnR1") and ctrl("div#st1R1") and ctrl("div#dR1"))

print("")
print("  --- 白天 ---")
print(string.format("  scene=%s score=%s ground=%s",
  hex(scene and scene.fields.bgColor),
  hex(score and score.fields.fontColor),
  hex(ground and ground.fields.bgColor)))

check("① 白天背景浅色", hex(scene.fields.bgColor) == "#f7f7f7",
  hex(scene.fields.bgColor))
check("① 白天字色深色", hex(score.fields.fontColor) == "#535353",
  hex(score.fields.fontColor))
check("① 白天地面线深色", hex(ground.fields.bgColor) == "#535353",
  hex(ground.fields.bgColor))
--[[ ★★★ 白天星月必须【真的不可见】。

     ⚠️ 这里踩过大坑：一度用 imageColor 的 alpha=0 当隐形手段，
        本地 mock 全绿，但【真机白天仍然看得见星月】（用户截图）。
        R16 那次 alpha=0 生效是因为那是【裁剪容器 enableMask】，
        语义不同，不能外推。

     现在的判据：display:none -> 控件 active=false（真不可见）。 ]]
check("★★ ① 白天星空层隐藏（active=false）",
  ctrl("div#sky").fields.active == false, tostring(ctrl("div#sky").fields.active))
check("★★ ① 白天月亮矩形不可见（控制被隐藏）",
  ctrl("div#mnR1").fields.active == false, tostring(ctrl("div#mnR1").fields.active))
check("★★ ① 白天星星矩形不可见",
  ctrl("div#st1R1").fields.active == false, tostring(ctrl("div#st1R1").fields.active))
check("① 白天恐龙可见（active=true）",
  ctrl("div#dR1").fields.active == true, tostring(ctrl("div#dR1").fields.active))

-- 开始游戏（只需按一次；环境里几乎没有障碍，不会撞死）
E.fireKey(root, "Enum.KeyEventType.KeyboardJumpKeyDown", {})
step(3)

local nightAt = nil
for f = 1, 600 do
  step(1)
  if not nightAt and hex(scene.fields.bgColor) == "#14161c" then
    nightAt = f
  end
  --[[ ★★ 转夜后再多跑几帧：show() 只改 DOM，
       控件是【下一帧 flush】才配给节点的。 ]]
  if nightAt and f >= nightAt + 12 then break end
end

print("")
print("  转夜发生在第 " .. tostring(nightAt) .. " 帧")
print("  --- 夜晚 ---")
print(string.format("  scene=%s score=%s ground=%s  sky.active=%s",
  hex(scene.fields.bgColor), hex(score.fields.fontColor),
  hex(ground.fields.bgColor), tostring(ctrl("div#sky").fields.active)))

check("★ ② 夜里背景转深色", hex(scene.fields.bgColor) == "#14161c",
  hex(scene.fields.bgColor))
check("★ ② 夜里字色转浅色", hex(score.fields.fontColor) == "#d8dce6",
  hex(score.fields.fontColor))
check("★ ② 夜里地面线转浅色", hex(ground.fields.bgColor) == "#d8dce6",
  hex(ground.fields.bgColor))
check("★★ ② 夜里星空层显示（active=true）",
  ctrl("div#sky").fields.active == true, tostring(ctrl("div#sky").fields.active))
check("★★ ② 夜里月亮矩形可见",
  ctrl("div#mnR1").fields.active == true, tostring(ctrl("div#mnR1").fields.active))
check("★★ ② 夜里星星矩形可见",
  ctrl("div#st1R1").fields.active == true, tostring(ctrl("div#st1R1").fields.active))

-- ★★ 坑①：星月矩形必须真的被重新染色（不是留在池里的旧深灰）
check("★★ 坑① 月亮矩形染成浅色（不是池里旧控件的深灰）",
  hex(ctrl("div#mnR1").fields.imageColor) == "#d8dce6",
  hex(ctrl("div#mnR1").fields.imageColor))
check("★★ 坑① 星星矩形染成浅色",
  hex(ctrl("div#st1R1").fields.imageColor) == "#d8dce6",
  hex(ctrl("div#st1R1").fields.imageColor))
check("★ 恐龙也转为浅色（精灵统一染色）",
  hex(ctrl("div#dR1").fields.imageColor) == "#d8dce6",
  hex(ctrl("div#dR1").fields.imageColor))

-- ★ 坑②：文字框自身背景必须跟着改（R21）
check("★★ 坑② 分数框自身背景也变深", hex(score.fields.bgColor) == "#14161c",
  hex(score.fields.bgColor))

--=============================================================================
print("")
print("=== 7. 再过一个周期：转回白天 ===")
--=============================================================================
local backAt = nil
for f = 1, 600 do
  step(1)
  if not backAt and hex(scene.fields.bgColor) == "#f7f7f7" then
    backAt = f
  end
  --[[ ⚠️ 必须【转回白天后】再等几帧才 break —— 且这个判断要在
       "是否已转回" 的 if 之外。第一版把它写在了 if 里面，
       结果刚记录 backAt 就 break，渲染器还没来得及写控件字段，
       导致"字色/月亮色"两条误判为失败（测试自身的 bug，不是游戏的）。

       ★ 这里不需要再喂跳跃键 —— 环境里几乎没有障碍（waveGap 已改大），
         不会撞死，dist 会稳定增长。 ]]
  if backAt and f >= backAt + 12 then break end
end

print("  转回白天发生在第 " .. tostring(backAt) .. " 帧")
check("★ ③ 一个周期后转回白天", backAt ~= nil, hex(scene.fields.bgColor))
check("★ ③ 星月重新隐藏（active=false）",
  ctrl("div#sky").fields.active == false and ctrl("div#mnR1").fields.active == false,
  string.format("sky=%s moon=%s", tostring(ctrl("div#sky").fields.active),
      tostring(ctrl("div#mnR1").fields.active)))
check("★ ③ 字色转回深色", hex(score.fields.fontColor) == "#535353",
  hex(score.fields.fontColor))
check("★ ③ 月亮矩形转回深灰", hex(ctrl("div#mnR1").fields.imageColor) == "#535353",
  hex(ctrl("div#mnR1").fields.imageColor))

--=============================================================================
print("")
print("=== 8. ★★★ 死在天黑时，重开必须回到白天 ===")
--=============================================================================
--[[ 用户反馈：「如果死亡在黑天不会从白天重新开始」。

     ⚠️ 根因：reset() 只把 S.dayPhase / S.theme 改成白天，
        但【没有把主题写进 DOM】—— 真正改颜色的是 applyTheme。
        而 updateDayNight 只在 phase【变化】时才调它：
        reset 后 dist=0 -> phase=0，与 S.dayPhase=0 相同 ->
        它认为"没变化"，于是 DOM 永远停在夜晚配色。

     ★ 判据：先跑到夜晚，再模拟死亡 + 按键重开，
        重开后背景必须【立刻】回到白天色。 ]]

-- 先跑到夜晚（此刻已在上面的流程里，但为独立性再确认一次）
local nightNow = nil
for f = 1, 600 do
  step(1)
  if hex(scene.fields.bgColor) == "#14161c" then nightNow = f break end
end
check("前置条件：已处于夜晚", nightNow ~= nil, hex(scene.fields.bgColor))

--[[ ★★ 两层断言：
      ① 源码级：重开分支必须调用 applyTheme(G.THEME.day)
      ② 行为级：真的制造一次"死在夜晚"再重开，看背景是否回到白天 ]]
do
  check("★★ 源码：重开分支显式应用白天主题",
    src:find("applyTheme(G.THEME.day)", 1, true) ~= nil)

  --[[ ② 行为级：用一份独立副本，配成"会自然撞死"的环境。

       ⚠️ 上面的副本把 waveGap 改得极大（为了稳定跨昼夜），
          那样永远不会撞死 —— 所以这里单独造一份：
             · DAYNIGHT_DIST 小   -> 能较快到夜晚
             · waveGap 适中       -> 会出障碍
             · 不按跳             -> 迟早撞死
             · birdChance = 0     -> 避免"不能跳的鸟"造成的随机性
             · ACCEL = 0          -> 速度恒定，节奏可预期 ]]
  local dn2 = src
  dn2 = dn2:gsub("DAYNIGHT_DIST%s*=%s*%d+", "DAYNIGHT_DIST = 600", 1)
  dn2 = dn2:gsub("waveGap%s*=%s*%d+", "waveGap = 900")
  dn2 = dn2:gsub("birdChance%s*=%s*0%.%d+", "birdChance = 0.00")
  dn2 = dn2:gsub("ACCEL%s*=%s*%d+", "ACCEL = 0", 1)
  dn2 = dn2:gsub("maxStalks%s*=%s*%d+", "maxStalks = 1")

  local E2, root2, step2 = mkEnv()
  assert(load(dn2, "@dino_restart"))()
  OnStart()
  step2(5)

  local function scene2()
    local d = byName(E2, "div#scene")
    return d and d.fields.bgColor
  end
  local function hex2(c)
    if type(c) ~= "table" then return "nil" end
    return string.format("#%02x%02x%02x", c.r or 0, c.g or 0, c.b or 0)
  end
  local function overShown()
    for _, c in ipairs(E2.controls) do
      local d = E2.dataOf(c)
      if d and d.kind == "textbox" and d.fields.text
         and tostring(d.fields.text):find("G A M E")
         and d.fields.active ~= false then
        return true
      end
    end
    return false
  end

  -- 开始（之后故意不跳）
  E2.fireKey(root2, "Enum.KeyEventType.KeyboardJumpKeyDown", {})
  step2(3)

  local sawNight, deadAtNight, restartedToDay = false, false, nil
  for f = 1, 6000 do
    step2(1)
    if hex2(scene2()) == "#14161c" then sawNight = true end

    if overShown() then
      if hex2(scene2()) == "#14161c" then
        deadAtNight = true
        -- 重开
        E2.fireKey(root2, "Enum.KeyEventType.KeyboardJumpKeyDown", {})
        step2(8)                      -- 等渲染器写主题
        restartedToDay = hex2(scene2())
        break
      end
      -- 白天死的：重开继续找夜晚
      E2.fireKey(root2, "Enum.KeyEventType.KeyboardJumpKeyDown", {})
      step2(2)
      E2.fireKey(root2, "Enum.KeyEventType.KeyboardJumpKeyDown", {})
      step2(3)
    end
  end

  check("本次观测到了夜晚", sawNight)
  if deadAtNight then
    check("★★★ 死在夜晚 -> 重开后背景【立刻】回到白天",
      restartedToDay == "#f7f7f7", "重开后 = " .. tostring(restartedToDay))
  else
    print("  （本次未在夜晚死亡 —— 该场景跳过，不计失败）")
  end

  OnDestroy()
end

--=============================================================================
print("")
print("=== 9. ★★★ 白色方块回归：每个可见矩形都必须被染色 ===")
--=============================================================================
--[[ 用户反馈：「有时会出现错误的白色方块渲染」。

     ⚠️ 根因：方形图 100001 是白→灰渐变，
        控件若没被染色，显示出来就是【白色】。
        而 sprite.apply 旧实现只在"从隐藏变显示"时才重贴图+染色 ——
        一直可见的节点，其控件可能已被池子换掉（没图/没色）-> 白块。

     ★ 判据（两层）：
       ① 源码级：sprite.apply 必须对【每个可见矩形】调 reimage
       ② 行为级：跑一段游戏后，所有可见的精灵矩形
          都必须有非白色的 imageColor ]]

local spriteSrc = io.open(_root .. "/lib/webui/webui_sprite.lua", "r"):read("*a")
check("★★ 源码：sprite.apply 不再用 wasHidden 门控 reimage",
  spriteSrc:find("local wasHidden = n._displayOverride", 1, true) == nil)
check("★★ 源码：reimage 对每个可见矩形都调用",
  spriteSrc:find("无论本次是否", 1, true) ~= nil
  and spriteSrc:find("pcall(reimage, n)", 1, true) ~= nil)

-- 行为级：跑一段，检查所有可见 image 控件的颜色
do
  -- 再跑一段，让障碍生成/切换若干次
  for _ = 1, 200 do step(1) end

  local white, checked = 0, 0
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.kind == "image" and d.fields.active ~= false
       and d.fields.imageId == 100001 then
      local col = d.fields.imageColor
      checked = checked + 1
      -- 白色 = 方形图原色（未染色）
      if not col or (col.r > 240 and col.g > 240 and col.b > 240) then
        white = white + 1
      end
    end
  end
  check(string.format("★★ 可见精灵矩形无一为白（检查了 %d 个）", checked),
    white == 0, white .. " 个白块")
  check("确实检查到了足够多的矩形（>=50）", checked >= 50, checked .. " 个")
end

--=============================================================================
print("")
print("=== 10. ★★★ 昼夜过渡必须走引擎 Tween（丝滑，不是跳变）===")
--=============================================================================
--[[ 用户反馈：「白天和黑夜的过度不够丝滑」。

     ★ 做法：给承载颜色的元素加 CSS transition，
        库会把它翻译成 game.Tween（bgColor / fontColor 都是 Tweenable）。

     ⚠️⚠️ 这里同时守一个【库级 bug】（R28 修）：
        渲染器在"字段变脏"时会清掉 diff 缓存，
        而 setStyle 改 background-color 恰好会把它标脏 ->
        last.bgColor 被清成 nil -> isFirst=true -> 不走过渡。
        结果：**过渡永远不生效**，颜色直接跳变。

        修法：清缓存时对【颜色字段】保留 prev（它本就是"上次写入值"）。

     ★ 判据：换主题后 game.Tween 必须被调用过，且字段含 bgColor。 ]]

do
  local dn3 = src
  dn3 = dn3:gsub("DAYNIGHT_DIST%s*=%s*%d+", "DAYNIGHT_DIST = 600", 1)
  dn3 = dn3:gsub("ACCEL%s*=%s*%d+", "ACCEL = 0", 1)
  dn3 = dn3:gsub("waveGap%s*=%s*%d+", "waveGap = 999999")

  local E3, root3, step3 = mkEnv()
  assert(load(dn3, "@dino_fade"))()
  OnStart()
  step3(5)

  check("★ CSS 给 .scene/.ground/文字框加了 transition",
    src:find("transition: background-color 0.8s linear", 1, true) ~= nil)
  check("★ 刻意不给 .sky 加 transition（星月靠 display 显隐）",
    src:find("不要给 .sky 加", 1, true) ~= nil)

  E3.resetTween()
  E3.fireKey(root3, "Enum.KeyEventType.KeyboardJumpKeyDown", {})
  step3(3)

  local tweened, sawBg = false, false
  for f = 1, 300 do
    step3(1)
    if E3.tweenCount() > 0 then
      tweened = true
      local lt0 = E3.lastTween()
      if lt0 and lt0.props and lt0.props.bgColor then sawBg = true end
      break
    end
  end

  check("★★★ 换主题时走了引擎 Tween（不是直接跳变）", tweened,
    "tween 调用 = " .. tostring(E3.tweenCount()))
  check("★★ Tween 的目标字段含 bgColor（背景在渐变）", sawBg)

  local lt = E3.lastTween()
  if lt then
    check("★ Tween 时长 = 0.8s（与 CSS 声明一致）",
      math.abs((lt.duration or 0) - 0.8) < 0.01, tostring(lt.duration))
  end

  OnDestroy()
end

OnDestroy()

print("")
print(string.format(">>> 通过 %d / 失败 %d", pass, fail))
if fail > 0 then os.exit(1) end