--[[ test_signal.lua —— 服务器信号层（webui_signal）

     ★ 本套件用 engine_mock（严格模拟真机限制）而不是普通 table，
       理由与前几个套件一致（"测试替身必须忠实"，
       见 docs/引擎能力与限制.md §七）：

       webui_signal 的全部价值在于「引擎不校验、库来校验」。
       若 mock 允许随便写、或允许在信号对象上挂自定义字段，
       那本地测的就是一个不存在的世界。

     ★ 覆盖重点（都是"真机静默失败"的类型）：
       1. 参数顺序 —— 引擎按【调用顺序】收，顺序错了服务端收到错位的值
       2. 参数个数 / 类型 —— 真机完全不校验
       3. 接收缓冲 —— 信号可能早于 DOM 到达（Root 晚一帧就绪是常态）
       4. 冷却 / 限流 —— 防 onTick 每帧狂发
       5. 字节预算 —— 抓"每帧发一大坨"
       6. 解绑 —— 引擎按名注册，不解绑会叠加
       7. 回调签名 —— 真机是 fn(signalName, params) 两个参数
]]

local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."
package.path = _root .. "/lib/webui/?.lua;"
             .. _root .. "/?.lua;" .. _root .. "/tests/?.lua;"
             .. _root .. "/tools/?.lua;" .. package.path

local EngineMock = require('engine_mock')

local PREFABS = { container=1073741933, textbox=1073741934,
                  button=1073741935, image=1073741938 }
local E = EngineMock.new(PREFABS)

game   = E.game
script = E.scriptStub()
Color  = { FromRGBA = function(r,g,b,a) return {r=r,g=g,b=b,a=a} end,
           FromRGB  = function(r,g,b) return {r=r,g=g,b=b} end }
Enum   = {
  EaseType = { Linear="Linear" },
  CursorEventType = {
    CursorClick="CursorClick", CursorDown="CursorDown", CursorUp="CursorUp",
    CursorEnter="CursorEnter", CursorExit="CursorExit",
    CursorBeginDrag="CursorBeginDrag", CursorDrag="CursorDrag",
    CursorEndDrag="CursorEndDrag",
  },
  TextHorizontalAlignmentLeft="L",
  TextHorizontalAlignmentMiddle="C",
  TextHorizontalAlignmentRight="R",
  ParamType = { Int="Int", IntList="IntList", Float="Float", String="String",
                StringList="StringList", Bool="Bool", Vector3="Vector3",
                Json="Json" },
}

local S = require('webui_signal')

local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass=pass+1; print(string.format("  [OK] %-44s %s", name, detail or ""))
  else fail=fail+1; print(string.format("  [XX] %-44s %s", name, detail or "")) end
end

--=============================================================================
print("=== 1. 类型规范化与推断 ===")
do
  local cases = {
    { "int", "int" }, { "Int", "int" }, { "integer", "int" },
    { "STRING", "string" }, { "bool", "bool" }, { "boolean", "bool" },
    { "vector3", "vector3" }, { "vec3", "vector3" },
    { "intlist", "intlist" }, { "json", "json" },
  }
  local bad = 0
  for i = 1, #cases do
    if S.normalizeType(cases[i][1]) ~= cases[i][2] then bad = bad + 1 end
  end
  check("类型别名规范化", bad == 0, string.format("%d 个不对", bad))
  check("未知类型返回 nil", S.normalizeType("nonsense") == nil)

  -- ★ 整数与小数必须分开：真机 Lua 5.3 有 math.type
  check("推断 int", S.inferType(5) == "int", S.inferType(5))
  check("推断 float", S.inferType(5.5) == "float", S.inferType(5.5))
  check("推断 string", S.inferType("a") == "string")
  check("推断 bool", S.inferType(true) == "bool")
  check("推断 vector3", S.inferType({x=1,y=2,z=3}) == "vector3")
  check("推断结构体 -> json", S.inferType({k=1}) == "json")
end

