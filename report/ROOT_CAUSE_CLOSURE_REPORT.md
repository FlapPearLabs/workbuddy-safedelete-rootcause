# ROOT CAUSE CLOSURE REPORT

**Date:** 2026-08-13 (original Mavis-authored closure)
**Last consolidated:** 2026-08-15 (post native R1/R2 reproduction + independent review PASS)
**Investigator:** Mavis (mavis orchestrator, MiniMax Code) — original findings;
WorkBuddy-native R1/R2 reproduction added 2026-08-14 → 2026-08-15
**Subject:** WorkBuddy safe-delete / sandbox interference with `npm ci` and Git worktree file loss
**Repository:** https://github.com/FlapPearLabs/workbuddy-safedelete-rootcause
**Companion document:** `BUG-REPORT-TENCENT.md` (the submission-ready file)

> The current two-bug overview and confidence boundaries are in
> `report/EXECUTIVE-SUMMARY.md`; the native R1/R2 evidence is in
> `report/BUG-B-GIT-WORKTREE-LOSS.md`. This file preserves the original Mavis
> closure analysis and adds the native WorkBuddy reproduction (R1) and the
> controlled four-checkpoint rerun (R2), with Bug B reclassified from
> `PENDING_NATIVE_WORKBUDDY_EXECUTION` to `PHENOMENON_CONFIRMED` /
> `COMPONENT_UNRESOLVED`.

---

## Final classification (this report)

| Bug | Product cause | Component cause | Status |
|---|---|---|---|
| **Bug A — npm ci safe-delete** | CONFIRMED | CONFIRMED (`genie-safe-delete.cjs` + `safe-delete-bulk-guard.cjs`) | Closed at component level |
| **Bug B — Git worktree loss** | UNRESOLVED | **UNRESOLVED** | PHENOMENON_CONFIRMED = YES; component open |

Do **not** call Bug B fully root-cause-confirmed. Do **not** state that R1/R2
proves a race. The correct phrasing: *"The anomaly is intermittent across the
observed native runs. The source of run-to-run variability remains unresolved."*

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

→ Standalone vendor report: `report/BUG-A-NPM-SAFE-DELETE.md`

---

## ISSUE B — Git worktree file loss

### B.1 Status

- **REPRODUCED in the user's environment** (5+ distinct events in the audit
  log between 2026-08-10 and 2026-08-13).
- **Reproduced in a native WorkBuddy synthetic probe (R1, 2026-08-14).** A
  F1-shape disposable git repo (160 tracked files, 3-path delta) run **inside**
  the real WorkBuddy execution chain (ancestry to `sandbox-cli.exe`) reproduced
  `WORKTREE_ONLY_LOSS`: 59 unrelated tracked files physically absent while
  HEAD / index / blob / fsck / remote stayed intact.
- **Controlled R2 rerun (2026-08-15) was clean.** A four-checkpoint harness
  (A after commit-A, B after `git checkout -b`, C after commit-B + shape
  assertion, D after final `git checkout master`) recorded CLEAN / missing 0 at
  every checkpoint; loss was **not** reproduced in that one controlled run.
  Combined with R1, the anomaly is **intermittent across observed native runs**
  (`INTERMITTENT_ACROSS_OBSERVED_NATIVE_RUNS = YES`).
- **NOT REPRODUCED from a Mavis / non-WorkBuddy shell** — `tsbx.dll` is a
  leading candidate component because it is present in the native sandbox stack
  and fits the observed control results, but its attachment/interception
  behavior was not directly traced.

| | NORMAL | WORKBUDDY SHIM-ONLY (env + `NODE_OPTIONS=--require=...`) | WORKBUDDY NATIVE (sandbox/filesystem layer) |
|---|---|---|---|
| Non-WorkBuddy shell probe | 11/11 `WORKTREE_CHECK_VERDICT=CLEAN` | 11/11 `WORKTREE_CHECK_VERDICT=CLEAN` | n/a (full native execution chain not present) |
| Native WorkBuddy R1 | — | — | **REPRODUCED** (59-file worktree-only loss) |
| Native WorkBuddy R2 (controlled) | — | — | **CLEAN** at all 4 checkpoints (loss not reproduced this run) |
| User-side observation | never observed | never observed | 5+ events in audit log |

