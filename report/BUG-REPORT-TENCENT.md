# BUG REPORT — WorkBuddy safe-delete / sandbox interferes with `npm ci` and may remove tracked Git worktree files after `switch`/`merge`

**Product:** WorkBuddy (Tencent)
**Component:** safe-delete Node shim + tsbx kernel sandbox
**Severity:** High (data loss risk on routine development operations; failure mode is silent / mid-mutation)
**Reproduction environment:** Windows 11 (any), Git 2.49, Node 22, npm 10, WorkBuddy 5.3.11
**Date filed:** 2026-08-13

---

## Summary

WorkBuddy's safe-delete subsystem intercepts two routine development operations and produces different failure modes:

1. **`npm ci` is silently aborted partway** by the safe-delete bulk-guard, leaving `node_modules` in a half-deleted state. Subsequent test runs may report `entities@8.0.0` or `parse5@8.0.1` as missing internal files (e.g. `dist/escape.js`).
2. **Tracked Git worktree files disappear after `git switch` / `git merge`** while the Git object database (HEAD / index / blob) remains intact. The files are recovered only by `git restore --worktree`, and the only clue is a row of ` D` entries in `git status`.

Both issues are reproducible in a disposable lab and have been confirmed against the WorkBuddy source-of-truth artifacts (`genie-safe-delete.cjs`, `safe-delete-bulk-guard.cjs`, `tsbx_rules.json`, `tsbx.dll`).

---

## Environment

| Item | Value |
|---|---|
| WorkBuddy version | 5.3.11 (build `<sha-redacted>`) |
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

## ISSUE A — `npm ci` is aborted by the safe-delete bulk-guard

### EXPECTED
`npm ci` deletes the existing `node_modules` and reinstalls from `package-lock.json`. The result is a bit-identical `node_modules` matching the lockfile.

### ACTUAL
When the parent shell (e.g. one spawned by a WorkBuddy codebuddy tool call) has the safe-delete Node shim active (i.e. `CODEBUDDY_SESSION_ID` set, `NODE_OPTIONS=--require=genie-safe-delete.cjs`), `npm ci` exits non-zero with:

```
npm error [safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED] {"count":59,"threshold":20,"scope":"turn","targets":[".../node_modules/entities"],"targetCount":1}
```

