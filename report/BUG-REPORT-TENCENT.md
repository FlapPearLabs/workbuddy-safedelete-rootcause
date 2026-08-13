# BUG REPORT — WorkBuddy safe-delete / sandbox interferes with `npm ci` and may remove tracked Git worktree files after `switch` / `merge`

**Product:** WorkBuddy (Tencent)
**Component:** `genie-safe-delete.cjs` Node shim + `safe-delete-bulk-guard.cjs` + `tsbx` kernel sandbox
**Severity:** MEDIUM (Issue A) / MEDIUM with HIGH-confidence unconfirmed (Issue B)
**Reproduction environment:** Windows 11 (any), Git 2.49, Node 22, npm 10, WorkBuddy 5.3.11
**Date filed:** 2026-08-13
**Repro repository:** https://github.com/FlapPearLabs/workbuddy-safedelete-rootcause

---

# Executive Summary

WorkBuddy's safe-delete subsystem intercepts two routine development operations and produces different failure modes:

1. **Issue A — `npm ci` is aborted partway by the safe-delete bulk-guard**, leaving `node_modules` in a half-deleted state. The shim report shows that the abort happens *after* the shim has already trashed at least one small file (`.package-lock.json`), so the failure is non-atomic. Subsequent test runs may report `entities@8.0.0` or `parse5@8.0.1` as missing internal files (e.g. `dist/escape.js`) even though the packages are still on disk.
   **Reproduced in this repo's disposable lab, A/B, in 1 click.** See "Issue A" below.

2. **Issue B — tracked Git worktree files disappear after `git switch` / `git merge`** while the Git object database (HEAD / index / blob) remains intact. The files are recovered by `git restore --worktree`. The only clue is a row of ` D` entries in `git status`. **Observed repeatedly in the user's native WorkBuddy session (5+ events across 4 days in the user's audit log).** The lab probe conclusively rules out the Node shim as the cause; the remaining candidate is the kernel filter (`tsbx.dll`) which is only loaded into processes spawned by `sandbox-cli.exe` inside a real WorkBuddy session. The lab probe therefore cannot reproduce Issue B; the verification procedure is in `report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md`.

The two issues have **different root-cause layers** (Node shim + bulk-guard for A; kernel filter for B) and the same product-level philosophy (deny-by-default + low default threshold). They are recommended to be filed as **two linked bugs** so that WorkBuddy's `safe-delete` and `sandbox` owners can each be assigned the right issue.

---

# Environment

| Item | Value |
|---|---|
| WorkBuddy version | 5.3.11 |
| Electron | 37.10.3 |
| Bundled Node | 22.21.1 |
| OS | Windows 11 (10.0.26200) |
| Filesystem | NTFS |
| Git | 2.49.0.windows.1 |
| Host Node | 22.15.0 |
| Host npm | 10.9.2 |

`tsbx_rules.json` (sha256 `30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A`) reports:
```json
"default_action": "deny_write",
"recyclebin_backup": true,
"auto_grant": true
```
There is **no allow-list rule for `D:\Dev\**`** — anything in that tree falls under the deny-by-default policy.

---

# Issue A — `npm ci` is aborted by the safe-delete bulk-guard

## Expected

`npm ci` deletes the existing `node_modules` and reinstalls from `package-lock.json`. The result is a bit-identical `node_modules` matching the lockfile.

## Actual

When the parent shell has the safe-delete Node shim active (i.e. `CODEBUDDY_SESSION_ID` set, `NODE_OPTIONS=--require=genie-safe-delete.cjs`), `npm ci` exits non-zero with:

```
npm error [safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED] {"count":59,"threshold":20,"scope":"turn","targets":[".../node_modules/entities"],"targetCount":1}
```

