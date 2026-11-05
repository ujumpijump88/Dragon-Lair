---
name: building-rule-engine-cookbook
description: Build rule tools that pick N items from a pool.
---

# 通用规则引擎工具构建工作流

适用场景：食堂排菜 / 课程编排 / 推荐系统 / 排班 / 任何「从数据池按规则选 N 个」的工具。

## 触发条件

用户描述里有：
- 「需要一个工具 / 排个 / 选个 / 生成个」
- 涉及**有池子**，**按规则抽** → **输出预览**
- 想要一个**可演示版本**（web 或 CLI）

## 工作流（5 阶段）

### Phase 1 · 数据基础（P0，1–2 天）

- **先抓数据再设计**：去 GitHub / 官方站找「为同类项目准备」的清洗后数据集（如《中国食物成分表》第 6 版）。把它们 SQLite 化进单文件 `data/app.db`。
- **设计 4–5 张表**：`资源池` + `详细属性` + `评分标签` + `输出结果` + `用户偏好`。所有数值用可空值 + 单位标准化（mg / g / kcal）。
- **验证优先级**：rows 数、schema 一致性、抽样 5–10 个对的常识性数据（「鸡胸 100g ≈ 100–150 kcal」 vs USDA 数据库）。

### Phase 2 · 算法原型（P1，1–3 天）

- **数据结构**：每个对象携带主料/烹饪/菜型等元数据，便于硬约束匹配。
- **算法分两层**：
  - **硬约束** = 必要条件（结构比例 / 主料去重 / 大类覆盖 / 烹饪轮换）
  - **软约束** = 评分（评分贪心，权重可调）
- **营养估算要「分层」**：
  - 原料层 — 从数据表每 100g 可食部 × 克数 / 100
  - 烹饪调整层 — 每个 cook method 配油/盐 + 营养素热损系数，独立 dict 维护
- 每次算法改动要内嵌一个「自检」，抽 5 道菜对常识（「宫保鸡丁 ≈ 300 kcal」）。

### Phase 3 · 报表导出（P1.5，半天）

- CSV 含详细列：`每日菜牌明细 + 营养明细 + 价格`。
- 同时生成两个份量视角：全份量（采购）+ 单人 0.5 份量（厨师对实际摄入）。
- 多周测试稳定性：变异系数 ≤ 1.5% 视为合格。

### Phase 4 · Web UI（P2，半天 – 2 天）

- **栈选** Flask + 原生 HTML/JS + Chart.js CDN，**单页 4 tab**：池浏览 / 当周 / 营养可视化 / 单资源详情。
- **多线程坑** — 单例 sqlite 连接跨线程会报错 → `check_same_thread=False` 或每请求建新连接。
- 营养数据可视化：每个 tab 配一个对应的 Chart.js bar chart。
- 互动「换资源」 — POST `/api/swap`，按相同 type + 烹饪筛候选，随机选 1。

### Phase 5 · 业务配置 + JSON 备份（P2.5，1 天）

- 季节性加权、动态定价、客户偏好 → 拆 JSON 配置 + 运行时加载。
- JSON 导入导出 CLI（带版本号、确认提示、schema 校验）。
- git init + .gitignore + README.md。

## 陷阱（避免踩）

