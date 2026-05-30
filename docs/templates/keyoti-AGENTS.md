# notchwow Automation Workspace

This directory contains user automation managed with notchwow.

Before editing scripts or plist files, read `~/Desktop/notchwow/docs/AUTOMATION_AGENT_GUIDE.md` when that repository is available.

## Directory Contract

- Put Shell scripts in `shs/workspace-scripts/*.sh`.
- Put Python scripts in `pys/*.py`.
- Put AppleScript files in `applescripts/*.applescript`.
- Put launchd plist files in `launchds/com.notchwow.<task>.plist`.
- Treat `shs/workspaces/`, `shs/workspace-inputs/`, transcript files, and log files as runtime output unless the task explicitly concerns them.

## Script Rules

- Resolve the workspace with `KEYOTI_HOME="${KEYOTI_HOME:-$HOME/keyoti}"`; do not hardcode `/Users/ben`.
- Use absolute paths in launchd `ProgramArguments`.
- Use `/bin/zsh` for Shell scripts, the configured Conda Python for Python scripts, and `/usr/bin/osascript` for AppleScript files.
- Keep scripts idempotent, quote paths, emit useful errors to stderr, and avoid embedding secrets.
- Use `com.notchwow.` for launchd labels.
- Do not load, unload, or delete launchd jobs without explicit approval.

## Validation

- Shell: `bash -n path/to/script.sh`
- Python: `python -m py_compile path/to/script.py`
- AppleScript: `osacompile -o /tmp/notchwow-check.scpt path/to/script.applescript`
- launchd: `plutil -lint path/to/com.notchwow.task.plist`
