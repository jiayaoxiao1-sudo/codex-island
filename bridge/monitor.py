#!/usr/bin/env python3
"""Read-only local Codex telemetry. Never exports reasoning or tool arguments."""
import argparse
import fcntl
import datetime as dt
import json
import os
import re
from pathlib import Path
import sqlite3
import sys
import time

ACTIVE = {"running", "waiting"}

def epoch(value):
    if isinstance(value, (int, float)):
        return value / 1000 if value > 100_000_000_000 else value
    try:
        return dt.datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except (ValueError, TypeError):
        return 0

def read_tail(path, limit=512 * 1024):
    try:
        with Path(path).open("rb") as handle:
            handle.seek(max(0, os.fstat(handle.fileno()).st_size - limit))
            data = handle.read(limit)
        for line in data.splitlines():
            try:
                value = json.loads(line)
                if isinstance(value, dict):
                    yield value
            except (ValueError, UnicodeDecodeError):
                continue
    except OSError:
        return

def phase_for(name):
    name = str(name).lower()
    if any(x in name for x in ("patch", "edit", "write", "filechange")):
        return "writing"
    if any(x in name for x in ("test", "review", "verify", "check")):
        return "testing"
    if any(x in name for x in ("search", "read", "browse", "web", "find")):
        return "reading"
    return "working"

def normalize_limits(raw, timestamp, source):
    if not isinstance(raw, dict):
        return None
    if raw.get("limitId", raw.get("limit_id", "codex")) not in (None, "codex"):
        return None
    windows = []
    for key in ("primary", "secondary"):
        window = raw.get(key)
        if not isinstance(window, dict):
            continue
        used = window.get("usedPercent", window.get("used_percent"))
        if not isinstance(used, (float, int)):
            continue
        windows.append({"usedPercent": max(0, min(100, used)),
                        "minutes": window.get("windowDurationMins", window.get("window_minutes", 0)),
                        "resetsAt": window.get("resetsAt", window.get("resets_at"))})
    if not windows:
        return None
    return {"windows": windows, "updatedAt": timestamp, "source": source}

def reduce_rollout(events, row, now):
    task = {"id": row["id"], "title": row.get("name") or row.get("title") or "未命名任务",
            "status": "unknown", "phase": "idle", "activity": "暂无操作记录",
            "tokens": row.get("tokens_used") or 0, "updatedAt": epoch(row.get("updated_at")),
            "source": "本机任务记录", "model": row.get("model") or "Codex"}
    quota = None
    for event in events:
        payload = event.get("payload") or {}
        if not isinstance(payload, dict):
            continue
        stamp = epoch(event.get("timestamp"))
        kind = payload.get("type")
        if event.get("type") == "event_msg":
            if kind in ("task_started", "turn_started"):
                task.update(status="running", phase="working", activity="正在处理任务", updatedAt=stamp)
            elif kind in ("task_complete", "task_completed", "turn_complete", "turn_completed"):
                task.update(status="completed", phase="done", activity="任务已完成", updatedAt=stamp)
                if payload.get("last_agent_message"):
                    task["completedText"] = str(payload["last_agent_message"])[:12000]
            elif kind in ("turn_aborted", "task_aborted"):
                task.update(status="interrupted", phase="idle", activity="任务已中断", updatedAt=stamp)
            elif kind == "token_count":
                info = payload.get("info") or {}
                total = info.get("total_token_usage") or {}
                if isinstance(total.get("total_tokens"), int):
                    task["tokens"] = total["total_tokens"]
                    task["inputTokens"] = total.get("input_tokens", 0)
                    task["outputTokens"] = total.get("output_tokens", 0)
                    task["cachedTokens"] = total.get("cached_input_tokens", 0)
                    task["tokensUpdatedAt"] = stamp
                    task["updatedAt"] = max(task["updatedAt"], stamp)
                candidate = normalize_limits(payload.get("rate_limits"), stamp, "Codex 用量事件")
                if candidate and (quota is None or candidate["updatedAt"] > quota["updatedAt"]):
                    quota = candidate
            elif kind == "agent_message":
                # Public progress messages only. Never collect agent_reasoning.
                if payload.get("phase") == "commentary":
                    task["activity"] = str(payload.get("message", ""))[:160]
                    task["updatedAt"] = stamp
                elif payload.get("phase") == "final_answer":
                    task["completedText"] = str(payload.get("message") or "")[:12000]
        elif event.get("type") == "response_item" and kind == "function_call":
            # Inspect only tool name; do not export command arguments or raw thoughts.
            name = str(payload.get("name", "tool"))
            task.update(phase=phase_for(name), activity="调用工具 · " + name.split("__")[-1], updatedAt=stamp)
    return task, quota

def readonly(path):
    return sqlite3.connect(Path(path).resolve().as_uri() + "?mode=ro", uri=True, timeout=0.2)

