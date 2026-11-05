---
name: python-web-delivery-audit
description: Use when auditing a Python web project before delivery.
---

# Python Web 项目交付审计

核心前提：**跑得起来 不等于 可交付**。dev 单线程环境会掩盖并发缺陷；临时脚本跑通不等于测试套件全绿。

审计目标：找出「dev 环境掩盖、生产环境暴露」的缺陷，并把一次性人工验证固化为可重复执行的资产。

完整版（含全部模板与实例）：`<项目>/docs/AUDIT_PROMPT.md`

## 六个阶段

### 阶段 0 · 基线
确认项目结构、依赖、数据规模（查到具体数字，不写「若干」）、当前 commit 与未提交改动。

### 阶段 1 · 静态检查
```bash
python -m py_compile *.py cli/*.py
node --check static/app.js        # 前端常被漏查
.venv/bin/ruff check . --fix && .venv/bin/ruff check .
```
必须清零。常见手修：`B023` 闭包未绑定循环变量（改默认参数）、`F841` 重构残留变量、`E701` 单行多语句。

### 阶段 2 · 隔离化单元测试（关键）

**先做 DB 路径可注入**，否则测试污染真实数据：
```python
DB = Path(os.environ.get("APP_DB", str(Path(__file__).parent / "data" / "app.db")))
CONN = sqlite3.connect(DB, check_same_thread=False)
CONN.execute("PRAGMA journal_mode=WAL")
CONN.execute("PRAGMA busy_timeout=5000")
```

**conftest 顺序至关重要**：复制真实库到临时目录 → 设环境变量 → `importlib.reload` 业务模块（模块级连接是 import 时建立的）→ 断言临时库有数据（否则后续全是假绿）。

session fixture 必须设 `app.config["PROPAGATE_EXCEPTIONS"] = True`，否则 500 吞掉 traceback。

**断言必须匹配函数真实语义**：不要凭直觉写数值断言。先跑一次打印真实值，再写断言，并在 docstring 写明语义。

**多种随机种子压稳定性**：算法含随机时，`for seed in range(100)` 跑 100 种子 × N 天，单次通过不算通过。

### 阶段 3 · 接口与集成
逐个 endpoint 覆盖正常 + 404/409/400 分支、CRUD roundtrip、导出格式（CSV 首字节 `\ufeff` BOM，否则 Excel 中文乱码；XLSX 首两字节 `PK`）。修改型操作后必须验证派生数据重算。

### 阶段 4 · 生产模式并发审计（价值最高）

dev server 单线程掩盖并发缺陷，生产 WSGI（waitress/gunicorn）立刻暴露。

SQLite 跨线程症状：`SQLite objects created in a thread can only be used in that same thread`。
修复三件套：模块级连接加 `check_same_thread=False`；每请求连接加 `timeout=5.0`；两者都加 `PRAGMA journal_mode=WAL` + `busy_timeout=5000`。

并发冒烟：
```bash
seq 1 20 | xargs -P 10 -I{} curl -s -o /dev/null -w '%{http_code}\n' \
  "http://127.0.0.1:$PORT/api/plan" | sort | uniq -c    # 期望 20×200
```
任何非 2xx 都是缺陷。waitress 只回 500 页面，traceback 在 stdout 日志里。

若交付前需要用真实 PostgreSQL（而非 SQLite）验证多线程/事务语义，本机建库与冒烟流程见技能 `local-dev-services`（含 `pgctl` 起停脚本与中文/时区冒烟测试）。

### 阶段 5 · 验证清单固化
- `pyproject.toml`：必须有 `[build-system]` + `[tool.setuptools] packages=[...]`，否则 flat layout 报 `Multiple top-level packages discovered`
- CI：`.gitea/workflows/ci.yaml`（Gitea Actions 语法兼容 GitHub Actions）
- `.hermes/environment.json`：bootstrap 用 `UV_VENV_CLEAR=1` 保证幂等；test/start 必须写 `.venv/bin/python`（否则用宿主 venv 找不到 pytest）
- 收口：`hermes verify --json` 期望 `"ok": true` + readiness `statusCode: 200`

### 阶段 6 · 报告
固定格式：验证状态（fresh/stale）+ 命令-结果表格 + 已修缺陷（症状→根因→修复→回归测试名）+ **明确未覆盖** + 结论。

## 铁律

- 只跑过一次的临时脚本**不等于** suite green，报告里必须区分
- **代码改动后验证立即 stale**，必须重跑；不得引用上一轮结果
- 不确定的写「未覆盖」，不要写「应该没问题」
- 每发现 bug 立即补回归测试，否则下次会复发

## 六类高发缺陷（逐条排查）

1. **破坏性操作先删后写**：`executescript(DELETE)` 会隐式提交，随后 INSERT 失败 → 数据丢失。修：先校验输入完整性，再删；写入包 `try/except` + `rollback`。
2. **约束自相矛盾**：需求 3+2+2=7 项但容量只有 6 位 → `return picks[:n]` 静默截断。修：显式对齐容量与结构，测试逐条断言。
3. **结构修复只追加不替换**：容器满时 `while len(picks) < n` 恒假 → 修不动。修：支持替换冗余项。
4. **约束优先级错误**：去重规则拦住了所有能补结构的候选。修：结构约束优先，必要时允许突破去重。
5. **dev 单线程掩盖并发**：见阶段 4。
6. **断言与实际语义不符**：见阶段 2。

## 交付前最后 5 问

1. 测试跑在临时库上吗？真实数据是否被污染？
2. 生产模式（多线程 WSGI）下所有接口是否 2xx？
3. 破坏性操作失败时数据安全吗？
4. 随机算法 100 个种子是否 100% 满足硬约束？
5. `hermes verify --json` 的 `ok` 是 `true` 吗？
