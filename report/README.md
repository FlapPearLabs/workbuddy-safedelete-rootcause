# WorkBuddy Root-Cause Closure Lab

> **HISTORICAL — internal lab README from the original investigation.**
> The canonical entry point is the repository **root `README.md`**; the
> canonical Bug B native procedure is `report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md`.
> The repository is `FlapPearLabs/workbuddy-safedelete-rootcause` (this
> file predates the rename from the working title `workbuddy-rootcause-lab`).

A disposable, isolated probe environment used to investigate the safe-delete
and sandbox behavior of WorkBuddy (Tencent) without touching the real
production repository or any system state outside this lab and the user's
temporary directory.

**DO NOT** add real production files here. The lab is intended to be
disposable; cleanup is performed by the repository-owned scoped helper
`Remove-OwnedProbePath` in `bin/_lib.ps1` (no external tools required).

## Layout

```
workbuddy-rootcause-lab/
├── bin/                                # PowerShell + Node probe scripts
│   ├── _lib.ps1                        # shared library (env, paths, manifest, worktree classifier, scoped cleanup)
│   ├── probe-shim.cjs                  # verifies Node shim is loaded
│   ├── repro-node-delete.mjs           # fs.rmSync small + large
│   ├── repro-npm-ci.ps1                # npm ci A/B with pre/post file manifest
│   ├── repro-all.ps1                   # runs all 5 phases in one click
│   ├── build-fixture.ps1               # creates Node delete fixtures
│   ├── build-git-probe.ps1             # initializes git probe repo (real branch delta)
│   ├── check-worktree.ps1              # verifies git worktree integrity per step
│   ├── run-git-cycles.ps1              # runs N switch cycles + ff merge
│   └── run-as-workbuddy.ps1            # sets WorkBuddy env vars for a child
├── npm-probe/                          # parse5+entities fixture (committed: package.json + lock)
│   ├── package.json
│   ├── package-lock.json
│   └── node_modules/                   # recreated by repro-npm-ci.ps1 (gitignored)
├── fixtures/                           # runtime-built probe fixtures (gitignored)
├── work/                               # per-run output dirs (gitignored)
└── report/                             # sanitized results
    ├── environment-summary.txt
    ├── sanitized-evidence.md
    ├── results-latest.txt
    ├── results-npm-ci.txt
    ├── results-git-normal.txt
    ├── results-git-shim-only.txt
    ├── results-allow-rule.txt
    ├── tsbx_rules.original.json        # sha256-pinned backup, paths redacted
    ├── BUG-REPORT-TENCENT.md           # 5-min read, 30-sec Issue A repro
    ├── ROOT_CAUSE_CLOSURE_REPORT.md    # closure summary + 4-class data-loss
    └── NEXT-WORKBUDDY-GIT-EXPERIMENT.md # Phase 1/2/3 native WorkBuddy procedure
```

## How to reproduce

```powershell
git clone https://github.com/FlapPearLabs/workbuddy-safedelete-rootcause <WORKSPACE>
cd <WORKSPACE>
powershell -ExecutionPolicy Bypass -File .\bin\repro-all.ps1
```

The lab probe is safe to re-run: the only destructive operations are
within the cloned repo root and the OS temp directory.

## What this lab does NOT do

- It does **not** modify the real production repo at `<PROD_REPO>`.
  The lab scripts hard-blacklist that path at the script level.
- It does **not** modify `tsbx_rules.json` on the live system.
- It does **not** restart WorkBuddy.
- It does **not** download or install any new software.

## Safety notes

- The `run-as-workbuddy.ps1` wrapper refuses to invoke any command whose
  argument contains the real production repo path. The blacklist is
  enforced at the script level.
- The bulk-guard state directory is `<USER_PROFILE>\AppData\Local\Temp\workbuddy-rootcause-control\`.
  It is created with a random suffix per run to avoid state cross-contamination.
- The shim report file is also under the same temp directory.
- All probe fixtures and runtime state are gitignored. The lab rebuilds
  them on every run from the committed scripts.
