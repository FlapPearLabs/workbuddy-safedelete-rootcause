# BUG A — `npm ci` aborted by WorkBuddy Node safe-delete bulk-guard

**Standalone vendor report.** Understandable without Bug B.
Companion: [`BUG-B-GIT-WORKTREE-LOSS.md`](BUG-B-GIT-WORKTREE-LOSS.md).

---

## TITLE
WorkBuddy `safe-delete` Node shim + bulk-guard aborts `npm ci` partway, leaving `node_modules`
in a half-deleted (non-atomic) state.

## PRODUCT / VERSION
- Product: WorkBuddy (Tencent)
- Version observed: 5.3.11 / 5.3.13 (see ENVIRONMENT-MODEL)
- Components:
  - `genie-safe-delete.cjs` (sha256 `A9F9800C1244ADA606A73C96699DA3EBB3E056CE2115BF50912CD9EFC302D1C7`)
  - `safe-delete-bulk-guard.cjs` (sha256 `EA40BA9DFD90D6555AC516AE3CA9C1BE7332D826781FBB07AC071903D88CA822`)

## ENVIRONMENT
| Item | Value |
|---|---|
| OS | Windows 11 (10.0.26200) |
| Git | 2.49.0.windows.1 |
| Node (host) | 22.15.0 |
| npm | 10.9.2 |
| WorkBuddy | 5.3.11 / 5.3.13 |
| Sandbox-cli | 5.3.3 |

## SUMMARY
When `npm ci` runs inside a WorkBuddy-spawned shell (where `CODEBUDDY_SESSION_ID` is set and
`NODE_OPTIONS=--require=genie-safe-delete.cjs`), the safe-delete bulk-guard throws
`SAFE_DELETE_BULK_CONFIRM_REQUIRED` and `npm ci` aborts. The shim has **already** trashed at
least one small file (`.package-lock.json`) before the guard fires, so `node_modules` is left
in a partial state. Subsequent builds/tests may report a package as missing internal files
even though it is still on disk.

## EXPECTED
`npm ci` deletes the existing `node_modules` and reinstalls from `package-lock.json`, yielding
a bit-identical `node_modules`.

## ACTUAL
Under the shim, `npm ci` exits 1:
```
npm error [safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED] {"count":59,"threshold":20,"scope":"turn","targets":[".../node_modules/entities"],"targetCount":1}
```
`node_modules` is half-mutated. `node_modules/entities` (the 59-file batch) is **not** deleted
(fail-closed), but `.package-lock.json` was already trashed by the shim beforehand.

## MINIMAL REPRO
```powershell
# Clone to a NON-TEMP, writable path (any drive). The shim deliberately
# skips os.tmpdir() paths, so cloning to %TEMP% will NOT reproduce the
# shim behavior. Prerequisites: Windows, PowerShell, Git, Node/npm on
# PATH, npm-registry network access, and a WorkBuddy install for the
# SHIM phases (see root README "Prerequisites").
$repo = Join-Path $env:USERPROFILE 'workbuddy-safedelete-rootcause'
git clone https://github.com/FlapPearLabs/workbuddy-safedelete-rootcause $repo
cd $repo
powershell -ExecutionPolicy Bypass -File .\bin\repro-all.ps1
```
Expected key lines:
```
PHASE1A NORMAL small: STILL_EXISTS_AFTER=false EXIT_CODE=0
PHASE1B NORMAL large: STILL_EXISTS_AFTER=false EXIT_CODE=0
PHASE1C SHIM   small: STILL_EXISTS_AFTER=false EXIT_CODE=0
PHASE1D SHIM   large: THROWN=... SAFE_DELETE_BULK_CONFIRM_REQUIRED EXIT_CODE=1
PHASE2 NPM_CI_PHASE1_CI_EXIT=0
PHASE2 NPM_CI_PHASE2_CI_EXIT=1   NPM_CI_PHASE2_BULK_GUARD_TRIGGERED=yes
PHASE2 NPM_CI_PHASE2_SHIM_TRASH_EVENT <ts> op=trash runtime=node path=...\node_modules\.package-lock.json
```

