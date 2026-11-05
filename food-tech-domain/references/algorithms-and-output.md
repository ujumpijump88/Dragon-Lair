# Canteen Algorithms & Output Patterns (refs for food-tech-domain)

Concrete techniques that complement the SKILL.md architecture: soft-constraint scoring, two-view reporting, runtime config, JSON I/O with versioning, and Flask + SQLite multi-thread safety. All patterns were validated in a working single-cafeteria MVP (87 recipes, 4-week stability, weekly 15-dish grid, 1657-row ingredient table).

## 1. Na soft-constraint via algorithm, not data

A cooking-time **adjustment table** (see SKILL.md `COOK_ADJ`) controls per-recipe Na. But even with low salt in `COOK_ADJ`, summing many salty dishes in one day blows past sodium limits.

Solution: encode Na control in the **scoring function** of the meal-plan algorithm:

```python
DAILY_NA_TARGET = 8500     # < this 加分 (鼓励再低, mg)
DAILY_NA_HIGH   = 9500     # > this 扣分 (避免爆, mg)

def score_nutrition(recipe, day_na_so_far):
    next_na = day_na_so_far + recipe._nut["na_mg"]
    if next_na < DAILY_NA_TARGET * 0.4:   return +2.0
    if next_na < DAILY_NA_TARGET * 0.7:   return +0.5
    if next_na <= DAILY_NA_HIGH:          return  0
    over = (next_na - DAILY_NA_HIGH) / 1000
    return -4.0 * over                    # 每超 1 g 扣 4 分
```

**Plus**: cap heavy-cook (braise / pan-fry / deep-fry) recipes per day (`HEAVY_COOKS = {"红烧", "煎", "炸"}, MAX_HEAVY_PER_DAY = 3`). Subtract 10 points when over — heavy cooking IS the source of Na, capping Na-correlated cooking patterns is structurally easier than capping Na directly.

Na baseline from a static algorithm vs. after this cap drops ~3–4%. Both segments count as the same algorithm, just with Na-aware scoring.

## 2. Two-portion reporting (don't sum per-100g × 100 per dish)

When you sum the **full per-serving** nutrition of all 15 dishes per day, the numbers look absurd (Na ~22 g/day) — because the algorithm models 1 serving per recipe, **not 1 dish-per-person**. Reality: each person picks ~6 dishes and eats ~50% of each.

Always provide both views in reports:

```python
PERSONAL_PORTION = 0.5          # 每道本人吃多少
SINGLE_RATIO = 0.6 * PERSONAL_PORTION / 7   # 1 人单餐 6 道 × 0.5 份的折扣率

weekly["full"]      = sum(kcal etc. for all dishes)         # 全供应 (采购视角)
weekly["personal"]  = weekly["full"] * SINGLE_RATIO        # 单人套餐 (厨师视角)
```

Mark them clearly: **"全供应总量"** vs **"单人 1 餐估算"**. Never present only the full number — it scares operators and obscures the real signal.

Acceptance check: `personal.kcal` should fall in [800, 960] kcal (Chinese lunch target for adult sedentary worker) — this number is what to optimize against.

## 3. Runtime-config + reload pattern

Externalize pricing, seasonality, thresholds into JSON files loaded at module import. **Two-step pattern**:

```python
# pricing.py
PRICING_BUCKET = {...}   # module-level default

def reload_pricing(config_path=None) -> dict:
    global PRICING_BUCKET, SUPPLY_YUAN, UTILITY_YUAN
    p = Path(config_path) if config_path else DEFAULT_CONFIG
    if p.exists():
        cfg = json.load(open(p, encoding="utf-8"))
        PRICING_BUCKET.update(cfg.get("buckets", {}))
        SUPPLY_YUAN = cfg.get("_fixed_costs", {}).get("supply", 0.5)
    return {...}

# meal_plan.py
CURRENT_MONTH = None
SEASONALITY = {}
SEASON_W_IN = 1.5
SEASON_W_OUT = -1.0

try:
    cfg = json.loads(SEASON_FILE.read_text(encoding="utf-8"))
    SEASONALITY = cfg.get("by_food_code", {})
except Exception as e:
    print(f"[warn] 加载 seasonality.json 失败: {e}")  # 不要 raise, 模块还能 import

def set_current_month(m: int):
    """调用一次即切换. 不重装 Python 解释器."""
    global CURRENT_MONTH
    CURRENT_MONTH = m

# 在评分函数里:
if CURRENT_MONTH is not None and CURRENT_MONTH in SEASONALITY.get(main, []):
    score += SEASON_W_IN
```

Edits to JSON files → restart is not needed if you also call `set_current_month`. Or just bundle the reset into a top-level CLI:

```bash
uv run python -c "from meal_plan import set_current_month; set_current_month(12)"
```

## 4. Recipe-validate before insert — fail fast on bad codes

A code typo will silently produce zero rows in joins. Always validate before `INSERT`:

```python
def validate_codes():
    valid = {row[0] for row in CONN.execute("SELECT food_code FROM foods")}
    bad = []
    for r in SEEDS:
        for code, _ in r["items"]:
            if code not in valid:
                bad.append((r["id"], r["name"], code))
    if bad:
        print("⚠️ 无效 codes:")
        for x in bad: print(" ", x)
    return len(bad)
```

Then:
```python
n_bad = validate_codes()
if n_bad:
    sys.exit("失败, 修 SEEDS 后重跑")
```

