## WSL2 Managed Playwright Chrome

On WSL2, a normal `playwright-cli open [URL]` uses **Managed Playwright
Chrome** headless by default: Windows Google Chrome with CDP on
`127.0.0.1:9222` and the dedicated profile
`%LOCALAPPDATA%\aiakos\playwright-cli\chrome-profile`.

- WSL mirrored networking is required. The command fails with remediation
  instead of falling back to a WSL browser.
- `open --headed` uses the same managed Windows Chrome identity in headed mode.
  `PLAYWRIGHT_MCP_HEADLESS=true|1` selects headless and
  `PLAYWRIGHT_MCP_HEADLESS=false|0` selects headed; `--headed` takes precedence.
- Headless and headed modes share the profile and CDP port but cannot run at the
  same time. Close the current managed consumer before changing modes.
- Only one managed CLI session may own the browser at a time. Reuse that
  session name or close it before opening another managed session.
- `open` creates a new tab. It does not navigate an existing Dashboard or
  authentication tab.
- `show` and `show --annotate` require headed mode. If a headless session is
  running, close it, run `open --headed`, then retry `show`. The Dashboard stays
  on `127.0.0.1:9323` until `show --kill`.
- `show --annotate` requires the session that owns the managed lease.
- `delete-data` is refused for a managed session. Reset the dedicated profile
  manually only after closing the session and Dashboard.
- Managed Dogfood Chrome uses the same browser-ownership directory with role
  `dogfood`; Playwright refuses to start while a dogfood run owns the browser.

Explicit `--config`, `--browser`, `--profile`, `--persistent`, `--device`,
or `--mobile` options, browser-shaping `PLAYWRIGHT_MCP_*` environment variables
other than `PLAYWRIGHT_MCP_HEADLESS`, `PWTEST_CLI_GLOBAL_CONFIG`, project
`.playwright/cli.config.json` files are rejected in WSL2 browser-free mode.
Use `playwright-cli attach --cdp=<remote-endpoint>` for an explicit remote CDP
browser. Non-WSL environments retain upstream behavior.

The dedicated profile may reuse authentication that the user established
manually. Authentication is not authorization for payments, production data
changes, or other irreversible actions. Never automate login, import
credentials, or reuse the user's normal Chrome profile. If authentication
expires during a headless session, close it. For manual authentication, use
`open --headed`, close it again, then reopen normally to return to headless.
