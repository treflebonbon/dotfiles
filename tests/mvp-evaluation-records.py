"""Keep native tool failures omitted by the compact exec JSONL stream."""
import contextlib
import io
import json
from pathlib import Path
import runpy
import tempfile

runtime = runpy.run_path(str(Path(__file__).resolve().parents[1]/'scripts/mvp-evaluation-runtime.py'))
with tempfile.TemporaryDirectory() as temporary:
    home = Path(temporary)
    sessions = home/'sessions'
    sessions.mkdir()
    records = [
        {'type':'response_item','payload':{'type':'message','role':'system','content':'do not export context'}},
        {'type':'response_item','payload':{'type':'function_call','call_id':'read-1','name':'exec_command','arguments':'{"cmd":"cat /inputs/SKILL.md"}'}},
        {'type':'response_item','payload':{'type':'function_call_output','call_id':'read-1','output':'sandbox initialization failed'}},
        {'type':'response_item','payload':{'type':'custom_tool_call','call_id':'edit-1','name':'apply_patch','input':'patch'}},
        {'type':'response_item','payload':{'type':'custom_tool_call_output','call_id':'edit-1','output':'Failed to write file'}},
    ]
    (sessions/'rollout.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in records))
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        runtime['emit_tool_records'](home)
    actual = [json.loads(line) for line in output.getvalue().splitlines()]
    assert [r['record'] for r in actual] == records[1:]
    assert [r['line'] for r in actual] == [2,3,4,5]
    assert all(r['type']=='runtime.tool_record' for r in actual)
print('native tool calls and failed outputs retained; system context excluded')
