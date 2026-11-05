#!/usr/bin/env bash
# Launch dsh web with the DeepSeek key pulled from ~/.hermes/.env
# Adapt the env-file path and working dir if the user's setup differs.
set -a
# source only the DEEPSEEK_API_KEY line from ~/.hermes/.env
while IFS= read -r line; do
  case "$line" in
    DEEPSEEK_API_KEY=*) export "$line" ;;
  esac
done < ~/.hermes/.env
set +a

if [ -z "$DEEPSEEK_API_KEY" ]; then
  echo "ERROR: DEEPSEEK_API_KEY not found in ~/.hermes/.env" >&2
  exit 1
fi
echo "DEEPSEEK_API_KEY injected (len ${#DEEPSEEK_API_KEY})"
cd /Users/xiebojun/Hermes
exec npx @deepseek-ai/dsh web "$@"
