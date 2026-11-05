---
name: food-tech-domain
description: Canteen menu planners and recipe nutrition tools.
---

# Food-Tech Domain Skill

**Use when**: Building canteen/school/employee meal planners, recipe nutrition estimators, weekly menu generators, OR any app needing authoritative Chinese food nutrition data + recipe→nutrition→meal-plan pipeline.

## Architecture Pattern (proven for single cafeteria MVP)

```
foods table (1657 rows) + nutrition table (1:1)   ← 中国食物成分表第6版
recipe_items table (recipe→food_code, raw_g)        ← 多对多关联
recipes table (cook_method, category, items)       ← 上层聚合
health_tags (auto-derived from cook_method + nut)  ← 不手填, 算法判
weekly_plan table (day, slot, recipe_id)           ← 每日菜牌
```

**Critical design decisions** (from a working session):

1. `recipes` 必须存 `items[]` 显式原料清单 + 克数, **不能从菜名猜**. 菜名带"鱼香"不等于里面有鱼. 营养估算只看 recipe_items.

2. 价格估算走"分桶粗估 + 辅材分摊". 即使 MVP 不上精确价, **数据通路要建好** (foods 有 price_per_kg 字段, recipe_items 存克数). 升级时不用改 schema.

3. **健康标签不要手填**, 用 `f(cooking_method, na_mg, fat_g, kcal)` 自动判:
   ```python
   HEALTHY_COOKS = {"清蒸", "水煮", "炖", "凉拌"}
   # 加上 Na < 800mg 阈值, 推 is_health_friendly = 0/1
   ```
   这样做评估可解释、可复现、可随着菜池扩容自动正确, 而手填标签会过期.

## Domain Pivot ⚠️ (教训)

User 会**中途切换模型**: "每餐 15 道菜 + 健康菜 40% 比例" 不是 "1 套餐 3 道". 这是两种截然不同的设计:
- **套餐模式**: 1 user = 3 道菜一组, 优化对象是"完整套餐"
- **食堂自选模式**: 每天 15 道同时出, 优化对象是"当日菜牌矩阵"

听到"食堂" + "15 道" + "%比例"就要立即转 **5 大类硬约束 + 周评分**架构, 不要在"套餐"模式上改装.

## Soft-Constraint (评分) vs Hard-Constraint

Hard constraints (= "must satisfy", filter candidates out):
- 健康池结构比例 (3 蒸 + 2 拌 + 2 烫/炖)
- 大类覆盖 ≥ 6
- 主料 1 周不超 4 次, 距上次 ≥ 2 天
- 同日单烹饪 ≤ 5 道
- 烹饪重口限 (红烧+煎+炸) 单日 ≤ 3 道 (这是 Na 控制核心)

Soft constraints (= "score to pick best", sum weighted points):
- 全局频率 (week_uses × 1.5 扣分)
- 大类空缺 (+2 加分)
- 烹饪已用 2-3 次 (-1), ≥ 4 次 (-3)
- 健康菜 (+0.5)
- **季节性对位** (in_season +1.5 / off_season -1.0; 用 `CURRENT_MONTH` 切换)
- **Na 软约束** — Na 累加到当日, < 5000 mg +2, < 7000 +0.5, > 10000 每 1 g -4
- 健康菜 (次健康, 算入健康池 + 主菜池评分)

编码模式: 把每个分数分段写成 `score += ...` 多段, 互不干扰. 调权容易.

## Cooking Adjustment Model (核心)

每种烹饪方式对每份菜的影响:
```python
COOK_ADJ = {
    "清蒸":    {"oil_g": 1, "salt_g": 1.5, "water_loss_pct": 0.25, "thermal_loss": 0.05},
    "水煮":    {"oil_g": 1, "salt_g": 2.0, "water_loss_pct": 0.30, "thermal_loss": 0.05},
    "炖":      {"oil_g": 2, "salt_g": 2.5, "water_loss_pct": 0.20, "thermal_loss": 0.08},
    "快炒":    {"oil_g": 8, "salt_g": 2.5, "water_loss_pct": 0.15, "thermal_loss": 0.10},
    "红烧":    {"oil_g": 10,"salt_g": 4.0, "water_loss_pct": 0.15, "thermal_loss": 0.10},
    "煎":      {"oil_g": 10,"salt_g": 2.0, "water_loss_pct": 0.10, "thermal_loss": 0.12},
    "炸":      {"oil_g": 18,"salt_g": 1.5, "water_loss_pct": 0.05, "thermal_loss": 0.20},
    "凉拌":    {"oil_g": 3, "salt_g": 2.0, "water_loss_pct": 0.05, "thermal_loss": 0.02},
}
# 每份: 额外 +adj["oil_g"]*9 kcal, +adj["salt_g"]*393*0.80 mg Na
# 损失: B/VC 类 × (1-water_loss), VA/VE/蛋白 × (1-thermal_loss)
```

营养估算公式 (per serving):
```
nutrition_per_serving = Σ(item.raw_g * edible_ratio/100 * food_nut_per_100g/100)
                      + cook_adj_oil_to_kcal_fat_ve
                      + cook_adj_salt_to_na
                      × (1 - thermal/water losses)
```

