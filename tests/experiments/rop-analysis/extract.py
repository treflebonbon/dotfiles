"""Read-only adapters. Syntax evidence is never promoted to inferred type facts."""
import argparse
import json
import os
import queue
import subprocess
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
WORK = REPO / 'tmp/rop-analysis-comparison'


def environment():
    env = os.environ.copy()
    paths = (WORK / 'preflight/tool-paths.txt').read_text().splitlines()
    env['PATH'] = os.pathsep.join(str(Path(p).parent) for p in paths) + os.pathsep + env['PATH']
    env['CARGO_TARGET_DIR'] = str(WORK / 'build')
    return env


def run(command, root, timeout=180):
    proc = subprocess.run(command, cwd=root, env=environment(), capture_output=True, text=True, timeout=timeout)
    if proc.returncode:
        raise RuntimeError(f'{command[0]} exited {proc.returncode}: {proc.stderr[-3000:]}')
    return proc.stdout


class Lsp:
    def __init__(self, root, features):
        self.root = root
        self.messages = queue.Queue()
        self.counter = 0
        self.diagnostics = []
        self.stderr = (WORK / 'preflight' / f'ra-{root.name}.stderr').open('w')
        self.proc = subprocess.Popen(['rust-analyzer'], cwd=root, env=environment(),
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.stderr)
        threading.Thread(target=self.read, daemon=True).start()
        self.request('initialize', {'processId': os.getpid(), 'rootUri': root.as_uri(),
            'capabilities': {'general': {'positionEncodings': ['utf-16']},
                             'experimental': {'serverStatusNotification': True}},
            'workspaceFolders': [{'uri': root.as_uri(), 'name': root.name}],
            'initializationOptions': {'checkOnSave': False, 'cargo': {'buildScripts': {'enable': True}, 'features': features},
                                      'hover': {'documentation': {'enable': False}},
                                      'procMacro': {'enable': True}}})
        self.send({'method': 'initialized', 'params': {}})
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline:
            msg = self.receive(deadline)
            if msg.get('method') == 'experimental/serverStatus' and msg.get('params', {}).get('quiescent'):
                self.diagnostics.append(msg)
                return
        raise TimeoutError('rust-analyzer did not finish loading')

    def read(self):
        try:
            while True:
                length = None
                while True:
                    line = self.proc.stdout.readline()
                    if not line:
                        raise EOFError('rust-analyzer exited')
                    if line == b'\r\n':
                        break
                    if line.lower().startswith(b'content-length:'):
                        length = int(line.split(b':')[1])
                self.messages.put(json.loads(self.proc.stdout.read(length)))
        except Exception as error:
            self.messages.put(error)

    def send(self, message):
        payload = json.dumps({'jsonrpc': '2.0', **message}).encode()
        self.proc.stdin.write(f'Content-Length: {len(payload)}\r\n\r\n'.encode() + payload)
        self.proc.stdin.flush()

    def receive(self, deadline):
        msg = self.messages.get(timeout=max(0.01, deadline - time.monotonic()))
        if isinstance(msg, Exception):
            raise msg
        if 'method' in msg and 'id' in msg:
            result = [] if msg['method'] == 'workspace/configuration' else None
            if msg['method'] == 'workspace/configuration':
                result = [None for _ in msg.get('params', {}).get('items', [])]
            self.send({'id': msg['id'], 'result': result})
        if msg.get('method') == 'textDocument/publishDiagnostics':
            self.diagnostics.append(msg)
        return msg

    def request(self, method, params):
        self.counter += 1
        ident = self.counter
        self.send({'id': ident, 'method': method, 'params': params})
        deadline = time.monotonic() + 180
        while True:
            msg = self.receive(deadline)
            if msg.get('id') == ident and 'method' not in msg:
                return msg

    def close(self):
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()
        self.stderr.close()


