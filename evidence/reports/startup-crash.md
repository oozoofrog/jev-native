# JEV Native startup crash diagnosis and patch

Date: 2026-10-10 KST. Project: `/path/to/jev-native`.

The installed CLI was rebuilt as **0.1.1 (2)**. Pure CLI commands no longer initialize `NSApplication`. Native preview functionality remains available and passed an actual GUI runtime check. The original macOS registration abort was not reproduced, so its underlying LaunchServices failure remains unresolved.

## Incident and causal certainty

Incident `REDACTED-LOCAL-ID` occurred at 01:55:40.2626 +0900, approximately 249 ms after launch. The main thread aborted in HIServices `RegisterApplication`, through AppKit initialization and `NSApplication.shared`, at the old `CLI.swift:16`. Another thread was constructing a LaunchServices error during local database access. The report supplies no exact LaunchServices error code or failed command arguments. It does not establish a TCC cause, corrupted database, or intrinsically unsafe `NSApplication.shared`.

The incident executable UUID `REDACTED-LOCAL-ID` matched the prepatch installed binary. The crash occurred after the 01:44 installed build and the subsequent speed test. The earlier suggestion that it preceded the setup/install changes and benchmark was incorrect. A bounded invocation of the prepatch `help` command completed normally. The incident-time unified-log query returned no supporting entries. Exact launch conditions and OS registration failure were not reproduced.

## Patch

- `CLI.main` selects a startup mode before creating AppKit application state. Help, setup without a UI action, skill installation, doctor, and file-based Codex delegation no longer create `NSApplication`.
- `Native` is created only for commands that use it. Pure help/setup/install commands no longer eagerly construct the automation backend.
- Preview and virtual-pointer paths retain the AppKit application event loop. Observation and input without those panels use the async CLI path.
- `Startup.swift` checks graphical-session access with public Security APIs and performs a public, read-only LaunchServices lookup before native UI startup. Detectable failures return actionable stderr. A successful preflight does not guarantee that a later AppKit registration cannot abort.
- Clipboard import and browser opening check graphical-service availability at the point of use. Existing-key setup returns before any clipboard read. Credential precedence and atomic file installation remain unchanged.
- `--no-preview --keep-open` does not retain a nonexistent preview. Incomplete runs still return exit 2.
- The bundle version is 0.1.1 (2), UUID `REDACTED-LOCAL-ID`. The existing installed symlink resolves to this rebuilt app.

## Verification

| Evidence | Result | Scope |
|---|---|---|
| `build.log` | Release app build and signing passed; no compiler warnings/errors | Current source and installed bundle |
| `tests.log` | 27 Swift tests passed | Includes startup routing, graphical-session errors, existing credential/install/state regressions |
| `smoke-final.json` | Installed help, doctor, setup, install-skill all exit 0 | Current Codex child launch context; existing skill reused |
| `smoke-final.json` | Credential bytes unchanged, checked internally | No credential or digest was printed |
| `calculator-observation/`, `calculator-final/` | Real Calculator AX/window capture succeeded without NSApplication startup | Final display remained 42%; foreground returned to Codex |
| `preview-run/report.json` | JEV selected done; `verified_complete` for existing display 42 | No input action executed; JEV model jev-1.13.0, API 209.19 ms |
| `preview-observation-final/window-REDACTED.png` | Actual 320-by-269 preview window captured and visually inspected | Shows Calculator 42% and Finished: verified_complete |
| `smoke.json` headless probe rows | Test unavailable: SessionCreate returned 100001, probe exit 77 | Tested binary was not launched by these rows; no headless runtime pass claimed |
| `swift-diagnostics.json` | SourceKit reports unresolved new Startup.swift declarations in CLI/CredentialSetup; Startup.swift itself has no diagnostics | Editor workspace state appears stale; actual Swift test/release compilation succeeds. No clean LSP claim |

An initial detached preview launch disappeared before producing report/output; no completion was inferred from it. A subsequent foreground tool-managed process produced the runtime evidence above. That owned process (PID REDACTED) was terminated after capture. The earlier unrelated preview process was not terminated. During preview launch the controller became foreground; this check does not certify focus preservation at application startup. After termination, observed foreground was Codex.

## Remaining limits

This change removes unnecessary application registration from pure command paths and diagnoses detectable GUI/service blockers. It does not establish that every LaunchServices registration abort is fixed. Native GUI runtime was verified only in the current macOS 27.0.1 arm64 Codex launch context. Headless, fresh Terminal/Finder, and alternative sandbox/session contexts remain unverified. Existing private window-event routing limits are unchanged; no private application-registration workaround was added.

No system database reset, backup, credential change, commit, or push was performed. Detailed artifacts are under `evidence/startup-crash/`. Source changes are in `CLI.swift`, `Startup.swift`, `CredentialSetup.swift`, `Scripts/build.sh`, `StartupTests.swift`, and `README.md`.


---
Public export note: local paths, incident identifiers and process identifiers were sanitized. Historical raw artifact names refer to the retained private validation corpus. Only the reviewed public subset in [the evidence index](../README.md) is included here. This report records its original check scope; later public packaging checks are recorded separately in PUBLICATION.md.
