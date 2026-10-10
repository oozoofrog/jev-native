# App selection validation — 0.2.0 (4)

`run --goal` and task JSON can omit apps. JEV selects real native app identities before the native workflow starts. `--auto` disables the app picker; `--simple` chooses from an interactive list without app-selection API calls. Explicit app scopes retain their previous order and validation.

## Source and build

- 35 Swift tests pass, including six new groups for argument/task modes, app bundle validity/deduplication, typed single/multi-app decisions, uncertainty/unavailability/malformed replies/service failures, explicit bypass, picker cancellation/EOF/non-TTY, provenance and a 601-app catalogue. Large-catalogue tests verify coverage and the per-question option limit. An uncertain shortlist group stops selection instead of silently dropping candidates.
- Final release build has no compiler warnings/errors. SourceKit-LSP reports no diagnostics for the resolver.
- The public app and extracted ZIP pass nine checks: help, doctor, existing key setup, both-host skill installation/repeat behavior, raw SwiftPM installation from another working directory, native Calculator observation, strict signature verification, ZIP CRC/extracted signature and relocated bundled skill installation. Credential bytes are unchanged during these checks.
- The app is ad-hoc signed arm64, not notarized. Fresh TCC/Gatekeeper contexts and other OS versions remain outside this validation.

## Actual JEV and native runtime

An owned app named JEV Selection Fixture was installed and registered in the user Applications folder, with no running process at discovery. JEV inferred its bundle ID from the goal without `--apps`, passed scope verification at 0.85, selected a native launch action, then scrolled the canvas. The final AX value was `drags=0, scroll=-5.0, x=40, y=40`; the final window screenshot visibly showed `Scroll: -5`. The report status was `verified_complete`. This validates selection of an installed app that was not running, launch, native action execution and observed completion in this launch context.

Task JSON with the apps field omitted also completed as `verified_complete` using the default automatic mode. The terminal picker selected the running fixture and completed without app-selection API calls. Cancellation, EOF, invalid input and absent TTY each exited 2 with no automation steps. The explicit Calculator regression completed with source `explicit` and zero app-selection API calls. A goal naming an absent app returned `app_selection_unavailable` before automation.

Calculator app inference passed after the scope question was clarified to judge identities/roles separately from task completion and UI permissions. Some subsequent Calculator action decisions were uncertain and stopped without input. An early scope question produced probabilities 0.82/0.83 and stopped; the clarified question produced 0.95/0.93 in Calculator probes. A later installed-executable fixture verification still produced 0.79 and stopped before execution. The threshold remained 0.85 throughout. These are recorded false-negative/uncertainty limits, not completed native tasks. No repeated identical-state retry or threshold reduction was used to claim success. Calculator retained its observed `42 %` value. A separate installed-CLI goal explicitly checking `42 %` completed as `verified_complete` without `--apps`.

## Evidence boundaries

`checks/app-selection-runtime-summary.json` contains selected identities, statuses, timings, usage and native action kinds. `checks/app-selection-picker.json` records the five terminal cases. The new build/test/artifact logs use the `app-selection-` prefix; prior evidence remains historical.

Raw app catalogues, request/response distributions, AX trees, window captures and local fixture installation paths remain private. Public summaries omit those inventories and paths. The runtime catalogue contained 183 normal app identities before adding the owned fixture. Actual multi-app semantic selection and a real catalogue above the API option limit were not tested; their branching and coverage were checked with injected typed replies. Selection confidence is not a guarantee that every goal will resolve or every downstream native action will succeed. Existing native input and Codex handoff limits remain unchanged.
