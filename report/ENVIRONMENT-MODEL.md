# ENVIRONMENT MODEL

Sanitized environment, version, and process-execution model for the
WorkBuddy safe-delete / sandbox investigation. Every `<PLACEHOLDER>` below
stands in for a real local path that is **not** published (see §5).

Source of truth: `report/environment-summary.txt` (captured 2026-08-13) plus
the native R1/R2 context assertions (`work/native-runs/…/context-assert.txt`,
local only). This document is referenced by `BUG-A-NPM-SAFE-DELETE.md`,
`BUG-B-GIT-WORKTREE-LOSS.md`, `ROOT_CAUSE_CLOSURE_REPORT.md`, and the
`MASTER-INVESTIGATION-LEDGER.md` (`ENV-*` rows).

---

## 1. Host & toolchain

| Item | Value |
|---|---|
| OS | Windows 11 (10.0.26200, 64-bit), NTFS |
| Architecture | x64 |
| Memory | 16 GB |
| Git | 2.49.0.windows.1 |
| Node (host) | 22.15.0 |
| npm | 10.9.2 |

## 2. WorkBuddy (Tencent) version

| Item | Value |
|---|---|
| Product | WorkBuddy (Tencent) |
| Version observed | **5.3.11** (Mavis lab) / **5.3.13** (native R1 run) — version drift across runs, both observed |
| Runtime | Electron 37.10.3 / Node 22.21.1 / Chrome 138 |
| Sandbox-cli | **5.3.3** |
| Install root | `<WORKBUDDY_INSTALL>` |
| User data root | `<USER_DATA>/.workbuddy/` |
| Sandbox root | `<WORKBUDDY_INSTALL>/resources/app.asar.unpacked/cli/vendor/sandbox/5.3.3` |

> **Version drift note (ENV-001):** the Mavis lab ran under 5.3.11; the native
> R1 reproduction ran under 5.3.13. Both are observed facts. The drift does not
> change the conclusions: Bug A is component-confirmed and version-independent at
> the shim/thresholds level; Bug B reproduced under 5.3.13 and was clean under a
> controlled 5.3.x rerun. The specific WorkBuddy build is not itself a causal
> variable under test.

## 3. Safe-delete / sandbox artifacts (sha256-pinned)

| Artifact | sha256 (or size) | Role |
|---|---|---|
| `genie-safe-delete.cjs` | `A9F9800C1244ADA606A73C96699DA3EBB3E056CE2115BF50912CD9EFC302D1C7` | Node shim — patches `fs.rmSync` etc. when `CODEBUDDY_SESSION_ID` set (Bug A) |
| `safe-delete-bulk-guard.cjs` | `EA40BA9DFD90D6555AC516AE3CA9C1BE7332D826781FBB07AC071903D88CA822` | bulk-guard — throws `SAFE_DELETE_BULK_CONFIRM_REQUIRED` at threshold 20 (Bug A) |
| `tsbx.dll` | 614,448 bytes (kernel minifilter) | `tsbx` kernel filter host, loaded by `sandbox-cli.exe` (Bug B candidate) |
| `genie-trash/win32-x64.exe` | 2,670,352 bytes (Rust crate trash-5.2.6, Tencent-signed) | performs the actual move-to-recycle-bin for the shim |
| `tsbx_rules.json` | `30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A` | sandbox rule file (see §4) |

## 4. tsbx sandbox rules (observed)

```jsonc
{
  "version": 1,
  "default_action": "deny_write",
  "recyclebin_backup": true,
  "auto_grant": true,
  "file_rules_user": [ "<WORKBUDDY_INSTALL>\\proxy-agent\\**" -> "inherit_user" ]
  // NOTE: <WORKSPACE>\** IS NOT in any allow-list
}
```

- `default_action: deny_write` — anything not explicitly allowed is denied write.
- `recyclebin_backup: true` — denied deletes may be routed to the OS recycle bin.
- `auto_grant: true` — allowed operations proceed without prompting.
- `<WORKSPACE>\**` (the dev workspace) has **no** allow rule → subject to `deny_write`.
- `ModifyBackup enabled=true method=ipc max 100MB` observed in the sandbox config;
  `$RECYCLE.BIN` carries an `inherit_user` rule (ENV-004). The exact routing of a
  denied delete is **not** directly observed — this is part of the unresolved
  component cause for Bug B.

## 5. Process-execution model (how the filters attach)

WorkBuddy spawns tool-call child processes through `sandbox-cli.exe`, which
attaches the `tsbx.dll` kernel minifilter to the child process tree:

```
WorkBuddy.exe
  └─ sandbox-cli.exe            (loads tsbx.dll as kernel filter host)
       └─ <child process>       (git.exe / node.exe / npm.cmd / bash ...)
            ├─ IRP-level file ops intercepted by tsbx filter
            └─ env: CODEBUDDY_SESSION_ID=<id>   (set by WorkBuddy)
                 └─ NODE_OPTIONS=--require=genie-safe-delete.cjs
                    (Node shim active in Node children only)
```

Key distinctions proven during the investigation:

1. **Node shim** attaches **only** to Node processes that inherit
   `CODEBUDDY_SESSION_ID` + `NODE_OPTIONS=--require=genie-safe-delete.cjs`.
   It patches `fs.*` delete entry points. It does **not** touch `git.exe`
   (FALSIFIED as the cause of Bug B via the SHIM-ONLY control, GIT-002).
2. **Kernel filter** (`tsbx.dll`) attaches to **all** file operations of every
   child process spawned through `sandbox-cli.exe`, at the IRP level. It is the
   only mechanism that can affect `git.exe` worktree operations (Bug B
   candidate, GIT-007).
3. **Native ancestry** is verifiable: `assert-native-workbuddy-context.ps1`
   confirms the process tree reaches `sandbox-cli.exe` (R1) or `WorkBuddy.exe`
   with a present `CODEBUDDY_SESSION_ID` (R2). Non-WorkBuddy shells do not load
   the filter, which is why Bug B never reproduces outside the native chain
   (GIT-008, WORKBUDDY_RUNTIME_ASSOCIATION=VERY_HIGH).

## 6. Sanitization placeholder glossary

| Placeholder | Meaning | Real value |
|---|---|---|
| `<USER_PROFILE>` | Windows user profile | `C:\Users\<user>` (not published) |
| `<WORKSPACE>` | disposable lab root | auto-resolved by `bin/_lib.ps1` from script location |
| `<WORKBUDDY_INSTALL>` | WorkBuddy install dir | `<USER_PROFILE>\...` (not published) |
| `<USER_DATA>` | WorkBuddy user-data dir | `<USER_PROFILE>\...` (not published) |
| `<TEMP>` | OS temp dir | `%TEMP%` (control root: `<TEMP>\workbuddy-rootcause-control`) |
| `<PROD_REPO>` | real production repo (the user's dev project) | withheld — hard-blacklisted in `bin/_lib.ps1` |

No real value for any placeholder above is committed to the public repository.
The historical Git metadata may contain the repository author's public Git
identity; that is not a credential.
