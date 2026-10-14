#!/usr/bin/env python3
"""Fail-open hook: publish lifecycle metadata, never prompts, arguments or reasoning."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

def main():
    data = json.load(sys.stdin)
    event = data.get("hook_event_name", "")
    sid = data.get("session_id")
    if not sid:
        return
    root = Path(os.environ.get("CODEX_ISLAND_DATA", Path.home() / "Library/Application Support/Codex Island"))
    directory = root / "sessions"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    target = directory / (hashlib.sha256(sid.encode()).hexdigest() + ".json")
    previous = {}
    try:
        previous = json.loads(target.read_text())
    except (OSError, ValueError):
        pass
    phase = "working"
    status = "running"
    activity = "正在处理任务"
    if event == "SessionStart":
        status, phase, activity = "idle", "idle", "会话已连接"
    elif event in ("Stop", "SessionEnd"):
        status, phase, activity = "completed", "done", "本轮任务已结束"
    elif event == "Interrupt":
        status, phase, activity = "interrupted", "idle", "任务已中断"
    elif event == "PermissionRequest":
        status, phase, activity = "waiting", "waiting", "等待你的确认"
    elif event in ("PreToolUse", "PostToolUse"):
        name = str(data.get("tool_name", "tool"))
        activity = ("正在调用 · " if event == "PreToolUse" else "工具完成 · ") + name.split("__")[-1]
        lower = name.lower()
        if any(x in lower for x in ("patch", "edit", "write")): phase = "writing"
        elif any(x in lower for x in ("test", "verify", "check", "review")): phase = "testing"
        elif any(x in lower for x in ("search", "read", "browse", "web")): phase = "reading"
    snapshot = {"id": sid, "title": previous.get("title", "Codex 任务"), "status": status,
                "phase": phase, "activity": activity, "updatedAt": time.time(),
                "source": "插件生命周期事件", "model": data.get("model", "Codex"),
                "turnId": data.get("turn_id")}
    temporary = target.with_suffix("." + str(os.getpid()) + ".tmp")
    temporary.write_text(json.dumps(snapshot, ensure_ascii=False))
    os.chmod(temporary, 0o600)
    temporary.replace(target)
    if event == "SessionStart" and not os.environ.get("CODEX_ISLAND_TEST"):
        app = root / "Codex Island.app"
        if app.is_dir():
            subprocess.run(["/usr/bin/open", "-g", str(app)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)

if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
