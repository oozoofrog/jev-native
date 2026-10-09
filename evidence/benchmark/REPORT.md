# Codex computer use vs JEV Native: one-action speed benchmark

Measured on 2026-10-10 KST, on this Mac running macOS 27.0.1. **The measured elapsed median was 6.291 s for Codex computer use and 2.037 s for JEV Native to exit. Both reached the correct UI state in 5/5 trials, but JEV reported successful completion in only 3/5.** The other two JEV runs exited `uncertain` after correctly pressing the button. The stop-time ratio is 3.09×; it is not a claim of a 3.09× reliable completion speedup.

## Task and method

One action: starting with Calculator's numeric display at exactly `0`, press its `7` digit button once and verify that the numeric display is exactly `7`. This is a real native Calculator task, not an owned substitute fixture. It avoids the additional steps and history entries of `7 × 6 =`.

Both paths used the same running Calculator window in basic mode. Each trial started after an untimed clear/reset and independent observation of `0`. One warmup per tool was excluded. Five measured trials per tool followed, in paired order C–J, J–C, C–J, J–C, C–J. No configuration or confidence thresholds were tuned after warmup. No retries were added to turn uncertain JEV exits into successes.

Codex used the actual `cua_repl` native-app API: `cua.getApp("Calculator")`, a fresh full `getAXState()`, the model's next tool call selecting the freshly observed `7` button, `app.click(10)`, then `getAXState()`. The native action was not issued by shell, AppleScript or a generated automation script. Numeric-display assertions checked `Value: 7`, not a button's label. The measured Codex model in this session was `gpt-6.1-sol`, reasoning `medium`, as recorded in local turn metadata.

JEV used the actual installed `~/.local/bin/jev-native run --task task.json --out ...` closed loop. The timing harness only launched the real CLI and recorded clocks/results; it did not select controls or inject input. JEV selected and executed one native AX press in every measured trial. Actual API responses identify `jev-1.13.0`. Default preview was enabled; default 250 ms settling, confidence 0.55, and progress gate 0.85 remained in place. There was no Codex delegation in the JEV task because no original text or image interpretation was needed.

## Timing boundaries

- **Codex start:** inside `cua_repl`, immediately before the measured fresh AX observation, after the reset was verified. **Codex end:** immediately after the click and final AX observation returned. The recorded interval spans the model/tool round trip between the two CUA calls. It includes no reset, commentary, unrelated tool call, warmup, final report drafting or intentional delay. Date.now timestamps have millisecond resolution.
- **JEV start:** immediately before spawning the installed CLI process. **JEV end:** process return after its report/exit status. Python `perf_counter_ns` measured the elapsed interval. This includes startup, observations/capture/OCR, actual JEV API calls, input, default settling, completion assessment, report writes and exit.
- **Independent JEV verification:** after each timed process exit, Codex CUA observed Calculator's numeric display at `7`. This cross-check is excluded from the timed JEV interval, but exact native AX state and JEV's report are retained as evidence.

These are practical orchestration-path timings, not symmetric backend microbenchmarks. Codex was already bound to the app after warmup; JEV started a fresh CLI process per trial. Codex used AX-only observations in the timed path. JEV used its default target screenshots/OCR, persisted evidence and live preview. Codex's end includes a programmatic exact-display assertion in the native tool call, while JEV also runs its model-based completion/uncertainty gate before exiting.

## Samples

All times are actual elapsed seconds. Every final display was independently verified as exactly `7`.

| Pair | Order | Codex elapsed | Codex result | JEV elapsed to exit | JEV report |
|---|---|---:|---|---:|---|
| 1 | C → J | 6.418 | verified UI | 2.152 | `verified_complete` |
| 2 | J → C | 6.291 | verified UI | 2.184 | `uncertain` |
| 3 | C → J | 6.031 | verified UI | 1.873 | `verified_complete` |
| 4 | J → C | 6.664 | verified UI | 2.037 | `uncertain` |
| 5 | C → J | 5.982 | verified UI | 1.835 | `verified_complete` |

