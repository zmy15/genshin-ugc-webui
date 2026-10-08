--[[============================================================================
  webui_signal.lua  ——  服务器信号（客户端 <-> 服务端唯一的通道）

  引擎能力（client_control_api.md §5 / §9，均为官方文档条目）：

    发送（客户端 -> 服务端）：
      game.ServerSignal(signalName)            -> ServerSignal
      sig:AddInt / AddString / AddFloat / ...  -- 往参数列表【末尾追加】
      sig:SendSignal()                         -- 发出去

    接收（服务端 -> 客户端）：
      script:RegisterServerSignalHandler(signalName, fn)
      script:UnregisterServerSignalHandler(signalName)
      回调签名：fn(signalName, params)   -- ★ 两个参数，第二个是数组

  ⚠️⚠️ 本模块存在的理由：引擎【不校验】任何东西。

    · 参数个数不对   -> 不报错，服务端收到缺参/多参
    · 参数顺序错     -> 不报错，服务端收到【错位的值】
    · 类型不对       -> 不报错，静默变成别的值
    · 信号名拼错     -> 不报错，谁都不响应

    也就是说，收发两端只能靠【约定】对齐，而约定写错的表现是
    「什么都没发生」。这正是本库最忌讳的失败模式
    （见 docs/引擎能力与限制.md §七：不许静默失败）。
    所以这里要求把约定【显式声明成签名】，并由库来校验。

  ---------------------------------------------------------------------------
  用法一：签名表 + 收发（推荐）

    local signal = require('webui_signal')

    local S = signal.new{
      signatures = {
        -- 名字               参数类型（顺序即约定顺序）
        buy_item   = { "int", "int" },          -- 商品ID, 数量
        chat       = { "string" },
        ready      = {},
            -- ★ 可写自定义事件名，但这只是【本地】事件；
            --   要与服务端通信必须用服务端已注册的信号名。
      },
    }

    -- 注册接收（内部走 script:RegisterServerSignalHandler）
    S:on("buy_item", function(a, b)
      -- a, b 已按签名解出，且带类型校验
    end)

    -- 发送（默认进队列，由 flush 统一发，见下"为什么用队列"）
    S:emit("buy_item", 1001, 3)

    -- 逐帧推进：每个渲染帧调一次（webui 已自动接好，见文末）
    S:flush()

  用法二：不声明签名也行

    没在 signatures 里声明的信号，emit 时【按值推断】类型
    （整数 -> int，小数 -> float，字符串 -> string，布尔 -> bool，
      带 x/y/z 的表 -> vector3，其他表 -> json）。
    ★ 推断出来的签名会在首次发送时记下，并对【后续同名字号】
      做一致性告警 —— 同一个信号一会儿发 int 一会儿发 string
      几乎肯定是写错了，而真机对此完全静默。

  ---------------------------------------------------------------------------
  四个可靠性机制（都是可关的）

   ① 接收缓冲 —— 服务端信号可能在控件/页面建好【之前】就到
      （Root 晚一帧就绪是真机常态，见 webui.lua 里 mount 的长注释）。
      此时 handler 直接跑会操作到 nil 的 DOM。所以：
        · 未 ready 时先【入队】（有上限，默认 128）
        · ready 时按【到达顺序】重放
      顺序必须保持：先到的"加钱"不能排在后到的"扣钱"后面。

   ② 发送队列 —— emit 不当场 SendSignal，而是攒到 flush 统一发。
      理由：onTick 里可能连发好几条；真机逐帧写入是有预算的
      （见 docs/引擎能力与限制.md 的逐帧上限压测），
      攒批能把发送点收敛到"每帧一次、渲染之前"。
      实时性要求高的（如"开火"）用 S:emitNow(...) 立即发。

   ③ 冷却 / 限流 —— 同一信号在【同一帧内】最多发一次（默认），
      超出的被合并计数。防止 onTick 每帧狂发把服务端打爆。

   ④ 校验与预算 ——
        · 参数个数 / 类型不符 -> warn（不是静默）
        · 单帧发送条数超预算 -> warn
        · 估算单帧信号字节数超预算 -> warn
      字节是按参数类型估算的（引擎没有"序列化后大小"API），
      用于抓"每帧发一大坨"这类问题，不是精确计费。

  ---------------------------------------------------------------------------
  ⚠️ 真机注意（写代码前先看）

    1. 【信号名是双端约定】。客户端单方面注册/发送毫无意义 ——
       必须先在服务端脚本里注册同名信号。
    2. 官方教程多讲【服务端悬浮交互页】，与客户端控件不是一套，
       别照着套（docs/引擎能力与限制.md §七）。
    3. script 是【入口脚本的身份】。本模块是 require 进来的，
       _ENV 独立 —— 所以注册监听必须拿到真的 script 对象，
       而不是模块里的全局 script。默认走全局 script 是给
       "调用方恰好在入口环境"用的；mount 会显式传进来。
    4. 回收必须解绑（UnregisterServerSignalHandler），
       否则监听累积 —— 与光标事件的 RemoveAllCursorEventListeners
       是同一类泄漏（见 docs/真机复用问题复盘.md）。
==============================================================================]]

local util = require('webui_util')

local S = {}

S.VERSION = "0.1.0"

--=============================================================================
-- 参数类型
--
--   与 client_control_api.md §9 的 Add* 方法一一对应。
--   别名是为了让签名表好写（"'int'" 比 "'Int'" 一样，但小写更省事）。
--=============================================================================

S.TYPES = {
  "int", "intlist", "float", "floatlist", "string", "stringlist",
  "vector3", "vector3list", "bool", "boollist",
  "guid", "guidlist", "entity", "entitylist",
  "prefabid", "prefabidlist", "configid", "configidlist",
}

