#!/bin/bash
# 自适应 kanban 防休眠守卫（cron 每 5 分钟触发，no_agent 静默 watchdog 模式）：
#   - 看板有活动任务(running/ready/todo/triage) 且 caffeinate 未运行 → 启动并记录 pid
#   - 看板空闲 且 caffeinate 在运行 → 释放
#   - 平时静默（无输出），只有状态变化才输出
# 部署：复制到 ~/.hermes/scripts/ → chmod +x → 手动跑一次验证 → cronjob no_agent 注册
# 验证：pmset -g assertions | grep caffeinate（应有 PreventSystemSleep /
#       PreventUserIdleSystemSleep / PreventUserIdleDisplaySleep / PreventDiskIdle）
# 幂等：caffeinate 存活时重跑本脚本必须静默；pid 文件归属保证不误杀他人 caffeinate
export NO_PROXY=localhost,127.0.0.1
PIDFILE="$HOME/.hermes/scripts/.kanban-caffeinate.pid"

ACTIVE=$(NO_PROXY=localhost,127.0.0.1 hermes kanban list --json 2>/dev/null | python3 -c "
import json,sys
try:
    ts=json.load(sys.stdin)
    active={'running','ready','todo','triage'}
    print(1 if any(t.get('status','') in active for t in ts) else 0)
except Exception:
    print(0)
")

CAFF_PID=""
[ -f "$PIDFILE" ] && CAFF_PID=$(cat "$PIDFILE" 2>/dev/null)
ALIVE=0
if [ -n "$CAFF_PID" ] && kill -0 "$CAFF_PID" 2>/dev/null; then ALIVE=1; fi

if [ "$ACTIVE" = "1" ] && [ "$ALIVE" = "0" ]; then
    nohup caffeinate -dims >/dev/null 2>&1 &
    echo $! > "$PIDFILE"
    echo "kanban-active: caffeinate started pid=$!"
elif [ "$ACTIVE" = "0" ] && [ "$ALIVE" = "1" ]; then
    kill "$CAFF_PID" 2>/dev/null
    rm -f "$PIDFILE"
    echo "kanban-idle: caffeinate $CAFF_PID released"
elif [ "$ALIVE" = "0" ] && [ -f "$PIDFILE" ]; then
    rm -f "$PIDFILE"   # 残留 pid 文件清理，下次 tick 重新拉起
fi
exit 0
