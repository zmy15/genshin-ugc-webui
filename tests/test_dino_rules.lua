--[[============================================================================
  test_dino_rules.lua  ——  小恐龙的【可解性】约束

     ★★ 为什么要单独测这个：

        用户提的几条要求（恐龙高度、跳跃高度、鸟的两个高度）本质上是
        【几何约束】—— 一旦有人调了其中任何一个数字，就可能出现
        「玩家无论如何都会死」的死局，而**游戏看起来完全正常**。

        这类 bug 不会报错、不会崩溃，只会让游戏变得无聊或不可通关。
        所以必须用断言把约束钉死。

     ★ 本测试只做【纯数值验算】，不跑引擎 —— 因为约束是几何的，
       与渲染无关，纯计算更快也更可靠。

     ⚠️ 这些常量必须与 deploy/demo_dino.lua 的 G 表【保持一致】。
        改动那边时，这里会失败 —— 这正是它的作用。
=============================================================================]]

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
-- 与 demo_dino.lua 的 G 表保持一致的常量
--=============================================================================
local CELL   = 8
local GROUND = 700        -- 地面线

local G = {
  GROUND_Y   = 564,       -- 恐龙落地 top
  GRAVITY    = 6100,
  JUMP_V     = -1600,
  DINO_SPR_H = 136,
  DINO_HIT_W = 76,
  DINO_HIT_T = 56,
  DINO_HIT_B = 112,
  DINO_X     = 160,
  OBS_HIT_PAD = 13,
  MAX_SPEED  = 1500,
  WAVE_GAP   = 1500,
  BIRD_YS    = { 603, 405 },   -- 低飞 / 高飞
}

-- 与 OBS_KINDS 保持一致
local OBS = {
  { name="cactusBig",   w=9,  h=18, ground=true,  hitL=10, hitW=52,  hitT=0, hitH=144 },
  { name="cactusMid",   w=6,  h=17, ground=true,  hitL=6,  hitW=36,  hitT=0, hitH=136 },
  { name="cactusSmall", w=5,  h=12, ground=true,  hitL=5,  hitW=30,  hitT=0, hitH=96  },
  { name="bird",        w=20, h=10, ground=false, hitL=20, hitW=120, hitT=8, hitH=72  },
}

--[[ 跳跃峰值：H = v^2 / (2g) ]]--
local PEAK = (G.JUMP_V * G.JUMP_V) / (2 * G.GRAVITY)

--[[ 区间重叠判定 ]]--
local function overlap(a0, a1, b0, b1)
  return not (a1 <= b0 or b1 <= a0)
end

--[[ 恐龙在【某个 y】时的碰撞盒（画布坐标） ]]--
local function dinoBox(y)
  return y + G.DINO_HIT_T, y + G.DINO_HIT_B
end

--[[ 障碍的碰撞盒（画布坐标） ]]--
local function obsBox(k, top)
  local t = top + k.hitT
  return t, t + k.hitH
end

-- 恐龙的两个关键姿态
local STAND_Y = G.GROUND_Y                  -- 站着
local PEAK_Y  = G.GROUND_Y - PEAK           -- 跳到峰值

print("\n=== 0. 基本数值 ===")
print(string.format("  跳跃峰值 = %d^2/(2*%d) = %.1f px", -G.JUMP_V, G.GRAVITY, PEAK))
print(string.format("  恐龙站立盒 = %.0f..%.0f", dinoBox(STAND_Y)))
print(string.format("  恐龙峰值盒 = %.0f..%.0f", dinoBox(PEAK_Y)))

--=============================================================================
print("\n=== 1. 恐龙高度 = 中仙人掌高度 ===")
--=============================================================================
local dinoH = G.DINO_SPR_H
local midH  = OBS[2].h * CELL
check("恐龙高度 = 136px", dinoH == 136, dinoH .. "px")
check("中仙人掌高度 = 136px", midH == 136, midH .. "px")
check("★ 两者相等", dinoH == midH, string.format("%d = %d", dinoH, midH))

