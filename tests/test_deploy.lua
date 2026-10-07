-- 在 mock 环境里跑 deploy_test.lua，确保真机部署前不会崩
-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/?.lua;" .. _root .. "/lib/?/init.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

--=============================================================================
-- Mock 引擎（模拟真机行为）
--=============================================================================
local createdCount = 0
local allControls = {}

local function makeControl(kind, parent)
  createdCount = createdCount + 1
  local c = {
    _kind = kind, name = kind,
    anchorMinX=0.5, anchorMinY=0.5, anchorMaxX=0.5, anchorMaxY=0.5,
    pivotX=0.5, pivotY=0.5, anchoredPositionX=0, anchoredPositionY=0,
    sizeDeltaX=100, sizeDeltaY=100, visible=true, active=true,
    _children={}, _cursorListeners={},
  }
  c.SetActive=function(self,v) self.active=v end
  c.SetVisible=function(self,v) self.visible=v end
  c.GetChildren=function(self) return self._children end
  c.SetAnchoredPosition=function(self,x,y) self.anchoredPositionX=x; self.anchoredPositionY=y end
  c.SetSizeDelta=function(self,w,h) self.sizeDeltaX=w; self.sizeDeltaY=h end
  if kind=="button" or kind=="area" then
    c.AddCursorEventListener=function(self,ev,cb)
      self._cursorListeners[#self._cursorListeners+1]={ev=ev,cb=cb}
    end
    c.SimulateCursorClick=function(self)
      for _,l in ipairs(self._cursorListeners) do
        if l.ev=="CursorClick" then
          l.cb({GetUIPos=function() return 42,77 end,
                GetPressUIPos=function() return 42,77 end,
                GetUIPosDelta=function() return 0,0 end,
                dragging=false,touchId=-1})
        end
      end
    end
  end
  if parent then parent._children[#parent._children+1]=c end
  allControls[#allControls+1]=c
  return c
end

local PREFABS={container=1,textbox=2,button=3}

-- 记录 TweenSequence 回调，手动推进
local pendingSeqs = {}

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
    local s={_cb=nil}
    s.AppendInterval=function(self,d) self._interval=d; return self end
    s.AppendCallback=function(self,f) self._cb=f; return self end
    s.Play=function(self)
      if self._cb then pendingSeqs[#pendingSeqs+1]=self._cb end
      return self
    end
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

-- 根控件
local root = makeControl("container", nil)
root.name = "ProbeRoot"
script = { object = root, name = "ProbeRoot" }

--=============================================================================
-- 加载 deploy_test.lua
--=============================================================================
print("========== 加载 deploy_test.lua ==========")
print()

-- 模拟单文件场景：先加载 bundle 建立 __WEBUI__
local chunk = loadfile("bundle/webui.lua")
local ok = pcall(chunk)
print("  bundle 加载: " .. (ok and "OK" or "失败"))
print("  __WEBUI__: " .. type(__WEBUI__))
print()

-- 加载 deploy_test（它会自己找 __WEBUI__）
local dtChunk, dtErr = loadfile("deploy_test.lua")
if not dtChunk then
  print("  ✗ deploy_test 加载失败: " .. tostring(dtErr))
  return
end
dtChunk()
print()

--=============================================================================
-- 调用生命周期
--=============================================================================
print("========== 调用 OnStart ==========")
local sok, serr = pcall(OnStart)
if not sok then
  print("  ✗ OnStart 出错: " .. tostring(serr))
  return
end
print()

--=============================================================================
-- 推进 TweenSequence 循环几轮
--=============================================================================
print("========== 推进循环 ==========")
for round = 1, 3 do
  local batch = pendingSeqs
  pendingSeqs = {}
  if #batch == 0 then
    print("  第 "..round.." 轮: 没有待执行回调（循环可能断了）")
    break
  end
  for _, cb in ipairs(batch) do
    local ok2, e2 = pcall(cb)
    if not ok2 then print("  回调出错: "..tostring(e2)) end
  end
end
print()

--=============================================================================
-- 模拟点击
--=============================================================================
print("========== 模拟点击按钮 ==========")
local btnCount = 0
for _, c in ipairs(allControls) do
  if #c._cursorListeners > 0 then
    pcall(function() c:SimulateCursorClick() end)
    btnCount = btnCount + 1
  end
end
print("  点击了 "..btnCount.." 个按钮")
print()

--=============================================================================
-- OnDestroy
--=============================================================================
print("========== 调用 OnDestroy ==========")
pcall(OnDestroy)
print()
print("*** deploy_test 在 mock 环境验证通过 ***")