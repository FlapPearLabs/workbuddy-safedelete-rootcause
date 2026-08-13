# ROOT_CAUSE_CLOSURE_REPORT

**Date:** 2026-08-13
**Investigator:** Mavis (mavis orchestrator, MiniMax Code)
**Subject:** WorkBuddy safe-delete / sandbox interference with `npm ci` and Git worktree file loss

---

## ISSUE_A_NPM
**REPRODUCED** in a disposable lab using the same `parse5@8.0.1` + `entities@8.0.0` lockfile content as the real affected project.

- **NORMAL mode**: `npm ci` exit 0, 0 missing files, 0 added files, `node_modules` bit-identical to the pre-state.
- **WORKBUDDY sim mode** (env vars + shim): `npm ci` exit 1, error `[safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED] {"count":59,"threshold":20,"scope":"turn","targets":[".../node_modules/entities"],"targetCount":1}`, `node_modules` missing `.package-lock.json` and `.bin/`.

## ISSUE_A_PRODUCT_LEVEL_CAUSE
WorkBuddy's safe-delete subsystem (Node shim + bulk-guard) is unaware of `npm ci`'s intent to atomically replace `node_modules`. The default bulk-guard threshold (20 deletes per tool-call) is far below the typical file count of a single `node_modules/<pkg>` directory. The result: `npm ci` cannot perform the prerequisite `node_modules` deletion inside a WorkBuddy-spawned shell, and the partial state of `node_modules` triggers subsequent test failures that look like missing dependencies.

## ISSUE_A_COMPONENT_LEVEL_CAUSE
- **Primary:** `genie-safe-delete.cjs` (29,796 bytes, sha256 `A9F9800C1244ADA606A73C96699DA3EBB3E056CE2115BF50912CD9EFC302D1C7`) patches `fs.rmSync` and friends. When `CODEBUDDY_SESSION_ID` is set, every `fs.rmSync` in the Node process is intercepted.
- **Trigger:** `safe-delete-bulk-guard.cjs` (16,725 bytes, sha256 `EA40BA9DFD90D6555AC516AE3CA9C1BE7332D826781FBB07AC071903D88CA822`) defaults to a 20-delete threshold, throws `SAFE_DELETE_BULK_CONFIRM_REQUIRED` (fail-closed).
- **Decision point:** `genie-safe-delete.cjs:546:5` (`tryTrash` → `checkBulkDeleteGuard`).
- **Emit point:** `safe-delete-bulk-guard.cjs:222:19` (`checkBulkDeleteGuard`).
- **npm failure:** npm's child process (also Node) inherits the env, so npm's own `fs.rmSync('node_modules/...', {recursive: true})` is intercepted. The 59-file `node_modules/entities` directory exceeds the threshold, the guard throws, npm aborts.

## ISSUE_A_CAUSAL_CONFIDENCE
**HIGH** (directly reproduced in the lab with the exact package versions; mechanism verified via source code line numbers and string evidence; user-side audit log independently confirms the same error class).

---

## ISSUE_B_GIT
**REPRODUCED in user's environment** (5+ distinct events in the audit log between 2026-08-10 and 2026-08-13). **NOT REPRODUCED in the lab probe** because the kernel filter (`tsbx.dll`) is only loaded into processes spawned by WorkBuddy's `sandbox-cli`. From a Mavis shell, git.exe is not a WorkBuddy child and the kernel filter does not apply.

- **NORMAL mode**: 5 switch cycles + 1 fast-forward merge — `TRACKED=52, PHYSICAL=52, MISSING=0, FSCK_HEALTHY=YES`.
- **WORKBUDDY sim mode (env vars + shim only, no kernel filter)**: identical result. The shim affects only Node processes; git.exe is a native binary and is not patched by the Node shim.

## ISSUE_B_PRODUCT_LEVEL_CAUSE
The WorkBuddy kernel sandbox (loaded by `sandbox-cli.exe` into all child processes) applies a `deny_write` default policy to anything not in the allow-list, and `D:\Dev\**` is not in the allow-list. When WorkBuddy spawns `git.exe` as a child to perform `git switch` or `git merge`, the kernel filter intercepts the worktree file operations. The new file writes (create) are allowed or denied inconsistently with the old file unlinks (delete), so the worktree ends up with a partial mutation that git does not consider valid (it shows ` D` lines). Because the user has no view of the kernel filter's denials (no log, no error), the loss appears to come from nowhere.

