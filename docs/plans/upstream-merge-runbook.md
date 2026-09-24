# Upstream Merge Runbook — vernonstinebaker as committer

Authorized 2026-09-25. Premises: committer access verified on `nullclaw/nullclaw`
(`maintain` + `push`, no admin); the working agreement applies in full — **one
upstream merge per explicit user go, check-in between PRs, no unapproved
changes**. This campaign merges only documentation PRs and vernonstinebaker's
own fleet-validated PRs. Third-party code PRs, upstreaming fork-only work, and
the philosophy items (PLAN.md Q1–Q4) are explicitly out of scope.

Why merging upstream PRs still needs fleet validation: the merge changes
upstream `main`, and conflict resolution can break things even when each PR is
individually green. Every code merge is therefore synced into the fork, built,
deployed, and smoked exactly like a normal fleet release.

## Standing per-PR loop

**Code PRs** (all steps, in order):

1. Pre-flight: PR CI green, mergeable, no force-push since review.
2. Merge upstream (merge commit, not squash — preserves PR history).
3. Sync: `git fetch upstream && git merge upstream/main` on fork `main`;
   resolve nothing mechanically — if anything conflicts, stop and report
   (fork main already contains this PR's content; a conflict means the merge
   introduced a real difference).
4. `zig build test --summary all` — 0 failures, 0 leaks.
5. Build: `NULLCLAW_VERSION=2026.9.23 ~/.nullclaw/workspace/build-all.sh
   --repo <this checkout>` (4 targets; 15t auto-deploys when online).
6. Deploy + health: SBCs via scp/atomic-swap/systemd restart, localhost via
   codesign + `launchctl kickstart`; `curl /health` on every host.
7. Smoke: two-turn tool-using REPL check per host (staggered stdin; fixture
   file pattern per the WebDAV deployment runbook). 15t only when reachable.
8. Record: PLAN.md ledger row, commit, push.
9. Rollback if anything fails: revert the upstream merge commit (GitHub
   revert-PR or `git revert -m 1`), fleet rolls back via `.bak-pre-*` binaries.

**Docs-only PRs** — *flagged decision, awaiting user confirmation*: a
docs merge cannot change the binary, so rebuild/redeploy is a no-op by
construction. Proposed loop: merge (with corrections, below) → suite as a
compile guard → reference/link verification → ledger row → commit/push. Full
build/deploy/smoke resumes with the first code PR. (User asked for deploy per
PR; physics says docs cannot alter the artifact — confirm the skip.)

## Wave 0 — pre-flight (no merges)

- [x] Courtesy note to donprus — done via Discord by the user (2026-09-25).
- [x] Maintainer-edit permission: **true on every branch** including telagod's
      (#776/#777) — corrections can be pushed to PR branches pre-merge.
- [x] CI + mergeability audit (2026-09-25):
      - MERGEABLE + CI SUCCESS: #962, #963, #776, #953, #954, #959, #970,
        #966, #987, #971 (971 still draft — un-draft in wave 3).
      - **CONFLICTING (branch update required before merge): #777, #775, #774**
        (telagod's April docs PRs rotted against main; rebase + corrections in
        one maintainer-push per branch).
      - #989: no checks ran (README-only); verify by eye.
      - **All PRs show state=BLOCKED despite green checks** — branch
        protection "review required". First merge attempt (2026-09-25, #962)
        confirmed the gate: maintain role cannot merge, admin-bypass refused
        ("At least 1 approving review is required by reviewers with write
        access"), and repo-level auto-merge is disabled. **Campaign is gated
        on donprus approvals** (one per PR, in runbook order) or a protection
        change (relax required reviews, bypass list, or admin grant). Evidence
        note + failed-merge state left clean on #962; nothing merged yet.

## Wave 1 — documentation (order: ours first, corrected others after)

| # | PR | Action before merge | Closes (upstream) |
|---|---|---|---|
| 1 | #962 (ours) | none — clean | #767 |
| 2 | #963 (ours) | none — clean | #817 |
| 3 | #776 (telagod) | 3 corrections REQUIRED (verified at fork intake): `mcp_servers.<id>.env`/`.headers` are string→string objects, not `{key,value}` arrays; subagent limits 15/4 are built-in, not `agents.defaults.subagent_max_*` keys — replace JSON block; document MCP lexical narrowing only-when-no-groups rule | — |
| 4 | #777 (telagod) | **DO NOT MERGE AS-IS** — pins Zig 0.15.2; must read 0.16.0 (repo-wide pin consistency). Also keep the zig-installation pointer | — |
| 5 | #775 (telagod) | verify AGENTS.md/CLAUDE.md cross-refs still valid | — |
| 6 | #774 (telagod) | re-verify every stat against current tree | — |
| 7 | #989 (FaintFlower) | cosmetic star-history chart; verify URL renders | — |

## Wave 2 — our code PRs, smallest first

| # | PR | Notes | Closes (upstream, verify at merge) |
|---|---|---|---|
| 1 | #953 | discord gateway close-before-heartbeat join | — |
| 2 | #954 | cron once-delivery use-after-free | #941 family |
| 3 | #959 | paired-token persistence (encrypted; scheduler decrypt) | #839, #915 |
| 4 | #970 | CLI arrow keys / line editor | #865 |
| 5 | #966 | Android credentialed curl fallback | #484 |

Close an upstream issue only when the merged PR demonstrably fixes it; cite
the merge commit in the close comment.

## Wave 3 — the two large PRs, in this order

1. **#987** (loop hygiene): already rebased on main, CI green. Merge as-is.
2. **#971** (streaming native tools): currently **draft** — un-draft first,
   rebase on post-#987 main. Both touch `agent/root.zig` + providers; the
   resolved combination already exists in fork history (`ce2d54ca`, then
   `bac43959`) — use it as the reference for any conflict, do not improvise.

## Wave 4 — decision item, not scheduled: Docker / OrbStack deploy

Findings (2026-09-25): the repo ships `Dockerfile`; `release.yml` publishes
images via the shared `nullbuilder` workflow (`publish_docker: true`).
Upstream **#449 "nullclaw installation using docker hub image" is still
open** (fork mirror was closed citing CI publishing; the open ask is Docker
Hub distribution and/or usable `docker run` guidance). Options:

- **(a) OrbStack as a fifth deploy target** (local container on the Mac mini,
  alongside the existing ZeroClaw/Hermes OrbStack containers): build or pull
  the image, mount config, health + smoke. Adds a container validation
  surface to every release with modest effort.
- **(b) Close the #449 gap**: verify where images actually publish (ghcr vs
  hub), add a documented `docker run` example (volume mounts, gateway port),
  decide whether Docker Hub publishing is wanted.
- **(c) Both.**

Needs a user decision before any work; nothing scheduled.

## Out of scope for this campaign

Third-party code PRs (#985, #984, #983, #981-closed, …), upstreaming
fork-only work (hardening, intakes, skills-symlinks, error-surfacing),
#969 approval-flow concept, Q1–Q4 philosophy decisions, version bumps/tags.
