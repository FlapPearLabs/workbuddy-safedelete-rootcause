# SOURCE COVERAGE AUDIT

This document satisfies **PHASE 1 (inventory)** and **PHASE 3 (coverage reconciliation)** of
the consolidation task. It records what was found in each of the four sources, classifies it,
and proves that every material finding is represented in the canonical public repository.

`UNCOVERED_HIGH_VALUE_FINDINGS = 0` (enforced at the end of this document).

---

## 1. Inventory

Columns: `SOURCE · PATH · TYPE · DATE/ORDER · TOPIC · RELEVANCE · SENSITIVE · PUBLICATION_ACTION`

`PUBLICATION_ACTION` values:
`INCLUDE_SANITIZED` · `SUMMARIZE_ONLY` · `ALREADY_CANONICAL` · `DUPLICATE` · `IRRELEVANT` · `KEEP_LOCAL_ONLY`

### SOURCE A — Minimax/Mavis workspace `mvs_6db755ca43674149a1d21ecc7e779894`
(on disk at `<USER_PROFILE>\.minimax\context-{snapshots,replacements}\mvs_6db755…`; `.mavis` is a symlink → `.minimax`)

| SOURCE | PATH | TYPE | DATE/ORDER | TOPIC | RELEVANCE | SENSITIVE | PUBLICATION_ACTION |
|---|---|---|---|---|---|---|---|
| A | `…/context-snapshots/mvs_6db755…-a44b8eb2-…-iteration-ctx_….json` | JSON (1.95 MB) internal iteration context | 2026-08-13 | Minimax runtime conversation/context blob | LOW (runtime state, not investigation output) | YES (may contain env blocks, tokens, chat) | KEEP_LOCAL_ONLY |
| A | `…/context-snapshots/mvs_6db755…-ed949410-…-iteration-ctx_….json` | JSON (2.26 MB) internal iteration context | 2026-08-14 | Minimax runtime conversation/context blob | LOW | YES | KEEP_LOCAL_ONLY |
| A | `…/context-replacements/mvs_6db755…-a44b8eb2-….json` | JSON (58 KB) context replacement | 2026-08-13 | Minimax runtime state | LOW | YES | KEEP_LOCAL_ONLY |
| A | `…/context-replacements/mvs_6db755…-ed949410-….json` | JSON (70 KB) context replacement | 2026-08-14 | Minimax runtime state | LOW | YES | KEEP_LOCAL_ONLY |

> **Key finding:** SOURCE A on disk contains **only internal Minimax context blobs**, not
> investigation documents. All durable Mavis *investigation outputs* (root-cause report,
> sanitized evidence, tsbx rule backup, results, environment summary, F1 record, Tencent
> submission) were already imported into SOURCE C during earlier phases. See §2.

### SOURCE B — Minimax/Mavis workspace `mvs_c19aa4fdfe7249e4b2c51571cef94437`

| SOURCE | PATH | TYPE | DATE/ORDER | TOPIC | RELEVANCE | SENSITIVE | PUBLICATION_ACTION |
|---|---|---|---|---|---|---|---|
| B | *(entire directory)* | — | — | — | — | — | **DOES NOT EXIST** |

> Verified via targeted `find` across `<USER_PROFILE>` (depth 9, case-insensitive) for `*c19aa4*`:
> **zero matches**. The directory named in the task is absent on this machine. No files from
> SOURCE B were reviewed because none are present. This is recorded, not silently skipped.

### SOURCE C — canonical repo `workbuddy-safedelete-rootcause` (this document set)

