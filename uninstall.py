#!/usr/bin/env python3
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

LABEL = "local.codex.island.watcher"
target = Path.home() / "Library/LaunchAgents" / (LABEL + ".plist")
if target.exists():
    with target.open("rb") as handle:
        if plistlib.load(handle).get("Label") != LABEL:
            raise RuntimeError("Unknown launch agent")
    subprocess.run(["/bin/launchctl", "bootout", "gui/" + str(os.getuid()), str(target)], check=False)
    target.unlink()
cli = shutil.which("codex")
if not cli:
    fallback = Path("/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
    cli = str(fallback) if fallback.exists() else None
plugin_removed = False
if cli:
    plugin_removed = subprocess.run([cli, "plugin", "remove", "codex-island@codex-island-local"], check=False).returncode == 0
print("已移除自动启动；" + ("插件已移除。" if plugin_removed else "插件移除未确认，请在 Codex 中检查。") + "应用及本地记录保留在 ~/Library/Application Support/Codex Island。")