def task_identity(row, titles, parents):
    """Keep saved chat titles; identify untitled child agents from actual metadata."""
    source = row.get("source", "")
    spawn = {}
    if isinstance(source, str) and source.startswith("{"):
        try:
            spawn = json.loads(source).get("subagent", {}).get("thread_spawn", {})
        except (ValueError, AttributeError):
            pass
    parent = parents.get(row["id"]) or spawn.get("parent_thread_id")
    child = bool(parent or row.get("thread_source") == "subagent" or spawn)
    saved = row.get("name") or row.get("title")
    parent_title = titles.get(parent, "")
    nickname = row.get("agent_nickname") or spawn.get("agent_nickname")
    path = row.get("agent_path") or spawn.get("agent_path") or ""
    role = path.rsplit("/", 1)[-1] or row.get("agent_role") or nickname or "协作代理"
    if saved:
        title = saved
    elif child:
        title = (parent_title + " · " if parent_title else "") + "子任务 / " + role
    else:
        preview = str(row.get("preview") or "").strip()
        title = preview.splitlines()[0][:80] if preview else "新任务（等待标题）"
    return {"title": title, "isSubtask": child, "parentId": parent,
            "parentTitle": parent_title, "agentName": nickname}

def internal_thread(row):
    if row.get('thread_source') in {'guardian_review', 'compaction', 'subagent_review'}:
        return True
    try:
        source = json.loads(row.get('source') or '{}')
        return source.get('subagent', {}).get('other') == 'guardian'
    except (ValueError, AttributeError, TypeError):
        return False


def root_thread(tid, parents):
    seen = set()
    while parents.get(tid) and tid not in seen:
        seen.add(tid)
        tid = parents[tid]
    return tid


def group_chats(active, unread):
    groups = {}
    for task in active:
        root = task.get('rootId') or task['id']
        existing = groups.get(root)
        if not existing or task['id'] == root:
            groups[root] = dict(task, id=root, title=task.get('rootTitle') or task['title'], listId='chat:' + root, isSubtask=False)
    for root, group in groups.items():
        members = [t for t in active if (t.get('rootId') or t['id']) == root]
        group['status'] = 'running' if any(t['status'] == 'running' for t in members) else 'waiting'
        group['activatedAt'] = max(t.get('activatedAt', 0) for t in members)
        group['collaborators'] = sum(t['id'] != root for t in members)
    for task in unread:
        root = task.get('rootId') or task['id']
        if root not in groups:
            groups[root] = dict(task, id=root, title=task.get('rootTitle') or task['title'], listId='chat:' + root, isSubtask=False)
        group = groups[root]
        group.setdefault('completionKeys', []).append(task['completionKey'])
        group['unreadCount'] = len(group['completionKeys'])
        if group.get('status') not in ACTIVE:
            group['unread'] = True
            group['phase'] = 'done'
            group['completedText'] = task.get('completedText', '')
    return list(groups.values())

