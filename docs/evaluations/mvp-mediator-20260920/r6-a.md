# Scenario A: inventory reservation dialog — architecture memo

## Deliverable

### Responsibility map

| Owner | Responsibility |
| --- | --- |
| Reservation use case (Model) | Owns available-stock policy and validates it again when executing `reserve(itemId, quantity)`. It returns the reservation result or a typed expected error; neither panel nor dialog calculates an independent stock-availability rule. |
| `InventoryReservationMediator` | The named UI owner for the reservation dialog. It accepts submit and close/cancel events, assigns an attempt ID, decides which attempt's result may be shown, and coordinates cancellation and retry. It derives enabled/disabled and messages from use-case outcomes plus the active UI attempt. |
| Existing operation binding and Effect execution boundary | Reuses its per-operation pending/outcome state to run the accepted reservation. It receives the attempt ID (or supplies its equivalent result-exclusion token), requests interruption under the Mediator's cancellation decision, preserves the execution/resource lifetime until its completion notification, and returns tagged completion events. Typed expected errors, defects, and interruption stay distinct. Interruption is never treated as confirmation that the server rolled back a reservation. |
| Reservation dialog Passive View | Keeps entered quantity and numeric-format validation locally. It renders Mediator-provided state and sends `Submit`, `Close`, and retry/open events. It does not implement stock policy or cancel execution itself. |
| Two inventory panels | Continue to read the shared Context independently. Both consume the same Mediator state and event entrance; no forwarding component or single connector is needed. Stock-refresh display data remains an independent subscription. |

The existing operation pending/outcome state remains the source for normal execution display. The only added coordination state is the Mediator's logical attempt record: current attempt ID, its UI phase, and retired attempt IDs that still need execution-lifetime completion. It is not a second copy of fetch or reservation state.

### Events and transitions

`n` is a monotonically new UI attempt ID for this dialog/item. A completion is display-applicable only when its ID equals the current attempt ID and the phase still accepts that completion. Retired attempts still deliver their termination/release notification to the execution boundary, but their success and failure outcomes are ignored for UI state.

| Previous state | Event | Next state | Resource owner / effect |
| --- | --- | --- | --- |
| Editing | `Submit(validQuantity)` | Submitting `n` | Mediator allocates `n`; execution boundary starts the use case through the existing binding. The use case rechecks stock. |
| Editing | `Submit(invalidQuantity)` | Editing | View retains its format error; no reservation effect starts. |
| Submitting `n` | `Result(n, success)` | Completed `n` | Mediator adopts the result; the existing binding exposes the outcome. |
| Submitting `n` | `Result(n, expectedError)` | Editing with error | Mediator adopts the typed error as display state; no stock rule is recreated in the View. |
| Submitting `n` | `Result(n, defect)` or `Interrupted(n)` | Editing with the corresponding distinct UI notification | Mediator records the distinct category; execution boundary completes its lifetime handling. |
| Submitting `n` | `Close` | Closed, with `n` retired | Mediator makes cancellation policy explicit and asks the execution boundary to interrupt `n`. It retains `n` until the required release/termination notification arrives. |
| Closed with retired `n` | `Released(n)` | Editing when the dialog is opened again | The binding's one-operation constraint, if any, has been released. A later server success/failure for `n` is stale and cannot be displayed. |
| Editing after cancellation | `Submit(validQuantity)` | Submitting `n + 1` | A new attempt record is allocated. |
| Submitting `n + 1` | `Result(n, success/failure)` | Submitting `n + 1` | Stale result is ignored for display; cleanup for `n` is still processed. |
| Any dialog state | `StockRefresh` | Same dialog state | Background refresh updates stock data through its existing subscription only. It cannot clear, complete, or replace the active attempt. |

The concrete retry policy is therefore: after cancellation has released the existing binding's operation slot, the user may submit the same item again as a new attempt. The previous attempt remains identifiable for cleanup and stale-result exclusion. If the adopted binding already provides equivalent generation/result exclusion, the Mediator uses that mechanism instead of adding another token.

### Behavioral checks

| Check | Expected result |
| --- | --- |
| Submit a numeric quantity when stock is no longer available at execution time | The use case rejects it at execution; the dialog displays the returned expected error without a panel or View stock-policy calculation. |
| Submit attempt `n`, close while pending, then reopen and submit `n + 1` | Close requests interruption for `n`; after the operation slot is released, `n + 1` starts with a different ID. |
| Deliver a delayed success from `n` while `n + 1` is submitting | `n + 1` stays pending and its UI is unchanged; the old completion only contributes required cleanup. |
| Deliver a delayed expected failure or defect from `n` while `n + 1` is submitting | Neither outcome overwrites `n + 1`; expected failure, defect, and interruption remain distinguishable in their applicable attempt. |
| Refresh stock in the background while `n` is submitting | The refreshed stock display may change in both Context consumers, while quantity, active attempt, pending state, and cancellation policy remain intact. |
| Enter non-numeric input, then correct it | The dialog's local format validation blocks only that submit; it does not create a global state or alter either panel's operations. |
| Trigger submit/cancel from either Context consumer | Both events reach `InventoryReservationMediator`, producing the same transition and no View-to-View direct control. |

## Frozen checklist achievement

| # | Achievement | Assessment | Reason |
| --- | --- | --- | --- |
| 1 | Use case owns and rechecks stock policy; display adds no second rule | ○ | Responsibility map and first behavioral check assign both policy and execution-time recheck to the reservation use case. |
| 2 | Named UI owner handles submit/cancel/result; stale prior same-item success and failure cannot overwrite a new attempt | ○ | `InventoryReservationMediator`, attempt IDs, retired-attempt handling, and tagged-result transitions exclude both stale success and failure. |
| 3 | Effect execution/interruption/lifetime delegated; errors, defects, interruption distinguished; interruption is not rollback | ○ | Execution boundary owns run/interruption/release and returns distinct completion categories; the memo explicitly rejects rollback inference. |
| 4 | Multiple Context consumers and local quantity/format remain; no mandatory forwarding components | ○ | Two panels independently consume shared Context, while the dialog owns local input/format validation. |
| 5 | Existing operation state reused; only cancellation/attempt coordination added | ○ | Pending/outcome stays in the existing binding; the Mediator records only logical attempt and release coordination. |
| 6 | Concrete event/transition checks include background refresh during submission | ○ | Transition table and behavioral checks define `StockRefresh` as state-preserving during submission. |

## Trace

Understanding / Planning / Execution / Formatting: OK. Scenario A's React + Effect condition required the skill reference; the memo uses its existing-binding, tagged-result, and execution-boundary guidance without selecting APIs, packages, or framework code.

## Unclear points

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| The binding's exact cancellation acknowledgement and result-correlation interface is unspecified. | The scenario states only that it exposes per-operation pending/outcome state. | Inspect the adopted binding before implementation. Reuse its generation/exclusion facility when it proves equivalent; otherwise pass and return a Mediator-owned attempt ID at the execution boundary. |
| The exact post-close UI (remain closed or immediately return to an editable dialog) is unspecified. | The requirement fixes cancellation semantics, not presentation after close. | Keep the cancellation and release transitions unchanged; select the presentation state from the product's dialog convention. Do not permit a new operation until the binding's applicable slot is released. |

## Discretionary fill-ins

- Assumption: a new same-item submission is enabled after cancellation has released the existing operation slot; this respects a possible one-outstanding-operation binding without inventing concurrent scheduling.
- Assumption: stock refresh is display data only. A changed stock value is enforced by the use case when the reservation executes, and never resets the active dialog flow.

## Retries

0
