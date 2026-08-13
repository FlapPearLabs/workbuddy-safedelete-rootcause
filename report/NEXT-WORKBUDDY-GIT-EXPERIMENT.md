# NEXT-WORKBUDDY-GIT-EXPERIMENT.md

> **Purpose.** The `bin/repro-all.ps1` orchestrator conclusively proves that the
> Node shim (the `genie-safe-delete.cjs` layer) is **not** the cause of the
> Git worktree file loss observed in the user's audit log. The kernel filter
> (`tsbx.dll`) is the only remaining mechanism consistent with the user-side
> pattern, but the kernel filter is only loaded into processes spawned by
> `sandbox-cli.exe` inside a real WorkBuddy session. This document is a
> **complete, copy-pasteable procedure** for running the Git worktree A/B
> inside a real WorkBuddy tool-call, so that the remaining inference can be
> either confirmed or falsified.

---

## 0. Hard rules — read this first

The following rules apply to **every step** of this experiment. Violating any
of them invalidates the evidence.

1. **Do not touch any path outside the disposable lab.** The lab root is the
   directory the user cloned this repo into; the lab scripts auto-resolve it.
   The lab scripts refuse (script-level blacklist) any command whose argument
   contains the real production repo path.
2. **Do not run `git reset --hard`, `git clean -fd`, or `git checkout HEAD -- <path>`
   inside the lab repos.** These are not needed; the lab probe uses non-destructive
   `git restore --worktree` to clean up between cycles.
3. **Do not modify `tsbx_rules.json` on the live system in Phase 1.** Phase 1 is
   the unmodified WorkBuddy baseline. Phase 2 only adds a narrow rule.
4. **Do not restart WorkBuddy** unless the procedure explicitly says so. If a
   restart is required for Phase 2, the procedure will pause and ask the user
   to perform the restart; do not auto-kill the WorkBuddy process.
5. **Do not force-push, do not rewrite Git history.** The lab repo is
   disposable; commits made during this experiment are local-only.
6. **Do not auto-submit any bug report to Tencent.** The user controls filing.
7. **Save every evidence artifact to the lab output dir** (`work/repro-workbuddy-phase1/`,
   `work/repro-workbuddy-phase2-baseline/`, `work/repro-workbuddy-phase2-allow-rule/`).
   Each phase produces a `results.txt` that the user can paste back to the
   investigation.

---

## 1. Phase 1 — REAL WORKBUDDY BASELINE (no rule changes)

**Goal:** Determine whether the worktree file loss reproduces inside a real
WorkBuddy tool-call session, with `tsbx_rules.json` unchanged.

### 1.1 — Pre-flight

Open a WorkBuddy tool-call session that can run PowerShell. Inside that
session:

```powershell
# 1) Locate the lab repo (replace with the actual clone path).
$labRoot = 'D:\Dev\workbuddy-rootcause-lab'   # <-- replace with the user's clone path
Set-Location $labRoot

# 2) Sanity check: WorkBuddy is present and the lab scripts can find it.
& $labRoot\bin\repro-all.ps1 -OutputDir "$labRoot\work\repro-preflight" 2>&1 | Select-String -Pattern 'REPRO_ALL_WORKBUDDY_SHIM_AVAILABLE'
# Expected: REPRO_ALL_WORKBUDDY_SHIM_AVAILABLE=True
# If False, abort: the kernel filter cannot be exercised without a real install.
```

If preflight reports `SHIM_AVAILABLE=True`, proceed. Otherwise stop and
report to the user.

### 1.2 — Run the Git probe from inside a WorkBuddy tool-call

The lab probe (`bin/repro-all.ps1`) deliberately does **not** run the Git
cycles under the kernel filter, because the Mavis orchestrator that drives
the lab is not a WorkBuddy child. Inside a real WorkBuddy tool-call, the
kernel filter IS active for every process WorkBuddy spawns. The Git cycles
must therefore be run by a script that WorkBuddy itself invokes.

