import { initState, transition, selectDisplay } from '/tmp/nix-shell.1IE6Qp/nix-shell.nIPVB2/nix-shell.lisrE2/nix-shell.lLt6rM/claude-1000/-home-ubuntu-ghq-github-com-treflebonbon-dotfiles/0df31814-6774-43dc-9854-523dea1cded4/scratchpad/ab/blind/S-3/model.mjs';

let trials = 2000;
let failures = 0;
for (let t = 0; t < trials; t++) {
  const n = 2 + Math.floor(Math.random() * 4);
  let state = initState();
  for (let i = 0; i < n; i++) state = transition(state, { type: 'search', query: 'x' }).state;
  const finalId = state.latestId; // n-1 (0-indexed)
  const outcomes = [];
  for (let id = 0; id < n; id++) {
    const ok = Math.random() < 0.5;
    outcomes.push({ id, outcome: ok ? { type: 'success', data: `d${id}` } : { type: 'failure', error: `e${id}` } });
  }
  const order = [...outcomes];
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [order[i], order[j]] = [order[j], order[i]];
  }
  for (const o of order) state = transition(state, { type: 'resolve', id: o.id, outcome: o.outcome }).state;
  const finalOutcome = outcomes[finalId].outcome;
  const disp = selectDisplay(state.bindingState, state);
  let ok;
  if (finalOutcome.type === 'success') ok = disp.status === 'success' && disp.data === finalOutcome.data;
  else ok = disp.status === 'failure' && disp.error === finalOutcome.error;
  if (!ok) {
    failures++;
    console.log('FAIL', JSON.stringify({ n, outcomes, order, disp }));
    if (failures > 5) break;
  }
}
console.log(`S-3 fuzz: ${trials} trials, ${failures} failures`);
