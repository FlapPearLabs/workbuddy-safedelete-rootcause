# WorkBuddy safe-delete / tsbx sandbox — root-cause investigation

A self-contained investigation of two WorkBuddy (Tencent) filesystem issues
observed in a Windows dev environment (5.3.11 / 5.3.13). **Bug A has a
one-click deterministic repro. Bug B has a native WorkBuddy reproduction
harness and a confirmed R1 reproduction, but is intermittent across the
observed native runs.**

- **Issue A** — `npm ci` is **aborted partway** by the safe-delete bulk-guard,
  leaving `node_modules` in a half-deleted state. **Directly reproduced in
  this repo's disposable lab** with a `parse5@8.0.1` + `entities@8.0.0`
  fixture identical to the real affected project. The shim report captured
  by the lab probe proves partial mutation: `.package-lock.json` is silently
  trashed **before** the bulk-guard fires on the bigger batch.
- **Issue B** — tracked Git worktree files disappear after `git switch` /
  `git merge` while HEAD / index / blob remain intact. The lab A/B probe
  rules out the Node shim as the cause (11/11 per-step
  `WORKTREE_CHECK_VERDICT=CLEAN` in both NORMAL and SHIM-ONLY modes with
  a real branch delta). `tsbx.dll` is present in the WorkBuddy sandbox
  distribution and is a HIGH_CONFIDENCE_HYPOTHESIS for Bug B. Its exact
  attachment/interception behavior relevant to the Git anomaly was not
  directly traced. **A native WorkBuddy run (R1) reproduced
  the worktree-only loss (59 unrelated tracked files)** using the
  F1-shape harness (`bin/build-git-probe-f1-shape.ps1`, 160 tracked files /
  3-path FF delta); a follow-up controlled four-checkpoint run (R2) was
  clean in that one shot, so the anomaly is **intermittent across observed
  native runs** with the component cause still unresolved. Full native
  evidence and confidence boundaries are in
  [`report/EXECUTIVE-SUMMARY.md`](report/EXECUTIVE-SUMMARY.md) and
  [`report/BUG-B-GIT-WORKTREE-LOSS.md`](report/BUG-B-GIT-WORKTREE-LOSS.md).

## Prerequisites

- **OS:** Windows 10/11 (NTFS). The scripts are Windows PowerShell 5.1+.
- **PowerShell** (`powershell`) on PATH.
- **Git** on PATH (the Git A/B control and Bug B harness invoke `git.exe`).
- **Node.js + npm** on PATH (Bug A fixture install: `npm install` / `npm ci`).
- **Network access to the npm registry** — Bug A Phase 1/2 fetches
  `parse5@8.0.1` + `entities@8.0.0` from the registry.
- **A normal WorkBuddy installation.** WorkBuddy 5.3.11 and 5.3.13 were
  observed/tested during this investigation; behavior on other versions
  may differ. Required for the SHIM phases of Bug A and for the Bug B
  native flow. `bin/repro-all.ps1` auto-discovers the install; pass
  `-WorkbuddyInstall` if it is not found.
- **Real WorkBuddy-native context** is required for the Bug B native run —
  Bug B native reproduction requires the WorkBuddy-native execution context
  observed in the R1/R2 runs. See `report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md`.
- **Clone to a NON-TEMP, writable path.** The shim deliberately skips
  operations on `os.tmpdir()` paths (`genie-safe-delete.cjs`
  `shouldUseNativeDelete`), so cloning to `%TEMP%` will not reproduce the
  shim's behavior.

## Quick repro (30 seconds for Issue A)

```powershell
# IMPORTANT: clone to a NON-TEMP writable path (any drive; do not assume D:
# exists). The shim deliberately skips operations on os.tmpdir() paths, so
# cloning to %TEMP% will not reproduce the shim's behavior.
$repo = Join-Path $env:USERPROFILE 'workbuddy-safedelete-rootcause'
git clone https://github.com/FlapPearLabs/workbuddy-safedelete-rootcause $repo
cd $repo
powershell -ExecutionPolicy Bypass -File .\bin\repro-all.ps1
```

