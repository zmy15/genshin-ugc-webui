--[[============================================================================
  test_sprite_reassert.lua  ——  ★★★ 白色障碍回归（R29）

     ══════════════════════════════════════════════════════════════════════
     用户反馈
     ══════════════════════════════════════════════════════════════════════

       「障碍物的渲染有问题，是白色的，这里有个白色的仙人掌」
       「是固定间隔出现的，一个白色的，一个正常的」

       ——即同屏两个障碍，固定会有【一个】是白块。

     ══════════════════════════════════════════════════════════════════════
     机制（为什么精灵会变成白块）
     ══════════════════════════════════════════════════════════════════════

       拼像素图用的是 image 控件 + 方形图 100001。
       而 100001 是【白→灰渐变】—— 所以：

         · 没调 SetImage  -> 控件显示模板自带的图（真机上就是白的）
         · 调了但没染色   -> 显示 100001 的原色（白→灰）-> 接近白

       => 「白块」= 这个矩形控件没被正确贴图/染色。

     ══════════════════════════════════════════════════════════════════════
     ★★ 本套件守的不变量
     ══════════════════════════════════════════════════════════════════════

       贴图/染色【不能只在换姿态那一刻做】。原因是时序：

         引擎每帧 = onTick（游戏逻辑，生成障碍）-> flush（渲染，建控件）
         生成障碍那一帧：setPose -> sprite.apply -> reimage
                          ▲ 此刻渲染器【还没】建出这些控件
                            （节点上一帧 display:none，不在 rendered.live）
                          => reimage 查不到控件，静默跳过（不报错）
         紧接着 flush 才建出控件 -> 没图没色 = 白块

       ⚠️ 而 sprite.apply 只在【换姿态】时调用：
          · 仙人掌生成后不再换姿态 -> 白块一直留到出屏（用户看到的）
          · 翼龙扇翅周期性换姿态   -> 白块过一会儿自己好了

       ★ 所以正确做法是【每帧对可见矩形补一次贴图+染色】：
         sprite.reassert(nodes, reimage, skip)。

     ══════════════════════════════════════════════════════════════════════
     ⚠️ 诚实说明：为什么这里守的是"结构性不变量"而不是"真机复现"
     ══════════════════════════════════════════════════════════════════════

       本地 mock 的控件池【不会】给出一个"从未贴过图"的控件
       （池里的控件都带着上次的 imageId），
       而真机上池复用时控件会回到模板默认外观（白）。
       => 这个 bug【无法在本地 mock 里复现】。

       所以本套件做两件事：
         ① 行为级：验证 reassert 的语义（可见的都补、隐藏的跳过）
         ② 源码级：验证 demo 真的每帧调了它，且没引入"按节点缓存颜色"
            这种在控件换主时会撒谎的优化
       并附带真机探针 deploy/probe_white.lua 供实地取证。
============================================================================]]

-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local sprite = require('webui_sprite')

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass=pass+1; print(string.format("  [OK] %-52s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-52s %s", name, detail or "")) end
end

