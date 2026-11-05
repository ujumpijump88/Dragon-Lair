#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generic formula verifier for openpyxl-generated workbooks — no LibreOffice needed.

Usage:
  .venv/bin/python verify_formulas.py <workbook.xlsx> [fill_spec.json] [--expect "Sheet!C1=12.0"]

fill_spec.json (optional): {"SheetName": {"A1": 5, "B2": 3.5}} — values written into a
COPY of the workbook before evaluating (e.g. sample inputs so formulas depending on
blank input cells still get exercised). The original file is never modified.

--expect (repeatable): assert a computed cell equals a value; e.g. cross-check against
a source workbook's cached values. Exits non-zero on any mismatch or error cell.

Output: total formula cells evaluated, error cells (value starting with '#'), and
PASS/FAIL per --expect check.
"""
import json
import os
import sys

import numpy as np
import formulas
import openpyxl


def to_py(v):
    """Unwrap formulas-lib values: XlCell -> .value, then to_python(), numpy -> .item()."""
    if hasattr(v, "value"):
        v = v.value
    if hasattr(v, "to_python"):
        v = v.to_python()
    if isinstance(v, np.ndarray):
        v = v.item() if v.size == 1 else v.tolist()
    return v


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    src = sys.argv[1]
    tmp = src.replace(".xlsx", "_verify_tmp.xlsx")

    wb = openpyxl.load_workbook(src)
    if len(sys.argv) > 2 and sys.argv[2].endswith(".json"):
        with open(sys.argv[2], encoding="utf-8") as f:
            fill = json.load(f)
        for sheet, cells in fill.items():
            for ref, val in cells.items():
                wb[sheet][ref] = val
    wb.save(tmp)

    sol = formulas.ExcelModel().loads(tmp).finish().calculate()

    errs, count = [], 0
    for k, v in sol.items():
        count += 1
        p = to_py(v)
        if isinstance(p, str) and p.startswith("#"):
            errs.append((k, p))
    print(f"formula cells evaluated: {count}")
    if errs:
        print("ERROR cells:")
        for k, e in errs[:50]:
            print(f"  {k}: {e}")
        sys.exit(1)
    print("OK: no formula errors")

    failed = False
    if "--expect" in sys.argv:
        i = sys.argv.index("--expect")
        for want in sys.argv[i + 1:]:
            ref, exp = want.rsplit("=", 1)
            sheet, cell = ref.split("!")
            got = None
            for k, v in sol.items():
                if k.endswith(f"{sheet}'!{cell}"):
                    got = to_py(v)
                    break
            ok = got is not None and str(got) == exp
            print(f"expect {ref} = {exp}: {'PASS' if ok else 'FAIL (got ' + str(got) + ')'}")
            failed = failed or not ok

    os.remove(tmp)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
