#!/usr/bin/env python3
"""Dedicated, serial entrypoint for the frozen MVP evaluation v8 contract."""
import argparse
from collections import Counter
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = Path(__file__).with_name('mvp-evaluation-runtime.py')
SOURCES = {
    'docs/evaluations/mvp-mediator-evaluation-v8/protocol.md': 'e7bdcde3adb7fd558b80e28dc9b675cf4592d49a7f28234752e15260ffb0d732',
    'docs/evaluations/mvp-mediator-evaluation-v7/protocol.md': 'ddf710d6e2f81a89e52cc7defae528eeb355e57f470f4867ba841f65ea74ef94',
    'docs/evaluations/mvp-mediator-evaluation-v6/protocol.md': '2c9fc22d2553d8e683bc782d94dd876f8d32a8ae41dbaefefcf2fc30c9e999a6',
    'docs/evaluations/mvp-mediator-evaluation-v5/protocol.md': '0bfa5674f914d9f0361ab7784371ab1847718d452bb499d302de66bcbf63baa2',
    'local-skills/mvp-mediator-architecture/SKILL.md': 'c1ca71acce6fa1487c0de6cb73498a61c14f6e1575284934dd86f15ed042fa29',
    'local-skills/mvp-mediator-architecture/references/tanstack-effect.md': '110b25b8ba320ac61ceb38c19142f5028aabfcc28a27cfd6b7a51b0eef288cca',
    'docs/evaluations/mvp-mediator-executable/protocol.md': 'ba0c8fa045387c5026e470b357afe4d8c9a1392fbadc1f0ccceca54d7cbfbcb2',
    'docs/evaluations/mvp-mediator-executable/check-device.mjs': '72adc7af373705e1324d26c48cec7eec123e5bbbc493f77bf1f34d259eb05ae1',
    'docs/evaluations/mvp-mediator-evaluation-v2/protocol.md': '19c48ebb1c35a7aa5d011c3b280a5451ed5cdbc8dd56ddba8607dceff790fbae',
    'docs/evaluations/mvp-mediator-evaluation-v3/protocol.md': 'e2c31bc70a9412b9782bb709122c7fadd34e3b59934f7d355e4f35ef89d1f73c',
    'docs/evaluations/mvp-mediator-evaluation-v4/protocol.md': 'f54c45743f598ca025b5d154bbe5310d53687ad476559216391ca328bd85184a',
    'docs/evaluations/mvp-mediator-followup/protocol.md': 'ce4fe0c46a15f96cfd842c0c50c9310fb77f8b5118130c3fed42fd02b3a17664',
}

def require(condition, message):
    if not condition:
        raise ValueError(message)

def sha(path):
    require(path.is_file() and not path.is_symlink() and path.stat().st_nlink == 1,
            f'regular unlinked file required: {path}')
    return hashlib.sha256(path.read_bytes()).hexdigest()

def read(path):
    sha(path)
    return json.loads(path.read_text())

def save(path, value):
    with path.open('x') as output:
        output.write(json.dumps(value, ensure_ascii=False, indent=2) + '\n')

def update(run, state):
    # The run lock serializes prepare/dispatch/audit, including the child lifetime.
    temp = run/'state.next'
    temp.write_text(json.dumps(state, ensure_ascii=False, indent=2)+'\n')
    os.replace(temp, run/'state.json')

def manifest(directory):
    require(not any(p.is_symlink() for p in directory.rglob('*')), 'symlink in manifest')
    return {str(p.relative_to(directory)): sha(p) for p in sorted(directory.rglob('*')) if not p.is_dir()}

def check_sources():
    for name, digest in SOURCES.items():
        require(sha(ROOT/name) == digest, f'frozen source changed: {name}')

def init(args):
    check_sources()
    conditions = read(args.conditions)
    require(all(isinstance(conditions.get(k), str) and conditions[k].strip()
                for k in ('instructions', 'effective_context', 'runtime_notes')), 'conditions incomplete')
    git = lambda *a: subprocess.check_output(['git','-C',str(ROOT),*a], text=True).strip()
    metadata = {
        'head':git('rev-parse','HEAD'), 'branch':git('branch','--show-current'),
        'git_dir':git('rev-parse','--git-dir'), 'common_dir':git('rev-parse','--git-common-dir')}
    require(Path(metadata['git_dir']).resolve() != Path(metadata['common_dir']).resolve(), 'task worktree required')
    args.run.mkdir(parents=True, exist_ok=False)
    (args.run/'attempts').mkdir()
    save(args.run/'start.json', {'root':str(ROOT), **metadata, 'sources':SOURCES,
         'tools':runpy.run_path(str(RUNTIME))['tools'](),
         'implementation':{str(p):sha(p) for p in (Path(__file__),RUNTIME,ROOT/'private_dot_local/share/codex-isolation/secret-isolation-gateway.py')},
         'conditions':conditions, 'model':'gpt-5.6-terra','effort':'high', 'fork':False,
         'mode':'fixture' if args.fixture else 'live',
         'canonical_metadata':{'tool_uses':'N/A','duration_ms':'N/A','source':'codex exec --json', 'reason':'Codex JSONL does not establish canonical counters'},
         'scenario_s_change':'remove held-out heading marker and timing sentence only'})
    update(args.run, {'attempts':[], 'stop':None, 'start_sha256':sha(args.run/'start.json')})

