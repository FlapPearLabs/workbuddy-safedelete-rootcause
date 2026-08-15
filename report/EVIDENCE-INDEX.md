# EVIDENCE INDEX

Every major public claim, with its evidence and confidence. Mirrors
[`MASTER-INVESTIGATION-LEDGER.md`](MASTER-INVESTIGATION-LEDGER.md) but organized by claim.

Legend:
`STATUS` ∈ {CONFIRMED, REPRODUCED, PROVEN, NEGATIVE CONTROL, FALSIFIED, HIGH_CONFIDENCE_INFERENCE, HYPOTHESIS, UNKNOWN}
`CONFIDENCE` ∈ {CONFIRMED, HIGH, MEDIUM, LOW, UNRESOLVED}

---

## Bug A — npm ci / Node safe-delete

### CLAIM NPM-01
`npm ci` can be interrupted by the safe-delete bulk-guard after partial mutation of
`node_modules`.

- STATUS = CONFIRMED
- CONFIDENCE = CONFIRMED
- PRIMARY_EVIDENCE = `report/results-npm-ci.txt` (`NPM_CI_PHASE2_CI_EXIT=1`,
  `NPM_CI_PHASE2_BULK_GUARD_TRIGGERED=yes`)
- SECONDARY_EVIDENCE = `report/sanitized-evidence.md §E.3`
- REPRO_METHOD = `bin/repro-npm-ci.ps1` (1-click via `bin/repro-all.ps1`)
- NEGATIVE CONTROLS = NORMAL `npm ci` exit 0, no guard
- NOT_PROVEN = that *every* package-manager operation fails (only SHIM-active `npm ci` tested)

### CLAIM NPM-02
The failure is non-atomic: a small file (`.package-lock.json`) is trashed by the shim
**before** the bulk-guard fires on the larger batch.

- STATUS = PROVEN (smoking gun)
- CONFIDENCE = CONFIRMED
- PRIMARY_EVIDENCE = `NPM_CI_PHASE2_SHIM_TRASH_EVENT … path=…node_modules\.package-lock.json`
  in `report/results-npm-ci.txt`
- SECONDARY_EVIDENCE = `report/sanitized-evidence.md §E.3` partial-mutation proof
- REPRO_METHOD = `bin/repro-npm-ci.ps1`
- NEGATIVE CONTROLS = NORMAL mode: 92 files, REMOVED=0
- NOT_PROVEN = the exact ordering of IPC vs. recycle-bin routing

### CLAIM NPM-03
Components `genie-safe-delete.cjs` + `safe-delete-bulk-guard.cjs` are the cause.

- STATUS = CONFIRMED (component)
- CONFIDENCE = CONFIRMED
- PRIMARY_EVIDENCE = `report/sanitized-evidence.md §A` (shim wraps `fs.rmSync`),
  §B (guard throws at threshold 20)
- SECONDARY_EVIDENCE = sha256 `A9F9800C…302D1C7` and `EA40BA9D…88CA822`
- REPRO_METHOD = static read + lab A/B
- NEGATIVE CONTROLS = shim-off `npm ci` passes
- NOT_PROVEN = interaction with npm versions other than 10.x

---

## Bug B — Git worktree physical loss

### CLAIM GIT-01
Tracked physical files can disappear in a WorkBuddy-native execution while HEAD/index remain
intact (WORKTREE_ONLY_LOSS).

- STATUS = CONFIRMED
- CONFIDENCE = CONFIRMED
- PRIMARY_EVIDENCE = `report/NATIVE-R1-EVIDENCE.md`
  (R1: 59 files, HEAD_INDEX_TREE_MATCH=YES, FSCK_HEALTHY=YES)
- RAW_LOCAL_SOURCE = `work/native-runs/2026-08-14T21-43-52Z-8d51e361d168/PHASE1_FINAL_REPORT.md` — **NOT AVAILABLE IN PUBLIC REPO**
- SECONDARY_EVIDENCE = `report/NATURAL-INCIDENT-F1.md` (F1: 18 files); `report/sanitized-evidence.md §F` (5+ user events)
- REPRO_METHOD = `bin/build-git-probe-f1-shape.ps1` + `bin/run-git-cycles.ps1`, run **inside** a WorkBuddy tool-call
- NEGATIVE CONTROLS = NORMAL 11/11 CLEAN; SHIM-ONLY 11/11 CLEAN
- NOT_PROVEN = which specific kernel component performs the mutation

### CLAIM GIT-02
The Node safe-delete shim alone causes Bug B.

- STATUS = FALSIFIED_BY_SHIM_ONLY_CONTROL
- CONFIDENCE = CONFIRMED (falsified)
- PRIMARY_EVIDENCE = `report/results-git-shim-only.txt` (11/11 CLEAN);
  `report/sanitized-evidence.md §E.4`
