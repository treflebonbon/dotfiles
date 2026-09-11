#!/usr/bin/env bats

@test "PR evidence preserves both concurrent updates to one PR" {
  run node --input-type=module - "$BATS_TEST_DIRNAME/../private_dot_config/nix-devshell/packages/pr-evidence.mjs" "$BATS_TEST_TMPDIR" <<'JS'
import assert from 'node:assert/strict';
import {setTimeout as delay} from 'node:timers/promises';
const { publishEvidence } = await import(process.argv[2]);
let body = 'Existing text\nPLACE_A\nPLACE_B';
const github = async (args) => {
 if(args[1] === 'view') { const snapshot=body; await delay(50); return JSON.stringify({body:snapshot}); }
 if(args[1] === 'edit') {const {readFile}=await import('node:fs/promises');body=await readFile(args.at(-1),'utf8');return '';}
 throw new Error('unexpected command');
};
await Promise.all(['A','B'].map(label=>publishEvidence({repo:'owner/repo',pr:42,placeholder:`PLACE_${label}`,asset:`https://github.com/user-attachments/assets/${label}`,directory:process.argv[3],github})));
assert.ok(body.startsWith('Existing text'));
assert.ok(body.includes('/assets/A'));
assert.ok(body.includes('/assets/B'));
JS
  [ "$status" -eq 0 ]
}

@test "upload failure closes only its owned page and preserves the sibling page" {
  run node --input-type=module - "$BATS_TEST_DIRNAME/../private_dot_config/nix-devshell/packages/pr-evidence.mjs" <<'JS'
import assert from 'node:assert/strict';
const { uploadEvidence }=await import(process.argv[2]);
let closed=0; const sibling={closed:false};
const editor={inputValue:async()=>'',waitFor:async()=>{},evaluate:async()=>{},setInputFiles:async()=>{throw new Error('network failed');}};
const body={locator:()=>editor,getByText:()=>({click:async()=>{}})};
const page={goto:async()=>{},url:()=> 'https://github.com/owner/repo/pull/42',locator:()=>({first:()=>body}),close:async()=>{closed++;}};
editor.click=async()=>{};
await assert.rejects(uploadEvidence({newPage:async()=>page,pages:()=>[sibling,page],close:async()=>{sibling.closed=true;}},{repo:'owner/repo',pr:42,image:'/dummy.png'}), /upload-failed/);
assert.equal(closed,1);assert.equal(sibling.closed,false);
JS
  [ "$status" -eq 0 ]
}

@test "reusing an existing asset still replaces a different requested placeholder" {
  run node --input-type=module - "$BATS_TEST_DIRNAME/../private_dot_config/nix-devshell/packages/pr-evidence.mjs" "$BATS_TEST_TMPDIR" <<'JS'
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {publishEvidence}=await import(process.argv[2]);
let body='![Earlier](https://github.com/user-attachments/assets/A)\nNEW_PLACE';
const github=async args=>{if(args[1]==='view')return JSON.stringify({body});body=await readFile(args.at(-1),'utf8');return '';};
await publishEvidence({repo:'owner/repo',pr:42,placeholder:'NEW_PLACE',asset:'https://github.com/user-attachments/assets/A',directory:process.argv[3],github});
assert.ok(!body.includes('NEW_PLACE'));
assert.equal(body.split('/assets/A').length,3);
JS
  [ "$status" -eq 0 ]
}
