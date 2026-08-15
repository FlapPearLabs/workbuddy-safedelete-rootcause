# NEXT-WORKBUDDY-GIT-EXPERIMENT.md

> **Purpose.** The `bin/repro-all.ps1` orchestrator proves that the Node
> shim (the `genie-safe-delete.cjs` layer) is **not** the cause of the Git
> worktree file loss observed in the user's audit log (11/11 per-step
> `WORKTREE_CHECK_VERDICT=CLEAN` in both NORMAL and SHIM-ONLY modes).
> The kernel sandbox/filesystem layer is the leading candidate mechanism
> (`tsbx.dll` HIGH_CONFIDENCE_HYPOTHESIS), but its exact
> attachment/interception behavior was not directly traced. This document
> is a **complete, copy-pasteable procedure** for running the **authoritative
> F1-shape** Git probe (`bin/build-git-probe-f1-shape.ps1`) inside a real
> WorkBuddy tool-call, plus the deterministic offline validation gate.
>
> **Authoritative Bug B harness.** The successful R1 native reproduction
> (59-file worktree-only loss) and the R2 four-checkpoint controlled run
> both used the **F1-shape** builder: 160 tracked files / 60 test-like /
> tiny 3-path FF delta (2 modified + 1 added, 0 deleted) with physical
> checkpoints A/B/C/D. `bin/build-git-probe.ps1` (60 files, 46 modified /
> 5 deleted / 16 added / 4 renamed) is **HISTORICAL / AUXILIARY** — it is a
> negative-control stress probe only and is NOT the Bug B reproduction shape.

---

## 0. Hard rules — read this first

1. **Do not touch any path outside the disposable lab.** The lab root is
   the directory the user cloned this repo into. The lab scripts
   auto-resolve it and refuse any command targeting the production repo.
2. **Do not run `git reset --hard`, `git clean -fd`, or
   `git checkout HEAD -- <path>`** inside the lab repos. The lab uses
   non-destructive `git restore --worktree -- .` to clean up.
3. **Do not edit `tsbx_rules.json` until Phase 2A.** Phase 1 is the
   unmodified WorkBuddy baseline. Phase 2A only adds a narrow lab rule.
4. **Do not auto-restart WorkBuddy.** Phase 2B requires a user-controlled
   restart between Phase 2A and the Git A/B re-run. The procedure pauses
   and asks the user.
5. **Do not force-push, do not rewrite Git history.** The lab repo is
   disposable; commits are local-only.
