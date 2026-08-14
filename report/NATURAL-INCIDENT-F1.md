# NATURAL INCIDENT F1 — worktree disappearance after `git merge --ff-only`

**Repository:** `FlapPearLabs/zhihu-grabber-toolkit`
**Incident date (UTC):** 2026-08-14 (natural recurrence)
**Document date:** 2026-08-14
**Status:** INGESTED. **No production source content is copied here.** All
path references use the placeholder `<PROD_REPO>` to identify the
project without leaking its full path.

This document records a natural recurrence of the worktree file loss
anomaly that the user has been tracking since 2026-08-10. The
recurrence was triggered by a normal `git merge --ff-only` on the
production repository. The merge delta itself was tiny (3 files);
the worktree disappearance was broad (18 test files). The two
observations are inconsistent with Git alone, and the investigation
narrows the search space to WorkBuddy runtime components without
claiming a specific cause.

---

## INCIDENT

The user ran a normal fast-forward merge in the production
repository:

```
git checkout master
git merge --ff-only <feature-tip-sha>
```

The merge succeeded. Immediately afterward, 18 existing tracked files
under `<PROD_REPO>/zhihu-answer-grabber/test/` were physically
absent from the worktree. `git status` showed them as `D` (deleted in
worktree, present in index). The Git object database was intact
(HEAD, index, blob, fsck all healthy; remote GitHub shows the same
commits).

The user recovered the files non-destructively:

```
git restore --worktree -- zhihu-answer-grabber/test/
```

This restored all 18 files without:
- `git reset`
- `git clean`
- `git stash`
- history rewrite
- a new recovery commit

The recovery is the standard, non-destructive WorkBuddy-side
workaround that the user has been using since the first observed
event in 2026-08-10. The fact that the workaround works is itself
evidence that the disappearance is worktree-only.

---

## TIMELINE

| Time (UTC) | Event |
|---|---|
| 2026-08-14 16:14 | Commit `<feature-tip-sha>` (`fix: F1 fence-aware answer frame counting`) pushed to `master` (FF) |
| 2026-08-14 ~16:18 | User ran `git checkout master` in production worktree |
| 2026-08-14 ~16:18 | User ran `git merge --ff-only <feature-tip-sha>` (succeeded) |
| 2026-08-14 ~16:18 | 18 tracked files under `zhihu-answer-grabber/test/` immediately absent from worktree |
| 2026-08-14 ~16:18 | `git status` shows 18 ` D` lines; HEAD/index/blob all healthy |
| 2026-08-14 ~16:18 | User ran `git restore --worktree -- zhihu-answer-grabber/test/`; full recovery |
| 2026-08-14 ~16:30 | User files this incident for ingest into the investigation |

---

## MERGE DELTA (verified independently from GitHub compare)

Base: `93e9c77f53ecd10b235af946469049b9c2c4e7af`
FF head: `4177c6e3ee0f386ad68c5a3b960c23333ce1921a`

`gh api repos/.../compare/<base>...<head>` reports exactly **3
changed paths**:

1. `<PROD_REPO>/zhihu-answer-grabber/src/verifier.js` — modified
2. `<PROD_REPO>/zhihu-answer-grabber/test/verifier-fence.test.js` — added
3. `<PROD_REPO>/zhihu-answer-grabber/test/verify-output.test.js` — modified

No deletions. No renames. The merge delta is a 3-file patch.

**Important delta fact:** the merge applied 0 deletions and 0
renames, yet 18 unrelated tracked files were missing from the
worktree afterward. The 18 missing files are not part of the
merge's own diff. The merge alone cannot explain the disappearance
of those 18 files.

---

## POST-MERGE SIGNATURE

After the successful merge, immediately on the production worktree:

```
$ git status --short
 D zhihu-answer-grabber/test/<file-01>.test.js
 D zhihu-answer-grabber/test/<file-02>.test.js
 ...  (18 entries total)
$ git status --short | wc -l
18
$ git diff --name-status HEAD -- zhihu-answer-grabber/test/ | wc -l
0
$ git ls-files --error-unmatch zhihu-answer-grabber/test/<file-01>.test.js
zhihu-answer-grabber/test/<file-01>.test.js
$ git show :zhihu-answer-grabber/test/<file-01>.test.js | head -1
... (intact content)
$ git show HEAD:zhihu-answer-grabber/test/<file-01>.test.js | head -1
... (intact content)
$ test -e zhihu-answer-grabber/test/<file-01>.test.js
false
```

The pattern is exactly `WORKTREE_ONLY_LOSS`: HEAD=yes, INDEX=yes,
PHYSICAL=no. HEAD and index blobs are readable. The file is
present in the object DB and recoverable from index, but not on
disk.

---

## GIT INTEGRITY

```
$ git rev-parse HEAD
<master-tip-sha>  (healthy, == 4177c6e...)
$ git write-tree
<root-tree-sha>   (healthy)
$ git status
On branch master
nothing to commit, working tree clean   (after restore)
$ git fsck --no-reflogs
(no output, exit 0 — healthy)
$ git remote -v
origin  https://github.com/FlapPearLabs/zhihu-grabber-toolkit.git
$ git ls-remote origin master
<master-tip-sha>  (matches local; remote healthy)
```

HEAD, index, blob, fsck, and remote are all healthy. The worktree
disappearance is worktree-only. The recovery (`git restore
--worktree`) is non-destructive and does not require history
rewrite.

---

## RECOVERY

The user recovered the missing 18 files with a single non-destructive
command:

```
git restore --worktree -- zhihu-answer-grabber/test/
```

After recovery, `git status` shows the working tree clean, no commit
is created, no history is rewritten, and the index is unchanged. The
recovery is idempotent and re-runnable.

---

## WORKBUDDY ENVIRONMENT FACTS (sanitized, captured from real sandbox logs)

The following facts are recorded from the user's WorkBuddy sandbox
session around the time of the incident. **Raw sandbox log lines are
NOT copied here; they may contain secrets (GATEWAY_PASSWORD, tokens,
cookies).** Only the safe, abstracted facts are recorded.

| Fact | Value |
|---|---|
| WorkBuddy version | 5.3.11 |
| sandbox-cli vendor | 5.3.3 |
| Kernel sandbox module | tsbx.dll (TsbxShmemV3 observed) |
| `workingDir` (sanitized) | `<PROD_REPO>` |
| `autoProjection` | `false` |
| `BASH_ENV` | safe-delete bash injection observed |
| `ModifyBackup` rule | `enabled=true`, `method=ipc`, max size 100 MB |
| `sandbox create` | `passthrough=true` |
| `$RECYCLE.BIN` | `inherit_user` rule observed |
| real `git.exe` | native (not Node) |

**Not recorded here (deliberately omitted, would leak secrets):**
- `GATEWAY_PASSWORD` value
- session tokens
- cookies
- raw `env:` blocks
- full sandbox log lines

---

## PROVEN

- The merge was a successful fast-forward from a parent commit that
  GitHub shows is `93e9c77...` to a child commit that GitHub shows is
  `4177c6e...`.
- The merge delta, verified independently via the GitHub compare
  API, contains exactly 3 changed paths (1 modified src + 1 added
  test + 1 modified test). No deletions, no renames.
- 18 tracked test files under `zhihu-answer-grabber/test/` were
  physically absent from the worktree immediately after the merge.
  `git status` showed them as ` D` (deleted in worktree, present in
  index).
- The 18 missing files are recoverable from the index via
  `git restore --worktree -- zhihu-answer-grabber/test/`. HEAD and
  index blobs are intact.
- HEAD, index, blob, fsck, and remote GitHub are all healthy. The
  Git object database is not corrupted. The disappearance is
  worktree-only.
- A 3-path merge delta cannot itself remove 18 unrelated tracked
  files from the worktree under normal Git semantics. Therefore
  the disappearance is **not** explainable as Git normally applying
  the merge.

## HIGH-CONFIDENCE INFERENCE

- The user was running inside an active WorkBuddy tool-call session
  when the incident occurred. The WorkBuddy-side runtime association
  is very high (not strictly proven for this specific merge invocation,
  but the user reports the tool-call context as standard).
