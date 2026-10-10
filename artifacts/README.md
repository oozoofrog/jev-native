# App artifact

`JevNative-0.3.0-arm64.zip` contains the native app bundle built from this repository, version 0.3.0 (5), for Apple Silicon. `checksums.json` records its SHA-256 and the executable digest.

This is a development artifact with an ad-hoc signature. It is not Developer ID signed or notarized. Runtime validation covers macOS 27.0.1 arm64 in the existing Codex launch context; macOS 14 is only the deployment target. Fresh Terminal/Finder/Gatekeeper behavior and TCC identity remain unverified. No system protection bypass is included or recommended.

For source builds, use `./Scripts/build.sh`. To rebuild a public archive executable without local source paths and debug sections, use `JEV_REDACT_BUILD_PATHS=1 ./Scripts/build.sh`. That mode strips debug data before signing. Skill templates are located at runtime from the app bundle or checkout; no builder source path is embedded. Run the app executable inside its bundle, rather than extracting the binary alone.

To use an extracted bundle, select a stable install location and add a symlink to `JevNative.app/Contents/MacOS/jev-native` at an unused command path. Run `doctor` for the actual launch-context permissions before automation. The archive does not include credentials, the separately installed Codex executable, or model weights.