--=============================================================================
print("=== 1. sprite.reassert 的语义 ===")
--=============================================================================
do
  -- 造 5 个假节点：3 个可见、2 个隐藏
  local seen = {}
  local nodes = {}
  for i = 1, 5 do
    local id = i
    nodes[i] = {
      _displayOverride = (i > 3) and "none" or nil,
      _id = id,
    }
  end

  local n = sprite.reassert(nodes, function(node)
    seen[#seen + 1] = node._id
  end, function(node)
    return node._displayOverride == "none"
  end)

  check("★ reassert 返回处理数 = 可见矩形数", n == 3, tostring(n))
  check("★ 可见的都被处理（1,2,3）",
    #seen == 3 and seen[1] == 1 and seen[2] == 2 and seen[3] == 3,
    table.concat(seen, ","))
  check("★ 隐藏的被跳过（4,5 不在）",
    seen[1] ~= 4 and seen[2] ~= 4 and seen[3] ~= 4)
end

do
  -- 无 reimage 回调时不炸
  local ok = pcall(function() return sprite.reassert({}, nil) end)
  check("★ reimage 为 nil 时安全返回", ok)
end

do
  --[[ ★ 节点表里 pcall 掉 reimage 抛错即可。

       ⚠️ 不能用 `{ nil, {...} }` 来造"空洞" ——
          Lua 里首元素为 nil 的表，# 长度是【未定义】的，
          reassert 只按 #nodes 遍历，本来就看不到空洞。
          那种写法测的是 Lua 语义，不是本函数的行为。 ]]
  local cnt = 0
  local ok = pcall(function()
    cnt = sprite.reassert({ { _displayOverride = nil } }, function() end)
  end)
  check("★ 单个节点正常处理", ok and cnt == 1, tostring(cnt))
end

do
  -- reimage 内部抛错被 pcall 吞掉，不中断整批
  local cnt = 0
  local ok = pcall(function()
    cnt = sprite.reassert(
      { { _displayOverride = nil }, { _displayOverride = nil } },
      function() error("boom") end)
  end)
  check("★ reimage 抛错不中断（pcall 兜住）", ok and cnt == 2, tostring(cnt))
end

--=============================================================================
print("")
print("=== 2. ★★★ demo 必须每帧补帖图 ===")
--=============================================================================
local src = io.open(_root .. "/deploy/demo_dino.lua", "r"):read("*a")

check("★★ demo 定义了 reassertSprites",
  src:find("local function reassertSprites()", 1, true) ~= nil)
check("★★★ demo 在 tick 里【每帧】调用 reassertSprites",
  src:find("\n  reassertSprites()", 1, true) ~= nil)

--[[ ★★ 调用必须在 S.started 早退【之前】。

     否则开局（还没按开始键）恐龙不会被补帖图 -> 开局恐龙是白的。 ]]
do
  local callPos = src:find("\n  reassertSprites()", 1, true)
  local startedPos = src:find("if not S.started then", 1, true)
  check("★★ 补帖图在【未开始早退】之前（否则开局恐龙是白的）",
    callPos ~= nil and startedPos ~= nil and callPos < startedPos,
    string.format("call@%s started@%s", tostring(callPos), tostring(startedPos)))
end

--[[ ★★ 补帖图必须覆盖【全部精灵】，不能只挑障碍。

     恐龙 4 个别名指向同一份节点表 -> 要按表身份去重，
     否则同一份被处理 3 遍（浪费）。 ]]
check("★★ reassertSprites 遍历 spNodes 全表",
  src:find("for _, list in pairs(spNodes) do", 1, true) ~= nil)
check("★★ 按节点表身份去重（恐龙有 4 个别名）",
  src:find("local done = {}", 1, true) ~= nil
  and src:find("done[list] = true", 1, true) ~= nil)

--=============================================================================
print("")
print("=== 3. ★★★ 不得引入「按节点缓存颜色」的优化 ===")
--=============================================================================
--[[ ⚠️⚠️ 缓存挂在【节点】上，而节点的控件会被共享池换掉：

       节点隐藏 -> 控件还池 -> 别的节点取走 -> 再取回来可能是另一个控件。

     于是"上次已经染过"的记录会撒谎 -> 跳过本次染色 -> 白块留下。
     （写这版时真的踩了一次：加了 _imgCol 缓存后 mock 里白块反而变多。）

     ★ 判据：reimageNode 里不得出现 node.xxx 形式的颜色/图 ID 缓存。 ]]
local rnStart = src:find("local function reimageNode(node)", 1, true)
-- ★ 找函数体结束：从起点往后找第一个【行首】的 "end"
local rnBody = ""
if rnStart then
  local tail = src:sub(rnStart)
  local relEnd = tail:find("\nend", 1, true)
  if relEnd then rnBody = tail:sub(1, relEnd) end
end

check("★★ 能定位 reimageNode 函数体", #rnBody > 0, #rnBody .. " 字节")
check("★★★ reimageNode 不缓存颜色到节点上（_imgCol）",
  rnBody:find("node._imgCol", 1, true) == nil)
check("★★★ reimageNode 不缓存图 ID 到节点上（_imgId）",
  rnBody:find("node._imgId", 1, true) == nil)
check("★★ reimageNode 每次都真写 SetImage",
  rnBody:find("SetImage", 1, true) ~= nil)
check("★★ reimageNode 每次都真写 imageColor",
  rnBody:find("imageColor", 1, true) ~= nil)

--=============================================================================
print("")
print("=== 4. 真机探针可用 ===")
--=============================================================================
do
  local ok, probe = pcall(function()
    return dofile(_root .. "/deploy/probe_white.lua")
  end)
  check("★ deploy/probe_white.lua 可加载", ok, tostring(probe))
  if ok and type(probe) == "table" then
    check("★ 探针导出 scan 函数", type(probe.scan) == "function")
    -- 空环境调用不应抛错
    local ok2 = pcall(function() probe.scan(nil, {}, {}) end)
    check("★ 空环境下 scan 不抛错", ok2)
  end
end

--=============================================================================
print("")
print(string.format(">>> 通过 %d / 失败 %d", pass, fail))
if fail > 0 then os.exit(1) end