-- 别名 -> 规范类型名
local TYPE_ALIAS = {
  integer = "int", integers = "int", i = "int", number = "float",
  real = "float", f = "float", str = "string", s = "string",
  boolean = "bool", b = "bool", vector = "vector3", vec3 = "vector3",
  v3 = "vector3", table = "json",
  -- 列表别名
  ints = "intlist", floats = "floatlist", numbers = "floatlist",
  strings = "stringlist", bools = "boollist",
  -- ★ json：不在引擎的类型列表里，是本模块的【本地约定】，
  --   用于"我这边按结构用、服务端也按结构收"的场景（见 toParams）。
  json = "json",
}

-- 规范类型 -> ServerSignal 的 Add 方法名
local ADD_METHOD = {
  int = "Int", intlist = "IntList",
  float = "Float", floatlist = "FloatList",
  string = "String", stringlist = "StringList",
  vector3 = "Vector3", vector3list = "Vector3List",
  bool = "Bool", boollist = "BoolList",
  guid = "Guid", guidlist = "GuidList",
  entity = "Entity", entitylist = "EntityList",
  prefabid = "PrefabId", prefabidlist = "PrefabIdList",
  configid = "ConfigId", configidlist = "ConfigIdList",
}

-- 规范类型 -> AddParam 用的 ParamType 枚举名（没有 AddXxx 方法时的退路）
local PARAM_TYPE_ENUM = {
  int = "Int", intlist = "IntList",
  float = "Float", floatlist = "FloatList",
  string = "String", stringlist = "StringList",
  bool = "Bool", boollist = "BoolList",
  vector3 = "Vector3", vector3list = "Vector3List",
  guid = "Guid", guidlist = "GuidList",
  entity = "Entity", entitylist = "EntityList",
  prefabid = "PrefabId", prefabidlist = "PrefabIdList",
  configid = "ConfigId", configidlist = "ConfigIdList",
}

-- 字节预算的估算权重（不是精确值，是"抓大坨"用的量级）
local SIZE_WEIGHT = {
  int = 8, float = 8, bool = 1, guid = 8, entity = 8,
  prefabid = 8, configid = 8,
  string = 32,            -- 基数字节；实际按字符串长度另算
  vector3 = 24,
  json = 64,
  intlist = 8, floatlist = 8, boollist = 1, guidlist = 8,
  entitylist = 8, prefabidlist = 8, configidlist = 8,
  stringlist = 32, vector3list = 24,
}

--[[ 类型名规范化。未知类型返回 nil（调用方负责 warn）。 ]]--
function S.normalizeType(t)
  if type(t) ~= "string" then return nil end
  local k = t:lower():gsub("[%s_%-]", "")
  if TYPE_ALIAS[k] then return TYPE_ALIAS[k] end
  for i = 1, #S.TYPES do
    if S.TYPES[i] == k then return k end
  end
  if k == "json" then return "json" end
  return nil
end

--=============================================================================
-- 值 -> 类型 推断（没声明签名时用）
--=============================================================================

local function isList(t)
  if type(t) ~= "table" then return false end
  if #t == 0 then return false end
  for i = 1, #t do
    if t[i] == nil then return false end
  end
  return true
end

--[[ 推断一个值的 webui 类型。

     ⚠️ Lua 里整数和小数都是 number，靠 math.type 区分
        （真机 Lua 5.3 有 math.type；没有就退回取整判断）。 ]]--
function S.inferType(v)
  local tv = type(v)
  if tv == "number" then
    if math.type then
      return math.type(v) == "integer" and "int" or "float"
    end
    return v == math.floor(v) and "int" or "float"
  end
  if tv == "string" then return "string" end
  if tv == "boolean" then return "bool" end
  if tv == "table" then
    -- 向量：以 x,y,z 为键
    if v.x ~= nil and v.y ~= nil then return "vector3" end
    -- 列表：取首元素推断元素类型
    if isList(v) then
      local elem = S.inferType(v[1])
      if elem == "int" then return "intlist" end
      if elem == "float" then return "floatlist" end
      if elem == "string" then return "stringlist" end
      if elem == "bool" then return "boollist" end
      if elem == "vector3" then return "vector3list" end
      return "json"
    end
    return "json"
  end
  return nil
end

--=============================================================================
-- 校验
--=============================================================================

--[[ 检查一个值是否符合声明的类型。返回 ok, 说明。 ]]--
function S.checkType(t, v)
  -- ★ 事件伪类型：值必须是 { "事件名", 参数... }。
  --   （它不会走到这里 —— encode 单独处理 —— 但外部直接调用时要有答案。）
  if t == "events" then
    if type(v) ~= "table" or type(v[1]) ~= "string" then
      return false, "期望 { \"事件名\", 参数... }"
    end
    return true
  end

  local tv = type(v)
  local function num()
    if tv ~= "number" then return false, "期望 number，实际 " .. tv end
    if t == "int" then
      if math.type then
        if math.type(v) ~= "integer" then
          return false, string.format("期望整数，实际是小数 %s", tostring(v))
        end
      elseif v ~= math.floor(v) then
        return false, string.format("期望整数，实际是小数 %s", tostring(v))
      end
    end
    return true
  end

  if t == "int" or t == "float" then return num() end
  if t == "string" then
    if tv ~= "string" then return false, "期望 string，实际 " .. tv end
    return true
  end
  if t == "bool" then
    if tv ~= "boolean" then return false, "期望 boolean，实际 " .. tv end
    return true
  end
  if t == "vector3" then
    if tv ~= "table" then return false, "期望 {x=,y=,z=}，实际 " .. tv end
    if type(v.x) ~= "number" or type(v.y) ~= "number" then
      return false, "向量缺少 x/y 数值字段"
    end
    return true
  end
  if t == "json" then
    if tv ~= "table" then return false, "期望 table，实际 " .. tv end
    return true
  end

  -- 列表类
  if t:sub(-4) == "list" then
    if tv ~= "table" then return false, "期望列表 table，实际 " .. tv end
    local elemT = t:sub(1, -5)
    if elemT == "prefabid" then elemT = "int" end
    if elemT == "configid" then elemT = "int" end
    if elemT == "guid" then elemT = "int" end
    if elemT == "entity" then elemT = "int" end
    for i = 1, #v do
      local ok, why = S.checkType(elemT, v[i])
      if not ok then
        return false, string.format("第 %d 项: %s", i, tostring(why))
      end
    end
    return true
  end

  return true   -- 未知类型不拦（上游已 warn）
