--[[ 图层顺序自检 —— ★★ 盯住"看不见但能点"这个静默 bug

     ══════════════════════════════════════════════════════════════════════
     真机事故：demo 的【退出按钮】和【手机跳跃按钮】都看不见，但都能点。

     根因有【两层】，本测试两层都守：

     ① 库侧：z-index 实现把节点编号成 0
        `SetSiblingIndex` 的索引是【父下的绝对槽位】（0..n-1，越大越靠上）。
        库只给"有 z-index 的节点"从 0 开始写 → 它们被塞到最底层，
        被天空/分数/地面盖住 = 视觉不可见、热区仍在 = "看不见却能点"。

     ② demo 侧：退出按钮原本排在场景内容【之前】，
        靠 z-index:10 才浮上来。一旦 z-index 失效它就沉底。

     ★ 现行方案（R32）：demo 【不依赖 z-index】，改用 DOM 顺序 ——
       任何"要盖住场景"的元素都排在场景内容之后。
       本测试断言的就是这个顺序，因此不依赖库的 z-index 路径。

     ⚠️ 为什么不断言"库把 z-index 排对了"：
        那条路在真机上会白屏（见 docs/小恐龙问题总清单.md 的模式 5 实例），
        已回退。现在【刻意不用 z-index】，所以这里守 DOM 顺序。
     ══════════════════════════════════════════════════════════════════════
]]

local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
             .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')

local PREFABS = { container=1073741933, textbox=1073741934,
                  button=1073741935, image=1073741938 }

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass=pass+1; print(string.format("  [OK] %-52s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-52s %s", name, detail or "")) end
end

local E = EngineMock.new(PREFABS)

local keyEnum = {}
for _, n in ipairs({
  "KeyboardJumpKeyDown","KeyboardJumpKeyUp",
  "KeyboardMoveLeftKeyDown","KeyboardMoveLeftKeyUp",
  "KeyboardMoveRightKeyDown","KeyboardMoveRightKeyUp",
  "KeyboardMoveForwardKeyDown","KeyboardMoveForwardKeyUp",
  "KeyboardMoveBackwardKeyDown","KeyboardMoveBackwardKeyUp",
  "KeyboardCraftspersonKey1Down","KeyboardCraftspersonKey1Up",
  "KeyboardCraftspersonKey2Down","KeyboardCraftspersonKey2Up",
  "KeyboardCraftspersonKey3Down","KeyboardCraftspersonKey3Up",
  "KeyboardCraftspersonKey4Down","KeyboardCraftspersonKey4Up",
  "ControllerJumpKeyDown","ControllerJumpKeyUp",
}) do keyEnum[n] = "Enum.KeyEventType." .. n end

_G.game = E.game
_G.Color = { FromRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
             FromRGB=function(r,g,b) return {r=r,g=g,b=b} end }
_G.Enum = {
  EaseType={Linear="Linear"},
  CursorEventType={CursorClick="C",CursorDown="D",CursorUp="U",CursorEnter="E",
                   CursorExit="X",CursorBeginDrag="B",CursorDrag="G",CursorEndDrag="N"},
  ImageSource={StaticReference="SR"},
  KeyEventType = keyEnum,
}

local root = E.makeControl("container", nil)
root.name = "Root"
E.setRoots({ root })
_G.script = { object = root, EnableUpdate=function() end }
_G.printerr = function(...) end

local pending = nil
game.TweenSequence = function()
  local s = {}
  function s:AppendCallback(cb) pending = cb; return s end
  function s:AppendInterval() return s end
  function s:Play() return s end
  function s:Kill() return s end
  return s
end

assert(load(io.open("deploy/demo_dino.lua", "r"):read("*a"), "@demo_dino"))()
OnStart()

local function step(n)
  for _ = 1, n do
    local cb = pending; pending = nil
    if cb then cb() end
  end
end
step(10)

--=============================================================================
print("\n=== 1. demo 页面里【不应再有 z-index】 ===")
--=============================================================================
--[[ ★ 这是本方案的核心约束：不用 z-index，就不碰库的缺陷路径。 ]]
do
  local src = io.open("deploy/demo_dino.lua", "r"):read("*a")
  local htmlStart = src:find("local HTML", 1, true)
  local cssStart  = src:find("local CSS", 1, true)
  local cssEnd    = src:find("\n]]", cssStart, true)
  local css = src:sub(cssStart, cssEnd)

  -- 去掉注释后再找（注释里提到 z-index 是允许的）
  local noComment = css:gsub("/%*.-%*/", "")
  local hits = 0
  for _ in noComment:gmatch("z%-index%s*:") do hits = hits + 1 end
  check("★★ CSS 里没有生效的 z-index 声明", hits == 0,
      hits == 0 and "0 处（图层完全靠 DOM 顺序）" or (hits .. " 处"))
end