def enrich(root, data, features):
    client = Lsp(root, features)
    try:
        for file in sorted({node['path'] for node in data['nodes']}):
            client.send({'method': 'textDocument/didOpen', 'params': {'textDocument': {
                'uri': (root / file).as_uri(), 'languageId': 'rust', 'version': 1,
                'text': (root / file).read_text()}}})
        cache = {}
        for node in data['nodes']:
            if node['kind'] not in ('call', 'method_call', 'function', 'method'):
                continue
            line = node.get('queryLine', node['start']) - 1
            column = node.get('queryColumn', node.get('column', 0))
            source_line = (root / node['path']).read_text().splitlines()[line]
            prefix = source_line[:column]
            position = {'line': line, 'character': len(prefix.encode('utf-16-le')) // 2}
            key = (node['path'], line, position['character'])
            if key not in cache:
                params = {'textDocument': {'uri': (root / node['path']).as_uri()}, 'position': position}
                cache[key] = {'queryPosition': position,
                    'hoverAtPosition': client.request('textDocument/hover', params),
                    'definitionAtPosition': client.request('textDocument/definition', params)}
            node['semantic'] = cache[key]
        data['diagnostics'].extend(client.diagnostics)
    finally:
        client.close()
    return data


def extract(case, backend):
    root = Path(case['root']).resolve()
    if backend == 'ts-morph':
        data = json.loads(run(['node', str(HERE / 'extract-ts.mjs'), str(root),
                             str(root / case['config']), *case['files']], root))
    elif backend in ('syn', 'rust-analyzer'):
        data = json.loads(run([str(WORK / 'build/debug/rop-syn-extractor'), *case['files']], root))
        if backend == 'rust-analyzer':
            data = enrich(root, restrict(case, data), case.get('cargoFeatures', []))
    elif backend == 'ast-grep':
        kinds = ('call_expression|return_statement|if_statement|ternary_expression|yield_expression|'
                 'throw_statement|arrow_function|function_declaration|function_expression') if case['language'] == 'ts' else (
                 'call_expression|try_expression|match_expression|return_expression|if_expression|'
                 'closure_expression|async_block|loop_expression|for_expression|while_expression|'
                 'break_expression|continue_expression|macro_invocation|function_item')
        rule = '\n---\n'.join(json.dumps({'id': kind,
            'language': 'TypeScript' if case['language'] == 'ts' else 'Rust',
            'rule': {'kind': kind}}) for kind in kinds.split('|'))
        proc = subprocess.run(['ast-grep', 'scan', '--inline-rules', rule, '--json=compact', *case['files']],
                              cwd=root, env=environment(), capture_output=True, text=True, timeout=180)
        if proc.returncode not in (0, 1):
            raise RuntimeError(proc.stderr)
        matches = json.loads(proc.stdout)
        data = {'nodes': [{'path': m['file'], 'start': m['range']['start']['line'] + 1,
                  'end': m['range']['end']['line'] + 1, 'range': m['range'], 'text': m['text'][:180],
                  'kind': m['ruleId'], 'type': None} for m in matches], 'diagnostics': []}
        # Tree containment is structural evidence, not name/scope resolution.
        for index, node in enumerate(data['nodes']):
            lo, hi = node['range']['byteOffset']['start'], node['range']['byteOffset']['end']
            parents = [(j, p) for j, p in enumerate(data['nodes']) if j != index and p['path'] == node['path']
                       and p['range']['byteOffset']['start'] <= lo and hi <= p['range']['byteOffset']['end']
                       and p['range']['byteOffset'] != node['range']['byteOffset']]
            node['parent'] = min(parents, key=lambda pair: pair[1]['range']['byteOffset']['end'] - pair[1]['range']['byteOffset']['start'])[0] if parents else None
    else:
        raise ValueError(backend)
    data = restrict(case, data)
    data['backend'] = backend
    data['entry'] = case['entry']
    data['capabilities'] = 'syntax+semantic' if backend in ('ts-morph', 'rust-analyzer') else 'syntax-only'
    return data


def restrict(case, data):
    if 'ranges' not in case:
        return data
    # Parent/scope indices refer to the original list; retain explicit ids after filtering.
    for i, node in enumerate(data['nodes']):
        node.setdefault('id', i)
    data['nodes'] = [n for n in data['nodes'] if any(lo <= n['start'] and n['end'] <= hi
                     for lo, hi in case['ranges'].get(n['path'], []))]
    return data


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('cases', type=Path)
    parser.add_argument('case')
    parser.add_argument('backend', choices=['ast-grep', 'syn', 'ts-morph', 'rust-analyzer'])
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    case = next(c for c in json.loads(args.cases.read_text()) if c['id'] == args.case)
    result = extract(case, args.backend)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2))
