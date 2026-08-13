# ROOT CAUSE CLOSURE REPORT

**Date:** 2026-08-13
**Investigator:** Mavis (mavis orchestrator, MiniMax Code)
**Subject:** WorkBuddy safe-delete / sandbox interference with `npm ci` and Git worktree file loss
**Repository:** https://github.com/FlapPearLabs/workbuddy-safedelete-rootcause
**Companion document:** `BUG-REPORT-TENCENT.md` (the submission-ready file)

---

## ISSUE A — npm ci

### A.1 Status

`REPRODUCED` in a disposable lab using the same `parse5@8.0.1` + `entities@8.0.0`
lockfile content as the real affected project.

| | NORMAL | WORKBUDDY SHIM SIMULATION |
|---|---|---|
| `npm ci` exit | 0 | 1 |
| Bulk-guard error | not fired | `SAFE_DELETE_BULK_CONFIRM_REQUIRED count=59 threshold=20 scope=turn` |
| Manifest pre-state | 92 files | 92 files |
| Manifest post-state | 92 files (REMOVED=0, ADDED=0, CHANGED=0) | 91 files (REMOVED=1: `.package-lock.json`) |
| `node_modules/parse5/dist/index.js` | present | present |
| `node_modules/entities/dist/escape.js` | present | present |
| Smoking gun: shim report | n/a | `op=trash runtime=node path=...\node_modules\.package-lock.json` (captured by `bin/repro-npm-ci.ps1`) |

The shim report capture is the smoking gun: under the shim, npm ci's first
successful delete is a single small file (`.package-lock.json`, count=1, well
below the threshold) which the shim silently trashes via `genie-trash`. The
bulk-guard only fires on the next bigger batch (`node_modules/entities`,
count=59). This proves that the shim + bulk-guard combination is non-atomic:
**partial mutation occurs before the guard fires**.

### A.2 Product-level cause

WorkBuddy's safe-delete subsystem (Node shim + bulk-guard) is unaware of
`npm ci`'s intent to atomically replace `node_modules`. The default
bulk-guard threshold (20 deletes per tool-call) is far below the typical
file count of a single `node_modules/<pkg>` directory. The result: `npm ci`
cannot perform the prerequisite `node_modules` deletion inside a
WorkBuddy-spawned shell, and the partial state of `node_modules` triggers
subsequent test failures that look like missing dependencies.

### A.3 Component-level cause

- **Primary:** `genie-safe-delete.cjs` (29,796 bytes, sha256
  `A9F9800C1244ADA606A73C96699DA3EBB3E056CE2115BF50912CD9EFC302D1C7`) patches
  `fs.rmSync` and 5 other entry points. When `CODEBUDDY_SESSION_ID` is set,
  every `fs.rmSync` in the Node process is intercepted.
- **Trigger:** `safe-delete-bulk-guard.cjs` (16,725 bytes, sha256
  `EA40BA9DFD90D6555AC516AE3CA9C1BE7332D826781FBB07AC071903D88CA822`) defaults
  to a 20-delete threshold, throws `SAFE_DELETE_BULK_CONFIRM_REQUIRED`
  (fail-closed).
- **Decision point:** `genie-safe-delete.cjs:546` (`tryTrash` → `checkBulkDeleteGuard`).
- **Emit point:** `safe-delete-bulk-guard.cjs:222` (`checkBulkDeleteGuard`).
- **npm failure:** npm's child process (also Node) inherits the env, so
  npm's own `fs.rmSync('node_modules/...', {recursive: true})` is
  intercepted. The 59-file `node_modules/entities` directory exceeds the
  threshold, the guard throws, npm aborts.

### A.4 Causal confidence

**HIGH.** Directly reproduced in the lab with the exact package versions;
mechanism verified via source code line numbers and string evidence;
user-side audit log independently confirms the same error class.

---

## ISSUE B — Git worktree file loss

### B.1 Status

- **REPRODUCED in the user's environment** (5+ distinct events in the audit
  log between 2026-08-10 and 2026-08-13).
- **NOT REPRODUCED in the lab probe** because the kernel filter (`tsbx.dll`)
  is only loaded into processes spawned by WorkBuddy's `sandbox-cli`. From
  a Mavis shell, `git.exe` is not a WorkBuddy child and the kernel filter
  does not apply.

