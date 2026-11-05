#!/usr/bin/env python3
"""Flask scaffold for food-tech-domain apps.

What it does:
  - Loads recipe pool + health tags from canteen.db
  - Exposes 4 GET + 1 POST endpoints (pool, plan, recipe, swap, export)
  - In-memory multi-week generation (no DB writes for plans)
  - Sodium soft-constraint in scoring (see references/algorithms-and-output.md)
  - Per-request sqlite connection (avoids multi-threaded CONN bug)

Run:
  uv run --with flask --with openpyxl python flask-canteen-app.py
  # -> http://127.0.0.1:5050/

This is a SCAFFOLD, not a finished app. It is meant to be modified.
Adapt:
  - DB path
  - `load_pool()`, `generate_plan()`, `_score_*` functions (import from your core module)
  - `index.html` / static assets
"""
import json
import random
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path
from typing import Optional

from flask import Flask, Response, jsonify, render_template, request

# 让 app 能 import 同目录下的核心算法模块
sys.path.insert(0, str(Path(__file__).parent))

app = Flask(__name__, template_folder="templates", static_folder="static")
DB = Path(__file__).parent / "data" / "canteen.db"


# ----------------------------------------------------------------------------
# sqlite helpers — per-request connections (multi-thread safe)
# ----------------------------------------------------------------------------

def conn():
    """Per-request db connection. 立刻关掉避免 worker 积累 fd."""
    c = sqlite3.connect(DB)
    c.row_factory = sqlite3.Row
    return c


def estimate_nutrition_inline(items_str: str, cook_method: str) -> dict:
    """计算菜品的营养. 在 Flask 端不依赖单例连接 (避免多线程 bug).

    直接走 SQL + COOK_ADJ, 不依赖 nutrition 模块.
    """
    from nutrition import COOK_ADJ   # 假设你的项目里有 nutrition.py
    c = conn()
    FIELDS = ["kcal", "protein_g", "fat_g", "cho_g", "fiber_g",
              "cholesterol_mg", "vit_a_ug", "thiamin_mg", "riboflavin_mg",
              "niacin_mg", "vit_c_mg", "vit_e_total_mg",
              "ca_mg", "p_mg", "k_mg", "na_mg", "mg_mg",
              "fe_mg", "zn_mg", "se_ug", "cu_mg", "mn_mg"]
    total = {f: 0.0 for f in FIELDS}
    for token in items_str.split(";"):
        if not token:
            continue
        code, g = token.split(":")
        row = c.execute(
            f"""SELECT edible_pct, {','.join(FIELDS)}
                FROM foods JOIN nutrition USING(food_code)
                WHERE food_code = ?""",
            (code,),
        ).fetchone()
        if not row:
            continue
        d = dict(row)
        edible = d.get("edible_pct") or 100
        edible_g = float(g) * edible / 100
        for f in FIELDS:
            v = d.get(f)
            if v is not None:
                total[f] += float(v) * edible_g / 100
    c.close()

    adj = COOK_ADJ.get(cook_method, {})
    total["fat_g"] += adj.get("oil_g", 0) * 0.999
    total["kcal"] += adj.get("oil_g", 0) * 9.0
    total["vit_e_total_mg"] += adj.get("oil_g", 0) * 1.0
    total["na_mg"] += adj.get("salt_g", 0) * 393 * 0.80
    if adj.get("water_loss_pct", 0):
        for f in ("vit_c_mg", "thiamin_mg", "riboflavin_mg", "niacin_mg"):
            if total[f]:
                total[f] *= (1 - adj["water_loss_pct"])
    if adj.get("thermal_loss", 0):
        for f in ("vit_a_ug", "vit_e_total_mg", "protein_g"):
            if total[f]:
                total[f] *= (1 - adj["thermal_loss"])
    return total


# ----------------------------------------------------------------------------
# Endpoints
# ----------------------------------------------------------------------------