1. **调料数据稀少** — 盐、酱油、蚝油这些调味在成分表里缺，**别尝试查数据库**，直接走「烹饪调整表」（每个 cook 配固定油/盐）。
2. **「份量」概念混淆** — 150g/200g 指**端上桌成品克数**还是**原料克数**？必须立即在模型里明确（建议端上桌）。
3. **可食部比例要留住** — 鸡腿可食部 53%，直接当 100% 会高估营养；数据表里 `edible_pct` 字段是核心。
4. **算法「暗门」** — 单餐营养数字过于离谱时（如全供应 22000mg Na）→ 说明份量或模型错了，要么把「全供应」和「单人」清晰分开，要么改烹饪调整系数。
5. **每菜 code 不要瞎猜** — 6 位字符串编码都对应实际科目，**先查后写**；至少用 SQL `WHERE food_name LIKE '关键词' LIMIT 5` 双向验证一遍。
6. **JSON 导入必须先校验后清库** — `sqlite3.executescript("DELETE ...")` 会**隐式提交**，先 DELETE 后 INSERT 失败 = 库被清空。修复：(a) 循环校验每个记录的必填字段，缺字段直接放弃导入；(b) DELETE + INSERT 包在 try/except 里，失败 `rollback()`。**规则：任何「先清后写」的导入都必须有校验 + 事务 + 近期备份**（本次实战靠 snapshot 恢复被清空的 87 道菜）。
7. **Flask 复用 `cli/` 目录模块** — `from cli.x import y` 报 `'cli' is not a package`（没有 `__init__.py`）。用 `importlib.util.spec_from_file_location` 按路径加载。另注意：Flask 多线程里模块级 sqlite 连接要么 `check_same_thread=False`，要么每请求新建连接。
8. **单资源「价格覆盖」模式** — 估算函数 + 手动覆盖并存：资源表加可空列 `price_override`，估算函数先查 override 非空则直接返回，否则走算法；旧库启动时用 `PRAGMA table_info` 检查列存在性 + `ALTER TABLE ADD COLUMN` 做增量迁移。
9. **需求内部矛盾要靠多种子约束测试暴露，而不是单跑一次** — 实战：用户要「健康菜 40%」（15 道 = 6 道），又要「蒸3+拌2+烫炖2」（= 7 道）。贪心 `take_n(蒸,3)+take_n(拌,2)+take_n(烫炖,2)` 取满 7 道后 `return picks[:n]` 静默截断成 6 → **最后加的类别被砍**，每天实际只有 1 道烫/炖，单次运行看不出来。修法：(a) 写 `test_health_ratio_and_structure` 这类硬断言（每天健康数==6、蒸≥3、拌≥2、烫炖≥1），(b) 用 **100 个随机种子 × 7 天** 跑属性测试（`random.seed(seed)` 循环，任何一天破约束即失败），(c) 需求冲突时硬比例优先、结构让位（3+2+1+自由补），并把这条决策写进测试注释。
10. **贪心选满后缺类别：用「替换」不是「追加」** — 主菜池已满（9/9）但大类覆盖 < 6 时，`while len(picks) < n` 的追加循环进不去。修法：找 picks 里数量最多的大类，把其中一道换成缺失大类的菜（`picks[idx] = cand`，同步 `ids_picked`/`used_bigcats`）。且结构修复要能**突破 main_ok 去重配额**——宁可主料隔 1 天重复，也要大类覆盖（候选从全池找，不受 `main_ok` 过滤）。
11. **测试库隔离：env 变量 DB 路径 + importlib.reload** — 各模块在 import 时建立模块级 `sqlite3.connect`，测试想用临时库必须在 conftest 里：`shutil.copy2(主库, 临时库)` → `os.environ["CANTEEN_DB"]=临时库路径` → 对每个业务模块 `importlib.reload`（已 import 的）或 `importlib.import_module`。会话级 autouse fixture 做这件事，所有测试天然不污染真实数据。详见 `references/verification-and-test-isolation.md`。
12. **生产服务器多线程会炸出开发服务器掩盖的 sqlite 跨线程 bug** — Flask dev server 单线程，模块级 `sqlite3.connect` 永远不会并发冲突；换 waitress/gunicorn（多线程）后立刻报 `SQLite objects created in a thread can only be used in that same thread`。修法：(a) 模块级连接 `check_same_thread=False` + `PRAGMA journal_mode=WAL` + `PRAGMA busy_timeout=5000`（WAL 允许多线程并发读写）；(b) 每请求新建的连接用 `sqlite3.connect(DB, timeout=5.0)`。**验证**：生产模式跑 `seq 1 20 | xargs -P 10 curl /api/plan` 全 200 + `xargs -P 5` 并发 POST 全 201——单线程 dev 测试测不出这个，必须对生产 WSGI 做并发冒烟。生产入口：`python app.py --prod`（waitress，`CANTEEN_HOST/PORT/THREADS` 环境变量）。Windows 服务器部署全配方见 `references/windows-deployment.md`。

## 数据获取踩过的坑

- 写 `code:g;code:g` 模型时，**永远先 SQL 查 1–5 个真实 code 再写**。
- China Food Composition Table 在 GitHub: https://github.com/Sanotsu/china-food-composition-data — 数据格式、foodCode 前缀、仓库目录选择等细节见姊妹技能 `food-tech-domain` 的 `references/china-food-data.md`。
- 用阿里云 PyPI 镜像装 Flask：`uv pip install --index-url https://mirrors.aliyun.com/pypi/simple/ flask`。
- **写 skill frontmatter 的 YAML 坑**：`description` 里出现冒号 `:`、破折号 `—` 会让 `skill_manage create` 报 `YAML frontmatter parse error`。用单行纯文本描述（无冒号），或 `description: >-` 折叠块。

### Phase 6 · 正式验证（P3，1 天）

- **pytest 套件 + ruff lint + CI 工作流** — 用 `CANTEEN_DB` env 隔离测试库（见陷阱 11），断言硬约束（数量/比例/结构/覆盖），多随机种子跑稳定性。
- **`hermes verify` 一键验证** — 项目根放 `.hermes/environment.json`（recipe: bootstrap=`UV_VENV_CLEAR=1 uv venv .venv && uv pip install -e '.[dev]'`，test=`.venv/bin/python -m pytest`，start=`.venv/bin/python app.py`，port=5050）。注意：bootstrap 的 `pip install -e .` 需要 pyproject 有 `[build-system]` + `[tool.setuptools] packages=["cli"]`（否则 flat-layout 报错）；test/start 必须用项目 venv 的 python（hermes 自己的 venv 里没有 pytest）。
- 完整配方、conftest 模板、`hermes verify` 排错路径见 `references/verification-and-test-isolation.md`。

## 模板文件

建议子目录结构：

```
my-rule-engine/
├── data/app.db
├── config/
│   ├── pricing.json
│   └── seasonality.json
├── cli/io_json.py
├── <algo>.py           # 核心算法
├── <export>.py         # CSV + 周报
├── app.py              # Flask 后端
└── templates/index.html + static/{style.css, app.js}
```

启动：

```bash
uv venv .venv
source .venv/bin/activate
uv pip install --index-url https://mirrors.aliyun.com/pypi/simple/ flask
./.venv/bin/python app.py    # http://127.0.0.1:5050/
```

## 姊妹技能

- `food-tech-domain`（productivity）— 食堂/营养领域的深度实现：cooking adjustment 系数、foodCode 表、Flask 多线程、CSV BOM、XLSX 双 sheet、可复用模板与校验脚本。本技能是通用骨架，那个是领域血肉。
