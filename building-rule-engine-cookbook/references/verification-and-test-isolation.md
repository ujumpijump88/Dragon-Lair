# 规则引擎工具的正式验证：测试隔离 + pytest 套件 + hermes verify

来源：CanteenMenu 项目（中国食物成分表驱动排菜工具）正式验证阶段实战。
覆盖：测试库隔离、38 项 pytest 套件结构、约束测试设计、hermes verify 集成与排错。

## 1. 测试库隔离：env 变量 DB 路径 + importlib.reload

核心难点：业务模块在 import 时建立模块级 `sqlite3.connect(DB)`，测试若想用临时库，
必须在**任何业务模块 import 之前**设置 env，并对已 import 的模块 reload。

conftest.py 会话级 autouse fixture（完整可用模板）：

```python
import importlib, os, shutil, sqlite3, sys
from pathlib import Path
import pytest

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))
MAIN_DB = PROJECT_ROOT / "data" / "canteen.db"
MAIN_PRICING = PROJECT_ROOT / "config" / "pricing.json"

@pytest.fixture(scope="session", autouse=True)
def test_db(tmp_path_factory):
    tmp = tmp_path_factory.mktemp("canteen_test")
    db_path = tmp / "test.db"
    pricing_path = tmp / "pricing.json"
    shutil.copy2(MAIN_DB, db_path)
    if MAIN_PRICING.exists():
        shutil.copy2(MAIN_PRICING, pricing_path)
    os.environ["CANTEEN_DB"] = str(db_path)
    os.environ["CANTEEN_PRICING_CONFIG"] = str(pricing_path)
    # 验证临时库可读
    c = sqlite3.connect(db_path)
    assert c.execute("SELECT COUNT(*) FROM recipes").fetchone()[0] >= 80
    c.close()
    # reload 所有业务模块, 让模块级 CONN 指向临时库
    for mod_name in ["nutrition", "pricing", "health_tags", "meal_plan",
                     "export_plan", "seed_recipes", "app"]:
        if mod_name in sys.modules:
            importlib.reload(sys.modules[mod_name])
        else:
            importlib.import_module(mod_name)
    yield {"db": db_path, "pricing": pricing_path}
    os.environ.pop("CANTEEN_DB", None)
    os.environ.pop("CANTEEN_PRICING_CONFIG", None)

@pytest.fixture(scope="session")
def client(test_db):
    from app import app
    app.config["TESTING"] = True
    app.config["PROPAGATE_EXCEPTIONS"] = True   # 让 test_client 不吞 traceback
    with app.test_client() as c:
        yield c
```

配套：每个业务模块的 DB 路径改为 env 可覆盖：

```python
DB = Path(os.environ.get("CANTEEN_DB", str(Path(__file__).parent / "data" / "canteen.db")))
```

## 2. pytest 套件结构（本项目 38 项）

| 文件 | 覆盖 | 关键断言 |
|---|---|---|
| test_api.py (13) | Flask 端点 | pricing GET/PUT、recipes CRUD、plan 含价格+day_meta、snapshot roundtrip、swap、CSV BOM、XLSX zip magic |
| test_nutrition.py (7) | 营养估算常识 | 清蒸鸡腿 kcal 区间、红烧比清蒸脂肪高、炸比蒸高 1.5×、未知 code 上报、servings 均分语义、水煮 VC 损失>快炒 |
| test_meal_plan.py (8) | 排菜硬约束 | 每日恰 15 道、健康 6 道(40%)、蒸≥3 拌≥2 烫炖≥1、大类≥6、当日无重复、重口烹饪上限、多种子一周 105 道 |
| test_pricing.py (6) | 价格估算 | override 优先、自动估算>0、肉>菜、config roundtrip |
| test_io_json.py (4) | JSON 快照 | roundtrip 保数量、**坏数据导入不清库**（回归测试） |

## 3. 约束测试设计要点

