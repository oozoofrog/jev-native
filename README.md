# JEV Native Computer Use

A standalone SwiftPM native macOS controller. Apple AppKit, Accessibility, ScreenCaptureKit, CoreGraphics, Vision, URLSession and CryptoKit implement automation directly. No browser tool, Python/Node bridge, AppleScript or external automation binary is used. Codex CLI is the sole external runtime exception for original text and image interpretation.

Current version: **0.3.0 (5)**. Build with Xcode command-line tools and Swift 6 on macOS. Runtime validation covers macOS 27.0.1 arm64; the macOS 14 deployment target is not a tested compatibility guarantee.

```sh
git clone https://github.com/oozoofrog/jev-native.git
cd jev-native
./Scripts/build.sh
mkdir -p "$HOME/.local/bin"
# Choose an unused command path; do not overwrite an existing installation.
ln -s "$PWD/dist/JevNative.app/Contents/MacOS/jev-native" "$HOME/.local/bin/jev-native"
export PATH="$HOME/.local/bin:$PATH"
```

The build creates an ad-hoc signed `dist/JevNative.app`. The CLI re-execs its canonical app path for AppKit bundle and Dock identity. Keep the checkout/app at the installed path. Run `doctor` and grant macOS Accessibility/Screen Recording permissions for your launch context when needed. The CLI reports consent status; it cannot grant it.

JEV decisions require a TypeSafe API credential and network access. Original text and screenshot interpretation additionally require an installed, authenticated Codex CLI. The native observation/input commands do not require a JEV key. See the [verification evidence](evidence/README.md), [publication manifest](PUBLICATION.md), and [provenance notice](NOTICE.md).

A path-sanitized, ad-hoc signed Apple Silicon app archive is included under [artifacts](artifacts/README.md). It is not Developer ID signed or notarized. Building from source is the verified development path.

```sh
jev-native --gui
jev-native doctor
jev-native setup
jev-native install-skill --host both
jev-native observe --app com.apple.TextEdit --out /tmp/jev-observation
jev-native run --goal 'Calculate 6 times 7 in Calculator' --expect-text 42
jev-native run --auto --goal 'Calculate 6 times 7 in Calculator' --expect-text 42
jev-native run --simple --goal 'Perform the requested task in my selected apps'
jev-native run --goal 'Calculate 6 times 7' --apps com.apple.calculator --expect-text 42
jev-native run --task task.json --out /tmp/jev-task
jev-native act --observation observation.json --action action.json --app com.apple.TextEdit --out /tmp/jev-action
jev-native delegate --prompt 'Describe this image' --image image.png --out /tmp/jev-vision
```

`observe` without `--app` captures the whole desktop, all display geometry, and foreground AX. With an app, it captures the selected independent window even behind another app. `--window ID` selects a returned window. Anonymous process IDs can be addressed as `pid:1234`. Observation distinguishes the actual foreground app from the automation target.

## Install the companion skill

```sh
jev-native install-skill --host codex
jev-native install-skill --host claude
jev-native install-skill --host both
jev-native install-skill --host both --scope project --project /absolute/project
jev-native install-skill --host claude --skills-dir /explicit/skills-directory
```

Claude means local Claude Code. These commands install the companion skill, not the Codex or Claude Code applications. No API credential or model request is needed for installation. The existing `setup` commands remain available for TypeSafe authentication.

Fresh user installs use `~/.agents/skills/jev-native` for Codex and `~/.claude/skills/jev-native` for Claude Code. Project installs use `.agents/skills/jev-native` and `.claude/skills/jev-native` beneath the explicitly selected existing project. `--skills-dir` overrides the skills directory for one host only; custom locations require the host to discover that location separately. It does not change any host configuration.

The previous compatible Codex installation at `~/.codex/skills/jev-native` is reused instead of silently installing a second same-name user skill. The existing symlink is preserved. New installations copy a host-specific `SKILL.md` and bind its native CLI command to the executable which performed installation. The signed app contains its skill template, so installing a skill does not require downloading files or invoking another installer. Keep that executable available; moving it later requires an explicit installation decision. Template discovery uses bundled resources first, then the executable’s checkout ancestors and current working directory; no builder source path is compiled into the production executable.