6. **Do not auto-submit any bug report to Tencent.** The user controls filing.
7. **Save every evidence artifact** to the lab output dir
   (`work/repro-workbuddy-phase1\`, `work/repro-workbuddy-phase2a\`,
   `work/repro-workbuddy-phase2b\`, `work/repro-workbuddy-phase2c\`).
   Each phase produces a `results.txt` and an `outcome.txt`.
8. **Use a fresh unique probe repo per run.** The F1-shape builder refuses
   to start if the target path already exists (release-gate P4). Always use
   a `-Repo` path containing a fresh timestamp/GUID, e.g.
   `fixtures\git-probe-f1shape-<ts>-<guid>`. No cleanup of a previous probe
   is then required.

---

## 1. Result-record format (P1-4: self-describing)

Every per-step record emitted by `bin/check-worktree.ps1` carries a
`label=<step>` token on the verdict line itself, so the consumer does
not need a separate index file. Example:

```
WORKTREE_CHECK_LABEL=step-1a-switch-to-feature
WORKTREE_CHECK_HEAD=<sha>
WORKTREE_CHECK_HEAD_TREE=<40-char root tree sha>
WORKTREE_CHECK_INDEX_TREE=<40-char root tree sha>
WORKTREE_CHECK_HEAD_INDEX_TREE_MATCH=YES
WORKTREE_CHECK_HEAD_PATH_COUNT=160
WORKTREE_CHECK_INDEX_PATH_COUNT=160
WORKTREE_CHECK_UNION_PATH_COUNT=160
WORKTREE_CHECK_PHYSICAL_PRESENT_COUNT=160
WORKTREE_CHECK_MISSING_COUNT=0
WORKTREE_CHECK_VERDICT label=step-1a-switch-to-feature value=CLEAN
WORKTREE_CHECK_FSCK_HEALTHY=YES
```

The verdict is one of:
- `CLEAN` — every path in the union is in (HEAD ∩ INDEX ∩ physical);
  HEAD_TREE == INDEX_TREE; no `D` status; fsck healthy.
- `WORKTREE_ONLY_LOSS` — at least one path: HEAD=yes, INDEX=yes, physical=no.
- `INDEX_AND_WORKTREE_LOSS` — at least one path: HEAD=yes, INDEX=no, physical=no.
- `INDEX_ONLY_DIVERGENCE` — at least one path: HEAD=yes, INDEX=no, physical=yes.
- `INDEX_ADDITION_PHYSICAL_MISSING` — at least one path: HEAD=no, INDEX=yes, physical=no.
- `WORKTREE_CONTENT_DIVERGENCE` — at least one path: HEAD=yes, INDEX=yes,
  physical=yes, INDEX_BLOB != PHYSICAL_BLOB.
- `OTHER_STATE_DIVERGENCE` — anything else (incl. HEAD_TREE ≠ INDEX_TREE or fsck bad).

Per-op records (from `bin/run-git-cycles.ps1`):
```
GIT_OPERATION_STEP label=step-1a-switch-to-feature
GIT_OPERATION_TYPE=checkout
GIT_OPERATION_TARGET=feature-probe-f1shape
GIT_OPERATION_BRANCH_BEFORE=master
GIT_OPERATION_HEAD_BEFORE=<sha>
GIT_OPERATION_EXIT=0
GIT_OPERATION_OUTPUT=Switched to branch 'feature-probe-f1shape'
GIT_OPERATION_BRANCH_AFTER=feature-probe-f1shape
GIT_OPERATION_HEAD_AFTER=<sha>
EXPECTED_BRANCH=feature-probe-f1shape
ACTUAL_BRANCH=feature-probe-f1shape
EXPECTED_HEAD=<sha before op>
ACTUAL_HEAD=<sha after op>
GIT_OPERATION_TARGET_REACHED=YES
```

A non-zero exit OR `GIT_OPERATION_TARGET_REACHED=NO` produces a
`GIT_OPERATION_INTERFERENCE` line and stops further mutation cycles
(but the current state's check-worktree is still recorded).

**Check counts (canonical tokens, emitted by `bin/run-git-cycles.ps1`):**
- `GIT_CYCLES_EXPECTED_MUTATION_CHECK_COUNT=11` (5 switch-to-feature +
  5 switch-to-master + 1 merge = **11** mutation steps)
- `GIT_CYCLES_ACTUAL_MUTATION_CHECK_COUNT=<n>`
- `GIT_CYCLES_BASELINE_CHECK_COUNT=1` (the step-0 pre-operation baseline is
  OUTSIDE the 11 mutation checks)

The build phase asserts its own F1 shape (`bin/build-git-probe-f1-shape.ps1`):
```
GIT_PROBE_F1_SHAPE_BASE_TRACKED_COUNT=160
GIT_PROBE_F1_SHAPE_TEST_LIKE_COUNT=60
GIT_PROBE_F1_SHAPE_CHANGED_PATH_COUNT=3
GIT_PROBE_F1_SHAPE_MODIFIED_PATH_COUNT=2
GIT_PROBE_F1_SHAPE_ADDED_PATH_COUNT=1
GIT_PROBE_F1_SHAPE_DELETED_PATH_COUNT=0
GIT_PROBE_F1_SHAPE_VALID=YES
GIT_PROBE_F1_SHAPE_BUILD_OK=YES
CHECKPOINT_A_VERDICT=CLEAN
CHECKPOINT_B_VERDICT=CLEAN
CHECKPOINT_C_VERDICT=CLEAN
CHECKPOINT_D_VERDICT=CLEAN
GIT_PROBE_F1_SHAPE_WORKTREE_READY=YES
```

**Result classification — use `bin/classify-run.ps1`, not an ad-hoc parser.**
`classify-run.ps1` reads a `run-git-cycles.ps1` results file and emits a
structured outcome with `RUN_CLASSIFICATION=` and `WORKTREE_LOSS_REPRODUCED=`.
It distinguishes:
`CLEAN`, `WORKTREE_ONLY_LOSS`, `WORKTREE_CONTENT_DIVERGENCE`,
`PREEXISTING_NON_CLEAN`, `GIT_OPERATION_INTERFERENCE`,
`INSTRUMENTATION_ERROR`, `CHECKER_ERROR`, `NONZERO_GIT_EXIT`,
`TARGET_NOT_REACHED`.
`WORKTREE_LOSS_REPRODUCED` is `YES` **only** for physical worktree
loss/divergence evidence (WORKTREE_ONLY_LOSS /
INDEX_AND_WORKTREE_LOSS / INDEX_ADDITION_PHYSICAL_MISSING /
WORKTREE_CONTENT_DIVERGENCE). A git operation that was merely interfered
with never yields `YES` — it yields `NO` with
`RUN_CLASSIFICATION=GIT_OPERATION_INTERFERENCE`. A checker/instrumentation
failure yields `UNKNOWN`. A pre-existing non-clean baseline is classified
`PREEXISTING_NON_CLEAN` and is never attributed to the mutation under test.

The offline validation gate (no native sandbox required) is:

```powershell
powershell -ExecutionPolicy Bypass -File .\bin\test-owned-path-delete.ps1
powershell -ExecutionPolicy Bypass -File .\bin\test-classify-run.ps1
powershell -ExecutionPolicy Bypass -File .\bin\test-tsbx-lab-rule.ps1
powershell -ExecutionPolicy Bypass -File .\bin\test-outcome-parser.ps1
powershell -ExecutionPolicy Bypass -File .\bin\test-attribution-preop.ps1
# Expected: OWNED_PATH_DELETE_TEST=PASS, CLASSIFY_RUN_TEST=PASS,
#           TSBX_RULES_TEST_RESULT=PASS, PARSER_TEST_RESULT=PASS,
#           ATTRIBUTION_TEST_RESULT=PASS
```

---

## 2. Phase 1 — REAL WORKBUDDY BASELINE (no rule changes)

**Goal:** Determine whether the worktree file loss reproduces inside a
real WorkBuddy tool-call session, with `tsbx_rules.json` unchanged.

### 2.1 — Pre-flight

```powershell
# 1) Locate the lab repo (replace with the actual clone path).
#    IMPORTANT: the lab must be cloned to a non-temp path, because
#    genie-safe-delete.cjs:shouldUseNativeDelete deliberately bypasses
#    operations on os.tmpdir() paths.
$labRoot = Join-Path $env:USERPROFILE 'workbuddy-safedelete-rootcause'   # <-- replace if needed
Set-Location $labRoot

# 2) Sanity check: WorkBuddy is present and the lab scripts can find it.
& $labRoot\bin\repro-all.ps1 -OutputDir (Join-Path $labRoot 'work\repro-preflight') 2>&1 |
    Select-String -Pattern 'REPRO_ALL_WORKBUDDY_SHIM_AVAILABLE'
# Expected: REPRO_ALL_WORKBUDDY_SHIM_AVAILABLE=True
# If False, abort: the kernel sandbox cannot be exercised without a real install.
```

If preflight reports `SHIM_AVAILABLE=True`, proceed. Otherwise stop and
report to the user.

### 2.2 — Run the F1-shape Git probe from inside a WorkBuddy tool-call

```powershell
$labRoot = Join-Path $env:USERPROFILE 'workbuddy-safedelete-rootcause'   # <-- replace if needed
$phase1Dir = Join-Path $labRoot 'work\repro-workbuddy-phase1'
New-Item -ItemType Directory -Force -Path $phase1Dir | Out-Null

# 1) Fresh unique F1-shape repo (no cleanup needed: P4 refuses existing paths).
$repo = Join-Path $labRoot ('fixtures\git-probe-f1shape-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))

# 2) Build the F1-shape probe. The builder emits physical checkpoints
#    A/B/C/D and STOPS immediately if the worktree becomes non-clean.
#    Expected: GIT_PROBE_F1_SHAPE_BUILD_OK=YES, CHECKPOINT_A/B/C/D=... CLEAN,
#    GIT_PROBE_F1_SHAPE_WORKTREE_READY=YES.
& "$labRoot\bin\build-git-probe-f1-shape.ps1" -Repo $repo 2>&1 |
    Tee-Object -FilePath (Join-Path $phase1Dir 'build.txt')
# If any CHECKPOINT_*_VERDICT is not CLEAN, or if
# GIT_PROBE_F1_SHAPE_WORKTREE_READY=NO, or if
# FIRST_KNOWN_NON_CLEAN_CHECKPOINT is set:
#   -> STOP. Preserve build.txt + the probe repo as evidence. Do NOT run
#      run-git-cycles.ps1 on a builder that already lost files.

# 3) ONLY if the builder finished CLEAN / WORKTREE_READY=YES:
#    Run 5 switch cycles + 1 ff merge (11 mutation checks) on the
#    SINGLE-LEVEL feature branch feature-probe-f1shape.
& "$labRoot\bin\run-git-cycles.ps1" -Repo $repo -Cycles 5 `
    -BranchName 'feature-probe-f1shape' `
    -OutputFile (Join-Path $phase1Dir 'results.txt') `
    -Merge 2>&1 |
    Tee-Object -FilePath (Join-Path $phase1Dir 'cycles.txt')

# 4) Classify the structured result (replaces any ad-hoc parsing).
& "$labRoot\bin\classify-run.ps1" `
    -ResultsFile (Join-Path $phase1Dir 'results.txt') `
    -OutcomeFile (Join-Path $phase1Dir 'outcome.txt') |
    Out-Null
Get-Content (Join-Path $phase1Dir 'outcome.txt')
# Expected clean run:
#   RUN_CLASSIFICATION=CLEAN
#   WORKTREE_LOSS_REPRODUCED=NO
#   GIT_CYCLES_EXPECTED_MUTATION_CHECK_COUNT=11
#   GIT_CYCLES_ACTUAL_MUTATION_CHECK_COUNT=11
# A physical loss run:
#   RUN_CLASSIFICATION=WORKTREE_ONLY_LOSS
#   WORKTREE_LOSS_REPRODUCED=YES
```

**If `WORKTREE_LOSS_REPRODUCED: YES`:**

- Do **not** immediately `git restore`. First, copy `$repo\.git` to
  `(Join-Path $phase1Dir 'repo-snapshot.git')` so the post-loss state
  is preserved:
  ```powershell
  $snapDir = Join-Path $phase1Dir 'repo-snapshot.git'
  if (Test-Path $snapDir) {
      . (Join-Path $labRoot 'bin\_lib.ps1')
      Remove-OwnedProbePath -Path $snapDir -OwnedRoots @($phase1Dir)
  }
  Copy-Item -Recurse "$repo\.git" $snapDir
  ```
- Save the per-step `results.txt` and `outcome.txt` (already there).
- Save `git status`, `git fsck --no-reflogs`, and
  `git ls-files --error-unmatch <each missing path>` output to
  `(Join-Path $phase1Dir 'post-loss-snapshots.txt')`.
- **Then** and only then, run
  `git -C $repo restore --worktree -- .` to recover the disposable
  probe repo for the next phase.
- **Stop and report to the user.** Do not proceed to Phase 2 without
  the user's confirmation, because Phase 2A requires editing
  `tsbx_rules.json`.

**If `WORKTREE_LOSS_REPRODUCED: NO_IN_11_STEPS`:**
(the outcome shows `RUN_CLASSIFICATION=CLEAN`, `WORKTREE_LOSS_REPRODUCED=NO`,
`GIT_CYCLES_ACTUAL_MUTATION_CHECK_COUNT=11`)

- Save the same outcome record as `NO_IN_11_STEPS`.
- **Do not loop indefinitely.** 5 cycles + 1 merge = 11 steps, 11
  `WORKTREE_CHECK_VERDICT` lines. The probe is a strong negative if
  all 11 are `CLEAN`.
- **Stop and report to the user.** The kernel sandbox is either not
  active for this `git.exe` invocation, or the worktree file loss
  requires a different workload (more files, different file types, a
  specific branch shape) than the F1-shape probe. The investigation
  should be redirected.

**If `RUN_CLASSIFICATION` is anything else** (`GIT_OPERATION_INTERFERENCE`,
`PREEXISTING_NON_CLEAN`, `INSTRUMENTATION_ERROR`, `CHECKER_ERROR`):
record the outcome as-is; do NOT report it as a reproduction. Investigate
the classification before continuing.

### 2.3 — Phase 1 deliverables

1. `work/repro-workbuddy-phase1/build.txt` — F1-shape build output
   (checkpoints A/B/C/D + shape assertions)
2. `work/repro-workbuddy-phase1/cycles.txt` — full run output
3. `work/repro-workbuddy-phase1/results.txt` — structured per-step records
4. `work/repro-workbuddy-phase1/outcome.txt` — the structured outcome from
   `bin/classify-run.ps1`
5. (only if `WORKTREE_LOSS_REPRODUCED: YES`)
   `work/repro-workbuddy-phase1/repo-snapshot.git/`
   and `work/repro-workbuddy-phase1/post-loss-snapshots.txt`

---

## 3. Phase 2A — PREPARE rule (no Git probe yet)

**Goal:** With `tsbx_rules.json` modified to add a narrow
`inherit_user` rule covering only the lab root, prepare the rule change
in a safe, atomic, byte-exact-recoverable way. **Do not run the Git
probe in this phase** — the rule change only takes effect after a
WorkBuddy restart, and the procedure below pauses for that.

This phase **must not** be entered if Phase 1 reproduced the loss and
the post-loss evidence has not been saved. The user must explicitly
approve.

The live `tsbx_rules.json` is **not** modified by hand. The procedure
calls `bin/prepare-tsbx-lab-rule.ps1`, which:

1. Locates the exact active rules file (auto-resolves the WorkBuddy
   install; pass `-WorkbuddyInstall <path>` or `-RulesPath <synthetic>`
   to override).
2. Reads the current SHA256.
3. Backs up the original bytes to `<LAB>\work\tsbx-backup\`
   (outside the WorkBuddy install dir).
4. Validates the backup hash matches the source hash.
5. Parses the JSON via node.
6. Rejects the operation if a duplicate lab rule already exists.
7. Appends ONLY one rule to `file_rules_user`:
   ```json
   { "path": "<LAB>\\**", "type": "inherit_user" }
   ```
8. Writes the staged file to `<LAB>\work\tsbx-staging\`.
9. Re-parses the staged file and verifies the new entry is present.
10. Atomically renames the staged file over the target (same volume;
    cross-volume fallback = copy + verify + remove).
11. Records the new SHA and prints `RULE_PREPARED_RESTART_REQUIRED`.

The live `<WORKSPACE>\**` is **not** affected; the rule is scoped strictly
to `<LAB>\**`.

### 3.1 — Run prepare-tsbx-lab-rule

```powershell
$labRoot = Join-Path $env:USERPROFILE 'workbuddy-safedelete-rootcause'   # <-- replace if needed
$phase2aDir = Join-Path $labRoot 'work\repro-workbuddy-phase2a'
New-Item -ItemType Directory -Force -Path $phase2aDir | Out-Null

& "$labRoot\bin\prepare-tsbx-lab-rule.ps1" -LabRoot $labRoot 2>&1 |
    Tee-Object -FilePath (Join-Path $phase2aDir 'prepare.txt')
# Expected:
#   TSBX_RULES_PRE_EDIT_SHA256=<sha>
#   TSBX_RULES_BACKUP_PATH=<LAB>\work\tsbx-backup\tsbx_rules.original.<ts>.json
#   TSBX_RULES_BACKUP_SHA256=<sha>      (== pre-edit sha)
#   TSBX_RULES_POST_EDIT_SHA256=<sha>   (different from pre-edit)
#   TSBX_RULES_LAB_RULE_PATH=<LAB>\**
#   TSBX_RULES_LAB_RULE_TYPE=inherit_user
#   TSBX_RULES_RULE_PREPARED_RESTART_REQUIRED=YES
#   TSBX_RULES_PHASE2A_OK=YES
```

### 3.2 — STOP and tell the user

```
RULE_PREPARED_RESTART_REQUIRED

The kernel sandbox reads tsbx_rules.json at <unknown time> (likely on
WorkBuddy startup). To make the new rule effective, please:

  1) save all your open WorkBuddy work
  2) quit WorkBuddy
  3) reopen WorkBuddy
  4) re-invoke this same tool-call

