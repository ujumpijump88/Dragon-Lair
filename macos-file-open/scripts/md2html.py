#!/usr/bin/env python3
"""极简 markdown → HTML 转换器（零依赖，处理常用语法子集）。
用法: python3 md2html.py <input.md> <output.html>
处理: 标题 / 列表 / 表格 / fenced code / 行内 code/bold/link / hr / 段落。中文正常。
"""
import html
import re
import sys

def inline(s: str) -> str:
    s = html.escape(s, quote=False)
    def repl(m):
        t = m.group(0)
        if t.startswith('`'):
            return '<code>' + t[1:-1] + '</code>'
        if t.startswith('**'):
            return '<strong>' + t[2:-2] + '</strong>'
        inner, url = t[1:-1].split('](', 1)
        return f'<a href="{url[:-1]}">{inner}</a>'
    return re.sub(r'`[^`]+`|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\)', repl, s)

def convert(text: str) -> str:
    lines = text.split('\n')
    out, i, n = [], 0, len(lines)
    in_code, code_buf = False, []
    while i < n:
        line = lines[i]
        if line.strip().startswith('```'):
            if in_code:
                out.append('<pre><code>' + '\n'.join(code_buf) + '</code></pre>')
                code_buf, in_code = [], False
            else:
                in_code = True
            i += 1
            continue
        if in_code:
            code_buf.append(html.escape(line))
            i += 1
            continue
        if not line.strip():
            i += 1
            continue
        if line.startswith('|') and i + 1 < n and re.match(r'^\|[\s:|-]+\|?$', lines[i+1]):
            tbl, j = [], i
            while j < n and lines[j].strip().startswith('|'):
                cells = [c.strip() for c in lines[j].strip().strip('|').split('|')]
                tbl.append(cells)
                j += 1
            if len(tbl) >= 2:
                rows = ['<table>']
                for k, cells in enumerate(tbl):
                    tag = 'th' if k == 0 else 'td'
                    rows.append('<tr>' + ''.join(f'<{tag}>{inline(c)}</{tag}>' for c in cells) + '</tr>')
                rows.append('</table>')
                out.append(''.join(rows))
            i = j
            continue
        m = re.match(r'^(#{1,6})\s+(.*)$', line)
        if m:
            lvl = len(m.group(1))
            out.append(f'<h{lvl}>{inline(m.group(2))}</h{lvl}>')
            i += 1
            continue
        if re.match(r'^\s*[-*]\s+', line):
            items = []
            while i < n and re.match(r'^\s*[-*]\s+', lines[i]):
                items.append('<li>' + inline(re.sub(r'^\s*[-*]\s+', '', lines[i])) + '</li>')
                i += 1
            out.append('<ul>' + ''.join(items) + '</ul>')
            continue
        if re.match(r'^\s*\d+\.\s+', line):
            items = []
            while i < n and re.match(r'^\s*\d+\.\s+', lines[i]):
                items.append('<li>' + inline(re.sub(r'^\s*\d+\.\s+', '', lines[i])) + '</li>')
                i += 1
            out.append('<ol>' + ''.join(items) + '</ol>')
            continue
        if re.match(r'^\s*---+$', line):
            out.append('<hr>')
            i += 1
            continue
        out.append('<p>' + inline(line) + '</p>')
        i += 1
    return '\n'.join(out)

if __name__ == '__main__':
    src, dst = sys.argv[1], sys.argv[2]
    css = ("body{max-width:820px;margin:40px auto;padding:0 24px;font-family:-apple-system,'PingFang SC','Helvetica Neue',sans-serif;"
           "line-height:1.75;color:#1f2937;background:#fafaf8}"
           "h1{border-bottom:3px solid #f59e0b;padding-bottom:12px;color:#111827}"
           "h2{border-bottom:1px solid #e5e7eb;padding-bottom:6px;margin-top:36px;color:#111827}"
           "code{background:#f3f4f6;padding:2px 6px;border-radius:4px;font-size:90%}"
           "pre{background:#111827;color:#e5e7eb;padding:16px;border-radius:10px;overflow-x:auto}"
           "pre code{background:none;color:inherit}"
           "table{border-collapse:collapse;width:100%;margin:16px 0}"
           "th,td{border:1px solid #d1d5db;padding:8px 12px;text-align:left}"
           "th{background:#fef3c7}blockquote{border-left:4px solid #f59e0b;margin:0;padding:4px 16px;background:#fffbeb}")
    html_doc = (f"<!DOCTYPE html><html lang='zh'><head><meta charset='utf-8'>"
                f"<title>{html.escape(src)}</title><style>{css}</style></head>"
                f"<body>{convert(open(src, encoding='utf-8').read())}</body></html>")
    with open(dst, 'w', encoding='utf-8') as f:
        f.write(html_doc)
    print(f"OK: {dst}")
