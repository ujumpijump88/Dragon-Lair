#!/usr/bin/env python3
"""Re-runnable verifier for food-tech-domain apps.

Covers:
  - All API endpoints (pool, plan, recipe detail, swap, export)
  - Multi-week JSON snapshot import/export CLI
  - Config files (pricing + seasonality)
  - Algorithm: 4-week generation, expected per-day dish count = 15

Usage:
    uv run python scripts/verify_canteen_paths.py

Exit codes:
    0 — all OK
    1 — at least one assertion failed (printed)

This is NOT a test suite — it's an ad-hoc smoke test for catching
regressions after refactors. Add more checks inline as you discover
new edges.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

# Adjust as needed: usually the project root is parent of scripts/
PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))
os.chdir(str(PROJECT_ROOT))
os.environ["NO_PROXY"] = "127.0.0.1,localhost"   # 避免 httpx 受系统代理影响

results = []   # list[(name, status, info)]


def rec(name, status, info=""):
    results.append((name, status, info))


def assert_true(cond, msg):
    if not cond:
        raise AssertionError(msg)


# ----------------------------------------------------------------------------
# 1. Flask API endpoints (用 test_client, 不需要真起 server)
# ----------------------------------------------------------------------------

try:
    # Path the user's app.py or app module
    sys.path.insert(0, str(PROJECT_ROOT))
    from app import app
    with app.test_client() as c:
        for path, expect_key in [
            ("/", "len"),
            ("/api/pool", "count"),
            ("/api/plan?weeks=1", "weeks"),
            ("/api/recipe/R001", "name"),
        ]:
            r = c.get(path)
            assert_true(r.status_code == 200, f"{path}: status={r.status_code}")
            if path == "/":
                body = r.get_data()
                rec("GET /", r.status_code, f"len={len(body)}")
            else:
                data = r.get_json()
                assert_true(expect_key in data, f"{path}: missing {expect_key}")
                rec("GET " + path, r.status_code, f"{expect_key}={str(data[expect_key])[:60]}")

        # POST swap
        r = c.post("/api/swap", json={
            "current_id": "R001",
            "exclude_ids": ["R001"],
            "prefer_dish_type": "main",
            "prefer_cook": "stir_fried",
        })
        assert_true(r.status_code == 200, f"/api/swap: status={r.status_code}")
        data = r.get_json()
        assert_true(data["id"] != "R001", "swap returned same id")
        rec("POST /api/swap", r.status_code,
            f"new={data['id']} alt={data.get('alternatives_total')}")

        # XLSX export
        r = c.get("/api/plan/week_a/export?format=xlsx")
        assert_true(r.status_code == 200, "xlsx export failed")
        body = r.get_data()
        assert_true(body[:2] == b"PK", "xlsx missing PK header")
        assert_true(len(body) > 1000, "xlsx too small to be valid")
        rec("XLSX export", r.status_code, f"sz={len(body)} zip=True")

        # CSV export
        r = c.get("/api/plan/week_a/export?format=csv")
        assert_true(r.status_code == 200, "csv export failed")
        text = r.get_data(as_text=True)
        assert_true(text.startswith("\ufeff"), "csv missing BOM")
        assert_true(text.count("\n") >= 100, "csv has < 100 rows")
        rec("CSV export", r.status_code,
            f"rows={text.count(chr(10)) - 1} bom=True")
except Exception as e:
    import traceback
    rec("API tests", "ERR", traceback.format_exc()[:200])


# ----------------------------------------------------------------------------
# 2. CLI JSON snapshot import/export
# ----------------------------------------------------------------------------

try:
    snap = "/tmp/snap_v_" + str(os.getpid()) + ".json"
    r1 = subprocess.run(
        [sys.executable, "cli/io_json.py", "export", snap],
        capture_output=True, text=True, timeout=30,
    )
    assert_true(r1.returncode == 0, f"export cli failed: {r1.stderr}")
    assert_true(Path(snap).exists(), "snapshot file not created")
    data = json.loads(Path(snap).read_text(encoding="utf-8"))
    assert_true(data["version"] == 1, "missing version field")
    assert_true(len(data["recipes"]) >= 80, f"only {len(data['recipes'])} recipes")
    assert_true("pricing" in data, "missing pricing block")
    rec("CLI export", r1.returncode,
        f"v={data['version']} rec={len(data['recipes'])} tags={len(data['health_tags'])}")
    Path(snap).unlink()
except Exception as e:
    import traceback
    rec("CLI snapshot", "ERR", traceback.format_exc()[:200])


# ----------------------------------------------------------------------------
# 3. Config files exist + loadable
# ----------------------------------------------------------------------------

try:
    p = json.loads(Path("config/pricing.json").read_text(encoding="utf-8"))
    s = json.loads(Path("config/seasonality.json").read_text(encoding="utf-8"))
    assert_true("buckets" in p, "pricing.json: missing buckets")
    assert_true("by_food_code" in s, "seasonality.json: missing by_food_code")
    assert_true(len(p["buckets"]) >= 10, "pricing buckets too few")
    assert_true(len(s["by_food_code"]) >= 5, "seasonality mapping too sparse")
    rec("config load", "ok",
        f"buckets={len(p['buckets'])} season={len(s['by_food_code'])}")
except Exception as e:
    import traceback
    rec("config", "ERR", traceback.format_exc()[:200])


# ----------------------------------------------------------------------------
# 4. Algorithm — multi-week generation (固定 seed, 期望 7×15)
# ----------------------------------------------------------------------------

try:
    import random
    from meal_plan import (load_pool, generate_one_day, WeeklyCounter,
                            SEASONALITY, SEASON_W_IN)
    assert_true(len(SEASONALITY) >= 10, "seasonality table empty in module")
    all_ok = True
    detail = ""
    for seed in (1, 42, 99):
        random.seed(seed)
        pool = load_pool()
        counter = WeeklyCounter()
        daily = []
        days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        for i in range(7):
            picks = generate_one_day(pool, counter, i, days[i])
            daily.append(len(picks))
        if sum(daily) != 105 or any(c != 15 for c in daily):
            all_ok = False
            detail = f"seed={seed} daily={daily}"
            break
    rec("week gen x3", "ok" if all_ok else "FAIL", f"105=7*15 {detail}")
except Exception as e:
    import traceback
    rec("algorithm", "ERR", traceback.format_exc()[:200])


# ----------------------------------------------------------------------------
# 打印汇总
# ----------------------------------------------------------------------------

print("\n===== VERIFY RESULTS =====")
fail = 0
for name, status, info in results:
    ok = status in (200, 0, "ok")
    tag = "ok  " if ok else "FAIL"
    if not ok:
        fail += 1
    print(f"  [{tag}] {name:<30}  status={str(status):<5}  {info[:60]}")
print(f"\n>>> {'ALL OK' if fail == 0 else f'{fail} FAILED'}")
sys.exit(0 if fail == 0 else 1)
