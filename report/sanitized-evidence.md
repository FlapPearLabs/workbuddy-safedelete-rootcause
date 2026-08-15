# Sanitized Evidence Pack

**Repository:** `FlapPearLabs/workbuddy-safedelete-rootcause`
**Investigation date:** 2026-08-13
**Path placeholders used throughout:**

- `<WORKSPACE>` = the disposable lab root the user cloned the repo into. Auto-resolved by `bin/_lib.ps1` `Resolve-RepoRoot` from the script's own path; users are not required to keep any particular location.
- `<WORKBUDDY_INSTALL>` = the WorkBuddy install root (e.g. `D:\WORKBUDDY` on a default install).
- `<USER_PROFILE>` = the Windows user profile (e.g. `C:\Users\<user>`).
- `<TEMP>` = `<USER_PROFILE>\AppData\Local\Temp` (the OS temp directory).

No real production source file content is included. Only short, necessary code snippets (under 30 lines each), SHA256 fingerprints, file names, line numbers, error strings, and behavioral descriptions are quoted.

---

## A. `genie-safe-delete.cjs` — Node shim

- **Source path (Windows):** `<WORKBUDDY_INSTALL>/resources/app.asar.unpacked/cli/vendor/shim/genie-safe-delete.cjs`
- **Size:** 29,796 bytes
- **SHA256:** `A9F9800C1244ADA606A73C96699DA3EBB3E056CE2115BF50912CD9EFC302D1C7`

**Key code segments (quoted verbatim, with line numbers from the version observed during this investigation):**

```javascript
// line 26
const SESSION_ID = process.env.CODEBUDDY_SESSION_ID
    || process.env.CLAUDE_SESSION_ID;

if (!SESSION_ID) {
    return;
}
```

```javascript
// line 567
const origUnlinkSync = fs.unlinkSync.bind(fs);
const origRmdirSync = fs.rmdirSync.bind(fs);
const origRmSync = fs.rmSync ? fs.rmSync.bind(fs) : null;
...
fs.unlinkSync = makeSyncWrapper(origUnlinkSync, false);
fs.rmdirSync = makeSyncWrapper(origRmdirSync, true);
if (origRmSync) fs.rmSync = wrappedRmSync;
```