@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/pool")
def api_pool():
    """返回菜品池 + 健康标签.
    注意: items (raw) 不返回给前端 — 只返概要, 避免响应过大."""
    c = conn()
    rows = c.execute("""
        SELECT r.id, r.name, r.category, r.dish_type, r.cook_method,
               r.main_ingredients, h.cook_category, h.is_health_friendly,
               h.tags AS health_tags
        FROM recipes r
        JOIN health_tags h ON r.id = h.recipe_id
    """).fetchall()
    c.close()
    out = []
    for r in rows:
        d = dict(r)
        d["main_ingredients"] = d["main_ingredients"].split(",") if d["main_ingredients"] else []
        d["health_tags"] = d["health_tags"].split(",") if d["health_tags"] else []
        d["is_health_friendly"] = bool(d["is_health_friendly"])
        out.append(d)
    return jsonify({"count": len(out), "pool": out})


@app.route("/api/plan")
def api_plan():
    """返回多周菜牌. 期望调用方传 weeks=N (默认 4)."""
    weeks = int(request.args.get("weeks", 4))
    plan, _ = generate_plan(weeks)        # 用户项目里实现
    return jsonify({"weeks": plan})


@app.route("/api/recipe/<rid>")
def api_recipe(rid):
    """单菜详情."""
    from meal_plan import load_pool     # 假设你的项目里有 meal_plan.py
    pool = load_pool()
    r = next((r for r in pool if r["id"] == rid), None)
    if not r:
        return jsonify({"error": "not found"}), 404
    nut = estimate_nutrition_inline(r["items"], r["cook_method"])
    return jsonify({
        "id": r["id"], "name": r["name"],
        "category": r["category"], "cook_method": r["cook_method"],
        "main_ingredients": r["main_ingredients"],
        "is_health_friendly": bool(r.get("is_health_friendly")),
        "health_tags": r.get("health_tags", []),
        "nutrition": {k: round(nut.get(k, 0) or 0, 1)
                       for k in ("kcal", "protein_g", "fat_g", "na_mg")},
    })


@app.route("/api/swap", methods=["POST"])
def api_swap():
    """换一道菜. 优先保持 dish_type + cook_method."""
    data = request.get_json(force=True, silent=True) or {}
    current_id = data.get("current_id")
    exclude_ids = set(data.get("exclude_ids") or [])
    if current_id:
        exclude_ids.add(current_id)
    prefer_type = data.get("prefer_dish_type")
    prefer_cook = data.get("prefer_cook")

    from meal_plan import load_pool
    pool = load_pool()
    cands = [r for r in pool if r["id"] not in exclude_ids]

    primary, secondary = [], []
    for r in cands:
        s_type = (r["dish_type"] == prefer_type) if prefer_type else True
        s_cook = (r["cook_category"] == prefer_cook) if prefer_cook else True
        if s_type and s_cook:
            primary.append(r)
        elif s_type or s_cook:
            secondary.append(r)

    choice = primary or secondary or cands
    random.shuffle(choice)
    new = choice[0]
    nut = estimate_nutrition_inline(new["items"], new["cook_method"])
    return jsonify({
        "id": new["id"], "name": new["name"],
        "category": new["category"], "cook_method": new["cook_method"],
        "cook_category": new.get("cook_category", ""),
        "main_ingredients": new["main_ingredients"],
        "is_health_friendly": bool(new.get("is_health_friendly")),
        "health_tags": new.get("health_tags", []),
        "nutrition": {k: round(nut.get(k, 0) or 0, 1)
                       for k in ("kcal", "protein_g", "fat_g", "na_mg")},
        "alternatives_total": len(choice),
    })


