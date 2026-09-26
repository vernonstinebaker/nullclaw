# NullClaw — Agent Engine Hardening Plan

> **Recovery contract:** This file is the authoritative scope, progress, and handoff record for this work. Read it before editing. Work on the first incomplete phase only. Write a regression test, observe the intended failure, implement the smallest fix, then validate. Update the ledger before stopping or changing phase. Never infer completion from a checked implementation box without its validation evidence.

## Goal and scope

Make the existing provider-agnostic agent engine correct under policy enforcement, concurrent tool execution, lossy output handling, repeated calls, cache reuse, interruptions, allocation failures, and long turns. Preserve the vtable architecture and the shared provider dispatch path. Fix observable behavior before moving large blocks between files.

This plan implements the findings in [the durable core review](docs/plans/core-review-2026-09-23.md). The prior `PLAN.md` is preserved verbatim at [the historical local-loop plan](docs/plans/local-loop-2026-08-15.md). Its PR gates, completed checkboxes, constrained-decoding proposals, and deployment instructions are historical context, **not authorization or prerequisites for this hardening work**. No new provider, grammar engine, dependency, release, deployment, or toolchain bump is part of this plan.

## Baseline and ownership

| Fact | Value |
|---|---|
| Repository | `nullclaw`; verify `git remote -v` before any remote action |
| Origin at planning | `https://github.com/vernonstinebaker/nullclaw.git` |
| Upstream at planning | `https://github.com/nullclaw/nullclaw.git` |
| Reviewed baseline | `10231364fb58628dfd7c429afe5eba0a17289773` (`v2026.9.23-1`) |
| Toolchain | Zig 0.16.0; do not change the pin |
| Host baseline | macOS arm64; also require portable deterministic tests |
| Baseline full suite | 7,500 passed, 9 skipped; exit 0; no reported leaks |
| Baseline release | ReleaseSmall passes; default macOS artifact 4,885,880 bytes |
| Baseline test memory | main test executable MaxRSS 344 MB; production RSS unmeasured |
| Last updated | 2026-09-23 |

The checkout already contains unrelated untracked `.claw/`, `CHECKIN.md`, `palace/`, `docs/en/rest-admin-api.md`, and multiple `zig-out-*` trees. Preserve them. Recheck status because other sessions may add commits. Do not stage unrelated files, reset changes, clean the workspace, force-push, tag, or deploy. Local commits may checkpoint completed phases; record actual hashes if made. Do not treat another project's commit/push workflow as a request to publish this work.

## Resume procedure (required after interruption, compaction, or agent replacement)

1. Read `AGENTS.md`, this plan's **Progress ledger**, **Current handoff**, and the relevant phase. The durable review contains triggers and rationale; line numbers can move, so find symbols with `rg`.
2. Run `git status --short`, `git log -10 --oneline`, `git diff --stat`, and `zig version`. Compare HEAD and modified files to the handoff. If HEAD advanced, inspect the intervening diff; never overwrite concurrent work or report obsolete findings.
3. Finish existing uncommitted phase work before starting another phase. A red test or half-written cleanup path is not a completed phase. If a test/build process is still running, use its recorded session or log; do not launch duplicates blindly.
4. Reproduce the next unchecked RED task. If another commit already fixes it, record the regression test and passing evidence as `superseded/verified`, not as new implementation.
5. Follow RED → GREEN → REVIEW below. Keep code, regression tests, documentation, and this plan in the same logical change.
6. Before stopping, update exact changed files, test names, commands/results, current HEAD, unresolved concerns, and the next executable action in **Current handoff**. `/tmp` logs are optional evidence; the plan must contain enough results to resume if they disappear.

## Per-phase TDD and quality gates

- **RED:** Add tests at the behavior boundary. Cite the guarded bug in a nearby `// Regression:` comment. Run before changing production code and record the expected failure. A compiler error or sandbox failure does not establish the regression.
- **GREEN:** Make the smallest repair; use existing tools/vtables. No speculative configuration switches. Failure paths must release all owned allocations and join every started worker.
- **REVIEW:** Check the diff for policy weakening, stale ownership, side effects, accidental secrets, and unrelated churn. Fix fixture races as well as production races.
- **VALIDATE:** `zig fmt --check` on changed Zig files, then `zig build test --summary all` with zero failures/leaks. Run ReleaseSmall after memory/concurrency changes and at final sign-off. Do not silently waive unrelated failures; record and resolve their cause or mark the phase incomplete.
- **PORTABILITY:** Fake providers, counting tools, temporary directories, deterministic synchronization, and fault injection only. Do not use a real shell command, browser, external account, provider, or network for new regression coverage. Existing localhost socket tests need sandbox permission; a permission failure is an environment issue, not a passing or failing product regression.
- **CHECKPOINT:** Update all phase checkboxes, ledger, and handoff. Each phase should be independently reviewable. Do not batch unrelated refactors into a fix.

Canonical commands (from repository root):

```sh
zig version
zig fmt --check src/agent/root.zig
zig build test --summary all
zig build -Doptimize=ReleaseSmall
```

Use the relevant changed files for formatting. Build currently has no test-filter option; do not assume `zig build test -- --test-filter ...` filters tests. A full-suite RED run is acceptable. Redirect full logs to a unique temporary path and summarize failures. If cache writes are sandbox-blocked, use a writable `--global-cache-dir` or the approved execution path; record the exact command. Optional release output can use `--prefix /tmp/nullclaw-hardening-release` to preserve existing installations.

## Progress ledger

Status: `TODO`, `RED`, `GREEN (validation pending)`, `DONE`, `BLOCKED`, or `SUPERSEDED (verified)`.

| Phase | Scope / finding | Status | Evidence / next dependency |
|---|---|---|---|
| 0 | Durable plan, preserve prior scope, baseline | DONE | Review and Swift examples read; 7,500-pass baseline recorded |
| 1 | Canonical tool identity / session exec policy (R1) | DONE | 7,501 passed / 9 skipped; formatting/diff checks pass |
| 2 | Parallel result ownership, joins, shared state (R2/R3) | DONE | 7,506 passed / 9 skipped; ReleaseSmall passes (4,885,816 bytes) |
| 3 | Lossless default output, safe compression (R4/R5) | DONE | 7,509 passed / 9 skipped; ReleaseSmall and fmt/diff pass |
| 4 | Exact tool replay identity and loop guard (R7 + guard gaps) | DONE | 7,519 passed / 9 skipped; `/tmp/nullclaw-p4-final.log` |
| 5 | Context-safe response caching (R6) | DONE | 7,522 passed / 9 skipped; `/tmp/nullclaw-p5.log` |
| 6 | Turn finalization, persistence, allocation cleanup (R9) | DONE | 7,524 passed / 9 skipped; `/tmp/nullclaw-p6c.log` |
| 7 | MCP availability and external-content policy (R8) | DONE | 7,527 passed / 9 skipped; D6 retains the lock |
| 8 | Active-model budgets, measured resource limits, final audit | DONE | 7,530 passed / 9 skipped; ReleaseSmall measured below |

## Phase 1 — Canonical identity before session exec policy

