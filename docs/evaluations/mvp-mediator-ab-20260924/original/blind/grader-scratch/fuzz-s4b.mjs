import { initState, transition, selectDisplay } from './s4-exportable.mjs';

let trials = 2000;
let failures = 0;
for (let t = 0; t < trials; t++) {
  const n = 2 + Math.floor(Math.random() * 4);
  let state = initState();
  for (let i = 0; i < n; i++) state = transition(state, { type: 'search', text: 'x' }).state;
  const finalId = state.acceptedId; // 1..n
  const outcomes = [];
  for (let id = 1; id <= n; id++) {
    const ok = Math.random() < 0.5;
    outcomes.push({ id, outcome: ok ? { ok: true, value: `d${id}` } : { ok: false, error: `e${id}` } });
  }
  const order = [...outcomes];
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [order[i], order[j]] = [order[j], order[i]];
  }
  for (const o of order) state = transition(state, { type: 'completed', id: o.id, outcome: o.outcome }).state;
  const finalOutcome = outcomes[finalId - 1].outcome;
  const disp = selectDisplay(state);
  let ok;
  if (finalOutcome.ok) ok = disp.status === 'success' && disp.value === finalOutcome.value;
  else ok = disp.status === 'error' && disp.error === finalOutcome.error;
  if (!ok) {
    failures++;
    console.log('FAIL', JSON.stringify({ n, outcomes, order, disp }));
    if (failures > 5) break;
  }
}
console.log(`S-4 fuzz: ${trials} trials, ${failures} failures`);
