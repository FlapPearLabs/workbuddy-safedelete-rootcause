# ZHIHU-GRABBER-TOOLKIT — Issue #1 COMMENT DRAFT

**Status: DRAFT — NOT POSTED.** This is the exact comment text prepared for
`FlapPearLabs/zhihu-grabber-toolkit` Issue #1. It is referenced by
`VENDOR-SUBMISSION-CHECKLIST.md` and `MASTER-INVESTIGATION-LEDGER.md`
(SOURCE D). Posting is gated on a human decision; this task does **not** post
it.

Canonical investigation repository:
`https://github.com/FlapPearLabs/workbuddy-safedelete-rootcause`

---

## Proposed comment (copy verbatim when posting)

> We opened a dedicated, publicly reviewable investigation repository for the
> WorkBuddy filesystem-interference issue observed in this project:
>
> **https://github.com/FlapPearLabs/workbuddy-safedelete-rootcause**
>
> Summary of where things stand:
>
> - The F1 natural incident (2026-08-14, a 3-path `git merge --ff-only` that
>   left 18 unrelated test files missing) is recorded there as
>   `NATURAL-INCIDENT-F1.md`, recovered via `git restore --worktree` with no
>   history rewrite.
> - **Bug A (`npm ci` / Node safe-delete bulk-guard)** is reproduced in a
>   1-click disposable lab and the component cause is confirmed
>   (`genie-safe-delete.cjs` + `safe-delete-bulk-guard.cjs`).
> - **Bug B (Git worktree physical disappearance)** was reproduced in a
>   **native WorkBuddy** synthetic probe (R1: 59 unrelated tracked files lost
>   while HEAD/index/blob/fsck stayed intact). A follow-up controlled
>   four-checkpoint rerun (R2) was clean in that one shot, so the anomaly is
>   **intermittent** across native runs. The specific component cause remains
>   **unresolved**; the `tsbx.dll` kernel filter is the leading
>   (high-confidence) hypothesis but has not been directly observed denying an
>   operation.
> - Recovery for committed/staged content: `git restore --worktree <path>`.
>   For unstaged/untracked content, check the OS recycle bin / editor local
>   history first, because `git restore --worktree` would wipe unstaged bytes.
>
> We are preparing two linked vendor reports (Bug A + Bug B) for Tencent. This
> issue is kept as the production-incident tracking reference; the rootcause
> repo is the canonical evidence and reproduction source.

---

## Notes for the poster

- Do **not** include any real production path, token, cookie, or user-profile
  string in the comment. The draft above is sanitized.
- Keep the canonical URL exactly as shown; it is the single source of truth.
- The draft explicitly states the Bug B component cause is **unresolved** —
  do not upgrade that wording when posting.
- The prior R1-repair claim of "localized to the build's final `git checkout
  master`" is **retracted** — do not repeat it. The correct statement is that
  R1 observed the non-clean worktree at the post-final-checkout checkpoint but
  lacked a physical pre-final-checkpoint, so the exact causal operation was not
  localized.