--=============================================================================
print("\n=== 2. 读【引擎侧】的 scene 子控件顺序 ===")
--=============================================================================
local function sceneOrder()
  local rd = E.dataOf(root)
  local stageCtrl = rd.children[1]
  if not stageCtrl then return nil end
  local sd = E.dataOf(stageCtrl)
  for _, ch in ipairs(sd.children or {}) do
    local cd = E.dataOf(ch)
    if tostring(cd.fields.name) == "div#scene" then
      local t = {}
      for i, c2 in ipairs(cd.children or {}) do
        t[#t+1] = tostring(E.dataOf(c2).fields.name)
      end
      return t
    end
  end
  return nil
end

local function pos(list, nm)
  for i, v in ipairs(list) do if v == nm then return i end end
  return nil
end

local o = sceneOrder()
check("拿到 scene 子控件列表", o ~= nil and #o > 0, o and (#o .. " 个") or "nil")

if not o then
  print(string.format("\n>>> 通过 %d / 失败 %d", pass, fail))
  os.exit(1)
end

print("    引擎子序（越后越上）：")
for i, nm in ipairs(o) do
  print(string.format("      %2d %s", i - 1, nm))
end

local pQuit  = pos(o, "div#quitBtn")
local pJump  = pos(o, "div#jumpBtn")
local pScore = pos(o, "div#score")
local pModal = pos(o, "div#modal")
local pDino  = pos(o, "div#dino")

--=============================================================================
print("\n=== 3. ★★★ 按钮必须在场景内容【之上】（否则看不见却能点） ===")
--=============================================================================
check("★★ 退出按钮已建出", pQuit ~= nil)
check("★★ 跳跃按钮已建出", pJump ~= nil)

check("★★ 退出按钮在【分数框】之上", pQuit and pScore and pQuit > pScore,
    string.format("quit=%s score=%s", tostring(pQuit), tostring(pScore)))

check("★★ 退出按钮在【恐龙】之上（原来被它盖住）",
    pQuit and pDino and pQuit > pDino,
    string.format("quit=%s dino=%s", tostring(pQuit), tostring(pDino)))

check("★★ 跳跃按钮在【分数框】之上", pJump and pScore and pJump > pScore,
    string.format("jump=%s score=%s", tostring(pJump), tostring(pScore)))

--=============================================================================
print("\n=== 4. ★★ 跳跃按钮要盖住结算窗口的遮罩 ===")
--=============================================================================
check("★★ 跳跃按钮在【弹窗】之上（否则被遮罩压住）",
    pJump and pModal and pJump > pModal,
    string.format("jump=%s modal=%s", tostring(pJump), tostring(pModal)))

check("★★ 退出按钮在【弹窗】之下（弹窗要能盖住它）",
    pQuit and pModal and pQuit < pModal,
    string.format("quit=%s modal=%s", tostring(pQuit), tostring(pModal)))

--=============================================================================
print("\n=== 5. ★ 索引必须唯一且落在 0..n-1 ===")
--=============================================================================
do
  local seen, dup = {}, {}
  local bad = {}
  for _, it in ipairs(o) do
    if seen[it] then dup[#dup + 1] = it end
    seen[it] = true
  end
  check("★ 无重复子控件（同名只出现一次）", #dup == 0,
      #dup == 0 and "无重复" or table.concat(dup, ","))
  check("★ 控件数量合理（无丢失）", #o >= 15, #o .. " 个")
end

--=============================================================================
print("\n=== 6. ★ 连跑多帧：图层顺序必须稳定（不抖动） ===")
--=============================================================================
do
  local before = table.concat(sceneOrder(), ",")
  step(120)
  local after = table.concat(sceneOrder() or {}, ",")
  check("★ 连跑 120 帧后顺序不变", before == after,
      before == after and "稳定" or "变了")
end

--=============================================================================
print("\n=== 7. ★ 昼夜切换后仍正确（sky 显隐、重排风险） ===")
--=============================================================================
--[[ ★ 走到夜晚（sky 变可见），再检查按钮仍在最上层。 ]]
do
  step(1500)
  local o2 = sceneOrder() or {}
  local q2 = pos(o2, "div#quitBtn")
  local j2 = pos(o2, "div#jumpBtn")
  local s2 = pos(o2, "div#score")
  local d2 = pos(o2, "div#dino")
  check("★ 跑到夜里后，退出按钮仍在分数框/恐龙之上",
      q2 and s2 and d2 and q2 > s2 and q2 > d2,
      string.format("quit=%s score=%s dino=%s", tostring(q2),
          tostring(s2), tostring(d2)))
  check("★ 跑到夜里后，跳跃按钮仍在最上层",
      j2 == #o2, string.format("jump=%s / 共 %d", tostring(j2), #o2))
end

print("")
print(string.format(">>> 通过 %d / 失败 %d", pass, fail))
if fail > 0 then os.exit(1) end