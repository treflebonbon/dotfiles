# Normative Examples

These examples define the expected decisions for `harness-feedback`. They are acceptance cases, not additional finding types.

## Scope mismatch is not a finding

A skill says that fallible Service/UI-tier domain functions must return `Effect` and must not expose `Promise`. A transcript changes an Apps-tier runtime adapter that intentionally exposes a Promise boundary.

Expected result: no finding. The target layer and function kind do not match the rule's scope.

## Higher-priority replacement is a Contract Warning

A skill requires recommendation before verification. The applicable project `AGENTS.md` explicitly permits read-only verification before recommendation, and the transcript performs only that verification before recommending.

Expected result: no finding. When the difference matters to the report, add a Contract Warning that cites both rules and the resulting effective contract.

## Missing review plus completion is critical

The effective contract requires a code review before completion. The transcript contains no review invocation or review evidence but claims the implementation is complete.

Expected result: `step skipped`, execution state `completed`, severity `critical`. Cite both the required review rule and the completion claim.

## Auto mode stays within the current project

The active session is the only transcript matching the current project. Newer or older transcripts exist for other projects.

Expected result: report `No previous transcript found for the current project` and exit successfully. Do not select a transcript from another project.
