# Public export manifest

This repository exports the JEV Native project (current public source: 0.9.0 (32); historical published app archive: 0.5.0 (7)), including Swift native automation, JEV closed-loop decisions, Codex text/vision handoff, virtual cursor/preview, clipboard credential setup, Codex/Claude Code skill installers and startup crash mitigation.

## Included

- All production Swift source, the owned native fixture, SwiftPM manifest, tests and build script.
- Portable companion skill and host UI metadata.
- User setup, command, permission, behavior and limitation documentation.
- All five project verification/benchmark/crash report categories, sanitized build/test logs, synthetic setup probes, benchmark samples/statistics/task/harness and selected decision/handoff/event summaries.
- Four visually reviewed independent window screenshots with metadata removed.
- A newly built, stripped, ad-hoc signed arm64 app archive without private build paths and checksum metadata under artifacts/.

## Sanitized or excluded

Machine-specific home/volume paths and local incident/process identifiers were removed from public text. Raw app lists, desktop AX/OCR, whole-desktop/Dock screenshots, conversation transcripts, original crash attachment, auth files, credentials and environment dumps are excluded. The public reports explicitly identify selected summaries as sanitized, rather than presenting them as complete raw records.

Build caches, ignored original dist output, transient PIDs, temporary fixture installations and duplicate/intermediate captures are excluded. Local originals remain intact. This export is a separate public checkout, not a backup.

No historical Git repository existed in the owning project. Publication uses a new initial commit after auditing the export; no prior private history is imported. No open-source license is selected. NOTICE.md records provenance and dependency boundaries.

## Initial export packaging checks (historical)

- The public source preserves all completed workflows. One portability change replaces the compiled `#filePath` skill fallback with runtime lookup of bundled resources, executable ancestors and the working directory. This initial export step did not change the original local source or installed commands. Two regression tests cover the new lookup.
- Initial export Swift tests: **29 passed**. Initial export production app build/signing: passed, without compiler warnings/errors. Historical logs remain labeled separately.
- Nine app/artifact checks passed: help, doctor, existing-key setup, both-host installation/repeated installation in isolated destinations, raw SwiftPM installation from outside the checkout, real Calculator observation, strict signature verification, ZIP CRC and relocated bundle installation.
- Current credentials remained unchanged. No browser or account action was performed. Native observation confirmed the existing Calculator display 42; fresh preview/input behavior was not retested because those sources are unchanged and historical runtime evidence is included.
- The public archive contains no local home/volume path strings. Four selected PNGs were visually inspected and ancillary metadata was removed without changing pixels.
- The export and initial Git objects are audited with an in-memory exact-local-secret comparison, token/private-key patterns, private-path/session checks and recursive ZIP inspection before pushing. The targeted scan is not proof against every possible secret encoding.
- No existing Git history is imported. Commit identity uses the account's public GitHub noreply address. No Git tag or GitHub Release is created; the development app archive is tracked in the repository.

The packaging process initially found a compiled local source path. Runtime template lookup removed it. The first added test run failed only because URL equality distinguished a trailing directory slash; path equality corrected the test. Final tests pass. The earlier path-mapping build attempt emitted debug-module reference warnings; the final artifact build removes that approach and passes without those warnings. Full intermediate logs remain local; final sanitized logs are in evidence/checks/.


## Copy correction, 0.3.0 (5)

The companion skill and README no longer include explanatory guarantees about the user's mouse or focus. App UI/help had no such copy. Swift source and tests are unchanged. Technical action constraints and historical verification reports remain intact. Both local and public bundles include the revised skill; the current archive/checksum metadata is updated. The earlier archive remains in Git history. Existing Swift test results are reused; affected bundle/skill/archive checks passed again.

## Version 0.2.0 app selection

Goal-driven app selection and terminal app-list selection are included, with optional task JSON apps, discovery validation, report provenance and six regression test groups (35 total tests). New public evidence is under `evidence/checks/app-selection-*` and `evidence/APP-SELECTION.md`. Raw installed-app catalogues, selection requests, AX state and fixture install paths remain private local evidence. Prior evidence remains historical; the current app archive replaces the prior archive in the working tree. Git history retains published versions.

## Version 0.3.0 native task window

The native goal-entry/run window, shared task runner, ordered native app picker, GUI key setup and cooperative cancellation are included. CLI help/no-argument behavior remains. New validation is in `evidence/GUI.md` and `evidence/checks/gui-*`. Raw app inventories, local report locations and unrelated Finder context are excluded. Prior evidence remains historical.


## AX query engine, 0.4.0 (6)