```powershell
$labRoot = 'D:\Dev\workbuddy-rootcause-lab'   # <-- replace
$phase1Dir = Join-Path $labRoot 'work\repro-workbuddy-phase1'
New-Item -ItemType Directory -Force -Path $phase1Dir | Out-Null

# 1) Clean up any prior run state
$repo = Join-Path $labRoot 'fixtures\git-probe-workbuddy-baseline'
if (Test-Path $repo) { mavis-trash $repo }

# 2) Build a fresh Git probe with real branch delta
& "$labRoot\bin\build-git-probe.ps1" -Repo $repo 2>&1 | Tee-Object -FilePath "$phase1Dir\build.txt"
# Expected: BRANCH_DELTA_VALID=YES
# If BRANCH_DELTA_VALID=NO, abort and report.

# 3) Run 5 switch cycles + 1 ff merge. Each step records WORKTREE_CHECK_*
& "$labRoot\bin\run-git-cycles.ps1" -Repo $repo -Cycles 5 -OutputFile "$phase1Dir\results.txt" -Merge $true 2>&1 | Tee-Object -FilePath "$phase1Dir\cycles.txt"

# 4) Parse the per-step verdicts
$lines = Get-Content "$phase1Dir\results.txt"
$verdicts = $lines | Select-String -Pattern '^WORKTREE_CHECK_VERDICT='
$verdicts | ForEach-Object { Write-Output $_ }
$worktreeLoss = $verdicts | Select-String -Pattern 'WORKTREE_ONLY_LOSS|INDEX_ONLY_LOSS|HEAD_ONLY_LOSS'
```

**Record the outcome** to `$phase1Dir\outcome.txt`:

```text
WORKTREE_LOSS_REPRODUCED: <YES | NO_IN_10_CYCLES | UNRESOLVED>
WORKTREE_LOSS_REPRODUCED_AT_STEP: <step label>   # only if YES
WORKTREE_CHECK_VERDICT_FIRST_NON_CLEAN: <step label or 'NONE'>
MISSING_TRACKED_PATHS: <count>
FIRST_MISSING_PATHS: <list of up to 10 paths, or 'NONE'>
TIMESTAMP_UTC: <ISO timestamp>
HEAD_BEFORE_LOSS: <sha>
HEAD_AFTER_LOSS: <sha>
INDEX_TREE_BEFORE_LOSS: <sha>
INDEX_TREE_AFTER_LOSS: <sha>
```

**If `WORKTREE_LOSS_REPRODUCED: YES`:**

- Do **not** immediately `git restore`. First, copy `$repo\.git` to
  `$phase1Dir\repo-snapshot.git\` so the post-loss state is preserved
  (`Copy-Item -Recurse "$repo\.git" "$phase1Dir\repo-snapshot.git"`).
- Save the per-step `results.txt` to `$phase1Dir\results.txt` (already
  there).
- Save the `git status`, `git fsck --no-reflogs`, and
  `git ls-files --error-unmatch <each missing path>` output to
  `$phase1Dir\post-loss-snapshots.txt`.
- **Then** and only then, run `git -C $repo restore --worktree -- .` to
  recover the disposable probe repo for the next phase.
- **Stop and report to the user.** Do not proceed to Phase 2 without the
  user's confirmation, because Phase 2 requires editing `tsbx_rules.json`.

**If `WORKTREE_LOSS_REPRODUCED: NO_IN_10_CYCLES`:**

- Save the same outcome record with `WORKTREE_LOSS_REPRODUCED: NO_IN_10_CYCLES`.
- **Do not loop indefinitely.** 5 cycles + 1 merge = 11 steps, 22
  `WORKTREE_CHECK_VERDICT` lines. The probe is a strong negative if all 22
  are `CLEAN`.
- **Stop and report to the user.** The kernel filter is either not active
  for this `git.exe` invocation, or the worktree file loss requires a
  different workload (more files, different file types, a specific branch
  shape) than the lab probe. The investigation should be redirected.

**If `WORKTREE_LOSS_REPRODUCED: UNRESOLVED`** (e.g. some steps fail with
errors unrelated to the kernel filter):

- Save the raw error output to `$phase1Dir\errors.txt`.
- Report to the user with the full error.

### 1.3 — Phase 1 deliverables

After Phase 1, the user should be able to attach the following to the
investigation:

1. `work/repro-workbuddy-phase1/build.txt` — Git probe build output
2. `work/repro-workbuddy-phase1/cycles.txt` — full run output
3. `work/repro-workbuddy-phase1/results.txt` — structured per-step records
4. `work/repro-workbuddy-phase1/outcome.txt` — the structured outcome above
5. (only if `WORKTREE_LOSS_REPRODUCED: YES`) `work/repro-workbuddy-phase1/repo-snapshot.git/`
   and `work/repro-workbuddy-phase1/post-loss-snapshots.txt`

---

## 2. Phase 2 — WorkBuddy-native rule A/B

**Goal:** With `tsbx_rules.json` modified to add a narrow `inherit_user` rule
covering only the lab root, repeat the exact same Git workload and compare.

This phase **must not** be entered if Phase 1 reproduced the loss and the
post-loss evidence has not been saved, because the rule change will alter
WorkBuddy's behavior across the system. The user must explicitly approve.

### 2.1 — Pre-flight: confirm `tsbx_rules.json` is loadable and the reload behavior

Inside a WorkBuddy tool-call session, before editing anything:

```powershell
# 1) Confirm the live tsbx_rules.json path
$rulesPath = 'D:\WORKBUDDY\resources\app.asar.unpacked\cli\vendor\sandbox\5.3.3\tsbx_rules.json'
if (-not (Test-Path $rulesPath)) { throw "tsbx_rules.json not found at $rulesPath" }

