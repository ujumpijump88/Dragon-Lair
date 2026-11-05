#!/bin/bash
# WPS 鉴权方式批量探测矩阵 — 用一条未知凭证快速判定网关接受的鉴权位置与格式
# 用法：WPS_AGENT_KEY="xxx.yyy" bash probe_wps_auth.sh [base_url]
# 不硬编码任何密钥；密钥从环境变量读。
# 判定语义：
#   403 "does not support app authorization" = Bearer 位正确、身份是 app，但该 API 仅 delegated
#   401 "invalid token format"               = Bearer 位正确、token 被解析但格式无效（如非 JWT）
#   401 "凭证无效"                            = 凭证位正确但内容无效（如未激活/需交换）
#   401 "账号未登录"                          = 该鉴权位不被识别
#   400 "authorization header not found"     = 鉴权头名不对（只认 Authorization）

KEY="${WPS_AGENT_KEY:?需要 WPS_AGENT_KEY 环境变量}"
CID="${KEY%%.*}"
CSEC="${KEY#*.}"
BASIC=$(printf "%s:%s" "$CID" "$CSEC" | base64)
URL="${1:-https://openapi.wps.cn}"

probe() {
  local desc="$1"; shift
  local code=$(curl -s --max-time 12 -o /tmp/probe.json -w "%{http_code}" "$@" "${URL}")
  echo "[$code] $desc -> $(head -c 180 /tmp/probe.json | tr -d '\n')"
}

probe "Bearer KEY"        -H "Authorization: Bearer ${KEY}"
probe "裸 KEY"            -H "Authorization: ${KEY}"
probe "Basic 前段:后段"    -H "Authorization: Basic ${BASIC}"
probe "X-API-Key"         -H "X-API-Key: ${KEY}"
probe "api-key header"    -H "api-key: ${KEY}"
probe "X-Ak/X-Sk"         -H "X-Ak: ${CID}" -H "X-Sk: ${CSEC}"

echo "--- oauth2/token (client_credentials 变体) ---"
t() {
  local desc="$1" body="$2"
  local code=$(curl -s --max-time 12 -o /tmp/t.json -w "%{http_code}" -X POST "${URL}/oauth2/token" \
    -H "Content-Type: application/x-www-form-urlencoded" -d "$body")
  echo "[$code] $desc -> $(head -c 180 /tmp/t.json | tr -d '\n')"
}
t "整体当 client_id"      "grant_type=client_credentials&client_id=${KEY}"
t "前段 id + 后段 secret" "grant_type=client_credentials&client_id=${CID}&client_secret=${CSEC}"
t "api_key grant"         "grant_type=api_key&api_key=${KEY}"
