# NullClaw core review — 2026-09-23

Review began at `82c88e8d8fdc17268aa24ee713c0ee0cba78a797` and was updated through `10231364fb58628dfd7c429afe5eba0a17289773` after concurrent commits arrived. Particular attention went to `6a1b5466` (loop hygiene), streaming tool execution, compaction, replay caching, and turn persistence. This is a focused source review of the agent engine and its immediate boundaries, not an exhaustive audit of every provider, channel, or tool. No repository source or configuration was changed by this review. Source locations below refer to the final reviewed commit.

## Findings

### 1. P1 — Normalized tool lookup can bypass session exec restrictions

`src/agent/root.zig:3564–3601`; `src/agent/commands.zig:5308–5317`; `src/agent/dispatcher.zig:379–385`.

`executeToolBody` trims the supplied tool name when resolving a tool, but passes the original `call.name` to `isExecToolName`. The latter only performs a case-insensitive equality check against `shell`. Native parsing preserves whitespace. Consequently a native call named `" shell "` resolves to the shell implementation but skips `execBlockMessage`, including `/exec security=deny` and `ask=always`. This does not bypass the shell implementation's separate configured security policy; it bypasses the session's additional restrictions.

Use the resolved registered tool name for policy decisions and execution identity. Add native-call regression tests with whitespace around shell under deny and approval-required settings, using a counting stub to prove execution never occurs.

### 2. P1 — Parallel workers allocate into a shared, unsynchronized arena

`src/agent/root.zig:3300–3314`, `3419–3423`.

Every worker receives the same iteration arena and concurrently calls `parent_arena.dupe`. ArenaAllocator mutates its own allocation metadata without locking; thread safety of its backing allocator does not make the arena thread-safe. Concurrent completions can overlap result storage or corrupt arena state. The existing mutex protects only `checkToolPolicyGate`.

Keep result ownership inside each worker until all workers have joined, then transfer results into the parent arena on the coordinating thread. Also audit shared tool implementations and verbose redaction before claiming that the name-based read-only allowlist is a thread-safety guarantee. `executeToolBody` can call the shared, stateful Redactor through verbose diagnostics.

### 3. P1 — Parallel error exits leave workers running against expired storage

`src/agent/root.zig:3417–3429`.

If a later `Thread.spawn` fails, earlier workers are never joined. Similarly, returning after observing one worker's error skips joining the remaining workers. Unwinding can free the iteration arena, parsed calls, worker contexts, and stack mutex while those workers still use them.

Track the number of started threads and install unconditional join cleanup immediately. Join all workers before propagating any worker error. Cover partial spawn failure and output-allocation failure with deterministic injection. This is separate from the shared-arena race and needs its own regression coverage.

### 4. P1 — Default output compression changes the evidence supplied to the model

`src/agent/root.zig:3070–3089`; `src/agent/result_compress.zig:25–80`.

Compression runs for every tool even with `local_loop.enabled=false`. The flag only changes the default byte cap. `extractTail` removes indentation and blank lines, and retains only the last 12 nonempty lines regardless of whether the result is below 8,192 bytes. Thus a small Python/YAML file loses meaningful whitespace, and a short multi-line source file can lose its declarations. This also contradicts the documentation that omitting local_loop preserves existing behavior.

Preserve exact source/data results by default. Make lossiness explicit and appropriate to tool semantics: tail extraction is useful for verbose command logs, but unsuitable as a universal transformation for file reads, structured data, or retrieved evidence. When truncation is necessary, retain an explicit indication and a way to retrieve omitted content.

Isolated probes against copied source reproduced both indentation loss and removal of an important leading line below the byte cap.

### 5. P1 — Error-signature matching reads a returned stack slice

`src/agent/result_compress.zig:88–105`.

`stackLowerAscii` returns a slice into its local `[256]u8` buffer. `extractErrorSignature` reads that slice after the helper returns. This is a dangling reference; inlining can conceal it in some builds. A probe forcing a real function call reproduced corrupted contents.

Place the buffer in the caller, return a value struct containing the buffer and length, or use a direct case-insensitive search. The separate 180-byte signature truncation should also preserve UTF-8 boundaries.

### 6. P1 — Enabled response caching can skip requested actions and reuse stale context

`src/agent/root.zig:2284–2293`, `2704–2714`; `src/memory/lifecycle/cache.zig:98–119`.

The key includes model, system prompt, and current user text, but not conversation history or retrieved memory. The final-response branch also caches answers after earlier tool iterations, despite its comment saying only direct responses are cached. Repeating an action request can therefore return an earlier completion without running the action again. The same follow-up text in different conversational states can receive the same cached answer.

Response caching is disabled by default, which limits default exposure. Keep it disabled until eligibility excludes action/tool turns and the cache key reflects the relevant conversational inputs. Test repeated action requests, identical follow-up text after different prior messages, and retrieved-memory changes.

### 7. P2 — Signature-based tool replay caching returns stale reads after writes

`src/agent/root.zig:2967–2981`, `3000–3035`, `3136–3144`.

Calls without native IDs are deduplicated for the entire turn by name and raw argument string. A successful `file_read(path)` followed by `file_write(path)` and then the same read returns the first read's cached output. This undermines read-edit-verify loops, especially on the XML fallback path. Repeated polling can similarly stop observing external changes.

Separate exact replay identity from intentional repeated calls. Preserve validated native-ID replay protection, but avoid caching arbitrary successful no-ID calls across state changes. Add a read/write/read test and repeated polling test. Validate that a reused native ID still has the same tool name and arguments before treating it as an exact replay.

### 8. P2 — MCP narrowing overrides configured always-on tools and loses follow-up context

