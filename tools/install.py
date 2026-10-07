# -*- coding: utf-8 -*-
"""把 webui 装进千星工程的 external_lua_file 目录。

★ 本质就是「复制」，不做任何改名或改写。

  为什么可以这么简单：
    lib/webui/ 里的文件名与 require 已经是【真机可直接用】的扁平形式：
      lib/webui/webui.lua        <- 入口
      lib/webui/webui_util.lua   <- require('webui_util')
      lib/webui/webui_clip.lua   <- require('webui_clip')
      ...
    真机的 require 规则是「同目录 + 文件名原样」（require('webui_util')
    找的就是 webui_util.lua），所以整个文件夹拷进去就能用。

用法:
    python tools/install.py "<external_lua_file 目录>"

例如:
    python tools/install.py "C:/.../Beyond_Local_Save_Level/1073741828/external_lua_file"

可选:
    --no-sample       不放起始页（只要库）
    --name=xxx.lua    起始页文件名（默认 main.lua）
"""

import argparse
import os
import shutil
import sys

# ---------------------------------------------------------------------------
# 路径：源文件按【脚本所在位置】解析（仓库根 = tools/ 的上一级），
#       这样从任何工作目录调用都能找到库；
#       目标目录按【调用者的工作目录】解析（符合直觉）。
# ---------------------------------------------------------------------------

_HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(_HERE)

LIB_DIR = os.path.join(REPO_ROOT, "lib", "webui")

# 库文件（必须与 lib/webui 下的实际文件名一致）
LIB_FILES = [
    "webui.lua",
    "webui_util.lua", "webui_dom.lua", "webui_html.lua", "webui_css.lua",
    "webui_color.lua", "webui_style.lua", "webui_transition.lua",
    "webui_layout.lua", "webui_render.lua", "webui_clip.lua", "webui_event.lua",
]

SAMPLE_SRC = os.path.join(REPO_ROOT, "deploy", "my_page.lua")
GUIDE_SRC = os.path.join(_HERE, "install_guide.md")

# 说明文件的输出名。
# ★ 用 ASCII 名：中文文件名在 Windows 上容易因编码不一致而变成乱码。
#   （Lua 版实测「使用说明.md」被写成「浣跨敤璇存槑.md」。）
GUIDE_NAME = "README-webui.md"


def _copy_binary(src, dst):
    """按字节复制。

    ★ 必须二进制复制而不是「读成文本再写回」：
      那样会动到行尾（CRLF/LF）与 BOM，导致部署产物与仓库不一致。
      测试里用 MD5 逐字节比对，正是为了盯住这一点。
    """
    with open(src, "rb") as f:
        data = f.read()
    with open(dst, "wb") as f:
        f.write(data)
    return len(data)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="把 webui 库 / 起始页 / 使用说明装到 external_lua_file 目录",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("target", help="external_lua_file 目录")
    parser.add_argument("--no-sample", action="store_true",
                        help="不放起始页")
    parser.add_argument("--no-guide", action="store_true",
                        help="不放使用说明")
    parser.add_argument("--name", default="main.lua",
                        help="起始页文件名（默认 main.lua）")
    args = parser.parse_args(argv)

    target = os.path.abspath(os.path.expanduser(args.target))
    sample_name = args.name

    print("================================================================")
    print(" webui 安装器")
    print("================================================================")
    print("目标目录: " + target)
    print()

    # 目标目录必须存在 —— 路径打错时给出明确提示，而不是一堆写入失败
    if not os.path.isdir(target):
        print("!! 目标目录不存在:")
        print("   " + target)
        print()
        print("   请确认路径正确、且已经在编辑器里创建过关卡。")
        return 1

    problems = []

    # -----------------------------------------------------------------------
    # 1. 库：直接复制（内容一字节不改）
    # -----------------------------------------------------------------------
    print("---- [1/3] 复制库 ----")
    print()

    copied = 0
    for name in LIB_FILES:
        src = os.path.join(LIB_DIR, name)
        dst = os.path.join(target, name)
        if not os.path.isfile(src):
            problems.append("找不到 " + src)
            print("  x %-22s 源文件不存在" % name)
            continue
        try:
            n = _copy_binary(src, dst)
            copied += 1
            print("  + %-22s %6d 字节" % (name, n))
        except OSError as e:
            problems.append("写不进 %s: %s" % (dst, e))
            print("  x %-22s 写入失败: %s" % (name, e))

    print()
    print("  库文件: %d/%d" % (copied, len(LIB_FILES)))

    # -----------------------------------------------------------------------
    # 2. 起始页
    # -----------------------------------------------------------------------
    print()
    print("---- [2/3] 复制起始页 ----")
    print()

    if args.no_sample:
        print("  (--no-sample：跳过)")
    elif not os.path.isfile(SAMPLE_SRC):
        problems.append("找不到起始页模板 " + SAMPLE_SRC)
        print("  x 找不到 " + SAMPLE_SRC)
    else:
        dst = os.path.join(target, sample_name)
        try:
            n = _copy_binary(SAMPLE_SRC, dst)
            print("  + %-22s %6d 字节" % (sample_name, n))
            print()
            print("  ★ 这个就是要改的文件。")
            print("     除底部 3 行生命周期接线，其余全是 HTML / CSS / 事件处理。")
        except OSError as e:
            problems.append("写不进 %s: %s" % (dst, e))
            print("  x 写入失败: %s" % e)

    # -----------------------------------------------------------------------
    # 3. 使用说明
    # -----------------------------------------------------------------------
    print()
    print("---- [3/3] 复制使用说明 ----")
    print()

    if not args.no_guide and not os.path.isfile(GUIDE_SRC):
        problems.append("找不到说明模板 " + GUIDE_SRC)
        print("  x 找不到 " + GUIDE_SRC)
    elif args.no_guide:
        print("  (--no-guide：跳过)")
    else:
        # 说明是文本，要替换占位符。
        # ★ 显式 utf-8 + newline="" ：不做任何换行转换，保持原样。
        with open(GUIDE_SRC, "r", encoding="utf-8", newline="") as f:
            guide = f.read()
        guide = guide.replace("@SAMPLE@", sample_name)

        dst = os.path.join(target, GUIDE_NAME)
        try:
            with open(dst, "w", encoding="utf-8", newline="") as f:
                f.write(guide)
            print("  + %-22s %6d 字节" % (GUIDE_NAME, len(guide.encode("utf-8"))))
        except OSError as e:
            problems.append("写不进 %s: %s" % (dst, e))
            print("  x 写入失败: %s" % e)

    # -----------------------------------------------------------------------
    print()
    print("================================================================")

    if problems:
        print(" 有问题：")
        for p in problems:
            print("   - " + p)
        print("================================================================")
        return 1

    print(" 安装完成")
    print("================================================================")
    print()
    print("接下来（这两步不能省，否则进游戏看不到东西）：")
    print("  1. 打开千星编辑器，把 external_lua_file 里的脚本【导入】到关卡。")
    print("     真机读的是关卡文件 .gil，不是这个文件夹 ——")
    print("     只复制文件不导入是不生效的。")
    print("  2. 给容器 / 文本框 / 按钮 / 图片各建一个控件模板，")
    print("     把它们在编辑器里显示的索引号填进 %s 的 prefabs。" % sample_name)
    print()
    print("之后进游戏就能看到起始页。想改成自己的界面：")
    print("只改 %s 里的 HTML / CSS / 事件即可，库不用动。" % sample_name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