- SECONDARY_EVIDENCE = `git.exe` is native; shim patches only Node `fs.*`
- REPRO_METHOD = Mavis lab Git A/B SHIM-ONLY
- NEGATIVE CONTROLS = N/A (this claim is itself the negative control)
- NOT_PROVEN = n/a

### CLAIM GIT-03
The `tsbx.dll` kernel filter (or `ModifyBackup` IPC / recycle-bin routing) specifically causes
Bug B.

- STATUS = NOT_PROVEN
- CONFIDENCE = HIGH_CONFIDENCE_HYPOTHESIS
- PRIMARY_EVIDENCE = `report/ROOT_CAUSE_CLOSURE_REPORT.md §B`; `report/NATIVE-R2-EVIDENCE.md`
  (`TSBX_FILTER_CAUSE=HIGH_CONFIDENCE_HYPOTHESIS`)
- RAW_LOCAL_SOURCE = `work/native-runs/2026-08-15T06-51-51Z-c7de59f17452/REPAIR_R2_FINAL_REPORT.md` — **NOT AVAILABLE IN PUBLIC REPO**
- SECONDARY_EVIDENCE = `tsbx_rules.json` deny_write default + no `<WORKSPACE>\**` allow;
  native ancestry confirmed; never reproduced outside WorkBuddy
- REPRO_METHOD = inference from policy + negative controls (no direct denial capture)
- NEGATIVE CONTROLS = R2 four-checkpoint run all CLEAN (loss not reproduced that run)
- NOT_PROVEN = direct observation of a kernel-filter denial of a specific git file op

### CLAIM GIT-04
Bug B is **intermittent** across observed native runs (R1 reproduced, R2 clean).

- STATUS = CONFIRMED (intermittency observed)
- CONFIDENCE = CONFIRMED
- PRIMARY_EVIDENCE = R1 `report/NATIVE-R1-EVIDENCE.md` vs R2 `report/NATIVE-R2-EVIDENCE.md`
  (`NATIVE_RERUN_NOT_REPRODUCED_IN_ONE_RUN=YES`)
- RAW_LOCAL_SOURCE = R1 `work/native-runs/2026-08-14T21-43-52Z-8d51e361d168/PHASE1_FINAL_REPORT.md` and R2 `work/native-runs/2026-08-15T06-51-51Z-c7de59f17452/REPAIR_R2_FINAL_REPORT.md` — **NOT AVAILABLE IN PUBLIC REPO**
- SECONDARY_EVIDENCE = user-side recurrence is also sporadic (5+ events over 4 days)
- REPRO_METHOD = two independent native runs
- NEGATIVE CONTROLS = R2 clean run
- NOT_PROVEN = the trigger condition for the intermittency

### CLAIM GIT-05
The WorkBuddy runtime is associated with the loss.

- STATUS = OBSERVED_ASSOCIATION = STRONG
- CONFIDENCE = VERY_HIGH
- PRIMARY_EVIDENCE = `report/NATIVE-R1-EVIDENCE.md` / `report/NATIVE-R2-EVIDENCE.md` (`WORKBUDDY_RUNTIME_ASSOCIATION=VERY_HIGH`);
  native ancestry to `sandbox-cli.exe`/`WorkBuddy.exe`
- SECONDARY_EVIDENCE = loss never observed from a non-WorkBuddy shell
- REPRO_METHOD = `assert-native-workbuddy-context.ps1`
- NEGATIVE CONTROLS = NORMAL/SHIM-ONLY lab clean
- NOT_PROVEN = component-level attribution (see GIT-03)

### CLAIM GIT-06
The specific component cause of Bug B.

- STATUS = UNKNOWN
- CONFIDENCE = UNRESOLVED
- PRIMARY_EVIDENCE = `report/NATIVE-R1-EVIDENCE.md` / `report/NATIVE-R2-EVIDENCE.md` (`GIT_COMPONENT_CAUSE=UNRESOLVED`)
- SECONDARY_EVIDENCE = both R1 and R2 lack direct component-level evidence
- REPRO_METHOD = n/a (open question)
- NEGATIVE CONTROLS = n/a
- NOT_PROVEN = any single component definitively identified

---

## Cross-cutting

### CLAIM ENV-01
`tsbx_rules.json` default policy is deny_write with `recyclebin_backup: true` and no
`<WORKSPACE>\**` allow rule.

- STATUS = CONFIRMED
- CONFIDENCE = CONFIRMED
- PRIMARY_EVIDENCE = `report/tsbx_rules.original.json`; `report/sanitized-evidence.md §C`
- SHA256 = `30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A`

### CLAIM REV-01
The R2 evidence pack is independently reviewable.

- STATUS = CONFIRMED
- CONFIDENCE = CONFIRMED
- PRIMARY_EVIDENCE = independent reviewer: **R2 HARNESS REVIEW = PASS**
- SECONDARY_EVIDENCE = `report/INVESTIGATOR-CONTRIBUTIONS.md`
