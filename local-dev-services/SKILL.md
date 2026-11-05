---
name: local-dev-services
description: Use when a project needs a local DB/cache for dev/test.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [postgres, postgresql, homebrew, local-dev, database, docker-alternative]
    related_skills: [python-web-delivery-audit, synology-docker-deployment]
---

# 本机开发服务（Docker-free 路径）

## When to Use

- 项目需要本地数据库（Postgres/MySQL/Redis）做开发测试，而本机**没有 Docker 或不需要 Docker**。
- 用户问“没有 PostgreSQL/Docker 命令，开发测试怎么办”。
- 需要在 macOS 上装、配、验证一个常驻本地服务，并给用户一个可复用的起停入口。
- 不适用：要跑别人的镜像或 docker-compose 编排（那时先装 colima，见 §1 决策表）。

核心前提：**“本机没 Docker”不是阻塞，绝大多数开发测试只需要一个本地数据库进程。** 但也不要凭假设装库——先看项目实际用什么。

支持的脚本：`scripts/pgctl.sh`（起停/进库/打印连接串）、`scripts/db_smoke_test.py`（编码+时区冒烟）。

## 0 · 先确认项目真的要这个库
```bash
cat requirements.txt 2>/dev/null
ls */requirements.txt 2>/dev/null
grep -rniE 'postgres|psycopg|DATABASE_URL|mysql|redis' --include='*.py' --include='*.txt' --include='*.yml' --include='*.yaml' --include='.env*' . | grep -v '\.venv' | head -20
```
- 只有 `sqlite3` → 不需要任何服务端库，别装。
- 有 `psycopg` / `postgresql://` → 装 PG，版本按部署目标定（PG17 为当前稳妥默认）。

同时说明结论：客户端库（psycopg）与服务器是两件事，`pip install psycopg` 不等于有库可连。

## 1 · 路径决策（一次问清，别分多轮）

| 需求 | 选 |
|---|---|
| 只要本地库做开发测试 | 原生 Homebrew 服务（最快、最省电、无 GUI 开销） |
| 要跑别人的镜像 / `docker-compose.yml` / 多服务编排 | `brew install colima docker && colima start`（免费无 GUI；偏 GUI 用 OrbStack） |
| 两者都要 | 原生库做日常 + colima 备用；端口不冲突可共存 |

一次 clarify 问两件事就够：走哪条路 + 库名/账号（新项目默认 `app` / `app_dev_db` / `127.0.0.1:5432`）。问到库名/密码后**直接装并跑通验证**，不要再逐步确认。

## 2 · 装 + 起（PG17 为例）
```bash
brew install postgresql@17          # initdb 自动完成
brew services start postgresql@17   # 登录自启
for i in $(seq 1 20); do pg_isready -h 127.0.0.1 -q && break; sleep 0.5; done
pg_isready -h 127.0.0.1
```
- `postgresql@NN` 是 **keg-only**：`psql/pg_dump/createdb` 不在默认 PATH。先 `export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"`，再**幂等**写进 `~/.zshrc`（`grep -q ... || printf '...' >> ~/.zshrc`，不要重复追加）。
- 就绪用 `pg_isready` 轮询，不要 `sleep 5` 赌时间。
- 装完先确认 brew 存在：`/opt/homebrew/bin/brew --version`（不要沿用“本机没有 Homebrew”的旧假设）。

## 3 · 打开真密码认证（否则“本地能连、上生产认证失败”）

Homebrew 的 initdb 默认给 TCP 连接 `trust`，即使带密码的连接串也照样连上——这会掩盖认证链路的配置错误。

```bash
HBA=/opt/homebrew/var/postgresql@17/pg_hba.conf
cp "$HBA" "$HBA.bak.$(date +%s)"     # 改前必备份
# 只把 127.0.0.1/32 与 ::1/128 的 host 行由 trust 改成 scram-sha-256
# 保留 local socket 的 trust，本机管理（psql -d postgres）不受影响
psql -d postgres -c "ALTER SYSTEM SET password_encryption='scram-sha-256';" \
                  -c "SELECT pg_reload_conf();"
```

改完必须用 **TCP + 密码**验证，socket 连上不算数：
```bash
PGPASSWORD=app_dev_pwd psql "postgresql://app:app_dev_pwd@127.0.0.1:5432/app_dev_db" \
  -c "select current_user, inet_server_addr();"
```

## 4 · 建角色与库（幂等写法）
```sql
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app') THEN
  CREATE ROLE app LOGIN PASSWORD 'app_dev_pwd' CREATEDB;
ELSE ALTER ROLE app WITH LOGIN PASSWORD 'app_dev_pwd' CREATEDB; END IF; END $$;
```
```bash
psql -d postgres -tc "SELECT 1 FROM pg_database WHERE datname='app_dev_db'" | grep -q 1 \
  || psql -d postgres -c "CREATE DATABASE app_dev_db OWNER app;"
```
有测试套件时顺手建 `app_test_db`（同 owner），让测试跑在测试库而非开发库。

## 5 · 冒烟测试：证明编码与时区，而不只是“能连”

跑 `scripts/db_smoke_test.py`：建表 → 插中文 → 读回 → drop。中文能 roundtrip 才说明 UTF-8 没配错；`timestamptz` 读回带 `Asia/Shanghai` 才说明时区对。

依赖装进项目 `.venv`（uv + 阿里云镜像），用 `.venv/bin/python` 跑：
```bash
uv venv .venv
uv pip install --python .venv/bin/python --index-url https://mirrors.aliyun.com/pypi/simple/ "psycopg[binary]" sqlalchemy
DATABASE_URL="postgresql://app:app_dev_pwd@127.0.0.1:5432/app_dev_db" .venv/bin/python scripts/db_smoke_test.py
```

## 6 · 给用户一个可复用的起停入口

把 `scripts/pgctl.sh` 装到 `~/.local/bin/pgctl` 并 `chmod +x`：`start|stop|restart|status|log|psql|url`，连接串集中在一处。用户会反复用这条命令，比记 `brew services` 子命令省事。装完实际跑一次 `pgctl status` 和 `pgctl restart` 贴输出。

## 铁律 / 坑

- **先查项目再装库**：Flask+sqlite3 的项目不需要 PG，装了只是噪音。
- **keg-only 的 PATH 必须显式处理**，否则用户新开终端 `psql: command not found`，“装好了”当场被打脸；改完用 `zsh -ic 'which psql'` 验证新 shell 生效。
- **别为了省事留在 `trust`**：TCP 走 scram，才真实验证密码链路与生产一致性。
- **交付口径要诚实**：无 Docker 的真实差别只有“跑他人镜像 / 多服务编排”，其余等价。既不要宣称完全等价，也不要把缺 Docker 说成阻塞。
- 数据目录 `/opt/homebrew/var/postgresql@NN`，停服务或卸载 formula 不删数据；重建干净库用 `dropdb/createdb`，不要 `rm -rf` 数据目录。
- 收尾把**版本 / 端口 / 库名 / 密码 / 连接串**用表格给出，并贴实际验证输出（`pg_isready`、冒烟脚本），不要只描述“已配置好”。
- 顺手把客户端工具也验一遍（`pg_dump --version`），备份/迁移脚本后面要用。
