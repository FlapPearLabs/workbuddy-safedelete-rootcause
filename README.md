# WorkBuddy safe-delete / tsbx sandbox — root-cause investigation

A self-contained, **one-click** reproducible investigation of two issues
observed in a Windows dev environment running WorkBuddy (Tencent) 5.3.11:

- **Issue A** — `npm ci` is **aborted partway** by the safe-delete bulk-guard,
  leaving `node_modules` in a half-deleted state. **Directly reproduced in
  this repo's disposable lab** with a `parse5@8.0.1` + `entities@8.0.0`
  fixture identical to the real affected project. The shim report captured
  by the lab probe proves partial mutation: `.package-lock.json` is silently
  trashed **before** the bulk-guard fires on the bigger batch.
- **Issue B** — tracked Git worktree files disappear after `git switch` /
  `git merge` while HEAD / index / blob remain intact. The Mavis lab probe
  conclusively rules out the Node shim as the cause (11/11 per-step
  `WORKTREE_CHECK_VERDICT=CLEAN` in both NORMAL and SHIM-ONLY modes with
  a real branch delta). The remaining candidate is the `tsbx.dll` kernel
  filter, which is only loaded into processes spawned by `sandbox-cli.exe`
  inside a real WorkBuddy session. **A native WorkBuddy run (R1) reproduced
  the worktree-only loss (59 unrelated tracked files)**; a follow-up
  controlled four-checkpoint run (R2) was clean in that one shot, so the
  anomaly is **intermittent across observed native runs** with the component
  cause still unresolved. Full native evidence and confidence boundaries are
  in [`report/EXECUTIVE-SUMMARY.md`](report/EXECUTIVE-SUMMARY.md) and
  [`report/BUG-B-GIT-WORKTREE-LOSS.md`](report/BUG-B-GIT-WORKTREE-LOSS.md).

## Quick repro (30 seconds for Issue A)

