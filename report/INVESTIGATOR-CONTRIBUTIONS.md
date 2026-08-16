# INVESTIGATOR CONTRIBUTIONS

This document exists for **provenance**, not vanity. It records who (which role) established
each class of finding, so a future engineer can trace a claim back to its origin and know
which contribution is durable vs. superseded.

> Repository policy does not require naming the conversational assistant that produced the
> Mavis-phase outputs. Roles are used instead of personal/agent names where the source is a
> private conversation history.

---

## MINIMAX / MAVIS CONTRIBUTIONS

The Mavis-phase investigation (2026-08-10 → 2026-08-13) was conducted from a **non-WorkBuddy
shell** (read-only environment forensics). It established the durable hypotheses and the
disposable lab that later WorkBuddy-native runs built upon.

- **Initial read-only environment forensics** — discovered the safe-delete subsystem and the
  `tsbx` sandbox policy without touching production state.
- **Safe-delete discovery** — `genie-safe-delete.cjs` Node shim + `safe-delete-bulk-guard.cjs`.
- **Node shim mechanics** — API surface patched, `CODEBUDDY_SESSION_ID` gating, trash routing.
- **Bulk-guard mechanics** — 20-delete default threshold, fail-closed
  `SAFE_DELETE_BULK_CONFIRM_REQUIRED`.
- **npm reproduction** — NORMAL vs SHIM A/B; partial-mutation smoking gun.
- **Normal / shim-only comparisons** — Git A/B establishing 11/11 CLEAN in both, ruling the
  shim out for Bug B.
- **First repro bundle** — `bin/repro-all.ps1` one-click orchestrator + fixtures.
- **Early root-cause confidence model** — layering (Node shim / shell shim / kernel filter),
  4-class data-loss boundary.
- **Report drafting** — `ROOT_CAUSE_CLOSURE_REPORT.md`, `sanitized-evidence.md`,
  `BUG-REPORT-TENCENT.md`, `NATURAL-INCIDENT-F1.md`, `NEXT-WORKBUDDY-GIT-EXPERIMENT.md`,
  `environment-summary.txt`, `tsbx_rules.original.json`, `results-*.txt`.

> **What Mavis could NOT do:** reproduce Bug B. The full WorkBuddy-native
> execution chain (including any kernel-sandbox attachment) is only present
> for processes spawned inside a real WorkBuddy tool-call session; a Mavis
> shell is not such a chain, so Bug B was left at `HIGH_CONFIDENCE_INFERENCE`.
> That gap was closed by the WorkBuddy-native phase.

---

## WORKBUDDY-NATIVE CONTRIBUTIONS

The native phase (2026-08-14 → 2026-08-15) ran the probes **inside the real WorkBuddy
sandbox execution chain** (same native context as the R1/R2 runs).

- **Real native sandbox execution** — `assert-native-workbuddy-context.ps1` proving ancestry
  to `sandbox-cli.exe` (R1) / `WorkBuddy.exe` with session id (R2).
- **Natural incidents** — F1 record (`NATURAL-INCIDENT-F1.md`) ingested from
  `zhihu-grabber-toolkit`.
- **F1 evidence** — 3-path ff merge → 18 unrelated test files missing, recovered via
  `git restore --worktree`.
- **Process ancestry evidence** — confirmed git runs under the WorkBuddy-native chain.
- **Synthetic 59-file native reproduction (R1)** — `WORKTREE_ONLY_LOSS` reproduced with
  HEAD/index intact, fsck healthy, persisted across checkout-back.
- **R1 evidence** — `PHASE1_FINAL_REPORT.md` (R1 reproduced the 59-file worktree-only loss; see `report/NATIVE-R1-EVIDENCE.md`). The prior R1-repair CASE A claim of "localized the loss to the build's final `git checkout master`" is **retracted**: R1 first observed the non-clean worktree at the post-final-checkout checkpoint but lacked a physical pre-final-checkout checkpoint, so the exact causal operation was not localized.
- **R2 localization harness** — four physical checkpoints (A/B/C/D) inserted into the build
  to pinpoint the CLEAN→NON_CLEAN interval; parser/attribution tests de-`mavis-trash`-ed.
- **R2 controlled clean run** — A/B/C/D all CLEAN; loss NOT reproduced in that one run,
  establishing intermittency.

> **Key native result:** Bug B is now `SYNTHETIC_NATIVE_REPRODUCTION = CONFIRMED` (R1), with
> `INTERMITTENT_ACROSS_OBSERVED_NATIVE_RUNS = YES` (R1 reproduced, R2 clean). Component cause
> remains `UNRESOLVED`; `tsbx` filter remains `HIGH_CONFIDENCE_HYPOTHESIS`.

---

## INDEPENDENT REVIEW CONTRIBUTIONS

An independent reviewer assessed the R2 evidence pack before vendor publication.

- **Evidence confidence corrections** — enforced the worktree/index distinction; prevented
  conflating "reproduced" with "component-confirmed".
- **Overclaim corrections** — required `GIT_COMPONENT_CAUSE=UNRESOLVED` wording; blocked any
  "race confirmed" / "filter-driver race confirmed" language.
- **Worktree/index distinction** — clarified that `git restore --worktree` does **not**
  recover unstaged modifications.
- **Checkpoint attribution requirements** — required each checkpoint to record
  `CHECK_STATUS` separately from `WORKTREE_INTERFERENCE`, so a checker crash could not be
  misread as a real loss.
- **Vendor-publication gate** — returned **R2 HARNESS REVIEW = PASS**, gating publication on a
  clean, reviewable evidence pack.

> The reviewer's gate is why this repository exists as a consolidated, sanitized,
> independently reviewable artifact rather than a loose collection of logs.
