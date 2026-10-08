--[[ 忠实还原真机的 Enum 形态（供测试与 mock 使用）。

   ★★★ 为什么需要这个文件（R23，2026-10-09 真机实测）

     真机上水平对齐枚举的真名是【带点的子表形式】：

         Enum.TextHorizontalAlignment        -> "TextHorizontalAlignment"（子表）
         Enum.TextHorizontalAlignment.Middle -> "Enum.TextHorizontalAlignment.Middle"
         Enum.TextHorizontalAlignment.Left   -> "Enum.TextHorizontalAlignment.Left"
         Enum.TextHorizontalAlignment.Right  -> "Enum.TextHorizontalAlignment.Right"

     而【文档】写的是扁平形式 Enum.TextHorizontalAlignmentMiddle ——
     真机上它是 **nil**。

     ⚠️⚠️ 后果：库原先写
            control.horizontalAlignment = Enum.TextHorizontalAlignmentMiddle
        会抛错，而那次写入被 pcall 包着 -> **失败被静默吞掉**，
        字段停在默认 Left。症状是"文字永远贴框左边"，
        从 R21 起一直没被发现。

     ★ 为什么测试没拦住：
       各测试文件自己手写 Enum 表，且写的是【文档的扁平形式】，
       于是 mock 世界里扁平名可用、库"测试全绿"，
       真机却全错。这正是 §七「测试替身必须忠实」的重演 ——
       mock 必须照【真机实测】的形态建模，不能照文档。

   ★ 用法：
       local enumkit = require('enum_kit')
       Enum = enumkit.build()

     需要额外枚举时，传进来合并：
       Enum = enumkit.build({ KeyEventType = ..., ImageSource = ... })
]]

local K = {}

--[[ 水平对齐：真机形态（子表 + 带点字符串值），扁平名【故意不提供】。

     ⚠️ 不要为了让测试好过而补上扁平名 ——
        那样就又把真机的坑盖回去了。 ]]--
function K.textHorizontalAlignment()
  local sub = {
    Left   = "Enum.TextHorizontalAlignment.Left",
    Middle = "Enum.TextHorizontalAlignment.Middle",
    Right  = "Enum.TextHorizontalAlignment.Right",
  }
  -- 子表自身有个名字（真机读回 "TextHorizontalAlignment"）
  return setmetatable(sub, {
    __tostring = function() return "TextHorizontalAlignment" end,
  })
end

--[[ 构造一个"像真机那样"的 Enum。
     extra 里的键会被合并进去（用于各测试自带的枚举）。 ]]--
function K.build(extra)
  --[[ ★ 用"空壳 + 后备表"来还原真机形态。

       ⚠️ 不能写 `__index = e`（指向自己）—— Lua 会报
          "__index chain too long; possible loop"。
          真机是宿主对象，在 C 层处理索引，不存在这个问题；
          这里用 back 表模拟同样的"能索引、但 pairs 不到"效果。 ]]--
  local back = {
    TextHorizontalAlignment = K.textHorizontalAlignment(),
  }
  if extra then
    for k, v in pairs(extra) do back[k] = v end
  end

  local shell = {}
  return setmetatable(shell, {
    __index = back,
    -- ★ 真机 pairs(Enum) = 0 项（R16 实测）—— 还原"顶层不可遍历"
    __pairs = function() return function() return nil end end,
  })
end

--[[ 便捷：在测试里断言"库真的把居中对齐写进去了"。

     返回 ok, 说明 —— ok 表示控件的 horizontalAlignment 是 Middle。 ]]--
function K.assertCentered(control)
  local v = control and control.horizontalAlignment
  if v == nil then
    return false, "字段读回 nil（控件可能不支持该字段）"
  end
  local s = tostring(v)
  if s:find("Middle", 1, true) then return true, s end
  return false, "读回 " .. s .. "（不是 Middle）"
end

return K