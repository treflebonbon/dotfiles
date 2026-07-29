## WSL2 Managed Playwright Chrome

On WSL2, a normal `playwright-cli open [URL]` uses **Managed Playwright
Chrome**: Windows Google Chrome with CDP on `127.0.0.1:9222` and the dedicated
profile `%LOCALAPPDATA%\aiakos\playwright-cli\chrome-profile`.

- WSL mirrored networking is required. The command fails with remediation
  instead of falling back to a WSL browser.
- Only one managed CLI session may own the browser at a time. Reuse that
  session name or close it before opening another managed session.
- `open` creates a new tab. It does not navigate an existing Dashboard or
  authentication tab.
- `show` keeps a WSL loopback Dashboard on `127.0.0.1:9323` and opens
  `http://localhost:9323/` in the same managed browser. Use `show --kill` to
  stop the Dashboard.
- `show --annotate` requires the session that owns the managed lease.
- `delete-data` is refused for a managed session. Reset the dedicated profile
  manually only after closing the session and Dashboard.

Explicit `--config`, `--browser`, `--profile`, `--persistent`, `--device`,
`--mobile`, or `--headed` options, browser-shaping `PLAYWRIGHT_MCP_*`
environment variables, project `.playwright/cli.config.json` files, and
`attach` retain upstream behavior.

The dedicated profile may reuse authentication that the user established
manually. Authentication is not authorization for payments, production data
changes, or other irreversible actions. Never automate login, import
credentials, or reuse the user's normal Chrome profile.
