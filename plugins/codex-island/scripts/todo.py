#!/usr/bin/env python3
"""Local, atomic todo storage and JSON CLI for Codex Island."""
import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import tempfile
import time
import uuid

DATA = Path(os.environ.get('CODEX_ISLAND_DATA', Path.home() / 'Library/Application Support/Codex Island'))

@contextlib.contextmanager
def store():
    DATA.mkdir(parents=True, exist_ok=True)
    with (DATA / 'todos.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = DATA / 'todos.json'
        items = json.loads(path.read_text()) if path.exists() else []
        if not isinstance(items, list):
            raise ValueError('Invalid todos.json; refusing to overwrite')
        yield items
        fd, name = tempfile.mkstemp(prefix='todos-', dir=DATA)
        try:
            with os.fdopen(fd, 'w') as out:
                json.dump(items, out, ensure_ascii=False, indent=2)
                out.flush()
                os.fsync(out.fileno())
            os.replace(name, path)
        finally:
            if os.path.exists(name):
                os.unlink(name)

def main():
    parser = argparse.ArgumentParser(description='Codex Island todo list; JSON output')
    commands = parser.add_subparsers(dest='command', required=True)
    add = commands.add_parser('add')
    add.add_argument('title')
    add.add_argument('--note', default='')
    ls = commands.add_parser('list')
    ls.add_argument('--all', action='store_true', help='include completed items')
    for name in ('done', 'reopen', 'toggle', 'remove'):
        commands.add_parser(name).add_argument('id')
    args = parser.parse_args()
    try:
        with store() as items:
            if args.command == 'add':
                title = args.title.strip()
                if not title:
                    raise ValueError('Title cannot be empty')
                if len(title) > 500 or len(args.note) > 4000:
                    raise ValueError('Title max 500 characters; note max 4000')
                result = dict(id=str(uuid.uuid4()), title=title, note=args.note,
                              done=False, createdAt=time.time(), updatedAt=time.time())
                items.append(result)
            elif args.command == 'list':
                result = [item for item in items if args.all or not item['done']]
            else:
                result = next((item for item in items if item['id'] == args.id), None)
                if result is None:
                    raise ValueError('Todo ID not found; run list --all for exact IDs')
                if args.command == 'remove':
                    items.remove(result)
                else:
                    result['done'] = (not result['done']) if args.command == 'toggle' else args.command == 'done'
                    result['updatedAt'] = time.time()
        print(json.dumps(result, ensure_ascii=False))
    except (OSError, ValueError, KeyError) as exc:
        parser.exit(1, str(exc) + '\n')

if __name__ == '__main__':
    main()