@app.route("/api/plan/<week_label>/export")
def api_plan_export(week_label):
    """导出周菜牌 XLSX/CSV. 默认 XLSX. 详见 templates/output-patterns.md."""
    fmt = request.args.get("format", "xlsx").lower()
    plan, _ = generate_plan(4)
    target = next((w for w in plan if w["week_label"] == week_label), None)
    if not target:
        return jsonify({"error": "not found"}), 404

    if fmt == "csv":
        from io import StringIO
        import csv
        si = StringIO()
        cw = csv.writer(si)
        cw.writerow(["日期", "菜名", "菜型", "烹饪", "健康",
                     "热量 kcal", "蛋白 g", "脂肪 g", "Na mg"])
        for day in target["days"]:
            for r in day:
                n = r["nutrition"]
                cw.writerow([r["day_label"], r["recipe_name"], r["dish_type"],
                             r["cook_method"],
                             "✓" if r["is_health_friendly"] else "",
                             n["kcal"], n["protein_g"], n["fat_g"], n["na_mg"]])
        return Response("\ufeff" + si.getvalue(),
                        mimetype="text/csv; charset=utf-8",
                        headers={"Content-Disposition":
                                 f"attachment; filename=canteen_{week_label}.csv"})

    # XLSX: import from your project's templates/output-patterns.md
    try:
        from openpyxl import Workbook
        from openpyxl.styles import Font, PatternFill
    except ImportError:
        return jsonify({"error": "openpyxl missing. Use ?format=csv"}), 500

    wb = Workbook()
    wb.remove(wb.active)
    ws = wb.create_sheet("每日菜牌")
    header_font = Font(bold=True)
    health_fill = PatternFill("solid", fgColor="C6F6D5")
    ws.append(["日期", "菜名", "菜型", "烹饪", "健康",
               "热量 kcal", "蛋白 g", "脂肪 g", "Na mg"])
    for cell in ws[1]:
        cell.font = header_font
    for day in target["days"]:
        for r in day:
            n = r["nutrition"]
            row = [r["day_label"], r["recipe_name"], r["dish_type"],
                   r["cook_method"],
                   "✓" if r["is_health_friendly"] else "",
                   n["kcal"], n["protein_g"], n["fat_g"], n["na_mg"]]
            ws.append(row)
            if r["is_health_friendly"]:
                excel_row = ws.max_row
                for col in range(1, len(row) + 1):
                    ws.cell(row=excel_row, column=col).fill = health_fill
    for i, w in enumerate([8, 22, 10, 8, 6, 10, 10, 10, 10], 1):
        ws.column_dimensions[chr(64 + i)].width = w

    ws2 = wb.create_sheet("每日营养")
    ws2.append(["日期", "全日 kcal", "全日蛋白 g", "全日脂肪 g",
                "全日 Na mg", "健康菜数", "总道数"])
    for cell in ws2[1]:
        cell.font = header_font
    for day in target["days"]:
        if not day:
            continue
        ws2.append([day[0]["day_label"],
                    round(sum(r["nutrition"]["kcal"] for r in day), 1),
                    round(sum(r["nutrition"]["protein_g"] for r in day), 1),
                    round(sum(r["nutrition"]["fat_g"] for r in day), 1),
                    round(sum(r["nutrition"]["na_mg"] for r in day), 0),
                    sum(1 for r in day if r["is_health_friendly"]),
                    len(day)])
    for i, w in enumerate([10, 12, 12, 12, 14, 10, 10], 1):
        ws2.column_dimensions[chr(64 + i)].width = w

    from io import BytesIO
    bio = BytesIO()
    wb.save(bio)
    bio.seek(0)
    return Response(bio.getvalue(),
                    mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    headers={"Content-Disposition":
                             f"attachment; filename=canteen_{week_label}.xlsx"})


# ----------------------------------------------------------------------------
# 启动
# ----------------------------------------------------------------------------

if __name__ == "__main__":
    print("\n  启动 Flask 服务器")
    print("  访问: http://127.0.0.1:5050/\n")
    app.run(host="127.0.0.1", port=5050, debug=True)
