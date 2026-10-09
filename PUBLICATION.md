# Public export manifest

This repository exports the completed JEV Native 0.1.1 (2) project, including Swift native automation, JEV closed-loop decisions, Codex text/vision handoff, virtual cursor/preview, clipboard credential setup, Codex/Claude Code skill installers and startup crash mitigation.

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

## Public packaging checks

- The public source preserves all completed workflows. One portability change replaces the compiled `#filePath` skill fallback with runtime lookup of bundled resources, executable ancestors and the working directory. Original local source and installed commands remain untouched. Two regression tests cover the new lookup.
- Current public Swift tests: **29 passed**. Current production app build/signing: passed, without compiler warnings/errors. Historical logs remain labeled separately.
- Nine app/artifact checks passed: help, doctor, existing-key setup, both-host installation/repeated installation in isolated destinations, raw SwiftPM installation from outside the checkout, real Calculator observation, strict signature verification, ZIP CRC and relocated bundle installation.
- Current credentials remained unchanged. No browser or account action was performed. Native observation confirmed the existing Calculator display 42; fresh preview/input behavior was not retested because those sources are unchanged and historical runtime evidence is included.
- The public archive contains no local home/volume path strings. Four selected PNGs were visually inspected and ancillary metadata was removed without changing pixels.
- The export and initial Git objects are audited with an in-memory exact-local-secret comparison, token/private-key patterns, private-path/session checks and recursive ZIP inspection before pushing. The targeted scan is not proof against every possible secret encoding.
- No existing Git history is imported. Commit identity uses the account's public GitHub noreply address. No Git tag or GitHub Release is created; the development app archive is tracked in the repository.

The packaging process initially found a compiled local source path. Runtime template lookup removed it. The first added test run failed only because URL equality distinguished a trailing directory slash; path equality corrected the test. Final tests pass. The earlier path-mapping build attempt emitted debug-module reference warnings; the final artifact build removes that approach and passes without those warnings. Full intermediate logs remain local; final sanitized logs are in evidence/checks/.
