--[[ demo_dino 的【视觉样式】回归 —— 守住真机上踩过的两个坑

     ★ 背景（2026-10-08 真机截图逐像素量得）：
       不写 background-color 时，引擎给文本框画【默认深色】底。
       Game Over 字色是深灰 #535353 -> 底(49,48,48) vs 字(46,45,45)，
       对比度只有 3，文字几乎完全看不见。
       => 所有带文字的框都【必须显式】指定背景色。

     ★ 居中：
       不设 text-align 时文字从框左边开始排。
       实测左边距 3.8px / 右边距 473.8px（差 470px），严重偏左。
       => 需要居中的框【必须显式】写 text-align。

     本测试断言这两个属性真的写进了引擎控件的字段。
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
  if cond then pass=pass+1; print(string.format("  [OK] %-50s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-50s %s", name, detail or "")) end
end

local E = EngineMock.new(PREFABS)
local keyEnum = {}
for _, n in ipairs({"KeyboardJumpKeyDown","KeyboardJumpKeyUp"}) do
  keyEnum[n] = "Enum.KeyEventType." .. n
end
game = E.game
Color = { FromRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end }
Enum = {
  EaseType={Linear="L"},
  CursorEventType={CursorClick="C",CursorDown="D",CursorUp="U",CursorEnter="E",
                   CursorExit="X",CursorBeginDrag="B",CursorDrag="G",CursorEndDrag="N"},
  ImageSource={StaticReference="SR"},
  KeyEventType = keyEnum,
  -- ★ 对齐枚举（真机真名，见 client_control_api.md）
  TextHorizontalAlignmentLeft="L",
  TextHorizontalAlignmentMiddle="C",
  TextHorizontalAlignmentRight="R",
}
local root = E.makeControl("container", nil)
root.name = "Root"
E.setRoots({ root })
script = { object = root, EnableUpdate=function() end }

local pending = nil
game.TweenSequence = function()
  local s = {}
  function s:AppendCallback(cb) pending = cb; return s end
  function s:AppendInterval() return s end
  function s:Play() return s end
  function s:Kill() return s end
  return s
end

local src = io.open("deploy/demo_dino.lua"):read("*a")
assert(src, "读不到 deploy/demo_dino.lua")
assert(load(src, "@demo_dino"))()
OnStart()

local function step(n) for _=1,n do local cb=pending; pending=nil; if cb then cb() end end end

--[[ ★ 采样时机很重要（display:none 的框不写 text）：
       · 提示文字  -> 只在【未开始】时可见 -> 先采
       · Game Over -> 只在【撞了之后】可见 -> 后采
     所以分两次收集，不能用一次快照。 ]]

local textboxes = {}
local function collectTexts()
  --[[ ⚠️ 每次都重建列表，不能跨轮复用。

       mock 的 __newindex 是【按引用】存表的，而库的 setColor 每帧可能
       传入新的颜色表 —— 上一轮缓存的 { d = ... } 里的 d.fields 会被
       后续写入改掉，导致"读到上一轮的旧值"。
       （我就是在这里踩了一次：提示文字的 bg 读成了 23/83 的旧值。） ]]
  textboxes = {}
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.kind == "textbox" then
      local txt = d.fields.text
      --[[ 只收【真正显示文字】的控件。

           色块（地面/恐龙/障碍）也是 textbox，text 为空但 bgColor
           是 #535353（那是真的色块底色，不是"忘了写文字背景"）。
           判据：必须同时有 fontColor —— 色块从不设字色。 ]]
      if txt and txt ~= "" and d.fields.fontColor ~= nil then
        textboxes[#textboxes+1] = { d = d, txt = txt }
      end
    end
  end
end
local function findBy(pat)
  for _, t in ipairs(textboxes) do
    if t.txt:find(pat) then return t.d end
  end
end

-- 第一轮：先跑几帧（字段在 flush 时才写下去），未开始 -> 提示可见
step(3)
collectTexts()
local hintD = findBy("按")

-- 开始游戏 -> 空跑到撞 -> 第二轮（Game Over 可见）
E.fireKey(root, "Enum.KeyEventType.KeyboardJumpKeyDown", {})
step(900)
step(10)
collectTexts()

local overD  = findBy("G A M E")
local scoreD = findBy("HI ")

--=============================================================================
print("\n=== 1. 每个含文字的框都必须有显式背景色 ===")
--=============================================================================
--[[ ★ 这是真机踩过的坑：不写 background-color -> 引擎给默认深色底。

     ⚠️ 判据不能用 `bgColor == nil` —— 真机的文本框【本来就有】默认底色
        （engine_mock 已忠实模拟成 #535353），所以字段永远不为 nil。
        真正要验的是【对比度】：字色与底色的亮度差够不够。
     这正是 R21 在真机上"字看不见"的直接原因。 ]]
print(string.format("  共采样 %d 个有文字的文本框", #textboxes))

local function lum(c)
  if type(c) ~= "table" then return nil end
  return ((c.r or 0) + (c.g or 0) + (c.b or 0)) / 3
end

local lowContrast = {}
for _, t in ipairs(textboxes) do
  local fg, bg = lum(t.d.fields.fontColor), lum(t.d.fields.bgColor)
  if fg and bg and math.abs(fg - bg) < 100 then
    lowContrast[#lowContrast+1] = string.format("%s(%.0f)", t.txt:sub(1, 10),
        math.abs(fg - bg))
  end
end
check("★ 所有文字框的对比度 > 100（真机默认底是深色 #535353）",
    #lowContrast == 0,
    #lowContrast == 0 and "全部达标"
        or ("对比度不足: " .. table.concat(lowContrast, " / ")))

--=============================================================================
print("\n=== 2. Game Over：居中 + 浅底深字 ===")
--=============================================================================
check("找到 Game Over 控件", overD ~= nil)

if overD then
  -- 居中：horizontalAlignment 应为 Middle
  local ha = overD.fields.horizontalAlignment
  check("★ Game Over 水平居中（horizontalAlignment=Middle）",
      ha == "C", "ha=" .. tostring(ha))

  -- 背景：必须与页面底色一致（视觉上无底条）
  local bg = overD.fields.bgColor
  local function hex(c)
    if type(c) ~= "table" then return tostring(c) end
    return string.format("#%02x%02x%02x", c.r or 0, c.g or 0, c.b or 0)
  end
  check("★ Game Over 背景 = 页面底色 #f7f7f7（视觉无底条）",
      hex(bg) == "#f7f7f7",
      "bg=" .. hex(bg) .. "（引擎默认深色底是 #535353）")

  -- 字色必须是深色（与浅底形成对比）
  local fc = overD.fields.fontColor
  check("★ Game Over 字色 = 深灰 #535353", hex(fc) == "#535353",
      "fontColor=" .. hex(fc))

  -- 算一下对比度（这就是真机上"看不清"的根因）
  local bl = ((bg.r or 0) + (bg.g or 0) + (bg.b or 0)) / 3
  local fl = ((fc.r or 0) + (fc.g or 0) + (fc.b or 0)) / 3
  local contrast = math.abs(bl - fl)
  check("★ 文字/背景对比度 > 100（真机原为 3）", contrast > 100,
      string.format("对比度 %.0f", contrast))
end

--=============================================================================
print("\n=== 3. 分数栏：靠右对齐 ===")
--=============================================================================
check("找到分数控件", scoreD ~= nil)
if scoreD then
  check("分数靠右（horizontalAlignment=Right）",
      scoreD.fields.horizontalAlignment == "R",
      "ha=" .. tostring(scoreD.fields.horizontalAlignment))
  check("分数有显式背景色", scoreD.fields.bgColor ~= nil)
end

--=============================================================================
print("\n=== 4. 提示文字：居中 + 显式背景 ===")
--=============================================================================
check("找到提示控件（未开始时采样）", hintD ~= nil)
if hintD then
  check("提示居中", hintD.fields.horizontalAlignment == "C",
      "ha=" .. tostring(hintD.fields.horizontalAlignment))
  check("提示有显式背景色", hintD.fields.bgColor ~= nil)
end

print("")
print(string.format(">>> 通过 %d / 失败 %d", pass, fail))
if fail > 0 then os.exit(1) end