| Metric | Codex computer use | JEV Native |
|---|---:|---:|
| Measured trials | 5 | 5 |
| Exact UI target reached | 5/5 | 5/5 |
| Controller reported completion | 5/5 | 3/5 |
| All-trial elapsed median | 6.291 s | 2.037 s to exit |
| All-trial range | 5.982–6.664 s | 1.835–2.184 s |

For the three JEV `verified_complete` runs only, median was **1.873 s**, range **1.835–2.152 s**. This is a conditional subset, not a five-trial completion comparison. Warmups were Codex 6.392 s and JEV 2.254 s; JEV's warmup also exited uncertain after reaching `7`.

## Where time was spent

Component medians are measured independently and are not an additive decomposition of a median trial.

| Codex component | Median |
|---|---:|
| Initial AX observation | 82 ms |
| Gap between initial observation and next input call | 5,721 ms |
| CUA click call | 55 ms |
| Final AX observation | 425 ms |

The 5.721 s gap includes model processing/code generation, dispatch and tool round-trip overhead. It cannot be isolated as pure model inference latency from these clocks.

| JEV component | Median per trial |
|---|---:|
| Native AX input execution | 7.660 ms |
| JEV API time, including dependent progress call where used | 458.267 ms |
| Local decision serialization/parsing | 0.599 ms |
| Persisted observation/capture/OCR time | 861.893 ms |

Successful JEV runs used two API calls: choose the press, then choose completion. The two uncertain runs used three calls, including the dependent progress check. API time includes network plus service latency. Persisted observation totals exclude the unpersisted freshness observation before input. JEV's input timing is an in-process execution timer; CUA's click timer includes its wrapper/RPC path, so their ratio is not a pure OS-input speed ratio.

## Completion failures retained

- JEV trial 2: `Uncertain selection: Choice confidence 0.52, progress probability 0.4. No identical-state retry.` Exit 2. Native and independent CUA observations both showed `7`.
- JEV trial 4: `Uncertain selection: Choice confidence 0.47, progress probability 0.63. No identical-state retry.` Exit 2. Native and independent CUA observations both showed `7`.

These are completion-gate failures, not failed digit presses. The benchmark did not lower thresholds, replace the closed loop, or count exit 2 as `verified_complete`.

## State preservation and limits

Calculator's original numeric display was `42 %`. It was restored through the native CUA controls after all trials and independently observed as `42 %`. No equals operation, new document, setting change, credential readout/change or unrelated app mutation was needed. The result screenshot was captured before restoration and visually inspected. Restored display evidence does not certify hidden Calculator history/internal state; this one-digit task was chosen to avoid adding completed calculation entries.

This is one trivial native AX task on one machine in an existing long-running Codex chat. The Codex context/model/tool service, JEV service/network load, capture behavior and completion policy differ. The sample size is five per tool, without a confidence interval or randomized workload. It does not establish general app compatibility, multi-step reliability, coordinate-input speed, Codex parity, or universal product speed.

The practical finding is that the JEV in-process loop had a shorter elapsed interval for this button task, while the current JEV completion gate was less reliable at reporting an already-correct result. Most of Codex's measured interval lay in the model/tool round trip rather than the native click.

## Evidence

Project evidence directory: `/path/to/jev-native/evidence/speed-benchmark`.

- `codex-cua-exact-export.json`: exact trial clocks and AX strings exported from the live CUA session, original display and restored display.
- `cua-calls.json`: actual native CUA calls and text outputs, excluding image bytes and unrelated conversation content.
- `codex-model-provenance.json`: local model/reasoning metadata.
- `jev-N-timing.json`, `jev-N/report.json`, task/decisions/observations/PNGs and stdout/stderr: raw JEV evidence for each trial and warmup.
- `task.json`, `run_jev_trial.py`: unchanged task and process-timing harness.
- `samples.csv`, `samples.json`, `summary.json`: computed samples and statistics.

No product source changes, commits or pushes were made for this benchmark. Credentials were resolved by the existing native implementation and were never printed or altered.


---
Public export note: local paths, incident identifiers and process identifiers were sanitized. Historical raw artifact names refer to the retained private validation corpus. Only the reviewed public subset in [the evidence index](../README.md) is included here. This report records its original check scope; later public packaging checks are recorded separately in PUBLICATION.md.