# 2) Capture the pre-edit hash
$preHash = (Get-FileHash $rulesPath -Algorithm SHA256).Hash
Write-Output "TSBX_RULES_PRE_EDIT_SHA256=$preHash"
# Expected (from the lab investigation): 30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A
# If the hash differs, the rule file has been updated since this investigation.
# Report the new hash to the user but proceed with caution.

# 3) Document the proposed rule (read-only, no write yet)
$labRoot = 'D:\Dev\workbuddy-rootcause-lab'
$proposedRule = @"
{ "path": "$labRoot\\**", "type": "inherit_user" }
"@
Write-Output "PROPOSED_RULE=$proposedRule"
```

**Decision point — WorkBuddy restart:**

This investigation was **unable to confirm** whether `tsbx_rules.json` is
hot-reloaded or only read on process startup. The procedure therefore
**prompts the user** to restart WorkBuddy at the start of Phase 2 rather
than guessing:

```
WORKBUDDY_RESTART_REQUIRED:
The kernel filter reads tsbx_rules.json at <unknown time>. To make the
new rule effective, please:
  1) save all your open WorkBuddy work
  2) quit WorkBuddy
  3) reopen WorkBuddy
  4) re-invoke this same tool-call

After WorkBuddy is restarted, the procedure continues from 2.2 below.
```

If the user does not want to restart, **stop and report**. Do not proceed.

### 2.2 — Apply the narrow rule (baseline re-run)

After the user confirms the restart:

```powershell
$rulesPath = 'D:\WORKBUDDY\resources\app.asar.unpacked\cli\vendor\sandbox\5.3.3\tsbx_rules.json'
$labRoot = 'D:\Dev\workbuddy-rootcause-lab'   # <-- replace

# 1) Backup the live rules to a side-by-side file with a timestamp
$backupPath = "$rulesPath.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item $rulesPath $backupPath
$backupHash = (Get-FileHash $backupPath -Algorithm SHA256).Hash
Write-Output "TSBX_RULES_BACKUP_PATH=$backupPath"
Write-Output "TSBX_RULES_BACKUP_SHA256=$backupHash"

# 2) Use node to edit the JSON atomically (avoid PowerShell string concat)
$proposedRuleJson = @{ path = "$labRoot\**"; type = "inherit_user" }
$rules = Get-Content $rulesPath -Raw | ConvertFrom-Json
$rules.file_rules_user += $proposedRuleJson
$rules | ConvertTo-Json -Depth 32 | Set-Content $rulesPath -Encoding UTF8

# 3) Capture the post-edit hash
$postHash = (Get-FileHash $rulesPath -Algorithm SHA256).Hash
Write-Output "TSBX_RULES_POST_EDIT_SHA256=$postHash"

# 4) Sanity check: JSON is still valid
try {
    $verify = Get-Content $rulesPath -Raw | ConvertFrom-Json
    if ($verify.file_rules_user[-1].type -ne 'inherit_user') { throw "rule not at end" }
    Write-Output "TSBX_RULES_POST_EDIT_VALID=yes"
} catch {
    # Roll back immediately
    Copy-Item $backupPath $rulesPath -Force
    throw "tsbx_rules.json became invalid after edit; rolled back from $backupPath"
}
```

### 2.3 — Run the same Git workload from inside a WorkBuddy tool-call

This is **byte-identical** to Phase 1.2 except the output dir is different:

```powershell
$labRoot = 'D:\Dev\workbuddy-rootcause-lab'   # <-- replace
$phase2Dir = Join-Path $labRoot 'work\repro-workbuddy-phase2-allow-rule'
New-Item -ItemType Directory -Force -Path $phase2Dir | Out-Null

