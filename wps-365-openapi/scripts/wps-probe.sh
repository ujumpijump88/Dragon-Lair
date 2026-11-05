#!/bin/bash
# WPS 开放平台鉴权探测脚本 —— 判断一个凭证/密钥在哪些网关有效
# 用法: bash wps-probe.sh <凭证>
# 示例: bash wps-probe.sh "apik:xxxx.yyyy"   （AI 助理密钥）
#       bash wps-probe.sh "<access_token>"   （OAuth token）
KEY="$1"
if [ -z "$KEY" ]; then echo "用法: $0 <凭证>"; exit 1; fi

echo "===== 1. openapi.wps.cn REST ====="
curl -s --max-time 12 -o /tmp/wp.json -w "[%{http_code}] " -H "Authorization: Bearer ${KEY}" "https://openapi.wps.cn/v7/drives?allotee_type=user&page_size=5"
head -c 200 /tmp/wp.json | tr -d '\n'; echo

echo "===== 2. openapi.wps.cn MCP (云文档) ====="
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"1.0"}}}'
curl -s --max-time 12 -o /tmp/wp.json -w "[%{http_code}] " -X POST "https://openapi.wps.cn/mcp/v2/kso-yundoc/message" \
  -H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -d "$INIT"
head -c 200 /tmp/wp.json | tr -d '\n'; echo

echo "===== 3. agentspace.wps.cn ====="
curl -s --max-time 12 -o /tmp/wp.json -w "[%{http_code}] " -H "Authorization: Bearer ${KEY}" "https://agentspace.wps.cn/api/v1/agent/list"
head -c 200 /tmp/wp.json | tr -d '\n'; echo

echo "===== 4. oauth2/token client_credentials（密钥两段式拆分尝试）====="
CID="${KEY%%.*}"; CSEC="${KEY#*.}"
curl -s --max-time 12 -o /tmp/wp.json -w "[%{http_code}] " -X POST "https://openapi.wps.cn/oauth2/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=${CID}&client_secret=${CSEC}"
head -c 200 /tmp/wp.json | tr -d '\n'; echo

echo
echo "判定指引:"
echo "  [200] 某网关有效 → 该凭证是有效的 access_token/凭证，可直接用"
echo "  401 invalid token format → 凭证≠token，需先经 OAuth/交换流程"
echo "  403 does not support app authorization → 凭证是 app 身份，需用户授权 token"
echo "  invalid_scope → 应用未申请该权限（去开发者后台申请+审核）"