The orchestrator runs five phases and writes the structured output to
`work\repro-run-<timestamp>\results.txt` (or the dir passed via
`-OutputDir <path>`). The expected key lines are:

```
PHASE1A NORMAL small: STILL_EXISTS_AFTER=false EXIT_CODE=0
PHASE1B NORMAL large: STILL_EXISTS_AFTER=false EXIT_CODE=0
PHASE1C SHIM   small: STILL_EXISTS_AFTER=false EXIT_CODE=0
PHASE1D SHIM   large: THROWN=... SAFE_DELETE_BULK_CONFIRM_REQUIRED EXIT_CODE=1
PHASE2 NPM_CI_PHASE1_CI_EXIT=0   NPM_CI_PHASE1_CI_OUTPUT_HEAD=added 2 packages
PHASE2 NPM_CI_PHASE2_CI_EXIT=1   NPM_CI_PHASE2_BULK_GUARD_TRIGGERED=yes
PHASE2 NPM_CI_PHASE2_SHIM_TRASH_EVENT <ts> op=trash runtime=node path=...\node_modules\.package-lock.json
PHASE3A BUILD BRANCH_DELTA_VALID=YES
PHASE3A 11x WORKTREE_CHECK_VERDICT=CLEAN
PHASE3B 11x WORKTREE_CHECK_VERDICT=CLEAN
PHASE4_RESULT=NOT_EXECUTED_REQUIRES_WORKBUDDY_PARENT
```

The SHIM phases (PHASE1C/1D, PHASE2 SHIM, PHASE3B) require a WorkBuddy
install to be present; without one they are skipped with
`*_SKIPPED_WORKBUDDY_NOT_INSTALLED` markers.

| Quick verdict | | |
|---|---|---|
| `ISSUE_A_NODE_DELETE` | NORMAL=PASS | WORKBUDDY_SHIM=BLOCKED |
| `ISSUE_A_NPM_CI` | NORMAL_EXIT=0 | WORKBUDDY_SHIM_EXIT=1, BULK_GUARD_TRIGGERED=YES |
| `ISSUE_B_GIT_NORMAL` | LOSS=NO (11/11 CLEAN) | |
| `ISSUE_B_GIT_SHIM_ONLY` | LOSS=NO (11/11 CLEAN) | |
| `ISSUE_B_GIT_FULL_SANDBOX` | **R1 REPRODUCED** (59-file worktree-only loss, F1-shape harness) | **R2 one-shot CLEAN** (intermittent; `GIT_COMPONENT_CAUSE=UNRESOLVED`) |

## Where to start (read in this order)

> Start with [`report/EXECUTIVE-SUMMARY.md`](report/EXECUTIVE-SUMMARY.md) for
> the two-bug overview and confidence boundaries, then the master reconciliation
> in [`report/MASTER-INVESTIGATION-LEDGER.md`](report/MASTER-INVESTIGATION-LEDGER.md).

1. **[`report/BUG-A-NPM-SAFE-DELETE.md`](report/BUG-A-NPM-SAFE-DELETE.md)** —
   the standalone Bug A vendor report (component-confirmed, 30-second
   repro, no PII, no real production source).
2. **[`report/BUG-B-GIT-WORKTREE-LOSS.md`](report/BUG-B-GIT-WORKTREE-LOSS.md)** —
   the standalone Bug B vendor report (phenomenon confirmed, component
   cause unresolved; primary public evidence in `report/NATIVE-R1-EVIDENCE.md`
   / `report/NATIVE-R2-EVIDENCE.md`).
3. **[`report/ROOT_CAUSE_CLOSURE_REPORT.md`](report/ROOT_CAUSE_CLOSURE_REPORT.md)**
   — the closure summary (4-class data-loss analysis, layering summary,
   privacy / proprietary content audit).
