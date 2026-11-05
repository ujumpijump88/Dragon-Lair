# WPS Open Platform — verified notes (2026-08-08)

## Doc source trick
- `open.wps.cn` and `developer.kdocs.cn` both serve the SAME SPA shell: `https://cloudcdn.qwps.cn/open/web_open-homepage/index-CIrwMuEK.js` (~10 MB).
- Raw markdown source: `https://open-docs.wpscdn.cn/docs-md/zh/app-integration-dev/<path>.md`
- Doc-app bundle (nav/routes/i18n strings): `https://cloudcdn.qwps.cn/open/doc-app-web/assets/index-DfidmDvy.js` (~21 MB) — grep for `"/documents/..."`, `mcp`, `aiAgentManagement`.

## Verified markdown docs
| Path | Content |
|---|---|
| guide/self-app/summary | 6-step app dev flow; admin approve at work.wps.cn/xz/app/audit |
| guide/app-type | 3 app types; forms: 后台服务/网页应用/机器人/小组件 |
| wps365/server/certification-authorization/summary | user vs app access tokens; selection guidance |
| wps365/server/api-description/flow | call flow: app → scopes → token → data permissions → IP whitelist |
| mcp-server/introduction | MCP intro; trial form f.kdocs.cn/ksform/w/write/KrrG1pwZ |
| cli/wps365-cli-installation-guide.md (open.wps.cn/documents/cli/) | agent-facing install + full scope tables |

## openapi.wps.cn probes
- `GET /oauth2/device/verify` → 200 (HTML error page)
- `POST /oauth2/token` with JSON → `415 {"code":41500001,"msg":"Content-Type unsupported"}` → form-encoded required
- `GET /v1/files`, `/v7/*` etc → 404 without valid token (auth-gated; existence unknown until authed)

## API families in bundled spec (wps365-cli v0.3.1 → ~/Library/Application Support/wps365-cli/spec/api.yaml, ~1.8MB)
- AI: `/v7/aiopen/*` — drives/{drive_id}/files/{file_id}/qa, drives/qa, files/search, sessions(+create/close/messages), ai_table_assistant, aigc/compose (libraries/ref_files), chunks/search, doc_operate_tasks, slides/generator, resource/files/{request_upload,commit_upload}
- AI docs: `/v7/aidocs/*` — contract_extract, doclib_list, drive/{drive_id}/file/{parent_id}/upload, extract, parse_content, spaces
- AirPage: `/v7/airpage/{file_id}/*` — blocks CRUD/convert, export_to_docx/pdf/json, import_json_data
- AirSheet: `/v7/airsheet/*` — worksheets, data_validations, filters, range_data/find
- AIPPT: `/v7/aippt/*` — gen_slides_from_multipages, theme_tpl/list
- Apps: `/v7/apps/{app_id}/configs/chat` (+update)
- Core: `/v7/chats*`, `/v7/calendars*`, `/v7/attendance*`, `/v7/audit*`, `/v7/announce/*`, `/v7/asr_tasks/*`

## Scope families (CLI install guide; readwrite 含 read, 只需申请 readwrite)
- 通讯录: kso.user_base.read, kso.user_current_id.read, kso.contact.read/readwrite
- 日历: kso.calendar.read/readwrite, kso.calendar_events.read/readwrite
- IM: kso.chat.read/readwrite, kso.chat_message.readwrite (含发送), kso.chat_bookmark/pin.readwrite, kso.chat_message_urgent_sms.readwrite
- 邮箱: kso.mail.read/readwrite (含发送), kso.mailbox.read, kso.mail_group/contact.*
- 云文档: kso.file.read/readwrite (含上传下载), kso.file_search.readwrite, kso.file_link/permission/version.readwrite, kso.drive.readwrite, kso.doclib.readwrite
- 多维表格: kso.dbsheet.read/readwrite (增删改查)
- 会议: kso.meeting.read/readwrite, kso.meeting_minutes*, kso.meeting_recording*, kso.meeting_rooms.*

## AI 助理身份 (from user screenshot OCR — WPS client 智能体管理)
Dialog "AI助理能力说明": identity designed for Agents; represents user within granted scope (文档/云盘/IM/会议); key = 访问密码; default = full open-platform permissions; rotation + third-party caution. UI actions: 生成访问密码 / 重置密码. **Call protocol UNVERIFIED** (no key at session end).

## CLI facts
- `wps365-cli version` → `cli: 0.3.1 / curated: 1.0`
- Config/spec dir: `~/Library/Application Support/wps365-cli/` (spec/ inside)
- Commands: auth {setup,login,logout,refresh,status,token,clean}, config {get,set,init,path,unset}, provider {add,list,remove,show,update}, spec {status,update}, api get|post, drive, dbsheet, im, mail, meeting, calendar, user