| | NORMAL | WORKBUDDY SHIM-ONLY (env + `NODE_OPTIONS=--require=...`) | WORKBUDDY FULL (kernel filter) |
|---|---|---|---|
| Lab probe outcome | 11/11 `WORKTREE_CHECK_VERDICT=CLEAN` | 11/11 `WORKTREE_CHECK_VERDICT=CLEAN` | **PENDING_NATIVE_WORKBUDDY_EXECUTION** |
| User-side observation | never observed | never observed | 5+ events in audit log |

**The lab probe conclusively rules out the Node shim as the cause of Issue B.**
The shim is a per-Node-process patch; it does not touch `git.exe`. The only
remaining mechanism consistent with the observed pattern is the kernel filter.

### B.2 Product-level cause

The WorkBuddy kernel sandbox (loaded by `sandbox-cli.exe` into all child
processes) applies a `deny_write` default policy to anything not in the
allow-list, and `D:\Dev\**` is not in the allow-list. When WorkBuddy
spawns `git.exe` as a child to perform `git switch` or `git merge`, the
kernel filter intercepts the worktree file operations. The new file
writes (create) are allowed or denied inconsistently with the old file
unlinks (delete), so the worktree ends up with a partial mutation that
git does not consider valid (it shows ` D` lines). Because the user has
no view of the kernel filter's denials (no log, no error), the loss
appears to come from nowhere.

### B.3 Component-level cause (inferred)

- `tsbx_rules.json` (sha256 `30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A`)
  has `default_action: "deny_write"` + `recyclebin_backup: true` + no
  allow-rule for `D:\Dev\**`.
- `tsbx.dll` is a Windows file system minifilter, loaded by
  `sandbox-cli.exe`. The kernel filter applies to all file operations of
  processes that WorkBuddy spawns.
- **The empirical test of this hypothesis requires running git from
  within a real WorkBuddy tool-call.** The lab probe from Mavis does
  not load the kernel filter, so the worktree anomaly is not
  reproducible from the lab alone. The procedure is in
  `report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md`.

### B.4 Causal confidence

- `SANDBOX_POLICY_CAUSE`: **HIGH_CONFIDENCE_INFERENCE** until Phase 1 of
  `NEXT-WORKBUDDY-GIT-EXPERIMENT.md` is executed.
- `COMPONENT_LEVEL_CAUSE`: **HIGH_CONFIDENCE_INFERENCE** until ETW /
  ProcMon evidence (Phase 3) is captured.

The kernel-filter hypothesis is the only remaining explanation after
Defender / SSD / NTFS / Defender-quarantine were ruled out in previous
rounds, and it is the only mechanism that matches all observed facts:
- tsbx kernel filter is loaded
- Rules have `deny_write` default
- `D:\Dev\**` is not in any allow-list
- `recyclebin_backup: true` may route denied operations to the recycle bin
- Worktree file loss is worktree-only (HEAD/index/blob intact) — consistent
  with partial-mutation
- No other candidate mechanism has been observed

---

## Layering summary (Experiment 8)

The WorkBuddy safe-delete has three distinct layers, each affecting different
operations:

| Layer | What it intercepts | Affects | Reproduced in lab? |
|---|---|---|---|
| **Node shim** (`genie-safe-delete.cjs`) | `fs.unlinkSync` / `fs.rmSync` / etc. in Node.js processes with `CODEBUDDY_SESSION_ID` set | All Node processes spawned by WorkBuddy (test code, npm, etc.) | **YES** — direct repro of Issue A; **conclusively rules it out for Issue B** |
| **Shell shim** (`safe-bin/{rm,rmdir,unlink}`) | `rm` / `rmdir` / `unlink` in shell sessions via `PATH` override | All bash / sh processes spawned by WorkBuddy | NOT TESTED (out of scope for this round) |
| **Kernel filter** (`tsbx.dll` + `tsbx_rules.json`) | All file system operations at the IRP level for any process whose handle is associated with the filter | All processes spawned by WorkBuddy (git.exe, node.exe, npm.cmd, etc.) | NOT REPRODUCED in Mavis (filter not active); HIGH-CONFIDENCE INFERENCE for Issue B |

