# -*- coding: utf-8 -*-
"""Verify every API identifier in the source text appears in the generated Markdown.

用法:
    python tools/ugc_verify.py <article.txt 路径>

若不传参数，则尝试用环境变量 UGC_ARTICLE，其次找同目录下的 article.txt。
生成的 Markdown 固定取仓库的 docs/client_control_api.md。
"""
import re, io, os, sys

_HERE = os.path.dirname(os.path.abspath(__file__))
SRC = (sys.argv[1] if len(sys.argv) > 1
       else os.environ.get("UGC_ARTICLE")
       or os.path.join(_HERE, "article.txt"))
MD = os.path.join(os.path.dirname(_HERE), "docs", "client_control_api.md")

src = io.open(SRC, encoding="utf-8-sig").read().replace("\u200b", "")
md = io.open(MD, encoding="utf-8").read()

# 1) all Enum.<Name> identifiers in source
enums = set(re.findall(r"Enum\.[A-Za-z][A-Za-z0-9_]*", src))
missing_enums = sorted(e for e in enums if e not in md)
print("enum identifiers in source:", len(enums), "| missing in md:", len(missing_enums))
for e in missing_enums[:20]:
    print("   MISSING", e)

# 2) all game.Xxx( calls
games = set(re.findall(r"game\.[A-Za-z][A-Za-z0-9_]*", src))
missing_games = sorted(g for g in games if g not in md)
print("game.* in source:", len(games), "| missing:", len(missing_games), missing_games)

# 3) all Color.Xxx / math.xxx / Tween / TweenSequence / ServerSignal / CursorEventData members
for pfx in ["Color.", "math.", "Tween:", "TweenSequence:", "ServerSignal:", "CursorEventData:",
            "script:"]:
    found = set(re.findall(re.escape(pfx) + r"[A-Za-z][A-Za-z0-9_]*", src))
    miss = sorted(f for f in found if f not in md)
    print(f"{pfx:20s} in source: {len(found):3d} | missing: {len(miss)} {miss}")

# 4) control field/method names inside ClientUI sections -- coarse check on identifiers
idents = set(re.findall(r"\b(Get|Set|Add|Remove|Refresh|Scroll|Simulate|Play|Stop)"
                        r"[A-Za-z0-9_]*\(", src))
miss = sorted(i for i in idents if i[:-1] not in md)
print("Method-like identifiers:", len(idents), "| missing:", len(miss), miss[:25])
