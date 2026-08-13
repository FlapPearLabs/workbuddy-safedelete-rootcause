# Sanitized Evidence Pack

Path placeholders used throughout:
- `<WORKSPACE>` = the real production repo path (DO NOT include in published bug report)
- `<WORKBUDDY_INSTALL>` = the WorkBuddy install root (DO NOT include)
- `<USER_DATA>` = the user's workbuddy user data root (DO NOT include)
- `<TEMP>` = `C:\Users\ssy\AppData\Local\Temp`

All evidence below is taken from a disposable lab at `D:\Dev\workbuddy-rootcause-lab\` and `C:\Users\ssy\AppData\Local\Temp\workbuddy-rootcause-control\`. **No real production file content** is included.

---

## A. `genie-safe-delete.cjs` — Node shim (29,796 bytes, sha256 A9F9800C1244ADA606A73C96699DA3EBB3E056CE2115BF50912CD9EFC302D1C7)

**Key code segments (quoted verbatim, with line numbers):**

```
// line 26
const SESSION_ID = process.env.CODEBUDDY_SESSION_ID
    || process.env.CLAUDE_SESSION_ID;

if (!SESSION_ID) {
    return;
}
```

```
// line 567
const origUnlinkSync = fs.unlinkSync.bind(fs);
const origRmdirSync = fs.rmdirSync.bind(fs);
const origRmSync = fs.rmSync ? fs.rmSync.bind(fs) : null;
...
fs.unlinkSync = makeSyncWrapper(origUnlinkSync, false);
fs.rmdirSync = makeSyncWrapper(origRmdirSync, true);
if (origRmSync) fs.rmSync = wrappedRmSync;
```

```
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

---

## B. `safe-delete-bulk-guard.cjs` — Bulk-delete guard (16,725 bytes, sha256 EA40BA9DFD90D6555AC516AE3CA9C1BE7332D826781FBB07AC071903D88CA822)

```
// line 8-10
const CONFIRM_MARKER = '[safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED]';
const REJECTED_MARKER = '[safe-delete][SAFE_DELETE_BULK_REJECTED]';
const ERROR_MARKER = '[safe-delete][SAFE_DELETE_BULK_GUARD_ERROR]';

// line 11
const DEFAULT_THRESHOLD = 20;
```

```
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

---

## C. `tsbx_rules.json` — full content (sha256 30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A)

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
        { "path": "C:\\openclaw\\openclaw\\**",         "type": "inherit_user" },
        { "path": "%USERPROFILE%\\.openclaw\\**",       "type": "inherit_user" }
    ],
    "file_rules_user": [
        { "path": "D:\\openclaw\\proxy-agent\\**", "type": "inherit_user" }
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

`D:\Dev\**` is **not** in any allow-list. With `default_action: deny_write`, all writes (and deletes via IRP_MJ_SET_INFORMATION) to `D:\Dev\**` are denied unless `recyclebin_backup: true` routes them to the OS recycle bin.

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

This confirms:
- The rule engine reads `tsbx_rules.json` (path inferred from the location of the binary).
- Rule types form an enum: `no_access | read_only | pinned_allow | inherit_user | trust | create_only | auto_grant | modify_backup | unknown | default`.
- `inherit_user` is the most permissive: it means "let the user's normal NTFS ACL apply; do not add sandbox restrictions".

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

**WorkBuddy sim mode:**
```
MODE=workbuddy
WHICH=small
FILE_COUNT_BEFORE=5
SHIM_SESSION_ID=simulated-bundle-session
STILL_EXISTS_AFTER=false       <-- appears deleted to the caller
EXIT_CODE=0
```

In normal mode, native fs.rmSync does a real delete.
In workbuddy sim, the shim catches the call, runs `genie-trash.exe` (or falls back to `Microsoft.VisualBasic.FileIO.FileSystem.SendToRecycleBin`), reports success.

**shim report file (sanitized path):**
```
{"operation":"trash","runtime":"node","path":"D:\\Dev\\workbuddy-rootcause-lab\\node-delete-probe\\small","timestamp":...}
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

**WorkBuddy sim mode:**
```
MODE=workbuddy
WHICH=large
FILE_COUNT_BEFORE=40
THROWN=Error: [safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED] {"count":45,"threshold":20,"scope":"turn","targets":["D:\\Dev\\workbuddy-rootcause-lab\\node-delete-probe\\large"],"targetCount":1}
EXIT_CODE=1
```

The shim's bulk-guard throws `SAFE_DELETE_BULK_CONFIRM_REQUIRED` and **does not perform the delete** (fail-closed). The target directory remains on disk.

### E.3 — npm ci

**Normal mode:**
```
npm ci exit: 0
node_modules after: 3 entries (entities, parse5, .bin)
Missing files: 0
Added files: 0
```