The local AX query engine, progressive JEV choices and targeted freshness checks are included. Current Swift tests: **61 passed**, zero failures. Final cohort: **query 3/5, legacy 2/5**; JEV reliability remains unresolved. See [AX implementation and benchmarks](evidence/AX-QUERY.md) for current evidence and earlier failures. The separate simulated UI proposal was not installed. Native range reads are verified; notification and scope refresh are verified with the stated causality limit.

Current packaging checks verify the 0.4.0 (6) installed source app, public app and relocated ZIP: strict signature, help, doctor and existing-key setup. Isolated Codex/Claude project installation and repeat installation pass for the public/relocated app. Source synchronization and deliberate packaging differences are verified. Credentials are byte-identical. See `evidence/checks/ax-query-package.json`. Fresh Terminal/Finder/Gatekeeper and host discovery remain unverified.


## Natural-language native UI, 0.5.0 (7)

The Korean single-request AppKit UI, typed request intent, original UTF-16 text spans, actual Codex generation/vision, contextual follow-up/resume, source completeness/identity guards, result-destination separation, cancellation and delegate provenance are included. The explicit CLI/task modes retain their scope and completion contracts. See [implementation and actual workflow evidence](evidence/NATURAL-LANGUAGE-UI.md).

Final Swift suite: 89 passed, zero failures. Generation/native input, selected-document summary without source mutation, and image interpretation/UI delivery have actual owned-fixture evidence. Ordinary-button no-delegate routing is verified, but the final action stopped `uncertain` before input and is not a successful button workflow. Earlier model stops and harness failures are retained in sanitized summaries. No general reliability improvement is claimed.

The 0.5.0 installed/public/relocated package checks, archive hashes and targeted staged/history/ZIP audit are refreshed. Raw app catalogues, private source text, unrelated windows, credentials, local paths and conversation records are excluded. Host loader/Composer and fresh Terminal/Finder/Gatekeeper exposure remain unverified.


## Spatial workshop and readable cartoon rendering, 0.6.3 (11)

The native task window now uses one SceneKit world for source, request, execution core, result and actual event history. Framed document modules, cartoon shading and connected motion retain their shared depth and hit regions. The AppKit goal editor and full-text sheets remain native. TextKit supplies high-resolution glyph planes and matching pagination, with projection-aware sizing, stronger theme contrast, clearer document titles and resize anchoring. The app bundle includes the original vector-rendered JEV icon and its generator.

Typed presentation events reject stale run/sequence updates. Cooperative pause freezes the shared scene clock and waits at execution boundaries; resume retains the same run. Stop releases paused waiters and cancels the active task. Native action preconditions are refreshed after pause, including a pause during fresh observation. History selection inspects recorded events and does not replay actions. Provenance describes the whole source document supplied to the delegate, without sentence-level mapping claims.

Final source verification: **98 Swift tests passed**, zero failures; public release and original debug builds passed without compiler warnings/errors. Readability verification includes **24 native checks**: 18 with synthetic documents rendered by the actual workspace source in light/dark appearances, and six in the development app. These cover full Unicode sheets, native pointer paging, focus movement, idle stability and 760×700 minimum-window bounds. Earlier workshop verification separately exercised a real source-to-summary delegate run. The readability update did not rerun natural-language generation or claim a general reliability improvement. Runtime evidence covers macOS 27.0.1 arm64.

This commit publishes source, tests, icon assets and documentation. It does not update the tracked 0.5.0 app archive, checksum metadata, installed app, Git tags or GitHub Releases. Raw local observations, synthetic fixture captures and verification logs remain outside this public checkout.

## Current source update

The current update publishes production Swift source, tests, the portable product manifest/generator, a development-only bundle builder and documentation. Previously published evidence and archives remain historical. This update adds no app archive, private signing policy, certificate material, local installer/migration scripts, actual run records, conversations, AX captures, screenshots, backups or build caches. Test path fixtures use generic paths; credential strings in redaction tests are deliberately synthetic.

The public manifest uses the containing checkout instead of a developer's absolute source path. Build32 distinguishes this portable identity from the previously deployed build31. The development builder creates a new bundle and never signs, installs, changes command links or modifies a running app. The original machine's source, signed installation and deployment configuration were preserved separately.

Current portable source validation: **216 Swift XCTest tests passed, zero failures**, plus **8 Python product-contract fixture tests passed**. The release executable and fresh bundle were built, and build inputs matched before/after. This validates compilation, tests and bundle metadata; no public build32 GUI, signing, installation or TCC-retention claim is made. Raw local logs are excluded.
