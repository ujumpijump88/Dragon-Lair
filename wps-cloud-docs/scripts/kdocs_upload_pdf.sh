#!/usr/bin/env bash
# kdocs_upload_pdf.sh - 把本地 PDF 上传到 WPS 云文档指定 mine 数字目录
# 用法: kdocs_upload_pdf.sh <本地pdf路径> <mine数字目录ID> [目标文件名]
# 规避 kdocs-cli v2.4.0 的 400100 坑:
#   新建 PDF 不能带 parent_id/drive_id -> 先裸上传到默认位, 再 move-file 进目标.
#   move-file 的 dst_parent_id 必须填文件夹的 file_id(vAEgk...), 不是 mine 数字.
set -e
PDF="$1"; MINE="$2"; NAME="${3:-$(basename "$PDF")}"
CLI="${KDOCS_CLI:-$HOME/.local/bin/kdocs-cli}"
[ -f "$PDF" ] || { echo "PDF 不存在: $PDF" >&2; exit 1; }
[ -n "$MINE" ] || { echo "缺少 mine 目录 ID" >&2; exit 1; }

# 1) mine 数字 -> 文件夹 file_id + drive_id
INFO=$( "$CLI" drive get-file-info "{\"file_id\":\"$MINE\"}" )
FOLDER_ID=$( echo "$INFO" | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['data']['data']['id'])" )
DRIVE_ID=$( echo "$INFO" | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['data']['data']['drive_id'])" )
echo "文件夹 file_id=$FOLDER_ID drive_id=$DRIVE_ID"

# 2) 裸上传(不带目录参数) -> 拿新文件 id
python3 - "$PDF" "$NAME" <<'PY'
import base64,json,sys
pdf, name = sys.argv[1], sys.argv[2]
b=base64.b64encode(open(pdf,'rb').read()).decode()
json.dump({"name":name,"content_base64":b}, open("/tmp/kdocs_payload.json","w"))
PY
UP=$( "$CLI" drive upload-file @/tmp/kdocs_payload.json )
FILE_ID=$( echo "$UP" | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['data']['id'])" )
LINK=$( echo "$UP" | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['data']['link_url'])" )
echo "已上传: $FILE_ID  $LINK"

# 3) 移入目标文件夹(dst_parent_id 用文件夹 file_id)
"$CLI" drive move-file "{\"drive_id\":\"$DRIVE_ID\",\"file_ids\":[\"$FILE_ID\"],\"dst_drive_id\":\"$DRIVE_ID\",\"dst_parent_id\":\"$FOLDER_ID\"}" >/dev/null
echo "已移入目录: $LINK"
