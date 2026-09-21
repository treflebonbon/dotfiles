"""PROTOTYPE: start the existing model bridge, then one fresh Codex session."""
import json
import os
from pathlib import Path
import runpy
import socket
import subprocess
import sys
import threading
import time

config = json.load(sys.stdin)
module = runpy.run_path('/gateway-bridge.py')
threading.Thread(target=module['bridge'], args=('/gateway/service.sock', 8123), daemon=True).start()
for attempt in range(100):
    try:
        with socket.create_connection(('127.0.0.1', 8123), timeout=1):
            break
    except OSError:
        time.sleep(.01)
else:
    raise SystemExit('model bridge unavailable')
Path('/home/agent/.codex').mkdir(parents=True)
args = [config['codex'], 'exec', '--ignore-user-config', '--ephemeral',
        '--skip-git-repo-check', '--sandbox', 'read-only', '--json',
        '-m', 'gpt-5.6-terra', '-C', '/inputs']
for setting in [
    'approval_policy="never"', 'model_reasoning_effort="high"',
    'model_provider="isolated"',
    'model_providers.isolated={name="Isolated model",base_url="http://127.0.0.1:8123/v1",wire_api="responses",requires_openai_auth=false,request_max_retries=0,stream_max_retries=0}',
    'web_search="disabled"', 'features.shell_snapshot=false',
]:
    args.extend(['-c', setting])
args.append('-')
result = subprocess.run(args, input=config['prompt'], text=True, timeout=150)
sys.exit(result.returncode)