**The lab probe conclusively rules out the Node shim as the cause of Issue B**
(FALSIFIED by the SHIM-ONLY control). The shim is a per-Node-process patch; it
does not touch `git.exe`. A native WorkBuddy run reproduced the loss, so the
loss is specifically associated with the WorkBuddy-native execution chain; the
leading candidate mechanism consistent with all observed facts is the `tsbx.dll`
kernel filter (HIGH_CONFIDENCE_HYPOTHESIS), but it has **not** been directly
observed denying a specific operation.

### B.2 Product-level cause

**Observed facts:**
- WorkBuddy-native R1 reproduced `WORKTREE_ONLY_LOSS`.
- normal and Node-shim-only controls were clean.
- sandbox policy artifacts include `deny_write` / `recyclebin_backup`.
- no direct operation trace identifies the mutating component.

**Leading hypothesis:**
the WorkBuddy-native sandbox/filesystem layer, potentially involving
`tsbx.dll` / `ModifyBackup` / recycle-bin routing, may interfere with Git
worktree filesystem mutations.

This mechanism has **NOT** been directly observed.

### B.3 Component-level cause (UNRESOLVED)

- `GIT_COMPONENT_CAUSE = UNRESOLVED`. The specific component that performs the
  worktree mutation is not directly observed. Candidates, in order of fit:
  1. `tsbx.dll` is a leading candidate component because it is present in the
     native sandbox stack and fits the observed control results, but its
     attachment/interception behavior was not directly traced
     (HIGH_CONFIDENCE_HYPOTHESIS).
  2. `ModifyBackup` IPC / recycle-bin routing (`tsbx_rules.json` references
     `recyclebin_backup: true`; `modify_backup` field referenced in the binary
     but not in the current rules file).
- The empirical test of the tsbx hypothesis requires running git from within a
  real WorkBuddy tool-call — which R1 did, reproducing the loss, but R2 (a
  controlled one-shot rerun) was clean. The run-to-run variability is the open
  question.

### B.4 Causal confidence

- `WORKBUDDY_RUNTIME_ASSOCIATION`: **VERY_HIGH** — loss occurs only inside the
  WorkBuddy-native execution chain; never from a non-WorkBuddy shell.
- `GIT_COMPONENT_CAUSE` (which specific component performs the mutation):
  **UNRESOLVED** — no direct component-level evidence; native R1 reproduced but
  R2 one-shot was clean, so the source of run-to-run variability is open.
- `TSBX_FILTER_CAUSE`: **HIGH_CONFIDENCE_HYPOTHESIS** — the `tsbx.dll` kernel
  filter is the leading candidate mechanism consistent with all observed facts,
  but it has not been directly observed denying a specific operation.
- `SOURCE_OF_RUN_TO_RUN_VARIABILITY`: **UNRESOLVED**.

Do **not** write "race confirmed", "timing bug confirmed", or "filter-driver
race confirmed". The anomaly is **intermittent across the observed native runs**;
the source of run-to-run variability remains unresolved.

→ Standalone vendor report: `report/BUG-B-GIT-WORKTREE-LOSS.md`
→ F1 real incident: `report/NATURAL-INCIDENT-F1.md`

---

## Layering summary (Experiment 8, updated)

The WorkBuddy safe-delete has three distinct layers, each affecting different
operations:

| Layer | What it intercepts | Affects | Reproduced in lab? |
|---|---|---|---|
| **Node shim** (`genie-safe-delete.cjs`) | `fs.unlinkSync` / `fs.rmSync` / etc. in Node.js processes with `CODEBUDDY_SESSION_ID` set | All Node processes spawned by WorkBuddy (test code, npm, etc.) | **YES** — direct repro of Issue A; **conclusively rules it out for Issue B** |
| **Shell shim** (`safe-bin/{rm,rmdir,unlink}`) | `rm` / `rmdir` / `unlink` in shell sessions via `PATH` override | All bash / sh processes spawned by WorkBuddy | NOT TESTED (out of scope for this round) |
| **Kernel filter** (`tsbx.dll` + `tsbx_rules.json`) | candidate native filesystem interception layer; exact interception scope not directly traced | candidate native sandbox/filesystem component; exact attachment/interception coverage unresolved | **NATIVE R1 REPRODUCED** the worktree loss; R2 one-shot clean → intermittent; `GIT_COMPONENT_CAUSE=UNRESOLVED`, `TSBX_FILTER_CAUSE=HIGH_CONFIDENCE_HYPOTHESIS` for Issue B |

The Node shim alone is sufficient to cause Issue A (component-confirmed).
For Issue B, the `tsbx.dll` kernel filter is a **HIGH_CONFIDENCE_HYPOTHESIS**
(leading candidate), **not** an established cause: it has not been directly
observed denying a specific git operation, and the source of run-to-run
variability (R1 reproduced, R2 clean) is unresolved. Bug A has a confirmed
component layer; Bug B remains unresolved, and the two must not be conflated —
the 20-delete
bulk-guard threshold that governs Issue A does **not** apply to Issue B.

---

## A/B result table

| Probe | NORMAL | WORKBUDDY SHIM SIMULATION | WORKBUDDY NATIVE (sandbox/filesystem layer) |
|---|---|---|---|
| Node fs.rm small (5 files) | native delete, exit 0 | shim silently trashes, exit 0 | n/a (native chain not exercised in lab) |
| Node fs.rm large (40 files) | native delete, exit 0 | shim BLOCKS with `SAFE_DELETE_BULK_CONFIRM_REQUIRED`, exit 1 | n/a |
| `npm ci` | exit 0, clean, REMOVED=0 | exit 1, `node_modules` half-deleted, shim report confirms `.package-lock.json` trashed before guard fires | n/a |
| Git worktree cycles (5+1) — Mavis shell | TRACKED=60, PHYSICAL=60, MISSING=0, all 11 steps CLEAN | TRACKED=60, PHYSICAL=60, MISSING=0, all 11 steps CLEAN | n/a (full native execution chain not present) |
| Git worktree — native R1 (F1-shape) | — | — | **REPRODUCED** 59-file `WORKTREE_ONLY_LOSS`, HEAD/index intact |
| Git worktree — native R2 (4-checkpoint) | — | — | **CLEAN** at A/B/C/D, loss not reproduced this run |

---

## Data-loss boundary (corrected)

The user proposed a 4-class classification of the data-loss boundary. The risk
for each class depends on the failure mode and on whether the user notices in
time to recover from the OS recycle bin (per `recyclebin_backup: true`).

| Class | Risk | Notes |
|---|---|---|
| `COMMITTED_CONTENT_RISK` | LOW | Git object is intact; `git restore --worktree <path>` or `git checkout HEAD -- <path>` recovers it. HEAD / index / blob verified intact in all observed user-side cases. |
| `STAGED_CONTENT_RISK` | LOW | Index entry persists. |
| `UNSTAGED_CONTENT_RISK` | POTENTIALLY_MEDIUM | If the worktree-only deletion happens to a file that was `M`-status, the file is lost from the worktree. The prior unstaged bytes are **not** in HEAD or in the index. `git restore --worktree <path>` would set the worktree file to the **index version** (i.e. wipe the unstaged change). The only recovery paths are external (OS recycle bin, editor / IDE local history, autosave / backup, out-of-band copy). `git diff` cannot recover the bytes either, because the file is already gone from the worktree. |
| `UNTRACKED_CONTENT_RISK` | POTENTIALLY_MEDIUM | The kernel filter may route the unlink to the OS recycle bin per `recyclebin_backup: true`. If the recycle bin is emptied before the user notices, the file is lost. |

