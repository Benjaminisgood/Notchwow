# 自动化 Agent 指南

这份文档用于指导生成 Shell、Python、AppleScript 和 `launchd` plist 的 agent。`notchwow` 把脚本编辑、直接运行和 Jobs 编排放在同一个工作台中，但脚本源文件与运行产物必须分开管理。

## 1. 安装工作区说明

仓库提供可下发到 `~/keyoti` 的 `AGENTS.md` 模板：

```bash
./Scripts/install-keyoti-agent-guide.sh
```

默认不会覆盖已有 `~/keyoti/AGENTS.md`。需要同步模板更新时显式执行：

```bash
FORCE=1 ./Scripts/install-keyoti-agent-guide.sh
```

## 2. 目录约定

| 类型 | 源文件位置 | 运行方式 |
| --- | --- | --- |
| Shell | `~/keyoti/shs/workspace-scripts/*.sh` | `/bin/zsh /absolute/path/script.sh` |
| Python | `~/keyoti/pys/*.py` | Settings 中配置的 Conda Python |
| AppleScript | `~/keyoti/applescripts/*.applescript` | `/usr/bin/osascript /absolute/path/script.applescript` |
| Jobs | `~/keyoti/launchds/com.notchwow.<task>.plist` | Jobs 工作区加载和卸载 |

Shell 的 `workspaces/`、`workspace-inputs/`，以及 transcript 和日志文件属于运行产物。agent 不应把业务脚本写入这些目录。

## 3. 脚本之间互调

Shell 脚本使用动态根目录，避免写死用户名：

```bash
KEYOTI_HOME="${KEYOTI_HOME:-$HOME/keyoti}"
CONDA_ROOT="${CONDA_ROOT:-$HOME/miniforge3}"
/bin/zsh "$KEYOTI_HOME/shs/workspace-scripts/prepare.sh"
"$CONDA_ROOT/bin/python" "$KEYOTI_HOME/pys/report.py"
/usr/bin/osascript "$KEYOTI_HOME/applescripts/notify.applescript"
```

如果 Python 路径已在 Settings 中覆盖，plist 应使用配置后的绝对路径。生成前先查看 Settings 或 Jobs AI 上下文，不要假设固定安装位置。

## 4. Jobs 编排

每个 plist 使用唯一的 `com.notchwow.` Label，并在 `ProgramArguments` 中使用绝对路径。stdout 与 stderr 建议写入 `~/keyoti/launchds/` 下对应的 `.stdout.log` 和 `.stderr.log` 文件。

Jobs 工作区会自动清理缺少本地 plist 的已加载 `com.notchwow.*` 服务。移动或重命名 plist 前先卸载任务。agent 不应未经确认直接执行 `launchctl bootstrap`、`bootout` 或删除操作。

## 5. 质量检查

生成或修改文件后至少执行对应检查：

```bash
bash -n ~/keyoti/shs/workspace-scripts/task.sh
python -m py_compile ~/keyoti/pys/task.py
osacompile -o /tmp/notchwow-check.scpt ~/keyoti/applescripts/task.applescript
plutil -lint ~/keyoti/launchds/com.notchwow.task.plist
```

脚本应可重复执行、正确引用带空格路径、把错误写入 stderr，并避免把 API Key、密码或 token 写入源码和 plist。
