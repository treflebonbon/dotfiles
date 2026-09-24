import { initState, reduce } from '/tmp/nix-shell.1IE6Qp/nix-shell.nIPVB2/nix-shell.lisrE2/nix-shell.lLt6rM/claude-1000/-home-ubuntu-ghq-github-com-treflebonbon-dotfiles/0df31814-6774-43dc-9854-523dea1cded4/scratchpad/ab/blind/S-2/model.mjs';

let trials = 2000;
let failures = 0;
for (let t = 0; t < trials; t++) {
  const n = 2 + Math.floor(Math.random() * 4);
  let s = initState();
  for (let i = 0; i < n; i++) s = reduce(s, { type: 'SUBMIT', text: 'x' });
  const finalGen = s.currentGeneration;
  const outcomes = [];
  for (let i = 1; i <= n; i++) {
    const ok = Math.random() < 0.5;
    outcomes.push({ generation: i, outcome: ok ? { ok: true, data: `d${i}` } : { ok: false, error: `e${i}` } });
  }
  const order = [...outcomes];
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [order[i], order[j]] = [order[j], order[i]];
  }
  for (const o of order) s = reduce(s, { type: 'SETTLE', generation: o.generation, outcome: o.outcome });
  const finalOutcome = outcomes[finalGen - 1].outcome;
  let ok = true;
  if (finalOutcome.ok) {
    ok = s.displayed.status === 'success' && s.displayed.data === finalOutcome.data;
  } else {
    ok = s.displayed.status === 'error' && s.displayed.error === finalOutcome.error;
  }
  if (!ok) {
    failures++;
    console.log('FAIL', JSON.stringify({ n, outcomes, order, got: s }));
    if (failures > 5) break;
  }
}
console.log(`S-2 fuzz: ${trials} trials, ${failures} failures`);
