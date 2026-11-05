# Windows 服务器部署配方（waitress + NSSM）

把 Flask 工具部署到公司内网 Windows 服务器（用户场景：Windows Server，无 Docker，需开机自启 + 崩溃重启）。

## 核心：生产入口（app.py 末尾）

```python
if __name__ == "__main__":
    import os, sys
    if "--prod" in sys.argv or os.environ.get("CANTEEN_PROD") == "1":
        from waitress import serve
        host = os.environ.get("CANTEEN_HOST", "0.0.0.0")   # 0.0.0.0 = 内网可访问
        port = int(os.environ.get("CANTEEN_PORT", "5050"))
        threads = int(os.environ.get("CANTEEN_THREADS", "8"))
        serve(app, host=host, port=port, threads=threads)
    else:
        app.run(host="127.0.0.1", port=5050, debug=True)   # 开发模式
```

- 依赖加 `waitress>=3.0`（纯 Python WSGI，Windows 原生，无需编译）。
- 开发模式保持 `127.0.0.1` + debug，生产用 `0.0.0.0` + waitress，两模式共用一个 `__main__`。

## 必踩的坑：sqlite 跨线程（waitress 多线程才会爆）

- Flask dev server 单线程 → 模块级 `sqlite3.connect` 从不冲突 → 单测全绿。
- waitress 8 线程并发 → 立刻 `sqlite3.ProgrammingError: SQLite objects created in a thread can only be used in that same thread`（app 日志里出现，HTTP 500）。
- 修复三件套（每个持模块级连接的 .py）：
  ```python
  CONN = sqlite3.connect(DB, check_same_thread=False)
  CONN.execute("PRAGMA journal_mode=WAL")
  CONN.execute("PRAGMA busy_timeout=5000")
  ```
  每请求新建连接的函数用 `sqlite3.connect(DB, timeout=5.0)`。
- 生产并发冒烟（必须做，单线程测试测不出）：
  ```bash
  seq 1 20 | xargs -P 10 -I{} curl -s -o /dev/null -w '%{http_code}\n' 'http://127.0.0.1:5052/api/plan?weeks=1' | sort | uniq -c
  # 期望全 200
  ```

## 交付物清单（deploy/ 目录）

| 文件 | 作用 |
|---|---|
| `install.bat` | 检查 python → 建 .venv → `pip install -r requirements.txt -i 阿里云镜像` → 首次导入数据（import_china_food + seed_recipes + health_tags） |
| `start_service.bat` | `chcp 65001` + `.venv\Scripts\python.exe app.py --prod` |
| `requirements.txt` | flask / openpyxl / waitress |
| `README.txt` | 部署说明（防火墙 / NSSM / 备份 / 常见问题） |

bat 文件要点：
- 首行 `chcp 65001 >nul` 解决中文乱码（bat 需 UTF-8 保存）。
- 路径用 `%~dp0` 锚定自身目录。
- 国内网络 `pip install -i https://mirrors.aliyun.com/pypi/simple/`，失败回退官方源。

## 防火墙放行（Windows 必做）

```bat
netsh advfirewall firewall add rule name="CanteenMenu" dir=in action=allow protocol=TCP localport=5050
```

## 开机自启（NSSM 注册服务）

```bat
nssm install CanteenMenu "C:\CanteenMenu\.venv\Scripts\python.exe" "C:\CanteenMenu\app.py" --prod
nssm set CanteenMenu AppDirectory C:\CanteenMenu
nssm set CanteenMenu Start SERVICE_AUTO_START
nssm set CanteenMenu AppStdout C:\CanteenMenu\logs\out.log
nssm set CanteenMenu AppStderr C:\CanteenMenu\logs\err.log
nssm start CanteenMenu
```

## 数据备份

- SQLite 单文件 `data\canteen.db`：计划任务每日 copy 到 backup\（文件名带日期）。
- 或 Web 界面手动导出 JSON 快照（`/api/snapshot/export`），恢复用导入 JSON。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| CANTEEN_PROD | — | =1 强制生产模式 |
| CANTEEN_HOST | 0.0.0.0 | 监听地址 |
| CANTEEN_PORT | 5050 | 端口 |
| CANTEEN_THREADS | 8 | waitress 线程数 |