**Risk:** High, access boundary. **Files:** `src/agent/root.zig` (`executeToolBody`), adjacent policy tests; `src/agent/dispatcher.zig` (`parseStructuredToolCalls`) and `commands.zig` (`isExecToolName`, `execBlockMessage`) for tracing.

Problem: lookup trims names but the exec check uses the original name; native `" shell "` reaches shell while skipping session deny/approval. The shell's separate security policy does not repair the missing session restriction.

- [x] P1.R Write a counting shell stub; parse native calls with leading/trailing spaces, tabs/newlines, and mixed case. Verify `/exec security=deny`, `ask=always`, and unsupported host deny execution. Approval records the pending command once and exposes no execution side effect. Include canonical shell and an allowed non-shell control. Observe RED before changing lookup/policy.
- [x] P1.G Apply policy using the resolved registered tool name (same identity as execution), not the provider-supplied spelling. Keep unknown tools and malformed arguments fail-closed. Do not relax configured shell allowlists.
- [x] P1.V Full suite and formatting pass; existing canonical shell approval/deny tests remain valid. Record the exact RED and GREEN test totals.
- [x] P1.D Document the security invariant near the decision point and update this ledger.

Acceptance: every spelling that resolves to shell is checked as shell, with zero stub executions when denied or awaiting approval.

## Phase 2 — Parallel worker lifetime and shared-state safety

**Risk:** High, memory safety and concurrent policy. **Files:** `src/agent/root.zig` (`ParallelReadOnlyWorker`, `executeParallelReadOnlyToolBatch`, diagnostics), `parallel_tools.zig`, `redaction.zig`, and allowlisted tool implementations as needed. Dependencies: inspect allocator ownership in session/CLI callers before choosing worker allocators.

- [x] P2.R1 Add deterministic concurrent-result regression coverage: unique sizable payload per worker, synchronized completion, stable result order, and a test allocator that rejects parent-arena access from worker threads. Avoid probabilistic repeated stress as the only assertion.
- [x] P2.R2 Inject a spawn failure after at least one worker starts, and a result-copy allocation failure. Assert every started worker finishes/joins before batch return and no context/arena is freed early. A narrow private test seam is acceptable; do not add public config or a general scheduling framework.
- [x] P2.R3 Replace non-atomic counters in existing parallel fixtures; retain tests for actual overlap, max concurrency, order, cancellation, denied calls, and worker tool failures.
- [x] P2.G1 Keep worker results in worker-owned storage through join; copy/transfer on the coordinator only. Define who destroys arenas on success, partial spawn, tool failure, copy failure, and interruption. Install cleanup immediately after initialization, before any fallible spawn.
- [x] P2.G2 Join *all* started workers before inspecting/propagating worker errors. Ensure the backing allocator is safe for worker allocations; avoid concurrent use of an Agent arena supplied by a caller.
- [x] P2.G3 Audit allowlisted tools for mutable state; read-only effects do not imply thread safety. Move shared redactor/observer mutation to the coordinator or synchronize explicitly. Preserve secret scrubbing; never bypass redaction to obtain concurrency. Remove unsafe tools from the parallel allowlist if their thread safety cannot be established.
- [x] P2.V Full suite, fault injection without leaks, ReleaseSmall, and diff review. Document remaining concurrency limitations accurately.

Acceptance: no worker allocates into the coordinating arena; no worker outlives batch storage; parallel success still overlaps and returns in call order. No global/thread-local test controls that introduce races across independent tests.

## Phase 3 — Preserve evidence and bound deliberate compression

**Risk:** Medium; impacts every provider's tool evidence. **Files:** `result_compress.zig`, `Agent.compressToolResultForHistory`, `LocalLoopConfig`, EN/ZH configuration documentation. Avoid adding config fields unless existing fields cannot express the agreed behavior.

- [x] P3.R1 Add RED unit/full-turn tests: short Python/YAML retains indentation/newlines/blank lines; a source result with >12 lines below byte cap retains its start; structured JSON stays parseable; default/local-loop-off forwards exact tool output before existing redaction.
- [x] P3.R2 Exercise signature detection without relying on inlining; test mixed-case error markers and a multi-byte character crossing the 180-byte signature boundary. Test caps 0, 1, marker-length−1, marker-length, UTF-8 edges, and large output; result never exceeds the byte cap.
- [x] P3.G Remove returned stack references with caller-owned storage or direct case-insensitive search. Preserve lossless output by default. Apply existing aggressive local compression only to explicit suitable log-style outputs; do not flatten source/JSON or silently tail arbitrary data. Specify which tool types may lose content and how omitted content can be retrieved (offset reads/refined query); retain redaction ordering.
- [x] P3.V Update prior lossy-default tests to the new contract, with evidence that they test changed behavior rather than just the implementation. Validate default and opt-in modes, full suite, ReleaseSmall. Keep EN/ZH docs consistent and state bytes versus characters truthfully.

Acceptance: default file/data reads retain exact content except the pre-existing privacy transformation; intentional truncation is explicit, UTF-8-safe, and respects all caps.

## Phase 4 — Distinguish replay from a new observation

**Risk:** High, repeated side effects and stale evidence. **Files:** `Agent.toolCallDedupFingerprint`, `CachedToolCallResult`, lookup/store helpers, sequential/parallel batch paths, `loop_guard.zig`.

- [x] P4.R1 Full-turn no-ID read→write→read fixture must observe new content; repeated polling sees changing tool results. Native replay of the *same* ID/name/arguments executes once and reuses success/failure consistently.
- [x] P4.R2 Reused ID with different tool/arguments must fail explicitly rather than silently reuse output or execute a different action. Duplicate IDs in one parallel batch must not execute twice. Tests must cover both paths and fresh IDs for legitimate repeated calls.
- [x] P4.G Remove turn-wide signature caching for intentional no-ID calls. Retain exact native replay protection with identity validation, not hash-only assumptions. Do not invalidate protection against repeated side effects merely to refresh reads.
- [x] P4.R3 Equivalent JSON objects with reordered keys/whitespace should contribute to the same guard count; genuinely different scalar values/array order must remain distinct. Alternating already-vetoed calls must not reset the stop budget indefinitely; legitimate progress resets it. Malformed/oversized arguments terminate safely.
- [x] P4.G2 Canonicalize semantics for loop detection with bounded parsing/storage and normalized registered names; define collision handling and veto counting. Keep this a quality guard, not an authorization boundary.
- [x] P4.V Full suite and zero-leak allocation failures for cache insertion/identity ownership; record bounded cache ownership for Phase 8.

Acceptance: verify-after-write works; exact replay does not repeat side effects; equivalent argument formatting does not evade the guard.

## Phase 5 — Response cache eligibility and conversational identity

**Risk:** High, actions omitted or wrong-context answers. **Files:** `Agent.responseCacheSafeForTurn`, cache hit/store branches, `memory/lifecycle/cache.zig`, related session tests.

- [x] P5.R Repeating an action request executes the action again; identical follow-up text after different histories must not reuse the old answer; changed retrieved memory invalidates eligibility/key. Include redaction placeholder protections and cache-enabled/disabled cases.
- [x] P5.G Define conservative eligibility *before lookup* and track whether tools executed before storing. Prefer disabling cache reuse for tool-capable/contextual turns rather than guessing action intent from text. If caching conversational requests remains, key the actual complete provider inputs and relevant generation/tool settings. No semantic guesswork about whether a cached answer is safe.
- [x] P5.V Test eligible simple direct responses still cache, ineligible ones do not, TTL behavior remains valid, and cache failures do not fail the turn. Full suite; document limitations in EN/ZH config docs. Default remains disabled.

