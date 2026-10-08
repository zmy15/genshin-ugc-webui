--[[ 本地试跑 align 探针模块（用 mock），确认：
       · 模块能跑通、不报错
       · 读回表打印正常
       · 五组对照的 ha / 框宽判定逻辑正确

     ⚠️ 本地结果【不构成真机结论】—— mock 无引擎开销、也不模拟
        真机渲染差异。这里只验证"探针本身没写错"。
]]

local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;" .. _root .. "/?.lua;"
             .. _root .. "/tests/?.lua;" .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')
local PREFABS = { container=1073741933, textbox=1073741934,
                  button=1073741935, image=1073741938 }
local E = EngineMock.new(PREFABS)

game = E.game
Color = { FromRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
          FromRGB=function(r,g,b) return {r=r,g=g,b=b} end }
Enum = {
  EaseType={Linear="Linear"},
  CursorEventType={CursorClick="CursorClick",CursorDown="CursorDown",
                   CursorUp="CursorUp",CursorEnter="CursorEnter",
                   CursorExit="CursorExit",CursorBeginDrag="CursorBeginDrag",
                   CursorDrag="CursorDrag",CursorEndDrag="CursorEndDrag"},
  ImageSource={StaticReference="SR"},
  KeyEventType={},
  -- ★ 对齐枚举的真名（client_control_api.md 第 557-559 行）
  TextHorizontalAlignmentLeft="L",
  TextHorizontalAlignmentMiddle="C",
  TextHorizontalAlignmentRight="R",
}

local root = E.makeControl("container", nil)
root.name = "Root"
E.setRoots({ root })
script = { object = root, EnableUpdate=function() end }

-- 捕获输出，便于断言
local captured = {}
local realPrint = print
print = function(...)
  local n = select('#', ...)
  local t = {}
  for i = 1, n do t[i] = tostring((select(i, ...))) end
  local line = table.concat(t, " ")
  captured[#captured + 1] = line
  realPrint(line)
end

-- 载入探针（它会自己 OnStart）
local src = io.open(_root .. "/deploy/probe.lua", "r"):read("*a")
assert(src, "读不到 deploy/probe.lua")
assert(load(src, "@probe"))()
OnStart()

print("")
print("=== 断言 ===")
local function has(pat)
  for _, l in ipairs(captured) do
    if l:find(pat, 1, true) then return true end
  end
  return false
end

local checks = {
  { "模块启动",   has("探针模块: align") },
  { "读回表标题", has("读回表：声明值 vs 引擎实际值") },
  { "A 组在表里", has("al-a1") },
  { "B 组在表里", has("al-b1") },
  { "C 组在表里", has("al-c1") },
  { "D 组在表里", has("al-d1") },
  { "E 组在表里", has("al-e1") },
  { "长文本在表里", has("al-l1") },
  { "判读表已打印", has("【判读表】") },
  { "给出了截图换算提示", has("截图像素 = 画布单位 x 1.6") },
  { "没有 after 异常", not has("after() 异常") },
  { "没有渲染失败", not has("渲染失败") },
}
local pass, fail = 0, 0
for _, c in ipairs(checks) do
  if c[2] then pass = pass + 1; print("  [OK] " .. c[1])
  else fail = fail + 1; print("  [XX] " .. c[1]) end
end

-- 统计读回表里是否全部判定为 ✅（mock 应当全部相符）
local okCount, badCount = 0, 0
for _, l in ipairs(captured) do
  if l:find("✅ 相符", 1, true) then okCount = okCount + 1 end
  if l:find("❌", 1, true) or l:find("⚠️ 宽度不符", 1, true) then
    badCount = badCount + 1
  end
end
print(string.format("  读回表: %d 行相符, %d 行不符", okCount, badCount))
if okCount >= 6 and badCount == 0 then pass = pass + 1
  print("  [OK] 六组对照在 mock 下全部相符（库写入正确）")
else fail = fail + 1
  print("  [XX] 读回表有异常行") end

print("")
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end