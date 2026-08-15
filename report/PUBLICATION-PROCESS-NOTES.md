# PUBLICATION PROCESS NOTES

Transparency record of repository-hygiene operations performed during the
publication of this investigation. This is **not** an investigation finding; it
documents how the git history was managed so a reviewer can separate *evidence
integrity* from *repo plumbing*.

---

## Prior publication ref/commit operations used `dangerouslyDisableSandbox`

During the earlier publication-ref/commit work that assembled the
`docs/vendor-handoff-final` branch, some git **write-ref** operations
(`git checkout -b`, `git update-ref`, `git commit`, `git push` against
multi-level refs such as `refs/heads/<dir>/<branch>`) were executed with
`dangerouslyDisableSandbox=true`.

**Why:** the bundled Windows PortableGit, when running inside the WorkBuddy
sandbox, silently fails to persist multi-level ref writes (command exits 0 but
the ref file is not created; `git rev-parse HEAD` then reports `ambiguous
argument 'HEAD'`). Writing refs therefore required escaping the sandbox.

**When:** this escape was used **only after all native experiments (R1, R2)
were complete** and their raw evidence had already been captured under
`work/native-runs/`.

**Forensic impact: NONE.** The `dangerouslyDisableSandbox` flag affected only
git's ability to *write repository refs/commits* for the publication branch. It
did not alter, re-run, or influence any WorkBuddy sandbox behavior, any native
reproduction, or any raw evidence captured during R1/R2. The native-run logs
remain byte-identical and are fingerprinted in `NATIVE-R1-EVIDENCE.md` /
`NATIVE-R2-EVIDENCE.md`.

---

## This correction task did NOT use `dangerouslyDisableSandbox`

`WORKBUDDY_VENDOR_PUBLICATION_FINAL_CORRECTION` (this task) committed its
corrections to `docs/vendor-handoff-final` with **normal sandbox permissions** —
no `dangerouslyDisableSandbox` was used. Multi-level ref writes were avoided by
committing directly on the existing publication branch (no new `checkout -b` of a
multi-level ref was required). Pushing used the normal path.

---

## Stop conditions honored by this task

This task is a **publication-package correction only**. It did NOT:

- run any new native experiment (NEW_NATIVE_EXPERIMENTS = NO)
- perform Phase 2A / edit `tsbx_rules.json` (PHASE2A = DEFERRED; TSBX_RULES_MODIFIED = NO)
- restart WorkBuddy (WORKBUDDY_RESTARTED = NO)
- modify the production repo `zhihu-grabber-toolkit` (PRODUCTION_REPO_CHANGED = NO)
- post the Zhihu Issue #1 comment (per `ZHIHU-ISSUE-1-COMMENT-DRAFT.md` gating)
- submit anything to Tencent (TENCENT_SUBMISSION = NO)
- merge `docs/vendor-handoff-final` into `master` (handled by a separate human
  publication-review gate)
- force-push or rewrite git history
- delete or alter any prior evidence