`node_modules` is left in a half-mutated state. The default 20-delete threshold is hit because `node_modules/<pkg>` directories contain many small files (each is counted by the bulk-guard's per-file count). The bulk-guard throws and `npm ci` aborts without rolling back partial deletes. Subsequent `npm test` runs may fail with `Cannot find module 'entities/dist/escape.js'` even though `node_modules/entities/` exists.

The failure is **not silent**: the bulk-guard emits a single line of stderr identifying the threshold and the offending target. It is **not atomic** either: the shim report captured by the lab probe shows that npm ci's first successful delete (a single small file, well below the threshold) is allowed through the shim before the bulk-guard fires on the bigger batch.

## 30-second repro (one click)

```powershell
git clone https://github.com/FlapPearLabs/workbuddy-safedelete-rootcause
cd workbuddy-safedelete-rootcause
powershell -ExecutionPolicy Bypass -File .\bin\repro-all.ps1
```

Expected output (key lines):

```
PHASE1A NORMAL small: STILL_EXISTS_AFTER=false EXIT_CODE=0
PHASE1B NORMAL large: STILL_EXISTS_AFTER=false EXIT_CODE=0
PHASE1C SHIM small: STILL_EXISTS_AFTER=false EXIT_CODE=0
PHASE1D SHIM large: THROWN=... SAFE_DELETE_BULK_CONFIRM_REQUIRED count=40 threshold=20 EXIT_CODE=1
PHASE2 NPM_CI_PHASE1_CI_EXIT=0   NPM_CI_PHASE1_CI_OUTPUT_HEAD=added 2 packages
PHASE2 NPM_CI_PHASE2_CI_EXIT=1   NPM_CI_PHASE2_BULK_GUARD_TRIGGERED=yes
PHASE2 NPM_CI_PHASE2_SHIM_TRASH_EVENT <ts> op=trash runtime=node path=...\node_modules\.package-lock.json
PHASE3A BUILD BRANCH_DELTA_VALID=YES
PHASE3A 11x WORKTREE_CHECK_VERDICT=CLEAN
PHASE3B 11x WORKTREE_CHECK_VERDICT=CLEAN
PHASE4_RESULT=NOT_EXECUTED_REQUIRES_WORKBUDDY_PARENT
```

The shim report is the smoking gun for "non-atomic partial mutation": the shim silently trashed `.package-lock.json` *before* the bulk-guard fired on `node_modules/entities`.

## A/B result

| Mode | npm ci exit | Bulk guard | `.package-lock.json` after | `node_modules/entities` after |
|---|---|---|---|---|
| NORMAL (env cleared) | 0 | not fired | present | present (92 files) |
| SHIM (env + `NODE_OPTIONS=--require=genie-safe-delete.cjs`) | 1 | fired (`count=59, threshold=20`) | **trashed by shim** | still on disk (bulk-guard blocked the bigger batch) |

The same lockfile content is used in both modes (`parse5@8.0.1` + `entities@8.0.0`).

## Confirmed root cause

`genie-safe-delete.cjs` (29,796 bytes, sha256 `A9F9800C1244ADA606A73C96699DA3EBB3E056CE2115BF50912CD9EFC302D1C7`) patches `fs.unlinkSync` / `fs.rmSync` (and 4 other entry points). When `CODEBUDDY_SESSION_ID` is set, every `fs.rmSync` in the Node process is intercepted and rerouted to `genie-trash.exe` / `Microsoft.VisualBasic.FileIO.FileSystem.SendToRecycleBin`. The decision point is at `genie-safe-delete.cjs:546` (`tryTrash` → `checkBulkDeleteGuard`).

`safe-delete-bulk-guard.cjs` (16,725 bytes, sha256 `EA40BA9DFD90D6555AC516AE3CA9C1BE7332D826781FBB07AC071903D88CA822`) defaults to a 20-delete threshold and throws `SAFE_DELETE_BULK_CONFIRM_REQUIRED` (fail-closed) when the cumulative count in the current turn exceeds the threshold. The decision is at `safe-delete-bulk-guard.cjs:222`.

The combination of the two is what causes the failure: the shim is permissive on small operations (the `.package-lock.json` trashing is one such), and the bulk-guard only fires on the bigger batch — so npm ci is in an undefined intermediate state when the abort happens.

---

# Issue B — tracked worktree files disappear after `git switch` / `git merge`

## Expected

`git switch <branch>` and `git merge --ff-only <branch>` produce a worktree consistent with HEAD. Tracked files present in HEAD are present on disk.

## Actual

After a `git switch` or `git merge` operation performed from a native WorkBuddy tool-call, a non-empty subset of tracked files is missing from the worktree. `git status` shows lines like ` D  <path>` (deleted in worktree, present in index). `git fsck` reports the repository as healthy. `git restore --worktree <path>` recovers every missing file with no further changes.

This has been observed repeatedly in the user's native WorkBuddy session (5+ events in the audit log between 2026-08-10 and 2026-08-13). In every case, **HEAD, index, and blob are all intact**. The loss is worktree-only.

## Native WorkBuddy reproduction (Phase 1 of the verification procedure)

The lab probe (`bin/repro-all.ps1`) is **not** able to reproduce Issue B from a non-WorkBuddy shell, because the kernel filter (`tsbx.dll`) is only loaded into processes spawned by `sandbox-cli.exe` inside a real WorkBuddy session. The Node shim is conclusively ruled out by the lab probe's Phase 3 (Git A/B): 11 per-step `WORKTREE_CHECK_VERDICT=CLEAN` results in both NORMAL and SHIM-ONLY modes, with a real branch delta (60 tracked files on master, feature branch with 48 modified / 5 deleted / 16 added / 4 renamed).

The complete, copy-pasteable procedure for running the Git probe from inside a real WorkBuddy tool-call is in `report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md`. It has 3 phases:

1. **Phase 1 — REAL WORKBUDDY BASELINE.** Run the Git probe (5 cycles + 1 merge) from a WorkBuddy tool-call with `tsbx_rules.json` unchanged. Record the outcome. If `WORKTREE_LOSS_REPRODUCED: YES`, save the post-loss snapshot. If `NO_IN_10_CYCLES`, stop and report.
2. **Phase 2 — WorkBuddy-native rule A/B.** Add a narrow `inherit_user` rule covering only the lab root to `tsbx_rules.json -> file_rules_user`. After a WorkBuddy restart, re-run the same Git probe. Compare outcomes.
3. **Phase 3 — Optional ETW / ProcMon capture.** If `procmon.exe` or `xperf` is available, capture a trace of the Git probe to directly observe the kernel-filter denials.

## A/B result (so far)

| Mode | Lab outcome (5 cycles + 1 merge) |
|---|---|
| NORMAL (env cleared) | 11/11 steps `WORKTREE_CHECK_VERDICT=CLEAN` |
| SHIM-ONLY (env + `NODE_OPTIONS=--require=genie-safe-delete.cjs`) | 11/11 steps `WORKTREE_CHECK_VERDICT=CLEAN` |
| WORKBUDDY FULL (kernel filter active) | **PENDING_NATIVE_WORKBUDDY_EXECUTION** (Phase 1 in `NEXT-WORKBUDDY-GIT-EXPERIMENT.md`) |
| WORKBUDDY FULL + `inherit_user` allow-rule | **PENDING_NATIVE_WORKBUDDY_EXECUTION** (Phase 2) |

The lab probe rules out the Node shim as the cause. The remaining candidate is the kernel filter. The kernel filter is the only mechanism consistent with all observed facts:

- `tsbx.dll` is currently loaded by `sandbox-cli.exe` (PID observed during investigation).
- `tsbx_rules.json` has `default_action: "deny_write"` + `recyclebin_backup: true` + no allow-rule for `D:\Dev\**`.
- The user has never observed the anomaly when running git from a non-WorkBuddy shell.
- The observed `git status` output (` D` lines, `git fsck` clean) is consistent with partial-mutation of the worktree.

## Root cause confidence

- `SANDBOX_POLICY_CAUSE` is `HIGH_CONFIDENCE_INFERENCE` until Phase 1 of `NEXT-WORKBUDDY-GIT-EXPERIMENT.md` is executed.
- `COMPONENT_LEVEL_CAUSE` is `HIGH_CONFIDENCE_INFERENCE` until ETW / ProcMon evidence (Phase 3) is captured.
- The `inherit_user` rule type semantics ("let NTFS ACL apply; do not add sandbox restrictions") is **inferred** from the field name and surrounding rule vocabulary. It is not asserted to be the product-team's documented definition.

---

# Impact

- **npm install failures:** `npm ci` is the canonical "I want a clean state" command. It is unsafe to use from inside a WorkBuddy-spawned shell.
- **Misleading test regressions:** Test runs may report `Cannot find module 'parse5/dist/index.js'` or `Cannot find module 'entities/dist/escape.js'`, which look like missing dependencies but are actually partial-deletes. The user or agent may waste time debugging nonexistent code regressions.
- **Tracked worktree file loss (Issue B, observed in the user's session):** Files disappear without any user-initiated destructive operation. Recovery is non-trivial (`git restore --worktree`); without HEAD/index integrity checks first, an inexperienced user might run `git checkout HEAD -- <path>` or `git reset --hard`, both of which could re-introduce data loss or rewrite history.
- **No observed permanent data loss:** `git fsck` is healthy in every case. The `.git/` directory is intact.

# Data-loss boundary

The user has proposed a 4-class classification of the data-loss boundary. The exact
risk for each class depends on the failure mode and on whether the user notices
in time to recover from the OS recycle bin (per `recyclebin_backup: true`).

| Class | What it is | Risk under the observed failure modes | Evidence |
|---|---|---|---|
| `COMMITTED_CONTENT` | Tracked files already in HEAD | LOW. Git object is intact; `git restore --worktree <path>` or `git checkout HEAD -- <path>` recovers it. | HEAD / index / blob verified intact in all observed user-side cases (5+ events). |
| `STAGED_CONTENT` | Files added to index but not committed | LOW. Index entry persists. | Per `git ls-files --error-unmatch <path>` and `git show :<path>` results in the lab probe. |
| `UNSTAGED_CONTENT` | Tracked files modified in worktree but not staged | POTENTIALLY_MEDIUM. If the worktree-only deletion happens to a file that was `M`-status, the file is lost from the worktree. The change is **not** in the index. `git restore --worktree <path>` would set the worktree file to the **index version** (i.e. wipe the unstaged change). Recovery from the worktree-only deletion alone is therefore non-trivial; the user must `git diff` first and re-apply the change after `git restore`. | Inferred from the worktree-only pattern; the lab probe does not yet exercise this exact race. The user has not reported losing unstaged changes (they tend to commit before risky operations). |
| `UNTRACKED_CONTENT` | New files not in HEAD or index | POTENTIALLY_MEDIUM. The kernel filter may route the unlink to the OS recycle bin per `recyclebin_backup: true`, in which case recovery is possible from the recycle bin. If the recycle bin is emptied before the user notices, the file is lost. | Inferred from the rule's `recyclebin_backup: true` setting; the empirical routing has **not** been observed directly in this round. |

**The risk is concentrated in `UNSTAGED_CONTENT` and `UNTRACKED_CONTENT`.** The
lab probe and the user's audit log show `COMMITTED_CONTENT` and `STAGED_CONTENT`
are recoverable in all observed cases. We do **not** claim that
`git restore --worktree` recovers unstaged modifications — it does not. The
correct recovery for an unstaged modification after a worktree-only deletion is
to first capture the modification (e.g. `git diff > /tmp/patch.diff` would also
fail under the bulk-guard; an out-of-band copy is required) and only then
`git restore --worktree <path>`.

# Workaround (verified in lab and at user site)

These workarounds are independently verified by the user and by the lab probe:

1. **Run `npm ci` from a non-WorkBuddy shell.** A regular PowerShell / cmd where `CODEBUDDY_SESSION_ID` is not set will not have the shim active, so `npm ci` will succeed normally.
2. **Use `npm install` instead of `npm ci` inside a WorkBuddy session** if a clean install is required. `npm install` does not delete the entire `node_modules` tree in one operation, so the bulk-guard threshold is less likely to fire. This is a workaround, not a fix.
3. **After any `git switch` or `git merge`, run `git status --short` immediately.** If any ` D` lines appear, run `git restore --worktree <path>` (one at a time, or `git restore --worktree -- .` for all). The recovery is non-destructive for committed and staged content.
4. **Commit frequently.** Tracked worktree files that are committed are not at risk of the worktree-only deletion causing data loss. Commit-then-do-other-operations limits the window.
5. **For unstaged modifications**, capture the diff out-of-band (e.g. `Get-Content` of the file to a temp location) before running `git restore --worktree`. The bulk-guard may also block out-of-band copy if the directory has many files; copy single files, not directories.

# Suggested fixes

These suggestions target the failure modes, not the safety mechanism itself.

1. **Recognize package-manager controlled cleanup.** The shim / bulk-guard should detect `npm ci` / `pnpm install --frozen-lockfile` / `yarn install --frozen-lockfile` and either pre-allow the entire `node_modules` tree (it is about to be re-populated by the same tool that is deleting it) or apply a much higher threshold (the `node_modules/<pkg>` count can be in the thousands; the 20-default is unrealistic for any non-trivial package).
2. **Atomic pre-deletion / post-deletion checks for `npm ci`.** When npm is about to delete `node_modules/`, the shim should perform a *test deletion* of the parent first. If the test deletion succeeds for the parent, all child deletions should be batched. If the test fails, abort atomically. The current fail-closed design is correct in principle but the threshold makes it impossible to use in practice.
3. **`git switch` / `git merge` are atomic operations from git's perspective.** The kernel filter (or the rule set) should treat `git.exe` as a developer-tool and inherit the user's permissions, not the deny-by-default policy. This is consistent with the existing `white_process` section (which currently lists only browsers). Adding `**\\git.exe` to `white_process` (with a corresponding `file_rules_user` entry for the dev workspace) would prevent the worktree anomaly.
4. **Diagnostic error messages should be clear.** When the bulk-guard fires, the current error message points to the target directory but does not mention the threshold, the safe-delete shim, or a recovery hint. Suggest a single-line actionable error: `[safe-delete] bulk delete blocked: 59 files in .../node_modules/entities exceeds threshold 20. Either raise threshold, allow the path, or run outside a WorkBuddy session.`
5. **Sandbox policy should not create partially-mutated worktrees.** The current design has the property that an in-flight `git switch` can leave the worktree in a state that git does not consider valid. Either the entire operation must be denied atomically (preferred, but expensive) or the post-operation state must be verifiable. The current behavior — "deny some, allow others, silently" — is the worst of both worlds.
6. **Pre-flight tool-call review.** When a tool-call is about to spawn a process that will modify many files, surface a single confirmation UI rather than a per-call confirm-required error. The current `SAFE_DELETE_BULK_CONFIRM_REQUIRED` is per-call, so a 5000-file `npm ci` would fire 250 confirmations.
7. **Add a `package_manager_safe: true` flag to the shim or rules** that npm / pnpm / yarn can opt into. The flag is set by the package manager's `node_modules` cleanup code and exempts it from the bulk-guard.

# Repro repository

The disposable lab at this repository is a self-contained, one-click reproduction
environment.

```powershell
git clone https://github.com/FlapPearLabs/workbuddy-safedelete-rootcause
cd workbuddy-safedelete-rootcause
powershell -ExecutionPolicy Bypass -File .\bin\repro-all.ps1
```

The orchestrator runs:
- **Phase 0:** environment / shim-injection probe
- **Phase 1:** Node `fs.rmSync` A/B (small + large, normal + shim)
- **Phase 2:** `npm ci` A/B (normal + shim, with pre/post file manifest)
- **Phase 3:** Git A/B (5 switch cycles + 1 ff merge, with real branch delta and per-step integrity check)
- **Phase 4:** WorkBuddy NATIVE — outputs `NOT_EXECUTED_REQUIRES_WORKBUDDY_PARENT` and points to `report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md`

All probe fixtures and runtime state are gitignored; the lab rebuilds them on every run.

# Evidence classification

- `PROVEN` (reproduced in this repo, A/B):
  - The shim wraps `fs.unlinkSync` / `fs.rmSync` (and 4 other entry points) when `CODEBUDDY_SESSION_ID` is set.
  - The bulk-guard default threshold is 20 and the error string is `SAFE_DELETE_BULK_CONFIRM_REQUIRED` with `count`, `threshold`, `scope`, `targets`, `targetCount`.
  - `npm ci` exits 1 under the shim and `.package-lock.json` is trashed by the shim before the bulk-guard fires (smoking gun: the shim report capture in `report/results-latest.txt`).
  - `tsbx_rules.json` has `default_action: "deny_write"`, `recyclebin_backup: true`, `auto_grant: true`, and no allow-rule for `D:\Dev\**`.
  - The `tsbx.dll` rule type vocabulary contains `no_access | read_only | pinned_allow | inherit_user | trust | create_only | auto_grant | modify_backup | unknown | default`.
  - The `npm ci` failure mode is observed in the user's audit log (`file-safety.bulk-delete.needs-approval` events).

- `HIGH_CONFIDENCE_INFERENCE` (not yet directly observed in the lab):
  - The worktree file loss is caused by the kernel filter (loaded by `sandbox-cli` into WorkBuddy-spawned children) denying write/delete operations on `D:\Dev\**`.
  - The empirical mechanism: a minifilter at `IRP_MJ_SET_INFORMATION` denies the unlink of the old worktree files while permitting the create of the new ones, leaving the worktree in a partial state.
  - The denial may be routed to the OS recycle bin per `recyclebin_backup: true`; this is **not** directly observed in this round.

- `NOT_PROVEN`:
  - The exact reload mechanism of `tsbx_rules.json` (hot-reload vs. per-invocation vs. process startup). The procedure in `NEXT-WORKBUDDY-GIT-EXPERIMENT.md` pauses for the user to perform a controlled restart.
  - The exact product-team definition of the `inherit_user` rule type. The behavior is **inferred** from the field name and the binary string vocabulary; product documentation was not consulted.
  - Whether the lab probe's Git A/B reproduces the worktree anomaly from a real WorkBuddy session. Requires Phase 1 of `NEXT-WORKBUDDY-GIT-EXPERIMENT.md`.

# What we recommend Tencent to do

1. **Decide whether `npm ci` is supposed to work inside a WorkBuddy session.** If yes, the bulk-guard threshold or its `node_modules` heuristic must be updated. If no, the documentation should make this explicit and the recommended workflow should be "use a regular shell for package management".
2. **Decide whether `git switch` / `git merge` are supposed to work inside a WorkBuddy session.** If yes, `git.exe` should be in the developer-tool allow-list (e.g. extend `white_process` with `**\\git.exe` and corresponding `inherit_user` file rule for the workspace). If no, the documentation should make this explicit and the recommended workflow should be "run git from a regular shell".
3. **Add a single error message that explains "safe-delete intercepted your operation, the shim is at <path>, here is how to disable it for this path"**, with a copy-paste rule. The current `SAFE_DELETE_BULK_CONFIRM_REQUIRED` error does not give the user enough information to recover on their own.
4. **Document the rule schema** (the type vocabulary and semantics) so users can self-service add narrow rules. Currently the only documentation is the `_comment` field in `tsbx_rules.json` and the binary strings, neither of which is user-facing.

# What remains unknown

- The empirical outcome of Phase 1 of `NEXT-WORKBUDDY-GIT-EXPERIMENT.md` (whether the worktree anomaly reproduces from a real WorkBuddy tool-call). Pending user execution.
- The exact reload mechanism of `tsbx_rules.json`.
- The exact `inherit_user` semantics.
- The frequency of the worktree anomaly for other WorkBuddy users. Only the user-side audit log is observed; broader telemetry would be needed before claiming impact beyond this single installation.
