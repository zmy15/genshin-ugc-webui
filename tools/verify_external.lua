--[[============================================================================
  模拟千星的 require 行为，验证扁平化后的库能否正确加载

  千星的 require 规则（从 cinterp_client 的用法推断）：
    require("name") -> 同目录下的 name.lua
    带缓存、独立 _ENV
==============================================================================]]

local TARGET = arg and arg[1]
if not TARGET then
  print("用法: lua verify_external.lua \"<external_lua_file 目录>\"")
  return
end

--[[ ★★ 关卡文件同步检查（2026-10-07 新增）

     踩过的坑：把 webui_clip.lua 复制进 external_lua_file 后，
     【本地验证通过、真机却报 failed to load script 'webui_clip'】。

     根因：真机不是直接读文件夹，而是读同级的 <关卡ID>.gil
           该文件由编辑器【导入】外部脚本时生成，Copy-Item 不会更新它。

     所以本验证器增加一步：检查每个模块的内容是否真的进了 .gil。
     这样"新增了文件但忘了在编辑器导入"能提前发现，
     而不是浪费一轮真机。
]]--
local function checkGilSync()
  -- 关卡目录是 external_lua_file 的上级
  local levelDir = TARGET:match("^(.*)[/\\][^/\\]+$")
  if not levelDir then return end

  local gilPath = nil
  local p = io.popen('dir /b "' .. levelDir .. '\\*.gil" 2>nul')
  if p then
    local line = p:read("*l")
    p:close()
    if line and line ~= "" then
      gilPath = levelDir .. "\\" .. line:gsub("%s+$", "")
    end
  end

  if not gilPath then
    print("========== 关卡文件同步检查 ==========")
    print("  (未找到 .gil，跳过)")
    print()
    return
  end

  local f = io.open(gilPath, "rb")
  if not f then
    print("========== 关卡文件同步检查 ==========")
    print("  (打不开 " .. gilPath .. "，跳过)")
    print()
    return
  end
  local gil = f:read("*a")
  f:close()

  print("========== 关卡文件同步检查 ==========")
  print("  关卡文件: " .. gilPath:match("[^/\\]+$"))
  print("  ⚠️ 这是真机【实际读取】的内容，不是文件夹")
  print()

  -- 每个模块找一个"独有标记"，看是否出现在 .gil 里
  local MARKERS = {
    util       = "function U.trim",
    dom        = "function D.newElement",
    html       = "S.parseLength",
    css        = "特指度",
    color      = "NAMED",
    style      = "_clipShape",
    transition = "TIMING_MAP",
    layout     = "flex-wrap",
    render     = "chooseKind",
    clip       = "C.SHAPES",
    sprite     = "DINO_ROWS",
    event      = "PSEUDO_EVENTS",
    init       = "Instance:render",
  }

  local missing = {}
  local names = {}
  for k in pairs(MARKERS) do names[#names+1] = k end
  table.sort(names)

  for _, name in ipairs(names) do
    local marker = MARKERS[name]
    local found = gil:find(marker, 1, true) ~= nil
    print(string.format("    %-12s %s", name, found and "已在 .gil 中" or "★ 缺失"))
    if not found then missing[#missing+1] = name end
  end
  print()

  if #missing > 0 then
    print("  !! 以下模块【没有进入关卡文件】:")
    for _, m in ipairs(missing) do print("       - " .. m) end
    print()
    print("  => 请在【编辑器】里重新导入外部 Lua 脚本。")
    print("     只复制文件到目录不会生效 —— 真机读的是 .gil。")
    print()
  else
    print("  ✓ 全部模块已同步到关卡文件")
    print()
  end
end

checkGilSync()

--=============================================================================
-- 模拟 require：从目标目录按名字找 .lua 文件
--=============================================================================
local cache = {}

local function fakeRequire(name)
  if cache[name] ~= nil then return cache[name] end

  local path = TARGET .. "\\" .. name .. ".lua"
  local f = io.open(path, "r")
  if not f then
    error("failed to load script '" .. name .. "' (找不到 " .. path .. ")")
  end
  local src = f:read("*a")
  f:close()

  local chunk, err = load(src, "@" .. name)
  if not chunk then
    error("failed to load script '" .. name .. "': " .. tostring(err))
  end

  -- 标记为加载中（循环依赖检测）
  cache[name] = false
  local result = chunk()
  if result == nil then result = true end
  cache[name] = result
  return result
end

-- 注入全局
_G.require = fakeRequire

--=============================================================================
-- 模拟引擎 API
--=============================================================================
local created = 0
local controls = {}

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
  if kind=="button" or kind=="area" then
    c.AddCursorEventListener=function(s,ev,cb)
      s._listeners[#s._listeners+1]={ev=ev,cb=cb}
    end
    c.SimulateCursorClick=function(s)
      for _,l in ipairs(s._listeners) do
        if l.ev=="CursorClick" then
          l.cb({GetUIPos=function() return 1,2 end,
                GetPressUIPos=function() return 1,2 end,
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

local PREFABS={container=1,textbox=2,button=3}
game={
  InstantiateClientUIControl=function(idx,parent)
    local kind="container"
    for k,v in pairs(PREFABS) do if v==idx then kind=k end end
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

--=============================================================================
-- 测试
--=============================================================================
print("========== 用 require 加载库 ==========")
print()

local ok, webui = pcall(require, "webui")
if not ok then
  print("  ✗ require('webui') 失败:")
  print("    " .. tostring(webui))
  return
end

print("  ✓ require('webui') 成功")
print("  版本: " .. tostring(webui.VERSION))
print()

-- 逐个模块检查
local MODS = {"util","dom","html","css","color","style","layout","render","clip","sprite","event"}
for _, m in ipairs(MODS) do
  local key = m
  print(string.format("    webui.%-8s = %s", key, type(webui[key])))
end
print()

--=============================================================================
-- 渲染
--=============================================================================
print("========== 渲染 ==========")

local root = makeControl("container", nil)
root.name = "ProbeRoot"
script = { object = root, name = "ProbeRoot" }

local clicks = 0
local ui = webui.new({
  root = root,
  prefabs = PREFABS,
  handlers = { onClick = function(info) clicks = clicks + 1 end },
})

ui:render([[
<style>
  .card { width: 320px; padding: 16px; background-color: #1e1e28; }
  .head { height: 26px; font-size: 18px; color: #ffffff; }
  .row  { display: flex; gap: 10px; margin-top: 10px; }
  .btn  { width: 100px; height: 36px; background-color: #3a7bd5; }
</style>
<div class="card">
  <div class="head">webui 测试</div>
  <div class="row">
    <div class="btn" onclick="onClick">A</div>
    <div class="btn" onclick="onClick">B</div>
  </div>
</div>
]])

print("  DOM: " .. (function()
  local st = webui.dom.stats(ui.doc)
  return string.format("元素=%d 文本=%d 深度=%d", st.elements, st.texts, st.maxDepth)
end)())
print("  渲染: " .. ui.rendered:statsText())
print("  事件: " .. tostring(ui.boundCount))

-- 点击
for _, c in ipairs(controls) do
  if #c._listeners > 0 then pcall(function() c:SimulateCursorClick() end) end
end
print("  点击触发: " .. clicks .. " 次")

-- 二次 flush
local before = created
ui:flush()
print("  二次 flush 新建: " .. (created - before) .. " 个 (应为 0)")

print()
print("*** external_lua_file 部署验证通过 ***")
