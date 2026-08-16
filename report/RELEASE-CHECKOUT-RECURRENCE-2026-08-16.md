# Native Worktree-Loss Recurrence During Release Checkout — 2026-08-16

This is the sanitized public derivative of a release-stage WorkBuddy-native incident. Machine-specific raw logs remain local and gitignored.

## What happened

During a **real release-stage workflow** (not a synthetic reproduction), the command

```text
git checkout master
```

returned **exit code 0**. Immediately afterward, **6 tracked paths were physically absent from the working tree**, even though all six remained present in the target commit tree and the index.

This is another observation of the `WORKTREE_ONLY_LOSS` class documented as Bug B. It occurred in a WorkBuddy-native agent execution context. The exact responsible WorkBuddy component remains unresolved.

## Affected tracked paths

The six missing paths were unrelated to the release commit's content change (that release commit modified only `README.md`):

- `bin/build-fixture.ps1`
- `bin/check-worktree.ps1`
- `bin/probe-shim.cjs`
- `bin/repro-node-delete.mjs`
- `bin/run-bundle.ps1`
- `bin/test-attribution-preop.ps1`

## Post-event integrity checks

| Check | Result |
| --- | --- |
| Present in target `HEAD` tree | YES — all 6 paths resolvable |
| Present in index (`git ls-files -s`) | YES — all 6 entries intact |
| Blobs readable (`git cat-file -e` / `rev-parse`) | YES — all 6 blob SHAs resolved |
| Physically present on disk | NO — all 6 files absent |
| `git write-tree` == `HEAD^{tree}` | YES |
| `git fsck --no-reflogs` | exit 0; no repository corruption |

The fsck output contained only a dangling commit unrelated to this event.

## Merge state

- `git merge` had **not** started when the loss was detected.
- `.git/MERGE_HEAD`, `.git/CHERRY_PICK_HEAD`, and `.git/REBASE_HEAD` were absent.
- No merge commit, rebase, reset, clean, stash, or force operation was performed in the causal interval.

## Causal interval

The observed CLEAN/physical-loss transition is localized to the **`git checkout master` interval**: the six files were found absent immediately after that command returned exit code 0, with no intervening mutation.

This localizes the observed event interval; it does **not** identify the WorkBuddy component responsible.

## Causal attribution — deliberately bounded

- `BUG_B_PHENOMENON_CONFIRMED = YES`
- `WORKBUDDY_RUNTIME_ASSOCIATION = VERY_HIGH`
- `PRODUCT_CAUSE = UNRESOLVED`
- `COMPONENT_CAUSE = UNRESOLVED`
- `TSBX_FILTER_CAUSE = HIGH_CONFIDENCE_HYPOTHESIS`

The `tsbx` filter remains a hypothesis, not a confirmed cause. No kernel-filter attachment state is claimed by this evidence.

## Release identifiers

- Release branch: `docs/vendor-handoff-final`
- Release commit: `875353ecc8d256e93e229945bb809641665a2449`
- Local `master` ref / checkout target at the event: `4243b04596e8073408c45e750a899db04328092c`
- Base repro commit: `a26699a4fcb98e50fa3f26430e576bcef7436bf5`
- Remote `master` at evidence capture: `875353ecc8d256e93e229945bb809641665a2449`
- Remote release branch at evidence capture: `875353ecc8d256e93e229945bb809641665a2449`

The remote `master` was advanced externally after the local STOP and before evidence capture. That remote fast-forward did not repair or alter the preserved local worktree-loss state.

## Evidence retention

Raw machine-specific evidence is retained locally under the gitignored `work/` evidence area and is **not published**. The local set includes status, refs, index/tree checks, blob checks, physical-path checks, fsck output, merge-state checks, native-context evidence, and an event summary.

The raw evidence set is pinned by a local `SHA256SUMS.txt` manifest. The SHA256 of that manifest is:

```text
4803a62bed0f824d855ca54add13d732cc2dcaaaa4d7cd9279d9a30308510e5f
```

This public document is a sanitized derivative. The raw local evidence remains the byte-level source of truth.