$repo = Join-Path $labRoot 'fixtures\git-probe-workbuddy-allow-rule'
if (Test-Path $repo) { mavis-trash $repo }

& "$labRoot\bin\build-git-probe.ps1" -Repo $repo 2>&1 | Tee-Object -FilePath "$phase2Dir\build.txt"
& "$labRoot\bin\run-git-cycles.ps1" -Repo $repo -Cycles 5 -OutputFile "$phase2Dir\results.txt" -Merge $true 2>&1 | Tee-Object -FilePath "$phase2Dir\cycles.txt"

# Parse the per-step verdicts
$lines = Get-Content "$phase2Dir\results.txt"
$verdicts = $lines | Select-String -Pattern '^WORKTREE_CHECK_VERDICT='
$verdicts | ForEach-Object { Write-Output $_ }
$worktreeLoss = $verdicts | Select-String -Pattern 'WORKTREE_ONLY_LOSS|INDEX_ONLY_LOSS|HEAD_ONLY_LOSS'
```

**Record the outcome** to `$phase2Dir\outcome.txt`:

```text
WORKTREE_LOSS_REPRODUCED: <YES | NO_IN_10_CYCLES | UNRESOLVED>
WORKTREE_LOSS_REPRODUCED_AT_STEP: <step label>   # only if YES
WORKTREE_CHECK_VERDICT_FIRST_NON_CLEAN: <step label or 'NONE'>
MISSING_TRACKED_PATHS: <count>
FIRST_MISSING_PATHS: <list of up to 10 paths, or 'NONE'>
TIMESTAMP_UTC: <ISO timestamp>
HEAD_BEFORE_LOSS: <sha>
HEAD_AFTER_LOSS: <sha>
INDEX_TREE_BEFORE_LOSS: <sha>
INDEX_TREE_AFTER_LOSS: <sha>
```

### 2.4 — Phase 2 deliverables

After Phase 2:

1. `work/repro-workbuddy-phase2-allow-rule/build.txt`
2. `work/repro-workbuddy-phase2-allow-rule/cycles.txt`
3. `work/repro-workbuddy-phase2-allow-rule/results.txt`
4. `work/repro-workbuddy-phase2-allow-rule/outcome.txt`
5. `work/repro-workbuddy-phase2-allow-rule/tsbx_rules.backup.txt` (the pre-edit
   backup file, for restoring)

### 2.5 — Restore the live `tsbx_rules.json`

**Always restore** at the end of Phase 2, regardless of outcome:

```powershell
$rulesPath = 'D:\WORKBUDDY\resources\app.asar.unpacked\cli\vendor\sandbox\5.3.3\tsbx_rules.json'
$backupPath = Get-ChildItem "$rulesPath.bak.*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Copy-Item $backupPath.FullName $rulesPath -Force
$restoredHash = (Get-FileHash $rulesPath -Algorithm SHA256).Hash
Write-Output "TSBX_RULES_RESTORED_FROM=$($backupPath.FullName)"
Write-Output "TSBX_RULES_RESTORED_SHA256=$restoredHash"
# Expected: 30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A
```

If the restored hash does not match the pre-edit hash, **stop and report**;
do not continue without manual intervention.

---

## 3. Phase 3 — Optional ETW / ProcMon capture

If the user already has ProcMon installed (`procmon.exe` from Sysinternals),
or can run `xperf` (Windows Performance Toolkit), Phase 3 produces direct
evidence of the kernel-filter denials.

### 3.1 — ProcMon (preferred if available)

Inside a WorkBuddy tool-call session, in one PowerShell process:

```powershell
# 1) Start a 60-second ProcMon trace
& 'C:\Tools\Procmon\procmon.exe' /AcceptEula /Quiet /BackingFile "$labRoot\work\repro-etw\pm-trace.pml"

