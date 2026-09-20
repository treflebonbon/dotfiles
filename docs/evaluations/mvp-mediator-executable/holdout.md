# T — bulk selection and background list refresh

Frozen before dispatch, after the verification-evidence wording change. Existing React/Effect document list uses a table library for selected row IDs and a query binding for loaded rows/loading. A background refresh may replace loaded row objects but must not reset selection or silently trigger an archive. An explicit archive click captures the selected IDs at that moment and passes them to the existing archive use case; selection changes after that click must not change the accepted command. The use case owns runtime permission checks. No cancellation, exclusion or retry policy is requested. Produce a short architecture memo and an executable abstract self-check. If you simulate library state, identify the simulation and the state actually added in production. Do not implement React or Effect APIs.

1. [critical] Refresh preserves selection and never implicitly archives; explicit archive uses a snapshot of selected IDs unaffected by later selection changes.
2. [critical] Execution-time permissions belong to the use case, not copied into the UI or replaced by disabled-button logic.
3. Reuses table selection and query binding state; any abstract mock is explicitly distinguished from new production state, with no duplicated selection/query state machine.
4. Uses the existing execution boundary for the accepted command, without adding a scheduler or unrequested cancel/exclusion/retry machinery.
5. Concrete assertions actually execute refresh, archive-click snapshot and subsequent selection change; memo states exactly what ran and what remains untested.
6. Local formatting/display concerns remain local, and one named UI owner routes the archive command without a forced single connector.