4. **[`report/sanitized-evidence.md`](report/sanitized-evidence.md)** — the
   full evidence pack: source code line numbers, `tsbx_rules.json` content
   (paths redacted in the published copy), binary string evidence, audit
   log quotes, and the shim report capture that proves partial mutation.
5. **[`report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md`](report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md)**
   — the complete, copy-pasteable procedure for running the Bug B native
   F1-shape probe from inside a real WorkBuddy tool-call. Has 3 phases
   (baseline, allow-rule A/B, optional ETW / ProcMon) plus the deterministic
   offline validation gate.

## Supporting artifacts

- **[`report/environment-summary.txt`](report/environment-summary.txt)** —
  WorkBuddy version, file SHAs, tsbx rule summary (historical capture).
- **[`report/results-latest.txt`](report/results-latest.txt)** —
  **HISTORICAL EVIDENCE** — full orchestrator output of the last pre-repair
  lab run (uses `<WORKSPACE>` placeholders; produced by the old harness).
- **[`report/results-npm-ci.txt`](report/results-npm-ci.txt)** —
  **HISTORICAL EVIDENCE** — npm ci A/B structured records (Phase 1 + Phase 2).
- **[`report/results-git-normal.txt`](report/results-git-normal.txt)** —
  **HISTORICAL EVIDENCE** — Git A/B NORMAL mode records (5 cycles + 1 merge =
  11 per-step checks; legacy record schema, retained as-is).
- **[`report/results-git-shim-only.txt`](report/results-git-shim-only.txt)** —
  **HISTORICAL EVIDENCE** — Git A/B SHIM-ONLY mode records (legacy schema).
- **[`report/tsbx_rules.original.json`](report/tsbx_rules.original.json)** —
  the **sanitized published copy** of the rules file. Hash provenance (see
  `report/ENVIRONMENT-MODEL.md` §3):
  - `ORIGINAL_LOCAL_SHA256 = 30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A`
    (verified 2026-08-15 against the raw shipped bytes in the author's
    WorkBuddy install; raw bytes are CRLF).
  - `PUBLIC_SANITIZED_TSBX_SHA256 = 121c8e05805f6fec831a737dbe71c00d471dd85196b55cd89df94cb3bf68f8f2`
    (the committed file; pinned byte-for-byte via `.gitattributes -text`).
  - `PUBLIC_COPY_BYTE_IDENTICAL_TO_ORIGINAL = NO` — the published copy
    redacts the WorkBuddy companion-app install paths
    (`C:\openclaw\openclaw\**`, `D:\openclaw\proxy-agent\**`) to
    `<OPENCLAW_INSTALL>` placeholders. Do not compare the two SHA256 values.
- **[`report/results-allow-rule.txt`](report/results-allow-rule.txt)** — the
  procedure for the proposed allow-rule empirical test (not executed in
  this round; requires a controlled WorkBuddy restart, see
  `NEXT-WORKBUDDY-GIT-EXPERIMENT.md`).

## Probe scripts

In `bin/`:

- `repro-all.ps1` — master orchestrator (5 phases: env probe, Node fs.rmSync
  A/B, npm ci A/B, Git A/B, WorkBuddy NATIVE = NOT_EXECUTED).
- `repro-npm-ci.ps1` — npm ci A/B with pre/post file manifest diff and
  shim report capture (the smoking gun for partial mutation).
- `repro-node-delete.mjs` — Node `fs.rmSync` A/B (small 5 files vs large
  40 files).
- **`build-git-probe-f1-shape.ps1` — the AUTHORITATIVE Bug B native
  harness** (160 tracked files, 60 test-like, tiny 3-path FF delta, 4
  physical checkpoints A/B/C/D). This is the shape of the successful R1
  reproduction and of the F1 natural incident. Use this for the Bug B
  native flow (see `report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md`).