Acceptance: cache cannot substitute for requested side effects or ignore relevant conversation/memory state.

## Phase 6 — Complete every turn coherently and release on errors

**Risk:** High, history/persistence and memory ownership. **Files:** `Agent.turn`, batch return contracts, `freeResponseFields`, `turn_persistence.zig`, `session.zig`; observer recording fixtures.

- [x] P6.R1 Force loop-guard stop both before execution and after an earlier successful tool in a mixed batch. Assert completed results and explicit skipped results remain paired with calls, final stop text is in history, persist/reload returns the actual stop reply, and turn-complete is emitted once.
- [x] P6.R2 Cover stop/interruption before provider, between tools, in parallel workers, and before the iteration-limit summary. No extra provider/tool call after cancellation. Preserve pending injection semantics and avoid losing completed work.
- [x] P6.G Centralize only the shared finalization needed by these paths; use an explicit batch stop outcome rather than dropping partial results. Persist an explicit final assistant response, not a role-only guess that can select a tool-step assistant entry.
- [x] P6.R3 Use `std.testing.checkAllAllocationFailures` or bounded failure injection around a minimal mocked full turn: native parse, history append, result formatting/redaction, final composition, summary, and injection. Account for ownership transfer and optional fields.
- [x] P6.G2 Install one scoped cleanup for provider responses immediately after successful acquisition, including summary responses. Audit owned append helpers and avoid double frees when transferring content. Clean up partially cloned parser entries where required by the exercised path.
- [x] P6.V Full suite with leak detection, interruption and restoration integration tests, ReleaseSmall. Keep test failure-injection scope small/deterministic rather than loading real configuration or networking.

Acceptance: every completed/degraded turn has truthful history, persistence, and observability; no allocation error leaks a provider response; all workers finish before turn cleanup.

## Phase 7 — Predictable tool availability and explicit external-content policy

**Risk:** High, availability and permission boundaries. **Files:** `filterToolSpecsForTurn`, `narrowMcpToolsForTurn`, prompt tool filtering, pending injection, `checkToolPolicyGate`, EN/ZH docs.

- [x] P7.R Test configured `always` tools without lexical name matches, short server names, >16 explicitly configured tools, a `continue` follow-up, and a mid-turn injection requesting a newly relevant tool. Keep dynamically excluded tools excluded unless the new instruction actually authorizes their availability.
- [x] P7.G Preserve explicit group semantics through narrowing. Prefer removing the unconditional second lexical filter if no bounded discovery/context-aware replacement can meet the tests; do not build a new discovery system without a concrete caller. Select schemas using current instructions and keep XML/native descriptions consistent.
- [x] P7.D Write a concrete decision record for the external-content lock: today any external-tool batch locks named mutators for the turn (even failures), research→save is blocked, and arbitrary MCP mutators are not covered. Do not silently remove or broaden this security policy. Prepare tested options and seek user direction only if the existing authorization does not resolve the product/security tradeoff; finish unrelated availability work first.
- [x] P7.V Add failure/same-batch/order/next-turn tests for the retained policy; document its actual limits without claiming complete prompt-injection protection. Full suite and no implicit permission broadening.

Acceptance: configured always tools stay available; follow-ups/injections do not lose required capabilities; any external-content policy change has a recorded decision and boundary tests.

## Phase 8 — Model-aware budgets and measured resource baseline

**Risk:** Medium/high; performance changes must preserve correctness. **Files:** iteration-limit summary and pre-dispatch preparation in `Agent.turn`, compaction/token helpers, replay cache; focused benchmark fixture and documentation.

- [x] P8.R Routed model differs from default; initial/retry/terminal-summary requests must all use the active model and its token budget/session ID. Streaming context-exhaustion recovery already landed: retain its tests rather than reimplement it. Add long tool-turn tests that reach budget pressure before finalization.
- [x] P8.G Compact/prepare before requests where needed, preserve tool-call/result grouping and latest instructions, keep retries bounded, and avoid replaying partial streamed text. Do not blindly drop history on unrelated provider errors.
- [x] P8.R2 Synthetic long-run fixture measures live allocation peak and replay-cache bytes across large outputs, many unique IDs, replay, and a user-raised iteration cap. No network or wall-clock performance assertions in unit tests.
- [x] P8.G2 Set a justified internal replay-memory bound without evicting side-effect replay identities unsafely. If payload retention is capped, fail explicitly or keep bounded replay metadata rather than re-executing an old action. Record tradeoffs and measurements.
- [x] P8.V Define reproducible default and minimal-feature build profiles from supported flags. Record binary bytes, test RSS, and production idle/representative turn RSS separately. Compare to baseline; do not relabel 344 MB test RSS as runtime memory or change the <1 MB/<5 MB targets silently. Explain feature/platform differences and get a target decision if required.
- [x] P8.F Final full suite/ReleaseSmall/format checks, review all open findings and documentation, confirm HEAD/status, and leave a final handoff. Do not claim exhaustive provider/security audit.

Acceptance: routed requests retain their model budget; long turns have a tested memory boundary; resource claims use reproducible profiles and measurements.

## Decision log

| ID | Decision | Rationale / revisit condition |
|---|---|---|
| D1 | Preserve old plan as historical, replace root plan | Existing untracked planning work must not be lost or mistaken for this scope |
| D2 | Keep vtables/shared dispatch; minimal fixes first | Avoid mixing architecture refactoring with correctness repairs |
| D3 | Default parallel tools and response cache remain off | Do not enable affected paths globally while hardening |
| D4 | Streaming context recovery is already resolved | Latest baseline includes shared dispatch and full-turn recovery tests |
| D5 | Do not relax external-content policy without a concrete decision | Review established a design concern, not authorization to weaken a boundary |
| D6 | Keep the external-content lock as it is | After `web_search`, `web_fetch`, `http_request`, or `browser` appears in a batch, named mutators stay blocked for the rest of that turn, including when the external call fails and when the mutator is ordered first. The next user message clears it. Arbitrary MCP writes are not covered. This is not a complete prompt-injection defense. Revisit only with a new product decision |
| D7 | #979 `auto_recall=false` does NOT broaden response-cache eligibility | `responseCacheSafeForTurn` keeps disqualifying any turn where a memory backend is configured (`mem`/`mem_rt` present), even though recall-off means memory cannot influence generation. Rationale: the P5 hardening rule is deliberately conservative and the cache is default-off; broadening eligibility is a separate decision if ever requested. The interaction is documented in the configuration docs |

## Validation ledger

| Phase / revision | RED evidence | GREEN evidence | Notes |
|---|---|---|---|
| Baseline `10231364` | Review probes: indentation, leading content, small cap, equivalent JSON, stack lifetime fail | Full suite: 7,500 passed / 9 skipped, 0 reported leaks; ReleaseSmall passes | Probes were temporary copies, not committed regression tests; phase tests must exercise production paths |
| P1 working tree | `zig build test --summary all`: 7,500 passed / 9 skipped / 1 failed; only `native shell name variants cannot bypass session exec policy` failed at the expected denial assertion | 7,501 passed / 9 skipped; exit 0, no reported leaks | Logs `/tmp/nullclaw-hardening-p1-{red,green}.log`; formatting and diff whitespace checks pass |

