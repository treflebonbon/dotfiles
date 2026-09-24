1. [critical] Executable transitions implement latest intent consistently in every waiting phase, including target changes back to the in-flight target, without duplicate I/O.
2. [critical] Stop and release success are required before the next acquire; failure blocks acquisition and explicit retry repeats only the failed stage.
3. Execution IDs survive intent changes, are fresh for new stages/retries, and stale success/failure cannot advance state.
4. Common UI parent owns policy; Effect owns execution, typed errors/defects/interruption/lifetime. The pure model only emits commands and does not invent a scheduler or runtime.
5. Child local flows and the profile editor remain independent; profile events leave device state/effects unchanged.
6. Model, memo and concrete checks agree; run at least one meaningful assertion-based check and report its actual result, separating executed checks from proposed checks.
