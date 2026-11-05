# `formulas` 库验证笔记（2026-08 实战验证）

## Why
Bundled `xlsx` skill mandates recalc via LibreOffice (`scripts/recalc.py`). On machines with no soffice/Excel/WPS (this Mac: only Apple Numbers), install the Python `formulas` package and evaluate the workbook in-process. Equivalent verification outcome: every formula cell recomputed, error cells detectable, results cross-checkable. NOTE: this verifies formulas *evaluate* and produce expected values; it does NOT fill cached values into the delivered file (Excel/WPS/Numbers recalculate on open anyway).

## Install
```
UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/ ~/.hermes/bin/uv pip install --python /Users/xiebojun/Hermes/.venv/bin/python formulas
```
(deps: numpy, schedula, tqdm, six; ~15s on this machine)

## API
```python
import formulas
xl = formulas.ExcelModel().loads(tmp_path).finish()
sol = xl.calculate()   # dict; tqdm progress bar on stderr
```

## Gotchas (all hit during validation)
1. **Solution key format**: `"'[_verify_filled.xlsx]行政管理岗'!E11"`
   - The workbook ref `[_name.xlsx]` is prepended to the sheet name.
   - A single quote `'` sits between sheet name and `!`.
   - Match with `k.endswith(f"{sheet}'!{cell}")` — `f"{sheet}!{cell}"` silently misses everything.
2. **Values are wrappers**: XlCell objects with `.value`; numeric results come back as numpy arrays (size-1 → `.item()`); `str()` on an array raises `TypeError: only 0-dimensional arrays can be converted to Python scalars`. Use the `to_py()` helper in `scripts/verify_formulas.py`.
3. **Error cells**: evaluate to strings starting with `#` (e.g. `#NAME?`, `#VALUE!`). Scan ALL solutions; empty scan = clean workbook.
4. SyntaxWarnings from numpy ("is with literal") and tqdm bars are noise — filter with `grep -vE "Warning|it/s"`.
5. **Do NOT `write_back()`** the model into the deliverable — it rewrites the whole workbook and can drop openpyxl styling. formulas lib is a read-only verification engine here.
6. Cross-sheet references (e.g. `=员工自评!W6`) also resolve fine, but keeping each sheet self-contained makes verification simpler.

## Session validation result (2026-08, 岗位价值评估评分表)
- 7 position sheets × ~13 formulas each (SUM/IF chains), 1002 solution cells total.
- Filled the source workbook's sample scores into a copy; every computed 小计/总分/投入/产出/岗位形状/价值等级 matched the source workbook's cached values (e.g. 人力资源管理岗 84分/B级/下山型; 行政管理岗 56分/D级/下山型). Zero error cells.
- Conclusion: SUM/IF/ROUND formula chains written by openpyxl evaluate identically in the formulas engine and in Excel-family apps.
