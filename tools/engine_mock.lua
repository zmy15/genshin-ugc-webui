--[[ 真机仿真 mock

     ★ 严格模拟真机的三个限制（均经真机探针确认）：

       1. 只有引擎预定义字段可写，【自定义字段一律静默写失败】
          探针证据（probe_field.lua）：
            __webuiParent 写=false 读=true 值=nil
            myCustomFlag  写=false 读=true 值=nil
            bgColor       写=true  读=true 值=...   ← 预定义字段正常

       2. 字段按控件类型封死
          容器/按钮没有 bgColor/text/fontColor

       3. 无 reparent API，控件固定在创建时的父下
          但 GetChildren() 可用，能反查真实父子关系

     ⚠️ 之前的 mock 用普通 table，自定义字段随便写，
        所以完全测不出「库依赖自定义字段」这个致命 bug。
        这个 mock 就是为了在本地拦住这类问题。
]]--

local EngineMock = {}

--[[ 创建一套仿真环境。
     返回 { game=..., controls={...}, created=..., dataOf=fn }
]]--
function EngineMock.new(prefabs)
  local created = 0
  local controls = {}
  local dataMap = {}      -- proxy -> 内部数据
  local externalRoots = {}  -- ★ 模拟"编辑器里搭好的"根控件

  local COMMON = {
    anchorMinX=1, anchorMinY=1, anchorMaxX=1, anchorMaxY=1,
    pivotX=1, pivotY=1,
    anchoredPositionX=1, anchoredPositionY=1,
    sizeDeltaX=1, sizeDeltaY=1,
    visible=1, active=1, name=1,
    localScaleX=1, localScaleY=1, localRotationZ=1,
    localRotationX=1, localRotationY=1,
    canControllerFocus=1,
  }
  local PER_KIND = {
    textbox   = { bgColor=1, text=1, fontColor=1, fontSize=1,
                  horizontalAlignment=1, verticalAlignment=1,
                  outlineColor=1, lineSpacing=1 },
    container = { },
    button    = { interactable=1, raycastTarget=1, clickAudioId=1 },
    area      = { raycastTarget=1 },
    --[[ ★ 图片控件（R16 真机实测补全）

         ⚠️ 关键：image 类型【没有】bgColor / text ——
            这正是"字段按类型封死"的体现。
             写 bgColor 会静默失败（真机行为）。
         有 imageColor / enableMask 等字段。
    ]]--
    image     = { imageColor=1, imageType=1, enableMask=1,
                  reverseMaskArea=1, enableSoftEdge=1, softEdgeMode=1,
                  softEdgeWidthX=1, softEdgeWidthY=1,
                  horizontalSoftRange=1, verticalSoftRange=1,
                  fillType=1, fillHorizontalType=1, fillVerticalType=1,
                  fillRadial90Type=1, fillRadialType=1, fillAmount=1 },
  }

  --[[ ★ 只读字段：真机上写不进去。

       R16 实测：imageType 写=false，读回仍是原值。
       而 imageId / imageSource 也是只读 —— 换图必须走 SetImage 方法。
  ]]--
  local READONLY = {
    image = { imageId=1, imageSource=1, imageType=1 },
  }

  local function makeControl(kind, parent)
    created = created + 1
    local data = {
      kind = kind,
      fields = { active = true, visible = true },
      children = {},
      listeners = {},
    }

    local allowed = {}
    for k in pairs(COMMON) do allowed[k] = true end
    for k in pairs(PER_KIND[kind] or {}) do allowed[k] = true end

    local METHODS = {
      GetChildren = function() return data.children end,
      SetActive = function(_, v) data.fields.active = v end,
      SetVisible = function(_, v) data.fields.visible = v end,
      SetAnchoredPosition = function(_, x, y)
        data.fields.anchoredPositionX = x
        data.fields.anchoredPositionY = y
      end,
      SetSizeDelta = function(_, w, h)
        data.fields.sizeDeltaX = w
        data.fields.sizeDeltaY = h
      end,
      SetSiblingIndex = function() return true end,
      SetAnchorMin = function(_, x, y)
        data.fields.anchorMinX = x; data.fields.anchorMinY = y
      end,
      SetAnchorMax = function(_, x, y)
        data.fields.anchorMaxX = x; data.fields.anchorMaxY = y
      end,
      SetPivot = function(_, x, y)
        data.fields.pivotX = x; data.fields.pivotY = y
      end,
      GetChild = function(_, n)
        for _, c in ipairs(data.children) do
          if dataMap[c] and dataMap[c].fields.name == n then return c end
        end
        return nil
      end,
      FindChild = function(_, n) return nil end,
      AddCursorEventListener = function(_, ev, cb)
        data.listeners[#data.listeners+1] = { ev=ev, cb=cb }
      end,
      RemoveAllCursorEventListeners = function()
        data.listeners = {}
      end,

      --[[ ★ 图片控件方法（R16 真机实测）

           SetImage(imageSource, imageId)

           ★ 真机行为：参数类型不对会【抛异常】：
               bad argument #2 to 'SetImage' (ImageSource expected, got nil)
             所以这里也做类型校验，让本地就能测出参数顺序错误。
      ]]--
      SetImage = function(_, imageSource, imageId)
        if imageSource == nil then
          error("bad argument #1 to 'SetImage' (ImageSource expected, got nil)", 2)
        end
        if type(imageId) ~= "number" then
          error("bad argument #2 to 'SetImage' (integer expected, got "
                .. type(imageId) .. ")", 2)
        end
        data.fields.imageId = imageId
        data.fields.imageSource = imageSource
      end,

      SetFillUnused = function() end,
      SetFillHorizontal = function() end,
      SetFillVertical = function() end,
      SetFillRadial90 = function() end,
      SetFillRadial180 = function() end,
      SetFillRadial360 = function() end,
      SetSoftEdgeWidth = function(_, x, y)
        data.fields.softEdgeWidthX = x
        data.fields.softEdgeWidthY = y
      end,
    }

    local proxy = {}
    setmetatable(proxy, {
      __index = function(_, k)
        if allowed[k] then return data.fields[k] end
        if METHODS[k] then return METHODS[k] end
        return nil            -- ★ 其他字段/方法一律不存在
      end,
      __newindex = function(_, k, v)
        -- ★ 只读字段：静默失败（真机行为 —— 写了不报错，但也写不进去）
        local ro = READONLY[kind]
        if ro and ro[k] then return end

        if allowed[k] then
          data.fields[k] = v
        end
        -- ★ 自定义字段：静默失败（真机行为，不报错也写不进）
      end,
    })

    if parent then
      local pd = dataMap[parent]
      if pd then pd.children[#pd.children+1] = proxy end
    end

    dataMap[proxy] = data
    controls[#controls+1] = proxy
    return proxy
  end

  local game = {
    InstantiateClientUIControl = function(idx, parent)
      for k, v in pairs(prefabs) do
        if v == idx then return makeControl(k, parent) end
      end
      return nil
    end,
    DestroyClientUIControl = function() end,
    GetUICanvasSize = function() return 1600, 900 end,

    --[[ ★ 真机 API（client_control_api.md 第 209-210 行）

         FindClientUIRoot(name)  —— 按名称找 UI 根控件
         GetClientUIRoots()      —— 取全部根控件

         真机上这些根控件来自【编辑器里搭好的控件树】，
         不由脚本创建。mock 里用一个"外部根"来模拟：
         测试可用 setRoots{...} 注入。
    ]]--
    FindClientUIRoot = function(name)
      for _, r in ipairs(externalRoots) do
        local d = dataMap[r]
        if d and d.fields.name == name then return r end
      end
      return nil
    end,
    GetClientUIRoots = function()
      local out = {}
      for i, r in ipairs(externalRoots) do out[i] = r end
      return out
    end,
  }

  return {
    game = game,
    controls = controls,
    --[[ ★ 注册"外部根控件"（模拟编辑器里搭好的控件树）

         测试里这样用：
           local root = E.makeControl("container", nil)
           root.name = "Root"
           E.setRoots({ root })
           -- 之后 game.FindClientUIRoot("Root") 就能找到
    ]]--
    setRoots = function(list)
      externalRoots = list or {}
    end,
    createdCount = function() return created end,
    makeControl = makeControl,
    dataOf = function(c) return dataMap[c] end,
    -- 工具：统计沿父链可见的控件数
    visibleCount = function()
      local n = 0
      for _, c in ipairs(controls) do
        local d = dataMap[c]
        if d and d.fields.active then
          -- 沿父链检查
          local vis, depth = true, 0
          local p = nil
          for _, c2 in ipairs(controls) do
            local d2 = dataMap[c2]
            if d2 then
              for _, kid in ipairs(d2.children) do
                if kid == c then p = c2 end
              end
            end
          end
          while p and depth < 30 do
            local pd = dataMap[p]
            if not pd or not pd.fields.active then vis = false break end
            local pp = nil
            for _, c2 in ipairs(controls) do
              local d2 = dataMap[c2]
              if d2 then
                for _, kid in ipairs(d2.children) do
                  if kid == p then pp = c2 end
                end
              end
            end
            p = pp
            depth = depth + 1
          end
          if vis then n = n + 1 end
        end
      end
      return n
    end,
  }
end

return EngineMock