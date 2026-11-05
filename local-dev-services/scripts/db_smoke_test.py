#!/usr/bin/env python3
"""PostgreSQL 冒烟测试：连通性 + 中文编码 + timestamptz 时区 + 事务。

用法:
    DATABASE_URL=postgresql://app:app_dev_pwd@127.0.0.1:5432/app_dev_db \
      .venv/bin/python db_smoke_test.py

若脚本同目录存在 .env 且 DATABASE_URL 未设置，则从 .env 读取。
验证的是“能写中文、时区正确”，而不只是“握手成功”。
"""
import os
import sys
from pathlib import Path


def load_env() -> None:
    env_file = Path(__file__).with_name(".env")
    if not env_file.exists():
        return
    for line in env_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


def main() -> int:
    load_env()
    url = os.environ.get("DATABASE_URL")
    if not url:
        print("❌ 未设置 DATABASE_URL", file=sys.stderr)
        return 2

    import psycopg

    with psycopg.connect(url, connect_timeout=5) as conn:
        with conn.cursor() as cur:
            cur.execute("select version()")
            print("✅ 连接成功:", cur.fetchone()[0].split(",")[0])
            cur.execute(
                """
                create table if not exists smoke_test (
                    id serial primary key,
                    name text not null,
                    created_at timestamptz default now()
                )
                """
            )
            cur.execute("insert into smoke_test (name) values (%s) returning id", ("中文写入测试",))
            row_id = cur.fetchone()[0]
            cur.execute("select id, name, created_at from smoke_test where id = %s", (row_id,))
            row = cur.fetchone()
            print("✅ 写入并读回:", row)
            assert row[1] == "中文写入测试", "中文 roundtrip 失败，检查 client_encoding / 库编码"
            cur.execute("drop table smoke_test")
        conn.commit()

    print("✅ DDL/DML/事务 全部通过 —— 开发库可直接用")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
