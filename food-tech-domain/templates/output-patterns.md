# Output Format Templates (XLSX, CSV, in-app downloads)

Concrete patterns for exporting the weekly meal plan. All snippets assume you're in a Flask endpoint and have `current_week` (`dict` with key `days: list[list[Recipe]]`).

## CSV (Excel-friendly)

```python
from io import StringIO
import csv
from flask import Response

def download_csv(week):
    si = StringIO()
    w = csv.writer(si)
    w.writerow(["日期", "菜名", "菜型", "烹饪", "健康",
                "热量 kcal", "蛋白 g", "脂肪 g", "Na mg"])
    for day in week["days"]:
        for r in day:
            nut = r["nutrition"]
            w.writerow([
                r["day_label"], r["recipe_name"], r["dish_type"],
                r["cook_method"],
                "✓" if r["is_health_friendly"] else "",
                nut["kcal"], nut["protein_g"],
                nut["fat_g"], nut["na_mg"],
            ])
    return Response(
        "\ufeff" + si.getvalue(),         # BOM 让 Excel UTF-8 不乱码
        mimetype="text/csv; charset=utf-8",
        headers={"Content-Disposition":
                 f"attachment; filename=canteen_{week['label']}.csv"},
    )
```

Key: the `"\ufeff"` **must be a Python literal `\ufeff`**, not the literal characters. `chr(0xFEFF)` also works.

## XLSX (two-sheet detail + summary + colored rows)

```python
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill
from io import BytesIO
from flask import Response

def download_xlsx(week):
    wb = Workbook()
    wb.remove(wb.active)                       # delete default sheet

    # ---- Sheet 1: 每日菜牌 (每菜一行 + 健康菜行绿色) ----
    ws = wb.create_sheet("每日菜牌")
    header_font = Font(bold=True)
    health_fill = PatternFill("solid", fgColor="C6F6D5")
    ws.append(["日期", "菜名", "菜型", "烹饪", "健康",
               "热量 kcal", "蛋白 g", "脂肪 g", "Na mg"])
    for cell in ws[1]:
        cell.font = header_font

    for day in week["days"]:
        for r in day:
            nut = r["nutrition"]
            row = [
                r["day_label"], r["recipe_name"], r["dish_type"],
                r["cook_method"],
                "✓" if r["is_health_friendly"] else "",
                nut["kcal"], nut["protein_g"],
                nut["fat_g"], nut["na_mg"],
            ]
            ws.append(row)
            if r["is_health_friendly"]:
                excel_row = ws.max_row
                for col in range(1, len(row) + 1):
                    ws.cell(row=excel_row, column=col).fill = health_fill

    widths = [8, 22, 10, 8, 6, 10, 10, 10, 10]
    for i, w in enumerate(widths, 1):
        ws.column_dimensions[chr(64 + i)].width = w

    # ---- Sheet 2: 每日营养合计 ----
    ws2 = wb.create_sheet("每日营养")
    ws2.append(["日期", "全日 kcal", "全日蛋白 g", "全日脂肪 g",
                "全日 Na mg", "健康菜数", "总道数"])
    for cell in ws2[1]:
        cell.font = header_font
    for day in week["days"]:
        if not day:
            continue
        ws2.append([
            day[0]["day_label"],
            round(sum(r["nutrition"]["kcal"] for r in day), 1),
            round(sum(r["nutrition"]["protein_g"] for r in day), 1),
            round(sum(r["nutrition"]["fat_g"] for r in day), 1),
            round(sum(r["nutrition"]["na_mg"] for r in day), 0),
            sum(1 for r in day if r["is_health_friendly"]),
            len(day),
        ])
    for i, w in enumerate([10, 12, 12, 12, 14, 10, 10], 1):
        ws2.column_dimensions[chr(64 + i)].width = w

    # ---- stream to browser ----
    bio = BytesIO()
    wb.save(bio)
    bio.seek(0)
    return Response(
        bio.getvalue(),
        mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition":
                 f"attachment; filename=canteen_{week['label']}.xlsx"},
    )
```

### Gotchas

- `wb.remove(wb.active)` is required — otherwise you get the default "Sheet" + your first named sheet.
- `ws.column_dimensions["A"].width = 8` — key is **uppercase letter** ("A"), not "a".
- For sheets beyond column Z, use `get_column_letter(N)` from `openpyxl.utils`.
- Chinese characters in cells are fine; **don't pre-encode UTF-8** — `wb.save()` handles it.

## Frontend trigger buttons

```html
<button id="btn-export-xlsx">📥 下载 Excel</button>
<button id="btn-export-csv">📄 下载 CSV</button>
```

```js
function downloadPlan(week, fmt) {
  if (!week) return;
  const a = document.createElement('a');
  a.href = `/api/plan/${week.week_label}/export?format=${fmt}`;
  a.download = `canteen_${week.week_label}.${fmt}`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
}
document.getElementById('btn-export-xlsx').onclick = () => {
  const wl = document.getElementById('week-select').value;
  downloadPlan(currentPlan.find(w => w.week_label === wl), 'xlsx');
};
```

The `download` attribute on the anchor is decorative; actual download is forced by the `Content-Disposition: attachment` header on the server response.

## Verification

- **CSV**: open in Excel — first column headers should not mangle. The BOM is invisible but makes Excel detect UTF-8. Verify with `head -c 3 file.csv` (should be `\xef\xbb\xbf`).
- **XLSX**: `file file.xlsx` should report "Microsoft Excel 2007+". Bytes start with `PK` (zip signature).

## Adding PDF (if needed later)

- `reportlab` is the standard pick for Python.
- For chart embedding use `matplotlib` → save PNG → insert into PDF via `reportlab.platypus.Image`.
- Watch memory: generate PDF in `BytesIO` not on disk.

## Related

- See `references/algorithms-and-output.md` §10 for the rationale.
- Companion skill `openpyxl-workbooks/SKILL.md` covers **form building** with openpyxl (vs. data export here).
