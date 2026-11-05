---
name: openpyxl-workbooks
description: "Build/verify xlsx with openpyxl when LibreOffice is absent."
version: 1.0.0
author: Hermes curator
license: Proprietary
platforms: [macos, linux, windows]
metadata:
  hermes:
    tags: [Excel, XLSX, openpyxl, formulas, verification, CJK]
    category: productivity
    related_skills: [xlsx, china-network-setup]
---

# openpyxl Workbooks (no-LibreOffice verification + CJK forms)

Companion to the bundled `xlsx` skill. The bundled skill's `scripts/recalc.py` requires LibreOffice (`soffice`); on machines without it (this Mac has only Apple Numbers — no soffice/Excel/WPS), **verify formulas with the Python `formulas` library instead**. Also carries openpyxl patterns for Chinese administrative forms (岗位评估/评分表, 汇总表).

## When to use
- Building/editing an .xlsx with openpyxl where formulas must be verified but LibreOffice is unavailable.
- Chinese office deliverables: scoring forms (评分表), evaluation sheets, work-plan sheets — one form per entity (e.g. per 岗位), scoring standards inlined next to score cells so raters don't flip sheets.

## Environment (this Mac)
- Project venv: `/Users/xiebojun/Hermes/.venv` (py3.11 via `~/.hermes/bin/uv`). Install deps from Aliyun mirror:
  `UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/ ~/.hermes/bin/uv pip install --python .venv/bin/python openpyxl formulas`
- **Run scripts via terminal with `.venv/bin/python script.py` — NOT execute_code.** The execute_code sandbox interpreter does not see project-venv packages (openpyxl → ModuleNotFoundError). Write a `.py` file, run it from terminal.
- `NO_PROXY=localhost,127.0.0.1` for any Python/httpx hitting local services.

## Build patterns (validated gotchas)
1. **Style helpers must handle single-cell refs.** `ws["B5"]` returns a Cell; `ws["B5:C6"]` returns tuple-of-tuples. A `style_range`/`set_merged` helper that only iterates rows breaks on single-cell ranges — branch on `":" in rng` (apply() to one cell vs. loop rows).
2. **`ws.sheet_properties.tabColor` takes ONE color string per sheet** — assign in a loop (`for ws, color in zip(...)`), never pass a list (TypeError: 'should be Color but value is list').
3. **ASCII `\"` at the end of a double-quoted Python string is an escape, not a terminator** — a Chinese string like `把"维度标准"与` inside `"..."` produces a confusing SyntaxError on the NEXT line. Use fullwidth 「」 or “” for CJK quoting.
4. **Per-row DataValidation for score cells** (max differs per row):
   `DataValidation(type="whole", operator="between", formula1="0", formula2=str(full), allow_blank=True, showErrorMessage=True, errorTitle=..., error=...)` then `ws.add_data_validation(dv); dv.add(f"E{row}")`.
5. **CJK row-height estimation**: CJK glyph ≈ 2 char widths; lines ≈ `ceil(len(line)/width_chars)`; height ≈ `lines × (font_pt+3.2) + 6`. openpyxl does NOT auto-fit row heights.
6. **Print setup for one-page-wide forms**: `page_setup.orientation="landscape"`, `paperSize=9` (A4), `fitToWidth=1`, `fitToHeight=0`, AND `sheet_properties.pageSetUpPr.fitToPage = True` (without it fitToWidth is ignored), plus `print_title_rows="1:6"`, `freeze_panes="A7"`.
7. **openpyxl writes formulas with no cached values** → `load_workbook(data_only=True)` / pandas see `None` until the file is opened+recalculated. Excel/WPS/Numbers compute on open, so delivery is fine — but verify first (below) and tell the user numbers appear once opened.
8. Read-side: `read_file` on an .xlsx auto-extracts sheet-by-sheet text — fast way to map an existing workbook (sheet names, headers, sample rows) before writing code.

