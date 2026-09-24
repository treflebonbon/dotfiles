
An existing React/Query screen has a search binding exposing pending/result for each request. Typing issues overlapping searches, including re-entering the same text. Only the newest request's success/failure may update displayed results. A help tooltip is independent. Query cancellation is best effort and does not prove the server stopped. Design the responsibility/event/verification memo and a minimal pure executable model with a self-check (no prescribed model API). Keep Query and its execution facilities; do not introduce Effect. This scenario is not supplied until the plateau check.

1. [critical] Latest request identity, not text equality, governs both success and failure acceptance, including repeated identical text.
2. [critical] Model execution and asserted checks show stale success/failure cannot change newer pending/results; current completion still applies.
3. Reuses the existing binding for execution and ordinary pending/result; identifies only the additional result-acceptance coordination needed.
4. No forced Effect/Atom adoption, custom scheduler or promise that cancellation rolls back server work.
5. Tooltip stays local and unrelated to request policy; UI has one named result-acceptance owner.
6. Memo and model agree, checks are actually run and their limitations stated; no claim of browser/runtime integration coverage.
