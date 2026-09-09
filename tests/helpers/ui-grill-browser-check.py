"""Check the round template in an existing Playwright CLI session.

Usage: python3 tests/helpers/ui-grill-browser-check.py --session NAME --output tmp/ui-grill-check
The browser uses a routed localhost page; this does not verify file-URL permissions.
"""

import argparse
import base64
import json
from pathlib import Path
import subprocess
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--session", required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
template = Path(__file__).resolve().parents[2] / "local-skills/ui-grill-with-docs/assets/round.html"
code = r"""async page => {
  const tab = await page.context().newPage();
  const errors = [], network = [], checks = [], screenshots = [];
  const url = 'http://127.0.0.1:8765/ui-grill-TEST_ID.html';
  let html = HTML_SOURCE.replace('"sessionId": "example-product-list"', '"sessionId": "test-TEST_ID"');
  const original = html;
  tab.on('pageerror', error => errors.push(error.message));
  await tab.route('**/*', route => {
    if (route.request().url() === url) return route.fulfill({contentType: 'text/html', body: html});
    network.push(route.request().url());
    return route.abort();
  });
  const check = (condition, message) => {if (!condition) throw Error(message);};
  const output = () => tab.locator('#markdown').inputValue();
  const unanswered = async () => (await output()).match(/回答: 未回答/g)?.length || 0;
  try {
    await tab.goto(url);
    await tab.bringToFront();
    const key = await tab.evaluate(() => {
      const round = JSON.parse(document.querySelector('#round-data').textContent);
      return `ui-grill:${JSON.stringify([round.sessionId, round.roundId])}`;
    });
    check(await tab.locator('fieldset').count() === 3, 'all questions rendered');
    check(await tab.locator('input:checked').count() === 0, 'recommendations must start unanswered');
    check(await unanswered() === 3, 'empty answers must be explicit');
    check(await tab.locator('#questions .comparison').count() === 1, 'visual comparison missing');
    check(!(await tab.locator('#copy').isDisabled()), 'partial copy disabled');
    checks.push('initial unanswered round, inline mockup, partial export');

    const custom = '独自案: 横幅に合わせる\n<svg onload="throw 1"> *強調* [リンク](https://example.com)';
    await tab.locator('#note-0').fill(custom);
    check(await unanswered() === 2, 'free-text-only answer not counted');
    check(!(await output()).includes('選択:'), 'unselected recommendation exported as answer');
    await tab.getByRole('radio').first().focus();
    await tab.keyboard.press('ArrowDown');
    check(await tab.getByRole('radio').nth(1).isChecked(), 'keyboard radio choice');
    check(!(await tab.getByRole('radio').first().isChecked()), 'single choice not exclusive');
    await tab.getByRole('button', {name: 'Q1の選択を解除'}).click();
    check(await tab.locator('input:checked').count() === 0, 'single choice cannot be cleared');
    check(await tab.locator('#note-0').inputValue() === custom, 'clearing choice erased free text');
    await tab.getByRole('radio').nth(1).check();
    await tab.getByRole('checkbox').nth(0).check();
    await tab.getByRole('checkbox').nth(1).check();
    check(await unanswered() === 1, 'multi-select answer not counted');
    const expected = await output();
    check(expected.includes('## Q1. 一覧のレイアウト') && expected.includes('画像の見比べ'), 'question context missing');
    check(expected.includes('- 価格\n- 在庫状況'), 'multiple selections missing');
    check(expected.includes('\\<svg') && expected.includes('\\*強調\\*'), 'answer Markdown is not escaped');
    check(await tab.locator('#questions svg').count() === 0, 'free text became markup');
    checks.push('keyboard single choice, multiple choice, custom multiline text, Markdown escaping');

    await tab.reload();
    check(await output() === expected, 'reload changed the answers');
    check(await tab.locator('#note-0').inputValue() === custom, 'draft text not restored verbatim');
    checks.push('same-round browser draft restoration');

    await tab.context().grantPermissions(['clipboard-read', 'clipboard-write'], {origin: 'http://127.0.0.1:8765'});
    await tab.bringToFront();
    await tab.getByRole('button', {name: '回答をコピー'}).click();
    await tab.waitForFunction(() => document.querySelector('#copy-status').textContent.includes('コピーしました'));
    const copied = await tab.evaluate(() => navigator.clipboard.readText());
    // Native clipboard text can use CRLF even though textarea values use LF.
    check(copied.replace(/\r\n/g, '\n') === expected, 'clipboard does not match visible Markdown');
    checks.push('real clipboard write/read');

    for (const unavailable of [false, true]) {
      await tab.evaluate(unavailable => {
        Object.defineProperty(navigator, 'clipboard', {configurable: true, value: unavailable ? undefined : {
          writeText: () => Promise.reject(new DOMException('Denied', 'NotAllowedError')),
        }});
      }, unavailable);
      await tab.locator('#copy').click();
      await tab.waitForFunction(() => document.querySelector('#copy-status').textContent.includes('自動コピーできません'));
      check(await tab.locator('#markdown').evaluate(el => document.activeElement === el && el.selectionStart === 0 && el.selectionEnd === el.value.length), 'manual-copy output not selected');
    }
    checks.push('clipboard denied and missing: manual-copy fallback');

    for (const [width, scheme] of [[1440, 'light'], [390, 'dark']]) {
      await tab.setViewportSize({width, height: 1000});
      await tab.emulateMedia({colorScheme: scheme});
      await tab.evaluate(() => window.scrollTo(0, 0));
      check(await tab.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'horizontal overflow');
      screenshots.push({name: `round-${width}-${scheme}.png`, data: (await tab.screenshot({fullPage: true})).toString('base64')});
    }
    checks.push('desktop/light and mobile/dark layout');

    html = original.replace('"roundId": "r1"', '"roundId": "r2"');
    await tab.reload();
    check(await unanswered() === 3, 'new round restored old answers');
    html = original.replace('"sessionId": "test-TEST_ID"', '"sessionId": "other-TEST_ID"');
    await tab.reload();
    check(await unanswered() === 3, 'another session restored old answers');
    html = original.replace('名前の読み比べと画像の見比べ', '価格の比較と在庫の確認');
    await tab.reload();
    check(await unanswered() === 3, 'changed questions restored stale answers');
    checks.push('round, session, and question-change isolation');

    html = original;
    await tab.evaluate(key => localStorage.setItem(key, '{broken'), key);
    await tab.reload();
    check(await unanswered() === 3, 'corrupt draft should keep sheet usable');
    check((await tab.locator('#save-status').textContent()).includes('読み込めません'), 'corrupt draft warning missing');
    await tab.locator('#note-2').fill('入力し直す');
    await tab.reload();
    check(await tab.locator('#note-2').inputValue() === '入力し直す', 'corrupt draft cannot recover');
    checks.push('corrupt draft recovery');

    await tab.addInitScript(() => {
      Storage.prototype.getItem = () => {throw new DOMException('Denied', 'SecurityError');};
      Storage.prototype.setItem = () => {throw new DOMException('Full', 'QuotaExceededError');};
    });
    await tab.reload();
    await tab.locator('#note-0').fill('保存不可でもコピーする');
    check((await tab.locator('#save-status').textContent()).includes('自動保存できません'), 'storage failure hidden');
    check((await output()).includes('保存不可でもコピーする'), 'storage failure broke export');
    check(await unanswered() === 2, 'storage failure broke input');
    checks.push('storage read/write failure keeps input and export usable');
    check(errors.length === 0, 'browser errors: ' + errors.join(', '));
    check(network.length === 0, 'unexpected network: ' + network.join(', '));
    return {checks, errors, network, screenshots};
  } finally {await tab.close();}
}""".replace("HTML_SOURCE", json.dumps(template.read_text())).replace("TEST_ID", uuid.uuid4().hex)
script = args.output / "check.js"
script.write_text(code)
run = subprocess.run(
    ["playwright-cli", f"-s={args.session}", "run-code", f"--filename={script}", "--raw"],
    capture_output=True, text=True, check=True,
)
try:
    result = json.loads(run.stdout)
except json.JSONDecodeError:
    raise RuntimeError(run.stdout[:3000]) from None
for screenshot in result.pop("screenshots"):
    (args.output / screenshot["name"]).write_bytes(base64.b64decode(screenshot["data"]))
(args.output / "results.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))
print(json.dumps(result, ensure_ascii=False, indent=2))
