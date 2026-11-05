#!/bin/bash
# pgctl — Homebrew PostgreSQL 一键控制（无 Docker）
# 用法: pgctl {start|stop|restart|status|log|psql|url}
# 环境变量:
#   PGCTL_FORMULA  formula 名（默认 postgresql@17）
#   PGCTL_URL      连接串（默认 postgresql://app:app_dev_pwd@127.0.0.1:5432/app_dev_db）
FORMULA="${PGCTL_FORMULA:-postgresql@17}"
DB_URL="${PGCTL_URL:-postgresql://app:app_dev_pwd@127.0.0.1:5432/app_dev_db}"
export PATH="/opt/homebrew/opt/${FORMULA}/bin:$PATH"
LOGFILE="/opt/homebrew/var/log/${FORMULA}.log"

wait_ready() {
  for _ in $(seq 1 20); do pg_isready -h 127.0.0.1 -q && return 0; sleep 0.5; done
  echo "启动超时，查看日志: $LOGFILE" >&2
  return 1
}

case "$1" in
  start)   brew services start "$FORMULA" >/dev/null 2>&1
           wait_ready && echo "已启动 (端口 5432)" ;;
  stop)    brew services stop "$FORMULA" >/dev/null 2>&1 && echo "已停止" ;;
  restart) brew services restart "$FORMULA" >/dev/null 2>&1
           wait_ready && echo "已重启" ;;
  status)  brew services list | grep "${FORMULA%@*}"
           pg_isready -h 127.0.0.1 ;;
  log)     tail -f "$LOGFILE" ;;
  psql)    shift
           # 从连接串拆出密码，避免交互提示
           pw=$(printf '%s' "$DB_URL" | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')
           PGPASSWORD="$pw" psql "$DB_URL" "$@" ;;
  url)     echo "$DB_URL" ;;
  *)       echo "用法: pgctl {start|stop|restart|status|log|psql|url}" >&2; exit 1 ;;
esac
