# JEV Native Computer Use — delivery evidence

Date: 2026-10-10 KST. Source: `/path/to/jev-native`.

## Delivered

Standalone SwiftPM native macOS CLI, ad-hoc signed `dist/JevNative.app`, and companion Codex skill. Installed symlinks: `~/.local/bin/jev-native` and `~/.codex/skills/jev-native`. No commits, pushes, or backups were made. Fresh Composer skill discovery was not verified.

Runtime automation and JEV requests use direct Swift/Apple frameworks: AppKit, Accessibility, ScreenCaptureKit, CoreGraphics, Vision, CryptoKit, URLSession. Codex CLI is the explicitly permitted external exception for original text and image interpretation. Python, Node, AppleScript, browser automation, and fixture executables are not runtime automation dependencies.

JEV selects typed candidates. Native code validates arguments, target ownership and fresh AX state before execution; pointer actions additionally validate target image SHA-256. Codex returns text or advisory image interpretation/proposals, which JEV receives before subsequent selection. Model choice is not silently overridden: explicit `--codex-model` is supported; otherwise the isolated CLI invocation uses its default.

Supported actions: background launch/openFile, explicit activate, selectWindow, AX press/secondary/focus/setValue/selectText, Unicode type, key, virtual click/doubleClick/rightClick/move/drag/scroll, raise/resize/moveWindow/wait. Target app/window state is separate from actual foreground app. Screenshots can capture independent background windows or all desktop displays. Large AX trees/candidate sets have documented limits.

The separate virtual cursor never warps/restores the physical cursor and never posts mouse events to global HID. A pink pointer marks target coordinates in the preview; optional desktop marker is click-through. Keyboard posting is process-targeted and is not a universal fake-focus implementation.

Default `run` displays a live, nonactivating bottom-corner target preview. Close hides it. Menu-bar toggle and Dock reopen are implemented. Hidden previews pause capture. `--keep-open` retains final/incomplete results; report status remains authoritative. The preview does not forward clicks.

## Build and permissions

- Latest release app build: `bundle-build.log`, passed.
- Latest Swift tests: `tests.log`, 6 tests, 0 failures.
- `doctor-final.json`: Accessibility, Screen Recording, input posting all true for this Codex-launched binary. Private annotation available. macOS 27.0.1 arm64.
- Deployment target macOS 14 is not runtime compatibility evidence. Fresh Terminal/Finder TCC identity was not verified.

## Runtime evidence

| Scenario | Evidence | Result and limit |
|---|---|---|
| JEV Calculator workflow | `background-jev-calculator/report.json` and final step image | `verified_complete`; actual AX controls produced 42. This earlier run used the earlier confidence setting; later checks exercise current configuration. |
| Codex text → JEV → native TextEdit | `textedit-handoff-v4/report.json`, `step-3/window-REDACTED.png` | `verified_complete`; owned fixture contains generated sentence with marker `JEV-NATIVE-731`. AX and screenshot inspected. |
| Codex vision → resumed JEV | `vision-resume/report.json`, `step-0/handoff.json` | Actual screenshot interpretation of current Calculator 42%, then JEV `done`; `verified_complete`. Delegate shell tools disabled. |
| Background virtual Calculator click | `annotated-mouse-click-output.json` | Calculator accepted a digit while another app was foreground. Natural small physical-pointer movement during sampling is not attributed to the controller. |
| Background virtual canvas drag | `fixture-drag-output.json`, `fixture-jev/report.json`, `fixture-events.jsonl` | Owned AppKit fixture received tagged mouse/drag events while inactive. JEV-selected drag ended at canvas x=300,y=128; `verified_complete`. |
| Background virtual canvas scroll | `fixture-scroll-v2-output.json`, `fixture-events.jsonl` | Actual scroll -8, fixture inactive, actual foreground Codex. Physical pointer before/after exactly x=1116.246,y=697.266. |
| Preview close/hide | `preview-hide-retry-output.json` | Selected preview window became null; process stayed alive. |
| Menu-bar reopen | `preview-reopened-final/observation.json` | Earlier runtime toggle restored preview. |
| Dock reopen | `dock-reopen-direct.json`, `preview-dock-final/observation.json`, `window-REDACTED.png` | Native Swift test sent AXPress to the Dock item whose AXURL is this app bundle; return code 0. Hidden panel reappeared. Screenshot visually inspected. Dock activation made the controller foreground as expected. |
| Final delivered surface | `delivered-preview/observation.json` | Preview retained; foreground restored to Codex. Owned fixture process terminated after evidence capture. |

The CLI's separate-observation Dock `act` test stopped on freshness mismatch (`dock-reopen-stderr.log`); Dock contents changed between helper invocations. This failure was retained. Dock callback acceptance was separately established by the single native Swift AX probe `dock-reopen-test.swift`; it is test-only, not a runtime dependency. Dock AX root traversal was added because Dock does not expose ordinary AX windows.

## Measured timing and usage

These are individual local runs, not latency benchmarks. API time includes network plus service time. Local time is serialization/parsing. Action time excludes settling and later observation.

- TextEdit run: four JEV calls, API 180–254 ms, local 0.27–0.55 ms; total JEV input 5,802 tokens, output 947. Native openFile 28.47 ms; native type 17.64 ms. Codex text handoff 6,265 ms.
- Vision/resume: JEV API 247.80 and 197.41 ms, local 0.488 and 0.208 ms; total JEV input 4,195, output 828. Codex vision handoff 6,778.81 ms.
- Actual API replies identify JEV model/version in saved response files. Credentials are loaded at runtime and never printed.

## Material limitations

1. Window-local coordinate routing relies on private SkyLight `SLEventSetWindowLocation` and undocumented CGEvent field 51, isolated in `WindowEvents.swift`. OS changes may break it; this path is not suitable for Mac App Store distribution. `JEV_DISABLE_PRIVATE_EVENTS=1` disables it and coordinate input fails without a global cursor fallback.
2. TextEdit background coordinate dragging did not select text in repeated runtime checks. Native fixture drag/scroll success does not establish universal app acceptance. AX text selection is available separately.
3. Raster image generation/editing is not supplied. Codex vision interpretation and original text are verified.
4. `verified_complete` verifies only supplied predicates plus JEV completion. `expectText` is an AX/OCR substring; `expectApp` matches target, not actual foreground. It is not unspecified E2E certification.
5. Automatic mode currently declines consequential send/purchase/delete/account/security actions. A target allowlist does not authorize every side effect. No such actions were used for validation.
6. Candidate arguments that are not observed/provided cannot be invented by a bare goal. Supply task literals/actions or authorize delegates. No universal Codex computer-use parity is claimed.

Earlier failures and invalid experiments are retained. A successful event post, build, or semantic completion is not substituted for actual app state verification.


---
Public export note: local paths, incident identifiers and process identifiers were sanitized. Historical raw artifact names refer to the retained private validation corpus. Only the reviewed public subset in [the evidence index](../README.md) is included here. This report records its original check scope; later public packaging checks are recorded separately in PUBLICATION.md.
