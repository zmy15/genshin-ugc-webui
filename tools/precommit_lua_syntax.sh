#!/usr/bin/env bash
# Lua 语法检查（pre-commit 钩子）
#
# 接收 pre-commit 传入的一批 .lua 文件路径，逐个做语法检查。
# 只解析不执行，因此不会触发任何副作用（不会 require 模块）。
#
# 为什么需要这个钩子：
#   本项目的库跑在游戏沙箱里，语法错误在真机上的表现是静默失败
#   （关卡报 failed to load script），本地不检查很容易漏。
#
# 兼容性：
#   - 优先 luac -p（Lua 官方语法检查器，最准确）
#   - 没有 luac 时回落到 loadfile（经环境变量传路径，见下方说明）
#   - Windows(Git Bash) / Linux / macOS 均可运行
#
# 退出码：任一文件语法错误则返回 1。

set -u

# ---------- 挑选可用的 Lua 工具 ----------
LUAC=""
LUA=""

for cand in luac luac5.3 luac5.4 luac5.5 luac5.1; do
  if command -v "$cand" >/dev/null 2>&1; then LUAC="$cand"; break; fi
done

for cand in lua lua5.3 lua5.4 lua5.5 lua5.1; do
  if command -v "$cand" >/dev/null 2>&1; then LUA="$cand"; break; fi
done

if [ -z "$LUAC" ] && [ -z "$LUA" ]; then
  echo "错误：找不到 luac 或 lua，无法做语法检查。" >&2
  echo "  请安装 Lua（例如 apt-get install lua5.3）后重试。" >&2
  exit 1
fi

if [ -n "$LUAC" ]; then
  echo "使用 $LUAC -p 做语法检查"
else
  echo "使用 $LUA loadfile 做语法检查（未找到 luac）"
fi

# ---------- 逐个检查 ----------
rc=0
checked=0

for f in "$@"; do
  # 跳过不存在的文件（例如已删除但仍在索引里的条目）
  [ -f "$f" ] || continue
  checked=$((checked + 1))

  if [ -n "$LUAC" ]; then
    if ! err=$("$LUAC" -p "$f" 2>&1); then
      echo "语法错误: $f"
      [ -n "$err" ] && echo "$err"
      rc=1
    fi
  else
    # 只用 loadfile 编译不执行；失败时脚本自身 os.exit(1) 把退出码带出去。
    #
    # ★ 为什么用环境变量传路径，而不是 `lua -e '...' -- "$f"`：
    #   实测（Lua 5.5）`lua -e 'chunk' -- file.lua` 会把 file.lua 放进 arg[0]
    #   而不是 arg[1]，导致 loadfile(arg[1]) 拿到 nil，对**所有**正常文件都报错；
    #   更糟的是它还会把 file.lua 当脚本**执行**（有副作用）。
    #   用环境变量可以彻底避开引号与参数位置的坑。
    if ! out=$(LUA_CHECK_FILE="$f" "$LUA" -e 'local p = os.getenv("LUA_CHECK_FILE"); local c, e = loadfile(p); if not c then io.stderr:write(e or "unknown error"); os.exit(1) end' 2>&1); then
      echo "语法错误: $f"
      [ -n "$out" ] && echo "$out"
      rc=1
    fi
  fi
done

if [ "$rc" -eq 0 ]; then
  echo "语法检查通过（$checked 个文件）"
fi

exit $rc
