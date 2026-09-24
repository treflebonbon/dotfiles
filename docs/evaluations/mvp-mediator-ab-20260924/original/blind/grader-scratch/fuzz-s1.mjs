import { initialState, reduce } from '/tmp/nix-shell.1IE6Qp/nix-shell.nIPVB2/nix-shell.lisrE2/nix-shell.lLt6rM/claude-1000/-home-ubuntu-ghq-github-com-treflebonbon-dotfiles/0df31814-6774-43dc-9854-523dea1cded4/scratchpad/ab/blind/S-1/model.mjs';

// Fuzz: random number of SEARCHes, then random-order SETTLED delivery with
// random outcomes, verify final display == outcome of settle for state.seq
// (the last SEARCH's seq), and that any settle for a non-final seq never
// changed the final status.data/error away from what the final seq dictates.
let trials = 2000;
let failures = 0;
for (let t = 0; t < trials; t++) {
  const n = 2 + Math.floor(Math.random() * 4); // 2..5 overlapping requests
  let s = initialState();
  for (let i = 0; i < n; i++) s = reduce(s, { type: 'SEARCH' });
  const finalSeq = s.seq; // == n
  const outcomes = [];
  for (let i = 1; i <= n; i++) {
    const ok = Math.random() < 0.5;
    outcomes.push({ seq: i, ok, data: ok ? `d${i}` : undefined, error: ok ? undefined : `e${i}` });
  }
  // random shuffle
  const order = [...outcomes];
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [order[i], order[j]] = [order[j], order[i]];
  }
  for (const o of order) {
    s = reduce(s, { type: 'SETTLED', seq: o.seq, ok: o.ok, data: o.data, error: o.error });
  }
  const finalOutcome = outcomes[finalSeq - 1];
  const settledFinal = order.some(() => true); // final seq is always in order since order == outcomes shuffled, all n delivered
  let expectedStatus, expectedData, expectedError;
  if (finalOutcome.ok) { expectedStatus = 'success'; expectedData = finalOutcome.data; expectedError = null; }
  else { expectedStatus = 'error'; expectedData = null; expectedError = finalOutcome.error; }
  if (s.status !== expectedStatus || s.data !== expectedData || s.error !== expectedError) {
    failures++;
    console.log('FAIL', JSON.stringify({ n, outcomes, order, got: s, expectedStatus, expectedData, expectedError }));
    if (failures > 5) break;
  }
}
console.log(`S-1 fuzz: ${trials} trials, ${failures} failures`);
