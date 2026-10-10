# AX query engine, 0.4.0 (6)

Implemented a local Swift AX query store, compact structured JEV input, progressive region/candidate/value expansion, indexed/batched AX acquisition, observer hints and bounded target freshness checks. **End-to-end JEV reliability remains unresolved.** The final complete cohort is **query 3/5, legacy 2/5**. No confidence threshold was lowered and no failed task was rerun merely to obtain a green result.

Final public executable SHA-256: `2ad9222bbbcc908208c5cdaf125a7efb134ff713cb37fa2d17b90bb42701e5f6`. The final cohort and native probes use this same executable. The fixture SHA is recorded in the JSON evidence. Tests: **61 passed**, zero failures; release build has no compiler warnings/errors. Ad-hoc signing is used; the app is not notarized.

## Implemented behavior

- Local `overview`, typed `find`, paginated `children`, explicit-field/UTF-16 `read`, and revision-aware `changes` APIs. Opaque handles expire on revision changes; cursors bind to operation/filter/parent/revision. Coverage is complete/partial/unknown for exposed AX only. No-match is distinct from unexplored content.
- Initial collection bounds at 160 nodes, with progressive region expansion. Structural bridge regions are grouped by their actual collected ancestors. All candidate pages remain reachable below the Choice limit; small UIs keep their direct candidate path. Same-name controls retain explicit ancestor paths. A name-priority prototype added unnecessary pages and was removed after its 1/5 cohort.
- Metadata uses batched AX reads. Children use indexed array pages. Exact acquired values/native parent references stay local. Secure fields/subtrees are excluded. Large editor text is previewed/read through UTF-16 ranges; wire-visible spans determine continuation. Omitted short/noneditable values have bounded read candidates too.
- Selection and progress verification share compact structured evidence. Structured proposed targets retain ambiguous-control ancestry. Values are bounded to 16 nodes and 6000 UTF-16 units, at most 2000 per value, with explicit omitted/truncated evidence and reachable reads.
- AXObserver notifications are hints. Recognizable loaded-node hints support local subtree invalidation; unknown/root/scope changes refresh conservatively. Unit tests prove unaffected refs survive local partial invalidation with one reread. The native changing fixture proves notifications arrived and fresh state was read, but initial process→window scope changed too, so **native partial-subtree reuse/notification causality is not proven**.
- Immediately before AX mutation: current process/window ownership, role/title/frame, secure/enabled/focused and observed selected/checked state, captured native AXParent identity/context, directly retained traversal ancestor labels/roles/enabled/security, and top-level modal-sheet stamps are checked. AXChildren and AXParent are not assumed inverse. These checks read the target/ancestor path, not whole editor content. Pointer actions retain fresh observation/image validation. Cancellation and shared GUI/CLI runner regressions remain covered.
- Explicit expectText/expectApp predicates now take documented precedence over a model done judgment, on fresh observations after pending literal texts and required text/vision delegates complete. All declared predicates must match. Text uses substring matching; app uses selected target identity. The caller must express all required conditions; app identity alone is not proof of a free-form goal. Without predicates, completion remains JEV semantic assessment.

## Final paired measurement

Source: `benchmarks/ax-query/bench-production.json`. Each mode/scenario has three fresh-process, image-free observation samples followed by one real JEV/native workflow. Collection time is the median in ms; count is the measured AX API invocation count from the first sample. Counts include read/action/observer registration calls, **not underlying Mach/XPC packet traces**. API-internal IPC multiplicity is unknown. Selection and verification request bytes are measured from serialized request bodies; input tokens come from TypeSafe responses.

| Fixture | Legacy collect ms / calls | Query collect ms / calls | Actual input tokens | JEV calls | Whole task ms | Legacy / query outcome |
|---|---:|---:|---:|---:|---:|---|
| small | 84.57 / 115 | 79.61 / 71 | 2409 → 1101 | 2 → 1 | 1474.4 → 1183.8 | verified_complete / verified_complete |
| large | 250.87 / 7811 | 109.34 / 691 | 9108 → 6423 | 1 → 3 | 826.1 → 1236.6 | blocked / uncertain |
| long | 95.39 / 220 | 91.62 / 114 | 3572 → 2747 | 2 → 2 | 892.8 → 831.8 | uncertain / uncertain |
| duplicates | 74.84 / 180 | 77.01 / 96 | 1191 → 1200 | 1 → 1 | 580.8 → 1091.7 | blocked / verified_complete |
| dialog | 76.68 / 115 | 80.10 / 71 | 3784 → 2339 | 3 → 2 | 2608.1 → 2364.9 | verified_complete / verified_complete |

The large initial snapshot collects 160 nodes instead of the legacy 600. Its lower initial cost does not mean equal coverage, full-tree throughput improvement or a completed task. Large/long query tasks stopped uncertain before any native event in the final cohort. Small, duplicates and dialog completed; duplicates emitted only `right`, with no left event. Initial collection was slightly slower in duplicates/dialog despite fewer API calls. Whole task comparisons also include the changed explicit-predicate completion contract and stochastic JEV/verification calls, so they do not isolate AX speed. One run per pair is not a reliability estimate or statistical performance guarantee.

## Native evidence and retained failures

Native long-document reads returned an exact 40-unit prefix and `END-MARKER-731` at UTF-16 location60000,length14 in a 60014-unit document. Real parameterized range calls, find/children cursors and within-batch target references were exercised. The notification fixture received two hints and read `result=changed`; scope-change causality limits are stated above. These probes do not call JEV.

All complete cohorts are retained: `bench`, `bench-compact`, `bench-parent`, `bench-structured`, `bench-final`, `bench-release`, `bench-production`. Earlier native row719/long/dialog completions and later uncertain completion judgments remain visible in their own candidate-round files. Earlier executable hashes were not retained consistently; those successes are not final-binary certification. `bench-release` is the removed name-priority prototype's **query1/5** cohort. `bench-final` is an earlier **query3/5** cohort, not a claim of five completions. Progress commentary that initially claimed five completions was corrected after inspecting the whole cohort. The final report uses the frozen rolled-back binary and its full `bench-production` cohort, without cherry-picking earlier successes.

The baseline is the instrumented legacy walker/candidate-cap/completion path in the same binary and fixture, not an immutable old-release binary. This is a controlled backend comparison with current packaging; do not treat it as a historical release benchmark. Raw AX trees, private app inventories, screenshots and full command logs stay local. Published JSON contains only owned-fixture measurements and sanitized summaries. No UI mockup was deployed, no backups were created, and credentials were not changed.