- `build-git-probe.ps1` — **HISTORICAL / AUXILIARY STRESS PROBE** for Bug B
  (60 tracked files, 46 modified / 5 deleted / 16 added / 4 renamed). It is
  the negative-control fixture for the Bug A Git A/B phases in
  `repro-all.ps1`; it is NOT the authoritative Bug B native reproduction
  shape and must not be used as such.
- `check-worktree.ps1` — per-step worktree integrity classifier (emits
  `WORKTREE_CHECK_VERDICT` + per-class counts).
- `run-git-cycles.ps1` — runs the switch/merge workload
  (5 switch cycles + 1 merge = 11 mutation checks + 1 pre-op baseline).
- `classify-run.ps1` — deterministic result classifier for a
  `run-git-cycles.ps1` results file (distinguishes CLEAN /
  WORKTREE_ONLY_LOSS / WORKTREE_CONTENT_DIVERGENCE /
  PREEXISTING_NON_CLEAN / GIT_OPERATION_INTERFERENCE /
  INSTRUMENTATION_ERROR / CHECKER_ERROR / NONZERO_GIT_EXIT /
  TARGET_NOT_REACHED).
- `build-fixture.ps1` — creates the small/large Node delete fixtures.
- `run-as-workbuddy.ps1` — sets the WorkBuddy env vars and invokes a
  child command (auto-discovers the WorkBuddy install). Refuses to run any
  command that targets the real production project (script-level
  blacklist).
- `probe-shim.cjs` — verifies whether the Node shim is loaded in the env.
- `_lib.ps1` — shared library (env, paths, manifest, worktree classifier,
  `Remove-OwnedProbePath` scoped cleanup).
- `test-owned-path-delete.ps1` / `test-classify-run.ps1` /
  `test-tsbx-lab-rule.ps1` / `test-outcome-parser.ps1` /
  `test-attribution-preop.ps1` — deterministic offline tests (no native
  sandbox required; see `FINAL VALIDATION` in the experiment doc).

## Probe fixtures

In `npm-probe/`:

- `package.json` + `package-lock.json` — the same `parse5@8.0.1` +
  `entities@8.0.0` content as the real affected project. Committed so
  the lockfile is bit-identical to the user's working project.
- `node_modules/` — **gitignored**, recreated by `repro-npm-ci.ps1` from
  the committed lockfile on every fresh run.

Runtime-built probe fixtures (in `fixtures/`, also gitignored):
- `node-delete/{small,large}/` — built by `build-fixture.ps1`.
- `git-probe-{normal,shim}/` — built by `build-git-probe.ps1`.

## Privacy / proprietary content

- **No real production source files** in this repo. The quoted snippets
  in `sanitized-evidence.md` are limited to under 30 lines per file
  from `genie-safe-delete.cjs` and `safe-delete-bulk-guard.cjs`, with
  SHA256 fingerprints so the receiving team can compare against the
  binary they ship.
- **No credentials, no API keys, no tokens, no cookies, no passwords.**
  The lab scripts hard-blacklist the real production repo path.