- The Node safe-delete shim is unlikely to be the cause of the
  worktree-only loss in this incident: `git.exe` is a native binary
  and the Node shim only patches `fs.*` calls inside Node processes.
  This is consistent with the lab probe's Phase 3 SHIM-ONLY run,
  which is clean (11/11 CLEAN, no worktree loss).
- The disappearance pattern (HEAD yes, INDEX yes, PHYSICAL no;
  recoverable by `git restore --worktree`) is the same pattern
  observed in 5+ user-side events between 2026-08-10 and 2026-08-13,
  before this F1 recurrence.

## UNPROVEN

- The specific component that caused the worktree disappearance in
  this F1 incident. Candidates that remain unproven:
  - `tsbx.dll` kernel filter denied the unlink of the 18 files.
  - `ModifyBackup` rule triggered an IPC call that moved the 18
    files to backup.
  - The OS recycle bin was used as the redirect target.
  - A specific kernel `IRP_MJ_SET_INFORMATION` was denied or
    redirected by a minifilter.
- Whether the kernel filter is even active for the user's
  `git.exe` invocation at all. The kernel filter is loaded into
  processes spawned by `sandbox-cli.exe`; the user's audit log
  shows WorkBuddy tool-call execution, but the exact ancestry
  for the merge invocation was not captured in this round.
- The exact reload mechanism of `tsbx_rules.json` (hot-reload vs.
  per-invocation vs. process startup). This is independent of the
  F1 incident and is documented elsewhere.
- Any claim that the cause is the same as Issue A (npm ci /
  Node shim). The two issues have different root-cause layers even
  though they share the same product-level philosophy.

---

## WHAT THE F1 INCIDENT DOES NOT PROVE

- It does NOT prove that the kernel filter caused the disappearance.
  The pattern is consistent with the kernel filter hypothesis, but
  a minifilter that denies the unlink of 18 files while allowing
  the create of new file contents (3-path delta) has not been
  directly observed.
- It does NOT prove that `ModifyBackup` is the cause. The
  `ModifyBackup` rule is observed in the sandbox config, but the
  specific IPC call sequence (if any) during this merge has not
  been captured.
- It does NOT prove that the recycle bin was used. The user did
  not check the recycle bin during the 30 seconds between the
  merge and the recovery. The recycle bin may or may not contain
  the 18 files.
- It does NOT prove that the cause is deterministic. A single
  reproduction is not enough to claim reproducibility in
  statistical terms.

---

## NEXT STEPS (for the native experiment, not for this document)

The full procedure for closing the F1 question is in
`report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md`. The native experiment
will run two probes:

- **PROBE_A (broad):** the existing 60-file mutation probe
  (`bin/build-git-probe.ps1`). Exercises large non-FF worktree
  mutations.
- **PROBE_B (F1-shape):** the new 160-file F1-shape probe
  (`bin/build-git-probe-f1-shape.ps1`). Exercises a tiny 3-path
  FF delta on a large worktree, mirroring the F1 natural
  recurrence shape.

If PROBE_B reproduces the worktree loss in the native WorkBuddy
session (with both pre-restart and allow-rule phases), the F1
incident is reproduced mechanically and the SANDBOX_POLICY_CAUSE
can be upgraded from HIGH_CONFIDENCE_INFERENCE to CONFIRMED.

---

## NO PRODUCTION CONTENT COPIED

This document intentionally contains:
- 0 lines of the production source code
- 0 lines of the production test fixtures
- 0 raw sandbox log lines
- 0 secret values (GATEWAY_PASSWORD, tokens, cookies, raw env blocks)
- 0 full file paths under `<PROD_REPO>` (only the project's
  relative top-level directories are referenced; the absolute
  install path is replaced with the placeholder)

All factual claims here either:
- reference a public commit SHA on GitHub,
- reference the user's audit log (the user's own words; not
  reproduced here verbatim because the log may contain other
  sensitive entries), or
- describe a counted observation (e.g. "18 files", "3 paths",
  "0 deletions").
