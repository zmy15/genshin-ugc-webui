--[[============================================================================
  webui/layout.lua  ——  盒模型布局计算

  坐标约定（内部统一用 HTML 习惯）：
    - 原点在【左上角】，X 向右，Y 向下
    - 渲染层负责翻转成千星的【左下原点、Y 向上】

  布局模型：
    - block：垂直堆叠，宽度默认填满父
    - inline：行内（简化：当作 block 处理，但宽度收缩到内容）
    - inline-block：宽度收缩到内容
    - none：不参与布局
    - flex：单行主轴排列（row / column）

  position：
    static / relative：参与正常流
    absolute / fixed：脱离流，相对父 padding box 定位

  输出：node.box = {
    x, y, w, h,            -- 相对画布左上角的内容盒位置
    contentX, contentY,    -- 内容区起点（去掉 padding）
    contentW, contentH,
    contentBoxW, contentBoxH,
  }
==============================================================================]]

local style = require('webui_style')
local util  = require('webui_util')
local dom   = require('webui_dom')

local L = {}

--=============================================================================
-- 辅助
--=============================================================================

local function len(str, base, fontSize)
  local l = style.parseLength(str)
  if l.auto then return nil, "auto" end
  if l.none then return nil, "none" end
  if l.unit == "%" then return base and (base * l.n / 100) or nil, "%" end
  if l.unit == "em" then return l.n * (fontSize or 14), "em" end
  return l.n, "px"
end

--[[ 取四个方向的边距 ]]--
local function boxEdges(st, base, attr)
  local out = {}
  for _, side in ipairs{"top", "right", "bottom", "left"} do
    local k = attr .. "-" .. side
    local v = len(st[k], base, st._fontSize)
    out[side] = v or 0
  end
  return out
end

--=============================================================================
-- 内容固有尺寸测量（文本 / 收缩宽度）
--=============================================================================

--[[ 递归估算节点的"收缩到内容"宽度（shrink-to-fit）]]--
--[[ 元素自身的固有宽度（★ 不含 margin）

     ⚠️ 2026-10-07 修正：原来这里把 margin 也算进了 extraW，
        但本函数的语义是"元素自身宽度"，margin 是【外部间距】，
        不该算进来。而且调用方（flex）还会自己加一次 margin，
        导致宽度被多算一个 margin 的量。

     真机表现：
        .avatar { width:130px; margin-right:20px }
          -> 布局宽度算成 150
          -> 子元素 .avatar-inner 只有 130
          -> 父右侧露出 20px（控件默认白底）-> 屏幕上一条白色竖条

     现在 extraW 只含 padding，margin 由调用方处理。
]]--
local function intrinsicWidth(node, availW, availH)
  if node:isText() then
    local st = node.style or {}
    return util.measureText(node.text or "", st._fontSize or 14)
  end
  if not node:isElement() then
    -- root
    local mw = 0
    for i = 1, #node.children do
      local w = intrinsicWidth(node.children[i], availW, availH)
      if w > mw then mw = w end
    end
    return mw
  end

  local st = node.style
  if not st or st.display == "none" then return 0 end

  local pad = boxEdges(st, availW, "padding")
  local extraW = pad.left + pad.right       -- ★ 不含 margin

  -- 显式宽度优先
  local w, mode = len(st.width, availW, st._fontSize)
  if w and mode ~= "auto" and mode ~= "none" then
    return w + extraW
  end

  -- 子节点横向排布
  local st_display = st.display
  if st_display == "flex" and st["flex-direction"] ~= "column" then
    local total = 0
    for i = 1, #node.children do
      total = total + intrinsicWidth(node.children[i], availW, availH)
    end
    local gap = len(st.gap, availW, st._fontSize) or 0
    if #node.children > 1 then total = total + gap * (#node.children - 1) end
    return total + extraW
  end

  -- block：取子节点最大值
  local mw = 0
  for i = 1, #node.children do
    local cw = intrinsicWidth(node.children[i], availW, availH)
    if cw > mw then mw = cw end
  end
  return mw + extraW
