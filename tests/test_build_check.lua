--[[ 验证 tools/build.lua --check 真的能发现"过期产物"。

      ★ 为什么需要这个套件：
        --check 原来只打印"将生成 N 字节"就 return，从不读磁盘上的
        bundle，任何情况都 exit 0 —— 而 .github/workflows/tests.yml 把它
        当成了防线，于是成了一枚【永远不会红】的假绿勾。
        现在换成真比对，但这个能力【本身必须有测试】：
        否则下次有人把它改回空转，仍然没有任何东西会报警。

      覆盖三条分支（与 build.lua 里的注释一一对应）：
        1. 产物与源码一致                 -> exit 0，输出 [OK]
        2. 产物过期（末尾多一行 / 中间改一行）-> exit 1，且能报出首个差异行
        3. 产物不存在（全新克隆场景）      -> exit 0，输出 [跳过]

      ★ 必须在【子进程】里跑 build.lua：
        它不一致时会 os.exit(1)，在进程内调用会把本测试一起带走。

      ★ 本套件会故意改坏 bundle/webui.lua，所以每一步之后都重建恢复；
        收尾再兜底重建一次，绝不给仓库留下过期产物。

      跑法：lua tests/test_build_check.lua（任何目录都可，内部自己 cd 到仓库根）
]]--

local _here = (arg and arg[0] or ""):gsub(string.char(92), "/")
local _root = _here:match("^(.*)/tests/") or "."

--[[ 兜底：在 tests/ 里直接 `lua test_build_check.lua`（arg[0] 不含 "/tests/"）时，
      _root 会退化成本目录 —— 那样 build.lua 找不到 lib/webui。
      往上找一层"带 tools/build.lua 的目录"来定位仓库根。 ]]
local function hasFile(p)
  local f = io.open(p, "rb")
  if f then f:close(); return true end
  return false
end
if not hasFile(_root .. "/tools/build.lua") and hasFile("../tools/build.lua") then
  _root = ".."
end

package.path = _root .. "/tests/?.lua;" .. package.path

local FS = require('fs_util')

--=============================================================================
-- 断言框架（与 test_bundle.lua 一致）
--=============================================================================
local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1; print(string.format("  [OK] %-34s %s", name, detail or ""))
  else fail = fail + 1; print(string.format("  [XX] %-34s %s", name, detail or "")) end
end

--=============================================================================
-- 找一个能跑 build.lua 的 Lua 解释器
--=============================================================================
local function q(s) return '"' .. tostring(s) .. '"' end

