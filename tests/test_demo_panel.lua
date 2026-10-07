--[[ 本地试跑 demo_panel.lua —— 用 engine_mock 验证页面能构建并渲染。

     ★ 目的：确保真机轮次不因脚本 bug 浪费。
     ★ mock 的渲染是假的，所以只能验证「逻辑跑通、控件建出来」，
       「视觉长什么样」必须真机看。
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

--[[ TweenSequence（演示页用它做逐帧循环）

     ⚠️ 陷阱：演示页的 tick() 会【递归】调用自己（每帧新建一个序列）。
        如果 mock 的 AppendCallback 立即执行，就变成无限递归 -> 卡死。
        真实引擎是【异步】的：AppendCallback 只是登记，等 Play 后按时间触发。

        所以这里必须模拟异步：回调【不立即执行】，只记录，
        等显式调用 pump() 时才触发一次。这样既能验证逻辑，又不会死循环。
]]--
local pending = {}
local seqCount = 0
game.TweenSequence = function()
  local s = {}
  function s:AppendCallback(f)
    pending[#pending+1] = f      -- 只登记，不执行
    return s
  end
  function s:AppendInterval(t) return s end
  function s:Append(t) return s end
  function s:Play() seqCount = seqCount + 1; return s end
  function s:Kill() return s end
  function s:SetLoops() return s end
  return s
end

--[[ 推进一帧：执行并清空本轮登记的回调。

     ★ 只执行【当轮】登记的回调 —— 回调里新登记的留给下一轮，
       否则又会无限递归。
]]--
local function pump()
  local cur = pending
  pending = {}
  for _, f in ipairs(cur) do
    pcall(f)
  end
end

printerr = function(...) io.stderr:write("[printerr] ", ...) end

print(">>> 试跑 demo_panel.lua")
print("")

local ok, err = pcall(function()
  dofile("deploy/demo_panel.lua")
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
  local grew = E.createdCount() - before
  print("")
  print(string.format(">>> 30 帧 flush 后新建控件 = %d （应接近 0，证明复用生效）", grew))

  OnDestroy()
end)

print("")
if ok then
  print(">>> 跑通，无崩溃")
  print(">>> mock 创建控件数 = " .. E.createdCount())
  -- 统计启用遮罩的控件
  local masked, byId = 0, {}
  for _, c in ipairs(E.controls) do
    local d = E.dataOf(c)
    if d and d.fields and d.fields.enableMask == true then
      masked = masked + 1
      byId[d.fields.imageId] = (byId[d.fields.imageId] or 0) + 1
    end
  end
  print(">>> 启用裁剪的控件 = " .. masked)
  for id, n in pairs(byId) do
    print(string.format("      imageId=%s  x%d", tostring(id), n))
  end
else
  print(">>> 【崩溃】 " .. tostring(err))
  os.exit(1)
end
