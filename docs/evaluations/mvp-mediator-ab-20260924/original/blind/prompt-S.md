
An existing React/Query screen has a search binding exposing pending/result for each request. Typing issues overlapping searches, including re-entering the same text. Only the newest request's success/failure may update displayed results. A help tooltip is independent. Query cancellation is best effort and does not prove the server stopped. Design the responsibility/event/verification memo and a minimal pure executable model with a self-check (no prescribed model API). Keep Query and its execution facilities; do not introduce Effect.