| P2 working tree | Parent-arena affinity assertion failed as expected: 7,501 passed / 9 skipped / 1 failed | Final suite: 7,506 passed / 9 skipped, exit 0, no reported leaks; ReleaseSmall exit 0; fmt/diff checks pass | `/tmp/nullclaw-resume-p2-{red-approved,audit,release-audit}.log`. Fault seam covers second spawn and first/second copy failures; atomic fixtures cover overlap/order and worker policy/error results. |

Concurrency audit: worker arenas use independent page allocation (testing allocator in tests). Coordinator alone copies to the turn arena after all joins. Policy operations use the batch mutex; active/interrupted names and verbose redaction use `tool_state_mu`. File tools otherwise use immutable configuration and call-local storage; SQLite queries open per-call connections/redactors; web tools use immutable configuration and call-local request state. Memory-backend calls and bootstrap-file reads remain sequential because their vtables do not guarantee thread safety. Tests use no external tools/providers. Default parallel setting remains off.

P3 validation: `/tmp/nullclaw-p3-red.log` records 7,506 passed, 9 skipped, 3 intended regression failures (source/history fidelity and tiny caps). `/tmp/nullclaw-p3-final.log` records 7,509 passed, 9 skipped, no reported leaks. `/tmp/nullclaw-p3-release.log` exits 0. Full-turn test checks exact large default output versus opt-in marked shell compression; unit tests cover Python/YAML/JSON, >12 lines, UTF-8 signature boundary and caps 0–31. EN/ZH docs agree; source/data/MCP stay lossless even with local mode on.

P4 validation: `/tmp/nullclaw-p4-red.log` records 7,509 passed, 9 skipped, 4 intended failures (no-ID stale read, native identity mismatch, equivalent JSON, alternating vetoes). `/tmp/nullclaw-p4-final.log` records 7,519 passed, 9 skipped, exit 0. No-ID calls execute again. Native replay identity is the exact id plus name and arguments; a mismatch returns a static conflict and does not execute. Duplicate native IDs in one batch run sequentially. Loop-guard keys are canonical. Malformed or oversized arguments stop the turn. Allocation-failure coverage is in `loop_guard.zig` and the replay-ownership test.

P5 validation: `/tmp/nullclaw-p5.log` records 7,522 passed, 9 skipped, exit 0. Response cache stays default-disabled. Lookup requires no tools, no memory, no conversation context, and exactly one user message. The key includes temperature, max tokens, and reasoning. A follow-up or a tool turn calls the provider again. Cache get/put errors do not fail the turn. EN/ZH configuration docs describe this.