After WorkBuddy is restarted, the procedure continues from Phase 2B.
```

If the user does not want to restart, **stop and report**. Do not
proceed. (Phase 2C must still be run to restore the original bytes —
see Phase 2C below.)

### 3.3 — Phase 2A deliverables

1. `work/repro-workbuddy-phase2a/prepare.txt` — full prepare output
2. (recorded in `prepare.txt`) the backup path under
   `work/tsbx-backup/` and the post-edit SHA

---

## 4. Phase 2B — AFTER RESTART (run the Git A/B)

**Goal:** After a WorkBuddy restart, run the same F1-shape Git probe with
the narrow `inherit_user` rule active.

### 4.1 — Pre-flight (in the new WorkBuddy tool-call)

```powershell
$labRoot = Join-Path $env:USERPROFILE 'workbuddy-safedelete-rootcause'   # <-- replace if needed
$phase2bDir = Join-Path $labRoot 'work\repro-workbuddy-phase2b'
New-Item -ItemType Directory -Force -Path $phase2bDir | Out-Null

# Locate the live rules file via the same auto-discovery as the lab scripts.
. (Join-Path $labRoot 'bin\_lib.ps1')
$wbInstall = Resolve-WorkbuddyInstallPath
if (-not $wbInstall) { throw "WorkBuddy install not found; pass -WorkbuddyInstall explicitly" }
$rulesPath = Join-Path $wbInstall 'resources\app.asar.unpacked\cli\vendor\sandbox\5.3.3\tsbx_rules.json'
if (-not (Test-Path $rulesPath)) {
    $candidates = Get-ChildItem (Join-Path $wbInstall 'resources\app.asar.unpacked\cli\vendor\sandbox') -Directory -ErrorAction SilentlyContinue
    $alt = $candidates | Where-Object { Test-Path (Join-Path $_.FullName 'tsbx_rules.json') } | Select-Object -First 1
    if ($alt) { $rulesPath = Join-Path $alt.FullName 'tsbx_rules.json' }
}
$currentSha = (Get-FileHash $rulesPath -Algorithm SHA256).Hash