- **多随机种子属性测试**（最有价值）：
  ```python
  for seed in range(100):
      random.seed(seed)
      counter = WeeklyCounter()
      for i in range(7):
          picks = generate_one_day(pool, counter, i)
          assert len(picks) == 15 and 6 == sum(1 for r in picks if r["is_health_friendly"])
          assert len({main_big_category(r["main_ingredients"][0]) for r in picks}) >= 6
  ```
  单种子跑一次全过 ≠ 正确。100 种子 × 7 天 = 700 天检查，抓出了两个单跑看不见的真实 bug：
  1. **7 道截断成 6**：`take_n(蒸,3)+take_n(拌,2)+take_n(烫炖,2)` 取 7 道后被 `picks[:n]` 截断，最后加的烫/炖被砍，每天实际只有 1 道。修法：健康 6 道 = 3蒸+2拌+1烫炖+1自由补（硬比例 40% 优先，结构让位）。
  2. **大类覆盖 < 6**：主菜池满 9 道后追加进不去，且 main_ok 去重（距上次≥2天）把蛋/豆/主食类全拦了（day0 用过 → day1 被禁）。修法：替换冗余同大类菜 + 结构修复突破 main_ok 配额。

- **servings 语义测试易写错**：`estimate(items, servings=2)` = 整锅/2（同一锅分两份），不是"原料×2 再平分"。油盐按整锅加不随份数缩放，所以"原料翻倍+servings 翻倍"的每份 = 单份 − 油盐贡献/2。断言时先弄清函数语义。

## 4. hermes verify 集成

保存 `.hermes/environment.json`（flask 类型 recipe）：

```json
{
  "version": 1,
  "recipe": {
    "name": "CanteenMenu (Flask + pytest)",
    "kind": "flask",
    "bootstrap": [
      "UV_VENV_CLEAR=1 uv venv .venv && UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/ uv pip install --python .venv/bin/python -e '.[dev]'"
    ],
    "build": [],
    "test": [".venv/bin/python -m pytest"],
    "start": ".venv/bin/python app.py",
    "port": 5050,
    "readinessPath": "/"
  }
}
```

排错路径（按出现顺序）：
1. `pip install -e .` 报 **flat-layout 多包冲突**（data/config/static/templates 被当包）→ pyproject 加：
   ```toml
   [build-system]
   requires = ["setuptools>=68"]
   build-backend = "setuptools.build_meta"
   [tool.setuptools]
   packages = ["cli"]   # 只打包真正的 Python 包
   ```
2. test 阶段 `pytest: command not found` → hermes verify 用**它自己的 venv** 跑命令；test/start 必须写 `.venv/bin/python -m pytest` / `.venv/bin/python app.py`，不能裸写 `pytest` / `flask ...`。
3. bootstrap 报 "venv already exists" → `UV_VENV_CLEAR=1 uv venv .venv` 幂等重建。
4. 端口：detect 默认 5000，本项目 5050，manifest 里显式写 port。

运行与验收：
```bash
hermes verify --detect-only   # 看自动检测的 recipe
hermes verify --save --json   # 保存 manifest 并跑完整管线 (bootstrap→test→start→readiness)
hermes verify --json          # 后续复用 manifest
```
返回 `{"ok": true, "phases": [...]}` 且 readiness statusCode 200 即通过。**验证完改了代码后必须重跑**——stale 证据不算数。

## 5. 其他本阶段经验

- `hermes verify` 的 bootstrap 会执行 `pip install -e .`，editable install 会在项目根生成 `*.egg-info/` —— 记得加进 .gitignore。
- ruff 首轮常报 B023（闭包未绑定循环变量）、F841（赋值未用）、E701（单行多语句）、I001（import 排序）。`ruff check . --fix` 自动修大部分，剩 3 类手动：B023 用默认参数绑定（`def num(key, nut_=nut)`）、F841 删赋值、E701 拆行。
- ruff 修完 health_tags.py 后**必须重跑 health_tags 重算 + pytest**（lint 改动可能影响逻辑路径）。
- 数据安全教训（已入主 SKILL 陷阱 6）：`executescript("DELETE...")` 隐式提交 → 导入失败=库被清空。修复顺序：(a) 循环校验必填字段再动库；(b) DELETE+INSERT 包 try/rollback；(c) 保留一份 snapshot.json 当安全网（本次靠它恢复被清空的 87 道菜）。
