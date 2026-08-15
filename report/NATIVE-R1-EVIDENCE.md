# NATIVE R1 EVIDENCE — WorkBuddy-native synthetic Bug B reproduction

**Public, sanitized derivative** of the R1 native-run raw log. This document is
the canonical, vendor-submissible evidence for the R1 reproduction of Bug B
(Git worktree physical loss). It contains no PII, no real production paths, and
no raw native-run log content — only the deduplicated, sanitized fields needed
to substantiate the claims in `BUG-B-GIT-WORKTREE-LOSS.md`,
`EXECUTIVE-SUMMARY.md`, and `MASTER-INVESTIGATION-LEDGER.md` (GIT-003).

> **RAW_LOCAL_SOURCE** (the un-sanitized native-run log that this document is
> derived from) is **NOT AVAILABLE IN PUBLIC REPO**. It lives only in the local,
> gitignored path `work/native-runs/2026-08-14T21-43-52Z-8d51e361d168/PHASE1_FINAL_REPORT.md`
> and is intentionally excluded from the public repository for privacy. Its SHA256
> is recorded below so a local re-verification can confirm this derivative matches
> the raw source without exposing it.

---

## Provenance

| Field | Value |
|---|---|
| Run | R1 — WorkBuddy-native synthetic PROBE_B (F1-shape) |
| Date | 2026-08-14 |
| Raw source (local only) | `work/native-runs/2026-08-14T21-43-52Z-8d51e361d168/PHASE1_FINAL_REPORT.md` |
| Raw source SHA256 | `34F3EC90A74A89CBF32FA0DCA1F049354ACAE860519ABC99525CC174EF530870` |
| Raw availability | **NOT AVAILABLE IN PUBLIC REPO** (gitignored under `work/`) |
| Public derivative | this file (`report/NATIVE-R1-EVIDENCE.md`) |
| Sanitization | all `<USER_PROFILE>` / `<WORKSPACE>` / `<WORKBUDDY_INSTALL>` / `<PROD_REPO>` / `<TEMP>` / `<USER_DATA>` placeholders applied; no tokens/cookies/paths published |

---

## Environment (R1)

| Field | Value |
|---|---|
| WorkBuddy version | 5.3.13 (native run) |
| Git version | 2.49.0.windows.1 |
| Windows | 10.0.26200 (NTFS) |
| Sandbox-cli | 5.3.3 |
| Native ancestry reached | `sandbox-cli.exe` |
| `CODEBUDDY_SESSION_ID` present | NO |
| `WORKBUDDY_NATIVE_ANCESTRY_CONFIRMED` | UNKNOWN (session id absent → could not confirm; ancestry to sandbox-cli.exe observed) |

> R2 later confirmed native ancestry definitively (`WorkBuddy.exe` with a present
> session id). Both runs prove the probe executed inside the WorkBuddy-native chain.

---

## F1-shape probe structure

| Field | Value |
|---|---|
| BASE_TRACKED | 160 |
| TEST_LIKE | 60 |
| CHANGED | 3 |
| MODIFIED | 2 |
| ADDED | 1 |
| DELETED | 0 |

The probe mirrors the 2026-08-14 F1 natural incident shape: a small 3-path delta
(1 modified src + 1 added test + 1 modified test) over a 160-tracked-file repo.

---

## Reproduction result (R1)

| Field | Value |
|---|---|
| `WORKTREE_ONLY_LOSS` | **REPRODUCED** |
| MISSING_COUNT | 59 (unrelated tracked files, physically absent) |
| HEAD | yes (git rev-parse HEAD healthy) |
| INDEX | yes (git write-tree matches; blob readable) |
| PHYSICAL | no (tracked files absent from disk) |
| HEAD_TREE == INDEX_TREE | YES (`8f9cc717…`) |
| FSCK_HEALTHY | YES (git fsck --no-reflogs, exit 0) |
| Loss persisted across checkout-back | YES (not self-healing) |

**Signature:** `HEAD=yes, INDEX=yes, PHYSICAL=no, HEAD_TREE==INDEX_TREE, FSCK healthy` —
the canonical WORKTREE_ONLY_LOSS signature. `git restore --worktree` recovers every
missing file non-destructively.

**First observed non-clean step:** `step-1a-switch-to-feature`
**First observed non-clean operation:** `git checkout feature-probe-f1shape`

→ Establishes `SYNTHETIC_NATIVE_REPRODUCTION = CONFIRMED` for Bug B.

---

## Retraction note — R1-repair CASE A localization claim

A subsequent R1-repair rerun (labeled CASE A, raw log
`work/native-runs/2026-08-14T15-32-33Z-jf10pgjgdoiu/REPAIR_FINAL_REPORT.md`,
**NOT AVAILABLE IN PUBLIC REPO**) previously characterized the loss as
"localized to the build's final `git checkout master`".

**That characterization is retracted.** R1 first observed the non-clean worktree at
the post-final-checkout checkpoint, but it lacked a physical pre-final-checkout
checkpoint, so the exact causal operation was **not** localized. The correct
statement is: **the precise causal operation within the build sequence remains
unresolved.** R2 (see `NATIVE-R2-EVIDENCE.md`) added A/B/C/D physical checkpoints;
its one controlled rerun completed clean, confirming the anomaly is intermittent
rather than pinning a single cause.

Do **not** cite "R1 localized the loss to the final `git checkout master`" or
"CASE A proved the final checkout caused the loss" — both are retracted.