end

--[[ 估算一个参数的字节开销（用于单帧预算告警，不是精确值）。 ]]--
function S.estimateSize(t, v)
  local w = SIZE_WEIGHT[t] or 8
  if t == "events" then
    -- 事件：序号 + 个数 + 各参数（粗估）
    return 16 + #v * 12
  end
  if t == "string" then return w + #tostring(v) end
  if t == "stringlist" then
    local n = 0
    for i = 1, #v do n = n + #tostring(v[i]) end
    return w + n
  end
  if t:sub(-4) == "list" then return w * math.max(1, #v) end
  if t == "json" then
    -- 粗略：按键值对数量估
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    return w + n * 16
  end
  return w
end

--=============================================================================
-- 模块级：当前实例
--
--   引擎的信号注册是【全局按名】的（script:RegisterServerSignalHandler），
--   没有"属于哪个实例"的概念。而 webui 的 mount 会反复 stop/start。
--   所以这里维护"当前活跃实例"，并由 Instance:destroy() 保证解绑 ——
--   与 webui_event.unbindKeys 是同一套思路（用同一引用移除，防泄漏）。
--=============================================================================

local current = nil

--[[ 取当前活跃实例（mount 建立的）。没有则为 nil。 ]]--
function S.current()
  return current
end

--[[ 模块级转发：往当前实例发一条信号。
     没有实例时返回 false，不报错（headless 场景用得上）。 ]]--
function S.emit(name, ...)
  if not current then
    util.warn("signal.emit: 尚无活跃实例（请在 mount 之后调用）")
    return false
  end
  return current:emit(name, ...)
end

function S.on(name, fn, opts)
  if not current then
    util.warn("signal.on: 尚无活跃实例（请在 mount 之后调用）")
    return false
  end
  return current:on(name, fn, opts)
end

function S.flush()
  if current then return current:flush() end
  return 0
end

--[[ 事件名索引（json 列表不支持非字符串键，签名表里用事件名引用）
--
--   signatures = {
--     buy_item = { "int", "int" },
--     events   = { "buy_item" },      -- -> 服务端收到 [1, 1001, 3]
--     on_hit   = { "int", "events" }, -- 混用
--   }
--
--   ★ "events" 是【签名专用】的伪类型：表示"这个槽位是一个事件
--     （事件名 + 它自己的参数）"。不是引擎的 Add* 类型，
--     所以在校验期要放行，否则会出现"签名里写了 events
--     却被判为无法识别的类型"这种自相矛盾。
--]]
--=============================================================================

local EVENT_TYPE = "events"

--[[ 建立"事件名 -> 序号"索引。

     为什么需要：json 列表要求元素同类型，没法把"事件名 + 参数"
     直接塞进去，所以事件在线上表示为
       [事件序号, 参数个数, 参数...]
     序号由签名表【排序后】的位置决定 —— 必须排序，
     否则 pairs 顺序一变，双端序号就对不上了。 ]]--
local function buildEventIndex(signatures)
  local idx = {}
  local names = {}
  for k in pairs(signatures) do
    if type(k) == "string" then names[#names + 1] = k end
  end
  -- ★ pairs 顺序未定义 —— 必须显式排序，否则事件的索引值
  --   会随 Lua 版本/表布局变化，服务端对不上号。
  table.sort(names)
  for i = 1, #names do idx[names[i]] = i end
  return idx, names
end

--=============================================================================
-- 把"签名 + 参数"编成服务端能收的原生类型序列
--=============================================================================

--[[ 编码：values -> 一串 { t = 类型, v = 值 }。

     规则：
       · 类型 events            -> 展开成 "int"(事件序号) + "int"(参数个数)
                                   + 各参数（值形如 { "事件名", 参数... }）
       · 类型 json（非事件名）  -> 展开成 "json" + JSON 字符串
         （json 列表要求元素同类型，不能直接塞异构 table）
     参数：eventIdx  事件名 -> 序号（可为 nil，则不做事件展开）
           strict    是否校验参数个数/类型
     返回：encoded, err ]]--
function S.encode(sig, values, eventIdx, strict)
  local out = {}
  local n = #values

  if strict and n ~= #sig then
    return nil, string.format("参数个数不符: 签名 %d 个，实际 %d 个", #sig, n)
  end

  for i = 1, #sig do
    local t = sig[i]
    local v = values[i]

    if t == EVENT_TYPE then
      -- ★ 值形如 { "事件名", 参数1, 参数2, ... }
      if type(v) ~= "table" or type(v[1]) ~= "string" then
        return nil, string.format(
            "第 %d 个参数(events): 期望 { \"事件名\", 参数... }，实际 %s",
            i, type(v))
      end
      local evName = v[1]
      local evId = eventIdx and eventIdx[evName] or nil
      if not evId then
        -- ★ 没登记的事件名：真机不会报错，只会让服务端无法识别 ——
        --   所以这里必须拦下（这正是本模块存在的意义）。
        return nil, string.format(
            "第 %d 个参数(events): 事件 '%s' 不在 signatures 里（无法取序号）",
            i, evName)
      end
      local cnt = #v - 1
      out[#out + 1] = { t = "int", v = evId }
      out[#out + 1] = { t = "int", v = cnt }
      for j = 2, #v do
        local vt = S.inferType(v[j])
        if not vt then
          return nil, string.format("事件 '%s' 的第 %d 个参数类型无法推断",
              evName, j - 1)
        end
        out[#out + 1] = { t = vt, v = v[j] }
      end
    else
      if strict then
        local ok, why = S.checkType(t, v)
        if not ok then
          return nil, string.format("第 %d 个参数(%s): %s", i, t, tostring(why))
        end
      end
      out[#out + 1] = { t = t, v = v }
    end
  end

  return out
end

--[[ 解码：把服务端的参数数组按签名解回 Lua 值。

     ★ 引擎回调给的是 any[]，本身不带类型信息 —— 只能靠签名
       约定解。所以签名写错 = 解出错位的值，且【不会报错】。
       这正是本模块要校验的理由。

     返回：values(数组), err ]]--
function S.decode(sig, params)
  local out = {}
  local n = #params

  for i = 1, #sig do
    local t = sig[i]
    local v = params[i]
    if v == nil then
      -- 参数比签名少：留 nil，但报出来
      out[i] = nil
    elseif t == "json" and type(v) == "string" then
      out[i] = S.fromJSON(v)
    elseif t == "int" and type(v) == "number" then
      out[i] = math.floor(v)
    else
      out[i] = v
    end
  end

  if n > #sig then
    return out, string.format("参数比签名多 %d 个（服务端发的是新版？）", n - #sig)
  end
  if n < #sig then
    return out, string.format("参数比签名少 %d 个", #sig - n)
  end
  return out, nil
end

--=============================================================================
-- 极简 JSON（真机没有 json 库：io/package 都不可用）
--
--   只做"够用"的子集：对象 / 数组 / 字符串 / 数字 / 布尔 / null。
--   不支持：非字符串键、嵌套深度保护靠递归自然栈。
--   ★ 键顺序因 pairs 未定义 —— 但 JSON 是对象，顺序无语义。
--=============================================================================

local JSON_ESC = {
  ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local function jsonEscape(s)
  return (s:gsub('[%z\1-\31\\"]', function(c)
    return JSON_ESC[c] or string.format('\\u%04x', c:byte())
  end))
end

local function jsonEncode(v, seen)
  local tv = type(v)
  if v == nil then return "null" end
  if tv == "boolean" then return v and "true" or "false" end
  if tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if math.type and math.type(v) == "integer" then return tostring(v) end
    -- 避免 1.0 被写成 "1.0" 之外的怪格式
    return (string.format("%.14g", v))
  end
  if tv == "string" then return '"' .. jsonEscape(v) .. '"' end
  if tv == "table" then
    -- ★ 环检测：真机没有 collectgarbage，环会让递归爆栈
    seen = seen or {}
    if seen[v] then return "null" end
    seen[v] = true

    local out
    if isList(v) then
      local parts = {}
      for i = 1, #v do parts[i] = jsonEncode(v[i], seen) end
      out = "[" .. table.concat(parts, ",") .. "]"
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      local parts = {}
      for i = 1, #keys do
        local k = keys[i]
        parts[i] = '"' .. jsonEscape(tostring(k)) .. '":' .. jsonEncode(v[k], seen)
      end
      out = "{" .. table.concat(parts, ",") .. "}"
    end

    seen[v] = nil
    return out
  end
  return "null"
end

function S.toJSON(v)
  return jsonEncode(v, nil)
end

--[[ 极简 JSON 解析（本模块发出/收到的 json 参数用）。
     失败返回 nil, 错误。 ]]--
function S.fromJSON(s)
  if type(s) ~= "string" then return nil, "不是字符串" end
  local pos = 1
  local len = #s

  local function skip()
    while pos <= len do
      local c = s:sub(pos, pos)
      if c == " " or c == "\t" or c == "\n" or c == "\r" then pos = pos + 1
      else break end
    end
  end

  local parseValue

  local function parseString()
    pos = pos + 1                       -- 跳过开头引号
    local buf = {}
    while pos <= len do
      local c = s:sub(pos, pos)
      if c == '"' then
        pos = pos + 1
        return table.concat(buf)
      elseif c == "\\" then
        local e = s:sub(pos + 1, pos + 1)
        local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f",
                      ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
        if map[e] then
          buf[#buf + 1] = map[e]; pos = pos + 2
        elseif e == "u" then
          local hex = s:sub(pos + 2, pos + 5)
          local cp = tonumber(hex, 16)
          if not cp then return nil, "非法 \\u 转义" end
          -- ★ 只处理 BMP：真机 utf8.char 可用
          buf[#buf + 1] = utf8.char and utf8.char(cp) or "?"
          pos = pos + 6
        else
          return nil, "非法转义 \\" .. tostring(e)
        end
      else
        buf[#buf + 1] = c
        pos = pos + 1
      end
    end
    return nil, "字符串没有收尾引号"
  end

  local function parseNumber()
    local start = pos
    while pos <= len and s:sub(pos, pos):match("[%d%.%+%-eE]") do pos = pos + 1 end
    local txt = s:sub(start, pos - 1)
    local n = tonumber(txt)
    if not n then return nil, "非法数字 " .. txt end
    return n
  end

  -- ★ 必须是 `parseValue = function()`（不是 `function parseValue()`）：
  --   后者会写成【全局】，而上面 `local parseValue` 永远是 nil ——
  --   递归到 "[" 或 "{" 时就会 "attempt to call a nil value"。
  parseValue = function()
    skip()
    if pos > len then return nil, "内容意外结束" end
    local c = s:sub(pos, pos)

    if c == '"' then return parseString() end
    if c == "{" then
      pos = pos + 1
      local obj = {}
      skip()
      if s:sub(pos, pos) == "}" then pos = pos + 1; return obj end
      while true do
        skip()
        local k, err = parseString()
        if k == nil then return nil, err end
        skip()
        if s:sub(pos, pos) ~= ":" then return nil, "对象缺 ':'" end
        pos = pos + 1
        local v, err2 = parseValue()
        if err2 then return nil, err2 end
        obj[k] = v
        skip()
        local d = s:sub(pos, pos)
        if d == "," then pos = pos + 1
        elseif d == "}" then pos = pos + 1; return obj
        else return nil, "对象缺 ',' 或 '}'" end
      end
    end
    if c == "[" then
      pos = pos + 1
      local arr = {}
      skip()
      if s:sub(pos, pos) == "]" then pos = pos + 1; return arr end
      while true do
        local v, err = parseValue()
        if err then return nil, err end
        arr[#arr + 1] = v
        skip()
        local d = s:sub(pos, pos)
        if d == "," then pos = pos + 1
        elseif d == "]" then pos = pos + 1; return arr
        else return nil, "数组缺 ',' 或 ']'" end
      end
    end
    if s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true end
    if s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false end
    if s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil end
    return parseNumber()
  end

  local v, err = parseValue()
  if err then return nil, err end
  skip()
  if pos <= len then return nil, "尾部有多余内容" end
  return v
end

--=============================================================================
-- 实例
--=============================================================================

local Instance = {}
Instance.__index = Instance

--[[ 建立信号层。

     opts = {
       signatures = { 事件名 = { 类型, ... }, ... },   -- 约定（可省）
       script     = 宿主 script 对象,                  -- 默认全局 script
       strict     = true,    -- 参数个数/类型不符就 warn（默认 true）
       queue      = true,    -- emit 进队列，flush 统一发（默认 true）
       buffer     = 128,     -- 接收缓冲上限（默认 128，0 = 关掉缓冲）
       perFrame   = 1,       -- 同一信号每帧最多发几次（默认 1，nil = 不限）
       frameBudget= 32,      -- 单帧最多发几条信号（默认 32）
       byteBudget = 4096,    -- 单帧信号字节预算（估算，默认 4096）
       logTag     = "[webui]",
     }
]]--
function S.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Instance)

  self.signatures = opts.signatures or {}
  self.eventIdx, self.eventNames = buildEventIndex(self.signatures)
  self.scriptObj  = opts.script or (type(script) ~= "nil" and script or nil)

  self.strict      = opts.strict ~= false
  self.useQueue    = opts.queue ~= false
  self.bufferMax   = opts.buffer      or 128
  -- ★ perFrame 语义：正数 = 每帧上限；0 或负数 = 【不限流】；
  --   nil = 用默认值 1。这里曾经写成 `if self.perFrame == nil then 1`，
  --   把显式传的 0 也当成了"没传"，于是"想关掉冷却"的人反而被限死。
  self.perFrame    = opts.perFrame
  if self.perFrame == nil then self.perFrame = 1 end
  self.frameBudget = opts.frameBudget or 32
  self.byteBudget  = opts.byteBudget  or 4096
  self.logTag      = opts.logTag      or "[webui]"

  self.handlers    = {}    -- 事件名 -> { fn, ... }（本地注册）
  self.registered  = {}    -- 事件名 -> 已注册到 script 的回调（★ 同一引用，移除要用）
  self.sendQueue   = {}    -- { {name=, values=}, ... }
  self.recvBuffer  = {}    -- { {name=, params=}, ... }（未 ready 时的积压）
  self.frameCount  = 0     -- 第几帧（flush 调用次数）
  self.lastFrameOf = {}    -- 事件名 -> 上次发送所在帧（冷却用）
  self.dupCount    = 0     -- 被冷却合并掉的条数
  self.stats       = { sent = 0, failed = 0, received = 0, replayed = 0,
                       dropped = 0, warned = 0, bytesThisFrame = 0 }
  self.ready_      = false
  self.inferred    = {}    -- 事件名 -> 推断出来的签名（一致性告警用）

  return self
end

--=============================================================================
-- 签名
--=============================================================================

function Instance:_signature(name)
  local sig = self.signatures[name]
  if sig == nil then return nil end
  -- 规范化（允许写别名，也允许直接写 { "int", "int" }）
  local out = {}
  for i = 1, #sig do
    local raw = sig[i]
    -- ★ 事件伪类型：原样保留（它由 encode 展开，不是引擎类型）
    if type(raw) == "string" and raw:lower() == EVENT_TYPE then
      out[i] = EVENT_TYPE
    else
      local t = S.normalizeType(raw)
      if not t then
        util.warn(string.format("signal: 信号 '%s' 的第 %d 个参数类型 '%s' 无法识别",
            tostring(name), i, tostring(raw)))
        return nil
      end
      out[i] = t
    end
  end
  return out
end

--[[ 装饰器：给一个信号声明签名。支持两种写法：

     S:sig("buy_item", "int", "int")            -- 可变参数
     S:sig{ buy_item = {"int","int"}, ... }     -- 表

     返回 self（可链式）。 ]]--
function Instance:sig(name, ...)
  if type(name) == "table" then
    for k, v in pairs(name) do
      self.signatures[k] = v
    end
  else
    local list = { ... }
    self.signatures[name] = list
  end
  self.eventIdx, self.eventNames = buildEventIndex(self.signatures)
  return self
end

--[[ 是否已声明签名。 ]]--
function Instance:hasSignature(name)
  return self:_signature(name) ~= nil
end

--=============================================================================
-- 接收
--=============================================================================

--[[ 注册一个信号处理。

     fn 的调用形式是 fn(...)，参数按签名【逐个展开】——
     比引擎原生的 fn(signalName, params) 好写。
     想拿原始数组用 opts.raw = true。

     opts = { raw = true,          -- 回调收 (name, params) 而不是展开
              once = true }        -- 只处理一次
     返回 self ]]--
function Instance:on(name, fn, opts)
  opts = opts or {}
  if type(name) ~= "string" or type(fn) ~= "function" then
    util.warn("signal:on 参数不对（需要 名字, 函数）")
    return self
  end

  self.handlers[name] = self.handlers[name] or {}
  self.handlers[name][#self.handlers[name] + 1] = { fn = fn, opts = opts }

  self:_ensureRegistered(name)
  return self
end

--[[ 解除某个信号的全部处理（并注销引擎侧监听）。 ]]--
function Instance:off(name)
  self.handlers[name] = nil
  self:_unregister(name)
  return self
end

--[[ 内部：确保 name 已在 script 上注册过。

     ★ 为什么每个信号只注册【一个】回调、再由本模块分发：
       引擎按名注册，重复注册同一名字会累积监听 ——
       与光标事件监听累积是同一类泄漏（真机复用问题复盘里踩过）。
       所以这里【只】把 _dispatch 注册一次，业务回调存在 self.handlers。 ]]--
function Instance:_ensureRegistered(name)
  if self.registered[name] then return true end

  local sc = self.scriptObj
  if not sc or type(sc.RegisterServerSignalHandler) ~= "function" then
    -- ★ 不静默：没有 script 就永远收不到信号，必须让开发者知道
    util.warn(string.format(
        "signal: 无法注册 '%s' —— script 不可用（缺 RegisterServerSignalHandler）",
        name))
    return false
  end

  local self_ = self
  -- ★ 真机回调签名是 (signalName, params) —— 两个参数
  local cb = function(signalName, params)
    self_:_dispatch(signalName, params)
  end

  local ok = util.try(function()
    sc:RegisterServerSignalHandler(name, cb)
  end)
  if not ok then
    util.warn(string.format("signal: 注册 '%s' 失败", name))
    return false
  end

  -- ★ 保存同一引用，解绑时必须用它（文档第 763 行的同类要求）
  self.registered[name] = cb
  return true
end

function Instance:_unregister(name)
  local cb = self.registered[name]
  if not cb then return false end
  local sc = self.scriptObj
  if sc and type(sc.UnregisterServerSignalHandler) == "function" then
    util.try(function() sc:UnregisterServerSignalHandler(name) end)
  end
  self.registered[name] = nil
  return true
end

--[[ 内部：处理一条到达的信号。

     ★★ 未 ready 就【入队】而不是直接跑 handler —— 服务端信号可能在
        Root/DOM 建好之前就到（真机上 Root 比脚本晚一帧是常态）。
        此时跑 handler 会操作到 nil 的 DOM，报错还被 pcall 吞成一行 warn。
        入队 + ready 后重放，才是"信号不丢"的正确做法。 ]]--
function Instance:_dispatch(name, params)
  params = params or {}
  self.stats.received = self.stats.received + 1

  if not self.ready_ and self.bufferMax > 0 then
    if #self.recvBuffer >= self.bufferMax then
      -- ★ 满了就丢【最旧的】—— 保留最近的更像"当前状态"，
      --   且必须报出来，不能悄悄丢。
      table.remove(self.recvBuffer, 1)
      self.stats.dropped = self.stats.dropped + 1
      util.warn(string.format(
          "signal: 接收缓冲已满(%d)，丢弃最旧的一条 '%s'",
          self.bufferMax, tostring(self.recvBuffer[1] and self.recvBuffer[1].name)))
    end
    self.recvBuffer[#self.recvBuffer + 1] = { name = name, params = params }
    return
  end

  self:_invoke(name, params, false)
end

--[[ 内部：真正调用业务回调。 ]]--
function Instance:_invoke(name, params, replayed)
  local list = self.handlers[name]
  if not list or #list == 0 then
    -- ★ 没注册过的信号不报错（可能是服务端广播、我们不需要），
    --   但也不要静默到无从排查 —— 只记一次。
    return 0
  end

  local sig = self:_signature(name)
  local values, err = nil, nil
  if sig then
    values, err = S.decode(sig, params)
  else
    -- 没声明签名：把原始数组当参数列表（尽力而为）
    values = {}
    for i = 1, #params do values[i] = params[i] end
  end

  if err and self.strict then
    self.stats.warned = self.stats.warned + 1
    util.warn(string.format("signal: '%s' 解码告警 —— %s", tostring(name), err))
  end

  local n = 0
  for i = 1, #list do
    local h = list[i]
    local ok, e
    if h.opts.raw then
      ok, e = util.try(h.fn, name, params)
    else
      ok, e = util.try(h.fn, (table.unpack or unpack)(values, 1, #params))
    end
    if ok then n = n + 1 end
    if h.opts.once then list[i] = nil end
  end

  -- 清理 once 留下的空洞（保持顺序）
  if #list == 0 then
    self.handlers[name] = nil
  end

  return n
end

--[[ 标记"已就绪"：重放缓冲里积压的信号。

     由 webui.lua 在【首帧渲染完成之后】调用 —— 此刻 DOM 与控件
     都已经建好，handler 操作界面才安全。

     ★ 顺序保证：按到达顺序重放（先到的先处理）。
       否则"先加钱后扣钱"会变成"先扣钱后加钱"。 ]]--
function Instance:ready()
  if self.ready_ then return 0 end
  self.ready_ = true

  local n = #self.recvBuffer
  if n == 0 then return 0 end

  local buf = self.recvBuffer
  self.recvBuffer = {}
  for i = 1, #buf do
    self:_invoke(buf[i].name, buf[i].params, true)
  end
  self.stats.replayed = self.stats.replayed + n
  return n
end

--[[ 此刻缓冲里积压多少条（诊断用）。 ]]--
function Instance:pending()
  return #self.recvBuffer
end

--=============================================================================
-- 发送
--=============================================================================

--[[ 构造一条信号并【入队】（队列路径）。

     ⚠️⚠️ 冷却（perFrame）【不在这里判】—— 曾经判在这里，是错的：
        入队时什么都没发出去，却把信号标成"本帧已发"，
        于是同帧第二条直接被吞（即使 perFrame=0 也吞）。
        正确的位置是 flush：那里才是"真的发了"的时刻。

     返回：ok, err ]]--
function Instance:_send(name, values, opts)
  opts = opts or {}

  if type(name) ~= "string" or name == "" then
    util.warn("signal: 信号名必须是字符串")
    return false, "bad name"
  end

  -- ---- 1. 取签名（没有就按值推断，并记住推断结果做一致性检查）----
  local sig = self:_signature(name)
  if not sig then
    local inferred = {}
    for i = 1, #values do
      local t = S.inferType(values[i])
      if not t then
        util.warn(string.format(
            "signal: '%s' 第 %d 个参数类型无法推断（%s）",
            name, i, type(values[i])))
        return false, "bad arg type"
      end
      inferred[i] = t
    end
    sig = inferred

    local prev = self.inferred[name]
    if prev then
      local same = (#prev == #inferred)
      if same then
        for i = 1, #inferred do
          if prev[i] ~= inferred[i] then same = false break end
        end
      end
      if not same then
        self.stats.warned = self.stats.warned + 1
        util.warn(string.format(
            "signal: '%s' 的参数形状变了（%s -> %s）——"
            .. "真机对此完全静默，建议显式声明签名",
            name, table.concat(prev, ","), table.concat(inferred, ",")))
        self.inferred[name] = inferred
      end
    else
      self.inferred[name] = inferred
    end
  end

  -- ---- 2. 编码（strict 时校验个数与类型）----
  local encoded, err = S.encode(sig, values, self.eventIdx, self.strict)
  if not encoded then
    self.stats.warned = self.stats.warned + 1
    util.warn(string.format("signal: '%s' 发送被拦下 —— %s", name, tostring(err)))
    return false, err
  end

  -- ---- 3. 字节预算 ----
  local bytes = 0
  for i = 1, #encoded do
    bytes = bytes + S.estimateSize(encoded[i].t, encoded[i].v)
  end

  if opts.now then
    if not self:_budget(name, bytes, true) then
      return false, "over budget"
    end
    return self:_doSend(name, encoded, bytes)
  end

  -- ★ 冷却与条数预算都在 flush 里判（那里才是"真的发"的时刻）
  self.sendQueue[#self.sendQueue + 1] = { name = name, encoded = encoded, bytes = bytes }
  return true
end

--[[ 内部：字节预算检查（立即发送路径）。

     ★ 条数预算（frameBudget）只在 flush 里管 —— 队列要"顺延不丢弃"，
       而立即发送没有队列可顺延。所以这里【只】查字节。
       曾经这里留了一段永远进不去的条数判断（条件自相矛盾），已删除：
       死代码比没有代码更坏 —— 它让后来的人以为条数在这是管着的。 ]]--
function Instance:_budget(name, bytes, immediate)
  if self.stats.bytesThisFrame + bytes > self.byteBudget then
    self.stats.warned = self.stats.warned + 1
    util.warn(string.format(
        "signal: 本帧信号字节预算超了（%d + %d > %d）—— 信号 '%s'",
        self.stats.bytesThisFrame, bytes, self.byteBudget, tostring(name)))
    return false
  end
  return true
end

--[[ 内部：真正调用引擎发送。 ]]--
function Instance:_doSend(name, encoded, bytes)
  local g = (type(game) ~= "nil") and game or nil
  if not g or type(g.ServerSignal) ~= "function" then
    util.warn("signal: game.ServerSignal 不可用，无法发送 '" .. name .. "'")
    self.stats.failed = self.stats.failed + 1
    return false, "no engine api"
  end

  local ok, err = util.try(function()
    local sig = g.ServerSignal(name)

    -- ★★ 逐个参数按【声明顺序】追加。顺序就是约定 ——
    --    顺序错了引擎不报错，服务端收到错位的值。
    for i = 1, #encoded do
      local p = encoded[i]
      local method = ADD_METHOD[p.t]
      local fn = method and sig["Add" .. method] or nil

      if type(fn) == "function" then
        fn(sig, p.v)
      else
        -- 退路：通用 AddParam(paramType, paramValue)
        -- ★ 枚举名禁止照文档猜（R16 教训），所以显式取 + pcall
        local pt = nil
        if type(Enum) ~= "nil" and Enum.ParamType then
          local ename = PARAM_TYPE_ENUM[p.t]
          if ename then
            local okc = pcall(function() pt = Enum.ParamType[ename] end)
            if not okc then pt = nil end
          end
        end
        if pt == nil then
          error(string.format("没有 Add%s，且 Enum.ParamType.%s 取不到",
              tostring(method), tostring(PARAM_TYPE_ENUM[p.t])), 2)
        end
        sig:AddParam(pt, p.v)
      end
    end

    sig:SendSignal()
  end)

  if not ok then
    self.stats.failed = self.stats.failed + 1
    util.warn(string.format("signal: 发送 '%s' 失败 —— %s", name, tostring(err)))
    return false, err
  end

  self.stats.sent = self.stats.sent + 1
  self.stats.bytesThisFrame = self.stats.bytesThisFrame + bytes
  self.lastFrameOf[name] = self.frameCount
  return true
end

--[[ 发送一条信号（默认进队列，由 flush 统一发）。 ]]--
function Instance:emit(name, ...)
  if not self.useQueue then
    return self:_send(name, { ... }, { now = true })
  end
  return self:_send(name, { ... }, {})
end

--[[ 立即发送（不进队列）—— 实时性要求高的场景（开火、确认购买）。 ]]--
function Instance:emitNow(name, ...)
  return self:_send(name, { ... }, { now = true })
end

--[[ 批量发送：items = { { "名字", 参数... }, ... } ]]--
function Instance:emitAll(items)
  local n = 0
  if type(items) ~= "table" then return 0 end
  for i = 1, #items do
    local it = items[i]
    if type(it) == "table" and it[1] then
      local values = {}
      for j = 2, #it do values[#values + 1] = it[j] end
      if self:emit(it[1], (table.unpack or unpack)(values)) then n = n + 1 end
    end
  end
  return n
end

--=============================================================================
-- 逐帧推进
--=============================================================================

--[[ 每个渲染帧调一次。

     做三件事：
       ① 换帧（frameCount +1）—— 冷却按帧计数
       ② 把队列里的信号按序发出去（条数/字节超预算就顺延，不丢弃）
       ③ 重置本帧字节计数

     ★ 冷却（perFrame）在这里判，不在 emit —— 见 _send 的注释。

     返回：本帧真正发出的条数 ]]--
function Instance:flush()
  self.frameCount = self.frameCount + 1
  self.stats.bytesThisFrame = 0

  local q = self.sendQueue
  if #q == 0 then return 0 end
  self.sendQueue = {}

  local sentThisFrame = 0
  local sentNames = {}     -- 名字 -> 本帧已发次数（冷却）
  local deferred = {}

  for i = 1, #q do
    local item = q[i]

    -- ① 条数预算：超了就顺延到下一帧（★ 不丢弃 —— 丢弃会丢业务）
    if sentThisFrame >= self.frameBudget then
      deferred[#deferred + 1] = item

    -- ② 冷却：本帧同名的条数达上限就合并掉
    elseif self.perFrame and self.perFrame > 0
           and (sentNames[item.name] or 0) >= self.perFrame then
      self.dupCount = self.dupCount + 1
      util.warn(string.format(
          "signal: '%s' 本帧已发满 %d 次，本条被合并",
          item.name, self.perFrame))

    -- ③ 字节预算：超了就顺延
    elseif self.stats.bytesThisFrame + item.bytes > self.byteBudget then
      self.stats.warned = self.stats.warned + 1
      util.warn(string.format(
          "signal: 本帧字节预算不足，'%s' 顺延到下一帧（本帧已用 %d/%d）",
          item.name, self.stats.bytesThisFrame, self.byteBudget))
      deferred[#deferred + 1] = item
    else
      local ok = self:_doSend(item.name, item.encoded, item.bytes)
      if ok then
        sentThisFrame = sentThisFrame + 1
        sentNames[item.name] = (sentNames[item.name] or 0) + 1
      end
      -- 发送失败的不重排（重排会掩盖错误），仅计入 failed
    end
  end

  -- 顺延的放回队首，保持相对顺序
  if #deferred > 0 then
    local rest = self.sendQueue
    self.sendQueue = deferred
    for i = 1, #rest do
      self.sendQueue[#self.sendQueue + 1] = rest[i]
    end
  end

  return sentThisFrame
end

--[[ 现在队列里还有多少条（诊断用）。 ]]--
function Instance:queued()
  return #self.sendQueue
end

--[[ 统计快照（诊断用；打印趋势比体感可靠）。 ]]--
function Instance:stats_()
  local s = util.copy(self.stats)
  s.queued    = #self.sendQueue
  s.pending   = #self.recvBuffer
  s.duplicates = self.dupCount
  s.frame     = self.frameCount
  s.handlers  = util.count(self.handlers)
  s.registered = util.count(self.registered)
  return s
end

--[[ 一行摘要，直接 print 就能看趋势。 ]]--
function Instance:report()
  local s = self:stats_()
  return string.format(
      "signal: 帧%d 发%d 失败%d 收%d 重放%d 丢弃%d 合并%d 队列%d 缓冲%d 监听%d/%d 告警%d",
      s.frame, s.sent, s.failed, s.received, s.replayed, s.dropped,
      s.duplicates, s.queued, s.pending, s.handlers, s.registered, s.warned)
end

--[[ 切换 strict（调试用：想临时关掉校验就 S:setStrict(false)）。 ]]--
function Instance:setStrict(on)
  self.strict = on and true or false
  return self
end

--=============================================================================
-- 销毁
--=============================================================================

--[[ 解绑全部引擎监听 + 清空队列。

     ★ 必须解绑：引擎按名注册，留着会在下一次 mount 时【叠加】——
       表现为"一个信号处理了两遍"（与光标事件监听累积同类）。
     返回解绑的条数 ]]--
function Instance:destroy()
  local n = 0
  local names = {}
  for k in pairs(self.registered) do names[#names + 1] = k end
  -- ★ pairs 顺序未定义 —— 解绑顺序不影响正确性，但显式排序便于日志比对
  table.sort(names)
  for i = 1, #names do
    if self:_unregister(names[i]) then n = n + 1 end
  end
  self.handlers   = {}
  self.sendQueue  = {}
  self.recvBuffer = {}
  if current == self then current = nil end
  return n
end

-- 供 webui.lua 设置"当前活跃实例"
function S.setCurrent(inst)
  current = inst
  return inst
end

--=============================================================================
-- 无状态便捷 API（不想建实例、也不想用签名时）
--
--   ⚠️ 不校验、不排队、不缓冲 —— 只是把引擎调用包一层。
--      要那四个可靠性机制请用 S.new。
--=============================================================================

--[[ 直接发一条信号（不校验）。返回 ok, err ]]--
function S.send(name, ...)
  local g = (type(game) ~= "nil") and game or nil
  if not g or type(g.ServerSignal) ~= "function" then
    util.warn("signal.send: game.ServerSignal 不可用")
    return false, "no engine api"
  end
  local values = { ... }
  local ok, err = util.try(function()
    local sig = g.ServerSignal(name)
    for i = 1, #values do
      local t = S.inferType(values[i])
      local method = t and ADD_METHOD[t]
      local fn = method and sig["Add" .. method]
      if type(fn) == "function" then
        fn(sig, values[i])
      else
        error("没有可用的 Add 方法（类型 " .. tostring(t) .. "）", 2)
      end
    end
    sig:SendSignal()
  end)
  if not ok then return false, err end
  return true
end

--[[ 直接注册一个监听（不缓冲、不校验）。返回 ok ]]--
function S.register(name, fn)
  local sc = (type(script) ~= "nil") and script or nil
  if not sc or type(sc.RegisterServerSignalHandler) ~= "function" then
    util.warn("signal.register: script 不可用")
    return false
  end
  local ok = util.try(function()
    sc:RegisterServerSignalHandler(name, function(signalName, params)
      util.try(fn, signalName, params)
    end)
  end)
  return ok
end

function S.unregister(name)
  local sc = (type(script) ~= "nil") and script or nil
  if not sc or type(sc.UnregisterServerSignalHandler) ~= "function" then
    return false
  end
  return (util.try(function() sc:UnregisterServerSignalHandler(name) end))
end

return S