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
> change the conclusions: Bug A is component-confirmed at the shim/thresholds level
> (tested under the observed 5.3.11 and 5.3.13 artifacts); Bug B reproduced under
> 5.3.13 and was clean under a controlled 5.3.x rerun. The specific WorkBuddy build is not itself a causal
> variable under test.

## 3. Safe-delete / sandbox artifacts (sha256-pinned)

| Artifact | sha256 (or size) | Role |
|---|---|---|
| `genie-safe-delete.cjs` | `A9F9800C1244ADA606A73C96699DA3EBB3E056CE2115BF50912CD9EFC302D1C7` | Node shim — patches `fs.rmSync` etc. when `CODEBUDDY_SESSION_ID` set (Bug A) |
| `safe-delete-bulk-guard.cjs` | `EA40BA9DFD90D6555AC516AE3CA9C1BE7332D826781FBB07AC071903D88CA822` | bulk-guard — throws `SAFE_DELETE_BULK_CONFIRM_REQUIRED` at threshold 20 (Bug A) |
| `tsbx.dll` | 614,448 bytes (kernel minifilter) | present in the sandbox distribution; candidate component for Bug B (attachment/interception semantics not directly traced) |
| `genie-trash/win32-x64.exe` | 2,670,352 bytes (Rust crate trash-5.2.6, Tencent-signed) | performs the actual move-to-recycle-bin for the shim |
| `tsbx_rules.json` (live, raw bytes) | `30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A` — **ORIGINAL_LOCAL_SHA256** (raw shipped CRLF bytes; re-verified 2026-08-15 against the author's install) | sandbox rule file (see §4) |
| `report/tsbx_rules.original.json` (published) | `121c8e05805f6fec831a737dbe71c00d471dd85196b55cd89df94cb3bf68f8f2` — **PUBLIC_SANITIZED_TSBX_SHA256** (committed file; byte-pinned via `.gitattributes -text`) | sanitized published copy |

> **Hash provenance (REPAIR-6).** `PUBLIC_COPY_BYTE_IDENTICAL_TO_ORIGINAL = NO`.
> The published copy redacts the WorkBuddy companion-app install paths
> (`C:\openclaw\openclaw\**`, `D:\openclaw\proxy-agent\**`) to
> `<OPENCLAW_INSTALL>` placeholders and normalizes descriptive comments;
> JSON structure, rule types, and every other rule are retained verbatim.
> The two SHA256 values above are therefore intentionally different — do
> not compare them directly.

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

## 5. Process-execution model (observed and inferred)

**Observed:** WorkBuddy tool calls are observed to execute through a native
WorkBuddy/sandbox process chain (`WorkBuddy.exe` → `sandbox-cli.exe` → child
process such as `git.exe` / `node.exe` / `npm.cmd` / `bash`). `tsbx.dll` and
`tsbx_rules.json` are present in the sandbox distribution.

**Not directly proven (relevant to Bug B):** that `tsbx.dll` is attached to
*every* child process; that it intercepts *every* IRP/file operation; that it
denied the specific Git worktree operation; the exact `ModifyBackup` /
recycle-bin routing semantics. The exact attachment/interception semantics
relevant to Bug B were not directly traced.

Observed and inferred distinctions during the investigation:

1. **Node shim** attaches **only** to Node processes that inherit
   `CODEBUDDY_SESSION_ID` + `NODE_OPTIONS=--require=genie-safe-delete.cjs`.
   It patches `fs.*` delete entry points. It does **not** touch `git.exe`
   (FALSIFIED as the cause of Bug B via the SHIM-ONLY control, GIT-002).
2. **Kernel filter** (`tsbx.dll`) — inferred to attach to file operations of
   child processes spawned through `sandbox-cli.exe` (the IRP-level mechanism is
   plausible but not directly traced). It is the leading candidate mechanism
   (HIGH_CONFIDENCE_HYPOTHESIS) that can affect `git.exe` worktree operations
   (Bug B candidate, GIT-007).
3. **Native ancestry** is verifiable: `assert-native-workbuddy-context.ps1`
   confirms the process tree reaches `sandbox-cli.exe` (R1) or `WorkBuddy.exe`
   with a present `CODEBUDDY_SESSION_ID` (R2). Bug B was not observed in the
   tested non-WorkBuddy controls. Whether differences in native sandbox/filter
   attachment explain that result remains unresolved
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