def clear(audit):
    return (audit['input']=='valid' and audit['scores']==[1]*6 and
            audit['compliance']==['pass']*4 and not audit['issues'] and not audit['failure_patterns'])

def summary(state):
    decided = [a for a in state['attempts'] if a.get('audit')]
    patterns = Counter(p for a in decided for p in set(a['audit']['failure_patterns']))
    repeated = sorted(p for p,n in patterns.items() if n >= 2)
    if repeated:
        return 'repeated failure: ' + ', '.join(repeated)
    if decided and decided[-1]['audit']['input']!='valid' and sum(a['replacement'] for a in state['attempts'])>=2:
        return 'resource cutoff; replacement limit'
    latest = {a['slot']:a for a in decided}
    if all(i in latest and latest[i]['audit']['input']=='valid' for i in range(9)):
        if not all(clear(latest[i]['audit']) for i in range(9)):
            return 'resource cutoff; convergence not established (three groups complete)'
        if 9 in latest and latest[9]['audit']['input']=='valid':
            return ('qualitative plateau; quantitative convergence unverified' if clear(latest[9]['audit'])
                    else 'convergence not established (L failed)')
    if len(state['attempts']) >= 12 and decided and len(decided)==len(state['attempts']):
        return 'resource cutoff; dispatch limit'
    return None

def prepare(args, state, start):
    require(not state['stop'], f'stopped: {state["stop"]}')
    attempts = state['attempts']
    slot = 0
    if attempts:
        last = attempts[-1]
        require(last.get('audit'), 'parent audit required')
        if last['audit']['input'] != 'valid':
            require(args.replace, 'only explicit replacement is allowed')
            require(sum(a['replacement'] for a in attempts)<2, 'replacement limit')
            slot = last['slot']
        else:
            require(not args.replace, 'valid input cannot be replaced for a functional failure')
            slot = last['slot']+1
    else:
        require(not args.replace, 'nothing to replace')
    require(len(attempts)<12 and slot<10, 'dispatch limit')
    if slot == 9:
        latest = {a['slot']:a for a in attempts if a.get('audit')}
        require(all(i in latest and clear(latest[i]['audit']) for i in range(9)), 'three clear groups required')
        require(args.unused_evidence, 'L unused-history evidence required')
        unused = read(args.unused_evidence)
        require(unused.get('unused') is True and unused.get('reason'), 'explicit unused-history attestation required')
    task = 'EBS'[slot%3] if slot<9 else 'L'
    source = 'mvp-mediator-followup' if task=='L' else 'mvp-mediator-executable'
    text = (ROOT/f'docs/evaluations/{source}/protocol.md').read_text()
    section = re.search(r'^## '+task+r' — .*?(?=^## |\Z)',text,re.M|re.S).group()
    if task=='S':
        section = section.replace('## S — held-out search UI','## S — search UI').replace(' This scenario is not supplied until the plateau check.','')
    ident = f'{len(attempts)+1:02d}'
    directory = args.run/'attempts'/ident
    (directory/'inputs/references').mkdir(parents=True)
    (directory/'artifacts').mkdir()
    for name in ('SKILL.md','references/tanstack-effect.md'):
        (directory/'inputs'/name).write_bytes((ROOT/'local-skills/mvp-mediator-architecture'/name).read_bytes())
    (directory/'inputs/AGENTS.md').write_text(start['conditions']['instructions'])
    files = ['memo.md'] if task=='B' else ['memo.md','model.mjs']
    for name in files:
        (directory/'artifacts'/name).touch()
    template = (ROOT/'docs/evaluations/mvp-mediator-evaluation-v2/protocol.md').read_text().split('```text\n',1)[1].split('```',1)[0]
    requirement = (ROOT/'docs/evaluations/mvp-mediator-evaluation-v3/protocol.md').read_text().split('```text\n',1)[1].split('```',1)[0]
    anchor = '  検査名は実行したコードに存在する名前を使い、検査範囲は実際のassertionに合わせてください。\n'
    require(template.count(anchor)==1, 'case-output insertion point missing')
    template = template.replace(anchor, anchor+requirement)
    values = [f'/inputs (isolated snapshot), branch={start["branch"]}, HEAD={start["head"]}, host Git dir={start["git_dir"]} (not mounted)',
              '/inputs/SKILL.md, '+SOURCES['local-skills/mvp-mediator-architecture/SKILL.md'],
              '/inputs/references/tanstack-effect.md, '+SOURCES['local-skills/mvp-mediator-architecture/references/tanstack-effect.md'],
              ', '.join('/artifacts/'+f for f in files), section]
    for value in values:
        template = re.sub(r'<[^>]+>',lambda _:value,template,count=1)
    (directory/'prompt.txt').write_text(template)
    bundle = {'inputs':manifest(directory/'inputs'), 'prompt':sha(directory/'prompt.txt'), 'artifacts':files}
    if slot==9:
        bundle['unused_evidence'] = evidence_ref(args.unused_evidence)
    save(directory/'bundle.json',bundle)
    attempts.append({'id':ident,'slot':slot,'task':task,'replacement':args.replace,'phase':'prepared',
                     'bundle_sha256':sha(directory/'bundle.json'), 'audit':None})
    update(args.run,state)

