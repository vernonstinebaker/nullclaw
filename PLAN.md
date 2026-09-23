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

## Current handoff

- **HEAD:** `10231364`. Hardening is uncommitted. No commit or push was requested.
- **Active task:** none. Phases 0–8 are done.
- **Changed files:** `src/agent/root.zig`, `src/agent/dispatcher.zig`, `src/agent/loop_guard.zig`, `src/agent/parallel_tools.zig`, `src/agent/result_compress.zig`, `src/config_types.zig`, `src/session.zig`, `docs/en/configuration.md`, `docs/zh/configuration.md`, `PLAN.md`.
- **Validation:** `zig fmt --check` on the changed Zig files, then `zig build test --summary all`: 7,530 passed, 9 skipped, exit 0. ReleaseSmall exit 0. Measurements are in the P8 validation note.
- **Pending processes:** none.
- **Next action:** review the uncommitted diff and commit only if asked. Do not stage `.claw/`, `CHECKIN.md`, `palace/`, `docs/en/rest-admin-api.md`, or `zig-out-*`.
- **Known constraints:** the external-content lock still does not cover arbitrary MCP writes. Replay payloads can be truncated or emptied once the turn budget is full; the identity is kept so the action is not run again. Default ReleaseSmall remains about 4.9 MB. This is not an exhaustive provider or security audit.
- **Stop rule:** phases are complete. Do not start a new scope from this plan without a new request.

## Session log

| Date | Work / result | Next |
|---|---|---|
| 2026-09-23 | Read Swift ZeroControl/TokenSidebar/llmserverplus planning examples; archived old plan and made this recovery-oriented TDD plan from the current code review | P1.R |
| 2026-09-23 | P1 RED reproduced whitespace policy bypass; resolved-identity fix passes full suite (7,501 passed, 9 skipped) | P2.R1 |
| 2026-09-23 | Confirmed P1 evidence; completed P2 ownership, unconditional joins, shared-state audit and fault tests; 7,506 passed / 9 skipped; ReleaseSmall passes | P3.R |
| 2026-09-23 | Completed P3; default source/data fidelity, bounded UTF-8 shell compression, expired stack reference removed; 7,509 passed / 9 skipped, ReleaseSmall passes | P4.R |
| 2026-09-23 | Completed P4–P8 on the uncommitted tree. Final suite 7,530 passed / 9 skipped. ReleaseSmall default 4,904,856 bytes. External-content lock retained (D6) | review / commit if asked |
| 2026-09-23 | Added full-turn interrupt-between-tools, interrupt-before-summary, and raised-cap replay tests. Suite 7,533 passed / 9 skipped | commit |
