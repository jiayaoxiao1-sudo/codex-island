#!/usr/bin/env python3
"""Install only this app, local marketplace and user-level launch agent."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import time
import argparse

ROOT = Path(__file__).resolve().parent
DATA = Path.home() / "Library/Application Support/Codex Island"
LABEL = "local.codex.island.watcher"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prebuilt", action="store_true", help="Install the packaged application without compiling")
    args = parser.parse_args()
    if not args.prebuilt:
        subprocess.run(["/bin/zsh", str(ROOT / "build.sh")], check=True)
    else:
        with (ROOT / "build/Codex Island.app/Contents/Info.plist").open("rb") as handle:
            if plistlib.load(handle).get("CFBundleIdentifier") != "local.codex.island":
                raise RuntimeError("Unexpected packaged application")
    DATA.mkdir(parents=True, exist_ok=True)
    app = DATA / "Codex Island.app"
    old_agent = Path.home() / "Library/LaunchAgents" / (LABEL + ".plist")
    if old_agent.exists():
        with old_agent.open("rb") as handle:
            if plistlib.load(handle).get("Label") != LABEL:
                raise RuntimeError("Launch agent target belongs to another service")
        subprocess.run(["/bin/launchctl", "bootout", "gui/" + str(os.getuid()), str(old_agent)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # Gracefully stop only previous instances of this exact app before upgrading.
    processes = subprocess.run(["/usr/bin/pgrep", "-fl", "CodexIsland"], capture_output=True, text=True)
    owned = {str(app / "Contents/MacOS/CodexIsland"), str(ROOT / "build/Codex Island.app/Contents/MacOS/CodexIsland")}
    for line in processes.stdout.splitlines():
        pid_text, _, executable = line.partition(" ")
        pid = int(pid_text)
        if executable in owned or any(executable == path + " --watch" for path in owned):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    time.sleep(0.3)
    # Replace only files owned by Codex Island, never another app.
    if app.exists():
        with (app / "Contents/Info.plist").open("rb") as handle:
            if plistlib.load(handle).get("CFBundleIdentifier") != "local.codex.island":
                raise RuntimeError("Target is not a Codex Island app")
        shutil.rmtree(app)
    shutil.copytree(ROOT / "build/Codex Island.app", app)
    marketplace = DATA / "marketplace"
    shutil.copytree(ROOT / "distribution/.agents", marketplace / ".agents", dirs_exist_ok=True)
    shutil.copytree(ROOT / "plugins", marketplace / "plugins", dirs_exist_ok=True)
    cli = shutil.which("codex")
    if not cli:
        fallback = Path("/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        cli = str(fallback) if fallback.exists() else None
    if not cli:
        raise RuntimeError("Codex CLI was not found")
    subprocess.run([cli, "plugin", "marketplace", "add", str(marketplace), "--json"], check=True)
    subprocess.run([cli, "plugin", "add", "codex-island@codex-island-local", "--json"], check=True)
    agent_dir = Path.home() / "Library/LaunchAgents"
    agent_dir.mkdir(parents=True, exist_ok=True)
    target = agent_dir / (LABEL + ".plist")
    agent = {"Label": LABEL, "ProgramArguments": [str(app / "Contents/MacOS/CodexIsland"), "--watch"],
             "RunAtLoad": True, "KeepAlive": {"SuccessfulExit": False}, "ThrottleInterval": 10,
             "LimitLoadToSessionType": "Aqua", "ProcessType": "Interactive",
             "StandardOutPath": str(DATA / "watcher.log"), "StandardErrorPath": str(DATA / "watcher-error.log")}
    if target.exists():
        with target.open("rb") as handle:
            if plistlib.load(handle).get("Label") != LABEL:
                raise RuntimeError("Launch agent target belongs to another service")
    with target.open("wb") as handle:
        plistlib.dump(agent, handle)
    domain = "gui/" + str(os.getuid())
    subprocess.run(["/bin/launchctl", "bootout", domain, str(target)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result = subprocess.run(["/bin/launchctl", "bootstrap", domain, str(target)], capture_output=True, text=True)
    print(json.dumps({"app": str(app), "plugin": "codex-island@codex-island-local", "launchAgent": str(target),
                      "watcherStarted": result.returncode == 0, "hooksNeedTrustReview": True}, ensure_ascii=False))
    if result.returncode:
        print("自动启动已配置；当前会话无法加载登录服务，下次登录后生效。", file=sys.stderr)

if __name__ == "__main__":
    main()
