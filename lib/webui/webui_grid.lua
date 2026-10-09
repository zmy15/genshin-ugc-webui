--[[============================================================================
  webui/grid.lua  ——  CSS Grid 布局

  ============================================================================
  为什么单独一个模块
  ============================================================================

  grid 的轨道尺寸解析（fr 分配、auto 轨道、span 跨列）与 flex
  是两套完全不同的算法，塞进 layout.lua 会让那个文件难以维护。
  这里只做【纯计算 + 布局回调】，不依赖渲染层，便于单独验算。

  ============================================================================
  支持范围（对齐原生 CSS 的常用子集）
  ============================================================================

    display: grid / inline-grid                     ✅
    grid-template-columns / grid-template-rows      ✅
      · 固定长度     100px / 20%
      · fr 单位      1fr / 2fr / 0.5fr
      · auto         按内容撑开
      · repeat(n, ...) 与 repeat(auto-fill, ...)
    gap / row-gap / column-gap                      ✅
    grid-column / grid-row（1-based）               ✅
      支持 "2" / "2 / 4" / "span 2" / "1 / span 2"
    grid-auto-flow: row / column                    ✅
    自动排列（auto-placement）                       ✅
    justify-items / align-items（轨道内对齐）        ✅

  不支持（会退化成合理默认，并 warn 一次）：
    grid-template-areas / grid-area（命名区域）
    minmax() / fit-content()
    隐式轨道尺寸（grid-auto-rows/columns 的具体值）
    负数列号（-1 表示最后一条线）

  ============================================================================
  算法（简化但语义正确）
  ============================================================================

    1. 解析轨道模板 -> 列表 { kind="px"|"%"|"fr"|"auto", value=... }
    2. 放置网格项：
         · 有显式 grid-column/row -> 放到指定位置（可能产生隐式轨道）
         · 否则按 auto-flow 顺序找下一个空位（跳过已占格）
    3. 解析轨道尺寸：
         · 固定/百分比轨道先定
         · auto 轨道按内容（该项的最大固有尺寸）
         · 剩余空间按 fr 权重分配
    4. 逐项布局，用轨道线坐标算位置
==============================================================================]]

local util = require('webui_util')

local G = {}

--=============================================================================
-- 轨道模板解析
--=============================================================================

