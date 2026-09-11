"""Check generated ROP reports in an existing Playwright CLI session."""

import argparse
import base64
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("reports", type=Path, nargs="+")
parser.add_argument("--session", required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
samples = [{"name": path.parent.name, "html": path.read_text()} for path in args.reports]
code = r"""async page => {
  const results = [];
  for (const sample of SAMPLES) {
    const tab = await page.context().newPage();
    const errors = [];
    tab.on('pageerror', error => errors.push(error.message));
    await tab.route('**/*', route => route.abort());
    await tab.bringToFront();
    try {
      await tab.setContent(sample.html);
      const model = await tab.locator('#flow-data').evaluate(el => JSON.parse(el.textContent));
      const sizes = [];
      for (const width of [1440, 390]) {
        await tab.setViewportSize({width, height: 1000});
        await tab.evaluate(() => new Promise(requestAnimationFrame));
        sizes.push(await tab.evaluate(() => {
          const graph = document.querySelector('#graph');
          const nodes = [...graph.querySelectorAll('.node')];
          const nodeBoxes = nodes.map(el => ({id: el.dataset.node, box: el.getBoundingClientRect()}));
          const model = JSON.parse(document.querySelector('#flow-data').textContent);
          const texts = [...graph.querySelectorAll('text')].filter(el => el.textContent.trim())
            .map(el => ({text: el.textContent, box: el.getBoundingClientRect()}));
          const textOverlaps = [];
          for (let i = 0; i < texts.length; i++) for (let j = i + 1; j < texts.length; j++) {
            const a = texts[i].box, b = texts[j].box;
            if (Math.min(a.right,b.right) - Math.max(a.left,b.left) > 1 &&
                Math.min(a.bottom,b.bottom) - Math.max(a.top,b.top) > 1)
              textOverlaps.push([texts[i].text, texts[j].text]);
          }
          const lineOverlaps = [];
          const nodeCrossings = [];
          const endpointErrors = [];
          for (const path of graph.querySelectorAll('.flowchart-link')) {
            const matrix = path.getScreenCTM();
            const edge = model.edges[Number(path.dataset.edgeIndex)];
            const others = nodeBoxes.filter(node => node.id !== edge.from && node.id !== edge.to);
            let textHit = false, nodeHit = false;
            for (let distance = 0; distance <= path.getTotalLength(); distance += 2) {
              const raw = path.getPointAtLength(distance);
              const point = new DOMPoint(raw.x, raw.y).matrixTransform(matrix);
              const hit = texts.find(({box}) => point.x > box.left + 1 && point.x < box.right - 1 &&
                point.y > box.top + 1 && point.y < box.bottom - 1);
              if (hit && !textHit) {lineOverlaps.push({path: path.id, text: hit.text}); textHit = true;}
              const crossed = others.find(({box}) => point.x > box.left + 1 && point.x < box.right - 1 &&
                point.y > box.top + 1 && point.y < box.bottom - 1);
              if (crossed && !nodeHit) {nodeCrossings.push({path: path.id, node: crossed.id}); nodeHit = true;}
              if (textHit && nodeHit) break;
            }
            for (const [id, distance] of [[edge.from, 0], [edge.to, path.getTotalLength()]]) {
              const raw = path.getPointAtLength(distance);
              const point = new DOMPoint(raw.x, raw.y).matrixTransform(matrix);
              const box = nodeBoxes.find(node => node.id === id).box;
              const dx = Math.max(box.left-point.x, 0, point.x-box.right);
              const dy = Math.max(box.top-point.y, 0, point.y-box.bottom);
              if (Math.hypot(dx,dy) > 12) endpointErrors.push({path: path.id, node: id});
            }
          }
          const svg = graph.querySelector('svg');
          const scale = svg.getBoundingClientRect().width / svg.viewBox.baseVal.width;
          const entry = nodeBoxes.find(node => node.id === model.start).box;
          const viewport = graph.getBoundingClientRect();
          return {width: innerWidth, textOverlaps, lineOverlaps, nodeCrossings, endpointErrors,
            nodes: nodes.length, edges: graph.querySelectorAll('path[data-edge-index]').length,
            labelFontSize: parseFloat(getComputedStyle(svg).fontSize) * scale,
            graphOverflow: graph.scrollWidth > graph.clientWidth,
            entryVisible: entry.left >= viewport.left && entry.right <= viewport.right,
            bodyOverflow: document.documentElement.scrollWidth > innerWidth};
        }));
      }
      if (sizes.some(size => size.nodes !== model.nodes.length || size.edges !== model.edges.length)) throw Error('graph count mismatch');
      const mobileScreenshot = (await tab.locator('.sheet').screenshot()).toString('base64');
      let transitions = 0;
      for (const node of model.nodes) {
        await tab.locator('#graph [data-node="' + node.id + '"]').focus();
        await tab.keyboard.press('Enter');
        if (await tab.locator('#detail').getAttribute('data-node') !== node.id) throw Error('node selection');
        if (node.source) {
          await tab.locator('#source-detail summary').click();
          if (await tab.locator('#source-code').textContent() !== node.excerpt) throw Error('source mismatch');
        }
        const edges = model.edges.filter(edge => edge.from === node.id);
        if (await tab.locator('#transitions').count()) {
          const items = tab.locator('#transitions li');
          if (await items.count() !== edges.length) throw Error('missing transition');
          for (let index = 0; index < edges.length; index++) {
            const text = await items.nth(index).textContent();
            if (!text.includes(edges[index].label || '次へ')) throw Error('missing condition');
            transitions++;
          }
        }
      }
      for (const [index, path] of model.paths.entries()) {
        await tab.locator('#path').selectOption(String(index));
        // A retry can traverse an edge twice; the SVG contains one element per edge.
        const expected = [...new Set(path.edges)].sort((a,b) => a-b);
        const actual = await tab.locator('#graph .on-path').evaluateAll(els =>
          els.map(el => Number(el.dataset.edgeIndex)).sort((a,b) => a-b));
        if (JSON.stringify(actual) !== JSON.stringify(expected)) throw Error('incorrect path edges');
        const expectedNodes = [...new Set(path.edges.flatMap(i => [model.edges[i].from, model.edges[i].to]))].sort();
        const actualNodes = await tab.locator('#graph .node:not(.dimmed)').evaluateAll(els => els.map(el => el.dataset.node).sort());
        if (JSON.stringify(actualNodes) !== JSON.stringify(expectedNodes)) throw Error('incorrect path nodes');
        await tab.locator('#steps button').first().click();
        if (await tab.locator('#path').inputValue() !== String(index)) throw Error('node selection changed path');
      }
      await tab.locator('#path').selectOption('');
      if (await tab.locator('#graph .dimmed, #graph .on-path').count()) throw Error('path reset');
      await tab.locator('#steps button').first().click();
      if (await tab.locator('#transitions button').count()) {
        const edge = model.edges.find(edge => edge.from === model.nodes[0].id);
        await tab.locator('#transitions button').first().click();
        if (await tab.locator('#detail').getAttribute('data-node') !== edge.to) throw Error('transition navigation');
        await tab.locator('#steps button').first().click();
      }
      await tab.setViewportSize({width: 1440, height: 1000});
      await tab.locator('#graph').evaluate(el => {el.scrollLeft = 0;});
      results.push({name: sample.name, sizes, transitions, paths: model.paths.length, errors,
        mobileScreenshot,
        screenshot: (await tab.locator('.sheet').screenshot()).toString('base64')});
    } finally {await tab.close();}
  }
  return results;
}""".replace("SAMPLES", json.dumps(samples))
script = args.output / "check.js"
script.write_text(code)
run = subprocess.run(["playwright-cli", f"-s={args.session}", "run-code", "--filename", str(script), "--raw"], capture_output=True, text=True, check=True)
try:
    results = json.loads(run.stdout)
except json.JSONDecodeError:
    raise RuntimeError(run.stdout[:2000]) from None
for result in results:
    (args.output / f'{result["name"]}.png').write_bytes(base64.b64decode(result.pop("screenshot")))
    (args.output / f'{result["name"]}-mobile.png').write_bytes(base64.b64decode(result.pop("mobileScreenshot")))
(args.output / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2))
print(json.dumps(results, ensure_ascii=False, indent=2))
assert all(not result["errors"] and all(not size["textOverlaps"] and not size["lineOverlaps"]
           and not size["nodeCrossings"] and not size["endpointErrors"] and not size["bodyOverflow"] and size["entryVisible"] and size["labelFontSize"] >= 13.9 for size in result["sizes"]) for result in results), "flowchart geometry regression"