```javascript
// line 365-386 (Windows path)
function trashOnWindows(absPath) {
    ...
    const script = [
        'Add-Type -AssemblyName Microsoft.VisualBasic',
        `[Microsoft.VisualBasic.FileIO.FileSystem]::${method}('${escaped}',`
            + ' [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,'
            + ' [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)',
    ].join('; ');
    execFileSync('powershell', ...);
}
```

**What this proves:** when `CODEBUDDY_SESSION_ID` is set in the env, the shim installs wrappers on `fs.unlinkSync`, `fs.rmdirSync`, `fs.rmSync` (and the async / promise variants). Every call to those APIs from the Node process (and any Node process that inherits the env) is rerouted to a `genie-trash.exe` subprocess or, on Windows, a `Microsoft.VisualBasic.FileIO.FileSystem.SendToRecycleBin` call. Fail-closed: the shim returns success even when the underlying trashed path is later blocked by the bulk-guard.

---

## B. `safe-delete-bulk-guard.cjs` — Bulk-delete guard

- **Source path:** `<WORKBUDDY_INSTALL>/resources/app.asar.unpacked/cli/vendor/shim/safe-delete-bulk-guard.cjs`
- **Size:** 16,725 bytes
- **SHA256:** `EA40BA9DFD90D6555AC516AE3CA9C1BE7332D826781FBB07AC071903D88CA822`

```javascript
// line 8-11
const CONFIRM_MARKER = '[safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED]';
const REJECTED_MARKER = '[safe-delete][SAFE_DELETE_BULK_REJECTED]';
const ERROR_MARKER = '[safe-delete][SAFE_DELETE_BULK_GUARD_ERROR]';
const DEFAULT_THRESHOLD = 20;
```

```javascript
// line 350-364 (the throwing decision)
if (totalCount >= context.threshold) {
    decision = {
        kind: 'confirmRequired',
        payload: {
            count: totalCount,
            threshold: context.threshold,
            scope: 'turn',
            targets: targets.slice(0, TARGET_SAMPLE_LIMIT),
            targetCount: targets.length,
        },
    };
    ...
    process.stderr.write(`${CONFIRM_MARKER} ${JSON.stringify(decision.payload)}\n`);
    process.exit(2);
}
```

**What this proves:** the bulk-guard is fail-closed — when the cumulative count of deletes in the current turn exceeds the threshold, it writes a `SAFE_DELETE_BULK_CONFIRM_REQUIRED` line to stderr and exits the wrapper process with code 2 (which the shim then surfaces as a thrown `Error` to the caller). The default threshold is 20.

---

## C. `tsbx_rules.json` — full content (redacted copy)

- **Live path:** `<WORKBUDDY_INSTALL>/resources/app.asar.unpacked/cli/vendor/sandbox/5.3.3/tsbx_rules.json`
- **ORIGINAL_LOCAL_SHA256** (raw shipped bytes): `30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A` (verified 2026-08-15)
- **PUBLIC_SANITIZED_TSBX_SHA256** (`report/tsbx_rules.original.json`, committed, byte-pinned via `.gitattributes -text`): `121c8e05805f6fec831a737dbe71c00d471dd85196b55cd89df94cb3bf68f8f2`
- **PUBLIC_COPY_BYTE_IDENTICAL_TO_ORIGINAL = NO** — the published copy redacts the WorkBuddy companion-app install paths (`C:\openclaw\openclaw\**`, `D:\openclaw\proxy-agent\**`) to `<OPENCLAW_INSTALL>` placeholders; JSON structure, rule types, and all other rules are retained verbatim.

```json
{
    "version": 1,
    "default_action": "deny_write",
    "recyclebin_backup": true,
    "auto_grant": true,
    "file_rules": [
        { "path": "%USERPROFILE%\\.ssh\\**",     "type": "no_access" },
        { "path": "%USERPROFILE%\\.gnupg\\**",   "type": "no_access" },
        { "path": "%LOCALAPPDATA%\\Temp\\**",    "type": "inherit_user" },
        { "path": "**\\$RECYCLE.BIN\\**",        "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.cache\\**",   "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.local\\**",   "type": "inherit_user" },
        { "path": "%LOCALAPPDATA%\\npm-cache\\**",       "type": "inherit_user" },
        { "path": "%LOCALAPPDATA%\\pnpm\\**",            "type": "inherit_user" },
        { "path": "%LOCALAPPDATA%\\Yarn\\**",            "type": "inherit_user" },
        { "path": "%LOCALAPPDATA%\\fnm_multishells\\**", "type": "inherit_user" },
        { "path": "%APPDATA%\\npm\\**",                  "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.npm\\**",             "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.yarn\\**",            "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.nvm\\**",             "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.fnm\\**",             "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.bun\\**",             "type": "inherit_user" },
        { "path": "%LOCALAPPDATA%\\pip\\**",             "type": "inherit_user" },
        { "path": "%LOCALAPPDATA%\\conda\\**",           "type": "inherit_user" },
        { "path": "%LOCALAPPDATA%\\uv\\**",              "type": "inherit_user" },
        { "path": "%APPDATA%\\uv\\**",                   "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.pyenv\\**",           "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.conda\\**",           "type": "inherit_user" },
        { "path": "%USERPROFILE%\\miniconda3\\**",       "type": "inherit_user" },
        { "path": "%USERPROFILE%\\miniforge3\\**",       "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.rustup\\**",  "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.cargo\\**",   "type": "inherit_user" },
        { "path": "%LOCALAPPDATA%\\go-build\\**","type": "inherit_user" },
        { "path": "%APPDATA%\\go\\**",           "type": "inherit_user" },
        { "path": "%USERPROFILE%\\go\\**",       "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.m2\\**",      "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.gradle\\**",  "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.sdkman\\**",  "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.dotnet\\**",  "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.nuget\\**",   "type": "inherit_user" },
        { "path": "%LOCALAPPDATA%\\NuGet\\**",   "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.docker\\**",  "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.asdf\\**",    "type": "inherit_user" },
        { "path": "%APPDATA%\\Code\\**",         "type": "inherit_user" },
        { "path": "%APPDATA%\\Trae\\**",         "type": "inherit_user" },
        { "path": "%APPDATA%\\Microsoft\\Windows\\PowerShell\\**",  "type": "inherit_user" },
        { "path": "%LOCALAPPDATA%\\Microsoft\\Windows\\PowerShell\\**", "type": "inherit_user" },
        { "path": "<WORKBUDDY_INSTALL>\\openclaw\\**",         "type": "inherit_user", "_comment": "WorkBuddy companion app (path redacted in published copy)" },
        { "path": "%USERPROFILE%\\.openclaw\\**",       "type": "inherit_user" }
    ],
    "file_rules_user": [
        { "path": "<WORKBUDDY_INSTALL>\\proxy-agent\\**", "type": "inherit_user", "_comment": "WorkBuddy proxy agent (path redacted in published copy)" }
    ],
    "registry_rules": [],
    "process_rules": [],
    "network_rules": [],
    "network_rules_user": [],
    "white_process": [
        { "path": "**\\msedge.exe" },
        { "path": "**\\chrome.exe" },
        { "path": "**\\firefox.exe" },
        { "path": "**\\brave.exe" },
        { "path": "**\\opera.exe" },
        { "path": "**\\360se.exe" },
        { "path": "**\\QQBrowser.exe" },
        { "path": "**\\SogouExplorer.exe" }
    ],
    "network_policy": {
        "enabled": true,
        "default": "allow",
        "deny_ips": [],
        "deny_domains": []
    }
}
```

`<WORKSPACE>\**` is **not** in any allow-list. With `default_action: deny_write`, all writes (and deletes via `IRP_MJ_SET_INFORMATION`) to `<WORKSPACE>\**` are denied by default. The `recyclebin_backup: true` flag suggests denied operations may be redirected to the OS recycle bin; the empirical confirmation of this routing under the kernel filter has **not** been performed in this round (see section I).

---

## D. tsbx binary strings — rule type vocabulary

Extracted from `<WORKBUDDY_INSTALL>/resources/app.asar.unpacked/cli/vendor/sandbox/5.3.3/tsbx.dll`:

```
no_access read_only pinned_allow inherit_user trust create_only auto_grant modify_backup unknown default
```

```
'file_rules' field (must be array)
'file_rules' array must not be empty
'file_rules[X]' must be an object
: missing or invalid 'path'
: missing or invalid 'type'
: unknown type 'XXX'                (validates against the enum above)
'file_rules_user' must be an array
'white_process' must be an array
```

```
'recyclebin_backup' must be a boolean
'auto_grant' must be a boolean
'modify_backup' is an object with sub-field 'enabled'
```

Extracted from `sandbox_ffi.dll`:

```
sandbox\src\permission\manager.rs
:build_windows_rules:
:add_file_rule: source=?, ty=?
globalsessiontempauto_grant
```

**What this confirms:**
- The rule engine reads `tsbx_rules.json` (path inferred from the location of the binary; the exact config path is not asserted in the binary strings).
- Rule types form an enum: `no_access | read_only | pinned_allow | inherit_user | trust | create_only | auto_grant | modify_backup | unknown | default`.
- `inherit_user` is the most permissive: based on the field name and the binary's surrounding strings, it is **inferred** to mean "let the user's normal NTFS ACL apply; do not add sandbox restrictions" — but this is **inferred**, not **proven** by direct product documentation. Tencent's documentation in the source tree was not consulted during this round; engineers should confirm the precise semantics.

---

## E. Live minimal repro results (this lab)

### E.1 — Node fs.rm small fixture (5 files, < threshold 20)

**Normal mode:**
```
MODE=normal
WHICH=small
FILE_COUNT_BEFORE=5
SHIM_SESSION_ID=
STILL_EXISTS_AFTER=false
EXIT_CODE=0
```

**WorkBuddy shim simulation mode** (env vars set, `NODE_OPTIONS=--require=genie-safe-delete.cjs`):
```
MODE=shim
WHICH=small
FILE_COUNT_BEFORE=5
SHIM_SESSION_ID=simulated-bundle-session
STILL_EXISTS_AFTER=false       <-- appears deleted to the caller
EXIT_CODE=0
```

In normal mode, native `fs.rmSync` does a real delete. In shim simulation, the shim catches the call, runs `genie-trash.exe` (or falls back to `Microsoft.VisualBasic.FileIO.FileSystem.SendToRecycleBin`), reports success.

**Shim report (captured by the lab probe, sanitized):**
```json
{"operation":"trash","runtime":"node","path":"<WORKSPACE>\\fixtures\\node-delete\\small","timestamp":...}
```

### E.2 — Node fs.rm large fixture (40 files, > threshold 20)

**Normal mode:**
```
MODE=normal
WHICH=large
FILE_COUNT_BEFORE=40
STILL_EXISTS_AFTER=false
EXIT_CODE=0
```

**WorkBuddy shim simulation mode:**
```
MODE=shim
WHICH=large
FILE_COUNT_BEFORE=40
THROWN=Error: [safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED] {"count":40,"threshold":20,"scope":"turn","targets":["<WORKSPACE>\\fixtures\\node-delete\\large"],"targetCount":1}
EXIT_CODE=1
```

The shim's bulk-guard throws `SAFE_DELETE_BULK_CONFIRM_REQUIRED` and **does not perform the delete** (fail-closed). The target directory remains on disk.

### E.3 — npm ci

**Normal mode:**
```
NPM_CI_PHASE1_INSTALL_EXIT=0
NPM_CI_PHASE1_INSTALL_MANIFEST_FILE_COUNT=92
NPM_CI_PHASE1_CI_EXIT=0
NPM_CI_PHASE1_CI_OUTPUT_HEAD=added 2 packages in 1s
NPM_CI_PHASE1_POST_FILE_COUNT=92
NPM_CI_PHASE1_CRITICAL_PARSE5=true
NPM_CI_PHASE1_CRITICAL_ENTITIES_ESCAPE=true
REMOVED=0 ADDED=0 CHANGED=0
```

**WorkBuddy shim simulation mode:**
```
NPM_CI_PHASE2_SHIM_INJECTED=yes
NPM_CI_PHASE2_INSTALL_EXIT=0
NPM_CI_PHASE2_INSTALL_MANIFEST_FILE_COUNT=92
NPM_CI_PHASE2_CI_EXIT=1
NPM_CI_PHASE2_CI_OUTPUT_HEAD=npm error [safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED] {"count":59,"threshold":20,"scope":"turn","targets":["<WORKSPACE>\\npm-probe\\node_modules\\entities"],"targetCount":1}
NPM_CI_PHASE2_BULK_GUARD_TRIGGERED=yes
NPM_CI_PHASE2_BULK_GUARD_MARKER=[safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED] {"count":59,"threshold":20,"scope":"turn","targets":["<WORKSPACE>\\npm-probe\\node_modules\\entities"],"targetCount":1}
NPM_CI_PHASE2_SHIM_REPORT_TRIES=1
NPM_CI_PHASE2_SHIM_REPORT_REASON=unknown
NPM_CI_PHASE2_SHIM_TRASH_EVENT <ts> op=trash runtime=node path=<WORKSPACE>\npm-probe\node_modules\.package-lock.json
NPM_CI_PHASE2_POST_FILE_COUNT=91
NPM_CI_PHASE2_CRITICAL_PARSE5=true
NPM_CI_PHASE2_CRITICAL_ENTITIES_ESCAPE=true
```

**Partial-mutation evidence (PROVEN):** the shim report captured by the lab probe shows that under the shim, npm ci's first successful delete is `node_modules\.package-lock.json` (a single file, well below the threshold), which the shim silently trashes via `genie-trash`. When npm ci then attempts to delete `node_modules/entities` (a 59-file directory), the bulk-guard fires and npm ci aborts. The pre/post manifest diff in `NPM_CI_PHASE2_DIFF` confirms the missing file is exactly `.package-lock.json`. The `.bin` directory is also missing in some runs (varies by npm version / shim version), but the smoking gun is the trash event for `.package-lock.json`: **npm ci's cleanup of `node_modules` is non-atomic and the shim permits partial mutation before the guard fires.**

### E.4 — Git worktree cycles (5 cycles + 1 fast-forward merge, with REAL branch delta)

**Fixture build (the lab probe's disposable Git repo):**
```
GIT_PROBE_INIT_REPO=<WORKSPACE>\fixtures\git-probe-normal
GIT_PROBE_MASTER_HEAD=<60-file root commit>
[master (root-commit) <sha>] commit-A: 60 tracked files on master (25 src, 25 test, 10 docs)
 60 files changed, 60 insertions(+)
... 60 create mode 100644 ...
GIT_PROBE_FEATURE_HEAD=<diverged feature commit>
[feature/probe/multi-level <sha>] commit-B: feature changes (modify 48, delete 5, add 16, rename 4)
GIT_PROBE_MASTER_FILE_COUNT=60
GIT_PROBE_FEATURE_FILE_COUNT=71
BRANCH_DELTA_VALID=YES
```

The feature branch contains: 46 modified tracked files, 5 deleted tracked files (`test/t16/spec.txt` ... `test/t20/spec.txt`), 16 newly added tracked files (`src/new01.txt` ... `test/new08.txt`), and 4 renames (`docs/d09/note-renamed.txt`, `docs/d10/note-renamed.txt`, `src/a24/main-renamed.txt`, `src/a25/main-renamed.txt`). This produces a non-trivial worktree mutation on every `git switch feature/probe/multi-level` and on the `git merge --ff-only`.

**Per-step integrity check (run after EVERY git operation):**

Every step in both NORMAL and SHIM-ONLY modes emits a structured `WORKTREE_CHECK_*` block. The verdict line for each of the 11 steps (5 cycles × 2 + 1 merge) in both modes is:

```
WORKTREE_CHECK_VERDICT=CLEAN
```

Concretely, for every step:
- `TRACKED_COUNT` matches `PHYSICAL_COUNT` (no files missing)
- `MISSING_COUNT=0`
- `WORKTREE_ONLY_LOSS_COUNT=0`
- `STATUS_D=0` (no ` D` lines)
- `FSCK_HEALTHY=YES`
- `MODIFIED_COUNT=0` after a clean switch
- After the merge: `TRACKED=71` (master + feature additions), `PHYSICAL=71`, all intact

**Critical negative finding:** the simulated WorkBuddy env (env vars + `NODE_OPTIONS=--require=genie-safe-delete.cjs`) does **not** reproduce the worktree file loss. The Node shim is a per-Node-process patch and does not touch `git.exe`. The kernel filter (`tsbx.dll`) is the layer that intercepts `git.exe`'s file operations at the IRP level, and it is only loaded when `git.exe` is spawned as a child of `sandbox-cli.exe` inside a real WorkBuddy session.

**This is the key reason the Issue B experiment must be executed inside a real WorkBuddy tool-call, not in the lab.** The lab probe conclusively proves that the Node shim layer is not responsible for the git worktree anomaly. The kernel-filter layer is the leading candidate mechanism (HIGH_CONFIDENCE_HYPOTHESIS) consistent with the observed user-side pattern (5+ events in the audit log).

---

## F. User-side audit log entries (sanitized quotes from real WorkBuddy audit log)

The user has run repeated native WorkBuddy sessions and observed the worktree anomaly. The following are the user's own words captured in the audit log, reproduced as evidence of the recurring pattern.

```
2026-08-10  audit "Worktree Checkout Anomaly（merge 后再次出现 32 个 tracked ` D`）"

2026-08-11  audit "checkout anomaly 再现：`git switch master` 后 16 个 test 文件
            worktree-only 删除。已证明 index tree==HEAD tree、fsck 健康、HEAD
            含文件 → 按 guard 执行 `git restore --worktree -- .` 恢复成功"

2026-08-13 01:5x  audit "merge 后两个 tracked docs 文件从 worktree 消失
                  （HEAD/index/blob 完好）→ 非破坏性 git restore --worktree 恢复"

2026-08-13 16:5x  audit "merge 后 17 个 tracked test 文件从 worktree 消失
                  （HEAD=index、blob 完好）→ git restore --worktree -- test/ 恢复"

2026-08-12 23:5x  audit "<real project> node_modules 残缺（entities@8.0.0
                  缺 dist/escape.js 等）→ 首跑 41 fail；npm ci 被 npm 10.9.7
                  safe-delete 批量确认拦截（SAFE_DELETE_BULK_CONFIRM_REQUIRED，
                  非交互 shell 无法确认）；workaround：rm -rf node_modules +
                  npm install（仅 untracked，lockfile 未变）→ 基线恢复 435/0/3"
```

Raw audit log event (sanitized, project name replaced with `<real project>`):

```json
{
  "category": "file-safety",
  "eventType": "file-safety.bulk-delete.needs-approval",
  "decision": "info",
  "commandPreview": "... rm -rf node_modules/entities ...",
  "count": 56,
  "threshold": 50,
  "targets": "<real project>/zhihu-answer-grabber/node_modules/entities"
}
```

(The `count: 56, threshold: 50` in this entry reflects the real project's `CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD` being overridden to 50 in the user's working project. The lab probe uses the default threshold of 20.)

**These are not the user's production code or any production repo file content. They are the user's own audit-log notes on the recurring failures, with project paths and package names replaced.** The audit log itself lives at `<USER_DATA>\.workbuddy\logs\audit\audit_<date>.jsonl` (path inferred from the standard WorkBuddy data layout; exact location may vary by version).

---

## G. `tsbx_rules.json` — backup and proposed narrow rule

The original `tsbx_rules.json` is preserved at:
- `<WORKBUDDY_INSTALL>/resources/app.asar.unpacked/cli/vendor/sandbox/5.3.3/tsbx_rules.json`
  (ORIGINAL_LOCAL_SHA256 `30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A`, raw shipped bytes, verified 2026-08-15)
- Lab copy: `report/tsbx_rules.original.json`
  (PUBLIC_SANITIZED_TSBX_SHA256 `121c8e05805f6fec831a737dbe71c00d471dd85196b55cd89df94cb3bf68f8f2` — NOT byte-identical; companion-app install paths redacted to `<OPENCLAW_INSTALL>`).

A narrow lab rule is **designed but not yet applied to the live system** (would require either a WorkBuddy restart or a confirmed hot-reload mechanism). The proposed rule is:

```json
{ "path": "<WORKSPACE>\\**", "type": "inherit_user" }
```

This rule is **scoped strictly to the disposable lab directory** and is **narrower** than the existing example `<WORKBUDDY_INSTALL>\proxy-agent\**` rule in `file_rules_user`. It does **not** affect the real production repo or any other `<WORKSPACE>\**` path.

---

## H. Empirical gap — what was NOT exercised

This investigation was conducted from a non-WorkBuddy shell (Mavis orchestrator, a MiniMax Code agent). The following are explicitly out of reach from this environment and require native WorkBuddy execution:

1. **The kernel-filter interaction with `git.exe`.** `tsbx.dll` is present in the WorkBuddy sandbox distribution and is the leading candidate component for the Git anomaly, but its exact attachment/interception behavior was not directly traced. The lab probe conclusively proves that the Node shim alone does not cause the worktree anomaly. The kernel-filter hypothesis (deny-by-default + `recyclebin_backup` routing) is the leading candidate mechanism (HIGH_CONFIDENCE_HYPOTHESIS) consistent with the observed user-side pattern. **Verification requires a native WorkBuddy tool-call execution of the Git probe.** The exact procedure is documented in `report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md`.
2. **Hot-reload vs. per-invocation vs. process-startup read of `tsbx_rules.json`.** The binary strings do not unambiguously identify the reload mechanism. Both `tsbx.dll` and the rust source string `appended NDJSON rule line. p...` (from `sandbox_ffi.dll`) suggest NDJSON rule appends are supported, but the exact behavior was not exercised.
3. **ETW / ProcMon capture of relevant filesystem operations and sandbox / filter activity.** The exact mechanism by which the kernel filter may interfere with git's file operations is not yet directly observed; it is a Windows file system minifilter, so relevant activity (which may or may not include denials) would appear in the kernel ETW stream (`Microsoft-Windows-Kernel-File`). ETW capture was not performed in this round (ProcMon is not installed; `xperf` availability not verified in the user's environment).
4. **The `inherit_user` rule semantics.** The behavior is **inferred** from the rule type name + the rule's role (broad allow-list pattern in the file). The exact product-team definition was not consulted during this round.

---

## I. WorkBuddy live processes observed during investigation

```
WorkBuddy.exe             (multiple, electron main + renderer + sidecar)
sandbox-cli.exe           (PID <redacted>)   — loads tsbx.dll as kernel filter host
sandbox-cli-gc.exe        (PID <redacted>)   — garbage-collects sandbox state
codebuddy.exe             (CLI server, --serve)
daemon-app-server-entry.js
editor_sdk.exe            (Tencent docs engine)
```

PIDs are redacted because the values change on every session and would mislead readers.

---

## J. Source quotation discipline

The proprietary source quotations in sections A and B are limited to the minimum lines necessary to identify:
- the API surface patched by the shim (A),
- the threshold and the throw decision (B),
- the Windows-specific trash fallback (A).

No more than 30 lines are quoted from any single proprietary file. No full file is reproduced. The SHA256 of each file is included so the receiving team can compare the exact same binary they ship against the binary used in this investigation.
