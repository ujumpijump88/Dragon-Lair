#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 Apple Pages (.pages / iWork IWA) 提取正文文本（v2）
纯 Python raw-snappy 解压 + protobuf length-delimited 字段的外层优先抽取。
用法: python3 pages_text.py a.pages b.pages
"""
import sys, zipfile, re, os


def snappy(data: bytes, pos: int = 0):
    n = len(data); length = 0; shift = 0; i = pos
    while True:
        if i >= n: return b''
        b = data[i]; i += 1
        length |= (b & 0x7F) << shift
        if not (b & 0x80): break
        shift += 7
        if shift > 35: return b''
    out = bytearray()
    while i < n and len(out) < length:
        tag = data[i]; i += 1
        t = tag & 3
        if t == 0:
            x = tag >> 2
            if x < 60:
                ln = x + 1
            else:
                nb = x - 59
                ln = int.from_bytes(data[i:i + nb], 'little') + 1
                i += nb
            out += data[i:i + ln]; i += ln
        else:
            if t == 1:
                ln = ((tag >> 2) & 7) + 4
                off = ((tag >> 5) << 8) | data[i]; i += 1
            elif t == 2:
                ln = (tag >> 2) + 1
                off = int.from_bytes(data[i:i + 2], 'little'); i += 2
            else:
                ln = (tag >> 2) + 1
                off = int.from_bytes(data[i:i + 4], 'little'); i += 4
            s = len(out) - off
            if s < 0: break
            for k in range(ln):
                out.append(out[s + k])
    return bytes(out)


CJK = re.compile(r'[\u4e00-\u9fff]')


def text_fields(raw: bytes):
    """收集所有能解码为 UTF-8 且有中文的 length-delimited 字段，外层优先"""
    n = len(raw)
    cands = []
    for p in range(n - 1):
        if (raw[p] & 0x07) != 2:
            continue
        j = p + 1; vl = 0; sh = 0; ok = False
        while j < n and sh < 35:
            c = raw[j]; j += 1
            vl |= (c & 0x7F) << sh; sh += 7
            if not (c & 0x80):
                ok = True; break
        if not ok or vl < 2 or j + vl > n or vl > 400000:
            continue
        chunk = raw[j:j + vl]
        try:
            s = chunk.decode('utf-8')
        except UnicodeDecodeError:
            continue
        if CJK.search(s):
            cands.append((j, j + vl, s))
    # 外层优先：按起点排序，若被前一个已选区间包含则跳过
    cands.sort(key=lambda x: (x[0], -(x[1] - x[0])))
    picked = []
    last_end = -1
    for a, b, s in cands:
        if a >= last_end:
            picked.append((a, b, s))
            last_end = b
    return picked


def extract(path: str) -> str:
    with zipfile.ZipFile(path) as z:
        blob = z.read('Index/Document.iwa')
    raw = snappy(blob, 4)
    picked = text_fields(raw)
    seen = set()
    out = []
    for a, b, s in picked:
        for line in s.split('\n'):
            line = line.strip()
            if not line or line in seen:
                continue
            if not CJK.search(line) and len(line) < 4:
                continue
            seen.add(line)
            out.append(line)
    return '\n'.join(out)


if __name__ == '__main__':
    for p in sys.argv[1:]:
        t = extract(p)
        dst = os.path.splitext(p)[0] + '.txt'
        with open(dst, 'w', encoding='utf-8') as f:
            f.write(t)
        print(f'{os.path.basename(p)} -> {os.path.basename(dst)}  {len(t)} 字符')