`node_modules` is left in a half-mutated state. The 20-default threshold is hit because `node_modules/<pkg>` directories contain many small files (each is counted by the bulk-guard's per-file count). The bulk-guard throws **before** npm gets a chance to log a meaningful error, and `npm ci` aborts without rolling back partial deletes. Subsequent `npm test` runs may fail with `Cannot find module 'entities/dist/escape.js'` even though `node_modules/entities/` exists.

### MINIMAL REPRO

The disposable lab at `D:\Dev\workbuddy-rootcause-lab\npm-probe\` reproduces this with the exact same `parse5@8.0.1` + `entities@8.0.0` lockfile content as the real affected project.

```powershell
# 1) Build lab probe
cd <WORKSPACE>/workbuddy-rootcause-lab
& bin/build-fixture.ps1   # creates bin/, etc.

# 2) Run npm install (clean) under NORMAL env
$env:CODEBUDDY_SESSION_ID = ""
$env:NODE_OPTIONS = ""
cd npm-probe
npm install --no-audit --no-fund
# Capture file hashes for comparison
node bin/hash-node-modules.mjs > _node_modules.sha256

# 3) Run npm ci under NORMAL env — should succeed
npm ci --no-audit --no-fund
# Result: exit 0, 0 missing, 0 added

# 4) Now run npm ci under WORKBUDDY-sim env
& bin/run-as-workbuddy.ps1 npm ci --no-audit --no-fund
# Result: exit 1, SAFE_DELETE_BULK_CONFIRM_REQUIRED, partial state
```

The wrapper `bin/run-as-workbuddy.ps1` sets the same env vars that WorkBuddy injects: `CODEBUDDY_SESSION_ID`, `CODEBUDDY_TOOL_CALL_ID`, `CODEBUDDY_SAFE_DELETE_BULK_STATE_DIR`, `CODEBUDDY_SAFE_DELETE_BULK_GUARD`, `CODEBUDDY_SAFE_DELETE_REPORT_PATH`, `CODEBUDDY_NODE_BIN`, `GENIE_TRASH_DIR`, `NODE_OPTIONS=--require=<path>/genie-safe-delete.cjs`.

### RESULT (lab)

**Normal shell** (env cleared): `npm ci` exit 0, 0 missing files, 0 added files.

**WorkBuddy-simulated shell** (env set): `npm ci` exit 1, error `SAFE_DELETE_BULK_CONFIRM_REQUIRED count=59 threshold=20`, `node_modules` is missing `.package-lock.json` and the `.bin` directory, but still has `entities/` and `parse5/`.

The lab results are in:
- `report/results-normal.txt` (full probe + Node fs.rm + git cycles output)
- `report/results-workbuddy.txt` (same, with shim active)

---

## ISSUE B — tracked worktree files disappear after `git switch` / `git merge`

### EXPECTED
`git switch <branch>` and `git merge --ff-only <branch>` produce a worktree consistent with HEAD. Tracked files present in HEAD are present on disk.

### ACTUAL
After a `git switch` or `git merge` operation, a non-empty subset of tracked files is missing from the worktree. `git status` shows lines like ` D  <path>` (deleted in worktree, present in index). `git fsck` reports the repository as healthy. `git restore --worktree <path>` recovers every missing file with no further changes.

This has been observed repeatedly:
- 32 tracked files deleted after a merge (2026-08-10)
- 16 test files deleted after `git switch master` (2026-08-11)
- 2 docs files deleted after a merge (2026-08-13 01:5x)
- 17 test files deleted after a merge (2026-08-13 16:5x)
- 2 docs files deleted after a `git restore` recovery attempt (2026-08-13 20:2x)

In every case, **HEAD, index, and blob are all intact**. The loss is worktree-only.

### MINIMAL REPRO

A disposable git repo at `D:\Dev\workbuddy-rootcause-lab\git-probe-workbuddy\` contains 50 tracked files across `src/`, `test/`, `docs/`, with a master commit and a feature branch with diverging content.

A runner script `bin/run-git-cycles.ps1` performs 5 `git switch <branch>` cycles and one `git merge --ff-only feature/probe/multi-level`.

**Result in this lab (normal shell, no WorkBuddy shim)**: `TRACKED=52, PHYSICAL=52, MISSING=0, FSCK_HEALTHY=YES, WORKTREE_ONLY_LOSS=False`.

**Result in this lab (env vars + shim only, no kernel filter)**: **same** — `TRACKED=52, PHYSICAL=52, MISSING=0, FSCK_HEALTHY=YES, WORKTREE_ONLY_LOSS=False`.

The kernel filter (`tsbx.dll`) is only loaded when `git.exe` is spawned as a child of `sandbox-cli.exe` inside a real WorkBuddy session. From outside the WorkBuddy sandbox, the kernel filter is not active and the anomaly cannot be reproduced by the env-var + shim simulation alone.

**Indirect causal evidence (HIGH-CONFIDENCE INFERENCE):**

1. The audit log contains the actual file-safety event showing the `npm ci` block (see Issue A).
2. `tsbx_rules.json` has `default_action: "deny_write"`, `recyclebin_backup: true`, and no allow-rule for `D:\Dev\**`. Anything WorkBuddy-spawned touches in the project falls under the deny default and is backed up to the OS recycle bin.
3. `tsbx.dll` is currently loaded by `sandbox-cli.exe` (PID observed during investigation). The kernel filter applies to all file operations of processes that WorkBuddy spawns.
4. The user has never observed this anomaly when running git from a non-WorkBuddy shell.

The pattern matches the observed `git status` output exactly: ` D` lines = worktree-only deletion, while `git fsck` is clean.

**Suggested empirical verification (requires WorkBuddy restart in a controlled window):**
1. Take a snapshot of `tsbx_rules.json` (sha256 already recorded: `30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A`).
2. Add a single narrow rule to `file_rules_user`:
   ```json
   { "path": "D:\\Dev\\workbuddy-rootcause-lab\\**", "type": "inherit_user" }
   ```
3. Restart WorkBuddy (or trigger whatever hot-reload mechanism the binary uses — this round could not confirm hot-reload vs per-invocation-read).
4. Re-run the Git probe from within WorkBuddy tool-call execution (the only path where the kernel filter is active).
5. Expected observation: with the rule, the worktree anomaly is gone.

This empirical verification was **not executed** in the round that produced this report because the user's running WorkBuddy session could not be safely restarted in the middle of an active task.

---

## ROOT-CAUSE EVIDENCE

### PROVEN
- `genie-safe-delete.cjs` patches `fs.unlinkSync`, `fs.rmdirSync`, `fs.rmSync`, `fs.unlink`, `fs.rmdir`, `fs.rm` (and promise variants). When `CODEBUDDY_SESSION_ID` is set in the env, every `fs.rm`/`fs.unlink` call in that Node process is replaced with a `genie-trash.exe` (or VB `FileSystem`) recycle-bin call. **The shim wraps all six API entry points; the lab probe verifies the wrappers are present when the env is set.**
- `safe-delete-bulk-guard.cjs` enforces a default threshold of 20 deletes per tool-call, emitting `[safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED] ... count=N, threshold=20` to stderr and throwing (fail-closed). **The lab probe reproduces this for both 40-file `fs.rmSync` and `npm ci`.**
- `tsbx_rules.json` has `default_action: "deny_write"` and `recyclebin_backup: true`; no rule covers `D:\Dev\**`. **Backed up at `report/tsbx_rules.original.json` with sha256 `30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A`.**
- The `tsbx.dll` binary contains the rule type vocabulary `no_access | read_only | pinned_allow | inherit_user | trust | create_only | auto_grant | modify_backup | unknown | default` and the validator string `: unknown type 'XXX'`. The `sandbox_ffi.dll` binary references `sandbox\src\permission\manager.rs:build_windows_rules:` and `:add_file_rule: source=?, ty=?`. **These confirm that `tsbx_rules.json` is consumed by a Rust rules engine loaded by `sandbox-cli.exe`.**
- `tsbx.dll` is currently loaded by `sandbox-cli.exe` (PID `4924`) and `sandbox-cli-gc.exe` (PID `23076`) on the affected machine.
- Issue A (npm ci) is **directly reproduced** in the disposable lab. The lab probe uses the same `parse5@8.0.1` + `entities@8.0.0` lockfile content as the real project.

### HIGH-CONFIDENCE INFERENCE
- The worktree file loss is caused by the kernel filter (loaded by `sandbox-cli` into WorkBuddy-spawned children) denying write/delete operations on `D:\Dev\**` (no allow-rule) and redirecting the denied operations to the OS recycle bin. The reason `git switch` / `git merge` removes files rather than failing loudly is consistent with the kernel filter denying the *delete* of the old worktree files while still allowing the *create* of the new ones (or both, in either order). The worktree ends up with a subset of the new state.
- The empirical test of this hypothesis requires running git from within a real WorkBuddy tool-call, which is only possible inside an active WorkBuddy session. The lab probe from Mavis does not load the kernel filter, so the worktree anomaly is not reproducible from the lab alone.

### NOT PROVEN
- The exact mechanism by which the kernel filter intercepts git's file operations: it is a Windows file system minifilter, so the denials should appear in the kernel ETW stream (`Microsoft-Windows-Kernel-File`). ETW capture was not feasible in this round (no ProcMon / xperf).
- The WorkBuddy-side hot-reload mechanism for `tsbx_rules.json` (per-invocation re-read vs. process restart). Both `tsbx.dll` and the rust source string `appended NDJSON rule line. p...` suggest NDJSON rule appends are supported, but the exact behavior was not exercised.
- Whether the fix recommendation below is the *right* fix or only mitigates a symptom. A proper fix likely requires changes in `genie-safe-delete.cjs` and `safe-delete-bulk-guard.cjs` to either recognize package-manager-controlled cleanup or fail-closed atomically.

---

## IMPACT

- **npm install failures:** `npm ci` is the canonical "I want a clean state" command. It is unsafe to use from inside a WorkBuddy-spawned shell.
- **Misleading test regressions:** Test runs may report `Cannot find module 'parse5/dist/index.js'` or `Cannot find module 'entities/dist/escape.js'`, which look like missing dependencies but are actually partial-deletes. The agent or user may waste time debugging nonexistent code regressions.
- **Tracked worktree file loss:** Files disappear without any user-initiated destructive operation. Recovery is non-trivial (`git restore --worktree`); without HEAD/index integrity checks first, an inexperienced user might run `git checkout HEAD -- <path>` or `git reset --hard`, both of which could re-introduce data loss or rewrite history.
- **Risk to uncommitted work:** The worktree deletion pattern deletes files, not their uncommitted changes. If a file is `M`-status (modified) and then deleted, the worktree-only deletion does not lose the changes (they are still in the index) — but the user has to realize the recovery path is `git restore --worktree <path>`, not the obvious "checkout the file from history".
- **Not a repository corruption issue:** the Git object database is intact in every observed case. `git fsck` is healthy. This is critical for the recommended workarounds and for users to understand the situation correctly.

The impact is **NOT** repository corruption. The impact is **user trust** and **operational efficiency**:
- Routine commands (`git switch`, `git merge`, `npm ci`) become unreliable
- Recurring false-positive "the repo is broken" signals
- Every test run is potentially affected by a half-deleted `node_modules`

---

## WORKAROUND (verified in lab and at user site)

These workarounds are **independently verified** by the user and by the lab probe:

1. **Test scratch space must use `os.tmpdir()`, not `process.cwd()`.** The user has already adopted this for the affected test files. (See `bin/build-fixture.ps1` in the lab for the pattern.)
2. **`npm ci` must be run from a non-WorkBuddy shell.** A regular PowerShell / cmd where `CODEBUDDY_SESSION_ID` is not set will not have the shim active, so `npm ci` will succeed normally.
3. **After any `git switch` or `git merge`, run `git status --short` immediately.** If any ` D` lines appear, run `git restore --worktree <path>` (one at a time, or `git restore --worktree -- .` for all). The recovery is non-destructive: HEAD, index, and blob are intact in every observed case.
4. **Commit frequently.** Tracked worktree files that are committed are not at risk; the issue is with the worktree-only state. Commit-then-do-other-operations limits the window.
5. **If a package manager's clean install is required inside a WorkBuddy session, use `npm install` (not `npm ci`)** — it does not delete the entire `node_modules` tree in one operation, so the bulk-guard threshold is less likely to fire. This is a workaround, not a fix.

### PROPOSED WORKAROUND (requires product-team confirmation)

If the team confirms the rule semantics (`inherit_user` = "let NTFS ACL apply, no extra restriction"), a single narrow rule in `tsbx_rules.json` -> `file_rules_user` would exempt the user's project from the deny-by-default:

```json
{ "path": "D:\\Dev\\<user-project>\\**", "type": "inherit_user" }
```

This is **strictly narrower** than the existing `D:\\openclaw\\proxy-agent\\**` rule in `file_rules_user`. It does not affect any other path. **This proposal is included for the team's consideration; it has not been applied to the live system.**

---

## SUGGESTED PRODUCT FIX

These suggestions target the failure modes, not the safety mechanism itself.

1. **Recognize package-manager controlled cleanup.** The shim / bulk-guard should detect `npm ci` / `pnpm install --frozen-lockfile` / `yarn install --frozen-lockfile` and either pre-allow the entire `node_modules` tree (it is about to be re-populated by the same tool that is deleting it) or apply a much higher threshold (the `node_modules/<pkg>` count can be in the thousands; the 20-default is unrealistic for any non-trivial package).
2. **Atomic pre-deletion / post-deletion checks for `npm ci`.** When npm is about to delete `node_modules/`, the shim should perform a *test deletion* of the parent first. If the test deletion succeeds for the parent, all child deletions should be batched. If the test fails, abort atomically. The current fail-closed design is correct in principle but the threshold makes it impossible to use in practice.
3. **`git switch` / `git merge` are atomic operations from git's perspective.** The kernel filter (or the rule set) should treat `git.exe` as a developer-tool and inherit the user's permissions, not the deny-by-default policy. This is consistent with the existing `white_process` section (which currently lists only browsers). Adding `**\\git.exe` to `white_process` (with a corresponding `file_rules_user` entry for the dev workspace) would prevent the worktree anomaly.
4. **Diagnostic error messages should be clear.** When the bulk-guard fires, the current error message points to the target directory but does not mention the threshold, the safe-delete shim, or a recovery hint. Suggest a single-line actionable error: `[safe-delete] bulk delete blocked: 59 files in .../node_modules/entities exceeds threshold 20. Either raise threshold, allow the path, or run outside a WorkBuddy session.`
5. **Sandbox policy should not create partially-mutated worktrees.** The current design has the property that an in-flight `git switch` can leave the worktree in a state that git does not consider valid. Either the entire operation must be denied atomically (preferred, but expensive) or the post-operation state must be verifiable. The current behavior — "deny some, allow others, silently" — is the worst of both worlds.
6. **Pre-flight tool-call review.** When a tool-call is about to spawn a process that will modify many files, surface a single confirmation UI rather than a per-call confirm-required error. The current `SAFE_DELETE_BULK_CONFIRM_REQUIRED` is per-call, so a 5000-file `npm ci` would fire 250 confirmations.
7. **Add a `package_manager_safe: true` flag to the shim or rules** that npm / pnpm / yarn can opt into. The flag is set by the package manager's `node_modules` cleanup code and exempts it from the bulk-guard.

---

## WHAT THE TENCENT TEAM NEEDS TO FIX

The team needs to:

1. **Decide whether `npm ci` is supposed to work inside a WorkBuddy session.** If yes, the bulk-guard threshold or its `node_modules` heuristic must be updated. If no, the documentation should make this explicit and the recommended workflow should be "use a regular shell for package management".
2. **Decide whether `git switch` / `git merge` are supposed to work inside a WorkBuddy session.** If yes, `git.exe` should be in the developer-tool allow-list (e.g., extend `white_process` with `**\\git.exe` and corresponding `inherit_user` file rule for the workspace). If no, the documentation should make this explicit and the recommended workflow should be "run git from a regular shell".
3. **Add a single error message that explains "safe-delete intercepted your operation, the shim is at <path>, here is how to disable it for this path"**, with a copy-paste rule. The current `SAFE_DELETE_BULK_CONFIRM_REQUIRED` error does not give the user enough information to recover on their own.
4. **Document the rule schema** (the type vocabulary and semantics) so users can self-service add narrow rules. Currently the only documentation is the `_comment` field in `tsbx_rules.json` and the binary strings, neither of which is user-facing.

---

## WHAT REMAINS UNKNOWN

- Whether `tsbx_rules.json` is hot-reloaded or only read on process startup. The lab probe did not exercise this.
- The exact mechanism by which the kernel filter applies to git.exe (per-process filter load via `sandbox-cli`? per-thread? per-handle?). The kernel filter mechanism is correct at the OS level (file system minifilter) but the rules engine's interaction with `git`'s specific file access patterns is not directly observed.
- Whether the `modify_backup` field in `tsbx_rules.json` (mentioned in the binary but not in the current `tsbx_rules.json`) is a newer field that supersedes `recyclebin_backup` and what its semantics are.
- The user-side frequency of the worktree anomaly. From the audit log, the user has hit it 5+ times across 4 days. The lab probe confirms the npm side; the git side is inferred.

---

## REPRO BUNDLE

The lab at `D:\Dev\workbuddy-rootcause-lab\` is the disposable repro bundle. It contains:

- `bin/probe-shim.cjs` — verifies the shim is active in the env
- `bin/repro-node-delete.mjs` — runs fs.rmSync on a small/large fixture, captures exit code + side effects
- `bin/repro-all.ps1` — runs Node + Git + npm probes in both modes
- `bin/build-fixture.ps1` — creates the small/large fixtures
- `bin/build-git-probe.ps1` — initializes the disposable git repo
- `bin/check-worktree.ps1` — verifies tracked file integrity after each git operation
- `bin/run-git-cycles.ps1` — runs the N switch + 1 merge cycle
- `bin/run-as-workbuddy.ps1` — sets the WorkBuddy env vars and runs a child command
- `node-delete-probe/`, `npm-probe/`, `git-probe-normal/`, `git-probe-workbuddy/`, `git-probe-allow-rule/` — the actual probes
- `report/environment-summary.txt` — sanitized environment info
- `report/sanitized-evidence.md` — full evidence pack (no PII)
- `report/results-normal.txt` — lab probe output, normal mode
- `report/results-workbuddy.txt` — lab probe output, workbuddy sim mode
- `report/tsbx_rules.original.json` — unmodified backup of the original rules file
- `report/BUG-REPORT-TENCENT.md` — this file
- `report/ROOT_CAUSE_CLOSURE_REPORT.md` — closure summary

A fresh engineer can:
1. Inspect `report/environment-summary.txt` to confirm the environment matches.
2. Inspect `bin/run-as-workbuddy.ps1` to see exactly which env vars are set.
3. Run `bin/repro-all.ps1` to reproduce the npm ci failure and the Node fs.rm blocking.
4. Compare `results-normal.txt` vs `results-workbuddy.txt` to see the A/B contrast.
5. Apply the proposed narrow rule in `tsbx_rules.json` (or a controlled test environment) and re-run `bin/repro-all.ps1` to confirm the worktree side (the npm side is already covered by env-var sim).