# 2) Immediately run the Git probe (Phase 1.2 workflow, again)
#    -- this is the workload to trace
& "$labRoot\bin\build-git-probe.ps1" -Repo $repo
& "$labRoot\bin\run-git-cycles.ps1" -Repo $repo -Cycles 5 -OutputFile "$labRoot\work\repro-etw\results.txt" -Merge $true

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
`$labRoot`, the kernel filter hypothesis is directly observed.

### 3.2 — xperf / ETW (alternative)

```powershell
# 1) Start the ETW session
xperf -on PROC_THREAD+LOADER+SYSCALL+DISK_IO+FILE_IO+FILTC -stackwalk FileIo+DiskIo -f "$labRoot\work\repro-etw\etw-trace.etl"

# 2) Run the Git probe
& "$labRoot\bin\build-git-probe.ps1" -Repo $repo
& "$labRoot\bin\run-git-cycles.ps1" -Repo $repo -Cycles 5 -OutputFile "$labRoot\work\repro-etw\results.txt" -Merge $true

# 3) Stop the session
xperf -d "$labRoot\work\repro-etw\etw-trace.etl"
```

Inspect the resulting `.etl` with `xperf` or `PerfView /DataFile=etw-trace.etl`.
Look for `Microsoft-Windows-Kernel-File` events with `STATUS_ACCESS_DENIED`
or `FILE_IS_DELETE_PENDING` from `tsbx.dll` in the stack.

If `xperf` is not installed, do **not** attempt to download / install it
during the experiment; report the gap to the user.

### 3.3 — Phase 3 deliverables

1. `work/repro-etw/pm-trace.csv` and `work/repro-etw/pm-trace.pml` (if ProcMon)
2. `work/repro-etw/etw-trace.etl` (if xperf)
3. `work/repro-etw/results.txt` (the Git probe output for the same workload)
4. `work/repro-etw/sanitized-trace-summary.md` — a one-page summary
   listing the matching events (path, process, operation, result, timestamp)

The trace files themselves can be very large. The sanitized summary is
the only artifact the user needs to attach to the investigation; the raw
trace can be retained locally.

---

## 4. What the user does after all three phases

1. Attach the `outcome.txt` from Phase 1 and Phase 2 to the investigation.
2. If the user-side audit log + Phase 1 outcome is `WORKTREE_LOSS_REPRODUCED: YES`
   and Phase 2 outcome is `WORKTREE_LOSS_REPRODUCED: NO`:
   - `SANDBOX_POLICY_CAUSE_CONFIRMED`.
3. If Phase 3 also captures `ACCESS DENIED` / `REPARSE` from the kernel filter:
   - `COMPONENT_LEVEL_CAUSE_CONFIRMED`.
4. Update `report/ROOT_CAUSE_CLOSURE_REPORT.md` with the actual outcomes.
5. Update `report/BUG-REPORT-TENCENT.md` severity classification based on
   the actual outcomes (the current report is conservative; it may be
   upgraded to `HIGH` if the Git worktree anomaly is fully confirmed).
6. Push the updated repo to GitHub. Re-run the fresh-clone verification.
7. File the bug report with Tencent.

If Phase 1 produces `WORKTREE_LOSS_REPRODUCED: NO_IN_10_CYCLES`, the
investigation **stays at HIGH_CONFIDENCE INFERENCE** for Issue B's
component-level cause, and the bug report's "Severity" and "Issue B"
sections should be downgraded accordingly.

---

## 5. What the Mavis / MiniMax Code side does after the user returns

The user's role is to execute this procedure inside a real WorkBuddy
session and return the Phase 1, Phase 2 (and optionally Phase 3)
outcomes. Mavis will then:

1. Ingest the native evidence (`work/repro-workbuddy-phase1/results.txt`,
   `work/repro-workbuddy-phase2-allow-rule/results.txt`, optional ETW summary).
2. Compare baseline vs. allow-rule to determine the
   `SANDBOX_POLICY_CAUSE_CONFIRMED` threshold.
3. Update `report/ROOT_CAUSE_CLOSURE_REPORT.md` with the actual outcomes.
4. Update `report/BUG-REPORT-TENCENT.md` severity and "Issue B" sections
   to match the evidence.
5. Commit + push to GitHub.
6. Fresh-clone verification.
7. Final release gate output.

No new code is needed; the lab scripts already produce the structured
per-step records. The only edits after Phase 1/2 are documentation and
the bug report.
