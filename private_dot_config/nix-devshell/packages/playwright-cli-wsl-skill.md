## WSL2 Managed Playwright Chrome

On WSL2, a normal `playwright-cli open [URL]` uses **Managed Playwright Chrome** headless by default, using a persistent profile and allocated loopback CDP endpoint for the physical worktree root. Different worktrees have different browser identities. Subdirectories of the same worktree share its identity.

- WSL mirrored networking is required; no WSL browser fallback is installed.
- `PLAYWRIGHT_MCP_HEADLESS=true|1` explicitly selects headless mode.
- `open --headed` and `PLAYWRIGHT_MCP_HEADLESS=false|0` select headed mode. Background tasks use headless, never OS input, foreground activation or automatic login / Dashboard display. A visible browser is a human-initiated operation.
- One CLI session owns each worktree browser. The same identity cannot be headless and headed simultaneously; conflicts preserve the current consumer. Different worktrees, attachment requests and Dogfood runs may proceed concurrently.
- `open` creates a new tab and never navigates another consumer's tab.
- `show` and `show --annotate` require headed mode and use the worktree's allocated Dashboard port. Annotation requires the lease-owning session. `show --kill` requires the session that started that Dashboard and stops only that Dashboard. Do not change mode automatically to satisfy a background task.
- Use `-s=<owner> close`; `close-all` and `kill-all` are refused. `delete-data` is refused for a managed session. After stopping that identity's session and Dashboard and releasing its owner, explicitly use `reset-profile --confirm-identity <identity>` to reset only that worktree profile. The shared authentication profile is never a reset target.
- `managed-chrome-owner locate --role playwright --workspace <physical-root>` prints identity, profile, CDP endpoint and Dashboard port, separated by tabs. `status` lists active records; use `--identity <identity> status` or `recover` for one browser. Recovery releases only confirmed stopped browsers, never profiles. A live or uncertain startup remains reserved; do not delete its record.
- Upgrade the package and Dogfood skill together after closing old consumers with the old package. Legacy global owner records and runtime leases block migration.
- PR evidence uses `browser-attachments upload`, not the worktree browser. For human authentication outside `to-pr`, run `browser-attachments auth`, log in in the dedicated window, then `browser-attachments close`. Uploads reopen headless with that profile. Never copy authentication or use a normal browsing profile.

Explicit `--config`, `--browser`, `--profile`, `--persistent`, `--device`, or `--mobile` options, browser-shaping `PLAYWRIGHT_MCP_*` environment variables other than `PLAYWRIGHT_MCP_HEADLESS`, `PWTEST_CLI_GLOBAL_CONFIG`, project `.playwright/cli.config.json` files are rejected in WSL2 browser-free mode. Use `playwright-cli attach --cdp=<remote-endpoint>` for an explicit remote CDP browser. Non-WSL environments retain upstream behavior.

The dedicated profile may reuse authentication that the user established manually. Authentication is not authorization for payments, production data changes, or other irreversible actions. Never automate login, import credentials, or reuse the user's normal Chrome profile. If authentication expires during a headless session, close it. For manual authentication, use `open --headed`, close it again, then reopen normally to return to headless.