| SOURCE | PATH | TYPE | DATE/ORDER | TOPIC | RELEVANCE | SENSITIVE | PUBLICATION_ACTION |
|---|---|---|---|---|---|---|---|
| C | `README.md` | markdown | 2026-08-14 | one-click repro entry | HIGH | NO | ALREADY_CANONICAL (updated) |
| C | `bin/*` (16 scripts) | PowerShell/Node | 2026-08-14→15 | repro + native harness | HIGH | NO | ALREADY_CANONICAL |
| C | `npm-probe/*` | JSON | 2026-08-14 | synthetic `parse5`+`entities` fixture | HIGH | NO | ALREADY_CANONICAL |
| C | `report/ROOT_CAUSE_CLOSURE_REPORT.md` | markdown | 2026-08-13 (updated 2026-08-15) | closure summary | HIGH | NO | ALREADY_CANONICAL (updated) |
| C | `report/sanitized-evidence.md` | markdown | 2026-08-13 | proprietary snippets/rules/audit | HIGH | NO (sanitized) | ALREADY_CANONICAL |
| C | `report/BUG-REPORT-TENCENT.md` | markdown | 2026-08-13 | prior submission file | HIGH | NO | ALREADY_CANONICAL (superseded by BUG-A/BUG-B) |
| C | `report/NATURAL-INCIDENT-F1.md` | markdown | 2026-08-14 | F1 real incident | HIGH | NO | ALREADY_CANONICAL (retained) |
| C | `report/NEXT-WORKBUDDY-GIT-EXPERIMENT.md` | markdown | 2026-08-13 | native diagnostic procedure | HIGH | NO | ALREADY_CANONICAL |
| C | `report/environment-summary.txt` | txt | 2026-08-13 | sanitized env | HIGH | NO | ALREADY_CANONICAL |
| C | `report/tsbx_rules.original.json` | json | 2026-08-13 | rule backup (paths redacted) | HIGH | NO | ALREADY_CANONICAL |
| C | `report/results-*.txt` (5 files) | txt | 2026-08-13 | structured A/B records | HIGH | NO | ALREADY_CANONICAL |
| C | `work/native-runs/**` | mixed | 2026-08-14→15 | R1/R2 raw evidence | HIGH | PARTIAL | KEEP_LOCAL_ONLY (raw); summarized into report/ |
| C | `report/EXECUTIVE-SUMMARY.md` | markdown | 2026-08-15 | this consolidation | HIGH | NO | INCLUDE_SANITIZED (new) |
| C | `report/MASTER-INVESTIGATION-LEDGER.md` | markdown | 2026-08-15 | master ledger | HIGH | NO | INCLUDE_SANITIZED (new) |
| C | `report/SOURCE-COVERAGE-AUDIT.md` | markdown | 2026-08-15 | this file | HIGH | NO | INCLUDE_SANITIZED (new) |
| C | `report/INVESTIGATION-TIMELINE.md` | markdown | 2026-08-15 | timeline | HIGH | NO | INCLUDE_SANITIZED (new) |
| C | `report/EVIDENCE-INDEX.md` | markdown | 2026-08-15 | claim index | HIGH | NO | INCLUDE_SANITIZED (new) |
| C | `report/INVESTIGATOR-CONTRIBUTIONS.md` | markdown | 2026-08-15 | provenance | HIGH | NO | INCLUDE_SANITIZED (new) |
| C | `report/BUG-A-NPM-SAFE-DELETE.md` | markdown | 2026-08-15 | Bug A vendor report | HIGH | NO | INCLUDE_SANITIZED (new) |
| C | `report/BUG-B-GIT-WORKTREE-LOSS.md` | markdown | 2026-08-15 | Bug B vendor report | HIGH | NO | INCLUDE_SANITIZED (new) |
| C | `report/ENVIRONMENT-MODEL.md` | markdown | 2026-08-15 | env model | HIGH | NO | INCLUDE_SANITIZED (new) |
| C | `report/VENDOR-SUBMISSION-CHECKLIST.md` | markdown | 2026-08-15 | two-bug submission | HIGH | NO | INCLUDE_SANITIZED (new) |
| C | `work/RAW-EVIDENCE-MANIFEST.md` | markdown | 2026-08-15 | raw map (local) | HIGH | NO | KEEP_LOCAL_ONLY (gitignored) |

### SOURCE D — `zhihu-grabber-toolkit` (GitHub, public records only)

