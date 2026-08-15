# INVESTIGATION TIMELINE

Chronological record of the WorkBuddy filesystem-interference investigation.
No conversations are pasted; only decisions and evidence are summarized.

---

## Stage 1 — Initial real zhihu-grabber worktree disappearances (2026-08-10 → 08-13)
User observed repeated tracked-file vanishings after `git switch` / `git merge` in
`zhihu-grabber-toolkit`. Pattern: ` D` lines in `git status`, HEAD/index/blob intact,
recovered via `git restore --worktree`. Logged as 5+ audit-log events.
→ `report/sanitized-evidence.md §F`, `report/NATURAL-INCIDENT-F1.md`

## Stage 2 — Git integrity checks
For every event: `git rev-parse HEAD` healthy, `git write-tree` matches index, `git fsck`
clean, `git ls-remote` matches remote. Established the **WORKTREE_ONLY_LOSS** signature:
HEAD=yes, INDEX=yes, PHYSICAL=no.
→ `report/NATURAL-INCIDENT-F1.md` (GIT INTEGRITY)

## Stage 3 — Non-destructive recovery
Standardized `git restore --worktree <path>` (no reset/clean/stash, no history rewrite) as
the safe recovery. Confirmed idempotent.
→ `report/NATURAL-INCIDENT-F1.md` (RECOVERY)

## Stage 4 — npm dependency partial-state incidents (2026-08-12)
User's project `node_modules` left partial after `npm ci` (e.g. `entities@8.0.0` missing
`dist/escape.js`). Bulk-guard event `SAFE_DELETE_BULK_CONFIRM_REQUIRED` in audit log.
→ `report/sanitized-evidence.md §F`

## Stage 5 — WorkBuddy safe-delete discovery (Mavis)
Minimax/Mavis read-only forensics found the `genie-safe-delete.cjs` Node shim and
`safe-delete-bulk-guard.cjs`.
→ `report/ROOT_CAUSE_CLOSURE_REPORT.md §A`, `report/sanitized-evidence.md §A,§B`

## Stage 6 — Node shim inspection
Shim wraps `fs.unlinkSync`/`fs.rmSync`/etc. when `CODEBUDDY_SESSION_ID` set; reroutes to
`genie-trash` / `Microsoft.VisualBasic.FileIO…SendToRecycleBin`.
→ `report/sanitized-evidence.md §A`

## Stage 7 — Bulk-guard reproduction (Mavis)
Disposable lab reproduced `npm ci` abort with `SAFE_DELETE_BULK_CONFIRM_REQUIRED
{count:59,threshold:20}`. Shim report proved **non-atomic partial mutation**
(`.package-lock.json` trashed before guard fired).
→ `report/sanitized-evidence.md §E.3`, `report/BUG-A-NPM-SAFE-DELETE.md`

## Stage 8 — Minimax/Mavis NORMAL vs SHIM A/B
Git A/B: 11/11 `WORKTREE_CHECK_VERDICT=CLEAN` in NORMAL and SHIM-ONLY. **Node shim ruled
out for Bug B.**
→ `report/sanitized-evidence.md §E.4`, `report/BUG-B-GIT-WORKTREE-LOSS.md`

## Stage 9 — Git shim-only negative control
SHIM-ONLY (env + `NODE_OPTIONS=--require=genie-safe-delete.cjs`) still 11/11 CLEAN →
confirmation that the shim is not the Git-loss mechanism.
→ `report/results-git-shim-only.txt`

## Stage 10 — tsbx/sandbox policy investigation
`tsbx_rules.json`: `default_action: deny_write`, `recyclebin_backup: true`, no `<WORKSPACE>\**`
allow rule. `tsbx.dll` kernel minifilter vocabulary extracted.
→ `report/sanitized-evidence.md §C,§D`, `report/ENVIRONMENT-MODEL.md`

## Stage 11 — F1 natural incident (2026-08-14)
`zhihu-grabber-toolkit`: `git merge --ff-only` with a **3-path** delta (0 deletions) left
**18 unrelated test files** missing from the worktree. Recovered via `git restore
--worktree`. Mirrors the earlier pattern at larger scale.
→ `report/NATURAL-INCIDENT-F1.md`

