import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("monitor", ROOT / "bridge/monitor.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class TelemetryTests(unittest.TestCase):
    def test_guardian_is_filtered_by_source_not_user_title(self):
        self.assertTrue(module.internal_thread({"thread_source": "guardian_review", "title": "Guardian review"}))
        self.assertTrue(module.internal_thread({"source": json.dumps({"subagent": {"other": "guardian"}})}))
        self.assertFalse(module.internal_thread({"thread_source": "user", "title": "Guardian review"}))
        with tempfile.TemporaryDirectory() as directory:
            inbox = module.CompletionInbox(directory)
            guard = {"id": "guardian", "completionKey": "guardian:t", "title": "Guardian review", "updatedAt": 2}
            user = {"id": "user", "completionKey": "user:t", "title": "Guardian review", "updatedAt": 1}
            inbox.sync([guard, user])
            self.assertEqual([t["id"] for t in inbox.sync([], {"guardian"})], ["user"])

    def test_root_chat_grouping_and_unread_completion_do_not_duplicate_running(self):
        parent = {"id": "parent", "rootId": "parent", "rootTitle": "我的对话", "title": "我的对话", "status": "running"}
        child = {"id": "child", "rootId": "parent", "rootTitle": "我的对话", "title": "内部子任务", "status": "running"}
        unread = dict(child, status="completed", completionKey="child:turn", unread=True, completedText="检查已通过。")
        grouped = module.group_chats([parent, child], [unread])
        self.assertEqual(len(grouped), 1)
        self.assertEqual(grouped[0]["id"], "parent")
        self.assertEqual(grouped[0]["status"], "running")
        self.assertEqual(grouped[0]["unreadCount"], 1)
        self.assertEqual(grouped[0]["completionKeys"], ["child:turn"])
        self.assertEqual(module.root_thread("child", {"child": "middle", "middle": "parent"}), "parent")

    def test_unread_completion_survives_restart_and_requires_exact_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            a = {"id": "same-chat", "turnId": "turn-a", "completionKey": "same-chat:turn-a", "title": "任务", "status": "completed", "updatedAt": 1}
            b = dict(a, turnId="turn-b", completionKey="same-chat:turn-b", updatedAt=2)
            inbox = module.CompletionInbox(directory)
            self.assertEqual(len(inbox.sync([a, b])), 2)
            restored = module.CompletionInbox(directory)
            self.assertEqual(len(restored.sync([])), 2)
            receipts = Path(directory) / "read-receipts"
            receipts.mkdir()
            (receipts / "viewed.json").write_text(json.dumps({"completionKey": a["completionKey"]}))
            remaining = restored.sync([])
            self.assertEqual([t["turnId"] for t in remaining], ["turn-b"])
            self.assertTrue(remaining[0]["unread"])
            self.assertEqual(len(restored.sync([a])), 1)
            self.assertEqual(len(module.CompletionInbox(directory).sync([])), 1)

    def test_untitled_subtask_uses_parent_and_role(self):
        row = {"id": "child", "title": "", "thread_source": "subagent", "agent_nickname": "Newton", "agent_path": "/root/verify_backend_commit"}
        identity = module.task_identity(row, {"parent": "主任务标题"}, {"child": "parent"})
        self.assertEqual(identity["title"], "主任务标题 · 子任务 / verify_backend_commit")
        self.assertTrue(identity["isSubtask"])
        self.assertEqual(identity["agentName"], "Newton")

    def test_source_metadata_fallback_and_saved_title(self):
        row = {"id": "child", "source": json.dumps({"subagent": {"thread_spawn": {"parent_thread_id": "parent", "agent_path": "/root/review"}}})}
        identity = module.task_identity(row, {"parent": "主任务"}, {})
        self.assertEqual(identity["title"], "主任务 · 子任务 / review")
        row["name"] = "真实标题"
        self.assertEqual(module.task_identity(row, {}, {})["title"], "真实标题")
        self.assertEqual(module.task_identity({"id": "new"}, {}, {})["title"], "新任务（等待标题）")

    def event(self, kind, **payload):
        return {"type": "event_msg", "timestamp": "2026-10-13T03:00:00Z", "payload": {"type": kind, **payload}}

    def test_terminal_state_and_token_accounting(self):
        events = [self.event("task_started"), self.event("token_count", info={"total_token_usage": {"total_tokens": 150, "input_tokens": 120, "output_tokens": 30, "cached_input_tokens": 100}}), self.event("task_complete")]
        task, quota = module.reduce_rollout(events, {"id": "a", "title": "test"}, time.time())
        self.assertEqual((task["status"], task["phase"], task["tokens"], task["cachedTokens"]), ("completed", "done", 150, 100))
        self.assertIsNone(quota)

    def test_never_exports_raw_reasoning_or_arguments(self):
        events = [{"type": "response_item", "payload": {"type": "reasoning", "content": "PRIVATE_CHAIN"}}, self.event("agent_reasoning", text="PRIVATE_CHAIN"), {"type": "response_item", "payload": {"type": "function_call", "name": "apply_patch", "arguments": "SECRET_COMMAND"}}]
        task, _ = module.reduce_rollout(events, {"id": "a"}, time.time())
        output = json.dumps(task)
        self.assertNotIn("PRIVATE_CHAIN", output)
        self.assertNotIn("SECRET_COMMAND", output)
        self.assertEqual(task["phase"], "writing")

    def test_zero_percent_is_known_and_other_bucket_is_ignored(self):
        zero = module.normalize_limits({"primary": {"used_percent": 0, "window_minutes": 300}}, 1, "test")
        self.assertEqual(zero["windows"][0]["usedPercent"], 0)
        self.assertIsNone(module.normalize_limits({"limit_id": "other", "primary": {"used_percent": 42}}, 1, "test"))

    def test_missing_database_is_disconnected(self):
        with tempfile.TemporaryDirectory() as directory:
            snapshot = module.Monitor(directory, directory).snapshot()
            self.assertFalse(snapshot["connected"])
            self.assertIsNone(snapshot["quota"])
            self.assertEqual(snapshot["runningCount"], 0)

    def test_concurrent_hooks_and_stop(self):
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ, CODEX_ISLAND_DATA=directory, CODEX_ISLAND_TEST="1")
            def hook(sid, event):
                return subprocess.Popen(["/usr/bin/python3", str(ROOT / "plugins/codex-island/hooks/event.py")], stdin=subprocess.PIPE, env=env, text=True)
            processes = []
            for sid in ("a", "b"):
                process = hook(sid, "UserPromptSubmit")
                process.stdin.write(json.dumps({"session_id": sid, "hook_event_name": "UserPromptSubmit", "prompt": "SECRET_PROMPT"}))
                process.stdin.close()
                processes.append(process)
            for process in processes:
                self.assertEqual(process.wait(timeout=3), 0)
            monitor = module.Monitor(directory, directory)
            snapshot = monitor.snapshot()
            self.assertEqual(snapshot["runningCount"], 2)
            self.assertEqual(snapshot["completions"], [])
            self.assertNotIn("SECRET_PROMPT", json.dumps(snapshot))
            process = hook("a", "Stop")
            process.communicate(json.dumps({"session_id": "a", "hook_event_name": "Stop"}), timeout=3)
            snapshot = monitor.snapshot()
            self.assertEqual(len(snapshot["completions"]), 1)
            self.assertEqual(monitor.snapshot()["completions"], [])
            self.assertEqual(module.Monitor(directory, directory).snapshot()["completions"], [])
            self.assertEqual(snapshot["runningCount"], 1)
            self.assertEqual(snapshot["tasks"][0]["id"], "b")

    def test_history_completion_wins_and_stale_turn_is_not_running(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rollout = root / "task.jsonl"
            old = time.time() - 2000
            stamp = module.dt.datetime.fromtimestamp(old, module.dt.timezone.utc).isoformat()
            rollout.write_text(json.dumps({"type": "event_msg", "timestamp": stamp, "payload": {"type": "task_started"}}) + "\n")
            with sqlite3.connect(root / "state_5.sqlite") as con:
                con.execute("create table threads(id text,title text,rollout_path text,tokens_used integer,updated_at integer,archived integer)")
                con.execute("insert into threads values('a','task',?,0,?,0)", (str(rollout), int(old)))
            monitor = module.Monitor(root, root)
            self.assertEqual(monitor.snapshot()["runningCount"], 0)
            with sqlite3.connect(root / "thread_history_1.sqlite") as con:
                con.execute("create table thread_turns(thread_id text,turn_id text,status text,started_at integer,completed_at integer,rollout_ordinal integer)")
                con.execute("insert into thread_turns values('a','t','completed',?,?,1)", (int(old), int(time.time())))
                con.execute("create table thread_items(thread_id text,turn_id text,item_type text,item_json text,rollout_ordinal integer)")
                con.execute("insert into thread_items values('a','t','reasoning',?,2)", (json.dumps({"summary": ["**Checking shard assignment logic**\nPRIVATE_SUMMARY_BODY"], "content": ["RAW_PRIVATE"]}),))
                con.execute("insert into thread_items values('a','t','agentMessage',?,3)", (json.dumps({"phase": "commentary", "text": "我正在跑 Go 测试和 Redis 检查。"}),))
                con.execute("insert into thread_items values('a','t','agentMessage',?,4)", (json.dumps({"phase": "final_answer", "text": "Go 测试通过，Redis 检查正常。"}),))
            snapshot = monitor.snapshot()
            self.assertEqual(snapshot["recentTasks"][0]["status"], "completed")
            self.assertEqual(snapshot["recentTasks"][0]["statusHeading"], "Checking shard assignment logic")
            self.assertEqual(snapshot["recentTasks"][0]["progressText"], "我正在跑 Go 测试和 Redis 检查。")
            self.assertEqual(snapshot["recentTasks"][0]["completedText"], "Go 测试通过，Redis 检查正常。")
            self.assertNotIn("PRIVATE_SUMMARY_BODY", json.dumps(snapshot))
            self.assertNotIn("RAW_PRIVATE", json.dumps(snapshot))

if __name__ == "__main__":
    unittest.main()