# Find the most recent prepare.txt that contains the post-edit SHA.
$prepareTxt = (Get-ChildItem (Join-Path $labRoot 'work\repro-workbuddy-phase2a') -Filter 'prepare.txt' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
$expectedSha = (Get-Content $prepareTxt | Select-String -Pattern '^TSBX_RULES_POST_EDIT_SHA256=').ToString().Substring(28)
"PHASE2B_CURRENT_SHA=$currentSha"
"PHASE2B_EXPECTED_SHA=$expectedSha"
if ($currentSha -ne $expectedSha) {
    throw "Phase 2A rule is not active on disk. Did WorkBuddy reload the rules file? Investigate before continuing."
}

# Verify the narrow rule is present
$rules = Get-Content $rulesPath -Raw | ConvertFrom-Json
$labPath = ($labRoot.TrimEnd('\','/')) + '\\**'
$found = $rules.file_rules_user | Where-Object { $_.path -eq $labPath -and $_.type -eq 'inherit_user' }
if (-not $found) {
    throw "Lab rule not found in file_rules_user. Phase 2A did not complete correctly."
}
```

### 4.2 — Run the same F1-shape probe (5 cycles + 1 merge)

This is **byte-equivalent** to Phase 1.2:

```powershell
$repo = Join-Path $labRoot ('fixtures\git-probe-f1shape-allowrule-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
& "$labRoot\bin\build-git-probe-f1-shape.ps1" -Repo $repo 2>&1 |
    Tee-Object -FilePath (Join-Path $phase2bDir 'build.txt')
# Same stop rule as Phase 1.2: proceed only if WORKTREE_READY=YES.
& "$labRoot\bin\run-git-cycles.ps1" -Repo $repo -Cycles 5 `
    -BranchName 'feature-probe-f1shape' `
    -OutputFile (Join-Path $phase2bDir 'results.txt') `
    -Merge 2>&1 |
    Tee-Object -FilePath (Join-Path $phase2bDir 'cycles.txt')
& "$labRoot\bin\classify-run.ps1" `
    -ResultsFile (Join-Path $phase2bDir 'results.txt') `
    -OutcomeFile (Join-Path $phase2bDir 'outcome.txt') |
    Out-Null
```

Apply the same interpretation as Phase 1.2: outcome is
`WORKTREE_LOSS_REPRODUCED: <YES | NO_IN_11_STEPS | UNKNOWN>` plus
`RUN_CLASSIFICATION=...`.

### 4.3 — Phase 2B deliverables

1. `work/repro-workbuddy-phase2b/build.txt`
2. `work/repro-workbuddy-phase2b/cycles.txt`
3. `work/repro-workbuddy-phase2b/results.txt`
4. `work/repro-workbuddy-phase2b/outcome.txt`

---

## 5. Phase 2C — RESTORE (always required)

**Goal:** Restore the live `tsbx_rules.json` to the byte-exact
original from the Phase 2A backup, regardless of the Phase 2B outcome.

This phase **must** run. The rule change is system-wide; leaving the
lab rule on a non-dev machine is not acceptable.

`bin/restore-tsbx-lab-rule.ps1` performs a byte-exact restore from the
backup. The staged-JSON diagnostic is **non-fatal**: if it fails (or
`node` is unavailable), restore still proceeds, because the byte-exact
backup SHA is re-verified against the target after the move. The restore
path remains usable even if an intermediate diagnostic operation fails.

### 5.1 — Run restore-tsbx-lab-rule

```powershell
$labRoot = Join-Path $env:USERPROFILE 'workbuddy-safedelete-rootcause'   # <-- replace if needed
$phase2cDir = Join-Path $labRoot 'work\repro-workbuddy-phase2c'
New-Item -ItemType Directory -Force -Path $phase2cDir | Out-Null

# Find the most recent backup from Phase 2A.
$backupPath = (Get-ChildItem (Join-Path $labRoot 'work\tsbx-backup') -Filter 'tsbx_rules.original.*.json' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName

& "$labRoot\bin\restore-tsbx-lab-rule.ps1" -BackupPath $backupPath 2>&1 |
    Tee-Object -FilePath (Join-Path $phase2cDir 'restore.txt')
# Expected:
#   TSBX_RULES_ORIGINAL_SHA256=<sha>          (= the pre-2A SHA)
#   TSBX_RULES_RESTORED_FROM=<backup path>
#   TSBX_RULES_RESTORED_SHA256=<sha>          (== ORIGINAL_SHA256)
#   TSBX_RULES_ORIGINAL_RULES_RESTORED_RESTART_REQUIRED=YES
#   TSBX_RULES_PHASE2C_OK=YES
```

### 5.2 — STOP and tell the user

```
ORIGINAL_RULES_RESTORED_RESTART_REQUIRED

The original tsbx_rules.json bytes have been restored. WorkBuddy
needs to be restarted again so the runtime picks up the restored
file. Please:

  1) save all your open WorkBuddy work
  2) quit WorkBuddy
  3) reopen WorkBuddy
  4) confirm in a new tool-call that the live tsbx_rules.json SHA
     matches <ORIGINAL_SHA256> from work/repro-workbuddy-phase2c/restore.txt
```

### 5.3 — Phase 2C deliverables

1. `work/repro-workbuddy-phase2c/restore.txt`

---

## 6. What the user does after all phases

1. Attach the `outcome.txt` from Phase 1 and Phase 2B to the
   investigation.
2. If Phase 1 = `WORKTREE_LOSS_REPRODUCED: YES` (with
   `RUN_CLASSIFICATION=WORKTREE_ONLY_LOSS` or `WORKTREE_CONTENT_DIVERGENCE`)
   and Phase 2B = `NO_IN_11_STEPS`:
   - `SANDBOX_POLICY_CAUSE_CONFIRMED`.
3. If Phase 1 = `NO_IN_11_STEPS`:
   - the investigation **stays at HIGH_CONFIDENCE_INFERENCE** for
     Issue B's component-level cause; the bug report's "Severity"
     and "Issue B" sections should remain downgraded accordingly.
4. Any other classification (interference / instrumentation / checker
   error / preexisting) must be reported as-is and must NOT be counted
   as a reproduction.

---

## 7. Phase 3 — Optional ETW / ProcMon capture

If the user already has ProcMon installed (`procmon.exe` from
Sysinternals), or can run `xperf` (Windows Performance Toolkit),
Phase 3 produces direct evidence of the relevant filesystem operations and
sandbox / filter activity (a denial is a possible but not presupposed outcome).

### 7.1 — ProcMon (preferred if available)

Inside a WorkBuddy tool-call session, in one PowerShell process:

```powershell
# 1) Start a 60-second ProcMon trace
& 'C:\Tools\Procmon\procmon.exe' /AcceptEula /Quiet /BackingFile "$labRoot\work\repro-etw\pm-trace.pml"

# 2) Immediately run the F1-shape probe (Phase 1.2 workflow, again,
#    with a fresh unique repo)
& "$labRoot\bin\build-git-probe-f1-shape.ps1" -Repo $repo
& "$labRoot\bin\run-git-cycles.ps1" -Repo $repo -Cycles 5 -BranchName 'feature-probe-f1shape' -OutputFile "$labRoot\work\repro-etw\results.txt" -Merge

# 3) After 60 seconds, stop the trace
Start-Sleep -Seconds 60
& 'C:\Tools\Procmon\procmon.exe' /Terminate

# 4) Convert the .pml to a CSV and filter
& 'C:\Tools\Procmon\procmon.exe' /AcceptEula /OpenLog "$labRoot\work\repro-etw\pm-trace.pml" /SaveAs "$labRoot\work\repro-etw\pm-trace.csv"
```

Inspect `$labRoot\work\repro-etw\pm-trace.csv` filtered to:

- `Process Name is git.exe or sandbox-cli.exe`
- `Path begins with $labRoot\`
- `Operation is CreateFile or WriteFile or SetDispositionInformationFile or SetRenameInformationFile`
- `Result is ACCESS DENIED or REPARSE`

If the trace shows `ACCESS DENIED` for `git.exe` writes/deletes inside
`$labRoot`, the kernel sandbox hypothesis is directly observed.

### 7.2 — xperf / ETW (alternative)

```powershell
# 1) Start the ETW session
xperf -on PROC_THREAD+LOADER+SYSCALL+DISK_IO+FILE_IO+FILTC -stackwalk FileIo+DiskIo -f "$labRoot\work\repro-etw\etw-trace.etl"

# 2) Run the F1-shape probe
& "$labRoot\bin\build-git-probe-f1-shape.ps1" -Repo $repo
& "$labRoot\bin\run-git-cycles.ps1" -Repo $repo -Cycles 5 -BranchName 'feature-probe-f1shape' -OutputFile "$labRoot\work\repro-etw\results.txt" -Merge

# 3) Stop the session
xperf -d "$labRoot\work\repro-etw\etw-trace.etl"
```

If `xperf` is not installed, do **not** attempt to download or install
it during the experiment; report the gap to the user.

### 7.3 — Phase 3 deliverables

1. `work/repro-etw/pm-trace.csv` and `work/repro-etw/pm-trace.pml` (if ProcMon)
2. `work/repro-etw/etw-trace.etl` (if xperf)
3. `work/repro-etw/results.txt`
4. `work/repro-etw/sanitized-trace-summary.md` — one-page summary

The trace files can be very large. The sanitized summary is the only
artifact the user needs to attach; the raw trace stays local.

---

## 8. What the Mavis / MiniMax Code side does after the user returns

The user's role is to execute Phase 1 (and optionally Phase 2A / 2B /
2C / 3) inside a real WorkBuddy session and return the outcomes.
Mavis will then:

1. Ingest the native evidence (`work/repro-workbuddy-phase1/outcome.txt`,
   `work/repro-workbuddy-phase1/results.txt`, `phase2b/...`).
2. Compare baseline vs. allow-rule to determine
   `SANDBOX_POLICY_CAUSE_CONFIRMED`.
3. Update `report/ROOT_CAUSE_CLOSURE_REPORT.md` with the actual outcomes.
4. Update `report/BUG-REPORT-TENCENT.md` severity and "Issue B" sections.
5. Commit + push to GitHub.
6. Fresh-clone verification.
7. Final release gate output.