**Permanent data loss has not been observed in this round.** The risk is
concentrated in `UNSTAGED_CONTENT` and `UNTRACKED_CONTENT`. We do **not**
claim that `git restore --worktree` recovers unstaged modifications — it
does not. The prior unstaged bytes are not stored in HEAD or in the index.
Before running `git restore --worktree`, check the OS recycle bin, the editor
/ IDE local history, autosave / backup, or any other out-of-band copy. `git
diff` cannot recover the bytes either, because the file is already gone from
the worktree.

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

See `BUG-REPORT-TENCENT.md` section "What we recommend Tencent to do" — the
four concrete items. For Bug B specifically, the remaining work is component-level
confirmation (see `BUG-B-GIT-WORKTREE-LOSS.md` → "Possible future diagnostics").

## What remains unknown

- The **component-level cause** of Bug B: which kernel component (`tsbx.dll`
  filter vs. `ModifyBackup` IPC vs. recycle-bin routing) performs the worktree
  mutation, and **why it is intermittent** (R1 reproduced, R2 one-shot clean).
- The exact reload mechanism of `tsbx_rules.json` (hot-reload vs. per-invocation
  vs. process startup).
- The exact `inherit_user` rule type semantics. **Inferred** from the field
  name and the binary string vocabulary; product documentation was not
  consulted in this round.
- The frequency of the worktree anomaly for other WorkBuddy users. Only the
  user-side audit log is observed; broader telemetry would be needed before
  claiming impact beyond this single installation.
- Whether the `modify_backup` field in `tsbx_rules.json` (referenced in the
  binary but not in the current `tsbx_rules.json`) supersedes
  `recyclebin_backup` and what its semantics are.

---

## Privacy / proprietary content audit

This public repository contains the minimum content required for the
investigation:

- No real production source files (no full file from `<WORKBUDDY_INSTALL>`).
- No credentials, no API keys, no tokens, no cookies, no passwords.
- No real production repo paths (`<PROD_REPO>` is hard-blacklisted
  in the lab scripts and is never touched).
- The user's Windows profile path (`C:\Users\<user>`) is replaced with
  `<USER_PROFILE>` in all published documents.
- The disposable lab root (`<WORKSPACE>`) is replaced with
  `<WORKSPACE>` in all published documents.
- The WorkBuddy companion app paths (`<WORKBUDDY_INSTALL>\openclaw\**`,
  `<WORKBUDDY_INSTALL>\proxy-agent\**`) are redacted in the published copy of
  `tsbx_rules.original.json` to a `_comment` saying "path redacted in
  published copy". The lab's `_redaction_marker` clearly identifies what
  was changed.
- Quoted code snippets from `genie-safe-delete.cjs` and
  `safe-delete-bulk-guard.cjs` are limited to the minimum lines necessary
  to identify the API surface, the threshold, and the throw decision
  (under 30 lines each).
- The historical Git metadata may contain the repository author's public
  Git identity (the user is the only author; this is not a secret).
- The raw native-run logs under `work/native-runs/` are **gitignored** and
  **not committed**; they are mapped to the sanitized public claims via
  `work/RAW-EVIDENCE-MANIFEST.md` for future re-verification.

**No force-rewriting of Git history was performed.** The prior commits that
contained the disposable probe sub-repos as gitlinks have been removed via
`git rm` and the new commits continue from the same parent. The gitlinks
and committed fixtures (now removed) were disposable, so the user does
not need to rewrite history; the published tree is clean from the new
commits forward.

---

## Canonical issue architecture

The investigation deliberately splits evidence collection from vendor filing.
The two repos have different roles:

- **`FlapPearLabs/zhihu-grabber-toolkit`** is the production repository where
  the natural incident was observed. It is **read-only** for the investigation.
  The natural incident log (issue-style evidence) lives in this repo's issue
  tracker (Issue #1) and in `report/NATURAL-INCIDENT-F1.md` in the rootcause
  repo. It contains the user's project evidence only; it does NOT contain the
  canonical repro, the safe-delete source code excerpts, the tsbx binary
  strings, or the WorkBuddy-side analysis.

- **`FlapPearLabs/workbuddy-safedelete-rootcause`** (this repo) is the
  **canonical repro + root cause + vendor report**. It contains:
  - the one-click repro bundle (`bin/repro-all.ps1`)
  - the sanitized evidence pack (`report/sanitized-evidence.md`)
  - the natural incident F1 record (`report/NATURAL-INCIDENT-F1.md`)
  - the next-step native procedure (`report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md`)
  - the Tencent submission file (`report/BUG-REPORT-TENCENT.md`)
  - the two standalone vendor reports (`report/BUG-A-NPM-SAFE-DELETE.md`,
    `report/BUG-B-GIT-WORKTREE-LOSS.md`)
  - the closure summary (this file)
  - the publication set (`report/EXECUTIVE-SUMMARY.md`,
    `report/MASTER-INVESTIGATION-LEDGER.md`, `report/SOURCE-COVERAGE-AUDIT.md`,
    `report/INVESTIGATION-TIMELINE.md`, `report/EVIDENCE-INDEX.md`,
    `report/INVESTIGATOR-CONTRIBUTIONS.md`, `report/ENVIRONMENT-MODEL.md`,
    `report/VENDOR-SUBMISSION-CHECKLIST.md`)

### Final vendor filing: TWO LINKED BUGS

Bug A has a confirmed component layer; Bug B remains unresolved. The two do NOT
share the same product-level philosophy — the 20-delete threshold is confirmed
only for Bug A. They are
recommended to be filed as **two linked bugs** so that the WorkBuddy
`safe-delete` and `sandbox` owners can each be assigned the right issue:

- **BUG A — `npm ci` / Node safe-delete bulk guard**
  - **CONFIRMED** in this repo's disposable lab (1 click, 11 per-step records,
    partial-mutation smoking gun in `NPM_CI_PHASE2_SHIM_TRASH_EVENT`).
  - **Component-level cause:** `genie-safe-delete.cjs` +
    `safe-delete-bulk-guard.cjs` (verified by source line numbers and SHA256).
  - **Owner:** WorkBuddy `safe-delete` team.
  - Stand-alone report: `report/BUG-A-NPM-SAFE-DELETE.md`.

- **BUG B — `git switch` / `git merge` / native WorkBuddy sandbox**
  - **PHENOMENON_CONFIRMED** by native R1 reproduction (59-file worktree-only
    loss) + 5+ real-world audit events + F1 natural recurrence (3-path merge
    delta + 18 missing files).
  - **WORKBUDDY_RUNTIME_ASSOCIATION = VERY_HIGH**; **COMPONENT_CAUSE =
    UNRESOLVED** — native R1 reproduced but R2 one-shot was clean
    (`INTERMITTENT_ACROSS_OBSERVED_NATIVE_RUNS = YES`); the specific component
    (tsbx filter vs. `ModifyBackup` IPC vs. recycle-bin routing) is not
    directly observed.
  - **Candidate component-level cause (HIGH_CONFIDENCE_HYPOTHESIS):** the
    `tsbx.dll` kernel filter (present in the sandbox distribution) is the leading
    candidate for the component that may interfere with file operations of
    processes spawned by `sandbox-cli.exe`; this attachment/interception has NOT
    been directly observed.
  - **Owner:** Vendor routing TBD; likely sandbox/filesystem team.
  - Stand-alone report: `report/BUG-B-GIT-WORKTREE-LOSS.md`.

An umbrella bug that links both is acceptable if Tencent prefers a single
routing ID, but the two issues should be tracked as distinct sub-issues so each
owner can address their own layer.