class CompletionInbox:
    def __init__(self, directory):
        self.directory = Path(directory)

    def sync(self, arrivals, excluded_ids=()):
        ledger = self.directory / 'pending-completions.json'
        if not arrivals and not ledger.exists() and not (self.directory / 'read-receipts').exists():
            return []
        self.directory.mkdir(parents=True, exist_ok=True)
        with (self.directory / 'completion-inbox.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            try:
                state = json.loads(ledger.read_text())
            except (OSError, ValueError):
                state = {'pending': {}, 'read': []}
            pending = state['pending']
            removed = [key for key, task in pending.items() if task['id'] in excluded_ids]
            for key in removed:
                pending.pop(key)
            read = set(state['read'])
            receipts = []
            for path in (self.directory / 'read-receipts').glob('*.json'):
                try:
                    key = json.loads(path.read_text())['completionKey']
                    read.add(key)
                    pending.pop(key, None)
                    receipts.append(path)
                except (OSError, ValueError, KeyError, TypeError):
                    continue
            for task in arrivals:
                key = task['completionKey']
                if key not in read:
                    pending[key] = dict(task, unread=True, listId='completed:' + key)
            if arrivals or receipts or removed:
                temporary = ledger.with_suffix('.' + str(os.getpid()) + '.tmp')
                temporary.write_text(json.dumps({'pending': pending, 'read': sorted(read)}, ensure_ascii=False))
                os.chmod(temporary, 0o600)
                temporary.replace(ledger)
                for path in receipts:
                    try:
                        path.unlink()
                    except OSError:
                        pass
            return sorted(pending.values(), key=lambda task: -task.get('updatedAt', 0))

class Monitor:
    def __init__(self, home=None, data=None):
        self.home = Path(home or os.environ.get("CODEX_HOME", Path.home() / ".codex"))
        self.data = Path(data or os.environ.get("CODEX_ISLAND_DATA", Path.home() / "Library/Application Support/Codex Island"))
        self.cache = {}
        self.quota = None
        self.muted_rounds = set()
        self.previous_turns = None
        self.announced_completions = set()
        self.inbox = CompletionInbox(self.data)

    def snapshot(self):
        now = time.time()
        tasks = []
        errors = []
        internal_ids = set()
        parents = {}
        titles = {}
        try:
            database = self.home / "state_5.sqlite"
            with readonly(database) as con:
                con.row_factory = sqlite3.Row
                columns = {x[1] for x in con.execute("pragma table_info(threads)")}
                required = {"id", "title", "rollout_path", "tokens_used", "updated_at", "archived"}
                if not required.issubset(columns):
                    raise ValueError("unsupported schema")
                fields = sorted(required | ({"name", "model", "preview", "source", "thread_source", "agent_nickname", "agent_role", "agent_path"} & columns))
                rows = [dict(r) for r in con.execute("select " + ",".join(fields) + " from threads where archived=0 order by updated_at desc limit 100")]
                title_fields = "id,title" + (",name" if "name" in columns else "")
                titles = {r["id"]: (dict(r).get("name") or r["title"] or "") for r in con.execute("select " + title_fields + " from threads")}
                parents = {}
                if con.execute("select 1 from sqlite_master where type='table' and name='thread_spawn_edges'").fetchone():
                    parents = {r["child_thread_id"]: r["parent_thread_id"] for r in con.execute("select child_thread_id,parent_thread_id from thread_spawn_edges")}
                metadata = [dict(r) for r in con.execute('select ' + ','.join(fields) + ' from threads')]
                internal_ids = {r['id'] for r in metadata if internal_thread(r)}
                rows = sorted((r for r in metadata if not r['archived'] and r['id'] not in internal_ids), key=lambda r: r['updated_at'], reverse=True)[:100]
                for r in metadata:
                    identity = task_identity(r, titles, parents)
                    if identity.get('parentId'):
                        parents.setdefault(r['id'], identity['parentId'])

            history = {}
            visible = {}
            history_path = self.home / "thread_history_1.sqlite"
            if history_path.exists():
                with readonly(history_path) as con:
                    con.row_factory = sqlite3.Row
                    for row in con.execute("select thread_id, turn_id, status, started_at, completed_at from thread_turns where rollout_ordinal=(select max(t.rollout_ordinal) from thread_turns t where t.thread_id=thread_turns.thread_id)"):
                        history[row["thread_id"]] = dict(row)
                    has_items = bool(con.execute("select 1 from sqlite_master where type='table' and name='thread_items'").fetchone())
                    for tid, turn in (history.items() if has_items else []):
                        if tid in internal_ids:
                            continue
                        for kind, raw in con.execute("select item_type,item_json from thread_items where thread_id=? and turn_id=? and item_type in ('agentMessage','reasoning') order by rollout_ordinal desc limit 20", (tid, turn['turn_id'])):
                            item = json.loads(raw)
                            info = visible.setdefault(tid, {})
                            if kind == 'agentMessage' and item.get('phase') == 'final_answer' and 'completedText' not in info:
                                info['completedText'] = str(item.get('text') or '')[:12000]
                            if kind == 'agentMessage' and item.get('phase') == 'commentary' and 'progressText' not in info:
                                info['progressText'] = str(item.get('text') or '')[:500]
                            elif kind == 'reasoning' and 'statusHeading' not in info:
                                for summary in item.get('summary') or []:
                                    text = summary if isinstance(summary, str) else summary.get('text', '')
                                    match = re.match(r'\s*\*\*([^\n*]{1,160})\*\*', text)
                                    if match:
                                        info['statusHeading'] = match.group(1)
                                        break

            for row in rows:
                path = Path(row["rollout_path"])
                try:
                    stat = path.stat()
                    key = (stat.st_mtime_ns, stat.st_size, row["tokens_used"], row["updated_at"])
                except OSError:
                    key = None
                cached = self.cache.get(row["id"])
                if key is not None and cached and cached[0] == key:
                    task, quota = dict(cached[1]), cached[2]
                else:
                    task, quota = reduce_rollout(read_tail(path), row, now)
                    self.cache[row["id"]] = (key, dict(task), quota)
                # Resolve each poll so title edits and parent renames invalidate no file cache.
                task.update(task_identity(row, titles, parents))
                task.update(visible.get(row["id"], {}))
                if quota and (not self.quota or quota["updatedAt"] > self.quota["updatedAt"]):
                    self.quota = quota
                turn = history.get(row["id"])
                if turn:
                    status = turn["status"]
                    task["status"] = {"inProgress": "running", "completed": "completed", "failed": "failed", "interrupted": "interrupted"}.get(status, "unknown")
                    if task["status"] == "completed":
                        task.update(phase="done", activity="任务已完成")
                    elif task["status"] == "failed":
                        task.update(phase="error", activity="任务失败")
                    elif task["status"] == "interrupted":
                        task.update(phase="idle", activity="任务已中断")
                    task["turnId"] = turn["turn_id"]
                    task["activatedAt"] = epoch(turn.get("started_at"))
                    task["updatedAt"] = max(task["updatedAt"], epoch(turn.get("completed_at")), epoch(turn.get("started_at")))
                if task["status"] in ACTIVE and now - task["updatedAt"] > 900:
                    task.update(status="unknown", activity="长时间未收到更新，运行状态待确认", phase="idle")
                tasks.append(task)
            keep = {r["id"] for r in rows}
            self.cache = {key: value for key, value in self.cache.items() if key in keep}
        except (OSError, sqlite3.Error, ValueError):
            errors.append("本机任务记录暂不可读，等待插件事件")
        # Hook files are individual atomic snapshots, so simultaneous sessions never clobber each other.
        by_id = {t["id"]: t for t in tasks}
        for path in (self.data / "sessions").glob("*.json"):
            try:
                hook = json.loads(path.read_text())
                old = by_id.get(hook["id"])
                if now - hook["updatedAt"] > 900 and hook.get("status") in ACTIVE:
                    continue
                # A later terminal rollout/turn state wins over an earlier hook.
                if old and old.get("status") in {"completed", "failed", "interrupted"} and old.get("updatedAt", 0) >= hook["updatedAt"]:
                    continue
                merged = dict(old or {})
                merged.update(hook)
                if old:
                    merged["tokens"] = old["tokens"]
                    if old.get("title") and hook.get("title") == "Codex 任务":
                        merged["title"] = old["title"]
                by_id[hook["id"]] = merged
            except (OSError, ValueError, KeyError, TypeError):
                continue
        tasks = sorted((t for t in by_id.values() if t["id"] not in internal_ids), key=lambda t: (t.get("status") not in ACTIVE, -t.get("updatedAt", 0)))
        for task in tasks:
            task['rootId'] = root_thread(task['id'], parents)
            task['rootTitle'] = titles.get(task['rootId']) or task['title']
        signals = []
        for path in sorted((self.data / 'notifications').glob('*.json')):
            try:
                event = json.loads(path.read_text())
                if event.get('soundKind') not in ('step', 'final') or not event.get('eventId'):
                    continue
                signals.append(event)
                if event.get('muteRoundKey'):
                    self.muted_rounds.add(event['muteRoundKey'])
                path.unlink()
            except (OSError, ValueError, KeyError):
                continue
        running = [t for t in tasks if t.get("status") in ACTIVE]
        current = {t['id']: (t.get('turnId'), t.get('status')) for t in tasks}
        completions = []
        if self.previous_turns is not None:
            for task in tasks:
                old = self.previous_turns.get(task['id'])
                completion_key = (task['id'], task.get('turnId') or task.get('updatedAt'))
                if task.get('status') == 'completed' and old and old != current[task['id']] and completion_key not in self.announced_completions:
                    self.announced_completions.add(completion_key)
                    key = task['id'] + ':' + str(task.get('turnId') or task.get('updatedAt'))
                    completions.append(dict(task, completionKey=key, soundKind='step', quiet=key in self.muted_rounds))
        if self.previous_turns is None:
            self.announced_completions.update((t['id'], t.get('turnId') or t.get('updatedAt')) for t in tasks if t.get('status') == 'completed')
        self.previous_turns = current
        unread = self.inbox.sync(completions + [e for e in signals if not e.get('isDemo')], internal_ids)
        for task in unread:
            task['rootId'] = root_thread(task.get('rootId') or task['id'], parents)
            task['rootTitle'] = titles.get(task['rootId']) or task.get('rootTitle') or task['title']
        displayed = group_chats(running, unread)
        for event in completions:
            event['title'] = event.get('rootTitle') or event['title']
            event['navigateId'] = event.get('rootId') or event['id']
        for task in tasks:
            task["stale"] = now - task.get("updatedAt", 0) > 120
        return {"version": 2, "updatedAt": now, "quota": self.quota, "runningCount": sum(t.get("status") in ACTIVE for t in displayed),
                "tasks": displayed, "unreadCount": len(unread), "completions": completions + signals, "recentTasks": tasks[:12], "errors": errors,
                "connected": bool(displayed) or bool(tasks) or not errors}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--home")
    parser.add_argument("--data")
    args = parser.parse_args()
    monitor = Monitor(args.home, args.data)
    while True:
        try:
            print(json.dumps(monitor.snapshot(), ensure_ascii=False), flush=True)
        except BrokenPipeError:
            return
        if args.once:
            return
        time.sleep(2)

if __name__ == "__main__":
    main()