print()
print("=== 2. 类型校验（真机完全不校验，全靠这一层）===")
do
  local ok1 = S.checkType("int", 5)
  local ok2, why2 = S.checkType("int", 5.5)
  local ok3, why3 = S.checkType("int", "5")
  local ok4 = S.checkType("string", "x")
  local ok5, why5 = S.checkType("bool", 1)
  local ok6 = S.checkType("intlist", {1,2,3})
  local ok7, why7 = S.checkType("intlist", {1,"a"})
  local ok8 = S.checkType("vector3", {x=1,y=2,z=3})
  local ok9, why9 = S.checkType("vector3", {x=1})

  check("int 接受整数", ok1)
  check("int 拒绝小数", ok2 == false, tostring(why2))
  check("int 拒绝字符串", ok3 == false, tostring(why3))
  check("string 接受字符串", ok4)
  check("bool 拒绝数字", ok5 == false, tostring(why5))
  check("intlist 接受整数列表", ok6)
  check("intlist 拒绝混合", ok7 == false, tostring(why7))
  check("vector3 接受 xyz", ok8)
  check("vector3 拒绝缺字段", ok9 == false, tostring(why9))
end

print()
print("=== 3. 发送：参数顺序就是约定 ===")
do
  E.resetSent()
  local s = S.new{ signatures = {
    buy  = { "int", "int" },
    chat = { "string" },
    move = { "float", "vector3", "bool" },
  } }

  s:emit("buy",  1001, 3)
  s:emit("chat", "hello")
  s:emit("move", 1.5, {x=1,y=2,z=3}, true)
  check("emit 先进队列（不当场发）", E.sentCount() == 0,
      "已发 " .. E.sentCount())
  check("队列长度", s:queued() == 3, s:queued())

  s:flush()
  check("flush 后发出 3 条", E.sentCount() == 3, E.sentCount())

  -- ★★ 最关键的一条：顺序必须与签名一致
  local r = E.sent()
  local buy = nil
  for i = 1, #r do if r[i].name == "buy" then buy = r[i] end end
  check("buy 参数个数正确", buy and #buy.params == 2,
      buy and #buy.params)
  check("buy 第1个是 int", buy and buy.params[1] == 1001, buy and buy.params[1])
  check("buy 第2个是 int", buy and buy.params[2] == 3, buy and buy.params[2])

  local mv = nil
  for i = 1, #r do if r[i].name == "move" then mv = r[i] end end
  check("move 参数个数正确", mv and #mv.params == 3, mv and #mv.params)
  check("move 顺序: float,vector,bool",
      mv and mv.params[1] == 1.5 and mv.params[2].x == 1 and mv.params[3] == true)
end

print()
print("=== 4. 校验拦截（真机会静默发出去）===")
do
  E.resetSent()
  local s = S.new{ signatures = { buy = { "int", "int" } } }
  local okFew  = s:emit("buy", 1)
  local okMany = s:emit("buy", 1, 2, 3)
  local okType = s:emit("buy", "x", 2)
  s:flush()
  check("少参被拦", okFew == false)
  check("多参被拦", okMany == false)
  check("类型错被拦", okType == false)
  check("被拦的一条都没发出去", E.sentCount() == 0, E.sentCount())

  -- strict=false 时放行（要留给"服务端就是想要宽松"的场合）
  E.resetSent()
  local loose = S.new{ signatures = { buy = { "int", "int" } }, strict = false }
  local okLoose = loose:emit("buy", 1)
  loose:flush()
  check("strict=false 时放行", okLoose == true and E.sentCount() == 1)
end

print()
print("=== 5. 未声明签名：按值推断 + 形状变化告警 ===")
do
  E.resetSent()
  local s = S.new{}
  s:emit("raw", 1, "a")
  s:flush()
  check("没签名也能发", E.sentCount() == 1)
  local r = E.lastSent()
  check("推断出 int,string", #r.params == 2 and r.params[1] == 1)

  -- ★ 同一信号参数形状变了：真机完全静默，这里必须告警
  local before = s:stats_().warned
  s:emit("raw", 1.5, "a")
  s:flush()
  check("形状变化触发了告警", s:stats_().warned > before,
      string.format("%d -> %d", before, s:stats_().warned))
end

print()
print("=== 6. 冷却 / 限流（防 onTick 每帧狂发）===")
do
  E.resetSent()
  local s = S.new{ signatures = { tick = { "int" } } }
  s:flush()                        -- 进入下一帧
  s:emit("tick", 1)
  s:emit("tick", 2)
  s:emit("tick", 3)
  s:flush()
  check("同帧 3 条只发 1 条", E.sentCount() == 1, E.sentCount())
  check("合并计数为 2", s:stats_().duplicates == 2, s:stats_().duplicates)

  E.resetSent()
  s:emit("tick", 4); s:flush()
  s:emit("tick", 5); s:flush()
  check("跨帧各发一次", E.sentCount() == 2, E.sentCount())

  -- perFrame = nil -> 不限
  E.resetSent()
  local free = S.new{ signatures = { sp = { "int" } }, perFrame = 0 }
  free:flush()
  free:emit("sp", 1); free:emit("sp", 2)
  free:flush()
  check("perFrame=0 时不限流", E.sentCount() == 2, E.sentCount())
end

print()
print("=== 7. 接收：回调签名与解码 ===")
do
  local got = {}
  local s = S.new{ signatures = { hp = { "int", "float" } } }
  s:on("hp", function(a, b) got[#got+1] = { a, b } end)
  s:ready()

  -- ★ 真机回调是 fn(signalName, params) 两个参数
  local n = E.fireSignal("hp", { 100, 0.5 })
  check("引擎回调被分发", n == 1, n)
  check("handler 收到解码后的参数",
      #got == 1 and got[1][1] == 100 and got[1][2] == 0.5,
      got[1] and (tostring(got[1][1]) .. "," .. tostring(got[1][2])))

  -- 参数个数不符 -> 仍然调用，但要 warn
  local before = s:stats_().warned
  E.fireSignal("hp", { 1 })
  check("个数不符时告警", s:stats_().warned > before,
      string.format("%d -> %d", before, s:stats_().warned))

  -- raw 模式拿到原始数组
  local rawParams = nil
  local s2 = S.new{ signatures = { x = { "int" } } }
  s2:on("x", function(name, params) rawParams = params end, { raw = true })
  s2:ready()
  E.fireSignal("x", { 7, 8 })
  check("raw 模式拿到原始数组", rawParams and #rawParams == 2,
      rawParams and #rawParams)
end

print()
print("=== 8. 接收缓冲：信号早于 DOM 到达也不丢 ===")
do
  local order = {}
  local s = S.new{ signatures = { add = { "int" }, sub = { "int" } } }
  s:on("add", function(v) order[#order+1] = "add" .. v end)
  s:on("sub", function(v) order[#order+1] = "sub" .. v end)

  -- ready 之前到达
  E.fireSignal("add", { 10 })
  E.fireSignal("sub", { 3 })
  E.fireSignal("add", { 1 })
  check("未 ready 时不直接执行", #order == 0, #order)
  check("进了缓冲", s:pending() == 3, s:pending())

  local replayed = s:ready()
  check("ready 重放 3 条", replayed == 3, replayed)
  -- ★★ 顺序必须保持：先加后减不能变成先减后加
  check("重放保持到达顺序",
      table.concat(order, ",") == "add10,sub3,add1",
      table.concat(order, ","))

  -- ready 之后再来的直接执行
  E.fireSignal("add", { 5 })
  check("ready 后直接执行", #order == 4)

  -- 缓冲上限：满了丢最旧的，且要报出来
  local b = S.new{ signatures = { n = { "int" } }, buffer = 2 }
  b:on("n", function() end)
  E.fireSignal("n", { 1 })
  E.fireSignal("n", { 2 })
  E.fireSignal("n", { 3 })
  check("缓冲满时丢弃最旧", b:pending() == 2 and b:stats_().dropped == 1,
      string.format("pending=%d dropped=%d", b:pending(), b:stats_().dropped))
end

print()
print("=== 9. 字节预算 ===")
do
  E.resetSent()
  local s = S.new{ signatures = { big = { "string" } }, byteBudget = 64 }
  s:emit("big", string.rep("x", 200))
  s:flush()
  check("超预算的一条没发出去", E.sentCount() == 0, E.sentCount())
  check("字节预算告警", s:stats_().warned > 0, s:stats_().warned)
  -- ★ 超预算应该【顺延】而不是丢弃
  check("超预算的顺延到下一帧", s:queued() == 1, s:queued())

  E.resetSent()
  local ok = S.new{ signatures = { small = { "int" } }, byteBudget = 64 }
  ok:emit("small", 1)
  ok:flush()
  check("预算内正常发出", E.sentCount() == 1)
end

print()
print("=== 10. 条数预算：顺延不丢弃 ===")
do
  E.resetSent()
  local s = S.new{ signatures = { n = { "int" } }, frameBudget = 2, perFrame = 0 }
  for i = 1, 5 do s:emit("n", i) end
  s:flush()
  check("本帧只发 2 条", E.sentCount() == 2, E.sentCount())
  check("其余 3 条还在队列", s:queued() == 3, s:queued())
  s:flush()
  check("下一帧接着发", E.sentCount() == 4, E.sentCount())
end

print()
print("=== 11. 事件名索引（json 不支持非字符串键）===")
do
  E.resetSent()
  local s = S.new{ signatures = {
    buy_item = { "int", "int" },      -- ★ 事件本体也在 signatures 里
    hit      = { "int", "events" },   -- 事件 + 参数
  } }
  -- 事件名索引是【排序后】的，保证双端一致（pairs 顺序未定义）
  check("事件索引已建立", s.eventIdx and s.eventIdx["buy_item"] == 1,
      s.eventIdx and s.eventIdx["buy_item"])

  s:emit("hit", 7, { "buy_item", 1001, 3 })
  s:flush()
  local r = E.lastSent()
  -- 期望: [7, 事件序号, 参数个数, 参数...]
  -- ★ 事件名【不上线】——它被替换成【序号】。因为 json/int 列表
  --   要求元素同类型，塞不进字符串，双端只能靠 signatures 的
  --   排序位置对齐（见 buildEventIndex 的注释）。
  check("事件展开成 5 个参数", r and #r.params == 5, r and #r.params)
  check("事件序号正确", r and r.params[2] == 1, r and r.params[2])
  check("事件参数个数正确", r and r.params[3] == 2, r and r.params[3])
  check("事件参数原样带上",
      r and r.params[4] == 1001 and r.params[5] == 3,
      r and (tostring(r.params[4]) .. "," .. tostring(r.params[5])))

  -- ★ 没登记过的事件名必须被拦下（真机只会静默让服务端看不懂）
  local okBad = s:emit("hit", 7, { "no_such_event", 1 })
  check("未登记的事件名被拦下", okBad == false)
end

print()
print("=== 12. JSON 往返（真机没有 json 库）===")
do
  local samples = {
    { 1, 2, 3 },
    { a = 1, b = "x" },
    { list = { 1, 2 }, nested = { k = { "deep", true } } },
    { s = 'quote " and \\ backslash', nl = "a\nb" },
    { f = 1.5, i = 42, t = true },
    { "中文", "测试" },
  }
  local bad = 0
  for i = 1, #samples do
    local enc = S.toJSON(samples[i])
    local dec, err = S.fromJSON(enc)
    if err or type(dec) ~= "table" then
      bad = bad + 1
      print("      !! " .. tostring(err) .. "  <- " .. tostring(enc))
    end
  end
  check("6 个样本全部往返成功", bad == 0, string.format("%d 个失败", bad))

  -- 嵌套数组（这里曾经有递归调用 nil 的 bug：local 声明 + 全局赋值）
  local dec = S.fromJSON('{"a":[1,[2,3]],"b":{"c":{}}}')
  check("嵌套数组/对象可解析",
      dec and dec.a[2][2] == 3 and type(dec.b.c) == "table")
  -- 越深越好，确保递归到底
  check("深层嵌套可解析", S.fromJSON('[[[[[1]]]]]') ~= nil)

  local _, err = S.fromJSON("{bad json")
  check("坏 JSON 返回错误而不是抛异常", err ~= nil, tostring(err))

  -- 环引用不能爆栈
  local cyc = {}; cyc.self = cyc
  local okEnc = pcall(function() return S.toJSON(cyc) end)
  check("环引用不爆栈", okEnc)
end

print()
print("=== 13. 引擎 API 缺失 / 注册失败要报出来，不能静默 ===")
do
  -- script 不可用（模块里的 script 是模块自己的身份，真机上常发生）
  local noScript = S.new{ signatures = { a = { "int" } } }
  noScript.scriptObj = nil
  -- ★ 这里数的是"有没有告警输出"，不是 stats.warned ——
  --   注册失败发生在【模块层】，不经过实例的 warn 计数。
  local warned = false
  local util = require('webui_util')
  local origWarn = util.warn
  util.warn = function(...) warned = true end
  local ok = noScript:_ensureRegistered("a")
  util.warn = origWarn
  check("script 不可用时注册返回 false", ok == false)
  check("并且发出了告警", warned, tostring(warned))

  -- game.ServerSignal 不存在
  local saved = game.ServerSignal
  game.ServerSignal = nil
  local s = S.new{ signatures = { a = { "int" } } }
  local ok2, err2 = s:emitNow("a", 1)
  check("game.ServerSignal 缺失时失败并计数",
      ok2 == false and s:stats_().failed == 1, tostring(err2))
  game.ServerSignal = saved

  -- 发送抛异常也要计入 failed
  local s3 = S.new{ signatures = { a = { "int" } } }
  E.setSendHook(function() error("引擎炸了") end)
  local ok3 = s3:emitNow("a", 1)
  E.setSendHook(nil)
  check("发送异常计入 failed", ok3 == false and s3:stats_().failed == 1,
      s3:stats_().failed)
end

print()
print("=== 14. 解绑：引擎按名注册，不解绑会叠加 ===")
do
  -- RegisterServerSignalHandler 累积监听 -> fireSignal 会调多次
  local s = S.new{ signatures = { dup = { "int" } } }
  local count = 0
  s:on("dup", function() count = count + 1 end)
  s:ready()
  E.fireSignal("dup", { 1 })
  check("一个 handler 触发一次", count == 1, count)

  -- ★ 同一信号注册多次 handler，引擎侧仍只注册【一个】回调
  s:on("dup", function() count = count + 1 end)
  E.fireSignal("dup", { 1 })
  check("两个 handler 各触发一次（引擎回调没重复注册）", count == 3, count)

  local freed = s:destroy()
  check("destroy 解绑了 1 个信号", freed == 1, freed)
  local after = count
  E.fireSignal("dup", { 1 })
  check("解绑后不再触发", count == after, count)
end

print()
print("=== 15. 无状态便捷 API ===")
do
  E.resetSent()
  local ok = S.send("quick", 42, "tag")
  check("S.send 直接发出", ok == true and E.sentCount() == 1)
  local r = E.lastSent()
  check("S.send 参数正确", #r.params == 2 and r.params[1] == 42)

  local got = nil
  S.register("inbound", function(name, params) got = { name, params } end)
  E.fireSignal("inbound", { 9 })
  check("S.register 收到回调", got and got[1] == "inbound" and got[2][1] == 9)
  S.unregister("inbound")
  got = nil
  E.fireSignal("inbound", { 9 })
  check("S.unregister 后不再收到", got == nil)
end

print()
print("=== 16. 统计与诊断 ===")
do
  E.resetSent()
  local s = S.new{ signatures = { a = { "int" } } }
  s:on("a", function() end)
  s:ready()
  s:emit("a", 1); s:flush()
  E.fireSignal("a", { 2 })
  local st = s:stats_()
  check("统计: 发出 1", st.sent == 1, st.sent)
  check("统计: 收到 1", st.received == 1, st.received)
  check("统计: 帧号 >= 1", st.frame >= 1, st.frame)
  check("report() 能出一行", type(s:report()) == "string" and #s:report() > 10)
end

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
if fail > 0 then os.exit(1) end