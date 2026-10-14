#!/usr/bin/env python3
"""Small CLI for agents operating the local companion; no credentials or network."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
import shutil
import platform
import sys
from urllib.parse import quote

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["status", "show", "restart", "open"])
    parser.add_argument("thread_id", nargs="?")
    args = parser.parse_args()
    data = Path.home() / "Library/Application Support/Codex Island"
    app = data / "Codex Island.app"
    label = "gui/" + str(os.getuid()) + "/local.codex.island.watcher"
    if args.command == "status":
        try:
            health = json.loads((data / "health.json").read_text())
        except (OSError, ValueError):
            health = {}
        pid = health.get("pid")
        live = False
        if isinstance(pid, int):
            try:
                os.kill(pid, 0)
                live = True
            except PermissionError:
                live = None
            except OSError:
                pass
        print(json.dumps({"installed": app.exists(), "processAlive": live,
                          "processCheckRestricted": live is None,
                          "hostArchitecture": platform.machine(), "pythonVersion": sys.version.split()[0],
                          "codexAvailable": bool(shutil.which("codex")) or Path("/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex").exists(),
                          "reportAgeSeconds": max(0, time.time() - health["lastSnapshotAt"]) if health.get("lastSnapshotAt") else None,
                          "health": health}, ensure_ascii=False))
    elif args.command == "show":
        subprocess.run(["/usr/bin/open", str(app)], check=True)
    elif args.command == "restart":
        subprocess.run(["/bin/launchctl", "kickstart", "-k", label], check=True)
    else:
        if not args.thread_id:
            parser.error("open requires the user's root chat ID")
        subprocess.run(["/usr/bin/open", "codex://threads/" + quote(args.thread_id, safe="")], check=True)

if __name__ == "__main__":
    main()
