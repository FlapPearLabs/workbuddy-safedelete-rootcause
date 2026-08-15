# EXECUTIVE SUMMARY — WorkBuddy safe-delete / sandbox filesystem interference

**Canonical repository:** `FlapPearLabs/workbuddy-safedelete-rootcause`
**Investigation window:** 2026-08-10 → 2026-08-15
**Last consolidated:** 2026-08-15 (post R2 independent review)
**Product under investigation:** WorkBuddy (Tencent) — `safe-delete` Node shim + `tsbx` kernel sandbox
**This document is the entry point.** Every claim here is traced to a finding in
[`MASTER-INVESTIGATION-LEDGER.md`](MASTER-INVESTIGATION-LEDGER.md) and, where applicable,
to a claim in [`EVIDENCE-INDEX.md`](EVIDENCE-INDEX.md).

---

## Two distinct bugs

This investigation covers **two bugs with different root-cause layers** that share the same
product philosophy (deny-by-default + a low default delete threshold). They MUST be filed and
tracked separately.

| | **Bug A — npm ci / Node safe-delete** | **Bug B — Git worktree physical loss** |
|---|---|---|
| Layer | Node shim (`genie-safe-delete.cjs`) + bulk-guard (`safe-delete-bulk-guard.cjs`) | `tsbx.dll` kernel filter loaded by `sandbox-cli.exe` |
| Reproduced in lab | **YES** (1-click, disposable) | **YES** (native WorkBuddy synthetic probe, R1) |
| Component cause | **CONFIRMED** | **UNRESOLVED** |
| Runtime association | **CONFIRMED** (shim active when `CODEBUDDY_SESSION_ID` set) | **VERY_HIGH** (loss only under WorkBuddy-native ancestry) |
| Status | Closed at component level | Phenomenon confirmed; component open |
| Owner | WorkBuddy `safe-delete` team | WorkBuddy `sandbox` team |

---

## BUG A — npm ci / Node safe-delete  (CONFIRMED)

**REPRODUCED = YES · PRODUCT_CAUSE = CONFIRMED · COMPONENT_CAUSE = CONFIRMED**

Confirmed relevant components:

- `genie-safe-delete.cjs` (sha256 `A9F9800C1244ADA606A73C96699DA3EBB3E056CE2115BF50912CD9EFC302D1C7`)
- `safe-delete-bulk-guard.cjs` (sha256 `EA40BA9DFD90D6555AC516AE3CA9C1BE7332D826781FBB07AC071903D88CA822`)

Observed behavior (tested conditions only — see below):

- **NORMAL** `npm ci` (no shim env) → exit 0, clean `node_modules`, no deletions blocked.
- **SHIM-active** `npm ci` (WorkBuddy-spawned shell, `CODEBUDDY_SESSION_ID` set,
  `NODE_OPTIONS=--require=genie-safe-delete.cjs`) → exits 1 with
  `SAFE_DELETE_BULK_CONFIRM_REQUIRED {count:59, threshold:20, scope:turn}`.
- **Partial mutation is the smoking gun:** the shim report captured by the lab probe shows
  `npm ci`'s *first* successful delete is a single small file (`.package-lock.json`) that the
  shim silently trashes via `genie-trash` **before** the bulk-guard fires on the larger
  `node_modules/entities` batch. The operation is therefore **non-atomic** — `node_modules`
  is left in a half-deleted state.
- The **same dependency family** (`parse5@8.0.1` + `entities@8.0.0`) reproduces the failure
  in the disposable synthetic lab, bit-identical to the real affected project.

**Scope caveat — do NOT over-claim.** We do **not** claim every package-manager operation
fails. We tested:

- `fs.rmSync` small (5 files) vs large (40 files)
- `npm ci` NORMAL vs SHIM
- the exact `parse5`/`entities` lockfile content

Only the SHIM-active `npm ci` path fails. The default bulk-guard threshold (20 deletes/turn)
is simply unrealistic for any non-trivial `node_modules/<pkg>` directory.

→ Full report: [`BUG-A-NPM-SAFE-DELETE.md`](BUG-A-NPM-SAFE-DELETE.md)

---

## BUG B — Git worktree physical disappearance  (PHENOMENON CONFIRMED, COMPONENT OPEN)

**REAL_WORLD_INCIDENTS = CONFIRMED · SYNTHETIC_NATIVE_REPRODUCTION = CONFIRMED · COMPONENT_CAUSE = UNRESOLVED**

### Signature (every observed case)

```
HEAD       = yes      (git rev-parse HEAD healthy)
INDEX      = yes      (git write-tree matches; blob readable)
PHYSICAL   = no       (tracked files absent from disk)
FSCK       = healthy  (git fsck --no-reflogs, exit 0)
REMOTE     = healthy  (git ls-remote matches local)
```

The loss is **worktree-only**: `git status` shows ` D <path>` lines, `git restore --worktree`
recovers every missing file non-destructively.

### Evidence progression