P6 validation: `/tmp/nullclaw-p6.log` and `/tmp/nullclaw-p6b.log` each failed one allocation-failure test (parser append, then the test's own history append). `/tmp/nullclaw-p6c.log` records 7,524 passed, 9 skipped, exit 0. A loop-guard stop commits completed results, skipped remainder, and the stop text. Provider responses are freed on the error path. Parsed tool calls are freed if the call list cannot grow.

P7 validation: `/tmp/nullclaw-p7.log` records 7,527 passed, 9 skipped, exit 0. Configured `always` groups stay available for short names, lists longer than 16, and `continue`. A `dynamic` tool appears only after the current text or a mid-turn injection contains its keyword. Ungrouped turns still omit unrelated MCP schemas. Decision D6 retains the external-content lock; failure, order, same-batch, and next-turn tests cover it. EN/ZH docs state the limits.

P8 validation: `/tmp/nullclaw-p8.log` records 7,530 passed, 9 skipped, exit 0. A routed `openai/gpt-4` turn uses that model, its 4,096-token cap, and the turn session id on the initial request, the context-recovery retry, and the iteration-limit summary. Compaction in that turn uses the routed model and its context window. `error.RateLimited` leaves existing history in place. Replay retention is 64 KiB per output, 256 KiB total, and 256 identities. Over-cap output is truncated. Output that does not fit becomes a short notice, or empty metadata once the notice itself does not fit. The 257th identity returns `error.ReplayMemoryExceeded` instead of evicting an executed call. Streaming context-recovery tests were left in place.

Resource measurements, macOS arm64, Zig 0.16.0, HEAD `10231364`, uncommitted hardening tree:

| Profile | Command | Bytes | `version` MaxRSS |
|---|---|---|---|
| Baseline default ReleaseSmall | recorded at planning | 4,885,880 | unmeasured |
| Default ReleaseSmall | `zig build -Doptimize=ReleaseSmall --prefix /tmp/nullclaw-hardening-release` | 4,904,856 | 2,916,352 max resident; 1,687,936 peak footprint |
| CLI + sqlite | `zig build -Doptimize=ReleaseSmall -Dchannels=cli -Dengines=base,sqlite --prefix /tmp/nullclaw-hardening-cli` | 4,378,904 | 2,899,968 max resident |
| `engines=base` without sqlite | same flags with `-Dengines=base` | does not link | sqlite_query still references sqlite |

The default artifact grew by 18,976 bytes from the planning baseline. Both profiles are above the <1 MB binary target; the planning baseline was already 4.89 MB, so this change does not move that target. `version` MaxRSS is under the <5 MB runtime target and is startup only, not a model turn. Suite MaxRSS was not remeasured: `zig build test` does not print it, and launching the cached test executable directly aborts because it expects the Zig test server. The historical 344 MB figure remains a test-process measurement, not production RSS. No representative provider turn was measured.

## Upstream intake — nullclaw/nullclaw → vernonstinebaker/nullclaw (authorized 2026-09-23)

Upstream `nullclaw/nullclaw` is dormant (no maintainer merges since 2026-04-17; 30 PRs open at assessment on 2026-09-23 — corrected from an earlier "28"; 26 open as of end of day after four closures below). This fork (`vernonstinebaker/nullclaw`) now maintains its own `main` directly.

> **Update 2026-09-26 — upstream is active again.** donprus merged **#986, #996, #985 on 2026-09-24** — the exact PRs this fork took as intakes U-10/U-9/U-1. Those three intakes are now redundant upstream; **#984, #776, #777 remain open**. The fork is a **staging path only**: the fleet build basis moved to **`upstream/main` + all open vernonstinebaker code PRs** (`wt/deploy-upstream-all-prs`, rebuilt by `rebuild-all-prs.sh`). Fork `main` is 100 ahead / 6 behind upstream and is no longer the build source. This scope incorporates selected **third-party** upstream PRs, one PR per increment, ranked against the fork's deployment environments: the OrangePi `webdav` MCP stdio server (`mcp_webdav_*` in an `always` tool-filter group), the bilingual `docs/en` + `docs/zh` tree, and the three deployment hosts (macOS arm64, OrangePi riscv64, Radxa aarch64 — daemon 24/7, Mattermost + Discord, sqlite memory, cron heartbeats).

**Workflow contract, per intake (mandatory):**

0. **Approval scope:** #985, #776, #777 approved 2026-09-23 (all DONE). **#979 approved 2026-09-23 (later decision), in progress.** **#984 approved 2026-09-23.** **Wrap-up salvage 2026-09-23/24 (user): closed-unmerged upstream PRs re-reviewed on the merits — "don't abandon good work just because the author gave up"; #978, #986, #996 taken (U-8..U-10), #965 verified superseded.** Do not intake any other upstream PR without a new explicit user decision. Work **one PR at a time** with a user check-in between PRs. Documentation changes must be accurate and up-to-date for this tree (verify claims against `src/`, fix stale references), and all changes must follow `AGENTS.md` and `CONTRIBUTING.md`.
0a. **Terminology (audience-aware, user rule 2026-09-23):** in anything other NullClaw users may read — upstream PR comments, docs, commit messages, this plan — avoid ambiguous possessives tied to the private deployment (e.g. "our fleet"). Use concrete referents instead: "this fork", "the deployment hosts (macOS arm64, OrangePi riscv64, Radxa aarch64)", "the OrangePi `webdav` MCP server".
0b. **Assessment criteria (user rules 2026-09-23):** refer to upstream work by its PR number, not internal ledger IDs, in all prose. This fork is maintained **for the broader NullClaw community** — the deployment hosts are the primary concern, not the only lens; weigh community benefit and upstream-config compatibility alongside deployment fit.

1. `git fetch origin && git log -1 --oneline origin/main` — a second agent session works in this repo and pushes may arrive concurrently (the hardening phases landed as `90e4b01c` during another session's review). Never overwrite concurrent work; rebase intake work on the new HEAD if it moved.
2. Fetch the exact upstream diff: `gh pr diff <N> -R nullclaw/nullclaw`. Prefer applying it verbatim (keeps future upstream merges clean); reconcile manually where this tree diverged, and say so in the commit body.
3. **Test first** where behavior is testable: apply/add the regression test, run it, observe and record the intended RED before the fix.
4. `zig fmt --check` on changed Zig files, then `zig build test --summary all` — zero failures, zero leaks. Docs-only intakes still run the suite (cheap, and the pre-push hook runs it anyway).
5. Commit only the intake's files. **Never stage** `.claw/`, `CHECKIN.md`, `palace/` (live credentials), `docs/en/rest-admin-api.md` (unrelated WIP), or `zig-out-*`.
6. `git push origin main`. Rollback unit = `git revert <intake commit>`; keep one PR per commit where the diff allows.

**Intake ledger** (status: `TODO`, `RED`, `GREEN (validation pending)`, `DONE`, `DEFERRED`):

| ID | Upstream PR | Scope / environment rationale | Status | Commit / evidence |
|---|---|---|---|---|
| U-1 | #985 (raskevichai) | `SESSION_TURN_STACK_SIZE` 2 MiB alias → 16 MiB. Turn path overflowed into the guard page and killed the process per inbound message on aarch64 — the Radxa deployment host. Turn path got deeper in `90e4b01c`; `thread_stacks.zig` untouched by it, applies cleanly. | DONE | `415b54c8`. RED: budget test failed vs 2 MiB alias (`zig test src/thread_stacks.zig` 3/4). GREEN: 4/4; full suite 7535 passed / 9 skipped, exit 0. Upstream notified 2026-09-23: [comment](https://github.com/nullclaw/nullclaw/pull/985#issuecomment-5796851845) |
| U-2 | #776 (telagod) | New en+zh docs: `mcp.md`, subagents, skills, voice, hardware (+651, 13 files, docs-only). Documents the exact MCP surface the deployment's `webdav`/`vikunja`/`mattermost` MCP servers use. **When landing: amend `mcp.md` to document the post-P7 rule — `narrowMcpToolsForTurn` only runs when no `tool_filter_groups` are configured.** | DONE | `29c02d55`. 10 new files applied verbatim; README index hunks ported manually (this tree's READMEs diverged from upstream). Intake-time corrections, verified against src: `env`/`headers` are string→string objects (`config_parse.zig:1439-1468`), not arrays; subagent limits 15/4 are built-in (`subagent.zig:52`), not configurable — JSON block removed; narrowing rule documented en+zh. Upstream notified 2026-09-23: [comment](https://github.com/nullclaw/nullclaw/pull/776#issuecomment-5796853927) |
| U-3 | #979 (valonmulolli) | `memory.auto_recall` / `recall_limit` / `max_context_bytes` config knobs (closes upstream #919). Composes with the P8 replay/memory bounds. **Conflicts expected:** `90e4b01c` reworked `memory_loader.zig`, sqlite engine, `memory_recall.zig`, and `agent/root.zig` — the upstream patch will not apply cleanly; reconcile semantics manually (budget injected recall bytes), not line-by-line. | DONE | Semantic re-implementation with upstream key names/semantics preserved. RED: 6 intended failures (config round-trip, wizard patch, 3 loader limit tests, agent `auto_recall` gate test) at 7533/9/6. GREEN: 7539 passed / 9 skipped, exit 0, fmt clean. Limit checks moved to top-of-loop (check-before-append, incl. archive-filter paths from `90e4b01c`); `RecallParams` threaded through the loader; `auto_recall` gate at the single call site; old constants removed; flattened `Config` mirrors + syncFlatFields; en+zh configuration docs (auto_save vs auto_recall, recall_limit vs search.query.max_results, byte-budget semantics, D7 cache note). D7 governs cache eligibility. Upstream notified 2026-09-23: [comment](https://github.com/nullclaw/nullclaw/pull/979#issuecomment-5797537259) |
| U-4 | #777 (telagod) | Docs cleanup: archive `docs/integration-analysis.md` + `docs/integration-roadmap.md` to `docs/archive/`, slim `CONTRIBUTING.md`, cross-ref `SECURITY.md`. Both stale files were still present in this tree. | DONE | `59ad630a`. SECURITY.md + docs/README.md hunks applied verbatim; renames via `git mv`; CONTRIBUTING.md ported manually — upstream's slimmed structure but keeping our accurate pins (Zig 0.16.0 + zig-installation pointer; upstream text said 0.15.2). Verified `docs/en/development.md` + zh cover all slimmed-away content (validation matrix, hooks, docs sync, PR guidance). All changed-file links resolve; `git diff --check` clean; suite 7535/9. Upstream notified 2026-09-23: [comment](https://github.com/nullclaw/nullclaw/pull/777#issuecomment-5796856550) |
| U-5 | #984 (raskevichai) | Supervisor: age out dead polling threads even when their failure path keeps refreshing the heartbeat. Symptoms reported on Telegram/Matrix; **before landing, verify the fix covers our Mattermost/Discord transports** — if not, record that and land only the general supervisor repair. | DONE | Verified before landing: the deployment's Mattermost/Discord channels are `gateway_loop` (health-check path) — NOT covered by, or at risk from, this fix; it covers the six polling channels (telegram, matrix, signal, weixin, imessage, max). Taken as community maintenance per criterion 0b. Applied verbatim (clean apply; failure path stops refreshing `last_activity`, backoff 1s→30s shared helpers). **No formal RED available** (AGENTS §8.1): the behavioral change lives in concrete-typed polling loops needing real network I/O; regression tests ship in the patch on the extracted `isPollingStale`/`nextPollBackoffNs` seams, citing #972, plus 2 added edge tests (backwards clock step, zero-input backoff). Suite 7545 passed / 9 skipped, fmt clean. Upstream notified 2026-09-23: [comment](https://github.com/nullclaw/nullclaw/pull/984#issuecomment-5797744970) |
| U-6 | — | Update `docs/plans/core-review-2026-09-23.md` to mark findings R1–R9 addressed at `90e4b01c` (plan ledger phases 1–8); the review currently reads as all-open. Docs-only. | DONE | Resolution-status banner (finding→phase table) + per-finding `> Resolved` tags added; every hardening-opportunity item confirmed resolved against the validation ledger before tagging. D6 write-lock concern noted as settled |
| U-7 | — | Repair mangled line prefixes in `docs/README.md` (11), `docs/en/README.md` (17), `docs/zh/README.md` (17): committed merge damage, lines like `MB:## Core User Docs` / `QV:- [Beginner's Guide]…`. Strip the two-letter-colon prefixes, keep content. Found during U-2; deliberately not fixed "while here". Verify rendered docs afterwards. | DONE | Prefixes introduced by `575a6162` (beginner's-guide commit); restoration verified against `575a6162^` — stripped blocks match the parent exactly where the content pre-existed, and new beginner-guide lines survive the strip intact. 0 mangled lines remain; resulting double-blank pairs collapsed; all links resolve; suite 7535/9 |
| U-11 | — | **Upstream merge campaign** (authorized 2026-09-25, committer access verified maintain+push): docs PRs corrected-then-merged, then our own fleet-validated PRs, smallest-first, #987→#971 last. Per-PR: merge → fork sync → suite → build 4 targets → deploy 4 hosts → 2-turn smoke → ledger. Runbook: [docs/plans/upstream-merge-runbook.md](docs/plans/upstream-merge-runbook.md). One merge per user go. Docker/OrbStack deploy is wave-4 decision (upstream #449 still open) | IN PLAN (wave 0 pre-flight) | Out of scope: third-party code PRs, upstreaming fork-only work, Q1–Q4 |
| U-8 | #978 (Tetraslam, closed unmerged 2026-07-22) | Discord typingLoop ran HTTPS+TLS on the 512KB auxiliary stack → SEGV on first typing indicator (deaf-gateway symptom, upstream #977). Wrap-up salvage: author gave up; fix is a crash-class repair. | DONE | `eb314a68`, applied verbatim (incl. cosmetic websocket.zig cleanup), suite 7545/9. Upstream [notified](https://github.com/nullclaw/nullclaw/pull/978#issuecomment-5798198562) |
| U-9 | #996 (be-student, closed unmerged 2026-09-12; fixes upstream #991) | stdio MCP reads unbounded → a hung server hangs the agent; no process-group cleanup. Directly hardens the OrangePi webdav-mcp dependency. | DONE | `8662764b`, applied verbatim (poll-bounded reads, process-group kill, PeekNamedPipe on Windows, failed-init cleanup, blocked-child test), suite 7546/9. Upstream [notified](https://github.com/nullclaw/nullclaw/pull/996#issuecomment-5798199090) |
| U-10 | #986 (gently-whitesnow, closed unmerged 2026-08-14) | `memory.database_path`: absolute or workspace-relative SQLite location; enables read-only-workspace deployments. | DONE | `6316a2c8`, applied verbatim except the one-line MemoryConfig field insertion (hand-reconciled beside the #979 fields); upstream tests + beginners-guide docs en+zh included, suite 7549/9. Upstream [notified](https://github.com/nullclaw/nullclaw/pull/986#issuecomment-5798199657) |
| — | #965 (mtdphn, closed unmerged 2026-08-03) | Structured streaming tool-call SSE parsing — superseded: this fork's #971 already parses `delta.tool_calls` (`sse.zig`) with `supportsStreamingNativeTools` gating. No intake. | SUPERSEDED (verified) | [Note left upstream](https://github.com/nullclaw/nullclaw/pull/965#issuecomment-5798200267) |

**Deferred / rejected (do not intake without a new user decision):**

- **#969** (approval flow, +11k lines): target region rewritten in `90e4b01c`; merging is now a re-implementation. Keep as a *design reference* only.
- **#980**: redundant — our merged #959 already persists the paired token encrypted (verified in `src/gateway.zig` / `src/cron.zig`). Redundancy note left upstream 2026-09-23 (PR since closed silently): [comment](https://github.com/nullclaw/nullclaw/pull/980#issuecomment-5797867071). All 15 resolved PRs now carry a public provenance comment.
- Tier 3 (opportunistic, no urgency): #990 Eden AI provider, #956 alpine bump, #958 Teams JWT fix, #968 Matrix persistence, #981 grok-cli, #775 CLAUDE.md dedup, #774 doc stats.
- Tier 4 (do not take): #319 DingTalk recall, #667 email/IMAP channel, #411 tool customization (this tree's `tool_filter_groups` cover the need), #982/#983 proxy transports, #989 README chart, #527 megapr (+617k lines).

## Decision queue (needs user philosophy session — raised 2026-09-25 morning)

| ID | Item | Context |
|---|---|---|
| Q1 | **#67 / up-993 Firecrawl endpoint — DEFERRED, do not implement or close yet.** | User is undecided between not-planned and other options pending Q2/Q3. No code changes without explicit approval. |
| Q2 | **Provider philosophy: built-in vs MCP.** Which web-search providers (and by extension other tools) deserve first-class status versus being delegated to MCP? May diverge from upstream (@donprus's direction). User finds Firecrawl unreliable; the Feb 2026 multi-provider rework (`939dc07c`) added nine built-in providers upstream. |
| Q3 | **Binary size.** Original attraction was <1 MB; now ~4.9 MB ReleaseSmall vs the AGENTS.md <1 MB target. Multi-provider search is a suspected contributor (unmeasured). Links to the parked size/RSS internal item. |
| Q4 | **Brave key wiring (verify when back).** User's preferred provider is Brave; fleet configs set `http_request.search_api_key` but provider code reads `BRAVE_API_KEY` from the environment — whether the config field feeds the env lookup is unverified. Brave IS a built-in provider and first keyed slot in the auto chain. |

## Current handoff

> **2026-09-26 update (supersedes the bullets below where they conflict).** Fleet build basis is now `upstream/main` + all open vernonstinebaker code PRs, not fork `main`.
>
> - **New upstream PRs:** **#1010** (`fix/discord-drop-self-authored-messages` — the self-echo guard, +3 tests; this was a documented known follow-up in the WebDAV deployment doc) and **#1011** (`fix/agent-tool-call-parse-leak` — `freeParsedToolCall` + missing `errdefer`s, RED 24 bytes at `ArrayList.append`). Both clean, `MERGEABLE`, based on `upstream/main` `f154dad5`.
> - **Resolved in the PR branches (per conflict policy):** #970 `fix/cli-arrow-keys` (rebuilt from its own 2 commits, dropping stale merge commits), #1004 `fix/provider-http-error-body` (rebased on upstream+#966; `helpers.zig` reconciled to the fork-main form), #1005 `fix/memory-archived-shards` (rebased on upstream+#1001; `memory_loader.zig` matches fork main byte-for-byte). All three pushed (force-with-lease), upstream PRs updated.
> - **Aggregate:** worktree `wt/deploy-upstream-all-prs` on `deploy/upstream-all-prs`; 19 code PRs merged (4 docs-only excluded by policy); suite **7471 passed / 9 skipped, 0 failures, 0 leaks**; `rebuild-all-prs.sh` rewritten to the upstream policy and verified deterministic (identical tree hash on re-run). Script backed up as `rebuild-all-prs.sh.bak-pre-upstream-20260926-174323`.
> - **Fleet deployed 2026-09-26** from that aggregate, `NULLCLAW_VERSION=2026.9.23`, all four hosts health `ok`, two-turn smoke passed on all four. Artifact SHA-256: localhost `8455234144cf05e5…`, OrangePi `2d463d16cace97b8…`, Radxa `2ff69632214de2c0…`, 15t `ec5f45bdd89eea7f…`. Backups on each host: `nullclaw.bak-pre-upstream-allprs-20260926`. 15t was offline during the build and deployed separately once reachable.
> - **Remaining gap to true parity:** upstream PR **#984** (poll-thread aging; third-party, still open — deliberately not duplicated) plus one `session.zig` test expectation tied to #987's behaviour (not standalone-PR-able). #776/#777 docs remain open.
> - **Incidental finding:** localhost's Discord gateway was stuck in a permanent ~64 s reconnect loop that never reached `READY`; the new build (containing #953's connect-grace + socket-shutdown work) reached `READY` on first start.

- **HEAD:** `90e4b01c` (= `origin/main`). Hardening phases 0–8 were committed and pushed as `90e4b01c` by the concurrent session after the previous handoff was written; working tree clean apart from the preserved untracked files.
- **Active task:** upstream intake scope above, in ledger order. Start at the first non-`DONE` row.
- **Standing next action:** none — every ledger row is DONE, DEFERRED (not approved), or SUPERSEDED. 2026-09-24 wrap-up complete: fleet (localhost, OrangePi, Radxa, 15t) deployed from `main` `2efa2d2f` (`NULLCLAW_VERSION=2026.9.23`, no new tag), all four health `ok`, two-turn smoke passed on all four hosts (OrangePi first attempt hit a transient provider `NoResponseContent`, retry passed). **Deployment doc of record: WebDAV `http://100.110.80.108:8080/docs/nullclaw-deployment.md`** (basic-auth creds in `palace/sbc-configs/orangepi.config.json`; canonical build path `NULLCLAW_VERSION=2026.9.23 ~/.nullclaw/workspace/build-all.sh --repo <this checkout>`; 15t deploys automatically when the phone is online). REPL smoke note: stagger the second piped stdin line (`sleep 25`) or it is dropped.
- **Changed files:** none uncommitted. Hardening diff from the previous handoff landed as commit `90e4b01c` (same file list: `src/agent/root.zig`, `src/agent/dispatcher.zig`, `src/agent/loop_guard.zig`, `src/agent/parallel_tools.zig`, `src/agent/result_compress.zig`, `src/config_types.zig`, `src/session.zig`, `docs/en/configuration.md`, `docs/zh/configuration.md`, `PLAN.md`).
- **Validation at `90e4b01c`:** final recorded suite 7,533 passed / 9 skipped (session log below); ReleaseSmall recorded in the P8 note. Re-run the suite before relying on it — concurrent sessions may have advanced HEAD.
- **Pending processes:** none.
- **Known constraints:** the external-content lock still does not cover arbitrary MCP writes. Replay payloads can be truncated or emptied once the turn budget is full; the identity is kept so the action is not run again. Default ReleaseSmall remains about 4.9 MB. This is not an exhaustive provider or security audit.
- **Stop rule:** hardening phases are complete. The upstream intake scope above is active under an explicit user request dated 2026-09-23; stop when its ledger rows are DONE/DEFERRED and the handoff reflects the last pushed commit.

## Session log

| Date | Work / result | Next |
|---|---|---|
| 2026-09-23 | Read Swift ZeroControl/TokenSidebar/llmserverplus planning examples; archived old plan and made this recovery-oriented TDD plan from the current code review | P1.R |
| 2026-09-23 | P1 RED reproduced whitespace policy bypass; resolved-identity fix passes full suite (7,501 passed, 9 skipped) | P2.R1 |
| 2026-09-23 | Confirmed P1 evidence; completed P2 ownership, unconditional joins, shared-state audit and fault tests; 7,506 passed / 9 skipped; ReleaseSmall passes | P3.R |
| 2026-09-23 | Completed P3; default source/data fidelity, bounded UTF-8 shell compression, expired stack reference removed; 7,509 passed / 9 skipped, ReleaseSmall passes | P4.R |
| 2026-09-23 | Completed P4–P8 on the uncommitted tree. Final suite 7,530 passed / 9 skipped. ReleaseSmall default 4,904,856 bytes. External-content lock retained (D6) | review / commit if asked |
| 2026-09-23 | Added full-turn interrupt-between-tools, interrupt-before-summary, and raised-cap replay tests. Suite 7,533 passed / 9 skipped | commit |
| 2026-09-23 | Hardening committed+pushed as `90e4b01c` (concurrent session). Assessed all 19 open third-party upstream PRs against the fork's deployment environments; user authorized intake. Added upstream intake scope (U-1…U-6 + deferred list) to this plan | U-1 RED |
| 2026-09-23 | U-1 #985 landed (`415b54c8`, RED-first, 7535/9). U-2 #776 landed (`29c02d55`, env/header + subagent-limit corrections, narrowing rule documented en+zh). User narrowed approval to #985/#776/#777 only; U-3 #979 and U-5 #984 marked DEFERRED; user requires one PR at a time with check-ins | U-4 (#777) |
| 2026-09-23 | U-4 #777 landed (`59ad630a`, 0.15.2→0.16.0 pin correction). Approved intake scope complete. Posted merged-into-fork comments on upstream #985/#776/#777 and landed-in-fork notes on the fork's nine still-open upstream PRs (#987, #971, #970, #966, #963, #962, #959, #954, #953) — upstream PRs cannot be marked merged (no write access; re-applied commits never trigger GitHub merge detection), so comments are the provenance record. Comment wording later revised per the audience-aware terminology rule (0a) | U-6/U-7 await user decision |
| 2026-09-23 | U-6 core-review statuses landed (`e80c5dfd`); U-7 README prefix repair landed (`521490af`); handoff closed (`119068a4`). User added criteria: PR-number naming, community-first intent; terminology rule recorded (0a/0b) | #979 review |
| 2026-09-23 | #979 approved after benefit/drawback review; groundwork + D7 landed (`80dc85a8`). #979 landed (`72db0008`, RED 6→GREEN 7539/9; upstream notified, ledger `52ce2c72`). #984 approved after pros/cons review; verified fleet channels are gateway_loop (unaffected), taken as community maintenance; landed with patch regression tests + 2 edge tests, 7545/9 | intake backlog empty; tier-3 + internal items on request |
| 2026-09-23 | Upstream activity after the fork's merged-into-fork comments: #979, #980, #969, #981 (all valonmulolli's) closed upstream today, unmerged. **Interpretation caveat (user, 2026-09-23): do not read these closures as a merit verdict.** Verified: all four closed silently — no merge, no closing comment, no maintainer note; the only recent comment on any of them is this fork's #979 notice. Most likely author housekeeping after being reminded. Every intake/parking decision in this plan was made on this fork's own review and is unaffected: #979 remains landed here on its own merits; #969/#981 remain parked for the recorded reasons (not because upstream closed them) — if #969's approval-flow concept is ever wanted, its branch remains fetchable via `gh pr checkout 969` while refs exist. Net disposition of the 30 assessed PRs: 15 resolved by this fork's main (9 vernonstinebaker PRs + #985/#776/#777/#979/#984 intakes + #980 substance via #959); 13 third-party still open and parked (tier-3/4) | — |
| 2026-09-24 | Wrap-up: #980 redundancy note left upstream (provenance set complete for all 15). Reviewed closed-unmerged #978/#965/#986/#996 (none ours; closed Jul 22–Sep 12, not today): took #978 (`eb314a68`), #996 (`8662764b`), #986 (`6316a2c8`); #965 superseded by #971. Issues pass: closed 6 origin mirrors (54, 55, 60, 63, 65, 43 → upstream 915/919/972/976/991/870) with fix references; commented on 10 upstream issues (976, 919, 972, 991, 839, 915, 870, 865, 767, 817) and 4 closed PRs. Suite 7549/9 at `6316a2c8`. Next: release builds, deploy 3 hosts, smoke tests | deploy |
| 2026-09-24 | Deploy: canonical `build-all.sh` from WebDAV runbook (`NULLCLAW_VERSION=2026.9.23`, all four targets incl. Android); 15t was online and auto-deployed; SBCs + localhost redeployed with `.bak-pre-2efa2d2f` backups. All four health `ok`, version `2026.9.23`. Two-turn smoke (file_read → ×23) passed on all four hosts; OrangePi needed one retry (transient bifrost `NoResponseContent`). WebDAV runbook updated with 2026-09-24 changelog + artifact SHAs (backup `.bak-20260924-pre-2efa2d2f`) | session complete |
| 2026-09-24 | Second issue pass (user-directed, "review thoroughly"): closed 14 fork mirrors with evidence — addressed (up 932 docs pin, 631 /status, 190 subagents, 623+871 keyless DDG search, 495 cloudflared, 624 multimodal, 867 example config, 449 docker CI, 613 config docs), answered (914 → MCP), not planned (997/998 paid-hop pitches), stale (473). 7 upstream comments posted. Kept open with verified reasoning: up-992 pairing code is still hidden by design (`gateway.zig:5978` — the earlier "code visible" sighting was a stale memory injection, not current behavior); up-993 firecrawl endpoint still hardcoded (`firecrawl.zig:14`); up-665 NoResponseContent reproduced live on OrangePi today. Created labels `security`/`triage-next`/`intake-candidate`/`needs-decision`/`needs-repro` and tagged 17 open issues for the next session. ~42 mirrors remain open | next session: work `triage-next` first (#30/#47/#67/#14/#72 mirrors) |
| 2026-09-24 | User query: LLM response content visible on 15t/localhost — suspected the engine work lost the `log_llm_io` flag. **Investigated: no regression.** Gate intact (`root.zig:4150/:4190`), proven empirically by the SBCs logging nothing on the same binary with `false` while 15t/localhost had `true` in config. Flipped both to `false` (backups `config.json.bak-20260924-llmio`), restarted 15t gateway + localhost daemon, health `ok`, live turns on both show zero LLM-IO lines with correct replies. Config op recorded in WebDAV runbook + CHECKIN | — |
| 2026-09-24 | Follow-up: re-verified Radxa + OrangePi live configs — `log_llm_io` already `false` on both (no change needed; related observation: `log_message_payloads` is `true` on all four hosts and logs full message content — left as-is, user decision). Diagnostics flags now properly documented en+zh (per-flag semantics, defaults, stderr destination, privacy guidance; example corrected from `log_llm_io: true` to production-safe values). Suite 7549/9 | — |
| 2026-09-26 | User report: fleet bots "off the rails" since the late-Aug/early-Sep LLM config change (bots answering themselves on Discord). RCA: `channels.discord.accounts.default.allow_bots: true` + `require_mention: true` + no self-echo guard — the bot's own reply opened with its own @-mention, so it re-entered the agent loop (8/65 inbound messages were verbatim echoes of its own outbound; persona bleed from one shared per-channel session). The new models (bifrost/auto on the SBCs, glm-5.3-flash locally) made it visible, not caused. Also found localhost's Discord gateway stuck in a permanent ~64 s reconnect loop (never `READY`). | fix |
| 2026-09-26 | Opened **#1010** (`fix/discord-drop-self-authored-messages`, upstream, based on `upstream/main` `f154dad5`): `isSelfAuthored` + ingress filter 0, 3 regression tests, one docs line; suite 7378/9 → 7381/9 on upstream. Opened **#1011** (`fix/agent-tool-call-parse-leak`): `freeParsedToolCall` + 3 missing `errdefer`s, RED 24 bytes at `ArrayList.append`; suite 7381 → 7379/9 pass. Realised upstream is **no longer dormant** (#986/#996/#985 merged 2026-09-24) and that the fork is staging-only — build basis must be `upstream/main` + all open PRs. | aggregate |
| 2026-09-26 | Rebuilt aggregate `wt/deploy-upstream-all-prs` = `upstream/main` + 19 open code PRs (docs excluded). Resolved the 3 conflicts **in the PR branches**: #970 (rebuilt from its 2 own commits, dropping stale merges), #1004 (rebased on upstream+#966, `helpers.zig` reconciled to fork-main form), #1005 (rebased on upstream+#1001, `memory_loader.zig` byte-identical to fork main); pushed force-with-lease. Aggregate suite **7471 passed / 9 skipped, 0 failures, 0 leaks**. `rebuild-all-prs.sh` rewritten to the upstream policy (backup `…bak-pre-upstream-20260926-174323`) and verified deterministic. | deploy |
| 2026-09-26 | Deployed the upstream-based aggregate to all four hosts (`NULLCLAW_VERSION=2026.9.23`); all health `ok`, two-turn smoke passed on all four (SBCs needed one retry each — transient `bifrost/auto` `NoResponseContent`, matching the documented flake). SHAs: localhost `8455234144cf05e5…`, OrangePi `2d463d16cace97b8…`, Radxa `2ff69632214de2c0…`, 15t `ec5f45bdd89eea7f…`; backups `nullclaw.bak-pre-upstream-allprs-20260926`. localhost's Discord gateway reached `READY` on first start (loop gone; #953). Also fixed a stray `core.worktree` in the main checkout's `.git/config` that pointed git at the parse-leak worktree. | docs |
| 2026-09-26 | Tooling bugs found (unfixed, need their own PRs): (1) `.githooks/pre-push` is unusable from any worktree — hooks export `GIT_DIR`/`GIT_INDEX_FILE`, which makes 9 `skills.installSkillFromGit` tests fail (reproduced deterministically); (2) those same skills tests mutate and `git commit` into whatever branch is checked out (author `test <test@example.com>`, subject `init`) — PR #1011 briefly acquired 14 fixture files from this before the branch was rebuilt. | tooling |
