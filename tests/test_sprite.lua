--[[============================================================================
  test_sprite.lua  ——  像素图形拼接（webui_sprite）

     ★ 核心风险：矩形分解算错，图形就画错。
       而"算错"很容易【看起来正常】（比如分解出 1 个覆盖全图的大矩形，
       屏幕上就是个实心方块，不报错）。

     ★ 所以本测试的重点是【覆盖正确性】：
       把矩形重建回点阵，与原串逐格比对 —— 必须 0 处不一致。

     ★ 并覆盖一个真实的 Lua 坑（本模块踩过）：
       Lua 里【0 是真值】，所以 `v and 1 or 0` 会把 0 变成 1，
       导致整个点阵变实心。
]]

-- 仓库根 = 本脚本所在目录的上一级（tests/ -> root/）
local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
            .. _root .. "/tools/?.lua;" .. package.path

local S = require('webui_sprite')

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass=pass+1; print(string.format("  [OK] %-48s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-48s %s", name, detail or "")) end
end

--=============================================================================
print("\n=== 1. ★ Lua 真值坑：0 必须被当成空 ===")
--=============================================================================
--[[ Lua 里 `0 and 1 or 0` 得到 1（0 是真值）。
     若分解器内部这样转换，整个点阵会变实心。
     这里用最小用例把这条钉住。 ]]