--[[ 展开 repeat()。

     repeat(3, 1fr)          -> 1fr 1fr 1fr
     repeat(2, 100px 1fr)    -> 100px 1fr 100px 1fr
     repeat(auto-fill, 80px) -> 由调用方按可用宽度决定份数

     返回 展开后的 token 串, autoFillCount（0 表示不是 auto-fill）
]]--
local function expandRepeat(s, availW)
  local out = {}
  local autoFill = 0
  local pos = 1

  while true do
    local st, en = s:find("repeat%s*%(", pos)
    if not st then
      out[#out + 1] = s:sub(pos)
      break
    end
    out[#out + 1] = s:sub(pos, st - 1)

    -- 找匹配的右括号
    local depth, k = 1, en + 1
    while k <= #s and depth > 0 do
      local ch = s:sub(k, k)
      if ch == "(" then depth = depth + 1
      elseif ch == ")" then depth = depth - 1 end
      k = k + 1
    end
    local inner = s:sub(en + 1, k - 2)

    -- 拆 "次数, 轨道列表"
    local countStr, tracks = inner:match("^%s*([^,]+)%s*,%s*(.-)%s*$")
    if not countStr then
      out[#out + 1] = inner      -- 解析不了，原样塞回去（后续会当单值处理）
    else
      countStr = util.trim(countStr):lower()
      local n
      if countStr == "auto-fill" or countStr == "auto-fit" then
        --[[ auto-fill：按可用宽度塞尽可能多的轨道。

             ⚠️ 需要知道单个轨道的宽度才能算份数。
                这里取轨道列表里的第一个固定值；取不到就退化成 1 份。 ]]--
        local first = tracks:match("^%s*([^%s]+)")
        local ln, lunit = first and first:match("^([%-%d%.]+)(%a*)$")
        local unitW = nil
        if ln and lunit == "px" then unitW = util.toNumber(ln) end
        if unitW and unitW > 0 and availW and availW > 0 then
          n = math.floor((availW + 0) / unitW)
          if n < 1 then n = 1 end
        else
          n = 1
        end
        autoFill = n
      else
        n = util.toNumber(countStr)
      end

      if n and n > 0 then
        -- ★ 上限保护：防止 repeat(99999, 1fr) 把内存撑爆
        if n > 200 then n = 200 end
        for _ = 1, n do
          out[#out + 1] = tracks
          out[#out + 1] = " "
        end
      end
    end
    pos = k
  end

  return table.concat(out), autoFill
end

--[[ 拆一个轨道模板串 -> 轨道定义列表

     每项：{ kind = "px"|"%"|"fr"|"auto", value = number|nil }
]]--
local function parseTracks(template, availW)
  if type(template) ~= "string" then return nil end
  local s = util.trim(template):lower()
  if s == "" or s == "none" then return nil end

  -- 展开 repeat()
  s = expandRepeat(s, availW)

  local tracks = {}
  for tok in s:gmatch("[^%s]+") do
    local kind, value, vunit

    if tok == "auto" then
      kind = "auto"
    else
      --[[ ⚠️ 单位匹配必须包含 '%' —— 只写 %a* 会让 "25%" 匹配失败，
            然后掉进 auto 分支（静默变成"按内容撑开"，列宽全错）。
            这与 calc tokenizer 踩的是同一个坑。 ]]--
      local n, unit = tok:match("^([%-%d%.]+)(%%?%a*)$")
      if n then
        n = util.toNumber(n)
        if unit == "fr" then
          kind, value = "fr", (n and n > 0) and n or 1
        elseif unit == "%" then
          kind, value = "%", n or 0
        elseif unit == "px" or unit == "" then
          kind, value = "px", n or 0
        elseif unit == "em" or unit == "rem" then
          -- em/rem 按库内默认字号 14px 近似（与 DEFAULTS 一致）
          kind, value = "px", (n or 0) * 14
        elseif unit == "vw" or unit == "vh" or unit == "vmin" or unit == "vmax" then
          kind, value, vunit = "viewport", n or 0, unit
        else
          kind, value = "auto"
        end
      else
        -- 未知 token（minmax / fit-content / 命名线等）-> auto
        kind = "auto"
      end
    end

    tracks[#tracks + 1] = { kind = kind, value = value, unit = vunit }
  end

  if #tracks == 0 then return nil end
  return tracks
end

--=============================================================================
-- 网格线定位解析
--=============================================================================

--[[ 解析 grid-column / grid-row 的值。

     "2"          -> { start=2, end=3 }
     "2 / 4"      -> { start=2, end=4 }
     "span 2"     -> { span=2 }
     "1 / span 2" -> { start=1, span=2 }
     "2 / -1"     -> 负值：从末尾数（由调用方补总数）

     返回 { start=, end=, span= } 或 nil（auto）
]]--
function G.parseLine(v)
  if type(v) ~= "string" then return nil end
  local s = util.trim(v):lower()
  if s == "" or s == "auto" then return nil end

  local a, b = s:match("^(.-)%s*/%s*(.-)$")
  if not a then
    a, b = s, nil
  end

  local out = {}
  local function readOne(tok)
    if not tok then return nil end
    tok = util.trim(tok)
    local sp = tok:match("^span%s+(%-?%d+)$")
    if sp then return { span = util.toNumber(sp) } end
    local n = tok:match("^(%-?%d+)$")
    if n then return { line = util.toNumber(n) } end
    return nil
  end

  local pa = readOne(a)
  if not pa then return nil end

  if pa.span then
    out.span = pa.span
  else
    out.start = pa.line
  end

  if b then
    local pb = readOne(b)
    if pb then
      if pb.span then
        out.span = pb.span
      else
        out.endLine = pb.line
      end
    end
  end

  -- 只给了 start：占 1 格
  if out.start and not out.span and not out.endLine then
    out.span = 1
  end

  return out
end

--=============================================================================
-- 轨道尺寸解析
--=============================================================================

--[[ 解析轨道尺寸。

     tracks:   parseTracks 的结果
     availW:   容器内容区尺寸（用于 % 与 fr 分配）
     gap:      轨道间距
     items:    放置结果，每项 { item=, col=, colSpan=, row=, rowSpan= }
     axis:     "col" 或 "row"
     measure:  function(item, trackSize) -> 该项在该轴上的固有尺寸

     返回 尺寸数组（长度 = 轨道数），以及总尺寸。

     算法（顺序很重要）：
       ① 固定轨道（px / %）先定
       ② auto 轨道按内容撑开
       ③ 剩余空间按 fr 权重分配
]]--
function G.resolveTracks(tracks, availW, gap, items, axis, measure, implicitCount)
  --[[ 补齐隐式轨道

       ⚠️ 两种情况都要补：
          · 显式放了超出模板范围的项（implicitCount）
          · 模板本身为空（grid-template-rows 没写）——
            原生会按需生成隐式轨道，这里按内容撑开。
         一开始漏了第二种，导致"没写 grid-template-rows 时所有项
         都堆在第 1 行、y 全是 0"。
  ]]--
  local list = {}
  for i = 1, #(tracks or {}) do list[i] = tracks[i] end

  -- 从放置结果推出"至少需要多少条轨道"
  local need = implicitCount or 0
  if items then
    for _, it in ipairs(items) do
      local a = (axis == "col") and it.col or it.row
      local sp = (axis == "col") and it.colSpan or it.rowSpan
      a = a or 1
      sp = sp or 1
      local e = a + sp - 1
      if e > need then need = e end
    end
  end

  for i = #list + 1, need do
    list[i] = { kind = "auto" }
  end

  local n = #list
  local sizes = {}
  local totalGap = (n > 1) and (gap * (n - 1)) or 0
  local inner = (availW or 0) - totalGap
  if inner < 0 then inner = 0 end

  -- ① 固定轨道
  local fixedTotal = 0
  local frTotal = 0
  local autoIdx = {}
  for i = 1, n do
    local t = list[i]
    if t.kind == "px" then
      sizes[i] = t.value or 0
      fixedTotal = fixedTotal + sizes[i]
    elseif t.kind == "%" then
      sizes[i] = inner * (t.value or 0) / 100
      fixedTotal = fixedTotal + sizes[i]
    elseif t.kind == "fr" then
      frTotal = frTotal + (t.value or 1)
      sizes[i] = 0
    else
      -- auto / viewport / 未知
      autoIdx[#autoIdx + 1] = i
      sizes[i] = 0
    end
  end

  -- viewport 轨道：按可用宽度近似（调用方一般已把 vw 换算好；
  -- 这里兜底成占满可用宽度，避免塌成 0）
  for i = 1, n do
    local t = list[i]
    if t.kind == "viewport" then
      sizes[i] = inner * (t.value or 0) / 100
      fixedTotal = fixedTotal + sizes[i]
      -- 从 autoIdx 里移除
      for k = #autoIdx, 1, -1 do
        if autoIdx[k] == i then table.remove(autoIdx, k) end
      end
    end
  end

  -- ② auto 轨道：按内容固有尺寸
  if #autoIdx > 0 then
    for _, i in ipairs(autoIdx) do
      local maxSize = 0
      for _, it in ipairs(items) do
        local a = (axis == "col") and it.col or it.row
        local sp = (axis == "col") and it.colSpan or it.rowSpan
        a = a or 1
        sp = sp or 1
        -- 跨多个轨道的项：把固有尺寸摊到它跨的轨道上
        if a <= i and (a + sp - 1) >= i then
          local m = measure(it.item, sizes[i] or 0) or 0
          local per = m / sp
          if per > maxSize then maxSize = per end
        end
      end
      sizes[i] = maxSize
      fixedTotal = fixedTotal + maxSize
    end
  end

  -- ③ 剩余空间按 fr 分配
  local free = inner - fixedTotal
  if frTotal > 0 then
    if free < 0 then free = 0 end
    for i = 1, n do
      if list[i].kind == "fr" then
        sizes[i] = free * (list[i].value or 1) / frTotal
      end
    end
  elseif free > 0 and #autoIdx > 0 and #autoIdx == n then
    --[[ ★ 没有 fr、且【全部】是 auto 轨道时，剩余空间均分给它们

         原生语义：grid-template-columns:auto 的容器，
         单条 auto 轨道会撑满容器宽度（不是贴着内容宽）。
         实测踩过：无模板时列宽算成 8px，卡片全挤成一条。

         ⚠️ 只在"全是 auto"时均分 —— 有固定轨道时，
            剩余空间按原生应留给 auto 轨道吸收，但多轨道混合的
            分配规则较复杂，这里保守处理（不擅自拉伸固定轨道）。 ]]--
    local per = free / #autoIdx
    for _, i in ipairs(autoIdx) do
      sizes[i] = (sizes[i] or 0) + per
    end
  end

  local total = totalGap
  for i = 1, n do total = total + (sizes[i] or 0) end

  return sizes, total, list
end

--=============================================================================
-- 自动放置
--=============================================================================

--[[ 把网格项放到格子里。

     flowItems: 按文档顺序的网格项（已排除 absolute）
     cols:      列数（模板列数；用于自动换行）
     flow:      "row" | "column"

     返回 placed 列表：{ item=, col=, colSpan=, row=, rowSpan= }
           以及实际用到的列数 / 行数

     ★ 采用简化的 auto-placement：
         · 有显式定位的项先占位
         · 其余项按顺序找"第一个能放下的空位"
       这与原生在有显式项时的行为基本一致（原生还有 packing 规则，
       本库不做稀疏/稠密区分，一律按稠密放置）。
]]--
function G.place(flowItems, cols, flow)
  local placed = {}
  local occupied = {}       -- [row][col] = true

  local function isFree(r, c, rs, cs)
    for rr = r, r + rs - 1 do
      for cc = c, c + cs - 1 do
        if cc < 1 or rr < 1 then return false end
        local row = occupied[rr]
        if row and row[cc] then return false end
      end
    end
    return true
  end

  local function occupy(r, c, rs, cs)
    for rr = r, r + rs - 1 do
      local row = occupied[rr]
      if not row then row = {}; occupied[rr] = row end
      for cc = c, c + cs - 1 do row[cc] = true end
    end
  end

  -- ---- ① 显式定位的项 ----
  local auto1 = {}
  for i = 1, #flowItems do
    local c = flowItems[i]
    local cst = c.style or {}
    local gc = G.parseLine(cst["grid-column"] or cst["grid-column-start"])
    local gr = G.parseLine(cst["grid-row"] or cst["grid-row-start"])

    if gc or gr then
      local cs = (gc and (gc.span or (gc.endLine and (gc.endLine - (gc.start or 1)) or 1))) or 1
      local rs = (gr and (gr.span or (gr.endLine and (gr.endLine - (gr.start or 1)) or 1))) or 1
      if cs < 1 then cs = 1 end
      if rs < 1 then rs = 1 end
      local col = (gc and gc.start) or 1
      local row = (gr and gr.start) or 1
      if col < 1 then col = 1 end
      if row < 1 then row = 1 end

      placed[#placed + 1] = { item = c, col = col, colSpan = cs,
                              row = row, rowSpan = rs, explicit = true }
      occupy(row, col, rs, cs)
    else
      auto1[#auto1 + 1] = c
    end
  end

  -- ---- ② 自动放置剩余项 ----

  --[[ 按 auto-flow 扫描空位。

       ★ 统一用"扫描坐标"而不是维护光标 ——
         原来分开写了 row/column 两套，column 那套有 bug 且很绕。
         这里对两个方向都用同一套：顺序遍历"主序"坐标，
         找到第一个能放下的空格。

       flow == "row"    ：主序是 行 -> 列（一行填满再下一行）
       flow == "column" ：主序是 列 -> 行 ]]--
  local function nextCell(r, c, cols)
    if flow == "column" then
      -- 列优先：先往下走，到底了换下一列
      return r + 1, c
    end
    -- 行优先：先往右走，到头了换下一行
    c = c + 1
    if cols > 0 and c > cols then c = 1; r = r + 1 end
    return r, c
  end

  local guardMax = 20000

  for _, c in ipairs(auto1) do
    local r, cc = 1, 1
    local guard = 0
    local ok = false

    while guard < guardMax do
      guard = guard + 1

      if isFree(r, cc, 1, 1) then
        ok = true
        break
      end

      r, cc = nextCell(r, cc, cols)
      if flow == "column" and cols > 0 and cc > cols then
        cc = 1
      end
    end

    placed[#placed + 1] = { item = c, col = cc, colSpan = 1,
                            row = r, rowSpan = 1 }
    occupy(r, cc, 1, 1)
  end

  -- 统计实际用到的行列数
  local maxCol, maxRow = cols or 0, 0
  for _, p in ipairs(placed) do
    local e = p.col + p.colSpan - 1
    if e > maxCol then maxCol = e end
    local er = p.row + p.rowSpan - 1
    if er > maxRow then maxRow = er end
  end
  if maxCol < 1 then maxCol = 1 end
  if maxRow < 1 then maxRow = 1 end

  return placed, maxCol, maxRow
end

--=============================================================================
-- 对外入口
--=============================================================================

--[[ 解析 grid 相关的样式。

     返回 { cols=轨道列表, rows=轨道列表, colGap=, rowGap=, flow= }
     或 nil（不是 grid）
]]--
function G.parseStyle(st, availW)
  if not st or (st.display ~= "grid" and st.display ~= "inline-grid") then
    return nil
  end

  local cols = parseTracks(st["grid-template-columns"], availW)
  local rows = parseTracks(st["grid-template-rows"], availW)

  -- gap 解析：gap / row-gap / column-gap
  local function num(v) return util.toNumber(v) end
  local g = st.gap or "0"
  local gapAll
  do
    local a, b = tostring(g):match("^%s*([%-%d%.]+%a*)%s+([%-%d%.]+%a*)%s*$")
    gapAll = a and { a, b } or { tostring(g) }
  end
  local function toPx(v, fallback)
    if not v then return fallback end
    local n, unit = tostring(v):match("^%s*([%-%d%.]+)(%a*)%s*$")
    n = util.toNumber(n)
    if not n then return fallback end
    if unit == "%" then return fallback end    -- 百分比 gap 少见，忽略
    return n
  end

  --[[ ★ gap 简写的优先级（原生规则）

       gap: 10px           -> row/column 都是 10
       gap: 10px 20px      -> row-gap 10, column-gap 20

       ⚠️ row-gap / column-gap 在 DEFAULTS 里是 "0"，
          不是 nil —— 所以【不能】用 `if not rowGap then ... end`
          来判断"没写"。必须先看它是否非零。
          踩过：这样写导致 gap:10px 完全不生效，列宽算成 205（应 200）。 ]]--
  local rgRaw = st["row-gap"]
  local cgRaw = st["column-gap"]

  local function isUnset(v)
    if v == nil then return true end
    local n = util.toNumber(tostring(v):match("^%s*([%-%d%.]+)") )
    return (n == nil) or (n == 0)
  end

  local rowGap = toPx(rgRaw, nil)
  local colGap = toPx(cgRaw, nil)
  if isUnset(rgRaw) or rowGap == 0 then rowGap = toPx(gapAll[1], 0) end
  if isUnset(cgRaw) or colGap == 0 then colGap = toPx(gapAll[2] or gapAll[1], 0) end

  return {
    cols = cols,
    rows = rows,
    colGap = colGap or 0,
    rowGap = rowGap or 0,
    flow = st["grid-auto-flow"] or "row",
    justifyItems = st["justify-items"] or "stretch",
    alignItems = st["align-items"] or "stretch",
  }
end

G.parseTracks = parseTracks
G.expandRepeat = expandRepeat

return G