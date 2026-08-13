# WorkBuddy Root-Cause Closure Lab

A disposable, isolated probe environment used to investigate the safe-delete
and sandbox behavior of WorkBuddy (Tencent) without touching the real
production repository or any system state outside this lab and the user's
temporary directory.

**DO NOT** add real production files here. The lab is intended to be
disposable; `mavis-trash` is used throughout for clean removal.

## Layout

```
workbuddy-rootcause-lab/
├── bin/                                # PowerShell + Node probe scripts
│   ├── probe-shim.cjs                  # verifies Node shim is loaded
│   ├── repro-node-delete.mjs           # fs.rmSync small + large
│   ├── repro-all.ps1                   # runs Node + Git + npm probes
│   ├── run-bundle.ps1                  # single-mode runner
│   ├── build-fixture.ps1               # creates Node delete fixtures
│   ├── build-git-probe.ps1             # initializes git probe repo
│   ├── check-worktree.ps1              # verifies git worktree integrity
│   ├── run-git-cycles.ps1              # runs N switch cycles + ff merge
│   └── run-as-workbuddy.ps1            # sets WorkBuddy env vars for a child
├── node-delete-probe/                  # fixtures for fs.rmSync probe
│   ├── small/                          # 5 files (under bulk threshold)
│   └── large/                          # 40 files (over bulk threshold)
├── npm-probe/                          # parse5+entities fixture
│   ├── package.json
│   ├── package-lock.json
│   └── node_modules/                   # recreated by probes
├── git-probe-normal/                   # git probe, runs from a normal shell
├── git-probe-workbuddy/                # git probe, runs with shim env vars
├── git-probe-allow-rule/               # git probe, for the allow-rule test
└── report/                             # sanitized results
    ├── environment-summary.txt
    ├── sanitized-evidence.md
    ├── results-normal.txt
    ├── results-workbuddy.txt
    ├── results-allow-rule.txt
    ├── tsbx_rules.original.json        # sha256-pinned backup
    ├── BUG-REPORT-TENCENT.md
    └── ROOT_CAUSE_CLOSURE_REPORT.md
```

## How to reproduce

```powershell
# Build the lab (one-time, can be re-run safely)
cd D:\Dev\workbuddy-rootcause-lab
& bin\repro-all.ps1

# Then read the report files
cat report\results-normal.txt
cat report\results-workbuddy.txt
```

The lab probe is safe to re-run: the only destructive operations are
within `D:\Dev\workbuddy-rootcause-lab\` and `C:\Users\ssy\AppData\Local\Temp\workbuddy-rootcause-control\`.

## What this lab does NOT do

- It does **not** modify the real production repo at `D:\Dev\zhihu-grabber-toolkit\`.
- It does **not** modify `tsbx_rules.json` on the live system.
- It does **not** restart WorkBuddy.
- It does **not** download or install any new software.

## Safety notes

- The `run-as-workbuddy.ps1` wrapper refuses to invoke any command whose
  argument contains `D:\Dev\zhihu-grabber-toolkit`. The black-list is
  enforced at the script level.
- The bulk-guard state directory is `C:\Users\ssy\AppData\Local\Temp\workbuddy-rootcause-control\`. It is created with a random suffix per run to avoid state cross-contamination.
- The shim report file is also under `C:\Users\ssy\AppData\Local\Temp\workbuddy-rootcause-control\`.