Repeated installs report `already_installed` when the document matches; extra user files are preserved. A differing document, empty directory, file or dangling symlink is a conflict. There is no force/update mode. Resolve conflicts explicitly. All selected hosts are checked before publication; each new directory is published atomically without replacement. If a concurrent filesystem failure occurs after one host was installed, that host stays installed and the command fails without replacing the conflicting destination. No backups, removals, settings edits or host restarts are performed.

Codex and Claude Code variants retain JEV typed decisions, Swift native automation, credential setup, preview behavior and current input limitations. Claude Code also uses the existing **real Codex CLI subprocess** for original text and image interpretation; Codex must be installed and authenticated separately. This does not install a Claude Desktop, Cowork or cloud integration.

The command reports file installation only. Check host discovery independently before claiming `$jev-native` in Codex or `/jev-native` in Claude Code is available in a fresh session. Current official location references, verified 2026-10-10 KST: [Codex local skills](https://learn.chatgpt.com/docs/build-skills), [Claude Code skills](https://code.claude.com/docs/en/skills).

## API key setup

Credentials retain their existing precedence: nonempty `TYPESAFE_API_KEY`, otherwise nonempty `~/.typesafeai`. Existing credentials skip setup and are not replaced. A failed API authentication does not automatically open a browser or import a different key.

When neither source is configured, an interactive `run` offers setup before creating a preview or starting automation. You can also run `jev-native setup`. Copy only the TypeSafe API key to the macOS pasteboard, then type `import` in the terminal. Do not paste the key into the terminal or chat. Type `open` to open key management, or `cancel` to leave without importing. EOF cancels. Pasteboard text is read only after `import`; the key is never displayed or passed as a command argument.

`jev-native setup --open-keys` explicitly opens [TypeSafe API keys](https://console.typesafe.ai/keys) with `NSWorkspace` and exits. This URL was verified against the [official Quick start dashboard link](https://docs.typesafe.ai/introduction/quickstart) on 2026-10-10 KST. Console login is handled by the user's browser.

Pipes and unattended jobs never wait for setup input. They fail with setup instructions if the key is missing. After copying the key, `jev-native setup --import-pasteboard` explicitly authorizes immediate import, including without a TTY. This flag reads the current pasteboard once; do not invoke it until the user has agreed to that import. No `pbpaste`, AppleScript or browser automation helper is used.

The imported token must be one 16–4096-byte ASCII Bearer-token-shaped string, with surrounding whitespace trimmed. This is a local accidental-paste check, not proof of a valid TypeSafe key or an official prefix/length contract. No API request is made during setup. Empty text, commands, JSON, URLs and multiline content are rejected without echoing their contents. The clipboard is not cleared or overwritten.

Saving stages a new file with mode `0600`, syncs it, then atomically publishes it using an exclusive hard link in the same directory. An existing destination—including an empty file, unreadable file or symlink—is never replaced. If an unusable `.typesafeai` already exists, setup reports the collision so the owner can resolve it manually. No backup is created. If a credential appears while the user is copying the key, setup rechecks and skips import.

`run` shows a small live target-window preview in the bottom corner. Close hides it. Its JEV menu-bar item or Dock icon reopens it. The panel never forwards clicks into the target. Hidden previews pause capture; visible previews refresh approximately four times per second. `--no-preview` disables it. `--keep-open` retains the final preview, including incomplete outcomes; the process then remains alive until Quit. With `--no-preview`, there is no final panel to retain. Without keep-open, an incomplete report exits 2. Other failures exit 1.

AX actions update the preview cursor at the control. `--show-virtual-cursor` additionally draws a click-through desktop marker; the normal cursor is shown within the preview. Target-window selection is separate from explicit `activate`/`raise` actions. Keys target a process and do not implement global system shortcuts.

## Task JSON

Only `goal` and `apps` are required. Other fields have defaults:

```json
{"goal":"Write the supplied text in an owned document","apps":["com.apple.TextEdit"],"texts":["Literal text"],"actions":[{"kind":"openFile","app":"com.apple.TextEdit","path":"/absolute/owned/Fixture.txt","label":"Open owned fixture"}],"generateText":false,"inspectImage":false,"maxSteps":30,"settleMS":250,"maxRecovery":3,"confidence":0.55,"expectText":"Literal text","expectApp":"com.apple.TextEdit"}
```

`--generate-text` / `generateText` invokes Codex for requested original text. `--inspect-image` / `inspectImage` invokes Codex vision. `--codex-model` preserves an explicit model choice; otherwise the isolated Codex invocation uses its CLI default. Codex runs with user configuration ignored, shell tools disabled, read-only sandbox, and JSON schema output. Events and results are retained. Tool attempts reject delegate output. Raster image generation/editing is not implemented. Vision observations and coordinate proposals remain advisory; JEV selects the next action. Vision evidence binds to target image SHA-256 and expires on state/image changes.

Action kinds: `launch`, `activate`, `openFile`, `selectWindow`, `press`, `secondary`, `focus`, `setValue`, `selectText`, `type`, `key`, `click`, `doubleClick`, `rightClick`, `move`, `drag`, `scroll`, `raise`, `resize`, `moveWindow`, `wait`. See `Action` and `validateAction` in `Models.swift` for fields. `secondary` requires an observed AX action name. Text selection offsets are UTF-16. `selectWindow` uses `windowID`; it can set that app's main window when supported. Keyboard input rejects a focused window different from the selected window.

Pointer coordinates default to global logical points. `coordinateSpace` can be `windowPoints` (top-left of selected window) or `screenshotPixels` (scaled through the recorded pixel size and window bounds). Drag uses `toX`/`toY`. Scroll uses `amount` and optional `horizontalAmount`, with optional x/y hover location. Resize uses `toX`/`toY` as width/height. Fresh AX state is checked before actions; pointer actions also recheck image SHA-256.

Choice confidence measures distribution concentration, not permission or workflow correctness. A dispersed Choice triggers one dependent Noul question about the selected step's progress; probability below 0.85 stops as `uncertain`. It does not reroll identical uncertainty until a favorable answer arrives. These are configurable/example operating thresholds, not calibrated safety claims. Recovery is bounded. Requests load the nonempty environment `TYPESAFE_API_KEY`, otherwise `~/.typesafeai`, at runtime without logging the credential.

Reports retain observations, PNGs, candidate sets, JEV responses/model/usage, Codex events/results, errors, before/after observations and timing. `verified_complete` means JEV completion plus supplied postconditions: `expectText` is a substring in AX/window OCR and `expectApp` matches the target, not foreground. It does not prove unspecified requirements. `jev_observed_complete` is semantic assessment only. API milliseconds include network plus service time; local serialization/parsing is separate. Input execution timing excludes settling and subsequent observation.

## Startup and graphical-session requirements

Help, credential setup without a clipboard/browser action, skill installation, and file-based Codex delegation do not create `NSApplication`. Native observation and input require the logged-in user's graphical session. Preview and virtual-pointer paths retain the AppKit event loop. `--no-preview` removes the preview requirement, but native automation still needs desktop-service access.

Before native UI startup, the CLI checks graphical-session access with `SessionGetInfo` and performs a public, read-only LaunchServices lookup. Detectable failures return actionable stderr. A successful preflight cannot guarantee that subsequent AppKit registration succeeds. The reported macOS 27.0.1 `RegisterApplication` abort was not reproduced; its exact LaunchServices error remains unknown. No TCC cause or system database reset is established by the crash stack.

## Compatibility and evidence boundaries

The private Apple `SLEventSetWindowLocation` symbol and AppKit's undocumented CGEvent field 51 annotate window-local mouse routing. This module is isolated in `WindowEvents.swift`. `JEV_DISABLE_PRIVATE_EVENTS=1` disables it; AX and keyboard remain available. Coordinate input fails when annotation is unavailable. Only macOS 27.0.1 arm64 runtime was tested; the macOS 14 minimum deployment target is not a runtime compatibility certification. This is not Mac App Store compatible private-API code.

Real evidence includes Calculator AX/JEV execution, Calculator virtual click, TextEdit Codex generation followed by JEV-selected native text input and observed marker, Codex image interpretation and resumed JEV completion, native canvas background drag/scroll events, and preview hide/reopen. TextEdit background drag did not select text in tested runs. Input acceptance is app-specific; no Codex parity is claimed. AX depth/node and Choice candidate limits can omit controls in large interfaces; inspect snapshots and supply explicit candidates or use `act` where required. Automatic JEV mode currently declines consequential send/purchase/delete/account/security actions; direct control remains governed by caller authorization.

Accessibility, Screen Recording and input posting passed for the Codex-launched installed binary. A fresh Terminal/Finder launch has not been certified and must use `doctor` for its actual TCC identity. No Automation/Apple Events permission is required by this backend. Validation used owned fixture data and made no purchases, messages, deletions of user data, or account/security changes. Owned fixture binaries are developer tests, not runtime dependencies.

## App selection

`run --goal` and task JSON may omit `apps`. JEV selects the necessary native apps from the installed and running app catalogue, in workflow order. Explicit `--apps` and task JSON `apps` retain their previous target order and execution scope. The first app is the initial target; the remaining apps become switch candidates.

- With neither mode flag, selection uses the goal. An ambiguous, unavailable or low-confidence result offers an app list when stdin and stderr are terminals. Noninteractive runs stop with an actionable diagnostic.
- `--auto` uses the goal and never opens an app-selection prompt.
- `--simple` lists actual apps and reads one or more comma-separated list numbers in workflow order. This skips JEV app selection; JEV still selects actions during execution. `cancel`, `q`, or EOF stops before automation. Invalid input stops with an error.
- `--apps`, `--auto`, and `--simple` are mutually exclusive. Task JSON that includes `apps` already uses explicit mode. Omit the field to infer or choose apps; an explicit empty array is rejected.

Discovery includes launchable foreground app bundles in `/Applications`, `/System/Applications`, `/System/Library/CoreServices`, `~/Applications`, and the running native app list. It excludes background helpers and the controller, deduplicates bundle IDs, and validates installation and LaunchServices resolution before execution. Apps outside these roots can be supplied with `--apps`. Installed apps need not already be running. App discovery does not search every filesystem volume.

Selection uses typed Choice judgments, followed by a Noul scope check of at least 0.85. Choice confidence must meet the task's confidence threshold. Catalogues above the Choice option limit use grouped selection without dropping candidates. These checks reduce uncertainty; semantic app selection can still be wrong. The resolved bundle IDs feed the existing execution scope and freshness checks.

`app-selection.json` and `report.json.appSelection` record source (`explicit`, `goal`, or `interactive`), status, selected identities, candidate count, API timings and usage. `app-candidates.json` contains local installation paths; request/call files retain the selection evidence. Treat these local outputs as private. Unresolved selection writes a report with no automation steps and exits 2.

## Native task window

Run `jev-native --gui` to open a native goal-entry and execution window. CLI invocation without arguments still prints help. `--gui --goal TEXT` pre-fills the goal without starting it. `--simple` initially selects the app-list mode; automatic app selection is the default. `--no-preview` starts with the target preview disabled. `--codex-model MODEL` retains an explicitly chosen delegate model. GUI launch rejects unsupported flags instead of silently ignoring an explicit app scope.

The window has a multiline goal, optional literal text to type, automatic/native-list app selection, target preview, Codex text/vision options, Run/Stop, status and a report location. It supports standard Edit menu shortcuts. In app-list mode, search names or bundle IDs, add one or more apps, and use Move Up/Move Down to set workflow order. The first selected app is the initial target. No terminal input is used by the GUI.

Only one run can be active in the window. Run and editable inputs are disabled until completion or cancellation. Stop waits for the current operation/API call, then prevents subsequent native input. Closing the task window requests a stop if needed and hides the window. Quitting during a run waits for a cancellation report before terminating. Completion and cancellation allow another run. Reopening the running application restores the goal window; Window > Show Task Window does the same. The existing target preview remains separate and can be hidden/reopened.

Reports are saved under `~/Library/Application Support/JEV Native/Runs/<UUID>/`. Each run folder is created with mode 0700. Show Report reveals its `report.json` in Finder. Reports distinguish `jev_observed_complete`, uncertain/blocked results, cancellation and errors; GUI semantic completion is not a deterministic postcondition guarantee. CLI task JSON and `--expect-text`/`--expect-app` remain available for explicit postconditions. Raw reports, screenshots and app inventories can contain private data.

Credentials use the existing environment/file resolver. If missing, the window offers Open Key Management and an explicit Import Key from Clipboard button. Key contents are never shown. The import preserves an existing key and uses the existing atomic 0600 writer. Opening the window does not read the clipboard, import a key or start automation.
