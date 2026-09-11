# ROP analysis comparison protocol

The experiment tests whether additional syntax/type evidence improves the meaning of an existing ROP flow model. It does not test human comprehension or tool speed.

Freeze cases, source hashes, gold requirements, extractor code, dependency locks, producer instructions, model/settings and randomized run order before generation. The manifest is the experiment's source of truth. A source or protocol mismatch must stop execution. Do not silently regenerate evidence or replace failed runs.

Use three independent fresh contexts per case/condition. The TypeScript conditions are baseline, ast-grep and ts-morph; Rust adds syn and syn plus rust-analyzer in place of ts-morph. There are 75 producer runs over seven cases. All conditions receive identical source excerpts and report semantics. Only supplemental evidence differs. Producers have no access to gold requirements or other outputs. All input is supplied in the prompt; tool calls invalidate a controlled run.

Store each raw response and JSONL transcript, its normalized flow.json, validation errors, duration and native usage counters. A failed generation counts as a failure, not as a reason to retry. Keep evaluator labels opaque: run ids carry no backend name. Evaluation gets the source, gold requirements and model, not extractor outputs or the condition map. Each requirement is scored with an explanation and graph/source references. Accept equivalent grouping; judge semantic edges, not graph spelling.

For each case/condition report all three observations and their arithmetic means: false assertions, fulfilled requirements, missing requirements, unknown boundaries, critical violations and generation failures. Failure scores have zero fulfilled requirements; do not impute false assertions for missing output. Report failures separately and retain denominators.

A candidate must have zero critical violations across its language's runs, fewer mean false assertions than baseline, at least baseline's mean fulfilled requirements in every case, and no more generation failures. Rank qualifying candidates by fewer false assertions, more fulfilled requirements, then integration burden. At equivalent burden prefer ast-grep. No demonstrated gain means retain baseline; unstable or incomplete evidence means defer adoption. Three repeats are a descriptive comparison, not proof of statistical significance.

The existing renderer checks source ranges, graph connectivity and terminal paths; these checks do not establish semantic correctness. Validate every model mechanically and inspect representative HTML plus candidate output. Do not edit production skill, renderer, global distribution or live chezmoi source as part of this experiment.