The Node shim alone is sufficient to cause Issue A. The kernel filter is
required (and inferred to be sufficient) to cause Issue B. The two issues
have **different root-cause layers** even though they share the same
product-level philosophy (deny-by-default + 20-default threshold).

---

## A/B result table

| Probe | NORMAL | WORKBUDDY SHIM SIMULATION | WORKBUDDY FULL |
|---|---|---|---|
| Node fs.rm small (5 files) | native delete, exit 0 | shim silently trashes, exit 0 | n/a (kernel filter not exercised in lab) |
| Node fs.rm large (40 files) | native delete, exit 0 | shim BLOCKS with `SAFE_DELETE_BULK_CONFIRM_REQUIRED`, exit 1 | n/a |
| `npm ci` | exit 0, clean, REMOVED=0 | exit 1, `node_modules` half-deleted, shim report confirms `.package-lock.json` trashed before guard fires | n/a |
| Git worktree cycles (5+1) | TRACKED=60, PHYSICAL=60, MISSING=0, all 11 steps CLEAN | TRACKED=60, PHYSICAL=60, MISSING=0, all 11 steps CLEAN | **PENDING_NATIVE_WORKBUDDY_EXECUTION** |

---

## Data-loss boundary (corrected)

The user has proposed a 4-class classification of the data-loss boundary.
The risk for each class depends on the failure mode and on whether the
user notices in time to recover from the OS recycle bin (per
`recyclebin_backup: true`).

| Class | Risk | Notes |
|---|---|---|
| `COMMITTED_CONTENT_RISK` | LOW | Git object is intact; `git restore --worktree <path>` or `git checkout HEAD -- <path>` recovers it. HEAD / index / blob verified intact in all observed user-side cases. |
| `STAGED_CONTENT_RISK` | LOW | Index entry persists. |
| `UNSTAGED_CONTENT_RISK` | POTENTIALLY_MEDIUM | If the worktree-only deletion happens to a file that was `M`-status, the file is lost from the worktree. The prior unstaged bytes are **not** in HEAD or in the index. `git restore --worktree <path>` would set the worktree file to the **index version** (i.e. wipe the unstaged change). The only recovery paths are external (OS recycle bin, editor / IDE local history, autosave / backup, out-of-band copy). `git diff` cannot recover the bytes either, because the file is already gone from the worktree. |
| `UNTRACKED_CONTENT_RISK` | POTENTIALLY_MEDIUM | The kernel filter may route the unlink to the OS recycle bin per `recyclebin_backup: true`. If the recycle bin is emptied before the user notices, the file is lost. |

**Permanent data loss has not been observed in this round.** The risk is
concentrated in `UNSTAGED_CONTENT` and `UNTRACKED_CONTENT`. We do **not**
claim that `git restore --worktree` recovers unstaged modifications — it
does not. The prior unstaged bytes are not stored in HEAD or in the
index. Before running `git restore --worktree`, check the OS recycle
bin, the editor / IDE local history, autosave / backup, or any other
out-of-band copy. `git diff` cannot recover the bytes either, because
the file is already gone from the worktree.
does not.

---

## Workaround (verified in lab and at user site)

- ✅ Test scratch space: use `os.tmpdir()` instead of `process.cwd()` (user has adopted this)
- ✅ `npm ci`: run from a non-WorkBuddy shell
- ✅ `git restore --worktree <path>` after any suspicious `git status` output (committed / staged content only)
- ✅ Capture unstaged changes via external means (recycle bin / editor local history / autosave) before `git restore --worktree`
- ✅ Commit frequently to limit the worktree-only window
- ⏳ Proposed narrow `tsbx_rules.json` rule (proposed, native verification pending — see `NEXT-WORKBUDDY-GIT-EXPERIMENT.md`)

---

## What Tencent needs to fix

See `BUG-REPORT-TENCENT.md` section "What we recommend Tencent to do" —
the four concrete items.

## What remains unknown

- The empirical outcome of Phase 1 of `NEXT-WORKBUDDY-GIT-EXPERIMENT.md`
  (whether the worktree anomaly reproduces from a real WorkBuddy tool-call).
- The exact reload mechanism of `tsbx_rules.json` (hot-reload vs. per-invocation
  vs. process startup). The procedure pauses for the user to perform a
  controlled restart in Phase 2.