**WorkBuddy sim mode:**
```
npm ci exit: 1
npm error [safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED] {"count":59,"threshold":20,"scope":"turn","targets":["D:\\Dev\\workbuddy-rootcause-lab\\npm-probe\\node_modules\\entities"],"targetCount":1}
node_modules after: 2 entries (entities, parse5)  <-- .bin and .package-lock.json gone
Missing files: 1
  MISSING: .package-lock.json
```

**Reproduction conditions (matters):** npm ci must be invoked while the parent process has `CODEBUDDY_SESSION_ID` set and `NODE_OPTIONS=--require=genie-safe-delete.cjs`. npm ci first deletes `node_modules/entities` (59 files, exceeds the 20-default threshold), the bulk-guard throws, npm ci aborts. The node_modules tree is left in a half-deleted state: `node_modules/entities` is not yet removed, but `.package-lock.json` and other small files have been silently trashed.

### E.4 — Git worktree cycles (5 cycles + 1 fast-forward merge)

**Normal mode:**
```
TRACKED_COUNT=52
PHYSICAL_COUNT=52
MISSING_COUNT=0
FSCK_HEALTHY=YES
WORKTREE_ONLY_LOSS=False
```

**WorkBuddy sim mode (env vars + shim, NO kernel filter):**
```
TRACKED_COUNT=52
PHYSICAL_COUNT=52
MISSING_COUNT=0
FSCK_HEALTHY=YES
WORKTREE_ONLY_LOSS=False
```

The simulated workbuddy env (env vars + shim) does **not** reproduce the worktree file loss. The kernel filter (`tsbx.dll`) is not active for git.exe under this simulated env.

This is the critical negative finding: the worktree anomaly requires the **full WorkBuddy sandbox** (where git.exe is spawned as a child of `sandbox-cli.exe` and the kernel filter is loaded into git's process), not merely the env vars + shim.

---

## F. User-side audit log entries (sanitized quotes from real WorkBuddy audit log)

These are the user's own words captured in the audit log. They are reproduced here as evidence of the recurring pattern.

```
2026-08-10  audit "Worktree Checkout Anomaly（merge 后再次出现 32 个 tracked ` D`）"

2026-08-11  audit "checkout anomaly 再现：`git switch master` 后 16 个 test 文件
            worktree-only 删除。已证明 index tree==HEAD tree、fsck 健康、HEAD
            含文件 → 按 guard 执行 `git restore --worktree -- .` 恢复成功"

2026-08-13 01:5x  audit "merge 后两个 tracked docs 文件从 worktree 消失
                  （HEAD/index/blob 完好）→ 非破坏性 git restore --worktree 恢复"

2026-08-13 16:5x  audit "merge 后 17 个 tracked test 文件从 worktree 消失
                  （HEAD=index、blob 完好）→ git restore --worktree -- test/ 恢复"

2026-08-12 23:5x  audit "zhihu-answer-grabber node_modules 残缺（entities@8.0.0
                  缺 dist/escape.js 等）→ 首跑 41 fail；npm ci 被 npm 10.9.7
                  safe-delete 批量确认拦截（SAFE_DELETE_BULK_CONFIRM_REQUIRED，
                  非交互 shell 无法确认）；workaround：rm -rf node_modules +
                  npm install（仅 untracked，lockfile 未变）→ 基线恢复 435/0/3"
```

```
audit log raw event (2026-08-12 23:53 file-safety.bulk-delete.needs-approval):
{
  "category": "file-safety",
  "eventType": "file-safety.bulk-delete.needs-approval",
  "decision": "info",
  "commandPreview": "... rm -rf node_modules/entities ...",
  "count": 56,
  "threshold": 50,
  "targets": "/d/Dev/zhihu-grabber-toolkit/zhihu-answer-grabber/node_modules/entities"
}
```

(The `count: 56, threshold: 50` in this entry reflects the real project's
`CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD` being overridden to 50. The lab probe
uses the default threshold of 20.)

---

## G. tsbx rules — backup and proposed narrow rule

The original `tsbx_rules.json` is preserved at:
- `<WORKBUDDY_INSTALL>/resources/app.asar.unpacked/cli/vendor/sandbox/5.3.3/tsbx_rules.json`
  (sha256 `30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A`)
- Lab copy: `D:\Dev\workbuddy-rootcause-lab\report\tsbx_rules.original.json` (same hash)

A narrow lab rule is **designed but not yet applied to the live system** (would require WorkBuddy restart). The proposed rule is:

```json
{ "path": "D:\\Dev\\workbuddy-rootcause-lab\\**", "type": "inherit_user" }
```

This rule is **scoped strictly to the disposable lab directory** and is **narrower** than the existing example `D:\\openclaw\\proxy-agent\\**` rule in `file_rules_user`. It does **not** affect the real production repo or any other `D:\Dev\**` path.
