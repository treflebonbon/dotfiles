# Blind grading: Task S and Task F

Grader ran `node model.mjs` in every S-* directory (all exited 0, output matched
each memo's claimed transcript verbatim) and additionally wrote independent
2000-trial randomized fuzz tests against each model's exported reducer
(`grader-scratch/fuzz-s{1,2,3}.mjs`, and `fuzz-s4b.mjs` against a copy of S-4's
model with an added `export` statement, since S-4's original file exports
nothing). All four S models: **0 failures out of 2000 randomized overlapping/
out-of-order trials each** — no correctness defect found in any of the four
by direct execution, independent of their self-reported results.

Critical items per rubric: S items 1–2, F items 1–2. A submission "succeeds"
only if both its critical items score full (1).

## Summary table

| Submission | 1 | 2 | 3 | 4 | 5 | 6 | Total/6 | Success | Over-eng. count |
|---|---|---|---|---|---|---|---|---|---|
| S-1 | 1 | 1 | 1 | 1 | 1 | 0.5 | 5.5 | Yes | 0 |
| S-2 | 1 | 1 | 1 | 1 | 1 | 1 | 6 | Yes | 1 (borderline/justified) |
| S-3 | 1 | 1 | 1 | 1 | 1 | 1 | 6 | Yes | 3 |
| S-4 | 1 | 1 | 1 | 1 | 1 | 1 | 6 | Yes | 1 |
| F-1 | 1 | 1 | 1 | 1 | 1 | 1 | 6 | Yes | 1 |
| F-2 | 1 | 1 | 1 | 1 | 1 | 0.5 | 5.5 | Yes | 1 |
| F-3 | 1 | 1 | 1 | 1 | 1 | 1 | 6 | Yes | 0 |
| F-4 | 1 | 1 | 1 | 1 | 1 | 1 | 6 | Yes | 0 |

All 8 submissions succeed (both critical items full in every case). No
submission contains a demonstrated logic/correctness defect; differentiation
is entirely on rubric items 3–6, over-engineering, and engineering judgment.

---

## Task S detail

### S-1

| # | Score | Evidence |
|---|---|---|
| 1 | 1 | `model.mjs` L39-46: `SEARCH` mints `seq = state.seq+1` with no text parameter at all — identity is purely the counter, never text; memo L27-29 states this explicitly as "the fix." |
| 2 | 1 | `model.mjs` L143-190 `exhaustive arrival order`: generates all 6 permutations of 3 settle events × 2 outcome-assignments, asserts `pending` tracks only seq-3 and final status always equals seq-3's outcome regardless of arrival order. Ran `node model.mjs` myself: exits 0, all 5 "ok -" lines print, matching memo L74-79 verbatim. |
| 3 | 1 | memo L13-16, L36-38: "Query (React Query / TanStack Query) is kept as-is... What's missing... is the display gate." Table names Query as unmodified. |
| 4 | 1 | memo L44, model.mjs L48-53: `CANCEL` is a documented no-op; no Effect/Atom, no scheduler, no rollback claim anywhere. |
| 5 | 1 | memo L39, L58 (case 4); model.mjs `TOOLTIP_OPEN/CLOSE` never touch `seq`/`data`; one named owner, "Display gate." |
| 6 | 0.5 | Memo/model agree and the run transcript (memo L73-80) matches actual `node model.mjs` output exactly (verified). But unlike S-2/S-3/S-4, there is no explicit "out of scope / not verified" section anywhere in the memo or model comments stating what integration/browser behavior was *not* checked — the closest is the "Scope" note in model.mjs L1-8, which describes what the model covers, not what remains unverified. Partial credit for missing the explicit limitations statement. |

(a) Over-engineering: none found — the reducer omits query text entirely as a deliberate, stated simplification (not an addition).
(b) Correctness defect: none (2000-trial fuzz, 0 failures). Minor hygiene note: `model.mjs` has no `import.meta.url` main-guard, so importing it as a module runs the entire self-check immediately (console output as a side effect of import) — a style nit, not a logic bug.
(c) Memo length: 82 lines.
(d) A senior frontend engineer would likely rate this the cleanest of the four: shortest memo, no framework jargon, and the auto-generated exhaustive-permutation check is a genuinely clever, low-code way to get strong ordering coverage without a property-testing library.

### S-2

| # | Score | Evidence |
|---|---|---|
| 1 | 1 | memo L27-29: "identity is a monotonically increasing `generation`... regardless of whether its text repeats an earlier search." model.mjs L28-36 `SUBMIT` never reads text into identity. |
| 2 | 1 | memo "Mutation check" (#6, L61-65) plus model.mjs L172-193: reduce with the generation guard *deleted* is shown to regress to the stale/wrong result — proves the check is load-bearing, not incidental. Ran it myself: `node model.mjs` prints the mutation-check line and "all checks passed", exit 0, matching memo L78-81. Fuzz test (2000 trials) also 0 failures. |
| 3 | 1 | memo L13-22: "Query (unchanged)" row explicitly retains fetch/retry/cache/abort; "Generation gate (new, thin)" is the only addition. |
| 4 | 1 | memo L34-36, L51-56: CANCEL modeled as a no-op; no Effect, no scheduler, no claim that abort proves the server stopped. |
| 5 | 1 | memo L59-60 (case 5); model.mjs `TOOLTIP_*` independent of `currentGeneration`/`displayed`. |
| 6 | 1 | memo "Out of scope for this model" (L70-73) explicitly lists what is *not* covered (network execution, retry/backoff, cache-key design, debounce timing); run transcript (L78-81) matches actual output; no claim of browser/integration coverage anywhere. |

(a) Over-engineering: `shouldCancel(prevKey, nextKey)` (model.mjs L73-80) is one extra function not literally demanded by the rubric text, but it's directly justified by a real subtlety the task raises (best-effort cancellation) — cancelling a same-key in-flight fetch on re-entry would abort the request you want to keep. Borderline but defensible, not gratuitous — counted as 1 for the count column but not treated as a quality deduction.
(b) Correctness defect: none (fuzz 2000/2000 passed; mutation test independently confirms the guard is load-bearing).
(c) Memo length: 82 lines.
(d) Of the four S submissions, a senior engineer would likely rate this the technically strongest: the mutation test (disable the guard, watch tests fail) is exactly the kind of self-skepticism a reviewer wants to see, and the same-key cancellation insight shows real protocol understanding beyond the literal ask.

### S-3

| # | Score | Evidence |
|---|---|---|
| 1 | 1 | memo §6 event `search(query)` always issues a fresh id (model.mjs `transition` L39-53); `repeatedTextReentry` case (memo L81, model.mjs L204-224) proves id0/id2 both "cat" are not conflated. |
| 2 | 1 | `staleResolution`, `newestFirstThenStaleFailure`, `bestEffortCancelStillArrives` cases (memo §7-8, model.mjs L157-238). Ran `node model.mjs`: 8/8 PASS, output matches memo L92-102 exactly. Fuzz test (2000 trials, random overlap count 2-5, random arrival order) also 0 failures. |
| 3 | 1 | memo §1, §4: "実行層＝Query 自体... 温存し、新設しない"; only `latestId` is the added state (§5 table). |
| 4 | 1 | memo §2, §6: cancel is explicitly "best effort... 停止の証明にはならない"; no Effect/Atom/scheduler introduced. |
| 5 | 1 | memo §4 (View row), `tooltipIndependence` case (model.mjs L262-275): tooltip toggling never touches `bindingState`/`latestId` and vice versa. |
| 6 | 1 | §11 "未実行・未確認の範囲" is unusually candid: it explicitly names a real blind spot in its own green self-check (the model's id-keyed `bindingState` cannot detect the hazard of a real Query implementation that keys its cache by *text* instead of by request id) — a genuine, self-identified limitation, not just boilerplate. Transcript (§8) matches actual `node model.mjs` output. |

(a) Over-engineering: the memo introduces meta-verification-of-the-memo sections (§9 "ケースと操作列の対応確認", §10 "状態表の照合") that re-check the memo's own internal consistency rather than the system under design — documentation ceremony, not functional scope creep. The `step()` helper (model.mjs L104-114) wraps *every* `transition` call in an input-invariance + double-call-determinism check, which is stronger purity/idempotency testing than the rubric or prompt asked for. The 5-column "state description" table (§5) is heavier formalism than S-1/S-2 use for an equivalent (and functionally identical) design.
(b) Correctness defect: none (8/8 self-check + 2000-trial fuzz, 0 failures).
(c) Memo length: 145 lines — longest of all eight submissions.
(d) A senior engineer would likely respect the honesty (§11's self-identified gap is a genuinely good catch) but find the memo's process apparatus — Mediator/View/Model role tables, dual cross-referencing sections — heavier than the problem warrants for what is, underneath, the same one-field (`latestId`) design as S-1/S-2/S-4.

### S-4

| # | Score | Evidence |
|---|---|---|
| 1 | 1 | memo "操作方針" L20-21: "同じテキストの再入力…毎回新しい論理リクエストとして扱う"; `caseReentrySameText` (model.mjs L152-179) proves it. |
| 2 | 1 | `caseOutOfOrderStale` (memo L45, model.mjs L181-209) plus explicit purity-check block on the stale completion. Ran `node model.mjs`: 5/5 ok, matches memo L69-76 exactly. Fuzz test (copy with added `export`, 2000 trials) — 0 failures. |
| 3 | 1 | memo "責務の所有者" table: "実行層（TanStack Query）" retains fetch/abort/release; only Mediator's `acceptedId`/`adopted` are new. |
| 4 | 1 | memo L21: "中断指示を送るが、その旧リクエストを『終了済み』として扱わない"; no Effect/Atom/scheduler. |
| 5 | 1 | `caseTooltipIndependence` (model.mjs L211-230): tooltip toggle leaves `nextId/pending/acceptedId/adopted` untouched and vice versa. |
| 6 | 1 | "未確認・未実行の範囲" section (memo L95-100) lists concrete unverified items (real binding wiring, actual abort call, real app integration); transcript matches actual run. |

(a) Over-engineering: shares S-3's `Mediator`/5-column-table formalism but without S-3's extra meta-cross-referencing sections — noticeably leaner. `cloneState`/`toPlain` snapshot helpers (model.mjs L24-32, L94-105) exist purely to support verification and are reasonably sized for that purpose.
(b) Correctness defect: none. One portability note: `model.mjs` exports nothing (`grep -n "^export"` → no match), so it can only be run as a script, not imported/reused as a module — the grader had to append an `export` statement to a copy to fuzz it independently. Not a rubric violation (no API was prescribed) but a minor practical limitation relative to S-1/S-2/S-3, which all export their reducer.
(c) Memo length: 105 lines.
(d) A senior engineer would likely find this the best-balanced of the two Japanese/Mediator-style submissions (S-3, S-4): same correctness and honesty about scope, less ceremony — though the non-exported model is a small practical minus.

---

## Task F detail

### F-1

| # | Score | Evidence |
|---|---|---|
| 1 | 1 | §1: "二重送信抑止と古い結果の除外はこの binding が既に保証し...本メモではこの機構自体を再検証しない"; §2: "新しい `isSubmitting` フラグや操作 ID を追加しない". |
| 2 | 1 | §1 L8: "両者を裁定する共通の親（Mediator／CoR）は不要" — explicitly names and rejects exactly the patterns the rubric forbids. |
| 3 | 1 | §2 tooltip bullet: local `useState`, "Context には置かない"; cases C/D/E/I test independence both ways; case F/G explicitly preserve the form's format-check vs. business-validation split. |
| 4 | 1 | §1: business validation stays in the use case; §6 "除外した境界" cites the task's given guarantee ("タスク前提として『既に保証・テスト済み』とされているため") rather than treating Atom-as-implementation as the guarantee. |
| 5 | 1 | §4 (9 concrete cases: normal submit, retry-after-failure, retry-after-success, tooltip non-interference both directions, format-error gating, business-error display, multi-consumer parity, tooltip persistence across re-render) + §5 explicitly marks every row "検査未実装" (not executed) — no overclaim of passing/integration coverage; §7 reiterates no app/model was built. |
| 6 | 1 | §6 ties each excluded concern to the task's stated constraints (no new exclusivity/cancellation policy because flows don't conflict; dedupe/staleness already guaranteed); never proposes a uniform relay or forced subscription move. |

(a) Over-engineering: the "根拠表" in §5 restates all 9 cases from §4 solely to mark them "検査未実装" again — a redundant table (documentation duplication), not an architecture addition.
(b) Correctness defect: none found (memo-only submission, no executable claims to falsify); the flagged uncertainty about whether the real `AsyncResult`'s "waiting" is a co-occurring flag vs. an exclusive tag (§7) is an honest, well-targeted unresolved question rather than a defect.
(c) Memo length: 74 lines.
(d) A senior engineer would likely value the precision and honesty (explicit "検査未実装" per case, explicit "Mediator/CoR not needed" callout) but find the memo longer and more table-heavy than the two-item ask strictly requires.

### F-2

| # | Score | Evidence |
|---|---|---|
| 1 | 1 | "送信中表示は既存 binding からの導出のみにする"; "個々の View が独自の `isSubmitting` ローカル状態や、別の操作 ID を持たない". |
| 2 | 1 | Opening line: "新しい Mediator・状態機械を追加する変更ではない" — near-verbatim match to the rubric's forbidden-pattern list. |
| 3 | 1 | tooltip kept in local `useState`, never influences submit/cancel; multi-consumer case in the confirmation table; form validation left untouched (§3 bullet). |
| 4 | 1 | "業務検証・入力形式チェックには手を入れない"; guarantee is grounded in "既存 binding が既に保証し、テスト済み" (the task's given premise), not "because it's an Atom." |
| 5 | 1 | Confirmation-case table marks every row "検査未実装" — no overclaim of execution/integration coverage. |
| 6 | 0.5 | Operational policy #1 proposes routing *all* consumers through a new named "共通の導出関数（例: `selectSubmitDisplay(bindingState)`）" so that "複数 consumer が同じ判断を同じ所有者から受け取ることを揃える." This is a new relay/derivation layer imposed uniformly across consumers for consistency — precisely the shape of thing rubric item 6 asks not to require, even though it is not phrased in "strict Passive View" terms and is only one function, not a class/store. Partial credit: the intent (single source of truth) is sound, but a mandated shared selector is an addition beyond simply "read the existing binding directly," which F-1/F-3/F-4 avoid entirely. |

(a) Over-engineering: the proposed `selectSubmitDisplay(bindingState)` central derivation function — an indirection layer not present in the other three submissions, introduced for consistency but not strictly required (each consumer could read the binding directly, as F-1/F-3/F-4 do).
(b) Correctness defect: none found.
(c) Memo length: 54 lines — shortest of the four F submissions.
(d) A senior engineer would likely appreciate the brevity and the near-literal echo of "no new Mediator/state machine," but would probably push back in review on the new shared selector function as an unrequested abstraction for what could be a direct read.

### F-3

| # | Score | Evidence |
|---|---|---|
| 1 | 1 | "送信中表示は binding の `pending` をそのまま使う。派生 state・新しい atom・新しい Context を作らない." |
| 2 | 1 | Never introduces any Mediator/CoR/state-machine/operation-id; item 5 explicitly forbids adding new exclusivity/cancellation logic, leaving the existing owner in place. |
| 3 | 1 | Tooltip fully local (`useState`/native `<details>`/popover), decoupled from submit Context; multi-consumer sync explicit in checklist item 1-2; format vs. business error separation preserved (item 3). |
| 4 | 1 | Business validation untouched (scope-out list); grounds the "don't re-guard" decision explicitly in the task's stated already-tested guarantee ("二重送信抑止ロジック本体... は既存で保証済みという前提"). |
| 5 | 1 | 12-item checklist (`[ ]` unchecked) covering pending-transition sync across consumers, single live region, subtree-not-remounted, tooltip surviving submit, format vs. business error location — phrased as verification-to-perform, no claim of having run or passed anything. |
| 6 | 1 | Point 1 says consolidate the submitting judgment into "既存 binding の値、または既存の selector" (reuse what's already there) rather than mandating a new relay layer; explicitly rejects adding new Context/atom for the tooltip, adding cancel/abort/lock logic, or unmounting the form subtree. |

(a) Over-engineering: none in the architecture sense. The memo does expand scope beyond the bare two-item ask into accessibility specifics (a single `role="status"` region across consumers to avoid duplicate screen-reader announcements, `Esc`-to-close, `aria-describedby`/`role="tooltip"`, and — notably — that a help trigger must not be visually layered over/inside the disabled submit button because disabled elements don't receive hover/focus events). These are concretely justified, not speculative, but they do go beyond "整える" as literally asked.
(b) Correctness defect: none found; conversely this submission catches a real technical risk the other three miss entirely (help-trigger-over-disabled-button making the tooltip unreachable during submission), and correctly notes `role="status"` already implies `aria-live="polite"` (no need to double up).
(c) Memo length: 58 lines.
(d) A senior frontend engineer would likely prefer this one in practice: it reads as someone who has actually shipped this exact UI pattern before (disabled-button/tooltip interaction, duplicate live-region announcements) rather than someone reasoning from architecture rules alone.

### F-4

| # | Score | Evidence |
|---|---|---|
| 1 | 1 | "既存Contextから`pending`...をそのまま...読むだけにする"; "consumerごとにpendingを別変数へコピーして独自にrender判定しない". |
| 2 | 1 | Explicit scope-out: "binding内部のロジック変更、requestId/世代管理の作り直し、新しいAbort/キャンセルの導入...はスコープ外とする" — directly names and excludes operation-id/state-machine rework. |
| 3 | 1 | Tooltip local (`useState` or native `<details>`/popover); multiple Context consumers addressed in confirmation items 2, 9; format vs. business error separation preserved (item 3, and premise section). |
| 4 | 1 | Business validation stays in the use case (premise); grounds the no-re-guard decision in "既存binding側で既に保証済み・テスト済みという前提を採用し", not in "Atom itself guarantees it." |
| 5 | 1 | 11-item confirmation list phrased as "を確認する" / "を回帰確認する" / "diffで確認する" (method of verification, not a claim of already-passing); explicitly scopes out claiming the binding's own dedupe/staleness guarantees as newly verified. |
| 6 | 1 | Explicitly invokes YAGNI: "遠く離れた複数コンポーネントで開閉状態を共有する要求が今回ない以上、共有state化はYAGNI" — the clearest, most direct rejection of unrequested shared-state/relay machinery among the four F submissions. |

(a) Over-engineering: none found — this is the most minimal of the four, explicitly reasoning each rejected addition back to "not needed for this task."
(b) Correctness defect: none found.
(c) Memo length: 61 lines.
(d) A senior frontend engineer would likely find this the best "diff-sized" version of the four: it makes the same core decisions as F-1/F-3 with the least ceremony and an explicit YAGNI justification for every rejected addition.

---

## Top 3 differentiating observations

1. **Only S-2 proves its own test is load-bearing.** It deliberately deletes the generation guard in a variant reducer and shows scenarios 1-3 flip to the stale/wrong result — a mutation test, not just a passing self-check. S-1/S-3/S-4 all pass green but never demonstrate their assertions would actually catch a regression if the guard were removed.

2. **S-3 is the only submission that names a real gap in its own green self-check.** Its §11 explicitly states that because its model keys state by request id (never by text), it cannot detect the hazard where a real TanStack Query implementation keys its cache by search text — meaning a same-text re-entry could still leak a stale result in the real app even though this model's tests all pass. That's a substantive, self-critical limitation disclosure none of the others make.

3. **F-2 is the only F submission that reintroduces a mild relay layer** (a proposed shared `selectSubmitDisplay(bindingState)` function all consumers must route through) in the name of consistency — precisely the kind of uniform-subscription/relay pattern rubric item 6 says not to require. F-1, F-3, and F-4 all resolve the same "keep multiple consumers in sync" concern by simply having every consumer read the existing binding/Context directly, with no new indirection. Separately, F-3 is the only F submission to catch a genuine implementation bug risk (a help-tooltip trigger overlapping a disabled submit button becomes unreachable via hover/focus) — the kind of detail that most differentiates "senior frontend engineer" judgment from architecturally-correct-but-generic advice.