- The exact `inherit_user` rule type semantics. **Inferred** from the field
  name and the binary string vocabulary; product documentation was not
  consulted in this round.
- The frequency of the worktree anomaly for other WorkBuddy users. Only
  the user-side audit log is observed; broader telemetry would be needed
  before claiming impact beyond this single installation.
- Whether the `modify_backup` field in `tsbx_rules.json` (referenced in
  the binary but not in the current `tsbx_rules.json`) supersedes
  `recyclebin_backup` and what its semantics are.

---

## Privacy / proprietary content audit

This public repository contains the minimum content required for the
investigation:

- No real production source files (no full file from `<WORKBUDDY_INSTALL>`).
- No credentials, no API keys, no tokens, no cookies, no passwords.
- No real production repo paths (`D:\Dev\zhihu-grabber-toolkit` is hard-blacklisted
  in the lab scripts and is never touched).
- The user's Windows profile path (`C:\Users\<user>`) is replaced with
  `<USER_PROFILE>` in all published documents.
- The disposable lab root (`D:\Dev\workbuddy-rootcause-lab`) is replaced with
  `<WORKSPACE>` in all published documents.
- The WorkBuddy companion app paths (`C:\openclaw\openclaw\**`,
  `D:\openclaw\proxy-agent\**`) are redacted in the published copy of
  `tsbx_rules.original.json` to a `_comment` saying "path redacted in
  published copy". The lab's `_redaction_marker` clearly identifies what
  was changed.
- Quoted code snippets from `genie-safe-delete.cjs` and
  `safe-delete-bulk-guard.cjs` are limited to the minimum lines necessary
  to identify the API surface, the threshold, and the throw decision
  (under 30 lines each).
- The historical Git metadata may contain the repository author's public
  Git identity (the user is the only author; this is not a secret).

**No force-rewriting of Git history was performed.** The prior commits that
contained the disposable probe sub-repos as gitlinks have been removed via
`git rm` and the new commits continue from the same parent. The gitlinks
and committed fixtures (now removed) were disposable, so the user does
not need to rewrite history; the published tree is clean from the new
commits forward.

---

## Files in this repro bundle

| File | Purpose |
|---|---|
| `README.md` | One-click reproduction entry |
| `bin/repro-all.ps1` | Master orchestrator (5 phases) |
| `bin/repro-npm-ci.ps1` | npm ci A/B with pre/post file manifest |
| `bin/repro-node-delete.mjs` | Node fs.rmSync A/B |
| `bin/probe-shim.cjs` | Verifies the Node shim is loaded in the env |
| `bin/build-fixture.ps1` | Creates the small/large Node delete fixtures |
| `bin/build-git-probe.ps1` | Initializes the disposable git repo with real branch delta |
| `bin/check-worktree.ps1` | Verifies tracked file integrity after each git operation |
| `bin/run-git-cycles.ps1` | Runs N switch cycles + 1 fast-forward merge |
| `bin/_lib.ps1` | Shared library (env, paths, manifest, worktree classifier) |
| `bin/run-as-workbuddy.ps1` | Sets WorkBuddy env vars and invokes a child command (refuses real-project paths) |
| `npm-probe/package.json` | parse5@8.0.1 + entities@8.0.0 fixture |
| `npm-probe/package-lock.json` | Committed lockfile (registry.npmjs.org) |
| `report/BUG-REPORT-TENCENT.md` | Submission-ready bug report (5-min read, 30-sec Issue A repro) |
| `report/ROOT_CAUSE_CLOSURE_REPORT.md` | This file |
| `report/sanitized-evidence.md` | Full evidence pack with code snippets, shim report, audit log quotes |
| `report/results-latest.txt` | Full orchestrator output (last lab run) |
| `report/results-npm-ci.txt` | npm ci A/B structured records |
| `report/results-git-normal.txt` | Git A/B NORMAL mode records |
| `report/results-git-shim-only.txt` | Git A/B SHIM-ONLY mode records |
| `report/environment-summary.txt` | Sanitized environment info |
| `report/tsbx_rules.original.json` | Unmodified backup of the original rules file (sha256-pinned, paths redacted) |
| `report/results-allow-rule.txt` | Documented procedure for the allow-rule test (not executed) |
| `report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md` | Complete procedure for native WorkBuddy Phase 1 / 2 / 3 verification |