| SOURCE | PATH | TYPE | DATE/ORDER | TOPIC | RELEVANCE | SENSITIVE | PUBLICATION_ACTION |
|---|---|---|---|---|---|---|---|
| D | `FlapPearLabs/zhihu-grabber-toolkit` Issue #1 | GitHub issue | 2026-08 (open) | tracking issue for the natural incident | HIGH | NO (public) | ALREADY_CANONICAL (referenced; comment draft prepared, NOT posted) |
| D | F1 natural incident (2026-08-14) | incident | 2026-08-14 | 3-path ff merge → 18 test files missing | HIGH | NO | ALREADY_CANONICAL (`NATURAL-INCIDENT-F1.md`) |

---

## 2. Coverage reconciliation (every material Mavis artifact → canonical)

For each durable Mavis investigation artifact, state whether its information is represented in
the canonical repo, and what action was taken.

| Mavis artifact (durable output, now in SOURCE C) | Contains | Canonical coverage | Action |
|---|---|---|---|
| `ROOT_CAUSE_CLOSURE_REPORT.md` | Bug A confirmed; Bug B HIGH_CONFIDENCE_INFERENCE; 4-class data-loss; layering | Bug A → YES (`BUG-A`); Bug B → YES, **updated** with R1/R2 (`BUG-B`, `ROOT_CAUSE`); layering → YES (`ENVIRONMENT-MODEL`); data-loss → YES (`BUG-B`) | UPDATED (R1/R2 folded in) |
| `sanitized-evidence.md` | shim/guard snippets, tsbx rule JSON, binary strings, audit quotes | Bug A components → YES (`BUG-A`); tsbx rules → YES (`ENVIRONMENT-MODEL`, `BUG-B`); audit quotes → YES (`BUG-B`, `EVIDENCE-INDEX`) | RETAINED + linked |
| `BUG-REPORT-TENCENT.md` | prior two-bug submission | Split into `BUG-A-NPM-SAFE-DELETE.md` + `BUG-B-GIT-WORKTREE-LOSS.md` | SUMMARIZED_ONLY (superseded by standalone reports) |
| `NATURAL-INCIDENT-F1.md` | F1 real incident record | F1 → YES (`NATURAL-INCIDENT-F1.md`, retained); linked from `BUG-B`, `TIMELINE`, `LEDGER` | RETAINED |
| `NEXT-WORKBUDDY-GIT-EXPERIMENT.md` | native diagnostic procedure | Diagnostics → YES (`BUG-B` "future diagnostics" section) | RETAINED + linked |
| `environment-summary.txt` | sanitized env/versions | → YES (`ENVIRONMENT-MODEL.md`) | RETAINED + linked |
| `tsbx_rules.original.json` | rule backup (sha256-pinned, redacted) | → YES (`ENVIRONMENT-MODEL`, `BUG-B`) | RETAINED |
| `results-*.txt` (5) | structured A/B records | → YES (`EVIDENCE-INDEX`, `BUG-A`, `BUG-B`) | RETAINED |
| `README.md` (repo) | one-click repro | → YES (updated `README.md`) | UPDATED |
| Mavis internal context blobs (SOURCE A on disk) | runtime state | N/A — no durable finding distinct from above | KEEP_LOCAL_ONLY (not published) |

**Coverage gaps found:** none of the durable Mavis findings were missing from the canonical
repo. The only "new" material is the **WorkBuddy-native R1/R2 evidence** (which came from
SOURCE C's own `work/native-runs/`, not from Mavis) — now surfaced into `report/` for the
first time via this consolidation.

---

## 3. Completeness enforcement

`UNCOVERED_HIGH_VALUE_FINDINGS = 0`

All material Mavis investigation artifacts are represented in the canonical repo. The two
Mavis on-disk context blobs (SOURCE A) and the absent SOURCE B directory contain no durable
investigation findings requiring publication; they are correctly excluded as runtime state /
non-existent.

Nothing is declared "complete" without this reconciliation.