def evidence_ref(path):
    return {'path':str(path.resolve()),'sha256':sha(path)}

def verify_bundle(directory, attempt):
    require(sha(directory/'bundle.json')==attempt['bundle_sha256'],'bundle changed')
    bundle = read(directory/'bundle.json')
    require(manifest(directory/'inputs')==bundle['inputs'] and sha(directory/'prompt.txt')==bundle['prompt'], 'input changed')
    return bundle

def verify_history(run, state):
    for attempt in state['attempts']:
        directory = run/'attempts'/attempt['id']
        verify_bundle(directory, attempt)
        if attempt.get('approval_sha256'):
            require(sha(directory/'approval.json')==attempt['approval_sha256'],'approval changed')
        if attempt.get('audit'):
            require(read(directory/'audit.json')==attempt['audit'], 'previous audit changed')
            require(all(sha(directory/ref['path'])==ref['sha256'] for ref in attempt['audit']['references']), 'audit reference changed')
        if attempt.get('evidence_sha256'):
            require(sha(directory/'evidence.json')==attempt['evidence_sha256'],'evidence changed')
            result = read(directory/'evidence.json')
            require(manifest(directory/'artifacts')==result['artifacts'],'artifacts changed after execution')
            require(all(sha(directory/f)==h for f,h in result['logs'].items()),'execution log changed')

