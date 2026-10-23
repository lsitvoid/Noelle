#!/usr/bin/env python3
"""
把 noelle.real 里的终端标题从 Miyu 改为 NOEL。

原理
----
标题在代码段里由一条指令直接写入：

    c7 00 4d 69 79 75     mov dword [rax], 0x7579694D   # "Miyu"
    48 c7 84 24 e0 01 00 00 04 00 00 00   mov qword [rsp+0x1e0], 4
    48 c7 84 24 f0 01 00 00 04 00 00 00   mov qword [rsp+0x1f0], 4

字符串字面量直接编进指令的立即数，长度为 4，硬编码在两处 mov 里。
因此**只能换成 4 个 ASCII 字符**，不能变长（变长需重写指令与重定位）。

用法
----
    python3 tools/patch-title.py bin/noelle.real NOEL
    python3 tools/patch-title.py bin/noelle.real --revert
"""

import sys
import pathlib

# 特征字节序列：mov dword [rax], 0x7579694D  ("Miyu")
SIGNATURE = bytes.fromhex("c700") + b"Miyu"
REPLACEMENT_NAME = "NOEL"


def find_all(data: bytes):
    pos, start = [], 0
    while True:
        i = data.find(SIGNATURE, start)
        if i < 0:
            break
        pos.append(i)
        start = i + 1
    return pos


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2

    path = pathlib.Path(sys.argv[1])
    if not path.is_file():
        print(f"[错误] 文件不存在: {path}", file=sys.stderr)
        return 1

    revert = "--revert" in sys.argv
    new = "Miyu" if revert else (sys.argv[2] if len(sys.argv) > 2 else REPLACEMENT_NAME)

    if len(new) != 4 or not new.isascii() or not new.isprintable():
        print(f"[错误] 必须是 4 个可打印 ASCII 字符，收到: {new!r}", file=sys.stderr)
        return 1

    data = bytearray(path.read_bytes())
    hits = find_all(bytes(data))

    if not hits:
        # 已经是目标名或签名不匹配
        if bytes(data).find(b"NOEL") >= 0:
            print("[跳过] 未找到 Miyu 签名，可能已打过补丁")
            return 0
        print("[警告] 未找到标题写入指令，上游结构可能已变", file=sys.stderr)
        return 1

    for i in hits:
        data[i + 2 : i + 6] = new.encode("ascii")

    path.write_bytes(bytes(data))
    path.chmod(0o755)
    print(f"[完成] {len(hits)} 处标题 → {new}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