## A/B
| Mode | npm ci exit | Bulk guard | `.package-lock.json` | `node_modules/entities` |
|---|---|---|---|---|
| NORMAL (env cleared) | 0 | not fired | present | present (92 files) |
| SHIM (env + `NODE_OPTIONS=--require=genie-safe-delete.cjs`) | 1 | fired (`count=59, threshold=20`) | **trashed by shim** | still on disk (guard blocked batch) |

Same lockfile content both modes: `parse5@8.0.1` + `entities@8.0.0`.

## PARTIAL MUTATION EVIDENCE
The shim report (captured by `bin/repro-npm-ci.ps1`) is the smoking gun:
```
NPM_CI_PHASE2_SHIM_TRASH_EVENT <ts> op=trash runtime=node path=<WORKSPACE>\npm-probe\node_modules\.package-lock.json
```
`npm ci`'s first successful delete is a single small file (count=1, below threshold) that the
shim silently trashes. The bulk-guard only fires on the next bigger batch
(`node_modules/entities`, count=59). The combination is **non-atomic**.

## IMPACT
- `npm ci` (the canonical "clean state" command) is unsafe inside a WorkBuddy-spawned shell.
- Misleading test regressions: tests report `Cannot find module 'entities/dist/escape.js'`
  which look like missing dependencies but are partial deletes.
- No object-database corruption; `.git/` is intact.

## WORKAROUND (verified)
1. Run `npm ci` from a **non-WorkBuddy shell** (no `CODEBUDDY_SESSION_ID` → no shim).
2. Or use `npm install` instead of `npm ci` inside a session (less likely to hit threshold).
3. Do **not** treat `SAFE_DELETE_BULK_CONFIRM_REQUIRED` as a hard failure of the package; the
   `node_modules` tree is partially present.

## ROOT CAUSE
`genie-safe-delete.cjs` patches `fs.rmSync` (and 4 other `fs.*` entry points) when
`CODEBUDDY_SESSION_ID` is set, rerouting deletes to `genie-trash` /
`Microsoft.VisualBasic.FileIO.FileSystem.SendToRecycleBin` (decision at
`genie-safe-delete.cjs:546` `tryTrash`→`checkBulkDeleteGuard`). `safe-delete-bulk-guard.cjs`
defaults to a **20-delete threshold** and throws fail-closed (`safe-delete-bulk-guard.cjs:222`)
when the cumulative count in the current turn exceeds it. `node_modules/<pkg>` directories
routinely exceed 20 files, so `npm ci`'s cleanup is blocked mid-way; the shim's prior small
trash leaves the tree partial.

## CONFIDENCE
**HIGH / CONFIRMED.** Reproduced in a disposable lab with the exact package versions;
mechanism verified via source line numbers + string evidence; user-side audit log independently
confirms the same error class.

## SUGGESTED FIXES
1. Recognize package-manager controlled cleanup (`npm ci` / `pnpm install --frozen-lockfile` /
   `yarn install --frozen-lockfile`) and either pre-allow the `node_modules` tree or raise the
   threshold drastically for it.
2. Atomic pre/post-deletion test for `npm ci` (test-delete the parent; if it succeeds, batch the
   children; else abort atomically).
3. Add a `package_manager_safe: true` opt-in flag the shim/rules honor.
4. Make the bulk-guard error actionable: name the shim, the threshold, and the recovery step.

## ATTACHMENTS (in this repo)
- `bin/repro-all.ps1`, `bin/repro-npm-ci.ps1`, `bin/repro-node-delete.mjs` (repro)
- `npm-probe/package.json` + `package-lock.json` (synthetic fixture, bit-identical family)
- `report/results-npm-ci.txt`, `report/results-latest.txt` (structured records)
- `report/sanitized-evidence.md §A,§B,§E` (component snippets + repro results)
- `report/ENVIRONMENT-MODEL.md` (versions)

## STATUS
`REPRODUCED = YES · PRODUCT_CAUSE = CONFIRMED · COMPONENT_CAUSE = CONFIRMED`
