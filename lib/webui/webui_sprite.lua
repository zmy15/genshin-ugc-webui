--[[============================================================================
  webui_sprite.lua  ——  用多个矩形图片控件拼出像素图形

  ══════════════════════════════════════════════════════════════════════════
  为什么需要它
  ══════════════════════════════════════════════════════════════════════════

    引擎【不能导入外部图像】，而预置资源只有 6 张形状图
    （方/圆/三角/四角星/五角星/圆环）。想画恐龙这种不规则图形，
    只能把点阵分解成矩形，每个矩形用 1 个图片控件（方形图 100001）。

  ══════════════════════════════════════════════════════════════════════════
  ★★ 性能依据（R22 真机实测，docs/引擎能力与限制.md §4.6）
  ══════════════════════════════════════════════════════════════════════════

     每帧耗时(ms) = 11.92 + 0.0449 x 写入次数
                     ↑ 固定(与节点数相关)   ↑ 单次写入仅 44.9 微秒

     => 写入【极便宜】：33 个矩形全量更新约 1.5ms，性能无忧。
     => 真正的成本是【固定 11.92ms】，与 DOM 节点数正相关。
        所以优化方向是【减节点】，不是"少写字段"。

  ══════════════════════════════════════════════════════════════════════════
  ★★ 用法（父容器整体移动 + 换帧时重算）
  ══════════════════════════════════════════════════════════════════════════

     把 N 个矩形塞进【一个父容器】，之后：

       · 每帧移动：只写父容器 1 次  ->  整只图形跟着动（几乎零成本）
       · 换姿态：重算 N 个矩形的尺寸/位置（约 1.5ms，每几帧才一次）

     这正是"父容器整体移动 + 换帧时重算"的推荐做法。

  ══════════════════════════════════════════════════════════════════════════
  ⚠️ 约束（复用本项目已验证的规则）
  ══════════════════════════════════════════════════════════════════════════

     · 矩形用【纯色块】画（background-color），不用 SetImage ——
       方形图拉伸了还是矩形，所以色块与图片等价，而色块更省：
       不需要图片资源、不占 image 控件池、不用调 SetImage。
       ★ 实测：带 background-color 的 div 会被选成 textbox（不是 image），
         这是【正确且期望】的行为（render.lua 的 chooseKind 规则②）。
     · 父容器用 overflow:hidden 时不要设 background-color（§4.5.2）
     · 每个矩形都是独立控件 -> 会占控件池，图形别做太碎
=============================================================================]]

local util = require('webui_util')

local S = {}

--=============================================================================
-- 矩形分解：把点阵转成矩形列表
--=============================================================================

