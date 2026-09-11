# ROP analysis comparison

Experimental adapters and a frozen, blinded comparison. These files are under `tests/`, outside the deployed skill. Start in the validated dotfiles task worktree. The protocol and producer/evaluator prompts here define the experiment; the existing report format remains owned by `local-skills/rop-visualizer`.

## Preparation

Use `docs/research/rop-public-inputs.json` for archive URLs and SHA-256. Download those archives to their recorded paths, checking the hashes before extraction. Store paths to rustc, cargo, rust-analyzer and ast-grep, one absolute executable per line, in `tmp/rop-analysis-comparison/preflight/tool-paths.txt`. Node, npm and Codex must be on PATH. Dependencies and artifacts stay in the experiment workspace; no global install or chezmoi apply is needed.

```bash
npm ci --prefix tests/experiments/rop-analysis --ignore-scripts
python3 tests/experiments/rop-analysis/prepare.py
python3 tests/experiments/rop-analysis/prepare-public.py
```

Build `syn-extractor/Cargo.toml` using `cargo build --locked`, with `CARGO_TARGET_DIR` set to the absolute `tmp/rop-analysis-comparison/build` path. Run `cargo check` for each Rust input (`--features unstable-index` for ripgrep) and the ts-morph extractor for each TS input; resolve diagnostics before freezing. The invoice case supplies a signature-only extern boundary through a transparent wrapper. It is checked, never linked or executed. Public snapshots remain unmodified except for experiment config and dependency placement.

## Frozen comparison

```bash
python3 -m unittest discover -s tests/experiments/rop-analysis -p 'test_*.py'
python3 tests/experiments/rop-analysis/experiment.py freeze
python3 tests/experiments/rop-analysis/experiment.py generate --workers 3
python3 tests/experiments/rop-analysis/experiment.py blind
python3 tests/experiments/rop-analysis/evaluate.py review
python3 tests/experiments/rop-analysis/evaluate.py summarize
```

`freeze` computes evidence and locks hashes before any producer sees source. Model and reasoning effort are captured from the current Codex configuration. Each run uses `codex exec --ephemeral --sandbox read-only`; the prompt carries all permitted source and tool use invalidates the controlled run. An interrupted run is retained for inspection, not silently retried. Completed runs can be resumed by `generate`.

Review packets have opaque run ids and omit backend information. Review batches are one fresh context per case. They contain the same source and fixed requirements for all outputs. The deterministic aggregate accepts only complete review coverage. At otherwise equal semantic results, integration burden is ranked ast-grep, then language-specific library, then syn plus a stateful rust-analyzer LSP client.

`summary.json` contains all observations and language-specific adoption gates. Keep raw transcripts and source/model artifacts adjacent. Do not claim that passing the renderer's graph checks establishes semantic correctness. Render representative models using the existing renderer and an authorized Playwright session after review.