```powershell
# IMPORTANT: clone to a non-temp path. The shim deliberately skips
# operations on os.tmpdir() paths (see genie-safe-delete.cjs
# shouldUseNativeDelete), so cloning to %TEMP% will not reproduce
# the shim's behavior.
git clone https://github.com/FlapPearLabs/workbuddy-safedelete-rootcause D:\workbuddy-safedelete-rootcause
cd D:\workbuddy-safedelete-rootcause
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

| Quick verdict | | |
|---|---|---|
| `ISSUE_A_NODE_DELETE` | NORMAL=PASS | WORKBUDDY_SHIM=BLOCKED |
| `ISSUE_A_NPM_CI` | NORMAL_EXIT=0 | WORKBUDDY_SHIM_EXIT=1, BULK_GUARD_TRIGGERED=YES |
| `ISSUE_B_GIT_NORMAL` | LOSS=NO (11/11 CLEAN) | |
| `ISSUE_B_GIT_SHIM_ONLY` | LOSS=NO (11/11 CLEAN) | |
| `ISSUE_B_GIT_FULL_SANDBOX` | **R1 REPRODUCED** (59-file worktree-only loss) | **R2 one-shot CLEAN** (intermittent; `GIT_COMPONENT_CAUSE=UNRESOLVED`) |

## Where to start (read in this order)

> Start with [`report/EXECUTIVE-SUMMARY.md`](report/EXECUTIVE-SUMMARY.md) for
> the two-bug overview and confidence boundaries, then the master reconciliation
> in [`report/MASTER-INVESTIGATION-LEDGER.md`](report/MASTER-INVESTIGATION-LEDGER.md).

1. **[`report/BUG-REPORT-TENCENT.md`](report/BUG-REPORT-TENCENT.md)** — the
   submission-ready bug report (5-minute read, 30-second Issue A repro,
   no PII, no real production source).
2. **[`report/ROOT_CAUSE_CLOSURE_REPORT.md`](report/ROOT_CAUSE_CLOSURE_REPORT.md)**
   — the closure summary (4-class data-loss analysis, layering summary,
   privacy / proprietary content audit).
3. **[`report/sanitized-evidence.md`](report/sanitized-evidence.md)** — the
   full evidence pack: source code line numbers, `tsbx_rules.json` content
   (paths redacted in the published copy), binary string evidence, audit
   log quotes, and the shim report capture that proves partial mutation.
4. **[`report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md`](report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md)**
   — the complete, copy-pasteable procedure for running the Git probe from
   inside a real WorkBuddy tool-call. Has 3 phases (baseline, allow-rule
   A/B, optional ETW / ProcMon).

## Supporting artifacts

- **[`report/environment-summary.txt`](report/environment-summary.txt)** —
  WorkBuddy version, file SHAs, tsbx rule summary.
- **[`report/results-latest.txt`](report/results-latest.txt)** — the full
  orchestrator output from the last lab run.
- **[`report/results-npm-ci.txt`](report/results-npm-ci.txt)** — npm ci
  A/B structured records (Phase 1 + Phase 2).
- **[`report/results-git-normal.txt`](report/results-git-normal.txt)** —
  Git A/B NORMAL mode records (5 cycles + 1 merge = 11 per-step checks).
- **[`report/results-git-shim-only.txt`](report/results-git-shim-only.txt)** —
  Git A/B SHIM-ONLY mode records.
- **[`report/tsbx_rules.original.json`](report/tsbx_rules.original.json)** —
  unmodified backup of the rules file (sha256
  `30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A`,
  paths redacted for the WorkBuddy companion app in the published copy).
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
- `build-git-probe.ps1` / `check-worktree.ps1` / `run-git-cycles.ps1` —
  disposable git repo with 60 tracked files on master, feature branch
  with 46 modified / 5 deleted / 16 added / 4 renamed; verifies
  worktree integrity after every step.
- `build-fixture.ps1` — creates the small/large Node delete fixtures.
- `run-as-workbuddy.ps1` — sets the WorkBuddy env vars and invokes a
  child command. Refuses to run any command that targets the real
  production project (script-level blacklist).
- `probe-shim.cjs` — verifies whether the Node shim is loaded in the env.
- `_lib.ps1` — shared library (env, paths, manifest, worktree classifier).

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

We recommend filing as **two linked bugs** because the two issues have
**different root-cause layers** even though they share the same
product-level philosophy (deny-by-default + 20-default threshold):

- **Bug A** — `safe-delete` Node shim + bulk-guard (owner: WorkBuddy
  `safe-delete` team). Concrete, repro'd in the lab, has a 30-second
  repro.
- **Bug B** — `tsbx` kernel sandbox (owner: WorkBuddy `sandbox` team).
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
  Severity can be upgraded to **HIGH** if ETW / ProcMon captures the
  kernel-filter denials directly (FUTURE_DIAGNOSTIC_IF_VENDOR_REQUESTS).

## Layering summary (Experiment 8)

| Layer | Intercepts | Affects | Reproduced in lab? |
|---|---|---|---|
| Node shim (`genie-safe-delete.cjs`) | `fs.unlinkSync` / `fs.rmSync` / etc. in Node processes with `CODEBUDDY_SESSION_ID` set | All Node processes spawned by WorkBuddy (test code, npm itself) | **YES** (Issue A directly reproduced) |
| Shell shim (`safe-bin/{rm,rmdir,unlink}`) | `rm` / `rmdir` / `unlink` in shell sessions | All bash / sh processes spawned by WorkBuddy | NOT TESTED |
| Kernel filter (`tsbx.dll` + `tsbx_rules.json`) | All file system operations at the IRP level for any process whose handle is associated with the filter | All processes spawned by WorkBuddy (git.exe, node.exe, npm.cmd, etc.) | NOT REPRODUCED in Mavis; **HIGH_CONFIDENCE_INFERENCE for Issue B** |

Issue A only needs the Node shim to manifest. Issue B requires the kernel
filter. The two issues share the same product-level root cause
(WorkBuddy's deny-by-default + threshold=20 default) but live in different
layers of the safe-delete / sandbox stack.

## Safety

- The lab is **read-only** against the real production repo.
- The lab does **not** modify the live `tsbx_rules.json`.
- The lab does **not** restart WorkBuddy.
- The lab does **not** download or install any new software.
- All deletions are confined to the cloned repo root and
  `<USER_PROFILE>\AppData\Local\Temp\workbuddy-rootcause-control\`.
