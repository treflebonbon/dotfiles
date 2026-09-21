"""OS boundary for the dedicated MVP evaluation entrypoint; not a general runner."""
import json
import os
from pathlib import Path
import runpy
import shutil
import socket
import subprocess
import sys
import threading
import time

def tools():
    return {name:str(Path(shutil.which(name) or '/missing-tool/'+name).resolve(strict=True))
            for name in ('python3','codex','bash','bwrap','node','rg','sed','sha256sum')}

def execute(directory, start, bundle):
    paths = tools()
    if paths != start['tools']:
        raise ValueError('runtime tools changed since init')
    root = Path(__file__).resolve().parents[1]
    gateway_path = root/'private_dot_local/share/codex-isolation/secret-isolation-gateway.py'
    closure = subprocess.check_output(['nix-store','--query','--requisites',
               *sorted({str(Path(p).parents[1]) for p in paths.values()})],text=True).splitlines()
    gateway = None
    args = [paths['bwrap'],'--unshare-all','--die-with-parent','--new-session','--clearenv']
    for path in closure:
        args.extend(['--ro-bind',path,path])
    empty = directory/'empty'
    empty.mkdir()
    for name in bundle['artifacts']:
        (empty/name).touch()
    args.extend(['--proc','/proc','--dev','/dev','--tmpfs','/tmp','--dir','/home/agent',
                 '--ro-bind',str(directory/'inputs'),'/inputs',
                 '--ro-bind',str(empty),'/artifacts',
                 '--ro-bind',str(Path(__file__).resolve()),'/runner.py',
                 '--dir','/bin','--symlink',paths['bash'],'/bin/bash',
                 '--setenv','HOME','/home/agent','--setenv','CODEX_HOME','/home/agent/.codex',
                 '--setenv','PATH',':'.join(sorted({str(Path(p).parent) for p in paths.values()})),
                 '--setenv','SHELL',paths['bash'],'--chdir','/artifacts'])
    for name in bundle['artifacts']:
        args.extend(['--bind',str(directory/'artifacts'/name),'/artifacts/'+name])
    config = {'paths':paths,'mode':start['mode'],'files':bundle['artifacts'],
              'prompt':(directory/'prompt.txt').read_text(),'forbidden':str(directory/'bundle.json')}
    try:
        if start['mode']=='live':
            module = runpy.run_path(str(gateway_path))
            gateway = module['start_gateway'](directory/'gateway','model')
            args.extend(['--ro-bind',str(directory/'gateway'),'/gateway',
                         '--ro-bind',str(gateway_path),'/gateway-bridge.py'])
        args.extend(['--',paths['python3'],'-I','/runner.py','--inside'])
        (directory/'launch.json').write_text(json.dumps({'command':args,'config':config},ensure_ascii=False,indent=2)+'\n')
        with (directory/'stdout.jsonl').open('w') as stdout, (directory/'stderr.txt').open('w') as stderr:
            child = subprocess.Popen(args,stdin=subprocess.PIPE,stdout=stdout,stderr=stderr,text=True)
            try:
                child.communicate(json.dumps(config),timeout=900)
                result = {'exit_code':child.returncode,'timed_out':False}
            except subprocess.TimeoutExpired:
                child.kill()
                child.communicate()
                result = {'exit_code':child.returncode,'timed_out':True}
        if gateway:
            result.update({'model_responses':gateway.requests,'gateway_status':gateway.last_status})
        return result
    finally:
        if gateway:
            gateway.shutdown()
            gateway.server_close()

def inside():
    config = json.load(sys.stdin)
    if config['mode']=='fixture':
        # This mode never mounts a gateway or starts Codex.
        assert Path('/inputs/SKILL.md').read_text()
        for path,mode in ((config['forbidden'],'r'),('/inputs/SKILL.md','a'),('/artifacts/unlisted','w')):
            try:
                with open(path,mode):
                    pass
            except OSError:
                continue
            raise RuntimeError('boundary violation: '+path)
        for name in config['files']:
            Path('/artifacts',name).write_text('export const fixture = true;\n' if name.endswith('.mjs') else 'fixture memo\n')
        print(json.dumps({'type':'fixture','result':'FIXTURE_BOUNDARY_OK'}))
        return
    module = runpy.run_path('/gateway-bridge.py')
    threading.Thread(target=module['bridge'],args=('/gateway/service.sock',8123),daemon=True).start()
    for _ in range(100):
        try:
            with socket.create_connection(('127.0.0.1',8123),timeout=1):
                break
        except OSError:
            time.sleep(.01)
    else:
        raise RuntimeError('model bridge unavailable')
    Path('/home/agent/.codex').mkdir(parents=True)
    args = [config['paths']['codex'],'exec','--ignore-user-config','--ephemeral',
            '--skip-git-repo-check','--sandbox','workspace-write','--json','-m','gpt-5.6-terra',
            '-C','/artifacts']
    for setting in ('approval_policy="never"','model_reasoning_effort="high"',
                    'model_provider="isolated"',
                    'model_providers.isolated={name="Isolated model",base_url="http://127.0.0.1:8123/v1",wire_api="responses",requires_openai_auth=false,request_max_retries=0,stream_max_retries=0}',
                    'web_search="disabled"','features.shell_snapshot=false'):
        args.extend(['-c',setting])
    result = subprocess.run([*args,'-'],input=config['prompt']+'\n追加の実行指示:\n'+Path('/inputs/AGENTS.md').read_text(),text=True)
    sys.exit(result.returncode)

if __name__=='__main__' and sys.argv[1:]==['--inside']:
    inside()
