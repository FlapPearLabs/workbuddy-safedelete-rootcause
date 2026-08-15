# NATIVE R2 EVIDENCE — WorkBuddy-native four-checkpoint controlled rerun

**Public, sanitized derivative** of the R2 native-run raw log. This document is
the canonical, vendor-submissible evidence for the R2 controlled rerun of Bug B
(Git worktree physical loss). It contains no PII, no real production paths, and
no raw native-run log content — only the deduplicated, sanitized fields needed
to substantiate the claims in `BUG-B-GIT-WORKTREE-LOSS.md`,
`EXECUTIVE-SUMMARY.md`, and `MASTER-INVESTIGATION-LEDGER.md` (GIT-005, GIT-006).

> **RAW_LOCAL_SOURCE** (the un-sanitized native-run log that this document is
> derived from) is **NOT AVAILABLE IN PUBLIC REPO**. It lives only in the local,
> gitignored path `work/native-runs/2026-08-15T06-51-51Z-c7de59f17452/REPAIR_R2_FINAL_REPORT.md`
> and is intentionally excluded from the public repository for privacy. Its SHA256
> is recorded below so a local re-verification can confirm this derivative matches
> the raw source without exposing it.

---

## Provenance

| Field | Value |
|---|---|
| Run | R2 — WorkBuddy-native four-checkpoint controlled rerun (F1-shape) |
| Date | 2026-08-15 |
| Raw source (local only) | `work/native-runs/2026-08-15T06-51-51Z-c7de59f17452/REPAIR_R2_FINAL_REPORT.md` |
| Raw source SHA256 | `7D47227D8CD0A040E0B011712A30D67770A1AF574F62A22CB7F99E8434EB3641` |
| Raw availability | **NOT AVAILABLE IN PUBLIC REPO** (gitignored under `work/`) |
| Public derivative | this file (`report/NATIVE-R2-EVIDENCE.md`) |
| Sanitization | all `<USER_PROFILE>` / `<WORKSPACE>` / `<WORKBUDDY_INSTALL>` / `<PROD_REPO>` / `<TEMP>` / `<USER_DATA>` placeholders applied; no tokens/cookies/paths published |

---

## Environment (R2)

| Field | Value |
|---|---|
| WorkBuddy version | 5.3.13 (native run) |
| Git version | 2.49.0.windows.1 |
| Windows | 10.0.26200 (NTFS) |
| Sandbox-cli | 5.3.3 |
| Native ancestry reached | `WorkBuddy.exe` |
| `CODEBUDDY_SESSION_ID` present | YES |
| `WORKBUDDY_NATIVE_ANCESTRY_CONFIRMED` | YES (definitively confirmed this run) |

---

## Checkpoint results (four physical checkpoints)

The R2 harness inserted four physical checkpoints into the build to attempt to
pinpoint the CLEAN→NON_CLEAN interval:

| Checkpoint | Location | Verdict | Missing | HEAD_INDEX_TREE_MATCH | FSCK_HEALTHY |
|---|---|---|---|---|---|
| A | after commit-A | **CLEAN** | 0 | YES | YES |
| B | after `git checkout -b` | **CLEAN** | 0 | YES | YES |
| C | after commit-B + shape assertion | **CLEAN** | 0 | YES | YES |
| D | after final `git checkout master` | **CLEAN** | 0 | YES | YES |

Ancillary operations:
- `FEATURE_INITIAL_CHECKOUT`: exit 0, target_reached = YES
- `FINAL_CHECKOUT`: exit 0, target_reached = YES
- `FIRST_KNOWN_NON_CLEAN_CHECKPOINT` = **NONE**

**Result:** loss **NOT** reproduced in this one controlled run.
→ `NATIVE_RERUN_NOT_REPRODUCED_IN_ONE_RUN = YES`.

---

## Interpretation fields (R2)

| Field | Value |
|---|---|
| `GIT_COMPONENT_CAUSE` | **UNRESOLVED** (no direct component-level evidence in either run) |
| `TSBX_FILTER_CAUSE` | **HIGH_CONFIDENCE_HYPOTHESIS** (leading candidate; not directly observed denying an op) |
| `WORKBUDDY_RUNTIME_ASSOCIATION` | **VERY_HIGH** (loss only under WorkBuddy-native ancestry; never from a non-WB shell) |
| `OBSERVED_ASSOCIATION` | **STRONG** |
| `SOURCE_OF_RUN_TO_RUN_VARIABILITY` | **UNRESOLVED** |

Combined with R1 (which reproduced the loss), R2 establishes
`INTERMITTENT_ACROSS_OBSERVED_NATIVE_RUNS = YES`. The anomaly is intermittent
across the observed native runs; the source of run-to-run variability remains
unresolved.

> The R2 harness received an independent review: **R2 HARNESS REVIEW = PASS**.
> The reviewer corrected overclaims (worktree/index distinction, checkpoint
> attribution requirements, confidence boundaries) and gated vendor publication
> on a clean, reviewable evidence pack.
