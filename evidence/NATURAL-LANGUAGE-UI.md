# Native natural-language UI, 0.5.0 (7)

The native AppKit window accepts one Korean natural-language request. Typed JEV decisions resolve ordinary actions, verbatim text, original writing, source transformation, visual interpretation and result destination. Swift validates original UTF-16 spans, follow-up field bindings, source-window identity and native execution scope. The GUI invokes the real Codex CLI for needed content or visual interpretation. Explicit CLI/task modes retain their prior override semantics.

## Behavior

The main window exposes request, examples, request/stop, status, result and report access. Connection and preview controls are in the menu. No app/generation/vision switches are required for the default request flow. Missing fields open a native follow-up sheet. The original request remains immutable, and field answers are recorded separately. A chosen live window ID remains authoritative while its current identity is revalidated. At most four answers are accepted.

Verbatim text is copied from exact original UTF-16 ranges, including Unicode, whitespace and line breaks. New writing uses a content delegate. A source transformation requires complete exposed AX text or exact supplied source text. Native document reading requires one text area, bounded complete AX coverage, length at most 12,000 UTF-16 units, two equal live reads, and current source-window identity. Partial, missing, ambiguous or oversized source content does not become a fabricated summary.

A summary, translation or image explanation without an explicit app write destination appears in the task window. Selecting a source does not authorize replacement. Explicit app writes reuse JEV-selected native actions and fresh target checks. A protected source window rejects mutating input unless replacement was explicitly requested. Visual interpretation has a separate `interpret` category, requires a selected screenshot, and uses `reply_vision` for UI results. Natural authored-visual-content requests with an app write destination stop as `visual_destination_unresolved` before native input. The selected visual source is not reused as an implicit write destination. A task-window image reply and vision-assisted native actions are supported. A focused resolver/task-spec invariant prevents the unsupported combination from reaching native execution. Explicit CLI generation+vision modes still require visual evidence before writing and pending text before completion.

Cancellation is checked across intent resolution, follow-up, source acquisition, delegates and native actions. A running Codex child is terminated. A report records original request, field answers, intent/model/usage, resolution events, source evidence, delegate output/usage and native steps. An absent actual Codex model ID remains unknown; it is not inferred from host configuration.

## Deterministic validation

The final public-source suite has **89 passing tests, zero failures**. Tests cover literal Unicode/whitespace fidelity, type routing, live target answer binding, source delivery/write protection, missing/partial source handling, follow-up/resume, cancellation including an actual child process, pending-text completion and visual-before-writing invariants. Final installed/public builds have no compiler warnings or errors. A temporary layout compile failure from an ambiguous CGFloat/Double constant was corrected; raw failed logs remain private.

The native composer, result and free-text follow-up use bounded wrapping text layout. Final window captures separately verify the long request at default and minimum geometry. UI capture does not execute a task.

## Actual owned-fixture runtime evidence

These are selected workflow observations, not a general success-rate benchmark. Full private logs remain separate. [Sanitized outcomes](checks/natural-language-runtime.json) retain cancelled, blocked, uncertain and harness-error runs as well as successful runs.

| Workflow | Observed result | Independent evidence |
|---|---|---|
| Natural new-writing request | `jev_observed_complete` | One actual Codex text delegate, JEV-selected native typing, native editor exactly equals the generated three-line Korean answer, native text-change events |
| Summary with document-selection follow-up | `content_delivered` | User-form answer selected 제품 제안서, actual complete 68 UTF-16 source, verified AXWindow identity, correct one-sentence summary, both source documents unchanged, zero native task inputs |
| Visual explanation without inspect flag | `content_delivered` | Separate interpret route, actual selected-window screenshot and Codex image delegate, coherent background/button description displayed, zero native task inputs |
| Ordinary 확인 button request | `uncertain` | Correct action classification, correct app/window and enabled button candidate; Choice 0.42 and progress probability 0.76 stop before input; zero content/vision delegates and zero button events |

The ordinary button workflow is **not verified successful**. An earlier run returned `blocked` at confidence 0.36 even though the button was exposed. The final run selected the correct button but stopped under existing thresholds. No threshold was weakened and no native task action was forced. Candidate inspection found the enabled button with `press`, title and fixture ancestor context; it did not establish that model reliability is resolved.

Earlier harness runs failed to select a popup option, depended on an NSControl callback not emitted by AX selection, sought the wrong fixture document, or lost the observe/act freshness race while answering the controller sheet. The product now validates the actual selection on submission. The corrected owned-form helper uses an immediate AXPress on the exact enabled continuation button. These harness operations target only our controller's form and never replace JEV selection of fixture task actions. The failed runs are not counted as product successes.

The first image-description run lacked a coherent content taxonomy and was cancelled at a generic clarification. The separate interpret category and visual clarification option corrected that routing gap. The successful image explanation used the repaired taxonomy. Generation, source summary and visual explanation were measured on identified pre-layout binaries; the final text-layout changes plus explicit unsupported authored-visual-destination guard/regression, rebuild and fresh GUI captures are recorded separately in packaging evidence. No model call was repeated solely to obtain a favorable result.

## Packaging and limits

The installed source app, public app and relocated ZIP are 0.5.0 (7), ad-hoc signed and not notarized. Strict signatures, help, doctor, existing-key setup, isolated Codex/Claude skill installation and repeat installation are checked. Credentials remain byte-identical. Public and original source synchronization retains deliberate portable-skill/build/test differences. [Package checks](checks/natural-language-package.json) and [archive metadata](../artifacts/checksums.json) identify the actual binaries.

This evidence covers owned fixtures in the Codex launch context on macOS 27.0.1 arm64. Fresh Terminal/Finder, Gatekeeper, host skill loader/Composer exposure, all apps, virtualized documents, and arbitrary natural-language file paths are not runtime certified. Natural visual-description app writes are explicitly unresolved. Image/video generation, external research and arbitrary shell execution are outside this backend. No messaging, purchase, deletion of user data or account/security action was performed. Existing AX-query evidence remains historical and does not become a new 0.5.0 benchmark.

Final native screenshots: [default size](screenshots/jev-native-natural-language-ui.png), [minimum size](screenshots/jev-native-natural-language-ui-minimum.png). Both contain the same long wrapped synthetic request.
