# BUG B — tracked Git worktree files disappear under the WorkBuddy sandbox

**Standalone vendor report.** Understandable without Bug A.
Companion: [`BUG-A-NPM-SAFE-DELETE.md`](BUG-A-NPM-SAFE-DELETE.md).

---

## TITLE
Tracked files physically disappear from the Git worktree after `git switch` / `git merge`
performed inside a WorkBuddy-native session, while HEAD / index / blob / fsck / remote all
remain healthy (worktree-only loss). The specific component is **unresolved**.

## PRODUCT / VERSION
- Product: WorkBuddy (Tencent)
- Version observed: 5.3.11 / 5.3.13
- Suspected component: `tsbx.dll` kernel minifilter loaded by `sandbox-cli.exe`
  (HIGH_CONFIDENCE_HYPOTHESIS — not directly observed denying an operation)
- `tsbx_rules.json` (sha256 `30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A`):
  `default_action: deny_write`, `recyclebin_backup: true`, **no** `<WORKSPACE>\**` allow rule

## ENVIRONMENT
| Item | Value |
|---|---|
| OS | Windows 11 (10.0.26200), NTFS |
| Git | 2.49.0.windows.1 |
| WorkBuddy | 5.3.11 / 5.3.13 |
| Sandbox-cli | 5.3.3 |

## SUMMARY
After a `git switch` / `git merge` inside a WorkBuddy-native tool-call, a non-empty subset of
tracked files is missing from disk. `git status` shows ` D <path>` lines. `git fsck` is clean;
`git restore --worktree <path>` recovers every missing file non-destructively.

## REAL INCIDENTS
- **User sessions (2026-08-10 → 08-13):** 5+ events in the audit log. Each: HEAD/index/blob
  intact, recovered via `git restore --worktree`.
- **F1 natural incident (2026-08-14, `zhihu-grabber-toolkit`):** a 3-path `git merge --ff-only`
  (1 modified src + 1 added test + 1 modified test, **0 deletions**) left **18 unrelated
  test files** missing from the worktree. Verified independently via the GitHub compare API
  (delta = exactly 3 paths). Recovered via `git restore --worktree -- zhihu-answer-grabber/test/`.
  → [`NATURAL-INCIDENT-F1.md`](NATURAL-INCIDENT-F1.md)

## SYNTHETIC R1 (WorkBuddy-native, 2026-08-14)
- Probe ran **inside** the real WorkBuddy execution chain (ancestry to `sandbox-cli.exe`).
- F1-shape probe (160 tracked files, 3-path delta) **reproduced** `WORKTREE_ONLY_LOSS`:
  - 59 unrelated tracked files physically absent
  - `HEAD_INDEX_TREE_MATCH = YES` (HEAD_TREE == INDEX_TREE)
  - `FSCK_HEALTHY = YES`
  - loss **persisted** after switching back to master (not self-healing)
- → `SYNTHETIC_NATIVE_REPRODUCTION = CONFIRMED`

## R2 (WorkBuddy-native, 2026-08-15)
- Four physical checkpoints (A after commit-A, B after `git checkout -b`, C after commit-B +
  shape assertion, D after final `git checkout master`) instrumented the build.
- Result of the controlled rerun:
  - CHECKPOINT A: **CLEAN**, missing 0
  - CHECKPOINT B: **CLEAN**, missing 0
  - CHECKPOINT C: **CLEAN**, missing 0
  - CHECKPOINT D: **CLEAN**, missing 0
  - Final checkout exit 0, target reached
- Loss **NOT** reproduced in this one controlled run.
- → `NATIVE_RERUN_NOT_REPRODUCED_IN_ONE_RUN = YES`
- Combined with R1: **`INTERMITTENT_ACROSS_OBSERVED_NATIVE_RUNS = YES`**

## NORMAL CONTROL
From a non-WorkBuddy shell: 11/11 `WORKTREE_CHECK_VERDICT=CLEAN` (5 switch cycles + 1 ff
merge). No loss. → NEGATIVE CONTROL.

## SHIM-ONLY CONTROL
Env + `NODE_OPTIONS=--require=genie-safe-delete.cjs` (Node shim active, **no** kernel filter):
11/11 `WORKTREE_CHECK_VERDICT=CLEAN`. → NEGATIVE CONTROL; **Node shim alone does NOT cause
Bug B** (FALSIFIED).

## SIGNATURE (every observed case)
```
HEAD       = yes      (git rev-parse HEAD healthy)
INDEX      = yes      (git write-tree matches; blob readable)
PHYSICAL   = no       (tracked files absent from disk)
FSCK       = healthy  (git fsck --no-reflogs, exit 0)
REMOTE     = healthy  (git ls-remote matches local)
```