local r = S.decompose({ {1, 0, 1} })
check("点阵 {1,0,1} 分解成 2 个矩形（不是 1 个）", #r == 2,
    #r .. " 个")
if #r == 2 then
  check("  左段 = {x=1,w=1}", r[1].x == 1 and r[1].w == 1,
      string.format("{x=%d,w=%d}", r[1].x, r[1].w))
  check("  右段 = {x=3,w=1}", r[2].x == 3 and r[2].w == 1,
      string.format("{x=%d,w=%d}", r[2].x, r[2].w))
end

local r2 = S.decompose(S.gridFromRows({"#.", ".."}))
check("2x2 只填左上 -> 1 个矩形", #r2 == 1, #r2 .. " 个")
if #r2 == 1 then
  check("  矩形 = {1,1,1,1}（不是覆盖全图的 2x2）",
      r2[1].x == 1 and r2[1].y == 1 and r2[1].w == 1 and r2[1].h == 1,
      string.format("{%d,%d,%d,%d}", r2[1].x, r2[1].y, r2[1].w, r2[1].h))
end

--=============================================================================
print("\n=== 2. gridFromRows：字符解析 ===")
--=============================================================================
local g = S.gridFromRows({ "#.", ".x" })
check("'#' 解析为 1", g[1][1] == 1)
check("'.' 解析为 0", g[1][2] == 0)
check("'x' 也解析为填充", g[2][2] == 1)
check("第二行第一格为空", g[2][1] == 0)
check("行/列数正确", #g == 2 and #g[1] == 2)

--=============================================================================
print("\n=== 3. 简单形状的分解数 ===")
--=============================================================================
local function count(rows)
  return #S.decompose(S.gridFromRows(rows))
end
check("2x2 全满 -> 1 个矩形", count({"##","##"}) == 1, tostring(count({"##","##"})))
check("L 形 -> 2 个矩形", count({"#.","##"}) == 2, tostring(count({"#.","##"})))
check("横条 -> 1 个", count({"####"}) == 1)
check("竖条 -> 1 个", count({"#","#","#"}) == 1)
check("棋盘 2x2 -> 2 个", count({"#.",".#"}) == 2,
    tostring(count({"#.",".#"})))
check("全空 -> 0 个", count({"..",".."}) == 0)
check("空表 -> 0 个", #S.decompose({}) == 0)

--=============================================================================
print("\n=== 4. ★★ 覆盖正确性：矩形能【完好重建】原点阵 ===")
--=============================================================================
--[[ 这是最关键的一组断言：
       把矩形涂回一张空网格，逐格与原串比对。
       任何"漏格"或"多格"都会被抓出来。 ]]
local function coverOK(name, rows)
  local rects = S.decompose(S.gridFromRows(rows))
  local grid = S.gridFromRows(rows)
  local H, W = #grid, #grid[1]

  local cell = {}
  for y = 1, H do
    cell[y] = {}
    for x = 1, W do cell[y][x] = 0 end
  end
  for _, rc in ipairs(rects) do
    for y = rc.y, rc.y + rc.h - 1 do
      for x = rc.x, rc.x + rc.w - 1 do
        if y >= 1 and y <= H and x >= 1 and x <= W then cell[y][x] = 1 end
      end
    end
  end

  local bad = 0
  for y = 1, H do
    for x = 1, W do
      if (grid[y][x] == 1) ~= (cell[y][x] == 1) then bad = bad + 1 end
    end
  end
  return bad, #rects
end

local cases = {
  { "恐龙站立", S.DINO_ROWS },
  { "恐龙跑动", S.DINO_RUN_ROWS },
  { "恐龙死亡", S.DINO_DEAD_ROWS },
  { "仙人掌",   S.CACTUS_ROWS },
  { "云",       S.CLOUD_ROWS },
}
for _, c in ipairs(cases) do
  local bad, n = coverOK(c[1], c[2])
  check(c[1] .. "：矩形完好重建点阵（0 处不一致）", bad == 0,
      string.format("%d 个矩形，不一致 %d 格", n, bad))
end

--=============================================================================
print("\n=== 5. 矩形不越界（越界会画到容器外）===")
--=============================================================================
for _, c in ipairs(cases) do
  local rows = c[2]
  local grid = S.gridFromRows(rows)
  local H, W = #grid, #grid[1]
  local rects = S.decompose(grid)
  local oob = 0
  for _, rc in ipairs(rects) do
    if rc.x < 1 or rc.y < 1 or rc.x + rc.w - 1 > W or rc.y + rc.h - 1 > H then
      oob = oob + 1
    end
  end
  check(c[1] .. "：无越界矩形", oob == 0, oob .. " 个越界")
end

--=============================================================================
print("\n=== 6. 缓存：重复取矩形不应重复分解 ===")
--=============================================================================
local a = S.dinoRects()
local b = S.dinoRects()
check("两次调用返回同一张表（有缓存）", a == b)
--[[ ★ 不硬编码矩形数 —— 点阵改一次数量就变（实测 31~34 之间）。
       这里只断言分解结果稳定且量级合理。 ]]--
local dn = #a
check("恐龙矩形数在合理区间（20~45）", dn >= 20 and dn <= 45, dn .. " 个")
check("两次调用结果一致", #a == #b, #a .. " / " .. #b)

--=============================================================================
print("\n=== 7. 参数不合法时不崩 ===")
--=============================================================================
check("decompose(nil) -> 空表", #S.decompose(nil) == 0)
check("decompose(数字) -> 空表", #S.decompose(123) == 0)
check("decompose({}) -> 空表", #S.decompose({}) == 0)
check("gridFromRows({}) -> 空表", #S.gridFromRows({}) == 0)

--=============================================================================
print("\n=== 8. ★★ 生成的 HTML 必须自带 position:absolute ===")
--=============================================================================
--[[ 真机踩过的坑（R23）：

     矩形 div 若【没有】position:absolute，inline 的 left/top 会被忽略，
     33 个矩形全部堆在父容器左边、纵向依次排开 —— 屏幕上是一根竖条，
     而不是恐龙。

     ⚠️ 这个 bug 曾经的测试抓不到：因为它只错在【布局】，
        矩形分解、数量、覆盖正确性全都对。
        所以必须专门断言"HTML 里带了 position"。
]]
local html = S.toHTML(S.dinoRects(), { cell = 8, prefix = "dR" })
check("HTML 里带 position:absolute", html:find("position:absolute") ~= nil)

-- 每一行（每个矩形）都要有
local missing = 0
for line in html:gmatch("[^\n]+") do
  if line:find("<div") and not line:find("position:absolute") then
    missing = missing + 1
  end
end
check("★ 每个矩形都带 position:absolute", missing == 0,
    missing .. " 个矩形缺 position")

--=============================================================================
print("\n=== 9. ★★ 渲染后矩形真的铺开成形状（不是堆成一列）===")
--=============================================================================
--[[ 这是"真机症状"的直接回归：
       用 engine_mock 渲染一份恐龙，检查矩形的 box 是否铺成了 2D 形状。

       判据：
         · x 方向要覆盖多个不同列（不是全在父亲左缘）
         · y 方向也要分散
         · 整体外接框应接近 176x192
]]
local EngineMock = require('engine_mock')
local PREFABS = { container=1073741933, textbox=1073741934,
                  button=1073741935, image=1073741938 }
local E2 = EngineMock.new(PREFABS)
game = E2.game
Color = { FromRGBA=function(r,g,b,a) return {r=r,g=g,b=b,a=a} end }
Enum = {
  EaseType={Linear="L"},
  CursorEventType={CursorClick="C",CursorDown="D",CursorUp="U",CursorEnter="E",
    CursorExit="X",CursorBeginDrag="B",CursorDrag="G",CursorEndDrag="N"},
  ImageSource={StaticReference="SR"},
  TextHorizontalAlignmentLeft="L", TextHorizontalAlignmentMiddle="C",
  TextHorizontalAlignmentRight="R",
}
local root2 = E2.makeControl("container", nil)
root2.name = "Root"
E2.setRoots({ root2 })
script = { object = root2, EnableUpdate=function() end }

local webui = require('webui')
local ui2 = webui.new({ root = root2, prefabs = PREFABS, handlers = {} })

-- ★ 刻意【不提供】 .sp-rc 的 position 规则 —— 模拟调用方漏配 CSS
ui2:render([[
<style>
  .wrap { position: absolute; left: 160px; top: 508px;
          width: 176px; height: 192px; }
  .body { position: absolute; left: 0px; top: 0px; }
</style>
<div class="wrap" id="wrap"><div class="body" id="body">
]] .. S.toHTML(S.dinoRects(), { cell = 8, prefix = "z" }) .. [[
</div></div>
]])

local xs, ys = {}, {}
local n = 0
local DINO_N = #S.dinoRects()
for i = 1, DINO_N do
  local node
  webui.dom.walk(ui2.doc, function(x)
    if x:isElement() and x.attrs and x.attrs.id == ("z" .. i) then node = x end
  end)
  if node and node.box then
    n = n + 1
    xs[#xs+1] = node.box.x
    ys[#ys+1] = node.box.y
  end
end
check(DINO_N .. " 个矩形都有布局 box", n == DINO_N, n .. " 个")

local minX, maxX = math.huge, -math.huge
local minY, maxY = math.huge, -math.huge
for i = 1, #xs do
  if xs[i] < minX then minX = xs[i] end
  if xs[i] > maxX then maxX = xs[i] end
  if ys[i] < minY then minY = ys[i] end
  if ys[i] > maxY then maxY = ys[i] end
end

-- 不同 x 值的数量（堆成一列的话只有 1~2 个）
local uniqX = {}
for i = 1, #xs do uniqX[xs[i]] = true end
local nx = 0
for _ in pairs(uniqX) do nx = nx + 1 end

check("★ 矩形在水平方向铺开（>=10 个不同 x）", nx >= 10, nx .. " 个不同 x")
check("★ 矩形在垂直方向铺开（>=10 个不同 y）",
    (function()
      local u = {}
      for i = 1, #ys do u[ys[i]] = true end
      local c = 0
      for _ in pairs(u) do c = c + 1 end
      return c
    end)() >= 10)

check("★ 外接框落在父容器内（minX >= 159，bleed 会外扩 1px）", minX >= 159,
    string.format("minX=%.0f", minX))
check("★ 外接框高度接近 192", (maxY - minY) <= 192 and (maxY - minY) >= 100,
    string.format("y 跨度 %.0f", maxY - minY))

--=============================================================================
print("\n=== 10. ★★ 相邻矩形不能露缝（bleed 外扩）===")
--=============================================================================
--[[ 真机踩过的坑（R23 第二次）：

     矩形铺开后，形状上出现【一条条缝】—— 相邻矩形之间露出背景色。
     截图逐像素量得：缝宽 1.25~4.38px，缝里是纯背景色 (255,251,243)。

     根因：真机上色块的实际渲染宽度比声明值略小，
           而点阵内部有几十条相邻边界（本例 45 条）-> 满身缝。

     解法：每个矩形四边各向外扩 1px（bleed），让相邻块互相压住。
           代价是轮廓胖 1px，但同色压同色背景，看不出来。

     ★ 这里直接验【覆盖性】：把 toHTML 的输出解析回像素矩形，
       检查点阵里每个填充格的中心、以及每一条内部边界，
       是否都被某个矩形盖住。
]]
do
  local CELL = 8
  local html2 = S.toHTML(S.dinoRects(), { cell = CELL, prefix = "b" })

  -- 从 HTML 里解析出每个矩形的像素范围
  local boxes = {}
  for left, top, w, h in html2:gmatch(
      "left:(%-?%d+)px;top:(%-?%d+)px;width:(%d+)px;height:(%d+)px") do
    boxes[#boxes + 1] = { x = tonumber(left), y = tonumber(top),
                          w = tonumber(w), h = tonumber(h) }
  end
  check("解析出 " .. DINO_N .. " 个矩形", #boxes == DINO_N, #boxes .. " 个")

  local function covered(cx, cy)
    for i = 1, #boxes do
      local b = boxes[i]
      if cx >= b.x and cx <= b.x + b.w and cy >= b.y and cy <= b.y + b.h then
        return true
      end
    end
    return false
  end

  local grid = S.gridFromRows(S.DINO_ROWS)
  local GW, GH = #grid[1], #grid

  -- ① 每个填充格的中心
  local holes = 0
  for gy = 1, GH do
    for gx = 1, GW do
      if grid[gy][gx] == 1 then
        if not covered((gx-1)*CELL + CELL/2, (gy-1)*CELL + CELL/2) then
          holes = holes + 1
        end
      end
    end
  end
  check("★ 每个填充格中心都被盖住（无空洞）", holes == 0, holes .. " 个空洞")

  -- ② 相邻填充格之间的【竖边界】—— 缝就出在这里
  local vEdge = 0
  for gy = 1, GH do
    for gx = 1, GW - 1 do
      if grid[gy][gx] == 1 and grid[gy][gx+1] == 1 then
        if not covered(gx * CELL, (gy-1)*CELL + CELL/2) then
          vEdge = vEdge + 1
        end
      end
    end
  end
  check("★ 竖边界无缝（相邻格之间）", vEdge == 0, vEdge .. " 条缝")

  -- ③ 相邻填充格之间的【横边界】
  local hEdge = 0
  for gy = 1, GH - 1 do
    for gx = 1, GW do
      if grid[gy][gx] == 1 and grid[gy+1][gx] == 1 then
        if not covered((gx-1)*CELL + CELL/2, gy * CELL) then
          hEdge = hEdge + 1
        end
      end
    end
  end
  check("★ 横边界无缝（相邻格之间）", hEdge == 0, hEdge .. " 条缝")

  -- ④ 反证：bleed=0 时相邻矩形【只是严格相接】，没有任何重叠余量。
  --    真机上正是这 0 余量导致渲染误差露缝。
  --    这里比较两者在同一探测带的覆盖，确认 bleed 确实带来了重叠。
  local htmlNo = S.toHTML(S.dinoRects(), { cell = CELL, prefix = "n", bleed = 0 })
  local boxesNo = {}
  for left, top, w, h in htmlNo:gmatch(
      "left:(%-?%d+)px;top:(%-?%d+)px;width:(%d+)px;height:(%d+)px") do
    boxesNo[#boxesNo + 1] = { x = tonumber(left), y = tonumber(top),
                              w = tonumber(w), h = tonumber(h) }
  end

  -- 每个矩形应比 bleed=0 时宽 2px、高 2px（四边各外扩 1px）
  local wider = 0
  for i = 1, math.min(#boxes, #boxesNo) do
    if boxes[i].w == boxesNo[i].w + 2 and boxes[i].h == boxesNo[i].h + 2 then
      wider = wider + 1
    end
  end
  check("★ 每个矩形四边各外扩 1px（宽高 +2）", wider == #boxesNo,
      wider .. "/" .. #boxesNo)

  -- 外扩后，矩形之间必然互相重叠（不再只是"严格相接"）
  --   ★ 用"重叠对数"判断，比"同一行间隙"可靠：
  --     不同行的矩形本来就有水平间隙（形状的凹凸），属于正常。
  local function overlaps(bxs)
    local n = 0
    for i = 1, #bxs do
      for j = i + 1, #bxs do
        local a, b = bxs[i], bxs[j]
        if a.x < b.x + b.w and b.x < a.x + a.w
           and a.y < b.y + b.h and b.y < a.y + a.h then
          n = n + 1
        end
      end
    end
    return n
  end

  local ovBleed = overlaps(boxes)
  local ovNo = overlaps(boxesNo)
  check("★ bleed=1 后相邻矩形产生重叠（互相压住）", ovBleed > ovNo,
      string.format("bleed=1: %d 对重叠, bleed=0: %d 对", ovBleed, ovNo))
  -- 实测 52 对（覆盖点阵内部那 45 条相邻边界所需的量级）
  check("★ 重叠对数与内部边界数同量级（>=40）", ovBleed >= 40,
      ovBleed .. " 对重叠")
end

print("")
print(string.format(">>> 通过 %d / 失败 %d", pass, fail))
if fail > 0 then os.exit(1) end
