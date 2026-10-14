import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

CLI = Path(__file__).resolve().parents[1] / 'plugins/codex-island/scripts/todo.py'

class TodoTests(unittest.TestCase):
    def test_lifecycle_and_concurrent_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ, CODEX_ISLAND_DATA=directory)
            def run(*args):
                return json.loads(subprocess.check_output(['/usr/bin/python3', str(CLI), *args], env=env))
            item = run('add', '中文待办 $()', '--note', '备注')
            self.assertEqual(run('list')[0]['title'], '中文待办 $()')
            self.assertTrue(run('done', item['id'])['done'])
            self.assertEqual(run('list'), [])
            self.assertEqual(len(run('list', '--all')), 1)
            self.assertFalse(run('reopen', item['id'])['done'])
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                list(pool.map(lambda n: run('add', str(n)), range(20)))
            self.assertEqual(len(run('list')), 21)
            run('remove', item['id'])
            self.assertEqual(len(run('list')), 20)
            path = Path(directory) / 'todos.json'
            before = path.read_bytes()
            result = subprocess.run(['/usr/bin/python3', str(CLI), 'done', 'missing'], env=env, capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(path.read_bytes(), before)