## IMPACT / DATA-LOSS BOUNDARY
- `COMMITTED_CONTENT`: LOW risk — `git restore --worktree` recovers (HEAD/index intact).
- `STAGED_CONTENT`: LOW risk — index entry persists.
- `UNSTAGED_CONTENT`: **POTENTIALLY_MEDIUM** — if a `M`-status file is lost, its bytes are not
  in HEAD or index; `git restore --worktree` would wipe the unstaged change. Recover only from
  external copies (recycle bin, editor history, autosave).
- `UNTRACKED_CONTENT`: **POTENTIALLY_MEDIUM** — `recyclebin_backup: true` may route the unlink
  to the OS recycle bin; if emptied before noticed, lost.
- **No permanent data loss observed** in any case (`.git/` always intact).

## Explicitly unresolved
**The specific component is unresolved.** Do NOT state "race confirmed", "timing bug
confirmed", or "filter-driver race confirmed".

Use instead:
- `SOURCE_OF_RUN_TO_RUN_VARIABILITY = UNRESOLVED`
- `WORKBUDDY_RUNTIME_ASSOCIATION = VERY_HIGH`
- `GIT_COMPONENT_CAUSE = UNRESOLVED`
- `TSBX_FILTER_CAUSE = HIGH_CONFIDENCE_HYPOTHESIS`

The anomaly is **intermittent across the observed native runs**; the source of run-to-run
variability remains unresolved.

## Possible future diagnostics (NOT required for this submission)
These are optional next steps for the vendor, marked **FUTURE_DIAGNOSTIC_IF_VENDOR_REQUESTS**:
1. **Narrow sandbox-rule A/B** — apply a scoped `inherit_user` rule for the dev workspace and
   re-run the native probe (see `NEXT-WORKBUDDY-GIT-EXPERIMENT.md`).
2. **ETW / ProcMon** capture of kernel-filter denials during a reproducing native run.

## STATUS
`PHENOMENON_CONFIRMED = YES · REAL_WORLD_INCIDENTS = CONFIRMED ·
SYNTHETIC_NATIVE_REPRODUCTION = CONFIRMED ·
PRODUCT_CAUSE = UNRESOLVED · COMPONENT_CAUSE = UNRESOLVED`

## ATTACHMENTS
**Committed in this repo (public evidence):**
- `report/NATIVE-R1-EVIDENCE.md` — sanitized public derivative of the R1 native run (WORKTREE_ONLY_LOSS reproduced, 59 files, HEAD/index intact)
- `report/NATIVE-R2-EVIDENCE.md` — sanitized public derivative of the R2 four-checkpoint run (A/B/C/D CLEAN, loss not reproduced in that one run)
- `bin/build-git-probe-f1-shape.ps1`, `bin/run-git-cycles.ps1`, `bin/check-worktree.ps1`,
  `bin/assert-native-workbuddy-context.ps1` (native harness — runnable, sanitized)
- `report/NATURAL-INCIDENT-F1.md` (F1 real incident)
- `report/ENVIRONMENT-MODEL.md`, `report/sanitized-evidence.md §C,§D`
- `report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md` (future diagnostic procedure)
- `report/MASTER-INVESTIGATION-LEDGER.md`, `report/EVIDENCE-INDEX.md` (reconciliation + claims)

**Raw local evidence (NOT AVAILABLE IN PUBLIC REPO — gitignored under `work/`, see `work/RAW-EVIDENCE-MANIFEST.md`):**
- `work/native-runs/2026-08-14T21-43-52Z-8d51e361d168/PHASE1_FINAL_REPORT.md` (R1 repro log) — `RAW_LOCAL_SOURCE` for `report/NATIVE-R1-EVIDENCE.md`
- `work/native-runs/2026-08-14T15-32-33Z-jf10pgjgdoiu/REPAIR_FINAL_REPORT.md` (R1 evidence-localization repair log — its "localized to final `git checkout master`" claim is retracted) — `RAW_LOCAL_SOURCE`
- `work/native-runs/2026-08-15T06-51-51Z-c7de59f17452/REPAIR_R2_FINAL_REPORT.md` (R2 clean-run log) — `RAW_LOCAL_SOURCE` for `report/NATIVE-R2-EVIDENCE.md`

These raw logs are **not part of the public repository**. The sanitized public
derivatives (`report/NATIVE-R1-EVIDENCE.md`, `report/NATIVE-R2-EVIDENCE.md`) carry
the canonical evidence and are mapped to the raw logs via `work/RAW-EVIDENCE-MANIFEST.md`
for future re-verification without exposing raw data.