def audit(args, state, attempt, directory):
    require(attempt['phase']=='awaiting-audit','completed evidence required; audit is immutable')
    result = read(directory/'evidence.json')
    require(sha(directory/'evidence.json')==attempt['evidence_sha256'],'evidence changed')
    require(manifest(directory/'artifacts')==result['artifacts'],'artifacts changed after execution')
    require(all(sha(directory/f)==h for f,h in result['logs'].items()),'execution log changed')
    record = read(args.record)
    require(record.get('evidence_sha256')==attempt['evidence_sha256'],'audit refers to different evidence')
    require(record.get('input') in ('valid','invalid','unknown'),'input validity required')
    scores, compliance = record.get('scores'), record.get('compliance')
    require(isinstance(scores,list) and len(scores)==6 and all(type(v) in (int,float) and v in (0,.5,1) for v in scores),'six scores required')
    require(isinstance(compliance,list) and len(compliance)==4 and all(v in ('pass','fail','unknown') for v in compliance),'C1-C4 required')
    for key in ('issues','failure_patterns'):
        require(isinstance(record.get(key),list) and all(isinstance(v,str) and v.strip() for v in record[key]),f'{key} required')
    require(record.get('reason') and isinstance(record.get('references'),list) and record['references'],'reason and evidence references required')
    for ref in record['references']:
        path = (directory/ref['path']).resolve()
        require(path.is_relative_to(directory.resolve()) and ref.get('locator'),'local evidence locator required')
        ref['sha256']=sha(path)
    if record['input']=='valid':
        parent_path = (directory/record.get('parent_checks','')).resolve()
        require(parent_path.is_relative_to((directory/'parent-checks').resolve()), 'parent-checks record required')
        checks = read(parent_path)
        required = ['proposal_review'] if attempt['task']=='B' else ['self_check']
        if attempt['task']=='E':
            required.append('fixed_checker')
        for name in required:
            check = checks.get(name,{})
            require(check.get('reason'), f'parent {name} record required')
            if name=='proposal_review':
                require(check.get('status')=='not-run','B records proposal review, not application execution')
                continue
            require(check.get('artifact_sha256')==result['artifacts']['model.mjs'], 'parent check artifact mismatch')
            require(check.get('status') in ('executed','not-run'), 'parent check status required')
            if check['status']=='executed':
                require(check.get('command') and check.get('expected') and type(check.get('exit_code')) is int and isinstance(check.get('output'),str), 'parent command, expected result, exit and output required')
            if name=='fixed_checker':
                require(check.get('checker_sha256')==SOURCES['docs/evaluations/mvp-mediator-executable/check-device.mjs'],'frozen checker mismatch')
            require(not clear(record) or (check['status']=='executed' and check['exit_code']==0), 'unexecuted/failed parent checks cannot clear')
        record['references'].append({'path':str(parent_path.relative_to(directory.resolve())), 'locator':'required parent checks','sha256':sha(parent_path)})
    require(clear(record) or record['failure_patterns'],'non-clear audit needs classified failure patterns')
    require(not clear(record) or result.get('exit_code')==0,'failed runtime cannot be clear')
    record['six_item_rate']=sum(scores)/6
    record['task_success']=scores[:2]==[1,1]
    record['decision_retry']=record.get('decision_retry','unknown')
    record['mechanical_retry']=record.get('mechanical_retry','unknown')
    if attempt['task']=='L':
        record['overfit_suspected']=1-record['six_item_rate']>=.15
    save(directory/'audit.json',record)
    attempt['audit']=record
    attempt['phase']='audited'
    state['stop']=summary(state)
    update(args.run,state)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action',required=True)
    for name in ('init','prepare','approve','dispatch','audit','status'):
        cmd = sub.add_parser(name)
        cmd.add_argument('run',type=Path)
        if name=='init':
            cmd.add_argument('--conditions',type=Path,required=True)
            cmd.add_argument('--fixture',action='store_true')
        if name=='prepare':
            cmd.add_argument('--replace',action='store_true')
            cmd.add_argument('--unused-evidence',type=Path)
        if name in ('approve','audit'):
            cmd.add_argument('--record',type=Path,required=True)
    args = parser.parse_args()
    args.run = args.run.resolve()
    if args.action=='init':
        init(args)
        return
    if args.action=='status':
        print(json.dumps(read(args.run/'state.json'),ensure_ascii=False,indent=2))
        return
    with (args.run/'lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        state, start = read(args.run/'state.json'), read(args.run/'start.json')
        check_sources()
        require(sha(args.run/'start.json')==state['start_sha256'], 'start conditions changed')
        require(all(sha(Path(p))==h for p,h in start['implementation'].items()), 'implementation changed')
        verify_history(args.run,state)
        if args.action=='prepare':
            prepare(args,state,start)
            return
        require(state['attempts'],'prepare required')
        attempt = state['attempts'][-1]
        directory = args.run/'attempts'/attempt['id']
        bundle = verify_bundle(directory,attempt)
        if args.action=='approve':
            require(attempt['phase']=='prepared','only prepared input can be approved')
            record = read(args.record)
            require(record.get('bundle_sha256')==attempt['bundle_sha256'] and record.get('reason'),'approval must bind bundle and give reason')
            save(directory/'approval.json',record)
            attempt['approval_sha256']=sha(directory/'approval.json')
            attempt['phase']='approved'
            update(args.run,state)
        elif args.action=='dispatch':
            require(attempt['phase']=='approved','approval required; completed/running dispatch cannot be replayed')
            require(not state['stop'], 'run stopped')
            require(manifest(directory/'artifacts')=={f:hashlib.sha256(b'').hexdigest() for f in bundle['artifacts']}, 'artifacts must be empty regular files')
            attempt['phase']='running'
            update(args.run,state)
            try:
                result = runpy.run_path(str(RUNTIME))['execute'](directory,start,bundle)
            except Exception as error:
                result = {'exit_code':None,'runtime_error':type(error).__name__}
            result.update({'bundle_sha256':attempt['bundle_sha256'],
                           'artifacts':manifest(directory/'artifacts'),
                           'logs':{f:sha(directory/f) for f in ('stdout.jsonl','stderr.txt','launch.json') if (directory/f).exists()},
                           'canonical_metadata':start['canonical_metadata']})
            save(directory/'evidence.json',result)
            attempt['evidence_sha256']=sha(directory/'evidence.json')
            attempt['phase']='awaiting-audit'
            update(args.run,state)
            require(result['exit_code']==0, 'runtime failed; evidence retained, parent audit required')
        else:
            audit(args,state,attempt,directory)

if __name__=='__main__':
    try:
        main()
    except (OSError,ValueError,KeyError,TypeError,subprocess.SubprocessError) as error:
        print(f'mvp-evaluation: {error}',file=sys.stderr)
        sys.exit(1)