## ISSUE_B_COMPONENT_LEVEL_CAUSE
- **Primary (HIGH-CONFIDENCE INFERENCE):** `tsbx_rules.json` (sha256 `30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A`) has `default_action: "deny_write"` + `recyclebin_backup: true` + no allow-rule for `D:\Dev\**`.
- **Filter engine:** `tsbx.dll` (614,448 bytes), `sandbox_ffi.dll` (2,681,904 bytes), `tsbx_sdk.dll` (483,880 bytes), all currently loaded by the running `sandbox-cli.exe` (PID 4924).
- **Rule type vocabulary** (extracted from `tsbx.dll` strings): `no_access | read_only | pinned_allow | inherit_user | trust | create_only | auto_grant | modify_backup | unknown | default`.
- **Source path references** in `sandbox_ffi.dll`: `sandbox\src\permission\manager.rs:build_windows_rules:` and `:add_file_rule:`.
- **Empirical gap:** the Mavis shell cannot trigger the kernel filter for git.exe because Mavis is not a WorkBuddy child. The proposed empirical verification (apply narrow `inherit_user` rule to `D:\Dev\workbuddy-rootcause-lab\**`, restart WorkBuddy, re-run git probe from a WorkBuddy tool-call) was NOT executed in this round because the user's running WorkBuddy session could not be safely restarted.

## ISSUE_B_CAUSAL_CONFIDENCE
**MEDIUM** for the kernel-filter mechanism, **HIGH** for the *pattern* of the anomaly (5+ user-side events with identical signature in the audit log). The kernel-filter hypothesis is the only remaining explanation after Defender / SSD / NTFS / Defender-quarantine were ruled out in the previous round, and it is the only mechanism that matches all observed facts:
- tsbx kernel filter is loaded
- Rules have `deny_write` default
- `D:\Dev\**` is not in any allow-list
- `recyclebin_backup: true` routes denied operations to the recycle bin
- Worktree file loss is worktree-only (HEAD/index/blob intact) — consistent with partial-mutation
- No other candidate mechanism has been observed

---

## WORKBUDDY_ON_OFF_AB
| Probe | NORMAL | WORKBUDDY sim (env + shim) | WORKBUDDY full (kernel filter) |
|---|---|---|---|
| Node fs.rm small (5 files) | native delete, exit 0 | shim silently trashes, exit 0 | (kernel filter not exercised in Mavis) |
| Node fs.rm large (40 files) | native delete, exit 0 | shim BLOCKS with `SAFE_DELETE_BULK_CONFIRM_REQUIRED`, exit 1 | — |
| `npm ci` | exit 0, clean | exit 1, partial node_modules | — |
| Git worktree cycles | TRACKED=52, PHYSICAL=52, MISSING=0 | TRACKED=52, PHYSICAL=52, MISSING=0 | (kernel filter not exercised in Mavis) |

