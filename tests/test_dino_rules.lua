--[[============================================================================
  test_dino_rules.lua  ——  小恐龙的【可解性】约束

     ★★ 为什么要单独测这个：

        用户提的几条要求（恐龙高度、跳跃高度、鸟的高度）本质上是
        【几何约束】—— 一旦有人调了其中任何一个数字，就可能出现
        「玩家无论如何都会死」的死局，而**游戏看起来完全正常**。

        这类 bug 不会报错、不会崩溃，只会让游戏变得无聊或不可通关。
        所以必须用断言把约束钉死。

     ★ 本测试只做【纯数值验算】，不跑引擎 —— 因为约束是几何的，
       与渲染无关，纯计算更快也更可靠。

     ⚠️ 这些常量必须与 deploy/demo_dino.lua 的 G 表【保持一致】。
        改动那边时，这里会失败 —— 这正是它的作用（第 7 节交叉校验）。

     ══════════════════════════════════════════════════════════════════════
     ★★★ R27 新增：三条与「难度」相关的约束
     ══════════════════════════════════════════════════════════════════════

       用户要求：① 鸟高度要在跳跃可达范围内（不能"跳起来撞不到"）
                 ② 仙人掌随机拼 1~4 株（不是写死）
                 ③ 开局只有单株仙人掌、无鸟，往后才加

       这三条都【可能引入死局】：

         ① 鸟若放在可达范围外 -> 玩家跳起来够不着，等于"别跳"的惩罚
         ② 4 株仙人掌可达 288px，而初始速度下最多只能跳 137px
            -> 随机拼株【必须按速度限宽】，否则第一波就必死
         ③ 阶段若推进太快/太慢 -> 难度曲线形同虚设

       所以下面各加了一节断言。
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
  MAX_SPEED  = 2000,
  BASE_SPEED = 620,
  ACCEL      = 48,
  WIDTH_SAFETY = 0.80,
  -- ★ 翼龙四档：前 2 档"必须跳"，后 2 档"不能跳"
  BIRD_YS    = { 596, 566, 440, 406 },
  BIRD_LOW_COUNT = 2,
}

-- 翼龙碰撞盒（与 OBS_KINDS.bird 一致）
local BIRD = { w=20, h=10, ground=false, hitL=20, hitW=120, hitT=8, hitH=72 }

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
-- ★ 恐龙 top 的可达区间（这就是"跳跃可达范围"）
local REACH_LO, REACH_HI = PEAK_Y, STAND_Y

--[[ ★★★ 当前速度下能越过的障碍最大宽度。

     与 demo 的 maxClearWidth 同一套公式（交叉校验见第 7 节）。 ]]--
local function maxClearWidth(obsH, speed)
  local needTop = GROUND - obsH - G.DINO_HIT_B
  local need = G.GROUND_Y - needTop
  if need <= 0 then return math.huge end
  local a, b, c = 0.5*G.GRAVITY, G.JUMP_V, need
  local disc = b*b - 4*a*c
  if disc < 0 then return 0 end
  local t1 = (-b - math.sqrt(disc)) / (2*a)
  local t2 = (-b + math.sqrt(disc)) / (2*a)
  local w = speed * (t2 - t1) - G.DINO_HIT_W
  if w < 0 then w = 0 end
  return w * G.WIDTH_SAFETY
end

print("\n=== 0. 基本数值 ===")
print(string.format("  跳跃峰值 = %d^2/(2*%d) = %.1f px", -G.JUMP_V, G.GRAVITY, PEAK))
print(string.format("  恐龙站立盒 = %.0f..%.0f", dinoBox(STAND_Y)))
print(string.format("  恐龙峰值盒 = %.0f..%.0f", dinoBox(PEAK_Y)))
print(string.format("  ★ 恐龙 top 可达区间 = [%.0f, %.0f]", REACH_LO, REACH_HI))

--=============================================================================
print("\n=== 1. 恐龙高度 = 中仙人掌高度 ===")
--=============================================================================
local dinoH = G.DINO_SPR_H
local midH  = sprite.CACTUS_KINDS[2].h * CELL      -- 中仙人掌 17 格
check("恐龙高度 = 136px", dinoH == 136, dinoH .. "px")
check("中仙人掌高度 = 136px", midH == 136, midH .. "px")
check("★ 两者相等", dinoH == midH, string.format("%d = %d", dinoH, midH))

-- 顺带验证：恐龙点阵实际就是 22x24 格
local dinoRows = sprite.DINO_ROWS
check("恐龙点阵是 22x24 格", #dinoRows[1] == 22 and #dinoRows == 24,
    string.format("%dx%d", #dinoRows[1], #dinoRows))
check("★ 点阵高度 x DINO_CELL(5.67) = 恐龙高度",
    math.abs(#dinoRows * 5.67 - dinoH) < 1,
    string.format("%.1f ~= %d", #dinoRows * 5.67, dinoH))

--=============================================================================
print("\n=== 2. 跳跃高度 > 最高的仙人掌（含 4 株组合）===")
--=============================================================================
-- 最高的仙人掌 = 大仙人掌 18 格 = 144px
local tallest = sprite.CACTUS_KINDS[1].h * CELL
check("最高的仙人掌 = 144px（大仙人掌）", tallest == 144, tallest .. "px")
check("★ 跳跃峰值 > 最高仙人掌", PEAK > tallest,
    string.format("%.0f > %d", PEAK, tallest))
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
print("\n=== 3. ★★ 单株仙人掌（三种）：站着必撞、跳起来能过 ===")
--=============================================================================
for _, k in ipairs(sprite.CACTUS_KINDS) do
  local hPx = k.h * CELL
  local top = GROUND - hPx
  local single = { hitT = 0, hitH = hPx, hitW = k.w * CELL }
  local oT, oB = obsBox(single, top)
  local sT, sB = dinoBox(STAND_Y)
  local pT, pB = dinoBox(PEAK_Y)

  check(string.format("%s仙人掌(%dpx)：站着会撞（有威胁）", k.name, hPx),
      overlap(sT, sB, oT, oB),
      string.format("盒 %.0f..%.0f vs %.0f..%.0f", sT, sB, oT, oB))
  check(string.format("%s仙人掌(%dpx)：跳到峰值能过（有解）", k.name, hPx),
      not overlap(pT, pB, oT, oB),
      overlap(pT, pB, oT, oB) and "★ 跳不过去 —— 死局！" or "安全")
end

--=============================================================================
print("\n=== 4. ★★★ 随机拼株：任意 1~4 株组合都必须可解 ===")
--=============================================================================
--[[ 这是 R27 最重要的一节。

     用户要求"随机组合 1~4 个仙人掌"。但株数一多，组就变宽 ——
     而恐龙滞空时间有限，太宽的障碍【无论怎么跳都会撞】。

     实测：4 株大仙人掌 = 36 格 = 288px
           而初始速度 620 下最多只能跳 137px
           -> 不做限宽的话，第一波就可能必死。

     ★ 所以这里穷举【所有 1~4 株组合】，对每个速度验证：
         demo 的 makeCactus（限宽后）实际产出的组，
         都能在【该速度】下跳过去。
]]--
local allKeys = {}
do
  local function rec(pref, n)
    if #pref == n then
      allKeys[#allKeys+1] = { table.unpack(pref) }
      return
    end
    for k = 1, 3 do
      local p = { table.unpack(pref) }
      p[#p+1] = k
      rec(p, n)
    end
  end
  for n = 1, 4 do rec({}, n) end
end
check("穷举出所有 1~4 株组合（3+9+27+81=120）", #allKeys == 120, #allKeys .. " 个")

-- ① 先证明【真正的危险存在】：不限宽时确实有超预算的组合
local worstUnlimited, worstKeys = 0, nil
for _, keys in ipairs(allKeys) do
  local g = sprite.cactusGroup(keys)
  local wpx = g.w * CELL
  if wpx > worstUnlimited then
    worstUnlimited = wpx
    worstKeys = keys
  end
end
local budgetAtBase = maxClearWidth(tallest, G.BASE_SPEED)
check("★ 不限宽时存在超预算的组合（危险是真的）",
    worstUnlimited > budgetAtBase,
    string.format("最宽 %dpx > 初始预算 %.0fpx", worstUnlimited, budgetAtBase))

-- ② 复刻 demo 的 makeCactus（限宽），对每个速度穷举验证
local seed = 20261008
local function rnd()
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed / 2147483648
end

local function makeCactusLike(maxStalks, speed)
  local budget = maxClearWidth(tallest, speed)
  local n = maxStalks
  local grp
  while n >= 1 do
    grp = sprite.randomCactusGroup(n, rnd)
    if grp.w * CELL <= budget then break end
    n = n - 1
  end
  return grp, n, budget
end

local violated, tested = 0, 0
for speed = G.BASE_SPEED, G.MAX_SPEED, 10 do
  for _ = 1, 60 do
    local grp, n, budget = makeCactusLike(4, speed)
    tested = tested + 1
    local hPx = grp.h * CELL
    -- 用【该组自己的高度】算可跳上限
    local limit = maxClearWidth(hPx, speed)
    if grp.w * CELL > limit + 0.01 then violated = violated + 1 end
  end
end
check(string.format("★ 限宽后 %d 次随机组全部可跳过", tested), violated == 0,
    violated == 0 and "0 次超预算"
        or string.format("★ %d 次超预算 —— 会出现死局！", violated))

-- ③ 初始速度下【必须】只出单株（否则开局就可能太难）
local wideAtStart = 0
for _ = 1, 200 do
  local grp = makeCactusLike(4, G.BASE_SPEED)
  if grp.w > 2 * CELL + 0.01 and grp.w * CELL > maxClearWidth(tallest, G.BASE_SPEED) then
    wideAtStart = wideAtStart + 1
  end
end
check("★ 初始速度下不会出现超预算的宽组", wideAtStart == 0,
    wideAtStart .. " 次")

-- ④ 株数应随速度增加（这就是"难度递增"的几何体现）
local nSlow = select(2, makeCactusLike(4, G.BASE_SPEED))
local nFast = select(2, makeCactusLike(4, G.MAX_SPEED))
check("★ 株数随速度增加（慢->少、快->多）", nFast >= nSlow,
    string.format("初始 %d 株 -> 最高速 %d 株", nSlow, nFast))

--=============================================================================
print("\n=== 5. ★★★ 翼龙四档：全部在跳跃可达范围内 + 语义正确 ===")
--=============================================================================
--[[ ★★ 用户反馈：「最上面的鸟高度不对，太高了跳起来撞不到」。

     所以这里的判据有【三条】，缺一不可：

       ① 语义正确：要么"必须跳"（站撞/峰过），要么"不能跳"（站过/峰撞）
          —— 绝不能"站着跳着都过"（障碍形同虚设）
             也绝不能"站着跳着都撞"（死局）
       ② 都在【跳跃可达范围内】—— 玩家跳到任何高度都能与它发生关系
       ③ 安全区够宽（>= 60px）—— 不是"帧级精度才活得下来"的伪死局
]]--
check("翼龙是空中障碍（ground=false）", BIRD.ground == false)
check("翼龙碰撞盒高 72px", BIRD.hitH == 72, BIRD.hitH .. "px")

local sT, sB = dinoBox(STAND_Y)
local pT, pB = dinoBox(PEAK_Y)
local N_LOW = G.BIRD_LOW_COUNT

for i, y in ipairs(G.BIRD_YS) do
  local t, b = obsBox(BIRD, y)
  local hitStand = overlap(sT, sB, t, b)
  local hitPeak  = overlap(pT, pB, t, b)
  local shouldJump = (i <= N_LOW)          -- 前两档 = 必须跳

  -- ① 语义
  if shouldJump then
    check(string.format("翼龙[%d] top=%d：站着撞 / 峰值过（必须跳）", i, y),
        hitStand and not hitPeak,
        string.format("盒 %d..%d  站:%s 峰:%s", t, b,
            hitStand and "撞" or "·", hitPeak and "撞" or "·"))
  else
    check(string.format("翼龙[%d] top=%d：站着过 / 峰值撞（不能跳）", i, y),
        (not hitStand) and hitPeak,
        string.format("盒 %d..%d  站:%s 峰:%s", t, b,
            hitStand and "撞" or "·", hitPeak and "撞" or "·"))
  end

  -- ② 都在可达范围内：★ 判据要用【恐龙可达的碰撞盒区间】，
  --    不是"恐龙 top 的区间" —— 这两者差一个盒子的高度。
  --
  --    恐龙 top 可达 [354, 564]，对应盒区间 = [354+56, 564+112] = [410, 676]。
  --    ⚠️ 下面这个 check 我第一版写错了（拿鸟盒去比 top 区间），
  --       于是低飞鸟（盒 604..676）被判成"够不着" —— 其实它比的是
  --       恐龙的"头顶位置"而不是"身体"。已改为比盒区间。
  local reachBoxT = REACH_LO + G.DINO_HIT_T
  local reachBoxB = REACH_HI + G.DINO_HIT_B
  local reachable = (b > reachBoxT) and (t < reachBoxB)
  check(string.format("★ 翼龙[%d] 与恐龙可达盒区间相交（跳起来够得着）", i),
      reachable,
      string.format("盒 %d..%d vs 可达盒 [%.0f,%.0f]", t, b, reachBoxT, reachBoxB))

  -- ③ 安全区够宽
  local safeBelow = t - G.DINO_HIT_B      -- 恐龙 top <= 此值 => 在鸟下方（跳过去）
  local safeAbove = b - G.DINO_HIT_T      -- 恐龙 top >= 此值 => 在鸟上方（站地上）
  local wBelow = math.max(0, math.min(safeBelow, REACH_HI) - REACH_LO)
  local wAbove = math.max(0, REACH_HI - math.max(safeAbove, REACH_LO))
  local wSafe = math.max(wBelow, wAbove)
  check(string.format("★ 翼龙[%d] 安全区 >= 60px（不是伪死局）", i),
      wSafe >= 60, string.format("%.0fpx", wSafe))
end

-- 四档高度必须【互不相同】，否则玩家无法区分
local uniq = {}
for _, y in ipairs(G.BIRD_YS) do uniq[y] = true end
local nu = 0
for _ in pairs(uniq) do nu = nu + 1 end
check("★ 四个飞行高度互不相同", nu == #G.BIRD_YS,
    string.format("%d 个不同值", nu))

-- ★ 关键回归：旧版 405 那档"太高"—— 现在最高档必须仍然够得着
local highest = G.BIRD_YS[#G.BIRD_YS]
local ht, hb = obsBox(BIRD, highest)
local rbt = REACH_LO + G.DINO_HIT_T
local rbb = REACH_HI + G.DINO_HIT_B
check("★★ 最高档翼龙仍在可达范围内（旧版 405 的问题）",
    hb > rbt and ht < rbb,
    string.format("最高档盒 %d..%d vs 可达盒 [%.0f,%.0f]", ht, hb, rbt, rbb))

--=============================================================================
print("\n=== 6. 翼龙三帧扇翅 ===")
--=============================================================================
local frames = sprite.birdFrames()
check("翼龙有 3 个姿态（抬 / 半收 / 放）", #frames == 3, #frames .. " 帧")
check("每帧都有矩形", frames[1] and #frames[1] > 0
    and frames[2] and #frames[2] > 0 and frames[3] and #frames[3] > 0,
    string.format("%d / %d / %d 个矩形",
        #frames[1], #frames[2], #frames[3]))

-- 三帧点阵尺寸必须一致，否则扇翅时会横向跳动
local r1, r2, r3 = sprite.BIRD_ROWS, sprite.BIRD_MID_ROWS, sprite.BIRD_FLAP_ROWS
check("★ 三帧点阵尺寸一致", #r1 == #r2 and #r2 == #r3
    and #r1[1] == #r2[1] and #r2[1] == #r3[1],
    string.format("%dx%d / %dx%d / %dx%d",
        #r1[1], #r1, #r2[1], #r2, #r3[1], #r3))

-- 三帧必须互不相同（否则"动画"是假的）
check("★ 三帧内容互不相同",
    table.concat(r1) ~= table.concat(r2)
    and table.concat(r2) ~= table.concat(r3)
    and table.concat(r1) ~= table.concat(r3))

-- 帧表是缓存的：重复调用返回同一张表
check("birdFrames 有缓存（重复调用同一张表）",
    sprite.birdFrames()[1] == sprite.birdFrames()[1])

--=============================================================================
print("\n=== 7. ★★★ 难度曲线：开局只有单株仙人掌、无鸟 ===")
--=============================================================================
--[[ 用户要求：「游戏刚开始应该只有单个仙人掌，没有鸟，
                 往后难度变大再增加鸟和仙人掌的数量和密度」

     这必须【源码级】校验 —— 几何验算证明不了"生成逻辑真的分阶段"。

     判据：
       ① STAGE_RULES[1].maxStalks == 1     （开局只出单株）
       ② STAGE_RULES[1].birdChance == 0    （开局绝不出鸟）
       ③ 株数上限【单调不减】              （难度只升不降）
       ④ 波间隔【单调不增】                （密度只增不减）
       ⑤ 鸟档数【单调不减】                （鸟的种类只多不少）
]]--
local f2 = io.open(_root .. "/deploy/demo_dino.lua", "r")
if not f2 then
  check("能读到 deploy/demo_dino.lua", false)
else
  local src = f2:read("*a")
  f2:close()

  -- 解析 STAGE_RULES
  local block = src:match("STAGE_RULES%s*=%s*{(.-)\n  }")
  check("能从 demo 读到 STAGE_RULES", block ~= nil)

  if block then
    local rules = {}
    for line in block:gmatch("[^\n]+") do
      local ms = tonumber(line:match("maxStalks%s*=%s*(%d+)"))
      if ms then
        rules[#rules+1] = {
          maxStalks  = ms,
          birdChance = tonumber(line:match("birdChance%s*=%s*([%d%.]+)")),
          waveGap    = tonumber(line:match("waveGap%s*=%s*(%d+)")),
          birdTiers  = tonumber(line:match("birdTiers%s*=%s*(%d+)")),
        }
      end
    end
    check("解析出 4 个阶段", #rules == 4, #rules .. " 个")

    if #rules == 4 then
      check("★★ 阶段1 只出【单株】仙人掌（maxStalks=1）",
          rules[1].maxStalks == 1, "maxStalks=" .. tostring(rules[1].maxStalks))
      check("★★ 阶段1 出鸟概率 = 0（开局没有鸟）",
          rules[1].birdChance == 0, "birdChance=" .. tostring(rules[1].birdChance))
      check("★★ 阶段1 鸟档数 = 0（根本不会生成鸟）",
          rules[1].birdTiers == 0, "birdTiers=" .. tostring(rules[1].birdTiers))
      check("★ 最后阶段可达 4 株（难度上限）",
          rules[#rules].maxStalks == 4, "maxStalks=" .. tostring(rules[#rules].maxStalks))

      -- 单调性
      local monoStalks, monoGap, monoTiers, monoBird = true, true, true, true
      for i = 2, #rules do
        if rules[i].maxStalks < rules[i-1].maxStalks then monoStalks = false end
        if rules[i].waveGap > rules[i-1].waveGap then monoGap = false end
        if rules[i].birdTiers < rules[i-1].birdTiers then monoTiers = false end
        if rules[i].birdChance < rules[i-1].birdChance then monoBird = false end
      end
      check("★ 株数上限单调不减（难度只升不降）", monoStalks)
      check("★ 波间隔单调不增（密度只增不减）", monoGap)
      check("★ 鸟档数单调不减（鸟的种类只多不少）", monoTiers)
      check("★ 出鸟概率单调不减", monoBird)

      -- 阶段分界必须是递增的
      local distBody = src:match("STAGE_DIST%s*=%s*{([^}]*)}")
      local ds = {}
      if distBody then
        for v in distBody:gmatch("(%d+)") do ds[#ds+1] = tonumber(v) end
      end
      check("能从 demo 读到 STAGE_DIST", #ds == 3, #ds .. " 个分界")
      local monoDist = true
      for i = 2, #ds do if ds[i] <= ds[i-1] then monoDist = false end end
      check("★ 阶段分界递增", #ds == 3 and monoDist,
          table.concat(ds, " < "))

      --[[ ★★★ 阶段1 必须【真的生效】—— 这是踩过的坑。

            ⚠️ 第一版写 STAGE_DIST[1] = 900，而第一波是在
               dist ~1100 才生成的（= 阶段1 的 waveGap）。
               900 < 1100  =>  第一波生成时【已经是阶段2】，
               => 阶段1 从未生效：开局第一波就是 2 株仙人掌、
                  第 2 波就出鸟，与需求完全相反。

           ★ 判据：STAGE_DIST[1] 必须 > 阶段1 的 waveGap
             （否则连第一波都盖不住），且最好能覆盖【前几波】。 ]]
      local gap1 = rules[1].waveGap
      check("★★ 阶段1 的分界 > 第一波出场距离（否则阶段1 形同虚设）",
          ds[1] > gap1,
          string.format("STAGE_DIST[1]=%d > waveGap=%d", ds[1], gap1))

      -- 能覆盖至少 3 波才算"开局学习期"
      local wavesInS1 = math.floor(ds[1] / gap1)
      check("★★ 阶段1 至少覆盖 3 波（真正的开局学习期）",
          wavesInS1 >= 3,
          string.format("约 %d 波", wavesInS1))

      --[[ ★★ 阶段2（无鸟 -> 有鸟 的过渡期）必须够长，
           否则玩家可能【一只鸟都没见到】就进入阶段3
           （那时会出现"不能跳"的鸟，规则正好相反）。

           判据：阶段2 内的波数 × birdChance，要能大概率见到鸟。
             期望波数 >= 10（0.75^10 = 5.6% 见不到）。 ]]
      local wavesInS2 = math.floor((ds[2] - ds[1]) / rules[2].waveGap)
      check("★★ 阶段2 有足够波数来引入鸟（>= 10 波）",
          wavesInS2 >= 10,
          string.format("约 %d 波（0.75^%d = %.1f%% 见不到鸟）",
              wavesInS2, wavesInS2,
              100 * (1 - rules[2].birdChance) ^ wavesInS2))
    end
  end

  -- ★ 交叉校验：maxClearWidth 的公式必须真的存在于 demo 里
  check("★ demo 里有 maxClearWidth（组宽预算）",
      src:find("maxClearWidth") ~= nil)
  check("★ demo 里有 widthBudget 用的 WIDTH_SAFETY",
      src:find("WIDTH_SAFETY") ~= nil)
  check("★★ demo 生成仙人掌时按【当前速度】限宽",
      src:find("makeCactus(rule.maxStalks, S.speed)", 1, true) ~= nil)
  check("★ demo 用 birdFrames() 取三帧（不是自己抄帧表）",
      src:find("sprite.birdFrames()") ~= nil)
end

--=============================================================================
print("\n=== 8. ★★★ 交叉校验：本测试的常量 == demo 的常量 ===")
--=============================================================================
--[[ ★★★ 为什么必须有这一节：

      本文件头部自己抄了一份 G 表（为了能做纯数值验算）。
      但那意味着：**若 demo 改了而本文件没改，所有断言依然全绿** ——
      而真机上跑的是 demo 的那套数值。

      ★ 所以这里直接读 demo 源码，逐项比对关键常量。 ]]
do
  local f3 = io.open(_root .. "/deploy/demo_dino.lua", "r")
  if not f3 then
    check("能读到 deploy/demo_dino.lua", false)
  else
    local src = f3:read("*a")
    f3:close()

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
      { "GROUND_Y",       G.GROUND_Y   },
      { "GRAVITY",        G.GRAVITY    },
      { "JUMP_V",         G.JUMP_V     },
      { "DINO_SPR_H",     G.DINO_SPR_H },
      { "DINO_HIT_W",     G.DINO_HIT_W },
      { "DINO_HIT_T",     G.DINO_HIT_T },
      { "DINO_HIT_B",     G.DINO_HIT_B },
      { "DINO_X",         G.DINO_X     },
      { "BASE_SPEED",     G.BASE_SPEED },
      { "MAX_SPEED",      G.MAX_SPEED  },
      { "BIRD_LOW_COUNT", G.BIRD_LOW_COUNT },
    }
    for _, pr in ipairs(pairsToCheck) do
      local key, expect = pr[1], pr[2]
      local got = num(key)
      check(string.format("★ %s 一致（demo = 本测试）", key),
          got == expect,
          string.format("demo=%s 本测试=%s", tostring(got), tostring(expect)))
    end

    -- 翼龙四档高度
    local bys = list("BIRD_YS")
    local same = bys and (#bys == #G.BIRD_YS)
    if same then
      for i = 1, #bys do
        if bys[i] ~= G.BIRD_YS[i] then same = false end
      end
    end
    check("★ BIRD_YS 一致（四档，demo = 本测试）", same,
        bys and table.concat(bys, ", ") or "未找到")

    -- 翼龙碰撞盒
    local seg = src:match('name%s*=%s*"bird"' ..
                          '.-hitL%s*=%s*%-?%d+' ..
                          '.-hitW%s*=%s*%-?%d+' ..
                          '.-hitT%s*=%s*%-?%d+' ..
                          '.-hitH%s*=%s*%-?%d+')
    if not seg then
      check("★ 翼龙碰撞盒能在 demo 里找到", false, "未找到")
    else
      local hl = tonumber(seg:match("hitL%s*=%s*(%-?%d+)"))
      local hw = tonumber(seg:match("hitW%s*=%s*(%-?%d+)"))
      local ht = tonumber(seg:match("hitT%s*=%s*(%-?%d+)"))
      local hh = tonumber(seg:match("hitH%s*=%s*(%-?%d+)"))
      check("★ 翼龙碰撞盒一致",
          hl == BIRD.hitL and hw == BIRD.hitW
          and ht == BIRD.hitT and hh == BIRD.hitH,
          string.format("demo=(%s,%s,%s,%s) 本测试=(%d,%d,%d,%d)",
              tostring(hl), tostring(hw), tostring(ht), tostring(hh),
              BIRD.hitL, BIRD.hitW, BIRD.hitT, BIRD.hitH))
    end
    -- 翼龙尺寸
    local bw = tonumber(src:match('name%s*=%s*"bird".-w%s*=%s*(%d+)'))
    local bh = tonumber(src:match('name%s*=%s*"bird".-h%s*=%s*(%d+)'))
    check("★ 翼龙尺寸一致 20x10",
        bw == BIRD.w and bh == BIRD.h,
        string.format("demo=%sx%s 本测试=%dx%d",
            tostring(bw), tostring(bh), BIRD.w, BIRD.h))

    -- ★ WIDTH_SAFETY 必须与 demo 一致（它直接决定"限宽"松紧）
    local ws = tonumber(src:match("WIDTH_SAFETY%s*=%s*([%d%.]+)"))
    check("★ WIDTH_SAFETY 一致", ws == G.WIDTH_SAFETY,
        string.format("demo=%s 本测试=%s", tostring(ws), tostring(G.WIDTH_SAFETY)))

    --[[ ★★★ 生成间隔的时间约束：两障碍间隔 > 跳跃全程（来得及落地再跳）

       ⚠️⚠️ 必须检查【所有阶段】的 waveGap，不能只取第一个！

          提速到 MAX_SPEED=2000 时暴露过这个测试自身的漏洞：
          它用 `src:match("waveGap%s*=%s*(%d+)")` 只读到【阶段1】的值
          （1100/2000 = 0.550s > 0.525s，看起来 OK），
          而阶段2~4 是 1000/950/900 -> 0.500/0.475/0.450s，
          【全部低于跳跃全程】= 玩家落地前下一个障碍就到了 = 必死波。

          => 判据必须对【每一档】都成立（取最严的那档）。 ]]
do
  local gaps = {}
  for v in src:gmatch("waveGap%s*=%s*(%d+)") do
    gaps[#gaps + 1] = tonumber(v)
  end
  -- 跳过测试用副本里的替换值（999999 之类）
  local real = {}
  for _, v in ipairs(gaps) do
    if v and v > 0 and v < 100000 then real[#real + 1] = v end
  end

  local maxSpeed = tonumber(src:match("MAX_SPEED%s*=%s*(%d+)"))
  local jumpDur = 2 * math.abs(G.JUMP_V) / G.GRAVITY

  check("★ 能读到各阶段的 waveGap", #real >= 4,
      string.format("读到 %d 档", #real))

  if maxSpeed and #real > 0 then
    local worst, worstGap = nil, nil
    for _, wg in ipairs(real) do
      local t = wg / maxSpeed
      if not worst or t < worst then worst, worstGap = t, wg end
    end
    check("★★★ 【每一档】最高速下间隔都 > 跳跃全程（来得及落地）",
        worst > jumpDur,
        string.format("最严档 waveGap=%d -> %.3fs > 跳跃 %.3fs（%+.3fs）",
            worstGap, worst, jumpDur, worst - jumpDur))
  else
    check("能从 demo 读到 waveGap / MAX_SPEED", false)
  end
end

--[[ ★★ 封顶距离必须与【阶段标定】相称。

     ⚠️ MAX_SPEED 提高时容易忽略：
        封顶 dist = BASE*t + 0.5*ACCEL*t^2，t = (MAX-BASE)/ACCEL。
        若加速度不跟着上调，封顶会被推到很远（甚至跑完所有阶段之后），
        表现为「阶段4 已到、速度却还没上来」= 难度曲线形同虚设。 ]]
do
  local base  = tonumber(src:match("BASE_SPEED%s*=%s*(%d+)"))
  local maxSp = tonumber(src:match("MAX_SPEED%s*=%s*(%d+)"))
  local accel = tonumber(src:match("ACCEL%s*=%s*(%d+)"))
  local stages = {}
  for v in src:gmatch("STAGE_DIST%s*=%s*{([^}]*)}") do
    for n in v:gmatch("(%d+)") do stages[#stages + 1] = tonumber(n) end
    break
  end
  check("能读到 BASE_SPEED / MAX_SPEED / ACCEL",
      base and maxSp and accel, string.format("%s/%s/%s",
          tostring(base), tostring(maxSp), tostring(accel)))

  if base and maxSp and accel and #stages >= 3 then
    local t = (maxSp - base) / accel
    local capDist = base * t + 0.5 * accel * t * t
    local lastStage = stages[#stages]
    check("★★ 封顶距离在【最后一个阶段之前】（否则阶段4 形同虚设）",
        capDist < lastStage,
        string.format("封顶 dist=%.0f < 阶段4 起点 %d（用时 %.1fs）",
            capDist, lastStage, t))
  end
end
  end
end

print("")
print(string.format(">>> 通过 %d / 失败 %d", pass, fail))
if fail > 0 then os.exit(1) end
