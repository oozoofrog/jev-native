# Codex and Claude Code skill installer delivery

Date: 2026-10-10 KST. Source: `/path/to/jev-native`.

## Delivered behavior

The native CLI now implements `install-skill --host codex|claude|both`. User scope is the default. `--scope project --project PATH` installs beneath an explicitly selected existing project. `--skills-dir PATH` provides an explicit directory override for one host. Invalid, missing, duplicate and unknown options fail before installation.

Fresh user destinations are `~/.agents/skills/jev-native` for Codex and `~/.claude/skills/jev-native` for Claude Code. Project destinations are `.agents/skills/jev-native` and `.claude/skills/jev-native`. A compatible existing user installation at `~/.codex/skills/jev-native` is reused, so this machine's existing source symlink is preserved without a duplicate Codex skill.

The installer renders a host-specific SKILL.md: `$jev-native` for Codex and `/jev-native` for Claude Code. Both preserve JEV typed action selection, direct Swift/Apple-framework execution and verification, the separate virtual cursor, preview controls, pasteboard API key setup and current capability limits. Both retain the actual Codex CLI handoff for original text and image interpretation. Claude installation does not replace that handoff with Claude output. Codex installation and authentication remain prerequisites for those delegates.

The installed instructions bind the native CLI path to the executable performing installation, with shell quoting for spaces/apostrophes. The app bundle now contains the companion template in `Contents/Resources/skills/jev-native/SKILL.md`; the build script includes it before ad-hoc signing. No external installer, shell subprocess, browser helper, package download or model request is used by skill installation.

All selected host destinations are checked before any skill is published. Matching documents report `already_installed` and preserve extra user files. Different documents, files, empty directories and dangling symlinks cause conflicts. Existing instructions are never updated or replaced. New directories are staged and atomically published with Darwin `renameatx_np(..., RENAME_EXCL)`, so a destination that appears after preflight is not replaced. Staging is cleaned after the operation. If an I/O race/failure happens after a prior host was published, that successful host remains installed; the error explains the possible partial result. No rollback deletes installed/user data.

No backups, commits, pushes, host settings edits, host restarts or unrelated skill changes were made. Installation does not touch credentials. No actual Claude user-scope installation was made during verification; Claude installs were tested in isolated destinations.

## Usage

```sh
jev-native install-skill --host codex
jev-native install-skill --host claude
jev-native install-skill --host both
jev-native install-skill --host both --scope project --project /absolute/project
jev-native install-skill --host claude --skills-dir /explicit/skills-directory
```

The output is a JSON array containing `host`, `path` and `status` (`installed` or `already_installed`). Conflicts exit 1 with the destination named. There is no `--force` or silent upgrade option. Installation adds the companion skill only; it does not install Codex or Claude Code themselves.

## Documentation checked

- Official OpenAI local-skill locations: https://learn.chatgpt.com/docs/build-skills (the previous https://developers.openai.com/codex/skills URL redirects here). The current documented user location is `.agents/skills` under the user's home; repository skill discovery uses `.agents/skills` along the repository path.
- Official Claude Code skills: https://code.claude.com/docs/en/skills . Personal skills use `~/.claude/skills/<name>/SKILL.md`; project skills use `.claude/skills/<name>/SKILL.md`.
- The legacy `.codex/skills` reuse is based on the existing local installation, not a claim that the current public location table lists it.

## Actual validation

- `skill-install-tests.log`: 24 Swift tests passed, including 8 new installer tests and all previous credential/automation regression tests. Installer coverage includes both user locations with an isolated home, both project locations, an explicit destination, repeated installs, preservation of extra user files, modified documents, both-host conflict preflight, compatible legacy Codex symlink reuse, conflicting legacy content, dangling symlink/empty-directory conflicts, argument validation and quoted executable paths.
- `skill-install-build.log`: release app build and ad-hoc signing passed; no compiler warnings/errors were found in the final log. The bundle contains the template resource.
- `skill-install-validation.log`: source companion skill and generated Codex/Claude variants each passed skill-creator structure validation.
- Swift Intelligence returned empty diagnostics for `SkillInstallation.swift` and `CLI.swift`.
- `skill-install-cli/results.json`: the rebuilt installed executable created both project-scope variants in an isolated evidence fixture; a second invocation returned `already_installed` for both. It rejected a modified Claude document without changing it, installed to a custom single-host directory, rejected a conflicting Claude destination before creating the Codex destination, and rejected an incomplete option.
- The same installed executable ran default `install-skill --host codex` against the real existing installation. It returned `already_installed` for `~/.codex/skills/jev-native`. The symlink target and document bytes remained unchanged, and no `~/.agents/skills/jev-native` duplicate was created. The actual TypeSafe key bytes also remained unchanged; no key or digest was logged.

## Discovery and portability limits

These checks establish file installation, repeat behavior and conflict preservation. They do not establish discovery or invocation in a fresh Codex or Claude Code session. No new host session was launched for acceptance. The CLI prints this distinction after a successful install.

A custom `--skills-dir` location is not automatically registered with a host. Host configuration and policy can also affect discovery. Project selection is the caller's explicit scope choice; installation does not initialize a repository or commit files.

Generated skills point to the installed native executable. Keep that executable path available. A moved executable or updated/modified skill document requires an explicit user decision to resolve the existing installation; the installer does not silently rewrite it. Claude means local Claude Code, not Claude Desktop, Cowork or a cloud deployment.


---
Public export note: local paths, incident identifiers and process identifiers were sanitized. Historical raw artifact names refer to the retained private validation corpus. Only the reviewed public subset in [the evidence index](../README.md) is included here. This report records its original check scope; later public packaging checks are recorded separately in PUBLICATION.md.
