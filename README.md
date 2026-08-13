# WorkBuddy safe-delete / tsbx sandbox — root-cause investigation

Repro bundle for the following two issues observed in a Windows dev environment
running WorkBuddy (Tencent) 5.3.11:

- **A.** `npm ci` is silently aborted by the safe-delete bulk-guard, leaving
  `node_modules` in a half-deleted state. Directly reproduced in a disposable
  lab.
- **B.** Tracked Git worktree files disappear after `git switch` / `git merge`,
  while HEAD / index / blob remain intact. Strongly inferred (not directly
  reproducible from outside the WorkBuddy sandbox) to be caused by the
  `tsbx.dll` kernel filter denying operations on the dev workspace.

## Where to start

Read these in order:

1. [`report/BUG-REPORT-TENCENT.md`](report/BUG-REPORT-TENCENT.md) — the
   submission-ready bug report (sanitized, no PII, no real production paths).
2. [`report/ROOT_CAUSE_CLOSURE_REPORT.md`](report/ROOT_CAUSE_CLOSURE_REPORT.md)
   — the closure summary (what was proven, what was inferred, what is open).
3. [`report/sanitized-evidence.md`](report/sanitized-evidence.md) — the full
   evidence pack: source code line numbers, `tsbx_rules.json` content,
   binary string evidence, audit log quotes.

## Supporting artifacts

- [`report/environment-summary.txt`](report/environment-summary.txt) —
  WorkBuddy version, file shas, tsbx rule summary.
- [`report/results-normal.txt`](report/results-normal.txt) — lab probe
  output, normal shell.
- [`report/results-workbuddy.txt`](report/results-workbuddy.txt) — lab probe
  output, workbuddy-sim shell (env vars + shim).
- [`report/results-allow-rule.txt`](report/results-allow-rule.txt) — the
  procedure for the proposed allow-rule empirical test (not executed in
  this round; requires a controlled WorkBuddy restart).
- [`report/tsbx_rules.original.json`](report/tsbx_rules.original.json) —
  unmodified backup of the rules file (sha256
  `30A07E5FB92AD06D7EFD3A0DA7F1AA796CBDF3C3517EF1D70C8FA1E658B9A45A`).

## Reproduction scripts

In `bin/`:

- `repro-all.ps1` — runs the full Node + Git + npm probes in both modes.
- `run-as-workbuddy.ps1` — sets the WorkBuddy env vars and invokes a child
  command. Refuses to run any command that targets the real production
  project.
- `repro-node-delete.mjs` — runs `fs.rmSync` on small/large fixtures.
- `build-git-probe.ps1` / `check-worktree.ps1` / `run-git-cycles.ps1` —
  disposable git repo with 50 tracked files; verifies worktree integrity.
- `build-fixture.ps1` — creates the Node delete fixtures.

## Probe fixtures

In `npm-probe/`, `node-delete-probe/`, `git-probe-*/`:

- `npm-probe/package.json` + `package-lock.json` — the same `parse5@8.0.1`
  + `entities@8.0.0` content as the real affected project.
- `node-delete-probe/small/` — 5 files (under bulk threshold).
- `node-delete-probe/large/` — 40 files (over bulk threshold).
- `git-probe-normal/` — 50 tracked files, master + feature branch.
- `git-probe-workbuddy/` — same, for the workbuddy-sim probe.
- `git-probe-allow-rule/` — same, reserved for the proposed allow-rule
  test (not yet executed).

## Safety

- The lab is **read-only** against the real production repo.
- The lab does **not** modify the live `tsbx_rules.json`.
- The lab does **not** restart WorkBuddy.
- The lab does **not** download or install any new software.
- All deletions are confined to `D:\Dev\workbuddy-rootcause-lab\` and
  `C:\Users\ssy\AppData\Local\Temp\workbuddy-rootcause-control\`.

## Layering summary (from Experiment 8)

WorkBuddy's safe-delete / sandbox has three layers, each affecting different
operations:

| Layer | Intercepts | Affects | Reproduced in lab? |
|---|---|---|---|
| Node shim (`genie-safe-delete.cjs`) | `fs.unlinkSync` / `fs.rmSync` / etc. in Node processes with `CODEBUDDY_SESSION_ID` set | All Node processes spawned by WorkBuddy (test code, npm itself) | **YES** (Issue A directly reproduced) |
| Shell shim (`safe-bin/{rm,rmdir,unlink}`) | `rm` / `rmdir` / `unlink` in shell sessions | All bash / sh processes spawned by WorkBuddy | NOT TESTED |
| Kernel filter (`tsbx.dll` + `tsbx_rules.json`) | All file system operations at the IRP level for any process whose handle is associated with the filter | All processes spawned by WorkBuddy (git.exe, node.exe, npm.cmd, etc.) | NOT REPRODUCED in Mavis; **HIGH-CONFIDENCE INFERENCE for Issue B** |

Issue A only needs the Node shim to manifest. Issue B requires the kernel
filter. The two issues share the same product-level root cause
(WorkBuddy's deny-by-default + threshold=20 default) but live in different
layers of the safe-delete / sandbox stack.