## Nutrition Data Source

**首选: 中国食物成分表第6版**, by Sanotsu 仓库 json 版 (vision-extracted via Qwen2.5-VL-72B):
- 仓库: https://github.com/Sanotsu/china-food-composition-data
- 路径: `json_data_vision_251206_Qwen2-5-VL-72B-Instruct/` (最新, 已剔婴幼儿奶粉)
- 规模: 1657 条食物, 15 大类, 22 营养字段

**foodCode 结构 (前 2-3 位定大类)**:
| 前缀 | 大类 |
|---|---|
| 081xxx | 猪肉 / 082xxx 牛肉 / 083xxx 羊肉 |
| 091xxx | 鸡肉 / 092xxx 鸭 |
| 111xxx | 鸡蛋 |
| 121xxx | 鱼 / 122xxx 虾 / 123xxx 蟹 / 124xxx 贝 |
| 021xxx | 薯类 (土豆=021101) / 011/012/013 谷物 |
| 031xxx | 豆制品 (豆腐代表=031301x) |
| 041-048 | 蔬菜 (叶茎花=045, 茄果瓜=043, 根菜=041, 葱蒜=044) |
| 051xxx | 菌 (木耳代表=051014 水发) / 052 藻 |
| 071-073 | 坚果种子 (花生=072002, 花生仁炒=072005) |

带 `x` 后缀 = **代表值** (e.g. `091101x` = 鸡代表值). 用代表值可一行覆盖一类菜的营养.

**已知缺数据**: 生姜查不到 (数据库用别名). 葱姜蒜以 044 系列为主. **遇到缺数据: 用相近食材或干脆省** (比如不放姜的"白切鸡").

## Hard-Constraint 模板 (15 道/餐 自选模式)

```python
# 健康池 6 道 (按比例)
health = {蒸: 3+, 拌: 2+, 烫/炖: 2+}

# 主菜池 9 道 (评分贪心)
main = {
  食品大类覆盖 >= 6: 畜/禽/鱼/蛋/豆/蔬/菌/主食,
  主料配额: 1 周 ≤ 4 次 且 距上次 ≥ 2 天,
  烹饪集中度: 同日单烹饪 ≤ 5 道,
  全局低频加分: 评分扣分 = week_uses * 1.5,
  大类空缺加分: +2.0,
  烹饪集中扣分: 已用 4 次后再用 -3.0
}
```

每周跑完必打印:
- 每日大类分布 (验证 ≥6)
- 本周主料频次 Top 10 (验证不多)
- 健康菜占比 (验证 40% ± 2%)
- 单日/单周成本 (验证预算)

## Two-View Reporting (关键)

算单一菜的 `estimate_nutrition_per_serving()` 是 1 份 (1 人份, 1 锅 1 小碟).
但食堂 1 人吃 1 餐平均选 6 道, 每道吃 ~50%. **直接把 15 道加起来报 Na=22000 mg/day 是错的**.

永远要给出两个视角:
- **全供应**: `sum(all dishes)` — 给采购看
- **单人套餐**: `personal = full * 0.6 * 0.5 / 7` (1 人 6 道 × 0.5 份 ÷ 7 天) — 给厨师看

单人 kcal 应在 [800, 960] 区间 (成年轻体力劳动者午餐目标). 这个数字用来推营养优化, 不要看全供应总量.

## Runtime Config Switch (JSON + 重启免)

营养和价格参数应放 JSON 文件, 加运行时切换函数:
- `pricing.reload_pricing(path)` — 立刻生效
- `meal_plan.set_current_month(m)` — 季节性切换

实现: 模块级 dict 缓存 + 函数 `reload_*` 改全局. 不要走 `importlib.reload()`.

## Flask + SQLite 多线程坑

`CONN = sqlite3.connect(DB)` 在模块级创建, Flask worker 线程切换时会报:
```
sqlite3.ProgrammingError: SQLite objects created in a thread can only be used in that same thread.
```

两条路:
- **A**: `sqlite3.connect(DB, check_same_thread=False)` — 允许跨线程, 简单但有锁
- **B**: 每请求 `c = sqlite3.connect(DB)` 然后 `c.close()` — 推荐, 无全局状态

每请求连接避免 worker 积累 fd, 每个 endpoint 都开/关一次.

## JSON Snapshot I/O

整库备份/恢复一定要带 `version` 字段 + 客户端确认 prompt:
- v=1 当前
- 导入时检查版本, 不匹配警告并 ask
- 替换式导入前必须 `input("确认? [y/N]: ")`

**⚠️ 先清后写 = 数据丢失 (实战踩过)**: `sqlite3.executescript("DELETE FROM ...")` 会**隐式提交**, 之后 INSERT 若失败, 库已半空且无法回滚. 修复三件套:
1. **先校验后清库** — 循环检查每个记录的必填字段 (id/name/category/dish_type/cook/items), 缺字段直接 `print(...放弃导入)` 并 return, 一条都不写.
2. **DELETE + INSERT 包在 try/except 里**, 失败 `CONN.rollback()` 再 raise; 成功才 commit.
3. **保留近期 snapshot 备份** (如 `data/snapshot.json`), 出事用它恢复 — 本次 87 道菜被清空, 全靠它救回.