`src/agent/root.zig:2017–2040`, `2345–2351`.

The latest commits apply a second unconditional MCP filter after the configured tool-group filter. It only matches name tokens of at least five characters against the original current user message and keeps at most 16 matching tools. Thus a tool explicitly included by an `always` group is still removed if its name tokens do not appear in that message. Follow-ups such as `continue` lose previously relevant MCP schemas, and mid-turn injected instructions do not affect this selection. This changes configured availability based on a brittle lexical heuristic.

Honor explicit always groups, preserve the relevant prior tool set for follow-ups, and provide a bounded discovery path when no schema matches. Cover configured always tools, short server names, pronoun-only follow-ups, and injected messages.

### 9. P2 — Loop-guard termination bypasses normal history finalization

`src/agent/root.zig:2743`, `2758–2768`, `3485–3488`; `src/agent/turn_persistence.zig:11–15`.

The assistant's tool-call message is appended before execution. A force-reply exits immediately, before recording collected results or adding the guard's final reply. The last history entry remains the tool-call assistant message. Persistence chooses that last assistant entry over the actual returned guard reply, so a restored session can contain the attempted tool call as its answer instead of the stop explanation. Earlier tools in a mixed batch may already have executed, but their results are lost from history.

Finalize completed/skipped tool results and append the stop response before returning. Prefer a shared finalization path for normal completion, interruption, iteration exhaustion, and guard termination. Test both immediate termination and termination after a successful earlier tool in the batch, then persist and reload.

## Additional hardening opportunities

- Loop fingerprints hash raw JSON, so argument key reordering or insignificant whitespace evades repetition counting. The isolated probe confirms this. Normalize parsed arguments if the guard is intended to detect equivalent calls, while preserving distinction between actual values. Alternating already-vetoed calls also resets consecutive veto tracking. Treat this as a bounded-run quality improvement, not a security boundary; the iteration cap remains in place.
- An explicitly small `max_result_chars` can be exceeded by the truncation marker itself. A cap of 1 produces more than 1 byte. An isolated probe confirms this.
- Provider response ownership is manually released on selected exits. After a successful provider call, intervening allocation/parse errors can return without `freeResponseFields`. Establish one scoped cleanup and add allocation-failure coverage for whole turns, beyond the existing constructor checks.
- The parallel overlap test increments its stub's plain `exec_count` concurrently, which is itself a data race. Make the counter atomic and add failure-path tests; successful overlap/order checks cannot establish safe worker lifetimes.
- Raw outputs are retained in the per-turn dedup cache before compression. History compression does not bound total turn memory. The latest commits reduce the default iteration budget from 1,000 to 32, which helps, but user overrides and large result batches still need a byte budget or a smaller retained representation.
- The terminal iteration-limit summary uses `self.model_name`, not the active `turn_model_name`. Preserve active routing and token-budget choices through recovery/finalization.

## Changes that improved during review

The concurrent changes extract a shared provider-dispatch helper, extend context-exhaustion recovery to streaming, lower the default iteration budget to 32, shorten follow-through instructions, and add full-turn tests. The initial streaming-recovery finding is therefore resolved in the final reviewed source. The memory-safety, output-fidelity, caching, and finalization findings above remain present.

The new external-content write lock also needs a product-level decision: it blocks even an authorized research-then-save workflow for the rest of the turn, while its hard-coded mutator list does not cover arbitrary MCP tools. Do not treat this list as a complete prompt-injection boundary. This is a design concern rather than a separately reproduced defect in this review.

## Validation and scope limits

- Zig 0.16.0, macOS arm64.
- `zig build test --summary all`: rerun at final reviewed HEAD, exit 0, 13/13 steps succeeded, 7,500 passed, 9 skipped, no reported allocator leaks. Initial sandbox execution could not bind localhost test sockets; the successful runs had the required access. Current full log: `/tmp/nullclaw-core-review-tests-current.log`.
- Main test executable MaxRSS: 344 MB, above AGENTS.md's stated 50 MB test target. This is test-process peak memory, not a measurement of production steady-state RSS.
- `zig build -Doptimize=ReleaseSmall --global-cache-dir /tmp/nullclaw-core-review/global-cache --prefix /tmp/nullclaw-core-review/release`: rerun successfully at final reviewed HEAD. Default macOS binary is 4,885,880 bytes (about 4.66 MiB), above the stated sub-1 MB target. Feature/platform configuration may differ from published measurements; define a reproducible target profile before comparing release claims.
- Five new isolated probes fail as expected: default indentation preservation, preservation of leading content under the byte cap, a small explicit cap, equivalent-JSON loop detection, and lifetime of the lowercase helper result. The harness imports copied current compressor/guard/util source; the added lifetime test is in the copied compressor. These probes do not modify repository files. They demonstrate specific defects/gaps, not full integration coverage. See `/tmp/nullclaw-core-review/regression-results.log` and `/tmp/nullclaw-core-review/src/review_tests.zig`.
- Concurrency and policy findings are source-traced; no exploit execution, external provider calls, or stress-race reproduction was performed.

## Recommended sequence

1. Fix tool identity normalization and the parallel ownership/join defects. Keep parallel_tools disabled until validated.
2. Restore lossless default tool output and remove the dangling stack slice.
3. Correct replay/cache semantics and finalize interrupted/guard-stopped turns consistently.
4. Preserve explicit MCP availability and make pre-dispatch context budgeting consistent, then measure long tool-heavy runs and enforce explicit resource budgets.

The vtable boundaries and existing tests are worth keeping. Prioritize these small, independently testable fixes before decomposing the large Agent implementation. A later extraction of request/recovery policy and turn finalization should follow verified behavior, rather than move the current inconsistencies into new files.