end

--[[ 递归估算高度（用于 height:auto）]]--
local function intrinsicHeight(node, w, availH)
  if node:isText() then
    local st = node.style or {}
    local fs = st._fontSize or 14
    local lh = st._lineHeight or (fs * 1.2)
    -- 按可用宽度算行数
    local text = node.text or ""
    if text == "" then return 0 end
    local textW = util.measureText(text, fs)
    local lines = 1
    if w and w > 1 and textW > w then
      lines = math.ceil(textW / w)
    end
    return lines * lh
  end

  if not node:isElement() then
    local total = 0
    for i = 1, #node.children do
      total = total + intrinsicHeight(node.children[i], w, availH)
    end
    return total
  end

  local st = node.style
  if not st or st.display == "none" then return 0 end

  local pad = boxEdges(st, w, "padding")
  local mar = boxEdges(st, w, "margin")
  local extraH = pad.top + pad.bottom + mar.top + mar.bottom

  local h, mode = len(st.height, availH, st._fontSize)
  if h and mode ~= "auto" and mode ~= "none" then
    return h + extraH
  end

  local innerW = (w or 0) - pad.left - pad.right
  if innerW < 1 then innerW = w or 0 end

  local total = 0
  if st.display == "flex" and st["flex-direction"] == "column" then
    for i = 1, #node.children do
      total = total + intrinsicHeight(node.children[i], innerW, availH)
    end
    local gap = len(st.gap, w, st._fontSize) or 0
    if #node.children > 1 then total = total + gap * (#node.children - 1) end
  else
    for i = 1, #node.children do
      total = total + intrinsicHeight(node.children[i], innerW, availH)
    end
  end
  return total + pad.top + pad.bottom + mar.top + mar.bottom
end

--=============================================================================
-- 主布局
--=============================================================================

