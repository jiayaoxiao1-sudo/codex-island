#!/usr/bin/env python3
"""Publish an explicitly classified public progress notification, or run a demo."""
import argparse
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import time
import uuid

DATA = Path.home() / "Library/Application Support/Codex Island"

def turn_key(chat_id):
    if not chat_id:
        return None
    try:
        database = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")) / "thread_history_1.sqlite"
        with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as con:
            row = con.execute("select turn_id from thread_turns where thread_id=? order by rollout_ordinal desc limit 1", (chat_id,)).fetchone()
        return chat_id + ':' + row[0] if row else None
    except sqlite3.Error:
        return None

def emit(kind, title, text, chat_id=None, demo=False):
    identifier = str(uuid.uuid4())
    key = turn_key(chat_id)
    event = {"eventId": identifier, "id": chat_id or 'demo', "rootId": chat_id or 'demo',
             "title": title, "completedText": text, "soundKind": kind, "isDemo": demo,
             "status": "completed", "phase": "done", "updatedAt": time.time(),
             "completionKey": key if kind == 'final' and key else identifier}
    if kind == 'final' and key:
        event['muteRoundKey'] = key
    folder = DATA / 'notifications'
    folder.mkdir(parents=True, exist_ok=True)
    temporary = folder / (identifier + '.tmp')
    temporary.write_text(json.dumps(event, ensure_ascii=False))
    temporary.replace(folder / (identifier + '.json'))
    deadline = time.monotonic() + 45
    receipt = DATA / 'notification-receipts' / (identifier + '.json')
    while time.monotonic() < deadline:
        if receipt.exists():
            result = json.loads(receipt.read_text())
            print(json.dumps(result, ensure_ascii=False), flush=True)
            if not result['played'] and not result['muted']:
                raise RuntimeError('Audio playback did not start')
            return result
        time.sleep(.25)
    raise TimeoutError('Notification was not presented within 45 seconds')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['demo', 'notify'])
    parser.add_argument('--kind', choices=['step', 'final'])
    parser.add_argument('--title')
    parser.add_argument('--text')
    parser.add_argument('--chat-id')
    args = parser.parse_args()
    if args.mode == 'notify':
        if not all((args.kind, args.title, args.text, args.chat_id)):
            parser.error('notify requires --kind, --title, --text and --chat-id')
        emit(args.kind, args.title, args.text, args.chat_id)
        return
    with tempfile.TemporaryDirectory(prefix='codex-island-demo-') as directory:
        path = Path(directory) / 'sample.json'
        path.write_text(json.dumps({'items': [1, 2, 3]}))
        emit('step', '[演示 1/3] 生成示例数据', '已生成 sample.json，包含 3 个数字。', demo=True)
        sample = json.loads(path.read_text())
        assert sample['items'] == [1, 2, 3]
        emit('step', '[演示 2/3] 校验示例数据', 'JSON 解析成功，数据数量和内容校验通过。', demo=True)
        total = sum(sample['items'])
        emit('final', '[演示 3/3] 多步骤任务整体完成', f'生成、校验、汇总全部完成。3 个数字合计为 {total}。', args.chat_id, demo=True)
        print('Demo completed: step → step → final', flush=True)

if __name__ == '__main__':
    main()
