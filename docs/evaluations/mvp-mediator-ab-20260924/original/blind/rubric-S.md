1. [critical] Latest request identity, not text equality, governs both success and failure acceptance, including repeated identical text.
2. [critical] Model execution and asserted checks show stale success/failure cannot change newer pending/results; current completion still applies.
3. Reuses the existing binding for execution and ordinary pending/result; identifies only the additional result-acceptance coordination needed.
4. No forced Effect/Atom adoption, custom scheduler or promise that cancellation rolls back server work.
5. Tooltip stays local and unrelated to request policy; UI has one named result-acceptance owner.
6. Memo and model agree, checks are actually run and their limitations stated; no claim of browser/runtime integration coverage.