--[[ 贪心最大矩形分解。

     输入 grid：二维数组，grid[y][x] 为 true/1 表示该格填充
               （y 从 1 开始，x 从 1 开始 —— 与 Lua 习惯一致）
     返回：{{x=, y=, w=, h=}, ...}（x/y 从 1 开始）

     ★ 为什么用贪心最大矩形而不是"逐行分段"：
       逐行分段会产生大量细长条（实测恐龙要 70 段），
       而贪心最大矩形只要 33 个 —— 少一半控件。
]]--
function S.decompose(grid)
  if type(grid) ~= "table" then return {} end

  local h = #grid
  local w = 0
  for y = 1, h do
    if type(grid[y]) == "table" and #grid[y] > w then w = #grid[y] end
  end
  if h == 0 or w == 0 then return {} end

  -- 复制一份可变矩阵
  --[[ ★★ 必须显式判断 == 1 —— Lua 里 0 是【真值】！

       早期写成 `(grid[y] and grid[y][x]) and 1 or 0`，
       于是 0 被当成"有值"转成 1，整个点阵全变实心，
       分解出 1 个覆盖全图的大矩形。（踩过，有测试守着。） ]]
  local m = {}
  for y = 1, h do
    m[y] = {}
    for x = 1, w do
      local v = grid[y] and grid[y][x]
      m[y][x] = (v == 1 or v == true) and 1 or 0
    end
  end

  --[[ 全 1 矩形检测：用"以 (x,y) 为右下角的最大矩形高度"加速。

       简单实现（四重循环）在 22x24 上够快，但图形大了会很慢。
       这里用经典的"柱状图最大矩形"思路做增量。 ]]--
  local rects = {}

  --[[ 找当前矩阵里的最大全 1 矩形。

       ★ 这里刻意用【直白的四重循环 + 逐格校验】，不用单调栈。
         原因：单调栈版本写错过一次（把列下标当高度用），
         结果分解出 1 个覆盖全图的矩形 —— 而图形小（22x24）时，
         直白写法足够快，且【正确性一眼可验】。

       做法：枚举所有 (左上角, 右下角) 组合，逐格确认全为 1，
             取面积最大者。
  ]]--
  local function findLargest()
    local best = nil
    for y1 = 1, h do
      for x1 = 1, w do
        if m[y1][x1] == 1 then
          local maxX = w
          for y2 = y1, h do
            --[[ ★ 必须先确认【本行起点】就是 1 ——
                 早期版本直接从 x1+1 往右探，漏检了 (y2, x1) 本身，
                 于是把空行也算进矩形，分解出覆盖全图的大矩形。 ]]
            if m[y2][x1] ~= 1 then break end

            -- 本行能向右延伸多远
            local x2 = x1
            while x2 + 1 <= maxX and m[y2][x2 + 1] == 1 do x2 = x2 + 1 end
            maxX = x2                          -- 下一行不能超过本行宽度

            local area = (y2 - y1 + 1) * (maxX - x1 + 1)
            if not best or area > best.area then
              best = {
                area = area, x = x1, y = y1,
                w = maxX - x1 + 1, h = y2 - y1 + 1,
              }
            end
          end
        end
      end
    end
    return best
  end

  -- 反复抠出最大矩形
  local guard = 0
  while true do
    guard = guard + 1
    if guard > 5000 then break end        -- 安全阀
    local r = findLargest()
    if not r then break end
    rects[#rects + 1] = { x = r.x, y = r.y, w = r.w, h = r.h }
    for y = r.y, r.y + r.h - 1 do
      for x = r.x, r.x + r.w - 1 do
        m[y][x] = 0
      end
    end
  end

  return rects
end

--[[ 从字符串数组生成点阵。

     rows = {
       "..##..",
       ".####.",
     }
     '#' 或 '1' 或 'x' 或 'X' 表示填充，其余为空。

     ★ 写图形时用字符串最直观，也便于从截图逐格转录。 ]]--
function S.gridFromRows(rows)
  local grid = {}
  for y = 1, #rows do
    local line = rows[y]
    grid[y] = {}
    for x = 1, #line do
      local c = line:sub(x, x)
      grid[y][x] = (c == "#" or c == "1" or c == "x" or c == "X") and 1 or 0
    end
  end
  return grid
end

--=============================================================================
-- 生成 HTML：把矩形表变成一堆 div
--=============================================================================

--[[ 生成矩形的 HTML。

     rects   S.decompose 的结果（或手写的 {x=,y=,w=,h=} 列表）
     opts    {
       cell    = 8,          -- 每个逻辑格多少 px
       prefix  = "sp",       -- id 前缀，用于运行时查找
       color   = "#535353",  -- 填充色（走 background-color）
       bleed   = 1,          -- ★ 每边向外扩多少 px（默认 1，见下）
       asImage = false,      -- ★ 用 image 控件（data-image）而非色块
     }
     返回：HTML 字符串（一串 div，父容器由调用方提供）

     ★★ 每个矩形【必须】position:absolute，否则 inline 的 left/top
        会被忽略，所有矩形挤成一条竖线堆在父容器左边。

        真机实测症状（R23）：
          父容器 176x192 里 33 个矩形全堆在 x=父左缘，
          纵向依次排开 —— 屏幕上是一根竖条，而不是恐龙。
          根因：子元素是静态流布局，left/top 对它们无效。

        ★ 所以这里把 position:absolute 写成【内联样式】，
          不依赖调用方是否记得配 CSS —— 之前的版本要调用方
          自己写 .sp-rc { position:absolute }，漏了就出这个 bug。

     ★★ bleed（外扩）：真机上相邻矩形之间会【露出背景缝】。

        真机实测（R23）：
          · 33 个矩形在点阵内部有 【45 条相邻边界】
          · 截图逐像素量得，这些边界处能看到 1.25~4.38px 的背景色缝

        所以每个矩形四边各向外扩 `bleed` px，让相邻块【互相压住】。

     ★★★ asImage：绕开【文本框模板自带的圆角】（R24）

        真机实测：textbox 模板外观【自带圆角】，且半径不小于 8px。
        于是：
          · 1 格宽（8px）的矩形 -> 圆角吃掉四角 -> 变成【圆形】
          · 33 个矩形里 29 个至少一边 <= 16px -> 88% 都变形
          · 圆角还让相邻矩形的四角对不上 -> 就是那些缝

        ⚠️ 圆角来自【控件模板】，不是 CSS ——
           docs/引擎能力与限制.md §4.3.4 记着 borderRadius 等
           6 个字段真机写入全部失败，代码改不了。

        => 所以提供 asImage 开关：改用 image 控件（贴方形图），
           它的模板外观可能没有圆角。
           ⚠️ 这一点【尚未真机验证】—— 需先在编辑器里看 image 模板。
]]--
function S.toHTML(rects, opts)
  opts = opts or {}
  local cell = opts.cell or 8
  local prefix = opts.prefix or "sp"
  local color = opts.color or "#535353"
  local bleed = opts.bleed
  if bleed == nil then bleed = 1 end
  local out = {}

  for i = 1, #rects do
    local r = rects[i]
    local x = (r.x - 1) * cell - bleed
    local y = (r.y - 1) * cell - bleed
    local w = r.w * cell + bleed * 2
    local h = r.h * cell + bleed * 2

    if opts.asImage then
      -- ★ 用 image 控件（贴方形图）绕开 textbox 模板的圆角。
      --   注意：不加 background-color —— 加了会被选成 textbox（chooseKind 规则②）
      --   ★ 用 %g 而非 %.1f：%g 对整数输出 "18"，浮点输出 "11.34"，
      --     不会出现 "18.0"（会让按整数解析的测试/引擎字段失配）
      out[#out + 1] = string.format(
        '<div class="%s" id="%s%d" data-image="1" style="position:absolute;left:%gpx;top:%gpx;width:%gpx;height:%gpx"></div>\n',
        opts.class or "sp-rc", prefix, i, x, y, w, h)
    else
      out[#out + 1] = string.format(
        '<div class="%s" id="%s%d" style="position:absolute;left:%gpx;top:%gpx;width:%gpx;height:%gpx;background-color:%s"></div>\n',
        opts.class or "sp-rc", prefix, i, x, y, w, h, color)
    end
  end

  return table.concat(out)
end

--[[ ★ asImage 模式下，把方形图贴到每个矩形控件上。

     必须在渲染后调用一次（用 webui_clip.setImage）。

     dom, doc  从 ui.rendered / ui.doc 取
     prefix    与 toHTML 的 prefix 一致
     count     矩形数量
     shapeId   方形图 ID，默认 100001

     返回：成功贴图的数量

     ★ 只需在【建控件时】调一次；换姿态只改尺寸/位置，不用重贴。
]]--
function S.setImages(clip, dom, doc, prefix, count, shapeId, rendered)
  shapeId = shapeId or 100001
  local n = 0
  for i = 1, count do
    local node = nil
    dom.walk(doc, function(x)
      if not node and x:isElement() and x.attrs and x.attrs.id == (prefix .. i) then
        node = x
      end
    end)
    if node then
      -- 优先用 rendered.live（拿控件引用最可靠）
      local ctrl = nil
      if rendered and rendered.live then
        local e = rendered.live[node]
        ctrl = e and e.control
      end
      ctrl = ctrl or node.control
      if ctrl and clip.setImage(ctrl, shapeId) then
        n = n + 1
      end
    end
  end
  return n
end

--[[ 生成配套 CSS（矩形绝对定位在父容器里）。

     ⚠️ 现在 toHTML 已经把 position 写成内联样式了，
        所以这个函数【通常不需要再调】。保留是为了兼容旧代码，
        以及需要统一改样式（如加 class 选择器）的场景。 ]]--
function S.css(opts)
  opts = opts or {}
  local cls = opts.class or "sp-rc"
  return string.format([[
.%s { position: absolute; left: 0px; top: 0px; }
]], cls)
end

--=============================================================================
-- 运行时：把矩形表应用到已渲染的节点上
--=============================================================================

--[[ 收集某个前缀下的所有矩形节点。

     返回 { [i] = node, ... }（i 从 1 开始，对应 toHTML 生成的顺序） ]]--
function S.collect(dom, doc, prefix, count)
  local nodes = {}
  for i = 1, count do
    local found = nil
    dom.walk(doc, function(n)
      if not found and n:isElement() and n.attrs and n.attrs.id == (prefix .. i) then
        found = n
      end
    end)
    nodes[i] = found
  end
  return nodes
end

--[[ ★ 换姿态：把新矩形表写回已有节点。

     nodes    S.collect 的结果
     rects    新姿态的矩形表
     cell     每格 px
     visible  需要显示的矩形数（多余的隐藏）
     bleed    每边向外扩多少 px（★ 必须与 toHTML 用同一个值，
              否则换姿态后缝又回来了）
     reimage  可选：function(node) -> 给该节点重贴方形图
              ★ 只在 asImage 模式下需要（换姿态会把隐藏的矩形
                重新显示，而控件可能已被池子回收 -> 图丢失）

     返回：实际写入的字段数

     ★ 只在【姿态切换时】调用（约每几帧一次），不要每帧调 ——
       虽然实测 33 个矩形全量更新只要 1.5ms，但没必要。
]]--
function S.apply(nodes, rects, cell, visible, bleed, reimage)
  cell = cell or 8
  visible = visible or #rects
  if bleed == nil then bleed = 1 end
  local writes = 0

  for i = 1, #nodes do
    local n = nodes[i]
    if n then
      local r = rects[i]
      if r and i <= visible then
        local wasHidden = n._displayOverride == "none"
        n:show()
        -- ★ 之前是隐藏的 -> 控件可能被回收过，重贴一次图
        if wasHidden and type(reimage) == "function" then
          pcall(reimage, n)
        end
        n:setStyle("left",   ((r.x - 1) * cell - bleed) .. "px")
        n:setStyle("top",    ((r.y - 1) * cell - bleed) .. "px")
        n:setStyle("width",  (r.w * cell + bleed * 2) .. "px")
        n:setStyle("height", (r.h * cell + bleed * 2) .. "px")
        writes = writes + 4
      else
        n:hide()
      end
    end
  end

  return writes
end

--=============================================================================
-- 预置：小恐龙点阵（从原版截图逐格转录，22x24 逻辑格）
--=============================================================================

--[[ ★★ 恐龙站立帧 22x24（原版 44x47 逐格转录）

     ★ 为什么回到 22x24：用户反馈 16x17 重采样后
       【眼睛丢了】。眼睛只占 1 格（行3 列14），
       重采样到 17 行时被采样吞掉了。

     ★ 嬺度要保持 = 中仙人掌 136px，
       所以 cell 用 136/24 = 5.67px（浮点）。 ]]--

S.DINO_ROWS = {
  "............#########.",
  "...........###########",
  "...........##.########",
  "...........###########",
  "...........###########",
  "...........###########",
  "...........######.....",
  "...........#########..",
  "#.........#####.......",
  "#.........#####.......",
  "#.......#######.......",
  "##.....###########....",
  "###..##########..#....",
  "###############.......",
  "###############.......",
  ".##############.......",
  "..############........",
  "...##########.........",
  "....########..........",
  ".....####..###........",
  ".....####..###........",
  "....###.#.............",
  ".....##...............",
  ".....###..............",
}

--[[ 恐龙跑动帧 22x24：两条腿交替摆动。 ]]--

S.DINO_RUN_ROWS = {
  "............#########.",
  "...........###########",
  "...........##.########",
  "...........###########",
  "...........###########",
  "...........###########",
  "...........######.....",
  "...........#########..",
  "#.........#####.......",
  "#.........#####.......",
  "#.......#######.......",
  "##.....###########....",
  "###..##########..#....",
  "###############.......",
  "###############.......",
  ".##############.......",
  "..############........",
  "...##########.........",
  "....########..........",
  "....####..####........",
  "...####...####........",
  "...###....###.........",
  "....##.....##.........",
  "....###....###........",
}

--[[ 恐龙死亡帧 22x24：眼睛那一格留空（看起来像闭眼）。 ]]--

S.DINO_DEAD_ROWS = {
  "............#########.",
  "...........###########",
  "...........###########",
  "...........###########",
  "...........###########",
  "...........###########",
  "...........######.....",
  "...........#########..",
  "#.........#####.......",
  "#.........#####.......",
  "#.......#######.......",
  "##.....###########....",
  "###..##########..#....",
  "###############.......",
  "###############.......",
  ".##############.......",
  "..############........",
  "...##########.........",
  "....########..........",
  ".....####..###........",
  ".....####..###........",
  "....###.#.............",
  ".....##...............",
  ".....###..............",
}

--[[ 仙人掌三档（原版有大/中/小三种，随机出现）。

     ★★ 全部从原版截图逐格转录（覆盖率重采样），
        并用连通域校验「必须是一整块，不能有悬空碎块」。

     ⚠️ 提取时的两个坑（都实际踩过）：
       ① 原图 y>=218 是【地面线】，不是仙人掌的一部分
          -> crop 必须裁到 y=205 就停，否则脚底下多一条横线
       ② 三株仙人掌的 x 范围【有重叠】（中 138..202，小 192..240）
          -> crop 不收紧会把邻株的臂切进来，导致"断成两块"
             （中仙人掌因此改成 138..185） ]]--

-- 大仙人掌 9x18（原版约 17x35，取一半精度）
S.CACTUS_BIG_ROWS = {
  "...###...",
  "...###...",
  "...###...",
  "...###...",
  "...###...",
  "...###..#",
  "##.###.##",
  "##.###.##",
  "##.###.##",
  "##.###.##",
  "##.###.##",
  "##.###.##",
  "#########",
  "########.",
  ".#####...",
  "...###...",
  "...###...",
  "...###...",
}

-- 中仙人掌 6x17
S.CACTUS_MID_ROWS = {
  "...##.",
  "...##.",
  "...##.",
  "...##.",
  "...##.",
  "...##.",
  "...##.",
  "##.###",
  "##.###",
  "##.##.",
  "##.##.",
  "##.##.",
  "#####.",
  ".####.",
  "...##.",
  "...##.",
  "...##.",
}

-- 小仙人掌 5x12（最矮，只有主干 + 两短臂）
S.CACTUS_SMALL_ROWS = {
  "..#..",
  "..#..",
  "..#..",
  "#.#.#",
  "#.#.#",
  "#.#.#",
  "#.#.#",
  "#.#.#",
  "#####",
  ".###.",
  "..#..",
  "..#..",
}

--[[ ★ 兼容别名：旧的单一日 CACTUS_ROWS 指向小仙人掌。

     ⚠️ demo_dino 早期版本用它；改成三档后保留别名，
        避免调用方 require 时拿到 nil。 ]]--
S.CACTUS_ROWS = S.CACTUS_SMALL_ROWS

--[[ ★★ 仙人掌组合（原版会一次出 2~3 株）。

     原版截图里常见：两株小仙人掌并排、或中+小一高一矮。
     组合 = 把单株点阵【底部对齐】并排拼成一行，
     移动时整组一起动、一起碰撞。

     ★ 为什么是底部对齐：所有脚都在地面线上。 ]]--

-- 组合 A：小+小（双株，最常见）
S.CACTUS_DOUBLE_ROWS = {
  "..#.......#..",
  "..#.......#..",
  "..#.......#..",
  "#.#.#...#.#.#",
  "#.#.#...#.#.#",
  "#.#.#...#.#.#",
  "#.#.#...#.#.#",
  "#.#.#...#.#.#",
  "#####...#####",
  ".###.....###.",
  "..#.......#..",
  "..#.......#..",
}

-- 组合 B：中+小（一高一矮）
S.CACTUS_MIX_ROWS = {
  "...##........",
  "...##........",
  "...##........",
  "...##........",
  "...##........",
  "...##.....#..",
  "...##.....#..",
  "##.###....#..",
  "##.###..#.#.#",
  "##.##...#.#.#",
  "##.##...#.#.#",
  "##.##...#.#.#",
  "#####...#.#.#",
  ".####...#####",
  "...##....###.",
  "...##.....#..",
  "...##.....#..",
}

--[[ 翼龙 20x10（空中障碍，两个高度来回飞）。

     ★ 从【原版截图】逐格转录，不是手调的。

     形状：喙在左上、眼睛是那个缺口、翅膀向右下展开。 ]]--
S.BIRD_ROWS = {
  "......##............",
  "......###...........",
  "....##.###..........",
  "...###.#####........",
  "..###########.......",
  "##############......",
  ".....#########......",
  ".......#############",
  "........###########.",
  ".........########...",
}

--[[ ★★ 翼龙扇翅帧（翅膀放下）。

     原版的两个动作：
       BIRD_ROWS      = 翅抬起（上面）
       BIRD_FLAP_ROWS = 翅放下（这条）—— 尾巴明显下垂

     ★ 两帧都验证过是【单一连通块】。 ]]--
S.BIRD_FLAP_ROWS = {
  "...###..............",
  "..#####.............",
  ".######.............",
  "##############......",
  ".......#############",
  "........###########.",
  "........########....",
  "........###.........",
  "........##..........",
  "........#...........",
}

--[[ ★★ 翼龙第三帧（翅膀半收）—— 让扇翅变成【三帧循环】而不是来回两帧。

     为什么值得加：
       两帧来回（A-B-A-B）看起来是"抖"，不像扇翅膀；
       三帧循环（抬 -> 半收 -> 放下 -> 抬）才有"扑翼"的节奏感。

     ★ 尺寸与另外两帧严格一致（20x10），否则扇翅时会横向跳动 ——
       因为容器尺寸是按 20x10 格固定的，点阵宽度不一致就会错位。 ]]--
S.BIRD_MID_ROWS = {
  "......##............",
  "....##.###..........",
  "...###########......",
  "##############......",
  ".....##########.....",
  ".......#############",
  "........###########.",
  "........##########..",
  "........#####.......",
  ".........##.........",
}

--[[ 云点阵（原版云是浅灰色轮廓，10x5）。 ]]--
S.CLOUD_ROWS = {
  "...####...",
  "..######..",
  "##########",
  ".########.",
  "..........",
}

--[[ 地面装饰：小石子/草丛（原版地面不是纯直线，点缀着小图案）。

     ★ 三个独立的点缀，宽度递减。它们贴在【地面线上】，
       随场景一起滚动，用来打破"一条直线"的单调。 ]]--
S.DECO_PEBBLE_ROWS = {     -- 小石子 5x2
  ".###.",
  "#####",
}
S.DECO_GRASS_ROWS = {      -- 草丛 7x2
  "#.#.#.#",
  "#######",
}
S.DECO_TUFT_ROWS = {       -- 小簇 3x2
  ".#.",
  "###",
}

--=============================================================================
-- 预置：直接取矩形表（带缓存，避免重复分解）
--=============================================================================

local rectCache = {}

local function cachedRects(name, rows)
  if not rectCache[name] then
    rectCache[name] = S.decompose(S.gridFromRows(rows))
  end
  return rectCache[name]
end

function S.dinoRects()      return cachedRects("dino",     S.DINO_ROWS)      end
function S.dinoRunRects()   return cachedRects("dinoRun",  S.DINO_RUN_ROWS)  end
function S.dinoDeadRects()  return cachedRects("dinoDead", S.DINO_DEAD_ROWS) end

-- 仙人掌三档
function S.cactusRects()       return cachedRects("cactusS", S.CACTUS_SMALL_ROWS) end
function S.cactusBigRects()    return cachedRects("cactusB", S.CACTUS_BIG_ROWS)   end
function S.cactusMidRects()    return cachedRects("cactusM", S.CACTUS_MID_ROWS)   end
function S.cactusSmallRects()  return cachedRects("cactusS", S.CACTUS_SMALL_ROWS) end

-- 仙人掌组合（一次出 2 株）
function S.cactusDoubleRects() return cachedRects("cactusD", S.CACTUS_DOUBLE_ROWS) end
function S.cactusMixRects()    return cachedRects("cactusX", S.CACTUS_MIX_ROWS)    end

function S.birdRects()      return cachedRects("bird",     S.BIRD_ROWS)      end
function S.birdFlapRects()  return cachedRects("birdFlap", S.BIRD_FLAP_ROWS)  end
function S.birdMidRects()   return cachedRects("birdMid",  S.BIRD_MID_ROWS)  end

--[[ ★★ 翼龙的【三帧扇翅循环】。

     顺序 = 抬翅(主帧) -> 半收 -> 放下(扇翅帧) -> 半收 -> 抬翅 ...
     （demo 里按下标轮转，回到主帧后继续，形成连续扑翼）

     ★ 只在这里定义一次，demo 与测试都从这里取 ——
       避免"两处各写一份帧表、改了一处忘另一处"。 ]]--
function S.birdFrames()
  return { S.birdRects(), S.birdMidRects(), S.birdFlapRects() }
end
function S.cloudRects()     return cachedRects("cloud",    S.CLOUD_ROWS)     end

-- 地面装饰
function S.pebbleRects()    return cachedRects("pebble",   S.DECO_PEBBLE_ROWS) end
function S.grassRects()     return cachedRects("grass",    S.DECO_GRASS_ROWS)  end
function S.tuftRects()      return cachedRects("tuft",     S.DECO_TUFT_ROWS)   end

--[[ ★ 仙人掌三档打包 + 组合，方便随机挑选。

     返回 { {rects=, w=, h=}, ... }（w/h 是逻辑格数）
     含 2 个组合（双株小、中+小）—— 原版会一次出 2 株。 ]]--
function S.cactusVariants()
  return {
    { rects = S.cactusBigRects(),   w = 9, h = 18 },
    { rects = S.cactusMidRects(),   w = 6, h = 17 },
    { rects = S.cactusSmallRects(), w = 5, h = 12 },
    { rects = S.cactusDoubleRects(), w = 13, h = 12 },
    { rects = S.cactusMixRects(),    w = 14, h = 17 },
  }
end

--[[ ★ 地面装饰打包，方便随机挑选。 ]]--
function S.decoVariants()
  return {
    { rects = S.pebbleRects(), w = 5, h = 2 },
    { rects = S.grassRects(),  w = 7, h = 2 },
    { rects = S.tuftRects(),   w = 3, h = 2 },
  }
end

--=============================================================================
-- ★★ 仙人掌组合：运行时随机拼 1~N 株
--=============================================================================

--[[ 把若干株仙人掌【底部对齐】并排拼成一个点阵。

     stalks  数组，每项 = { rows = 点阵字符串数组, gap = 右侧间距(格) }
             rows 必须是同宽的矩形点阵；「底部对齐」由本函数负责。
     gap     株与株之间的默认间距（格），可被每株的 gap 覆盖

     返回：{ rows = 拼接后的点阵字符串数组, w = 总宽(格), h = 总高(格) }

     ★★ 为什么要底部对齐而不是顶部对齐：

        仙人掌的脚都踩在地面线上，高度又各不相同（大 18 / 中 17 / 小 12 格）。
        若顶部对齐，矮的那株脚就悬在半空 —— 真机上看起来"仙人掌浮起来了"，
        而代码不会报错。这是本函数存在的唯一理由。

     ★ 拼接策略：先算出总宽 = 所有株宽 + 间距，总高 = 最高的那株，
       然后每株按 (总高 - 自身高) 行偏移写入 —— 这就是底部对齐。 ]]--
function S.joinStalks(stalks, gap)
  if type(stalks) ~= "table" or #stalks == 0 then
    return { rows = {}, w = 0, h = 0 }
  end
  gap = gap or 1

  -- ① 先量出总宽与总高
  local totalW, totalH = 0, 0
  for i = 1, #stalks do
    local st = stalks[i]
    local rows = st.rows or {}
    local h = #rows
    local w = 0
    for y = 1, h do
      if #rows[y] > w then w = #rows[y] end
    end
    st._w, st._h = w, h
    totalW = totalW + w
    if i < #stalks then totalW = totalW + (st.gap or gap) end
    if h > totalH then totalH = h end
  end
  if totalW == 0 or totalH == 0 then
    return { rows = {}, w = 0, h = 0 }
  end

  -- ② 准备空白画布（全部 '.'）
  local canvas = {}
  for y = 1, totalH do
    canvas[y] = string.rep(".", totalW)
  end

  -- ③ 逐株按【底部对齐】贴上去
  local cx = 0                                   -- 当前株的左边界（0 基）
  for i = 1, #stalks do
    local st = stalks[i]
    local rows = st.rows
    local yOffset = totalH - st._h               -- ★ 底部对齐的关键
    for sy = 1, st._h do
      local src = rows[sy]
      local ty = yOffset + sy
      local line = canvas[ty]
      for sx = 1, st._w do
        if src:sub(sx, sx) == "#" then
          local tx = cx + sx                      -- 1 基列号
          line = line:sub(1, tx - 1) .. "#" .. line:sub(tx + 1)
        end
      end
      canvas[ty] = line
    end
    cx = cx + st._w + (st.gap or gap)
  end

  return { rows = canvas, w = totalW, h = totalH }
end

--[[ ★★ 随机拼一组仙人掌（运行时用，1~count 株）。

     count    株数（1~4）
     rndFn    取随机数的函数：返回 0..1（调用方传入，便于复现）
     kinds    可选：株型表 { {rows=,w=,h=}, ... }，默认用大/中/小三种

     返回：{ rects = 矩形表, w, h, stalks = 实际株型索引数组 }
           w/h 单位是【格】，rects 是分解好的矩形表。

     ★ 为什么在库里做而不是在 demo 里做：

       拼接 + 底部对齐 + 分解这套逻辑与「点阵」强相关，
       放在库里可以被测试单独覆盖（不必启动整个游戏）。
       demo 只负责「随机挑几株」这一步的调用。

     ★★ 密度：株间默认留 0 格间距（紧挨着），
        因为原版里连排的仙人掌就是贴在一起的；
        太宽会让玩家无处可跳（障碍越宽，跳过它需要的滞空越久）。 ]]--
function S.randomCactusGroup(count, rndFn, kinds)
  rndFn = rndFn or function() return 0.5 end
  kinds = kinds or S.CACTUS_KINDS

  if count < 1 then count = 1 end
  if count > 4 then count = 4 end

  local stalks, picked = {}, {}
  for i = 1, count do
    local k = math.floor(rndFn() * #kinds) + 1
    if k > #kinds then k = #kinds end
    if k < 1 then k = 1 end
    picked[i] = k
    stalks[i] = { rows = kinds[k].rows }
  end

  local joined = S.joinStalks(stalks, 0)
  return {
    rects  = cachedRects("grp:" .. table.concat(picked, ",") .. "",
                         joined.rows),
    w      = joined.w,
    h      = joined.h,
    rows   = joined.rows,
    stalks = picked,
  }
end

--[[ ★ 三种单株仙人掌（点阵原文），供 randomCactusGroup 挑选。

     顺序 = 大 / 中 / 小，与 demo 里的观感一致。 ]]--
S.CACTUS_KINDS = {
  { name = "big",   rows = S.CACTUS_BIG_ROWS,   w = 9, h = 18 },
  { name = "mid",   rows = S.CACTUS_MID_ROWS,   w = 6, h = 17 },
  { name = "small", rows = S.CACTUS_SMALL_ROWS, w = 5, h = 12 },
}

--[[ 给一个组合规格（株型索引数组）算出确定性的组合结果。

     用于测试与「按难度指定组合」（同一规格必须每次得到同一张矩形表）。 ]]--
function S.cactusGroup(keys, gap)
  local stalks = {}
  for i = 1, #keys do
    local k = S.CACTUS_KINDS[keys[i]]
    if k then stalks[#stalks + 1] = { rows = k.rows, gap = gap } end
  end
  local joined = S.joinStalks(stalks, gap or 0)
  return {
    rects = cachedRects("grp:" .. table.concat(keys, ",") .. ":" ..
                        tostring(gap or 0), joined.rows),
    w     = joined.w,
    h     = joined.h,
    rows  = joined.rows,
    stalks = keys,
  }
end

return S