--[[ 对一个盒子布局：parentX/Y 是父的【内容区】左上角

     widthOverride: 由 flex 布局算出的宽度。传入时忽略 st.width，
                    否则 flex-grow / flex-shrink 的结果会被丢弃。
]]--
local function layoutNode(node, parentContentX, parentContentY, parentContentW, parentContentH, canvasW, canvasH, widthOverride)
  if node:isText() then
    -- 文本节点：占据父给的位置，高度按自身算
    local st = node.style or {}
    local fs = st._fontSize or 14
    local lh = st._lineHeight or (fs * 1.2)
    local text = node.text or ""
    local textW = util.measureText(text, fs)
    local lines = 1
    if parentContentW and parentContentW > 1 and textW > parentContentW then
      lines = math.ceil(textW / parentContentW)
    end
    node.box = {
      x = parentContentX, y = parentContentY,
      w = parentContentW, h = lines * lh,
      contentX = parentContentX, contentY = parentContentY,
      contentW = parentContentW, contentH = lines * lh,
      isText = true,
    }
    return node.box
  end

  local st = node.style
  if not st then
    -- 没有样式（不该发生），给个空盒
    node.box = { x = parentContentX, y = parentContentY, w = 0, h = 0,
                 contentX = parentContentX, contentY = parentContentY,
                 contentW = 0, contentH = 0 }
    return node.box
  end

  if st.display == "none" or st.visibility == "hidden" and false then
    node.box = { x = parentContentX, y = parentContentY, w = 0, h = 0,
                 contentX = parentContentX, contentY = parentContentY,
                 contentW = 0, contentH = 0, hidden = true }
    return node.box
  end

  local fs = st._fontSize or 14

  -- ---- 解析宽高 ----
  local pos = st.position or "static"
  local isAbs = (pos == "absolute" or pos == "fixed")

  -- 可用基准：绝对定位相对父 padding box；普通流相对父内容区
  local baseW = parentContentW
  local baseH = parentContentH
  if isAbs then
    -- 用父的 padding box（近似：内容区 + 父 padding 已被上层扣除，这里直接用 parentContent）
    baseW = parentContentW
    baseH = parentContentH
  end

  -- 宽度
  -- 宽度（flex 传入的 widthOverride 优先）
  local w, wmode = len(st.width, baseW, fs)
  if widthOverride then
    w = widthOverride
    wmode = "px"
  elseif wmode == "auto" or w == nil then
    if isAbs then
      -- 绝对定位 + auto：收缩到内容
      w = intrinsicWidth(node, baseW, baseH)
    elseif st.display == "inline-block" or st.display == "inline" then
      w = intrinsicWidth(node, baseW, baseH)
      if baseW and w > baseW then w = baseW end
    else
      w = baseW or 0          -- block：填满
    end
  end
  -- min/max
  local minW = len(st["min-width"], baseW, fs)
  local maxW = len(st["max-width"], baseW, fs)
  if minW and w < minW then w = minW end
  if maxW and w > maxW then w = maxW end

  -- 高度
  local h, hmode = len(st.height, baseH, fs)
  local autoH = (hmode == "auto" or h == nil)

  -- ---- 边距 / 内边距 ----
  local mar = boxEdges(st, baseW, "margin")
  local pad = boxEdges(st, baseW, "padding")

  -- ---- 定位原点 ----
  local x, y
  if isAbs then
    -- 相对父 padding box：left/right/top/bottom
    local l, _ = len(st.left, baseW, fs)
    local r, _ = len(st.right, baseW, fs)
    local t, _ = len(st.top, baseH, fs)
    local b, _ = len(st.bottom, baseH, fs)

    if l then x = parentContentX + l
    elseif r then x = parentContentX + (baseW or 0) - r - w
    else x = parentContentX end

    if b then
      -- 注意：内部坐标是 Y 向下，CSS 的 bottom 是距底部
      y = parentContentY + (baseH or 0) - b - (h or 0)
    elseif t then
      y = parentContentY + t
    else
      y = parentContentY
    end
  else
    -- 正常流：由父的排布决定，这里先给占位，父会覆盖
    x = parentContentX + mar.left
    y = parentContentY + mar.top
  end

  -- relative：在正常流基础上偏移
  if pos == "relative" then
    local l = len(st.left, baseW, fs)
    local t = len(st.top, baseH, fs)
    if l then x = x + l end
    if t then y = y + t end
  end

  -- 先创建 box（高度可能待定）
  local box = {
    x = x, y = y, w = w, h = h or 0,
    margin = mar, padding = pad,
    isAbs = isAbs,
    autoH = autoH,
  }
  node.box = box

  -- ---- 内容区 ----
  local cw = w - pad.left - pad.right
  if cw < 0 then cw = 0 end
  local contentX = x + pad.left
  local contentY = y + pad.top

  -- ---- 子节点布局 ----
  local children = {}
  for i = 1, #node.children do
    local c = node.children[i]
    -- 跳过 display:none
    local show = true
    if c:isElement() and c.style and c.style.display == "none" then show = false end
    if show then children[#children + 1] = c end
  end

  -- 可用高度传给子节点：如果自身高度 auto，先给一个估计
  local childBaseH = box.h
  if autoH or childBaseH <= 0 then
    childBaseH = (parentContentH or 0) - y + parentContentY
    if childBaseH < 0 then childBaseH = 0 end
  end

  local flowChildren = {}
  local absChildren = {}
  for i = 1, #children do
    local c = children[i]
    local cst = c.style
    if cst and (cst.position == "absolute" or cst.position == "fixed") then
      absChildren[#absChildren + 1] = c
    else
      flowChildren[#flowChildren + 1] = c
    end
  end

  local usedH = 0

  if st.display == "flex" then
    -- ---- flex 布局（简化：单行） ----
    local dir = st["flex-direction"] or "row"
    local justify = st["justify-content"] or "flex-start"
    local alignItems = st["align-items"] or "stretch"
    local gap = len(st.gap, cw, fs) or 0

    if dir == "column" then
      local cy = contentY

      --[[ ★ flex column 的交叉轴对齐（2026-10-07 修）

           bug：这里原来无条件把子项宽度设为父容器宽度（cw2 = cw），
                导致子项 CSS 里显式写的 width 【被完全忽略】。

           真机表现（很隐蔽）：
             #root { display:flex; flex-direction:column }
               .avatar { width:130px }   -> 实际被算成 980px（父宽）
               于是 border-radius:50% 按 980:130 适配
               -> 圆形被横向拉成"扁椭圆"
               同理 overflow:hidden 的卡片变宽 -> 子元素不再溢出 -> 裁剪看不出效果

           正确语义：
             align-items: stretch 时，只有【未显式指定宽度】的子项才拉伸；
             指定了 width 的子项应保持自身宽度，并按 align-items 决定水平位置。
      ]]--
      for i = 1, #flowChildren do
        local c = flowChildren[i]
        local cst = c.style or {}
        local cmar = boxEdges(cst, cw, "margin")
        local ch = intrinsicHeight(c, cw, childBaseH)

        -- 子项是否显式指定了宽度
        local expW, expMode = len(cst.width, cw, cst._fontSize or 14)
        local hasExplicitW = expW and expMode ~= "auto" and expMode ~= "none"

        local cw2
        local cx2 = contentX + cmar.left

        if hasExplicitW then
          -- 显式宽度：保持自身宽度，按 align-items 水平定位
          cw2 = expW
          local availW = cw - cmar.left - cmar.right
          local free = availW - cw2
          local align = alignItems
          if align == "center" then
            cx2 = contentX + cmar.left + free / 2
          elseif align == "flex-end" then
            cx2 = contentX + cmar.left + free
          end
          -- flex-start / stretch 都靠左
        else
          -- 未指定：stretch 填满；否则收缩到内容宽
          if alignItems == "stretch" then
            cw2 = cw - cmar.left - cmar.right
          else
            cw2 = intrinsicWidth(c, cw, childBaseH)
            local availW = cw - cmar.left - cmar.right
            local free = availW - cw2
            if alignItems == "center" then
              cx2 = contentX + cmar.left + free / 2
            elseif alignItems == "flex-end" then
              cx2 = contentX + cmar.left + free
            end
          end
        end

        layoutNode(c, cx2, cy + cmar.top, cw2, childBaseH,
                   canvasW, canvasH, cw2)
        cy = cy + ch + gap
      end
      usedH = cy - contentY - (gap > 0 and gap or 0)
    else
      -- row（支持 flex-wrap: wrap）
      local wrap = (st["flex-wrap"] == "wrap" or st["flex-wrap"] == "wrap-reverse")

      local widths = {}
      for i = 1, #flowChildren do
        local c = flowChildren[i]
        local cst = c.style or {}
        local cmar = boxEdges(cst, cw, "margin")

        --[[ ★ 行内占位宽度 = 元素自身宽度 + 左右 margin

             intrinsicWidth() 【不含 margin】（已修正），
             所以这里加一次 margin 得到行内占位，是正确的。
        ]]--
        local cwid = intrinsicWidth(c, cw, childBaseH)
        local outerW = cwid + cmar.left + cmar.right   -- 行内占位

        -- flex 基础尺寸：flex-basis > width > 内容宽
        local basis = nil
        local fb = cst["flex-basis"]
        if fb and fb ~= "auto" and fb ~= "none" then
          local b = len(fb, cw, cst._fontSize)
          if b then basis = b end
        end

        widths[i] = {
          w = outerW,        -- 行内占位（含 margin）
          inner = cwid,      -- 元素自身内容宽（不含 margin）
          basis = basis,
          mar = cmar,
          grow = tonumber(cst["flex-grow"]) or 0,
          shrink = tonumber(cst["flex-shrink"]) or 1,
        }
      end

      -- ---- 分行（flex-wrap）----
      local lines = {}
      if wrap then
        local cur = { items = {}, width = 0 }
        for i = 1, #flowChildren do
          local wI = widths[i].basis or widths[i].w
          local add = wI + (#cur.items > 0 and gap or 0)
          if #cur.items > 0 and cur.width + add > cw then
            lines[#lines + 1] = cur
            cur = { items = {}, width = 0 }
            add = wI
          end
          cur.items[#cur.items + 1] = i
          cur.width = cur.width + add
        end
        if #cur.items > 0 then lines[#lines + 1] = cur end
      else
        local all = { items = {}, width = 0 }
        for i = 1, #flowChildren do
          all.items[#all.items + 1] = i
          all.width = all.width + (widths[i].basis or widths[i].w)
        end
        if #all.items > 1 then all.width = all.width + gap * (#all.items - 1) end
        lines[1] = all
      end

      -- ---- 逐行布局 ----
      local lineY = contentY
      local totalH = 0

      for li = 1, #lines do
        local line = lines[li]
        local items = line.items
        local n = #items

        -- 本行的 grow / shrink 计算
        local lineW = 0
        for _, idx in ipairs(items) do
          lineW = lineW + (widths[idx].basis or widths[idx].w)
        end
        if n > 1 then lineW = lineW + gap * (n - 1) end

        local free = cw - lineW
        if free > 0 then
          local totalGrow = 0
          for _, idx in ipairs(items) do totalGrow = totalGrow + widths[idx].grow end
          if totalGrow > 0 then
            for _, idx in ipairs(items) do
              local info = widths[idx]
              if info.grow > 0 then
                info.w = (info.basis or info.w) + free * info.grow / totalGrow
              elseif info.basis then
                info.w = info.basis
              end
            end
          else
            for _, idx in ipairs(items) do
              if widths[idx].basis then widths[idx].w = widths[idx].basis end
            end
          end
        elseif free < 0 then
          local totalShrink = 0
          for _, idx in ipairs(items) do
            local info = widths[idx]
            totalShrink = totalShrink + info.shrink * (info.basis or info.w)
          end
          if totalShrink > 0 then
            for _, idx in ipairs(items) do
              local info = widths[idx]
              local base = info.basis or info.w
              local cut = (-free) * (info.shrink * base) / totalShrink
              local nw = base - cut
              if nw < 0 then nw = 0 end
              info.w = nw
            end
            lineW = 0
            for _, idx in ipairs(items) do lineW = lineW + widths[idx].w end
            if n > 1 then lineW = lineW + gap * (n - 1) end
          end
        else
          for _, idx in ipairs(items) do
            if widths[idx].basis then widths[idx].w = widths[idx].basis end
          end
        end

        -- justify（每行独立）
        local free2 = cw - lineW
        local startX = contentX
        local useGap = gap
        if justify == "center" then startX = contentX + free2 / 2
        elseif justify == "flex-end" then startX = contentX + free2
        elseif justify == "space-between" and n > 1 then
          useGap = gap + free2 / (n - 1)
        end

        -- 本行高度
        local maxH = 0
        local cx = startX
        local lineItems = {}
        for _, idx in ipairs(items) do
          local c = flowChildren[idx]
          local info = widths[idx]
          local cwid = info.w - info.mar.left - info.mar.right
          if cwid < 0 then cwid = 0 end
          local ch = intrinsicHeight(c, cwid, childBaseH)
          if ch + info.mar.top + info.mar.bottom > maxH then
            maxH = ch + info.mar.top + info.mar.bottom
          end
          lineItems[#lineItems + 1] = { c = c, info = info, cwid = cwid, ch = ch, x = cx }
          cx = cx + info.w + useGap
        end

        -- 真实布局（等本行 maxH 算完后才能做 align-items）
        for _, it in ipairs(lineItems) do
          local cy = lineY + it.info.mar.top
          if alignItems == "center" then
            cy = lineY + (maxH - it.ch) / 2
          elseif alignItems == "flex-end" then
            cy = lineY + maxH - it.ch - it.info.mar.bottom
          end
          layoutNode(it.c, it.x + it.info.mar.left, cy, it.cwid,
                     childBaseH, canvasW, canvasH, it.cwid)
        end

        lineY = lineY + maxH
        totalH = totalH + maxH
      end

      usedH = totalH
    end

  else
    -- ---- 普通 block 流 ----
    local cy = contentY
    local prevMarginBottom = 0

    for i = 1, #flowChildren do
      local c = flowChildren[i]
      local cst = c.style or {}
      local cmar = boxEdges(cst, cw, "margin")

      -- 外边距折叠（简化：相邻取较大者）
      local collapse = 0
      if i > 1 then
        collapse = math.max(prevMarginBottom, cmar.top) - cmar.top
        cy = cy + collapse
      end

      local childBaseW = cw - cmar.left - cmar.right
      if childBaseW < 0 then childBaseW = 0 end

      local cb = layoutNode(c, contentX + cmar.left, cy + cmar.top,
                            childBaseW, childBaseH, canvasW, canvasH)

      local ch = cb.h + cmar.top + cmar.bottom
      cy = cy + ch
      prevMarginBottom = cmar.bottom
    end

    usedH = cy - contentY
    if #flowChildren == 0 then usedH = 0 end
  end

  -- 绝对定位子节点
  for i = 1, #absChildren do
    local c = absChildren[i]
    local cst = c.style or {}
    layoutNode(c, contentX, contentY, cw, box.h, canvasW, canvasH)
  end

  -- ---- 高度定案 ----
  if autoH then
    box.h = usedH + pad.top + pad.bottom
    local minH = len(st["min-height"], baseH, fs)
    local maxH2 = len(st["max-height"], baseH, fs)
    if minH and box.h < minH then box.h = minH end
    if maxH2 and box.h > maxH2 then box.h = maxH2 end
  end

  box.contentX = contentX
  box.contentY = contentY
  box.contentW = cw
  box.contentH = box.h - pad.top - pad.bottom
  if box.contentH < 0 then box.contentH = 0 end

  return box
end

--[[ 计算整棵树的布局 ]]--
function L.compute(root, canvasW, canvasH)
  canvasW = canvasW or 1600
  canvasH = canvasH or 900

  -- 从 root 的每个子节点开始（root 自身当作画布）
  local cy = 0
  for i = 1, #root.children do
    local c = root.children[i]
    if c:isElement() and c.style and c.style.display == "none" then
      c.box = { x = 0, y = 0, w = 0, h = 0, hidden = true,
                contentX = 0, contentY = 0, contentW = 0, contentH = 0 }
    else
      layoutNode(c, 0, cy, canvasW, canvasH, canvasW, canvasH)
      if c.box and not c.box.isAbs then
        cy = cy + c.box.h
      end
    end
  end

  return root
end

--=============================================================================
-- 调试
--=============================================================================

function L.dump(root, maxDepth)
  maxDepth = maxDepth or 20
  local lines = {}
  dom.walk(root, function(n, d)
    if d > maxDepth or not n.box then return end
    local b = n.box
    local pad = string.rep("  ", d)
    local label = n:isText() and ('"' .. (n.text or ""):sub(1, 12) .. '"') or ("<" .. (n.tag or "?") .. ">")
    lines[#lines + 1] = string.format("%s%-14s x=%.1f y=%.1f w=%.1f h=%.1f",
        pad, label, b.x, b.y, b.w, b.h)
  end)
  return table.concat(lines, "\n")
end

L.intrinsicWidth = intrinsicWidth
L.intrinsicHeight = intrinsicHeight

return L
