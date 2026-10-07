--[[ 本地试跑 deploy/demo_feature.lua —— 用 engine_mock 验证页面能构建并渲染。

     ★ 目的：确保真机轮次不因脚本 bug 浪费。
     ★ mock 的渲染是假的，只能验证「逻辑跑通、控件建出来、形状设置成功」，
       「视觉长什么样」必须到真机看。

     本文件与 test_demo_panel.lua 同构，只是把试跑对象换成 demo_feature。
]]--

-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')

local PREFABS = {
  container = 1073741933,
  textbox   = 1073741934,
  button    = 1073741935,
  image     = 1073741938,
}

local E = EngineMock.new(PREFABS)

game  = E.game
Color = { FromRGBA = function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
          FromRGB  = function(r,g,b) return {r=r,g=g,b=b} end }

Enum = {
  EaseType = { Linear="Linear", InQuad="InQuad", OutQuad="OutQuad", InOutQuad="InOutQuad" },
  CursorEventType = {
    CursorClick="CursorClick", CursorDown="CursorDown", CursorUp="CursorUp",
    CursorEnter="CursorEnter", CursorExit="CursorExit",
    CursorBeginDrag="CursorBeginDrag", CursorDrag="CursorDrag",
    CursorEndDrag="CursorEndDrag",
  },
  TextHorizontalAlignmentLeft="L",
  TextHorizontalAlignmentMiddle="C",
  TextHorizontalAlignmentRight="R",
  ImageSource = { StaticReference = "Enum.ImageSource.StaticReference" },
  ImageType = { Basic = "Enum.ImageType.Basic" },
}

local root = E.makeControl("container", nil)
root.name = "Root"                 -- ★ mock 按 name 查根控件
E.setRoots({ root })
script = { object = root, EnableUpdate = function() end, GetParam = function() return nil end }

--[[ TweenSequence：演示页的 tick() 会递归新建序列，
     若 mock 立即执行回调会变成无限递归 -> 卡死。
     所以必须模拟异步：只登记，等 pump() 才触发。 ]]--
local pending = {}
local seqCount = 0
game.TweenSequence = function()
  local s = {}
  function s:AppendCallback(f)
    pending[#pending+1] = f
    return s
  end
  function s:AppendInterval(t) return s end
  function s:Append(t) return s end
  function s:Play() seqCount = seqCount + 1; return s end
  function s:Kill() return s end
  function s:SetLoops() return s end
  return s
end

local function pump()
  local cur = pending
  pending = {}
  for _, f in ipairs(cur) do
    pcall(f)
  end
end

printerr = function(...) io.stderr:write("[printerr] ", ...) end

print(">>> 试跑 demo_feature.lua")
print("")

--=============================================================================
-- 断言框架（与 test_wrap.lua 一致）
--=============================================================================
local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-30s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-30s %s", name, detail or "")) end
end

local grew30 = 0
local ok, err = pcall(function()
  dofile("deploy/demo_feature.lua")
  assert(type(OnInit) == "function", "OnInit 缺失")
  assert(type(OnStart) == "function", "OnStart 缺失")
  assert(type(OnUpdate) == "function", "OnUpdate 缺失")
  assert(type(OnDestroy) == "function", "OnDestroy 缺失")
  OnInit()
  OnStart()
  OnUpdate(0.016)

  -- ★ 推进若干帧，验证逐帧循环稳定（不新建控件）
  local before = E.createdCount()
  for i = 1, 30 do pump() end
  grew30 = E.createdCount() - before

  OnDestroy()
end)

print("")
if ok then
  check("demo 跑通无崩溃", true)
  check("30 帧 flush 不新建控件", grew30 == 0,
      string.format("新建 %d 个（期望 0，证明复用生效）", grew30))
  check("建出了控件", E.createdCount() > 0,
      "created=" .. E.createdCount())

  --[[ 统计图片控件。

       ★ 这里断言的是「六种形状都真的被 SetImage 过」，
         而不是只看 demo 自己打印的成功计数 ——
         打印可能说谎（前一版就报"已设置 8 个"但实际只有 1 个 image 控件）。
  ]]--
  local masked, byId, usedShapeIds = 0, {}, {}
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    local f = d and d.fields or {}
    if f.imageId then
      usedShapeIds[f.imageId] = (usedShapeIds[f.imageId] or 0) + 1
    end
    if f.enableMask == true then
      masked = masked + 1
      byId[f.imageId] = (byId[f.imageId] or 0) + 1
    end
  end

  -- 六种预置形状都应被用到（100001..100006）
  local SHAPES = { 100001, 100002, 100003, 100004, 100005, 100006 }
  local missing = {}
  for _, id in ipairs(SHAPES) do
    if not usedShapeIds[id] then missing[#missing + 1] = id end
  end
  check("六种预置形状都被用到", #missing == 0,
      #missing == 0 and "100001..100006 齐全"
                   or ("缺 " .. table.concat(missing, ",")))

  -- 启用遮罩的控件：头像(圆) + 大圆(圆) + 矩形裁剪 = 3
  check("启用遮罩的控件 = 3", masked == 3,
      string.format("实际 %d 个", masked))
  check("圆形遮罩 x2", (byId[100002] or 0) == 2,
      string.format("CIRCLE 实际 %d 个", byId[100002] or 0))
  check("矩形遮罩 x1", (byId[100001] or 0) == 1,
      string.format("SQUARE 实际 %d 个", byId[100001] or 0))

  --[[ ★ 真机硬约束：文字框高 >= 字号 × 1.9
       框太矮时引擎字号自适应会把字压没（症状是"文字凭空消失"）。 ]]--
  local badRatio, textCount = 0, 0
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.kind == "textbox" then
      local f = d.fields or {}
      if f.text and f.text ~= "" and f.fontSize and f.fontSize > 0 and f.sizeDeltaY then
        textCount = textCount + 1
        if f.sizeDeltaY / f.fontSize < 1.9 then badRatio = badRatio + 1 end
      end
    end
  end
  check("文字框高 >= 字号 x1.9", badRatio == 0,
      string.format("检查 %d 个有文字的控件，违反 %d 个", textCount, badRatio))
  check("确实有文字被渲染", textCount > 10,
      string.format("有文字的控件 %d 个", textCount))

  print("")
  print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
  if fail > 0 then os.exit(1) end
else
  print(">>> 【崩溃】 " .. tostring(err))
  os.exit(1)
end