# Native task-window validation — 0.3.0 (5)

`jev-native --gui` opens a native AppKit goal-entry/run window. It shares app selection, credential resolution, execution and reports with the CLI. It does not start automation or import clipboard contents on launch. CLI without arguments still prints help.

## Implementation

The task window provides a multiline goal, optional literal text, automatic/native-list app selection, target preview and Codex text/vision options, Run/Stop, status and a report location. A native sheet supports name/bundle search, multiple apps, add/remove and explicit workflow ordering. GUI selection never reads stdin. Missing credentials produce a report and GUI instructions; clipboard import is an explicit action through the existing atomic credential writer.

One RunSession owns the active operation. Controls lock during execution and unlock on completion/cancellation. Stop is cooperative: after an in-flight app-selection/action decision or delegate returns, the workflow checks cancellation before native input. Fresh-observation cancellation is also checked before execution. An already executing native operation can finish. The existing preview Stop/quit actions feed the GUI session as well. Closing the goal window requests a stop and hides it; quitting an active GUI waits for a cancellation report. Reopening the running app restores the goal window. Preview capture stops at run completion and can restart for another run.

## Tests and packaged app

- **42 Swift tests pass**, zero failures: the prior 35 plus seven new groups covering GUI options, duplicate-run prevention/reset, post-selection cancellation/report, missing-key non-prompt behavior, native selection without TTY with ordered IDs and revalidation, cancellation during an app-selection API call with preserved provenance, and cancellation after a decision/fresh observation before any input.
- Final public and installed release builds have no compiler warnings/errors. The installed changed source matches the public source; the original/public skill-template lookup distinction is preserved.
- Nine app/archive checks pass: help, doctor, existing-key setup, both-host isolated installation/repeat behavior, raw SwiftPM installation outside the checkout, Calculator observation, strict signature verification, ZIP CRC/extracted signature and relocated help/bundled installation. Credential bytes remain unchanged.
- Explicit CLI Calculator regression returns `verified_complete`, with zero app-selection calls. The actual PTY `--simple` selection returns `verified_complete`; cancel, EOF, invalid number and absent TTY exit 2 with zero automation steps.
- The installed Codex skill is still a real directory and passes structural validation. The packaged skill matches its source. Fresh host discovery is not inferred from file installation.

## Actual native window and execution

The native window was opened and inspected through native accessibility and screenshots. Multiline entry and normal paste worked. Input controls and Run were disabled while active; Stop was enabled. Status and the saved report path were visible afterward.

The native app sheet was used to search the owned fixture, add it, add Calculator, move Calculator before the fixture, then remove Calculator before execution. This verifies multiple selection and ordering in the UI; it does not claim a multi-app native task was executed. Only the owned fixture remained when Use Selected Apps started the run.

The GUI selected and launched the owned JEV GUI Fixture and scrolled its canvas. The report was `jev_observed_complete`. Native AX independently showed `drags=0, scroll=-5.0, x=40, y=40`. A later long scroll goal was stopped through the actual Stop button. The report was `cancelled`; the final observed canvas was `scroll=-20.0`, well short of the requested -500. The last decision had no executed action. A subsequent automatic Calculator run in the same window completed as `jev_observed_complete`, showing that cancellation did not leave the session locked.

The final installed app was also launched with a pre-filled goal and `--no-preview`. It showed Ready without automatically starting. A named nonexistent app produced a short GUI-specific unavailable message and no native steps. Revising the goal to verify Calculator's existing `42 %` value completed as `jev_observed_complete`; the report and AX value were inspected. Calculator data was not changed.

Closing the goal window left the separate target preview visible. Opening the already-running app bundle from Finder restored the goal window, its text and the last result. This exercises the application reopen path used by Dock reopening; a direct Dock click was not independently verified because the native Dock inspection timed out. The temporary Finder window was closed after this check.

## Evidence boundaries

An initial automatic fixture selection stopped at scope probability 0.80, below the unchanged 0.85 threshold. It executed no native steps. The native list provided an explicit scope for the successful fixture run. GUI completion is semantic (`jev_observed_complete`); no deterministic GUI postcondition control was added. The CLI retains explicit postconditions and produced `verified_complete` in regression checks.

Missing-key import and no-TTY behavior use injected credential/runner tests and the existing credential tests. The live GUI had an existing key, so its import button was disabled and key-management/import actions were not clicked. No credential file was changed for UI validation. Normal goal paste used the native tool's clipboard-restoring path; clipboard contents were not inspected or published. GUI Codex delegation and quitting while a real delegate is in flight were not exercised; delegate behavior is preserved, with cancellation checked before applying returned content/proposals. Stop may wait for that in-flight operation.

SourceKit reported no diagnostics for GoalWindow, TaskRunner, Models and AppResolution. A cached public-workspace Workflow query referenced an obsolete RunReport initializer and missing cross-file types despite passing compiler builds/tests. The identical Workflow in the freshly queried original workspace returned no diagnostics. Compiler build/test results are the acceptance evidence; the stale public LSP result is not described as a clean check.

Raw app inventories, reports, requests, AX trees, screenshots and unrelated Finder context remain private local evidence. Public derived summaries are `checks/gui-runtime-summary.json`, `checks/gui-cli-picker.json` and `checks/gui-cli-regression.json`. Build/test/artifact records use the `gui-` prefix. Earlier evidence remains historical. Native window inspection preceded the final small preview-stop callback linkage; the final callback code was rebuilt, passed the same regression suite and archive checks, but the preview status-menu Stop item was not separately clicked afterward.

The current bundle is ad-hoc signed arm64, not notarized. Fresh TCC/Gatekeeper contexts, other OS versions and headless GUI operation remain outside this validation. Existing native input and Codex limitations remain documented.
