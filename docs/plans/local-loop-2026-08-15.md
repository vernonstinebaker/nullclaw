# PLAN: Local-Optimized Long Agent Loops

| Field | Value |
|---|---|
| **Status** | Phase 0 — complete (ready for PR) |
| **Tracking** | Untracked local handoff (`PLAN.md`) — remove after all phases land or abandon |
| **Base branch** | `main` @ `9967eb9c` (2026-08-15) |
| **Feature branch (suggested)** | `feat/local-loop-phase0` → then `feat/constrained-tool-envelope` |
| **Last plan update** | 2026-08-15 (fleet: 2048 cap interim; P1-8 added) |
| **Reference** | [AtomicBot-ai/atomic-agent](https://github.com/AtomicBot-ai/atomic-agent) (loop design only; no TurboQuant fork) |

---

## How to resume this work (agent handoff)

1. Read this file top to bottom; check **Progress tracker** below.
2. Confirm base: `git fetch origin && git log -1 --oneline origin/main`.
3. Re-check **Upstream PR gate** before starting Phase 1 (§ Phase 1 gate).
4. Run validation after every task group: `zig fmt src/` then `zig build test --summary all`.
5. Update checkboxes and **Session log** at the bottom when stopping.

**Do not** branch from `feat/streaming-native-tools` (#971) or any integration branch.

---

## Goal (one paragraph)

Make small local quantized models survive long, tool-heavy agent loops without turning NullClaw into a llama.cpp client. Atomic Agent’s GAIA L1 gap vs Hermes (69.8 % vs 58.5 %, same model) comes from **loop design**: constrained tool-call envelope, cache-friendly prompt shape, compressed tool results, parallel read batches, loop guards. NullClaw stays **provider-agnostic** — cloud keeps native `tools[]`; local backends opt in via `supportsConstrainedDecoding()`.

---

## Non-goals (do not implement)

- [ ] Vendor TurboQuant or fork llama.cpp
- [ ] Replace the default cloud agent loop
- [ ] Full JSON-Schema→GBNF for every tool argument (envelope only)
- [ ] Managed model downloader / GPU picker
- [ ] Register `reply` in `src/tools/root.zig`
- [ ] Raise default `max_tool_iterations` or `token_limit`

---

## Architecture summary

```
Agent (provider-agnostic)
  ├─ buildStablePrefix() + buildVariableTail()   ← Phase 0 starts this split
  ├─ result_compress / loop_guard / parallel_tools
  ├─ provider-aware compress caps (local 2048 / cloud 8192)   ← Phase 1 (P1-8)
  └─ if provider.supportsConstrainedDecoding():
         ChatRequest.constrained_envelope_schema → provider maps to Ollama format / OpenAI response_format / llama.cpp grammar
     else:
         existing native tools + XML path (unchanged)
```

**Interchange format (Phase 1):** JSON Schema for `[{ "name": string enum, "arguments": object }, …]`. Providers translate; agent never sends GBNF or `slot_id`.

---

## Upstream PR gate (Phase 1 only)

Phase 0 can open **immediately** off current `main`. Phase 1 touches the same files as several open PRs — start Phase 1 only after the gate below.

| PR | Title | Overlap | Phase 1 action |
|---|---|---|---|
| **#971** (draft) | Streaming native tool calls | `src/agent/root.zig`, `src/providers/root.zig`, `sse.zig`, vtable | **Wait** — merges or closes first. Adds `supportsStreamingNativeTools`, `StreamChatResult.tool_calls`, `ChatRequest` streaming path. Rebase Phase 1 on post-#971 `main`. |
| **#969** | Approval request/response flow | `agent/root.zig`, `dispatcher.zig`, `config_types.zig`, +26 files | **Strong wait** if still open when Phase 1 starts — largest conflict surface (+11k lines). Prefer #969 merged or explicitly deferred before Phase 1 branch. |
| **#979** | Memory auto-recall knobs | `agent/root.zig`, `memory_loader.zig`, `config_types.zig` | **Rebase OK** — small; merge #979 first if easy, else resolve mechanically. |
| **#981** | grok-cli provider | `providers/factory.zig`, `providers/root.zig` | No gate — factory conflict only if both touch same enum slot. |
| **#970** | CLI arrow keys | `agent/cli.zig` only | No gate for this plan. |

**Gate rule:** Phase 1 branch opens when **#971 is merged or closed** AND **(#969 is merged OR you accept a large rebase)**. Until then, land Phase 0 only.

Check before Phase 1:

```bash
gh pr view 971 --json state,mergeable,mergeStateStatus
gh pr view 969 --json state,mergeable,mergeStateStatus
git fetch origin && git log -1 --oneline origin/main
```

---

## Progress tracker

| Phase | PR branch | Status | Blocked by |
|---|---|---|---|
| **0** — Loop hygiene | `feat/local-loop-phase0` | ✅ done | — |
| **1** — Constrained envelope | `feat/constrained-tool-envelope` | ⬜ Not started | #971 (+ prefer #969 settled) |
| 2 — llama.cpp provider (optional) | `feat/llamacpp-native-completion` | ⬜ Future | Phase 1 |
| 3 — Prompt budget / memory pointers | — | ⬜ Future | Phase 1 |
| 4 — Eval harness | — | ⬜ Future | Phase 1 |
| 5 — Docs | — | ⬜ Future | Phase 1 |

Legend: ⬜ not started · 🟡 in progress · ✅ done · ⏸ blocked

---

# PHASE 0 — Loop hygiene (start now)

**Risk:** Low–medium · **New provider:** No · **Config breaking:** No (defaults preserve today)

**Outcome:** Every backend (cloud + Ollama + compat local) gets shorter history, optional parallel reads, identical-call protection, and a prompt shape ready for prefix caching in Phase 1.

**Suggested PR title:** `feat(agent): loop hygiene for long local runs (compress, guard, parallel reads)`

---

## P0-1 — Prompt prefix / tail split (datetime out of prefix)

**Why:** `appendDateTimeSection` in `buildSystemPrompt` (`src/agent/prompt.zig` ~L423) embeds wall-clock time to the minute → prefix bytes change every minute → any future KV cache is useless.

### Tasks

- [x] **P0-1a** Add `buildStablePrefix(allocator, ctx) ![]const u8` — everything in current `buildSystemPrompt` **except** datetime and anything that changes every turn (keep conversation context in prefix for now if sender fingerprint already triggers rebuild; document choice in test).
- [x] **P0-1b** Add `buildVariableTail(allocator, ctx) ![]const u8` — start with **Current Date & Time** section only.
- [x] **P0-1c** Refactor `buildSystemPrompt` to `stable ++ tail` (single system message for cloud — behavior preserved).
- [x] **P0-1d** Export `stablePrefixHash(allocator, ctx) !u64` (Wyhash of stable bytes) for Phase 1 tests; use in unit test.
- [x] **P0-1e** Tests in `src/agent/prompt.zig`:
  - Stable hash identical when only clock would differ (mock: call stable builder twice with same ctx).
  - Full `buildSystemPrompt` still contains datetime somewhere.
  - Existing prompt tests still pass.

### Files

| File | Action |
|---|---|
| `src/agent/prompt.zig` | Split builders; move `appendDateTimeSection` to tail |
| `src/agent/root.zig` | No change required if still calls `buildSystemPrompt` |

### Done when

- [x] `zig build test --summary all` clean
- [x] `buildStablePrefix` output has **no** `## Current Date & Time`
- [x] `buildSystemPrompt` output **has** datetime

---

## P0-2 — Tool result compression

**Why:** `dispatcher.formatToolResults` (`src/agent/dispatcher.zig` ~L337) embeds full tool output in history; one `web_fetch`/`shell` blowup kills local context.

### Tasks

- [x] **P0-2a** Create `src/agent/result_compress.zig`:
  - `compressToolOutput(raw: []const u8, opts: CompressOptions) ![]const u8`
  - Keep last N non-blank lines (default 12), prepend error signature line if status error (`error:`, `Traceback`, etc.)
  - Hard cap chars (default 8192 when `local_loop` off; use 400 when local_loop on — config in P0-5)
  - Suffix `\n… [truncated]` when clipped
- [x] **P0-2b** Wire in `Agent.turn` **after** `executeTool`, **before** `formatToolResults` (compress `result.output` in arena for history only; observer logs unchanged policy).
- [x] **P0-2c** Tests: empty input, long grep output, error with signature, UTF-8 boundary at cap.

### Files

| File | Action |
|---|---|
| `src/agent/result_compress.zig` | **new** |
| `src/agent/root.zig` | Call compressor in tool loop ~L2750–2810 |
| `src/root.zig` or `src/agent/root.zig` | Re-export if needed for tests |

### Done when

- [x] 10 KB fake tool output in history ≤ configured cap
- [x] No secrets logged (compress after redaction path unchanged)

---

## P0-3 — Loop guard (identical tool calls)

**Why:** Only in-turn dedup exists (`seen_tool_call_results` in `Agent.turn` ~L2185). Local models repeat same call across steps.

### Tasks

- [x] **P0-3a** Create `src/agent/loop_guard.zig`:
  - `LoopGuard` struct with `record(name, args_json) -> enum { ok, warn, veto }`
  - Fingerprint: Wyhash of `name` + `args_json`
  - Defaults: warn @ 3, veto @ 5 (configurable in P0-5)
  - `consecutive_vetoes: u32` — at 3, return `force_reply` signal
- [x] **P0-3b** Persist guard on `Agent` (or per-turn state cleared at turn end — **per session across steps within one turn**).
- [x] **P0-3c** On `warn`: prepend one-line notice to next tool-result user message (not stable prefix).
- [x] **P0-3d** On `veto`: skip `executeTool`, synthetic error result `"Skipped: identical tool call repeated N times"`.
- [x] **P0-3e** On `force_reply`: break tool loop, append user-visible stuck summary (reuse iteration-exhausted pattern ~L2826).
- [x] **P0-3f** Tests: 3 same calls → warn text present; 5 → skip execute; 3 vetoes → forced exit (force_reply covered by `loop_guard.zig` unit test).

### Files

| File | Action |
|---|---|
| `src/agent/loop_guard.zig` | **new** |
| `src/agent/root.zig` | Integrate before `executeTool` |

---

## P0-4 — Honor `agent.parallel_tools`

**Why:** `config_types.zig` L385 `parallel_tools: bool = false` is parsed in `config_parse.zig` but **never read** in `src/agent/` (verified: no matches in `agent/root.zig`).

### Tasks

- [x] **P0-4a** Add `parallel_tools: bool` to `Agent` (from config in init).
- [x] **P0-4b** Add static readonly allowlist (comptime array): `file_read`, `file_read_hashed`, `memory_recall`, `memory_list`, `memory_search`, `web_fetch`, `web_search`, `sqlite_query` — **not** `git_operations` (mixed read/write) in v1.
- [x] **P0-4c** In tool batch execution (~L2730): if `parallel_tools` and **all** calls in batch are allowlisted, execute via sequential for v1 **or** document thread-pool defer — **minimum viable:** parallel only when batch size > 1 and all allowlisted; use existing sync execute in loop first, add `std.Thread` pool only if tests prove need (YAGNI: start sequential batching flag that **groups** results, true parallelism optional sub-task P0-4d).
- [x] **P0-4d** *(Optional stretch)* Thread pool max 4 for allowlisted reads only; join before history append.
- [x] **P0-4e** Test: with `parallel_tools=true`, two `file_read` calls in one response both execute (mock/stub tools).

**Note:** NullClaw parses XML/native one-by-one today. Parallelism applies when provider returns **multiple** calls in one assistant message. Native multi-call already parsed in `parseStructuredToolCalls` / XML multi-tag path — verify and test.

### Files

| File | Action |
|---|---|
| `src/agent/root.zig` | Read flag; batch execution branch |
| `src/config.zig` | Ensure agent init passes `parallel_tools` (likely already) |

---

## P0-5 — Config bundle `agent.local_loop` (Phase 0 subset)

**Why:** Single place for limits; Phase 1 extends same struct.

### Tasks

- [x] **P0-5a** Add to `src/config_types.zig`:

```zig
pub const LocalLoopConfig = struct {
    enabled: bool = false,  // Phase 1 sets meaning; Phase 0 ignores except compress defaults
    max_result_chars: u32 = 8192,       // 400 when enabled=true in Phase 1
    max_result_tail_lines: u32 = 12,
    identical_call_warn: u32 = 3,
    identical_call_veto: u32 = 5,
    identical_call_force_reply: u32 = 3,
    max_parallel_readonly: u32 = 4,
};
// AgentConfig.local_loop: LocalLoopConfig = .{},
```

- [x] **P0-5b** Parse in `config_parse.zig` under `agent.local_loop`.
- [x] **P0-5c** Wire compress + loop_guard from config (when `enabled`, use 400 char cap; else 8192 or unlimited — pick 8192 default).
- [x] **P0-5d** Config round-trip test in `config.zig`.

### Files

| File | Action |
|---|---|
| `src/config_types.zig` | `LocalLoopConfig` |
| `src/config_parse.zig` | Parse |
| `src/config.zig` | Test |
| `src/agent/root.zig` | Read limits |

---

## Phase 0 — Validation checklist

Run before opening PR:

```bash
zig fmt src/
zig fmt --check src/
zig build test --summary all          # 0 failures, 0 leaks
zig build -Doptimize=ReleaseSmall     # still builds
```

Manual smoke (optional):

1. `nullclaw agent` with Ollama/local model, run tool-heavy turn with large `file_read`.
2. Confirm history does not contain full 50 KB file content.
3. Repeat same tool call 5× — see veto/skip behavior.

### Phase 0 PR checklist

- [ ] All P0-1 … P0-5 tasks checked
- [ ] No new dependencies
- [ ] Cloud default behavior unchanged (`local_loop.enabled=false`)
- [ ] AGENTS.md test mandate satisfied (every behavior change has test)
- [ ] PR description links this PLAN.md section

---

# PHASE 1 — Constrained tool envelope (wait for PR gate)

**Risk:** Medium–high · **Start after:** #971 merged/closed; **prefer** #969 merged

**Outcome:** When `agent.local_loop.enabled=true` (or `"auto"` + provider capability), the model must emit a JSON **array** of `{name, arguments}`; parser accepts it; `reply` terminates loop; providers map schema — **no GBNF in agent code**.

**Suggested PR title:** `feat(agent): provider-agnostic constrained tool-call envelope`

**Do not implement in Phase 1:** `src/providers/llamacpp.zig`, `slot_manager`, GBNF compiler in agent (defer to Phase 2 optional).

---

## P1-0 — Rebase and conflict prep

- [ ] **P1-0a** `git fetch origin && git checkout -b feat/constrained-tool-envelope origin/main`
- [ ] **P1-0b** Merge or rebase completed Phase 0 PR first (Phase 1 stacks on Phase 0).
- [ ] **P1-0c** If #971 landed: read `supportsStreamingNativeTools` / `StreamChatResult.tool_calls` — constrained mode uses **non-streaming** path only in v1.
- [ ] **P1-0d** If #969 landed: read approval hooks in `Agent.turn` — constrained path must not bypass approval for gated tools.

---

## P1-1 — Envelope JSON Schema builder

### Tasks

- [ ] **P1-1a** Create `src/agent/constrained_envelope.zig` (or `src/grammar/envelope_schema.zig`):
  - Input: `[]const ToolSpec` + include `reply` synthetic name
  - Output: owned JSON Schema string for array of `{ name: enum, arguments: object }`
  - Max array length 16 (match Atomic)
  - `arguments` uses generic `"type":"object"` per tool (no per-arg schema in v1)
- [ ] **P1-1b** Snapshot test: fixed tool set → stable schema string hash.

### Files

| File | Action |
|---|---|
| `src/agent/constrained_envelope.zig` | **new** |

---

## P1-2 — Provider vtable + ChatRequest (provider layer only)

### Tasks

- [ ] **P1-2a** Extend `ChatRequest` in `src/providers/root.zig`:

```zig
constrained_envelope_schema: ?[]const u8 = null,  // JSON Schema; agent sets when local_loop active
```

- [ ] **P1-2b** Add optional vtable method (default false / no-op):

```zig
supportsConstrainedDecoding: ?*const fn (ptr: *anyopaque) bool = null,
```

- [ ] **P1-2c** `Provider.supportsConstrainedDecoding()` wrapper — default `false`.
- [ ] **P1-2d** Delegate in `router.zig`, `reliable.zig`.

**Coordination:** If #971 added vtable fields nearby, add **after** rebase; do not duplicate streaming slots.

---

## P1-3 — Ollama provider: `format` field

### Tasks

- [ ] **P1-3a** In `ollama.zig` `buildChatRequestBody`: when `request.constrained_envelope_schema != null`, set `"format": <schema>` (Ollama JSON schema mode).
- [ ] **P1-3b** `supportsConstrainedDecoding` → `true` for Ollama.
- [ ] **P1-3c** Parse response: if content is JSON array string, feed through new parser (P1-4).
- [ ] **P1-3d** Tests: request body contains `format` iff schema set; mock response `[{"name":"file_read",...}]`.

### Files

| File | Action |
|---|---|
| `src/providers/ollama.zig` | format + capability |
| `src/providers/factory.zig` | unchanged classify |

---

## P1-4 — Compatible provider: `response_format` / extra_body

### Tasks

- [ ] **P1-4a** In `compatible.zig` `buildChatRequestBody`: when schema set, append `"response_format":{"type":"json_schema","json_schema":{...}}` (OpenAI shape) **or** document vLLM `guided_json` via `extra_body_params` for known locals.
- [ ] **P1-4b** `supportsConstrainedDecoding` → `true` only when config flag `provider.constrained_decoding: true` or auto-detect localhost URL (conservative: opt-in per provider entry first).
- [ ] **P1-4c** Tests: lmstudio/vllm localhost fixture URL gets schema in body when enabled.

---

## P1-5 — Dispatcher: parse tool-call array

### Tasks

- [ ] **P1-5a** Add `parseConstrainedToolCallArray(allocator, response_text) !ParseResult` in `dispatcher.zig`:
  - Expect top-level JSON array
  - Each element: `name` + `arguments` (object or JSON string)
  - Map `name == "reply"` → terminal (no execute; extract `arguments.text` or `arguments` string field)
- [ ] **P1-5b** Integrate in `parseToolCalls` **before** XML fallback when `local_loop` active OR when response starts with `[`.
- [ ] **P1-5c** Reject unknown tool names at execute time (existing registry) — parser may accept, executor denies.
- [ ] **P1-5d** Tests: array of 3 calls, solo `[{...}]`, bare `{` rejected, `reply` terminates.

### Files

| File | Action |
|---|---|
| `src/agent/dispatcher.zig` | New parser + tests |

---

## P1-6 — Agent loop integration

### Tasks

- [ ] **P1-6a** Create `src/agent/local_loop.zig`:
  - `shouldUseConstrainedLoop(agent, provider) bool` — `local_loop.enabled` or auto + `supportsConstrainedDecoding()`
  - `buildConstrainedSchema(allocator, tool_specs) ![]const u8`
- [ ] **P1-6b** In `Agent.turn` tool loop (~L2200):
  - If constrained: set `request.constrained_envelope_schema`, **disable native tools** (`tools = null`), use blocking `chat` (not streaming) in v1
  - Use `buildStablePrefix` + tail for messages (prefix in system msg; tail sections appended — full raw prompt deferred to Phase 2 llama.cpp)
- [ ] **P1-6c** Add array-only instructions to stable prefix when constrained (examples for `[{...}]`, parallel reads, `reply`).
- [ ] **P1-6d** On `reply` call: return text to user, exit tool loop.
- [ ] **P1-6e** Tests: mock provider returns array; loop executes tools; `reply` ends turn.

### Files

| File | Action |
|---|---|
| `src/agent/local_loop.zig` | **new** |
| `src/agent/root.zig` | Branch in turn loop |
| `src/agent/prompt.zig` | Constrained instructions block |

**Conflict hotspots with #971 / #969:** `Agent.turn` streaming gate, tool propagation — resolve manually after rebase.

---

## P1-7 — Config: enable local_loop

### Tasks

- [ ] **P1-7a** `local_loop.enabled`: `false | true` (string `"auto"` optional stretch — check provider in runtime).
- [ ] **P1-7b** When `enabled=true` and `max_result_chars` unset, default `max_result_chars=400` (aggressive local-only default). **Interim fleet policy (2026-08-15):** all hosts run `enabled: true`, `max_result_chars: 2048` until P1-8 ships provider-aware caps.
- [ ] **P1-7c** Document in PR body; full docs in Phase 5.

---

## P1-8 — Provider-aware tool result compression caps

**Why:** Phase 0 applies one global `max_result_chars` per gateway. `local_loop.enabled` only toggles the aggressive 400-char substitution when `max_result_chars` is still the struct default (8192); it does **not** distinguish Ollama/local vs cloud providers. Today every model on a host shares the same cap — fleet runs **2048 fleet-wide** as a compromise until this task lands.

**Goal:** Same config, different caps by active provider — **2048** for local/constrained backends, **8192** for cloud — without per-host config edits when switching models.

### Tasks

- [ ] **P1-8a** Add `compressCapForProvider(agent, provider) u32` in `src/agent/local_loop.zig` (or helper on `Agent`): when `local_loop.enabled`, use `local_max_result_chars` (default 2048) for providers where `supportsConstrainedDecoding()` is true or provider is classified local (Ollama, localhost compat); else use `cloud_max_result_chars` (default 8192).
- [ ] **P1-8b** Wire `toolResultCompressOptions` in `src/agent/root.zig` through the helper instead of a single global `max_result_chars`.
- [ ] **P1-8c** Extend `LocalLoopConfig` in `src/config_types.zig`:

```zig
local_max_result_chars: u32 = 2048,
cloud_max_result_chars: u32 = 8192,
```

Keep `max_result_chars` as an optional explicit override for both (when set, bypasses provider split — document semantics).

- [ ] **P1-8d** Parse in `config_parse.zig`; round-trip test in `config.zig`.
- [ ] **P1-8e** Unit tests: mock Ollama provider → 2048 cap; mock OpenRouter → 8192; explicit `max_result_chars` override wins.
- [ ] **P1-8f** Docs (`docs/en/configuration.md` + zh): explain provider-aware caps; note removal of fleet-wide 2048 workaround once shipped.

### Files

| File | Action |
|---|---|
| `src/agent/local_loop.zig` | **new** helper (may share file with P1-6 gating) |
| `src/agent/root.zig` | `toolResultCompressOptions` uses provider split |
| `src/config_types.zig` | `local_max_result_chars` / `cloud_max_result_chars` |
| `src/config_parse.zig` | Parse new keys |

### Done when

- [ ] One gateway with cloud primary + Ollama fallback applies 8192 vs 2048 per active provider without config hot-swaps.
- [ ] Fleet can drop explicit `max_result_chars: 2048` and rely on defaults after deploy.

---

## Phase 1 — Validation checklist

```bash
zig fmt --check src/
zig build test --summary all
zig build -Doptimize=ReleaseSmall
```

Manual:

1. Ollama: `ollama pull qwen2.5:7b` (or similar), config `"local_loop":{"enabled":true}`, provider `ollama`.
2. Ten-step file/read task — valid JSON array each step, no XML fallback.
3. Cloud provider with `enabled=false` — zero behavior change.

### Phase 1 PR checklist

- [ ] Phase 0 merged first
- [ ] #971 gate satisfied (note PR number in commit message)
- [ ] No `grammar` / `slot_id` / `llamacpp` imports in `src/agent/`
- [ ] Tests for schema builder, Ollama body, dispatcher array, turn integration

---

# PHASE 2+ (outline only — not scheduled)

| Phase | Scope | Depends on |
|---|---|---|
| **2** | Optional `src/providers/llamacpp.zig` native `/completion`, GBNF inside provider, `slot_manager` | Phase 1 |
| **3** | Prompt token budgets, memory-as-pointers, skill bodies in tail | Phase 1 |
| **4** | `eval/` tool-call validity bench (no GAIA badge until measured) | Phase 1 |
| **5** | `docs/en/configuration.md` + zh, `doctor` capability probe | Phase 1 |

---

## Key file map (all phases)

| Path | Phase | Purpose |
|---|---|---|
| `src/agent/prompt.zig` | 0, 1 | Prefix/tail; constrained instructions |
| `src/agent/result_compress.zig` | 0, 1 | Tool output truncation; provider cap selection (P1-8) |
| `src/agent/loop_guard.zig` | 0 | Identical call detection |
| `src/agent/local_loop.zig` | 1 | Mode gating; provider-aware compress caps (P1-8) |
| `src/agent/constrained_envelope.zig` | 1 | JSON Schema builder |
| `src/agent/dispatcher.zig` | 1 | Array parser |
| `src/agent/root.zig` | 0, 1 | Turn loop wiring |
| `src/providers/root.zig` | 1 | ChatRequest + vtable |
| `src/providers/ollama.zig` | 1 | `format` schema |
| `src/providers/compatible.zig` | 1 | `response_format` |
| `src/config_types.zig` | 0, 1 | `LocalLoopConfig` |

---

## Security reminders (all phases)

- Constrained decoding ≠ permission bypass — policy/sandbox still apply in `executeTool`.
- `reply` is loop-internal only; never register as a Tool.
- Do not log schema bodies with user content, tool args, or secrets.
- Unknown tool names from model: fail closed at execution.

---

## Relationship to streaming native tools (#971)

Complementary, not duplicate:

- **#971:** SSE `delta.tool_calls` for providers that already speak native tools while streaming.
- **This plan:** Non-streaming constrained JSON array for tiny models that break native/XML formats.

Constrained local mode v1 should use **blocking** `chat()`. Streaming + grammar is Phase 2+.

---

## Session log

| Date | Agent / note | Completed | Next |
|---|---|---|---|
| 2026-08-15 | Plan rewritten — trackable Phase 0/1, PR gate, provider-agnostic Phase 1 | — | Start P0-1a on `feat/local-loop-phase0` |
| 2026-08-15 | Phase 0 implemented TDD on `feat/local-loop-phase0` | P0-1…P0-5 (except P0-4d thread pool) | Open PR; wait for #971 before Phase 1 |
| 2026-08-15 | P0-4d parallel read-only batch executor | Slot-ordered thread pool; policy gate mutex | Open PR |
| 2026-08-15 | PR #987 rebased on `main`; fleet enabled `local_loop` | `enabled: true`, `max_result_chars: 2048` on all hosts (interim) | P1-8 provider-aware caps; wait for #971 before Phase 1 branch |

*(Append a row when stopping mid-phase.)*

---

## Quick command reference

```bash
# Start Phase 0
git fetch origin
git checkout -b feat/local-loop-phase0 origin/main

# Validate
zig fmt src/ && zig build test --summary all

# Before Phase 1
gh pr view 971 --json state
gh pr view 969 --json state
```