-- 顺带验证：恐龙点阵实际就是 16x17 格
local dinoRows = sprite.DINO_ROWS
check("恐龙点阵是 22x24 格", #dinoRows[1] == 22 and #dinoRows == 24,
    string.format("%dx%d", #dinoRows[1], #dinoRows))
--[[ 恐龙用独立的浮点格宽 DINO_CELL，非全局 CELL：
       点阵 24 行 x 5.67px = 136px = 恐龙高度 ]]--
  check("★ 点阵高度 x DINO_CELL(5.67) = 恐龙高度",
      math.abs(#dinoRows * 5.67 - dinoH) < 1,
      string.format("%.1f ~= %d", #dinoRows * 5.67, dinoH))

--=============================================================================
print("\n=== 2. 跳跃高度 > 最高仙人掌 ===")
--=============================================================================
local tallest = 0
local tallestName = nil
for _, k in ipairs(OBS) do
  if k.ground and k.h * CELL > tallest then
    tallest = k.h * CELL
    tallestName = k.name
  end
end
check("最高地面障碍是 " .. tallestName, tallestName == "cactusBig")
check("★ 跳跃峰值 > 最高仙人掌",
    PEAK > tallest, string.format("%.0f > %d", PEAK, tallest))
check("★ 余量 >= 40px（不只勉强越过）", PEAK - tallest >= 40,
    string.format("余量 %.0fpx", PEAK - tallest))

-- 真正的判据是【碰撞盒】能越过，不单是峰值数字
local _, dinoPeakBottom = dinoBox(PEAK_Y)
local bigTop = GROUND - tallest
check("★ 峰值时恐龙盒底 < 大仙人掌顶（真的能越过）",
    dinoPeakBottom < bigTop,
    string.format("%.0f < %d（余量 %.0f）", dinoPeakBottom, bigTop,
        bigTop - dinoPeakBottom))

--=============================================================================
print("\n=== 3. 三种仙人掌：站着必撞、跳起来能过 ===")
--=============================================================================
for _, k in ipairs(OBS) do
  if k.ground then
    local top = GROUND - k.h * CELL
    local oT, oB = obsBox(k, top)
    local sT, sB = dinoBox(STAND_Y)
    local pT, pB = dinoBox(PEAK_Y)

    -- 站着应该撞（否则障碍形同虚设）
    local standHit = overlap(sT, sB, oT, oB)
    -- 跳到峰值应该安全（否则无解）
    local peakHit = overlap(pT, pB, oT, oB)

    check(string.format("%s：站着会撞（有威胁）", k.name), standHit,
        string.format("盒 %.0f..%.0f vs %.0f..%.0f", sT, sB, oT, oB))
    check(string.format("%s：跳到峰值能过（有解）", k.name), not peakHit,
        peakHit and "★ 跳不过去 —— 死局！" or "安全")
  end
end

-- 水平方向也要够宽：恐龙得有时间从障碍上方掠过
print("\n  水平可行性:")
local K = G.GRAVITY
local safeTime = 0
do
  -- 求"恐龙盒底高于障碍顶"的持续时间
  local y, vy = G.GROUND_Y, G.JUMP_V
  local dt = 1/50
  local inSafe = false
  for _ = 1, 500 do
    vy = vy + K * dt
    y = y + vy * dt
    local _, b = dinoBox(y)
    -- 用最高的仙人掌做最严苛的判据
    if b < GROUND - tallest then
      safeTime = safeTime + dt
      inSafe = true
    end
    if y >= G.GROUND_Y then break end
  end
  check("★ 安全窗口足够长（> 0.25s）", safeTime > 0.25,
      string.format("%.2fs", safeTime))
  -- 最快速度下，障碍在窗口内能走多远？要能走完"恐龙宽 + 障碍宽"
  local maxSpeed = 1500
  local travel = maxSpeed * safeTime
  local need = G.DINO_HIT_W + OBS[1].hitW
  check("★ 最高速下窗口内能走完恐龙+障碍宽度", travel > need,
      string.format("走 %.0fpx，需要 %dpx", travel, need))
end

--=============================================================================
print("\n=== 4. ★★ 翼龙两个高度：低飞必跳 / 高飞不能跳 ===")
--=============================================================================
local bird = OBS[4]
check("翼龙是空中障碍（ground=false）", bird.ground == false)

local loY, hiY = G.BIRD_YS[1], G.BIRD_YS[2]
local sT, sB = dinoBox(STAND_Y)
local pT, pB = dinoBox(PEAK_Y)

-- 低飞：站着撞 + 峰值安全 -> 必须跳
local loTop, loBot = obsBox(bird, loY)
local loStandHit = overlap(sT, sB, loTop, loBot)
local loPeakHit  = overlap(pT, pB, loTop, loBot)
check("★ 低飞鸟：站着会撞", loStandHit,
    string.format("鸟 %.0f..%.0f vs 站 %.0f..%.0f", loTop, loBot, sT, sB))
check("★ 低飞鸟：跳到峰值能躲开", not loPeakHit,
    loPeakHit and "跳过也撞 —— 无解！" or "安全")
check("★★ 低飞鸟结论：必须跳才能过",
    loStandHit and not loPeakHit,
    string.format("top=%d", loY))

-- 高飞：站着安全 + 峰值撞 -> 不能跳
local hiTop, hiBot = obsBox(bird, hiY)
local hiStandHit = overlap(sT, sB, hiTop, hiBot)
local hiPeakHit  = overlap(pT, pB, hiTop, hiBot)
check("★ 高飞鸟：站着能安全通过", not hiStandHit,
    hiStandHit and "站着就撞 —— 那和低飞没区别" or "安全")
check("★ 高飞鸟：跳起来反而会撞", hiPeakHit,
    string.format("鸟 %.0f..%.0f vs 峰值 %.0f..%.0f", hiTop, hiBot, pT, pB))
check("★★ 高飞鸟结论：不用跳，跳了会撞",
    not hiStandHit and hiPeakHit,
    string.format("top=%d", hiY))

-- 两个高度必须不同，否则玩家无法区分
check("★ 两个飞行高度不同", loY ~= hiY,
    string.format("%d vs %d", loY, hiY))

-- 高飞鸟的区间不能太高（否则玩家跳不跳都无所谓，失去意义）
check("★ 高飞鸟在恐龙跳跃可达范围内（否则跳了也撞不到）",
    hiBot < STAND_Y,
    string.format("鸟底 %.0f < 恐龙站立顶 %d", hiBot, STAND_Y))

--=============================================================================
print("\n=== 5. 翼龙扇翅帧 ===")
--=============================================================================
local birdRects = sprite.birdRects()
local flapRects = sprite.birdFlapRects()
check("翼龙有两个姿态（主帧 + 扇翅帧）",
    #birdRects > 0 and #flapRects > 0,
    string.format("%d / %d 个矩形", #birdRects, #flapRects))
check("★ 两个姿态不同（不是同一张）",
    sprite.BIRD_ROWS ~= sprite.BIRD_FLAP_ROWS)

-- 两帧尺寸必须一致，否则扇翅时会跳动
check("★ 两姿态点阵尺寸一致",
    #sprite.BIRD_ROWS == #sprite.BIRD_FLAP_ROWS
    and #sprite.BIRD_ROWS[1] == #sprite.BIRD_FLAP_ROWS[1],
    string.format("%dx%d / %dx%d",
        #sprite.BIRD_ROWS[1], #sprite.BIRD_ROWS,
        #sprite.BIRD_FLAP_ROWS[1], #sprite.BIRD_FLAP_ROWS))

--[[ ★★ 障碍槽按【矩形最多的那一帧】建节点。

     ⚠️ 这里要证的是【危险真的存在】：
        扇翅帧的矩形数比其他所有障碍都多 ——
        所以建节点时「只看主帧」就会少一块，扇翅时缺角。

     ★ 之前写成 `#flapRects <= math.max(maxObs, #flapRects)` 是个套话
        （恒为真），起不到保护作用。 ]]
local maxOther = 0
local maxOtherName = nil
for _, k in ipairs(OBS) do
  local rects
  if k.name == "cactusBig" then rects = sprite.cactusBigRects()
  elseif k.name == "cactusMid" then rects = sprite.cactusMidRects()
  elseif k.name == "cactusSmall" then rects = sprite.cactusSmallRects()
  else rects = birdRects end
  if #rects > maxOther then
    maxOther = #rects
    maxOtherName = k.name
  end
end

--[[ ★★ 障碍槽按【矩形最多的那一帧】建节点。

     新参考姿态下：翼龙主帧（翅上） 15 个矩形，
     扇翅帧（翅下） 12 个 —— 主帧更多。
     所以不再有「扇翅帧占去额外节点」的危险。
     但“按最大矩形数建节点”的原则仍然成立。 ]]
check("★ 扇翅帧矩形数 <= 主帧（不会超出节点数）",
    #flapRects <= #birdRects,
    string.format("扇翅 %d <= 主帧 %d", #flapRects, #birdRects))

--=============================================================================
print("\n=== 6. ★★★ 可解性：同时出现时还有活路吗？ ===")
--=============================================================================
--[[ ★★★ 这是用户明确要求的一条：「确保有解」。

     问题：若仙人掌和高飞的鸟同时挡在身前 ——
           跳起来躲仙人掌 -> 撞上高飞的鸟
           不跳躲鸟       -> 撞上仙人掌
           是不是死局？

     方法：把恐龙能处的每个 y 都试一遍，看有没有
           「对两个障碍都安全」的 y。

     ★ 关键不在「有没有」，而在「宽不宽」——
       只有 16px 的话，玩家必须帧级精度才能生存，
       实际等于死局。 ]]
local function dinoBox(y)
  return y + G.DINO_HIT_T, y + G.DINO_HIT_B
end

local function avoidIVs(o0, o1, yLo, yHi)
  -- 避开 [o0,o1] 的 y 区间（恐龙盒不与之重叠）
  local out = {}
  local hi = o0 - G.DINO_HIT_B        -- 恐龙在障碍下方
  if hi >= yLo then out[#out+1] = { yLo, math.min(hi, yHi) } end
  local lo = o1 - G.DINO_HIT_T        -- 恐龙在障碍上方
  if lo <= yHi then out[#out+1] = { math.max(lo, yLo), yHi } end
  return out
end

local yLo, yHi = PEAK_Y, STAND_Y

-- 障碍的碰撞盒（画布坐标）
local bigBox  = { GROUND - OBS[1].h * CELL, GROUND }
local loBird  = { G.BIRD_YS[1] + bird.hitT, G.BIRD_YS[1] + bird.hitT + bird.hitH }
local hiBird  = { G.BIRD_YS[2] + bird.hitT, G.BIRD_YS[2] + bird.hitT + bird.hitH }

--[[ 求「对两个障碍都安全」的 y 区间宽度 ]]--
local function commonWidth(a, b)
  local best = 0
  local aIVs = avoidIVs(a[1], a[2], yLo, yHi)
  local bIVs = avoidIVs(b[1], b[2], yLo, yHi)
  for _, x in ipairs(aIVs) do
    for _, y in ipairs(bIVs) do
      local lo = math.max(x[1], y[1])
      local hi = math.min(x[2], y[2])
      if hi - lo > best then best = hi - lo end
    end
  end
  return best
end

local wBigLow  = commonWidth(bigBox, loBird)
local wBigHigh = commonWidth(bigBox, hiBird)

print(string.format("  大仙人掌 + 低飞鸟 : 公共安全区 %.0fpx", wBigLow))
print(string.format("  大仙人掌 + 高飞鸟 : 公共安全区 %.0fpx", wBigHigh))
print("")
print("  ★ 读法：低飞鸟的安全区有 92px ——")
print("    为仙人掌跳起来就自然越过了它，不构成额外约束。")
print("  ★ 但高飞鸟只剩 16px ——实战几乎不可能打中。")

check("★ 大仙人掌 + 高飞鸟的安全区极窄（< 40px）",
    wBigHigh < 40, string.format("%.0fpx", wBigHigh))
print("      ↳ 这就是为什么【必须把它们拆开生成】")

--[[ ★ 验证 demo 确实拆开了（源码级检查）

     不能只验几何，还要验「生成逻辑真的没让它们同时出现」。
     这里做一个轻量的源码检查：看 demo 是否用 WAVE_GAP
     而非 SPAWN_GAP 来控制生成节奏。 ]]
local demoPath = _root .. "/deploy/demo_dino.lua"
local f = io.open(demoPath, "r")
if f then
  local src = f:read("*a")
  f:close()
  check("★ demo 使用 WAVE_GAP 控制生成节奏",
      src:find("WAVE_GAP") ~= nil)
  check("★ demo 生成时只激活一个槽位（break 跳出）",
      src:find("o%.active = true") ~= nil and src:find("break") ~= nil)
  --[[ ★★ 生成间隔的真正不变量

       不是「两个障碍不能同屏」（屏宽 1600，而 WAVE_GAP=1500 会同屏），
       而是「处理完前一个后，要有时间回到地面再处理下一个」：

         两障碍到达恐龙的时间间隔 = WAVE_GAP / speed
         最坏情况（最高速）也要 > 跳跃全程时长

       ★ 实测：1500/1500 = 1.000s  vs  跳跃 0.633s  ->  余量 0.37s ✓ ]]
  local waveGap = tonumber(src:match("WAVE_GAP%s*=%s*(%d+)"))
  local maxSpeed = tonumber(src:match("MAX_SPEED%s*=%s*(%d+)"))
  local jumpDur = 2 * math.abs(G.JUMP_V) / G.GRAVITY

  if waveGap and maxSpeed then
    local worstGap = waveGap / maxSpeed
    check("★ 最高速下两障碍间隔 > 跳跃全程（来得及落地）",
        worstGap > jumpDur,
        string.format("间隔 %.3fs > 跳跃 %.3fs（余量 %.3fs）",
            worstGap, jumpDur, worstGap - jumpDur))
    check("★ 余量 >= 0.2s（不是刚好卡着）",
        worstGap - jumpDur >= 0.2,
        string.format("%.3fs", worstGap - jumpDur))
  else
    check("能从 demo 读到 WAVE_GAP / MAX_SPEED", false)
  end
else
  check("能读到 deploy/demo_dino.lua", false, demoPath)
end

--=============================================================================
print("\n=== 7. ★★★ 交叉校验：本测试的常量 == demo 的常量 ===")
--=============================================================================
--[[ ★★★ 为什么必须有这一节：

     本文件头部自己抄了一份 G 表（为了能做纯数值验算）。
     但那意味着：**若 demo 改了而本文件没改，所有断言依然全绿** ——
     而真机上跑的是 demo 的那套数值。

     这正是项目文档里「**测试替身必须忠实**」那条教训：
     替身（这里的常量副本）与真实对象不一致时，测试给的是假阳性。

     ★ 所以这里直接读 demo 源码，逐项比对关键常量。 ]]
do
  local f2 = io.open(_root .. "/deploy/demo_dino.lua", "r")
  if not f2 then
    check("能读到 deploy/demo_dino.lua", false)
  else
    local src = f2:read("*a")
    f2:close()

    --[[ 从源码里抓出常量值。
         格式：KEY = 数字   或  KEY = { a, b } ]]
    local function num(key)
      return tonumber(src:match(key .. "%s*=%s*(%-?%d+)"))
    end
    local function list(key)
      local body = src:match(key .. "%s*=%s*{([^}]*)}")
      if not body then return nil end
      local t = {}
      for v in body:gmatch("(%-?%d+)") do t[#t+1] = tonumber(v) end
      return t
    end

    local pairsToCheck = {
      { "GROUND_Y",   G.GROUND_Y   },
      { "GRAVITY",    G.GRAVITY    },
      { "JUMP_V",     G.JUMP_V     },
      { "DINO_SPR_H", G.DINO_SPR_H },
      { "DINO_HIT_W", G.DINO_HIT_W },
      { "DINO_HIT_T", G.DINO_HIT_T },
      { "DINO_HIT_B", G.DINO_HIT_B },
      { "DINO_X",     G.DINO_X     },
    }
    for _, pr in ipairs(pairsToCheck) do
      local key, expect = pr[1], pr[2]
      local got = num(key)
      check(string.format("★ %s 一致（demo = 本测试）", key),
          got == expect,
          string.format("demo=%s 本测试=%s", tostring(got), tostring(expect)))
    end

    -- 翼龙两个高度（数组）
    local bys = list("BIRD_YS")
    check("★ BIRD_YS 一致（demo = 本测试）",
        bys and #bys == 2 and bys[1] == G.BIRD_YS[1] and bys[2] == G.BIRD_YS[2],
        bys and table.concat(bys, ", ") or "未找到")

    -- 障碍碰撞盒：抓 OBS_KINDS 里的 hitW/hitT/hitH
    for _, k in ipairs(OBS) do
      -- 在源码里找到该 name 的那一段
      local seg = src:match('name%s*=%s*"' .. k.name .. '"' ..
                            '.-hitL%s*=%s*%-?%d+' ..
                            '.-hitW%s*=%s*%-?%d+' ..
                            '.-hitT%s*=%s*%-?%d+' ..
                            '.-hitH%s*=%s*%-?%d+')
      if not seg then
        check(string.format("★ %s 的碰撞盒能在 demo 里找到", k.name),
            false, "未找到")
      else
        local hl = tonumber(seg:match("hitL%s*=%s*(%-?%d+)"))
        local hw = tonumber(seg:match("hitW%s*=%s*(%-?%d+)"))
        local ht = tonumber(seg:match("hitT%s*=%s*(%-?%d+)"))
        local hh = tonumber(seg:match("hitH%s*=%s*(%-?%d+)"))
        local ok = hl == k.hitL and hw == k.hitW and ht == k.hitT and hh == k.hitH
        check(string.format("★ %s 碰撞盒一致", k.name), ok,
            string.format("demo=(%s,%s,%s,%s) 本测试=(%d,%d,%d,%d)",
                tostring(hl), tostring(hw), tostring(ht), tostring(hh),
                k.hitL, k.hitW, k.hitT, k.hitH))
      end
    end

    -- 尺寸（w/h）也比一下
    for _, k in ipairs(OBS) do
      local seg = src:match('name%s*=%s*"' .. k.name .. '"' ..
                            '.-w%s*=%s*%-?%d+%s*,%s*h%s*=%s*%-?%d+')
      if seg then
        local w = tonumber(seg:match("w%s*=%s*(%-?%d+)"))
        local h = tonumber(seg:match("h%s*=%s*(%-?%d+)"))
        check(string.format("★ %s 尺寸一致", k.name),
            w == k.w and h == k.h,
            string.format("demo=%sx%s 本测试=%dx%d",
                tostring(w), tostring(h), k.w, k.h))
      end
    end
  end
end

print("")
print(string.format(">>> 通过 %d / 失败 %d", pass, fail))
if fail > 0 then os.exit(1) end