- **No Windows user-profile paths.** All `C:\Users\<user>\` references
  in this repo's documents are replaced with `<USER_PROFILE>`.
- **No `<WORKSPACE>\` paths** in this repo's documents.
  The lab root is replaced with `<WORKSPACE>` (the actual path is
  auto-resolved by `bin/_lib.ps1` from the script's own location).
- **No `<WORKBUDDY_INSTALL>\openclaw\**` paths** in the published
  `tsbx_rules.original.json`. The WorkBuddy companion app paths are
  redacted to a `_comment` saying "path redacted in published copy".
- **No force-rewriting of Git history.** The prior commits contained
  disposable probe sub-repos as gitlinks; those have been removed via
  `git rm` and the new commits continue from the same parent. The
  published tree is clean from the new commits forward.

The historical Git metadata may contain the repository author's public
Git identity. This is the user's public commit author, not a credential.

## Recommended bug report structure

We recommend filing as **two linked bugs** because Bug A has a confirmed
component layer while Bug B remains unresolved, even though both sit within
WorkBuddy's safe-delete / sandbox stack:

- **Bug A** — `safe-delete` Node shim + bulk-guard (owner: WorkBuddy
  `safe-delete` team). Concrete, repro'd in the lab, has a 30-second
  repro.
- **Bug B** — WorkBuddy native sandbox/filesystem behavior (specific
  component unresolved; `tsbx.dll` is a HIGH_CONFIDENCE_HYPOTHESIS).
  Phenomenon confirmed by native R1 reproduction + 5+ real-world events;
  component cause unresolved; stand-alone report in
  `report/BUG-B-GIT-WORKTREE-LOSS.md`, future diagnostics in
  `report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md`.

An umbrella bug that links both is acceptable if the team prefers a
single routing ID, but the two issues should be tracked as distinct
sub-issues so each owner can address their own layer.

## Severity

- **Bug A: MEDIUM.** Affects routine `npm ci`. The failure is not silent
  (stderr has the bulk-guard error), but the partial mutation that
  precedes the abort is. Workaround is straightforward: run `npm ci`
  from a non-WorkBuddy shell. Impact is on dev workflow, not on
  production data.
- **Bug B: MEDIUM, with VERY_HIGH runtime association and an UNRESOLVED
  component cause.** Real-world audit log shows 5+ events across 4 days; a
  native WorkBuddy run (R1) reproduced the worktree-only loss (59 files),
  and a controlled R2 four-checkpoint run was clean in that one shot —
  i.e. intermittent across observed native runs, component cause still
  open (`GIT_COMPONENT_CAUSE=UNRESOLVED`, `TSBX_FILTER_CAUSE=HIGH_CONFIDENCE_HYPOTHESIS`).
  Severity should be reassessed if a direct component-level filesystem
  trace demonstrates the mutation mechanism or if permanent user-data loss
  is observed (FUTURE_DIAGNOSTIC_IF_VENDOR_REQUESTS).

## Layering summary (Experiment 8)

| Layer | Intercepts | Affects | Reproduced in lab? |
|---|---|---|---|
| Node shim (`genie-safe-delete.cjs`) | `fs.unlinkSync` / `fs.rmSync` / etc. in Node processes with `CODEBUDDY_SESSION_ID` set | All Node processes spawned by WorkBuddy (test code, npm itself) | **YES** (Issue A directly reproduced) |
| Shell shim (`safe-bin/{rm,rmdir,unlink}`) | `rm` / `rmdir` / `unlink` in shell sessions | All bash / sh processes spawned by WorkBuddy | NOT TESTED |
| Candidate native sandbox/filesystem component (`tsbx.dll` + `tsbx_rules.json`) | Observed: artifacts/rules are present in the WorkBuddy sandbox distribution; native R1 reproduced the phenomenon. | Inferred / unresolved: exact process attachment, interception coverage, and causal role. | HIGH_CONFIDENCE_HYPOTHESIS for Bug B; COMPONENT_CAUSE=UNRESOLVED |

Issue A only needs the Node shim to manifest. Issue B is strongly associated with
the WorkBuddy-native execution environment; `tsbx.dll` remains a
high-confidence component hypothesis. The two issues must not be conflated:
Issue A is component-confirmed (Node shim + 20-delete bulk-guard); Issue B's
cause is a HIGH_CONFIDENCE_HYPOTHESIS with an unresolved component cause, and the
20-delete threshold does not apply to it.

## Safety

- The lab is **read-only** against the real production repo.
- The lab does **not** modify the live `tsbx_rules.json`.
- The lab does **not** restart WorkBuddy.
- The lab does **not** download or install any new software.
- All deletions are confined to the cloned repo root and
  `<USER_PROFILE>\AppData\Local\Temp\workbuddy-rootcause-control\`.