## Verification without LibreOffice (formulas lib)
1. `pip install formulas` (env command above; pulls numpy/schedula/tqdm).
2. Work on a COPY: fill known/sample inputs via openpyxl, save tmp file. Never modify the deliverable with samples.
3. `xl = formulas.ExcelModel().loads(tmp).finish(); sol = xl.calculate()` → dict of every formula cell.
4. **Key format gotcha**: keys look like `"'[_file.xlsx]行政管理岗'!E11"` — single quote sits between sheet name and `!`. Match with `k.endswith(f"{sheet}'!{cell}")`.
5. **Value unwrapping**: XlCell wrappers → `.value`/`.to_python()`; numpy arrays → `.item()` for size-1.
6. Cross-check computed values against known expectations (e.g. an existing workbook's cached values); scan ALL solutions for `#`-prefixed error strings.
7. Validated 2026-08: 7 sheets × ~13 SUM/IF formulas, 1002 solution cells, zero errors, 7/7 matched the source workbook's values (e.g. 人力资源管理岗 84分/B级/下山型).

## User conventions (this user)
- Chinese office/HR deliverables: respond in Chinese; deliver the .xlsx AND a structured 工作开展计划 (phases → 责任主体 → 时间安排 → 输出物, plus 里程碑/风险) — both as a workbook sheet and summarized in chat.
- Form style: yellow fill = input cells, gray = auto-calc, light blue = dimension group cells; dark blue title bar; standards inlined in the form.

## Pitfalls
- formulas lib prints numpy SyntaxWarnings ("is with literal") + tqdm progress bars — noise; filter `grep -vE "Warning|it/s"`.
- Never `write_back()` with formulas lib on a styled deliverable — it rewrites the workbook and can drop openpyxl styling. Read-only verification only.
- Deliver blank input cells (no sample scores) in the final form; samples only in the temp verification copy.

## Stream-XLSX from Flask (data export pattern, NOT form-building)

Different from the form pattern above. When you have a Flask endpoint serving **generated data** (e.g. meal-plan export, financial summary, log dump) as `.xlsx`:

```python
from io import BytesIO
from flask import Response
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

@app.route("/api/<id>/export")
def export(id):
    wb = Workbook()
    wb.remove(wb.active)                                # delete default Sheet
    ws = wb.create_sheet("Detail")
    header_font = Font(bold=True)
    health_fill = PatternFill("solid", fgColor="C6F6D5")
    ws.append(["col1", "col2", "is_special"])
    for cell in ws[1]:
        cell.font = header_font
    for row in rows:
        ws.append([row.x, row.y, "✓" if row.special else ""])
        if row.special:
            for col in range(1, 4):
                ws.cell(row=ws.max_row, column=col).fill = health_fill
    bio = BytesIO()
    wb.save(bio)
    bio.seek(0)
    return Response(bio.getvalue(),
                    mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    headers={"Content-Disposition":
                             f"attachment; filename={id}.xlsx"})
```

Frontend trigger:
```js
const a = document.createElement('a');
a.href = '/api/X/export?format=xlsx';
a.download = 'report.xlsx';
document.body.appendChild(a); a.click(); document.body.removeChild(a);
```

**Gotchas specific to this pattern**:
- `wb.remove(wb.active)` is required — `Workbook()` creates a default "Sheet". Otherwise the workbook has both default + your first named sheet.
- `font_color` for "is_special" / boolean indicators: use a Unicode check (✓ / ✗) + `PatternFill` row-coloring rather than building conditional formatting rules (which openpyxl supports but doesn't ship evaluated values).
- `Content-Disposition: attachment` is what forces download. Without it, the browser may render the .xlsx inline (modern browsers can preview xlsx).
- Companion skill `food-tech-domain/templates/output-patterns.md` has a more detailed 2-sheet (Detail + Summary) version of this.

## Support files
- `scripts/verify_formulas.py` — generic re-runnable formula verifier (load → optional fill-spec JSON → calculate → error scan → optional --expect checks).
- `references/formulas-lib-notes.md` — key format, value unwrapping, session validation results.