`recipes` 字段顺序 = 主料/菜名/分类/烹饪/items. `pricing` 选带可编辑. INSERT 用**显式列名** (兼容 `price_override` 等新列), 不要 `INSERT INTO recipes VALUES(...)` 位置绑定.

## Output Formats

CSV 必须带 `\ufeff` BOM 否则 Excel 会乱码:
```python
return Response("\ufeff" + si.getvalue(),
                mimetype="text/csv; charset=utf-8",
                headers={"Content-Disposition":
                         f"attachment; filename={week_label}.csv"})
```

XLSX 两 sheet 模式: 详情 + 每日营养合计. 健康菜行用 `PatternFill(fgColor="C6F6D5")` 标绿.
不要在 `Workbook()` 加载后忘了 `wb.remove(wb.active)` —— 否则会有默认 "Sheet".

## Recipe CRUD 坑

`recipe_items` 在 SQLite 表存为 `code1:g1;code2:g2;...` 单字符串. 不要存 JSON 列 (SQLite 解析有版本兼容).

```python
# 写入:
",".join(f"{c}:{g}" for c, g in items)
# 读出:
[(t.split(":")[0], float(t.split(":")[1])) for t in s.split(";")]
```

## Key Pitfalls (avoid these)

1. **`dict | None` 语法**: macOS 系统 Python 3.9 不支持 PEP 604. 用 `Optional[dict]` from typing.
2. **GitHub codeload**: 新仓库默认 `main` 不是 `master`. 先 `git/trees/HEAD` 或 `api/repos/.../default_branch` 看默认分支.
3. **SQLite 参数绑定**: 不能传 Python `list`. dict-of-row 写入前 `",".join(...)` 转字符串.
4. **手工估价的价**: 即使要"按大类粗估", 也要建 `foods.price_per_kg` 字段 + 留 `recipe_items[].raw_g` 通路. 不要纯算法估算后忘记升级路径.
5. **手贴健康标签**: 会与算法冲突. 用 `cook_method` 自动判.
6. **生鲜 vs 加工**: 数据里"马铃薯"有 `021101` (生鲜) + `021101` (脱水) + `022110` (淀粉) 三种, 别混.
7. **不验 codes 直接 INSERT**: 6 位字符串易拼错. 任何新菜先 `validate_codes()` 在数据库里 `LIKE food_name% LIMIT 5` 双向核对. 别信自己.
8. **算法把"全供应"当"单人食用"**: Na 22 g/day 不是 1 人的实际摄取, 是 1 个菜单贡献的总. 必须报"单人套餐视图"或用户崩溃.
9. **Flask + 模块级 sqlite CONN**: 多线程开发服务器默认开. 用 `check_same_thread=False` 或每请求新连接.
10. **CSV 不带 BOM 给 Excel**: "中文乱码" 问题大多是缺 `\ufeff` BOM. 加 BOM 等于让 Excel 自动识别 UTF-8.
11. **Na 软约束只在单菜**: Na 来源是合成的. 算法要累加"当日已选菜 Na 总量", 然后才对每菜打分; 否则约束形同虚设.
12. **Flask 里 `from cli.xxx import y` 报 "not a package"**: `cli/` 目录没有 `__init__.py` 不是包. 用 `importlib.util.spec_from_file_location("mod", Path(__file__).parent / "cli" / "x.py")` + `exec_module` 按路径加载. 同时 Flask 端点里记得给模块级 sqlite 连接用 `check_same_thread=False` 或每请求新建.
13. **单菜手动定价 (price_override)**: 表加可空列 `price_override`, 估算函数先查 override 非空则直接返回, 否则走算法; 启动时 `PRAGMA table_info(recipes)` 检查列存在性 + `ALTER TABLE ADD COLUMN` 做旧库迁移. 这样"自动估算 + 单菜覆盖"并存, 且不会因旧库缺列崩掉.

## 链接文件

- `references/china-food-data.md` — foodCode 表 + 数据完整性记录
- `references/algorithms-and-output.md` — 算法评分 + 输出报告 + 多线程 + JSON I/O 模式 (本目录)
- `references/cooking-nutrition.md` — 烹饪修正数据出处
- `templates/recipes-table.sql` — recipes + recipe_items + health_tags schema
- `templates/meal-plan-engine.py` — 可复用的 15 道排菜引擎骨架
- `templates/output-patterns.md` — XLSX 双 sheet + 健康菜染色 + CSV BOM + Flask 流式下载代码
- `templates/flask-canteen-app.py` — Flask 后端最小化模板 (含每周 sqlite 多线程坑修复)
- `templates/build-canteen-db.sh` — 一键 import_china_food + seed_recipes + health_tags
- `scripts/verify_canteen_paths.py` — 重复可跑的 ad-hoc 校验 (API + 算法 + 配置 + JSON)
