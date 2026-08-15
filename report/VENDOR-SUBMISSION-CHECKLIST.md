# VENDOR SUBMISSION CHECKLIST

Two linked bugs, prepared for submission to Tencent (WorkBuddy). **This
document is a preparation checklist only — nothing has been submitted
automatically.** The repository is publication-ready; submission is gated on a
human (independent publication review) decision.

Canonical repository: `https://github.com/FlapPearLabs/workbuddy-safedelete-rootcause`

---

## 0. Pre-submission gating (all must be YES)

- [x] Independent review of R2 harness = **PASS** (gates vendor publication)
- [x] No new native experiments added in this consolidation pass
- [x] No Phase 2A work performed
- [x] `zhihu-grabber-toolkit` left unchanged (read-only evidence source)
- [x] All tracked files pass sanitization scan (no REAL user-profile paths;
      placeholders such as `<USER_PROFILE>` are expected) — see
      `report/SOURCE-COVERAGE-AUDIT.md`
- [x] Proprietary content audit = **PASS** (no full WorkBuddy source; only
      sha256 + minimal excerpts) — see `ROOT_CAUSE_CLOSURE_REPORT.md` §Privacy
- [x] Raw local evidence (Mavis context blobs, native-run logs) **not** committed
- [x] Confidence boundaries preserved (no overclaims; Bug B component UNRESOLVED)

---

## 1. BUG A package — `npm ci` / Node safe-delete bulk-guard

| Item | Location | Status |
|---|---|---|
| Standalone vendor report | `report/BUG-A-NPM-SAFE-DELETE.md` | READY |
| Minimal reproduction (1-click) | `bin/repro-all.ps1` + `bin/repro-npm-ci.ps1` | READY (committed) |
| Synthetic fixture (bit-identical family) | `npm-probe/package.json` + `package-lock.json` | READY (committed) |
| Component evidence (sha256 + line refs) | `report/sanitized-evidence.md` §A,§B,§E | READY |
| Structured A/B results | `report/results-npm-ci.txt`, `report/results-latest.txt` | READY (committed) |
| Environment / versions | `report/ENVIRONMENT-MODEL.md` | READY |
| GitHub repository | `FlapPearLabs/workbuddy-safedelete-rootcause` | PUBLIC |

**Bug A classification:** `REPRODUCED=YES · PRODUCT_CAUSE=CONFIRMED ·
COMPONENT_CAUSE=CONFIRMED`. Owner: WorkBuddy `safe-delete` team.

---

## 2. BUG B package — Git worktree physical loss

| Item | Location | Status |
|---|---|---|
| Standalone vendor report | `report/BUG-B-GIT-WORKTREE-LOSS.md` | READY |
| Real-world incident record (F1) | `report/NATURAL-INCIDENT-F1.md` | READY |
| Native R1 synthetic reproduction (summary) | `report/BUG-B-GIT-WORKTREE-LOSS.md` §SYNTHETIC R1 | READY |
| Native R2 four-checkpoint run (summary) | `report/BUG-B-GIT-WORKTREE-LOSS.md` §R2 | READY |
| Native R1 sanitized evidence (public) | `report/NATIVE-R1-EVIDENCE.md` | READY |
| Native R2 sanitized evidence (public) | `report/NATIVE-R2-EVIDENCE.md` | READY |
| Root-cause closure classification | `report/ROOT_CAUSE_CLOSURE_REPORT.md` §ISSUE B | READY |
| Native harness (runnable, sanitized) | `bin/build-git-probe-f1-shape.ps1`, `bin/run-git-cycles.ps1`, `bin/check-worktree.ps1`, `bin/assert-native-workbuddy-context.ps1` | READY (committed) |
| Negative controls (NORMAL / SHIM-ONLY) | `report/results-git-normal.txt`, `report/results-git-shim-only.txt` | READY (committed) |
| Future diagnostic procedure | `report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md` | READY |
| zhihu-grabber-toolkit reference | Issue #1 (comment draft prepared, NOT posted) | READY |
| GitHub repository | `FlapPearLabs/workbuddy-safedelete-rootcause` | PUBLIC |

**Bug B classification:** `REAL_WORLD_INCIDENTS=CONFIRMED ·
SYNTHETIC_NATIVE_REPRODUCTION=CONFIRMED · COMPONENT_CAUSE=UNRESOLVED`.
Suggested routing: WorkBuddy sandbox/filesystem team, subject to Tencent triage. Do **not** state "race confirmed" or
"component confirmed".

> Raw native-run logs (`work/native-runs/**`) are **local-only** (gitignored,
> **NOT AVAILABLE IN PUBLIC REPO**) and are surfaced as sanitized public derivatives
> `report/NATIVE-R1-EVIDENCE.md` (R1) and `report/NATIVE-R2-EVIDENCE.md` (R2). The raw
> logs themselves are intentionally NOT part of the submission package.

---

## 3. Vendor channels

1. **WorkBuddy application — Help / Feedback**
   Attach: Bug A report + Bug B report (or the canonical repo URL). Two linked
   bugs; two separate WorkBuddy filesystem-safety bugs; Bug A is
   component-confirmed, while Bug B's specific component remains unresolved.
2. **Official WorkBuddy support email** (if appropriate per policy)
   Same two reports; reference the canonical repository URL for the full
   evidence pack and harness.

Do **not** submit automatically. A human must perform the independent
publication review and choose the channel.

---

## 4. Submission message skeleton (for the human sender)

> We are filing two linked bugs from the public investigation repository
> `FlapPearLabs/workbuddy-safedelete-rootcause`:
>
> - **Bug A — `npm ci` / Node safe-delete bulk-guard** (component-confirmed):
>   `npm ci` is aborted mid-cleanup by the safe-delete bulk-guard, leaving
>   `node_modules` half-deleted. Reproduced 1-click in the repo.
> - **Bug B — Git worktree physical loss** (phenomenon-confirmed, component
>   unresolved): tracked files disappear from the worktree after `git switch`/
>   `git merge` inside a WorkBuddy-native session while HEAD/index/blob/fsck/
>   remote stay intact. Reproduced natively (R1, 59 files); a controlled R2
>   rerun was clean in that one shot (intermittent). Candidate cause: the
>   `tsbx.dll` kernel filter (HIGH_CONFIDENCE_HYPOTHESIS), not directly observed.
>
> Evidence, harness, and confidence boundaries are in the repository. We request
> component-level confirmation for Bug B (narrow sandbox-rule A/B and/or ETW /
> ProcMon) at Tencent's discretion.

---

## 5. Post-submission (out of scope for this task)

- Post the `zhihu-grabber-toolkit` Issue #1 comment (draft in
  `report/ZHIHU-ISSUE-1-COMMENT-DRAFT.md`) — **NOT posted** by this task.
- Merge the `docs/vendor-handoff-final` branch — **NOT merged** by this task
  (publication review gate).
- No further native experiments — this consolidation is documentation only.