local candidates = {}
if arg and arg[-1] then candidates[#candidates + 1] = q(arg[-1]) end  -- ★ 正在跑本测试的那个
for _, n in ipairs({ "lua", "lua5.3", "lua5.4", "lua5.5" }) do
  candidates[#candidates + 1] = n
end

local LUA = nil
for _, exe in ipairs(candidates) do
  -- ★ 用 -v 而不是 --version：Lua 5.3 没有 --version（会 exit 1）
  local probe = os.execute(exe .. " -v" .. FS.SILENT)
  if probe == 0 or probe == true then LUA = exe; break end
end

if not LUA then
  print("!! 找不到 Lua 解释器（试过: " .. table.concat(candidates, ", ") .. "）")
  print("   本套件需要在子进程里跑 tools/build.lua，无法在本进程内替代。")
  os.exit(1)
end
print("(解释器: " .. LUA .. ")")

-- cd 到仓库根 —— build.lua 用相对路径找 lib/webui 与 bundle/
local CD = "cd " .. q(FS.IS_WINDOWS and (_root:gsub("/", "\\")) or _root) .. " && "

--[[ 跑一条命令，返回 成功?, 合并后的输出, 退出码。

     ★ 不能只看输出 —— 要退出码。
       io.popen 的 close 在 5.1 返回数字，在 5.3+ 返回 (true|nil, "exit", code)。
]]--
local function run(cmd)
  local p = io.popen(CD .. cmd .. " 2>&1")
  if not p then return false, "", nil end
  local out = p:read("*a") or ""
  local ok, _, code = p:close()
  return (ok == true or ok == 0), out, code
end

local function rebuild()
  return run(LUA .. " tools/build.lua")
end

local BUNDLE = _root .. "/bundle/webui.lua"
local BAK    = BUNDLE .. ".bak_test"
local MARK   = "-- STALE MARKER (test_build_check)"

--[[ 致命错误出口：先把现场恢复（重建 bundle），再非零退出。 ]]--
local function bail(msg)
  fail = fail + 1
  print(string.format("  [XX] %-34s %s", "致命错误", msg))
  print()
  print("  正在重建 bundle 恢复现场 ...")
  local _, out = rebuild()
  print(out)
  print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
  os.exit(1)
end

--=============================================================================
-- 1. 一致：先重建，再 --check
--=============================================================================
print()
print("=== 1. 产物一致时 --check 应通过 ===")

local okBuild, outBuild = rebuild()
if not okBuild then
  bail("重建 bundle 失败:\n" .. outBuild)
end
check("重建 bundle 成功", okBuild, "exit 0")

local ok1, out1, code1 = run(LUA .. " tools/build.lua --check")
check("--check 退出码 = 0", ok1 == true, "code=" .. tostring(code1))
check("输出标记 [OK]", out1:find("%[OK%]") ~= nil,
    (out1:find("%[OK%]") and "有" or "无"))

local fresh = FS.read(BUNDLE)
if not fresh then bail("读不到 " .. BUNDLE .. "（bundle/ 可能没构建成功）") end
local freshLines = select(2, fresh:gsub("\n", "")) + 1

--=============================================================================
-- 2a. 过期：末尾多一行
--=============================================================================
print()
print("=== 2a. 产物末尾多一行（过期）应被检出 ===")

--[[ ★ 注意：bundle 末尾【没有】换行（build.lua 是 join("\n") 拼的），
       所以这里必须先补一个 \n 才是"多出一行"；直接拼字符串会粘在末行上，
       那就变成"末行被改"而不是"多一行"了。 ]]
if FS.write(BUNDLE, fresh .. "\n" .. MARK) == nil then
  bail("写不进 " .. BUNDLE)
end

local ok2, out2, code2 = run(LUA .. " tools/build.lua --check")
check("--check 退出码 = 1", ok2 == false and (code2 == 1 or code2 == nil),
    "code=" .. tostring(code2))
check("输出标记 [已过期]", out2:find("已过期") ~= nil,
    (out2:find("已过期") and "有" or "无"))
check("报出差异内容", out2:find("STALE MARKER", 1, true) ~= nil,
    (out2:find("STALE MARKER", 1, true) and "有" or "无"))

-- 报出的首个差异行 = 新加的那一行（原行数 + 1）
local reported2 = tonumber(out2:match("首个差异在第 (%d+) 行"))
check("首个差异行 = 末行", reported2 == freshLines + 1,
    string.format("报出 %s，期望 %d", tostring(reported2), freshLines + 1))

local okR1 = rebuild()
check("重建后恢复原样", okR1 == true and FS.read(BUNDLE) == fresh, "")

--=============================================================================
-- 2b. 过期：改动【中间】一行 —— 验证它不只会看末尾
--=============================================================================
print()
print("=== 2b. 产物中间被改一行（过期）应能定位 ===")

local anchor = "local __webui_loaders = {}"
local edited, n = fresh:gsub(anchor, anchor .. " -- EDITED", 1)
if n ~= 1 then
  bail("找不到锚点文本（bundle 结构变了？）: " .. anchor)
end

-- 算出被改的是第几行（行号与 build.lua 的 splitLines 一致）
local expectedLine = nil
do
  local i = 0
  for line in (edited .. "\n"):gmatch("(.-)\n") do
    i = i + 1
    if line:find("-- EDITED", 1, true) then expectedLine = i; break end
  end
end

if FS.write(BUNDLE, edited) == nil then bail("写不进 " .. BUNDLE) end

local ok3, out3, code3 = run(LUA .. " tools/build.lua --check")
check("--check 退出码 = 1", ok3 == false and (code3 == 1 or code3 == nil),
    "code=" .. tostring(code3))

local reported3 = tonumber(out3:match("首个差异在第 (%d+) 行"))
check("定位到中间那一行", reported3 == expectedLine,
    string.format("报出 %s，实际改动在第 %s 行", tostring(reported3), tostring(expectedLine)))
check("差异行数 = 1", out3:match("差异行数 1，") ~= nil,
    "差异行数 " .. tostring(out3:match("差异行数 (%d+)")))

local okR2 = rebuild()
check("重建后恢复原样", okR2 == true and FS.read(BUNDLE) == fresh, "")

--=============================================================================
-- 3. 产物不存在：不算过期，应 [跳过]
--=============================================================================
print()
print("=== 3. 产物不存在时应跳过（全新克隆场景）===")

os.remove(BAK)
local moved = os.rename(BUNDLE, BAK)
if not moved then
  bail("无法把 bundle 挪走（os.rename 失败）")
end

local ok4, out4, code4 = run(LUA .. " tools/build.lua --check")

-- ★ 先放回现场再断言 —— 断言再要紧，也不能把仓库撂在坏状态
local back = os.rename(BAK, BUNDLE)

check("退出码 = 0（不存在 != 过期）", ok4 == true, "code=" .. tostring(code4))
check("输出标记 [跳过]", out4:find("%[跳过%]") ~= nil,
    (out4:find("%[跳过%]") and "有" or "无"))
check("产物已放回原处", back == true and FS.exists(BUNDLE), "")

--=============================================================================
-- 收尾：仓库里必须留下"与源码一致"的产物
--=============================================================================
print()
print("=== 收尾 ===")
local okFinal = rebuild()
local okCheck, outCheck = run(LUA .. " tools/build.lua --check")
check("最终产物与源码一致",
    okFinal == true and okCheck == true and FS.read(BUNDLE) == fresh, "")
check("临时备份已清理", not FS.exists(BAK), "")

if fail > 0 then
  print()
  print("--- 最后一次 --check 输出 ---")
  print(outCheck)
end

print()
print(string.format("=== 合计: %d 通过, %d 失败 ===", pass, fail))
os.exit(fail > 0 and 1 or 0)