BUG B is **closed at the phenomenon level** (reproduced natively, R2 harness
reviewed and PASS) but **component cause remains open**. The remaining
diagnostics (narrow sandbox-rule A/B, ETW / ProcMon) are optional and gated as
`FUTURE_DIAGNOSTIC_IF_VENDOR_REQUESTS` in
`report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md`.

## Files in this repro bundle

| File | Purpose |
|---|---|
| `README.md` | One-click reproduction entry (updated for native R1/R2) |
| `bin/repro-all.ps1` | Master orchestrator (5 phases) |
| `bin/repro-npm-ci.ps1` | npm ci A/B with pre/post file manifest |
| `bin/repro-node-delete.mjs` | Node fs.rmSync A/B |
| `bin/probe-shim.cjs` | Verifies the Node shim is loaded in the env |
| `bin/build-fixture.ps1` | Creates the small/large Node delete fixtures |
| `bin/build-git-probe.ps1` | Initializes the disposable git repo with real branch delta (HISTORICAL / AUXILIARY for Bug B; negative-control fixture for Bug A Git A/B) |
| `bin/build-git-probe-f1-shape.ps1` | F1-shape native probe — AUTHORITATIVE Bug B harness (R1/R2) |
| `bin/check-worktree.ps1` | Verifies tracked file integrity after each git operation |
| `bin/run-git-cycles.ps1` | Runs N switch cycles + 1 fast-forward merge |
| `bin/assert-native-workbuddy-context.ps1` | Confirms real WorkBuddy ancestry |
| `bin/test-outcome-parser.ps1` / `bin/test-attribution-preop.ps1` | Offline harness self-tests |
| `bin/_lib.ps1` | Shared library (env, paths, manifest, worktree classifier) |
| `bin/run-as-workbuddy.ps1` | Sets WorkBuddy env vars and invokes a child command (refuses real-project paths) |
| `npm-probe/package.json` | parse5@8.0.1 + entities@8.0.0 fixture |
| `npm-probe/package-lock.json` | Committed lockfile (registry.npmjs.org) |
| `report/BUG-REPORT-TENCENT.md` | Submission-ready bug report |
| `report/BUG-A-NPM-SAFE-DELETE.md` | Standalone Bug A vendor report |
| `report/BUG-B-GIT-WORKTREE-LOSS.md` | Standalone Bug B vendor report |
| `report/EXECUTIVE-SUMMARY.md` | Two-bug overview + confidence boundaries |
| `report/MASTER-INVESTIGATION-LEDGER.md` | Master reconciliation of every finding |
| `report/SOURCE-COVERAGE-AUDIT.md` | Source inventory + coverage reconciliation |
| `report/INVESTIGATION-TIMELINE.md` | Chronological investigation stages |
| `report/EVIDENCE-INDEX.md` | Claim-by-claim evidence + confidence |
| `report/INVESTIGATOR-CONTRIBUTIONS.md` | Provenance: who found what |
| `report/ENVIRONMENT-MODEL.md` | Environment / version / process model |
| `report/VENDOR-SUBMISSION-CHECKLIST.md` | Two linked bug packages + channels |
| `report/ROOT_CAUSE_CLOSURE_REPORT.md` | This file |
| `report/sanitized-evidence.md` | Full evidence pack with code snippets, shim report, audit log quotes |
| `report/NATURAL-INCIDENT-F1.md` | Sanitized record of the 2026-08-14 F1 natural recurrence |
| `report/results-latest.txt` | Full orchestrator output (last lab run) |
| `report/results-npm-ci.txt` | npm ci A/B structured records |
| `report/results-git-normal.txt` | Git A/B NORMAL mode records |
| `report/results-git-shim-only.txt` | Git A/B SHIM-ONLY mode records |
| `report/environment-summary.txt` | Sanitized environment info |
| `report/tsbx_rules.original.json` | Unmodified backup of the original rules file (sha256-pinned, paths redacted) |
| `report/results-allow-rule.txt` | Documented procedure for the allow-rule test (not executed) |
| `report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md` | Complete procedure for native WorkBuddy diagnostics |