This catches typos in `091101` vs `0911xx` vs `092101` vs `092101x` — **country data is 6-digit strings with `x` suffix** for "代表值". Easy to miss.

## 5. JSON snapshot I/O with versioning

For backup/restore of the whole recipe library:

```python
VERSION = 1

def export_all(out_path):
    payload = {
        "version": VERSION,
        "exported_at": datetime.now().isoformat(timespec="seconds"),
        "seed_count": len(recipes),
        "recipes": [{...} for r in rows],
        "health_tags": [...],
        "pricing": {...},          # optional, include config
    }
    out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2),
                         encoding="utf-8")
```

Import must:
- Check `version` matches (warn + ask before proceeding)
- Confirm destructive operation (require `y/N` in CLI)
- Validate all codes again post-load (since this is a full replacement)

```python
if data["version"] != VERSION:
    if input("版本不匹配, 仍要继续? [y/N]: ").lower() != "y":
        return
```

**Why version matters**: future you changes the schema. Without it, importing an old file silently corrupts the DB.

## 6. Flask + SQLite multi-thread

A module-level `CONN = sqlite3.connect(DB)` **will break** under Flask dev server (worker threads).

Two fixes (pick one):

```python
# Option A: 允许跨线程访问 (sqlite >= 3.x)
CONN = sqlite3.connect(DB, check_same_thread=False)
CONN.row_factory = sqlite3.Row

# Option B: 每请求都新建
def conn():
    return sqlite3.connect(DB)
```

Recommended: **option B + dispose-in-endpoint**. If your endpoint does a lot of work (computing nutrition from many rows), reuse the connection **inside one request**:

```python
with sqlite3.connect(DB) as c:    # context-managed, auto-close at request end
    result = c.execute(...)
    return jsonify(...)

# OR pattern (don't close in middle):
@app.route("/api/something")
def handler():
    c = sqlite3.connect(DB)
    c.row_factory = sqlite3.Row
    try:
        ...use c...
        return jsonify(...)
    finally:
        c.close()             # 关闭, 避免 worker 耗尽
```

If endpoint timing has shown >5 ms query time, batch across multiple `c.execute()` calls inside the same connection, not multiple new connections.

## 7. SQLite parameter binding 不接受 Python list

`cursor.execute("... VALUES(?,?,...)", [row_to_dict(r)])` → `InterfaceError`. Always:

```python
row_out = dict(r)
row_out["main_ingredients"] = ",".join(r["main_ingredients"]) \
    if isinstance(r["main_ingredients"], list) \
    else r["main_ingredients"]
cursor.execute("INSERT ... VALUES(:a,:b,...)", row_out)
```

Renaming columns vs. unpacking them: prefer **aliasing in SELECT** (`h.tags AS health_tags`) over post-fetch `dict` rename — keeps the calling layer clean.

## 8. Multi-week stability check

After implementing the algorithm, generate **4 weeks with a fixed seed** and print cross-week statistics:

```python
import statistics
costs = [sum(p.price for p in week) for week in weeks]
sd = statistics.stdev(costs)
cv = sd / statistics.mean(costs) * 100
print(f"成本变异: {cv:.1f}%")    # 期望 < 1.5%
```

If CV > 2%, the algorithm is not stable — likely culprit: hard constraints that always fail leaving fallback to per-criterion scoring. Tighten scoring weights, or add a "duplicate day across weeks" soft penalty.

## 9. Per-recipe nutrition caching

Running `estimate_nutrition_per_serving(recipe)` on every candidate re-hits sqlite many times per algorithm tick. Cache:

```python
def _nut_per_serving(recipe):
    if "_nut" not in recipe:
        items = []
        for token in recipe["items"].split(";"):
            if token:
                c, g = token.split(":")
                items.append((c, float(g)))
        recipe["_nut"] = estimate_nutrition_per_serving(items, recipe["cook_method"], 1)
    return recipe["_nut"]
```

`recipe["_nut"]` survives across candidates if same recipe re-evaluated; saves ~80% sqlite queries in 4-week run.

## 10. Output formats

### CSV
- Header row in Chinese.
- Add `"\ufeff"` BOM prefix → Excel doesn't mangle UTF-8.
- `text/csv; charset=utf-8` mime.

### XLSX
Two-sheet pattern (Detail + Summary):
- **Sheet 1**: "每日菜牌" — one row per dish with health-tagged row colored `PatternFill(fgColor="C6F6D5")`.
- **Sheet 2**: "每日营养" — one row per day summing all selected dishes.
- Widths: `ws.column_dimensions[chr(64+i)].width = N` per column.
- Column header bold: `Font(bold=True)`.
- Stream from Flask: `BytesIO` → `Response(mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")` with `Content-Disposition: attachment; filename="...xlsx"`.
- Frontend trigger: `<a href="/api/plan/.../export?format=xlsx" download>`. The anchor element forces browser download.

See `templates/output-patterns.md` for full snippets.

## Related files

- `food-tech-domain/templates/output-patterns.md` — full code for XLSX two-sheet + colored cells + CSV BOM
- `food-tech-domain/templates/flask-canteen-app.py` — minimal Flask scaffold that won't fall into the sqlite multi-thread trap
- `food-tech-domain/scripts/verify_canteen_paths.py` — re-runnable verifier covering all algorithm paths