| Stage | Result | Interpretation |
|---|---|---|
| Real-world user sessions (2026-08-10 → 08-13) | 5+ events in audit log | OBSERVED FACT — worktree-only loss recurs |
| F1 natural incident (2026-08-14, `zhihu-grabber-toolkit`) | 3-path `git merge --ff-only` → 18 unrelated test files missing | OBSERVED FACT — see [`NATURAL-INCIDENT-F1.md`](NATURAL-INCIDENT-F1.md) |
| Mavis lab NORMAL control | 11/11 `WORKTREE_CHECK_VERDICT=CLEAN` | NEGATIVE CONTROL — normal git does not lose files |
| Mavis lab SHIM-ONLY control | 11/11 `WORKTREE_CHECK_VERDICT=CLEAN` | NEGATIVE CONTROL — **Node shim alone does NOT cause Bug B** (FALSIFIED) |
| **WorkBuddy-native R1** (2026-08-14) | **reproduced** `WORKTREE_ONLY_LOSS`, 59 unrelated tracked files, HEAD/index intact, fsck healthy, under real `sandbox-cli.exe` ancestry | **SYNTHETIC_NATIVE_REPRODUCTION = CONFIRMED** |
| R1 evidence-localization repair | loss localized to the build's final `git checkout master` | narrowed CLEAN→NON_CLEAN interval |
| **WorkBuddy-native R2** (2026-08-15, four-checkpoint harness) | A CLEAN · B CLEAN · C CLEAN · D CLEAN — loss **NOT** reproduced in this one controlled run | **INTERMITTENT_ACROSS_OBSERVED_NATIVE_RUNS = YES** |

### What this means for the cause

- `SOURCE_OF_RUN_TO_RUN_VARIABILITY = UNRESOLVED`
- `WORKBUDDY_RUNTIME_ASSOCIATION = VERY_HIGH` (loss occurs only inside the WorkBuddy-native
  execution chain; never observed from a non-WorkBuddy shell)
- `GIT_COMPONENT_CAUSE = UNRESOLVED` (no direct component-level evidence)
- `TSBX_FILTER_CAUSE = HIGH_CONFIDENCE_HYPOTHESIS` (the `tsbx.dll` kernel filter is the only
  remaining mechanism consistent with all observed facts, but it has **not** been directly
  observed denying a specific operation)

**Do NOT write** "race confirmed", "timing bug confirmed", or "filter-driver race confirmed".
The anomaly is **intermittent across the observed native runs**; the source of run-to-run
variability remains unresolved.

→ Full report: [`BUG-B-GIT-WORKTREE-LOSS.md`](BUG-B-GIT-WORKTREE-LOSS.md)

---

## Independent review

The R2 localization harness received an independent review:

- **R2 HARNESS REVIEW = PASS**

The reviewer corrected overclaims (worktree/index distinction, checkpoint attribution
requirements, confidence boundaries) and gated vendor publication on a clean, reviewable
evidence pack — which this repository now is.

---

## What Tencent needs to investigate next (Bug B)

1. **Narrow sandbox-rule A/B** — apply a scoped `inherit_user` rule for the dev workspace and
   re-run the native probe (see [`NEXT-WORKBUDDY-GIT-EXPERIMENT.md`](NEXT-WORKBUDDY-GIT-EXPERIMENT.md)).
   NOT REQUIRED for the current submission; FUTURE_DIAGNOSTIC_IF_VENDOR_REQUESTS.
2. **ETW / ProcMon capture** of the kernel-filter denials during a reproducing native run.
   NOT REQUIRED for the current submission; FUTURE_DIAGNOSTIC_IF_VENDOR_REQUESTS.
3. **Component-level confirmation** of which kernel component (tsbx filter vs. `ModifyBackup`
   IPC vs. recycle-bin routing) performs the worktree mutation, and why it is intermittent.

---

## Repository orientation

| Document | Role |
|---|---|
| `README.md` | One-click reproduction entry |
| `report/EXECUTIVE-SUMMARY.md` | This file |
| `report/MASTER-INVESTIGATION-LEDGER.md` | Master reconciliation of every finding |
| `report/SOURCE-COVERAGE-AUDIT.md` | Source inventory + coverage reconciliation |
| `report/INVESTIGATION-TIMELINE.md` | Chronological investigation stages |
| `report/EVIDENCE-INDEX.md` | Claim-by-claim evidence + confidence |
| `report/INVESTIGATOR-CONTRIBUTIONS.md` | Provenance: who found what |
| `report/BUG-A-NPM-SAFE-DELETE.md` | Standalone Bug A vendor report |
| `report/BUG-B-GIT-WORKTREE-LOSS.md` | Standalone Bug B vendor report |
| `report/NATURAL-INCIDENT-F1.md` | Real F1 production incident record |
| `report/ROOT_CAUSE_CLOSURE_REPORT.md` | Root-cause closure classification |
| `report/sanitized-evidence.md` | Proprietary snippets, rule JSON, audit quotes (sanitized) |
| `report/ENVIRONMENT-MODEL.md` | Environment / version / process model |
| `report/VENDOR-SUBMISSION-CHECKLIST.md` | Two linked bug packages + channels |

Raw, non-sanitized local evidence (Mavis context blobs, native-run logs) is **not** committed;
see `work/RAW-EVIDENCE-MANIFEST.md` (local only) for the re-verification map.
