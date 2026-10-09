# TypeSafe API key setup delivery

Date: 2026-10-10 KST. Scope: existing JEV Native macOS CLI and companion skill. No commit, push, backup, actual key replacement, new API key issuance or authentication request.

## Changes

`Sources/JevComputerUse/CredentialSetup.swift` adds injectable setup I/O, native NSPasteboard reads, explicit NSWorkspace URL opening, local token-shape validation, and atomic exclusive credential installation. `CLI.swift` adds `setup` and a missing-key preflight for `run`, before preview creation or automation. README and the installed companion skill describe consent, noninteractive use, precedence and limitations.

Existing precedence is unchanged: nonempty `TYPESAFE_API_KEY` first, otherwise nonempty `~/.typesafeai`. A configured key prevents prompts and clipboard reads, even with `--import-pasteboard`. Setup does not try to rotate a rejected key after an API authentication failure.

Interactive setup offers three commands: `import`, `open`, `cancel`. The prompt asks the user to copy only the key to the macOS pasteboard and specifically tells them not to paste the key into the terminal. Clipboard text is read only after `import`. EOF cancels. After waiting for the user, setup rechecks for a credential before reading the clipboard. Messages never include clipboard contents or keys.

`setup --import-pasteboard` is deliberate immediate import consent and works without a TTY. Ordinary noninteractive missing-key setup/run fails promptly without reading stdin, opening a browser or reading the clipboard. `setup --open-keys` explicitly opens key management and exits without importing. NSWorkspace and NSPasteboard are the runtime APIs; no pbpaste, osascript or browser automation helper is added. Codex remains the sole external runtime binary exception.

Credential writes use an owner-only staging file in the opened home directory, O_EXCL/O_NOFOLLOW, fchmod(0600), a full write loop, fsync and an atomic exclusive linkat publication. Existing entries, including symlinks and concurrent credentials, are never replaced. Staging files are removed after success/failure. No backup is made. The clipboard is left unchanged.

## Official URL verification

On 2026-10-10 KST the official TypeSafe Quick start at https://docs.typesafe.ai/introduction/quickstart linked its API key dashboard to https://console.typesafe.ai/keys . Following that official link redirected to https://console.typesafe.ai/login?returnTo=/keys . The implemented URL is https://console.typesafe.ai/keys . This verifies the official entry point; authenticated management UI was not inspected.

## Usage

- `jev-native setup`: interactive setup when needed.
- Copy only the key using the user's browser, then type `import` at the prompt. Type `cancel` to leave without changing configuration.
- Type `open` at the prompt, or run `jev-native setup --open-keys`, when the user chooses to open key management.
- After the user has explicitly agreed to import their copied key, `jev-native setup --import-pasteboard` performs immediate import without waiting for stdin. Do not invoke it speculatively against arbitrary clipboard content.
- `jev-native run ...` offers the same interactive setup only if both credential sources are unavailable. Pipes/unattended jobs receive an error with the explicit setup commands.
- `doctor` remains read-only and does not trigger setup.

## Actual validation

- `evidence/credential-setup-tests.log`: all 16 Swift tests passed, including 10 new credential setup tests. Coverage: cancellation/EOF, noninteractive missing key, environment/file precedence, unique native NSPasteboard import, file mode/ownership, no secret messages, empty/malformed content, explicit noninteractive import, explicit page-opening choice, a credential appearing while waiting, existing destination/symlink preservation, staging cleanup, and empty-file collision.
- `evidence/credential-setup-build.log`: release bundle build and ad-hoc signing passed, with no compiler warnings/errors in the final log.
- Swift Intelligence diagnostics for `CredentialSetup.swift`: empty diagnostic list.
- `evidence/credential-setup-skill-validation.log`: Skill is valid.
- `evidence/credential-setup-probe.swift` compiled the actual production Models/CredentialSetup sources into a test-only probe. A real TTY session accepted `import`, read a synthetic key from a unique NSPasteboard, saved it in an isolated temporary home, and reported matching synthetic content and mode 600. A second TTY session accepted `cancel` and left no file. Probe source, binary and transcript are retained; temporary homes and private pasteboards were cleaned up.
- `evidence/credential-setup-noninteractive.log`: the same probe with stdin redirected from /dev/null returned missing-key guidance immediately and reported no saved file.
- `evidence/credential-setup-installed-existing.json`: the rebuilt installed CLI ran `setup --import-pasteboard` against the existing valid configuration, exited 0 and skipped import. In-memory digests and filesystem metadata comparisons verified unchanged actual key bytes, inode, permissions and mtime. Neither digest nor key was printed or saved.

The probe's URL-opening adapter is synthetic and records only the intended action. No browser was actually opened in validation. The probe uses the production readLine/isatty path but an isolated key location and unique NSPasteboard; the real user's general pasteboard was not overwritten or read for these tests.

## Limits

- Import checks a conservative 16–4096-byte ASCII Bearer-token shape. It rejects accidental commands, JSON, URLs and multiline text, but it cannot prove service validity. This is not an official TypeSafe prefix/length contract. No API request is made during setup.
- For no-overwrite guarantees, even an existing empty/unreadable `.typesafeai` is preserved. Setup reports the collision for the owner to resolve manually. It does not repair or rotate existing credentials.
- Actual creation with a new real API key and actual browser login were not performed. TTY and noninteractive missing-key paths were exercised with production setup code in the isolated native probe, rather than by removing the user's working key.
- Prompt-based setup requires stdin and stderr to be TTYs. Callers that intentionally redirect streams must use the deliberate explicit import command after obtaining user agreement.


---
Public export note: local paths, incident identifiers and process identifiers were sanitized. Historical raw artifact names refer to the retained private validation corpus. Only the reviewed public subset in [the evidence index](../README.md) is included here. This report records its original check scope; later public packaging checks are recorded separately in PUBLICATION.md.