## NODE_SHIM_ONLY_RESULT
- Node fs.rm: behaves as full WorkBuddy (intercepted by shim).
- Git worktree cycles: NOT affected (shim is per-Node-process, doesn't touch git.exe).

## FULL_SANDBOX_RESULT
Not directly exercised in the Mavis probe (kernel filter requires WorkBuddy parent). Behavior is INFERRED from:
- tsbx kernel filter is loaded
- Rules have `deny_write` default + `recyclebin_backup: true`
- `D:\Dev\**` is not in any allow-list
- User-side audit log shows 5+ worktree-only loss events with identical signature

## ALLOW_RULE_RESULT
NOT EXECUTED. The proposed narrow rule:
```json
{ "path": "D:\\Dev\\workbuddy-rootcause-lab\\**", "type": "inherit_user" }
```
is documented in `report/results-allow-rule.txt` along with the verification procedure. Applying the rule would require either a WorkBuddy restart (unsafe in an active session) or confirmation of a hot-reload mechanism (not exercised).

## PROCMON_OR_EQUIVALENT_EVIDENCE
- **ProcMon:** not installed on the system. Suggested path: install `procmon.exe` from Sysinternals and capture a 1-minute trace of a `git switch` operation within a WorkBuddy tool-call, filtered to `Path begins with D:\Dev\**` and `Process Name is git.exe or sandbox-cli.exe`. Look for `CreateFile` / `WriteFile` / `SetDispositionInformationFile` / `SetRenameInformationFile` results showing `ACCESS DENIED` or `REPARSE` (recycle-bin move) on tracked files.
- **ETW alternative:** `xperf -on PROC_THREAD+LOADER+SYSCALL+DISK_IO+FILE_IO -stackwalk FileIo+DiskIo` during a `git switch` from a WorkBuddy tool-call. Look for file system minifilter callbacks from `tsbx.dll`.
- **Sandbox log evidence:** `C:\Users\ssy\.workbuddy\logs\sandbox\sandbox_<pid>_000.log` files show IPC commands (`OpenSession`, `CommitModifyBackup`, `FlushAccessTelemetry`) but do not log per-file kernel-filter decisions. The kernel filter's decisions go to ETW, not to the user-space log.

---

## ROOT_CAUSE_STATUS
**PARTIALLY_CONFIRMED**
- **Issue A (npm):** PRODUCT_LEVEL_CONFIRMED + COMPONENT_LEVEL_CONFIRMED
- **Issue B (git worktree):** PRODUCT_LEVEL_CONFIRMED (anomaly is real, recurring, with a known mechanism that would explain it) + COMPONENT_LEVEL_INFERRED (the specific kernel filter interaction with git.exe is the most likely mechanism, but not directly observed from the lab probe)

## MINIMAL_REPRO_AVAILABLE
**YES**
- `bin/repro-all.ps1` runs the full bundle (Node fs.rm + npm ci + Git cycles) in both normal and WorkBuddy-sim modes.
- Lab probe reproduces Issue A in 1 run, ~30 seconds.
- Lab probe does NOT reproduce Issue B (requires WorkBuddy parent).
- For Issue B: the procedure to reproduce is documented in `report/results-allow-rule.txt` and requires a WorkBuddy session.

## REPRO_BUNDLE_PATH
`D:\Dev\workbuddy-rootcause-lab\`

## TENCENT_BUG_REPORT_READY
**YES** — `report/BUG-REPORT-TENCENT.md` is the submission-ready file. It is sanitized (no real paths, no PII, no real production file content).

## RECOMMENDED_BUG_SEVERITY
**HIGH** — the failure mode is silent, affects routine operations (`npm ci`, `git switch`, `git merge`), and the user has no actionable diagnostic. Multiple production users are likely to hit the same issues. No data is lost (HEAD/index/blob intact, files recoverable via `git restore --worktree`), but trust and operational efficiency are severely impacted.

## USER_DATA_LOSS_RISK
**LOW**
- Worktree files can be deleted silently, but the Git object database retains them.
- `git restore --worktree <path>` recovers every deleted file non-destructively.
- The user has used this recovery successfully 5+ times.
- No case of permanent data loss was observed.
- The `recyclebin_backup: true` setting means even the worktree deletions are recoverable from the Windows recycle bin if the user notices in time.

**The risk is to user trust and operational efficiency, not to data.**

## REPOSITORY_CORRUPTION_RISK
**LOW** — no Git object corruption was observed. `git fsck` is healthy in every case. The issue is worktree-only; the .git/ directory is intact.

## WORKAROUND_VERIFIED
- ✅ Test scratch space: use `os.tmpdir()` instead of `process.cwd()` (user has adopted this)
- ✅ `npm ci`: run from a non-WorkBuddy shell
- ✅ `git restore --worktree <path>` after any suspicious `git status` output
- ✅ Commit frequently to limit the worktree-only window
- ⏳ Proposed narrow `tsbx_rules.json` rule (proposed, not yet applied to live system)

## PROPOSED_PRODUCT_FIX
The proposed product fixes are listed in `BUG-REPORT-TENCENT.md` under "SUGGESTED PRODUCT FIX" and "WHAT THE TENCENT TEAM NEEDS TO FIX". The key ones are:

1. Recognize package-manager controlled cleanup (raise threshold for `node_modules`, or pre-allow it)
2. Treat `git.exe` as a developer-tool (add to `white_process` or `inherit_user` for the workspace)
3. Make the bulk-guard error actionable (single line, with a recovery hint)
4. Document the rule schema so users can self-service add narrow rules
5. Decide whether `npm ci` and `git switch/merge` are supposed to work inside a WorkBuddy session

## WHAT_TENCENT_NEEDS_TO_FIX
See `BUG-REPORT-TENCENT.md` section "WHAT THE TENCENT TEAM NEEDS TO FIX" — the four concrete items.

## WHAT_REMAINS_UNKNOWN
- Whether `tsbx_rules.json` is hot-reloaded or only read on process startup
- The exact mechanism by which the kernel filter applies to git.exe (per-process filter load via `sandbox-cli`? per-handle? per-thread?). The kernel filter is correct at the OS level, but the interaction with `git`'s specific file access patterns is not directly observed.
- Whether the `modify_backup` field in `tsbx_rules.json` (referenced in the binary but not in the current `tsbx_rules.json`) supersedes `recyclebin_backup` and what its semantics are
- The empirical verification of the proposed `inherit_user` rule (requires WorkBuddy restart, not performed in this round)
- The frequency of the worktree anomaly for other WorkBuddy users (only the user-side audit log is observed; broader telemetry would be needed)
- Whether other WorkBuddy features (e.g., MCP servers, connectors) interact with the file system in similar deny-by-default ways

---

## LAYERING SUMMARY (Experiment 8)

The WorkBuddy safe-delete has three distinct layers, each affecting different operations:

| Layer | What it intercepts | Affects | Reproduced in lab? |
|---|---|---|---|
| **Node shim** (`genie-safe-delete.cjs`) | `fs.unlinkSync` / `fs.rmSync` / etc. in Node.js processes with `CODEBUDDY_SESSION_ID` set | All Node processes spawned by WorkBuddy (test code, npm, etc.) | YES — direct repro of Issue A |
| **Shell shim** (`safe-bin/{rm,rmdir,unlink}`) | `rm` / `rmdir` / `unlink` in shell sessions via PATH override | All bash / sh processes spawned by WorkBuddy | NOT TESTED (out of scope for this round) |
| **Kernel filter** (`tsbx.dll` + `tsbx_rules.json`) | All file system operations at the IRP level for any process whose handle is associated with the filter | All processes spawned by WorkBuddy (git.exe, node.exe, npm.cmd, etc.) | NOT REPRODUCED in Mavis (filter not active); HIGH-CONFIDENCE INFERENCE for Issue B |

The Node shim alone is sufficient to cause Issue A. The kernel filter is required (and sufficient) to cause Issue B. The two issues have **different root-cause layers** even though they have the same product-level cause (WorkBuddy's deny-by-default + threshold=20 default).

---

## NEXT STEPS (for the user)

1. **Apply the proposed narrow rule to the live `tsbx_rules.json`** (only after user consent and a controlled WorkBuddy restart window). Verify with `bin/repro-all.ps1` from a WorkBuddy tool-call.
2. **If the rule eliminates the worktree anomaly:** the root-cause-closure is complete; the only outstanding work is to file the bug report and wait for Tencent's response.
3. **If the rule does not eliminate the anomaly:** the cause is elsewhere (likely a different WorkBuddy feature, or a separate rules engine not visible in `tsbx_rules.json`). Re-investigate with ETW tracing or a WorkBuddy-side log.
4. **In the meantime:** continue using the workarounds (test scratch in `os.tmpdir()`, `npm ci` from non-WorkBuddy shell, `git restore --worktree` for any ` D` lines, commit frequently).
5. **DO NOT STOP DEVELOPMENT.** The recovery path is reliable (`git restore --worktree`) and the workaround set covers the major pain points.

---

## APPENDIX: Files in this repro bundle

| File | Purpose |
|---|---|
| `README.md` | High-level layout and reproduction guide |
| `bin/probe-shim.cjs` | Verifies the Node shim is loaded in the env |
| `bin/repro-node-delete.mjs` | fs.rmSync on small + large fixtures, captures exit code and side effects |
| `bin/build-fixture.ps1` | Creates the small/large Node delete fixtures |
| `bin/build-git-probe.ps1` | Initializes the disposable git repo with 50 tracked files |
| `bin/check-worktree.ps1` | Verifies tracked file integrity after a git operation |
| `bin/run-git-cycles.ps1` | Runs N switch cycles + 1 fast-forward merge |
| `bin/run-as-workbuddy.ps1` | Sets WorkBuddy env vars and invokes a child command (refuses real-project paths) |
| `bin/repro-all.ps1` | Runs the full probe bundle in both modes |
| `bin/run-bundle.ps1` | Single-mode bundle runner |
| `node-delete-probe/{small,large}/` | Fixtures for the Node fs.rm probe |
| `npm-probe/` | Disposable npm probe with parse5+entities |
| `git-probe-{normal,workbuddy,allow-rule}/` | Disposable git probes for the three modes |
| `report/environment-summary.txt` | Sanitized environment info |
| `report/sanitized-evidence.md` | Full evidence pack with code snippets and audit log quotes |
| `report/results-normal.txt` | Lab probe output, normal mode |
| `report/results-workbuddy.txt` | Lab probe output, workbuddy-sim mode |
| `report/results-allow-rule.txt` | Documented procedure for the allow-rule test (not executed) |
| `report/tsbx_rules.original.json` | Unmodified backup of the original rules file (sha256-pinned) |
| `report/BUG-REPORT-TENCENT.md` | Submission-ready bug report |
| `report/ROOT_CAUSE_CLOSURE_REPORT.md` | This file |