## Stage 12 — Dedicated rootcause repo creation
`FlapPearLabs/workbuddy-safedelete-rootcause` created as the canonical repro + root-cause +
vendor-report repository (separate from the production repo).
→ `README.md`

## Stage 13 — Native WorkBuddy context validation (R1, 2026-08-14)
`assert-native-workbuddy-context.ps1` proved the probe ran under real `sandbox-cli.exe`
ancestry (R1 session id absent → UNKNOWN, but ancestry confirmed; R2 later got YES).
→ `report/NATIVE-R1-EVIDENCE.md` (context assertion; RAW_LOCAL_SOURCE: `work/native-runs/2026-08-14T21-43-52Z-8d51e361d168/context-assert.txt` — NOT AVAILABLE IN PUBLIC REPO)

## Stage 14 — Native synthetic R1: 59-file WORKTREE_ONLY_LOSS (2026-08-14)
WorkBuddy-native PROBE_B (F1-shape) **reproduced** `WORKTREE_ONLY_LOSS`: 59 unrelated
tracked files physically absent, HEAD/index intact, HEAD_TREE==INDEX_TREE, fsck healthy.
Persisted across checkout-back (not self-healing).
→ `report/NATIVE-R1-EVIDENCE.md` (RAW_LOCAL_SOURCE: `work/native-runs/2026-08-14T21-43-52Z-8d51e361d168/PHASE1_FINAL_REPORT.md` — NOT AVAILABLE IN PUBLIC REPO)
→ `report/BUG-B-GIT-WORKTREE-LOSS.md` (SYNTHETIC R1)

## Stage 15 — Evidence-localization repair (R1-repair, 2026-08-14)
Harness repair closed two gaps (pre-first-checkout baseline; runner always finalizes).
Rerun (CASE A) observed the non-clean worktree at the post-final-checkout checkpoint but lacked a physical pre-final-checkout checkpoint, so the exact causal operation was **not** localized. The prior "localized to the build's final `git checkout master`" characterization is retracted.
`GIT_COMPONENT_CAUSE=UNRESOLVED`, `TSBX_FILTER_CAUSE=HIGH_CONFIDENCE_HYPOTHESIS`.
Committed as `b28ca20…` on `fix/phase1-evidence-localization`.
→ `report/NATIVE-R1-EVIDENCE.md` (retraction note; RAW_LOCAL_SOURCE: `work/native-runs/2026-08-14T15-32-33Z-jf10pgjgdoiu/REPAIR_FINAL_REPORT.md` — NOT AVAILABLE IN PUBLIC REPO)

## Stage 16 — R2 four-checkpoint harness (2026-08-15)
`build-git-probe-f1-shape.ps1` gained four physical checkpoints (A/B/C/D) to pinpoint the
CLEAN→NON_CLEAN interval. Parser/attribution tests fixed (removed `mavis-trash` dependency).
Committed as `4243b04…` (independent-review PASS).
→ `report/NATIVE-R2-EVIDENCE.md` (RAW_LOCAL_SOURCE: `work/native-runs/2026-08-15T06-51-51Z-c7de59f17452/REPAIR_R2_FINAL_REPORT.md` — NOT AVAILABLE IN PUBLIC REPO)

## Stage 17 — R2: A/B/C/D CLEAN, one-shot non-reproduction (2026-08-15)
Controlled R2 rerun: CHECKPOINT A/B/C/D all CLEAN, loss **NOT** reproduced. Combined with
R1's reproduction, establishes **INTERMITTENT_ACROSS_OBSERVED_NATIVE_RUNS = YES**.
`SOURCE_OF_RUN_TO_RUN_VARIABILITY = UNRESOLVED`.
→ `report/BUG-B-GIT-WORKTREE-LOSS.md` (R2)

## Stage 18 — Final independent review PASS (2026-08-15)
Independent reviewer returned **R2 HARNESS REVIEW = PASS**, correcting overclaims and gating
vendor publication on a clean evidence pack — which this consolidation delivers.
→ `report/INVESTIGATOR-CONTRIBUTIONS.md`

---

## Consolidation (2026-08-15)
This canonical publication assembled the complete, independently reviewable investigation
repository per `WORKBUDDY_COMPLETE_INVESTIGATION_ARCHIVE_AND_PUBLICATION`. Master branch
fast-forwarded to include R1+R2 (`4243b04`). New public docs added under
`docs/vendor-handoff-final`.
