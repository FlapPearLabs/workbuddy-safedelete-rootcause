# MASTER INVESTIGATION LEDGER

Master reconciliation of **every** material finding from the four sources:

- **SOURCE A** — Minimax/Mavis workspace `mvs_6db755…` (on-disk: two internal context JSON blobs only; durable outputs already imported into SOURCE C)
- **SOURCE B** — Minimax/Mavis workspace `mvs_c19aa4…` — **UNAVAILABLE** on this machine. Verified via literal-path PowerShell (`Test-Path` / `Resolve-Path` on `<USER_PROFILE>\.mavis\agents\mavis\workspace`): `SOURCE_B_TEST_PATH_EXISTS=False`; the workspace contains only `.mavis`, `.opencode`, `avatars`, `story-image-studio`, `tts`, `voice-audition`, `workbuddy-tutorial`. `SOURCE_B_STATUS = UNAVAILABLE`; `SOURCE_B_COVERAGE = NOT_VERIFIABLE`; `AVAILABLE_SOURCE_UNCOVERED_HIGH_VALUE_FINDINGS = 0`. **KNOWN_SOURCE_GAP:** SOURCE B is unavailable on the current machine; no claim is made that its (absent) contents were audited.
- **SOURCE C** — canonical repo `workbuddy-safedelete-rootcause` (this document set)
- **SOURCE D** — `zhihu-grabber-toolkit` Issue #1 + F1 natural incident

Status vocabulary (never collapsed):

`OBSERVED FACT` · `PROVEN` · `REPRODUCED` · `NEGATIVE CONTROL` · `HIGH_CONFIDENCE_INFERENCE` · `HYPOTHESIS` · `FALSIFIED` · `UNKNOWN`

Confidence vocabulary: `CONFIRMED` · `HIGH` · `MEDIUM` · `LOW` · `UNRESOLVED`

---

| ID | DATE / PHASE | SOURCE | QUESTION | EXPERIMENT / INCIDENT | OBSERVATION | STATUS | CONFIDENCE | CANONICAL EVIDENCE | PUBLICATION LOCATION | SUPERSEDED_BY | NOTES |
|---|---|---|---|---|---|---|---|---|---|---|---|
| ENV-001 | 2026-08-13 | A/C | Which WorkBuddy build? | environment-summary + R1 context-assert | WorkBuddy 5.3.11 (Mavis) / 5.3.13 (R1 native); sandbox-cli 5.3.3; tsbx `TsbxShmemV3` | OBSERVED FACT | CONFIRMED | `report/environment-summary.txt`, `work/native-runs/2026-08-14T21-43-52Z-8d51e361d168/env-facts.txt` | ENVIRONMENT-MODEL.md | — | version drift 5.3.11→5.3.13 across runs; both observed |
| ENV-002 | 2026-08-13 | A/C | What is the tsbx default policy? | read `tsbx_rules.json` | `default_action: deny_write`, `recyclebin_backup: true`, `auto_grant: true`; **no** `<WORKSPACE>\**` allow rule | PROVEN | CONFIRMED | `report/tsbx_rules.original.json`, `report/sanitized-evidence.md §C` | ENVIRONMENT-MODEL.md, BUG-B | — | sha256 `30A07E5F…B9A45A` |
| ENV-003 | 2026-08-14 | C (R1) | Is git run inside the WorkBuddy sandbox? | `assert-native-workbuddy-context.ps1` | ancestry reaches `sandbox-cli.exe` (R1) / `WorkBuddy.exe` (R2, session id present) | PROVEN | HIGH | `work/native-runs/…/context-assert.txt` | BUG-B, ENVIRONMENT-MODEL | — | R1 session id ABSENT→UNKNOWN; R2 session id PRESENT→YES; both prove native ancestry |
| NPM-001 | 2026-08-13 | A/C | Does normal `npm ci` succeed? | Mavis lab Phase 2 NORMAL | exit 0, 92 files, REMOVED=0 | PROVEN | CONFIRMED | `report/results-npm-ci.txt`, `report/sanitized-evidence.md §E.3` | BUG-A | — | baseline control |
| NPM-002 | 2026-08-13 | A/C | Does shim-active `npm ci` fail? | Mavis lab Phase 2 SHIM | exit 1, `SAFE_DELETE_BULK_CONFIRM_REQUIRED {count:59,threshold:20,scope:turn}` | REPRODUCED | CONFIRMED | `report/results-npm-ci.txt`, `report/sanitized-evidence.md §E.3` | BUG-A | — | synthetic `parse5@8.0.1`+`entities@8.0.0` |
| NPM-003 | 2026-08-13 | A/C | Is the failure non-atomic? | shim report capture | `.package-lock.json` trashed (count=1) BEFORE bulk-guard fires on `entities` (count=59) | PROVEN (smoking gun) | CONFIRMED | `report/results-npm-ci.txt` `NPM_CI_PHASE2_SHIM_TRASH_EVENT`, `report/sanitized-evidence.md §E.3` | BUG-A | — | partial mutation proven |
| NPM-004 | 2026-08-13 | A/C | Which components? | static read of shim + guard | `genie-safe-delete.cjs` patches `fs.rmSync` etc.; `safe-delete-bulk-guard.cjs` throws at threshold 20 | CONFIRMED (component) | CONFIRMED | `report/sanitized-evidence.md §A,§B` | BUG-A | — | sha256 both pinned |
| NPM-005 | 2026-08-13 | A/C | Is the Node shim the cause of Bug A? | A/B shim injection | shim on = fail; shim off = pass | PROVEN | CONFIRMED | `report/BUG-REPORT-TENCENT.md` Issue A | BUG-A | — | |
| GIT-001 | 2026-08-10/13 | D/A | Do tracked files vanish after switch/merge? | user audit log (5+ events) | ` D` lines, HEAD/index/blob intact, recovered via `git restore --worktree` | OBSERVED FACT | HIGH | `report/sanitized-evidence.md §F` | BUG-B, NATURAL-INCIDENT-F1 | — | recurring pattern |
| GIT-002 | 2026-08-13 | A/C | Does Node shim alone cause Bug B? | Mavis lab Git A/B SHIM-ONLY (11/11 CLEAN) | 11/11 `WORKTREE_CHECK_VERDICT=CLEAN` | NEGATIVE CONTROL / FALSIFIED (shim-cause) | CONFIRMED | `report/results-git-shim-only.txt`, `report/sanitized-evidence.md §E.4` | BUG-B | — | **Node shim ruled out for Bug B** |
| GIT-003 | 2026-08-14 | C (R1) | Can Bug B be reproduced natively? | WorkBuddy-native PROBE_B (F1-shape) | **reproduced** `WORKTREE_ONLY_LOSS`, 59 unrelated tracked files, HEAD/index intact, HEAD_TREE==INDEX_TREE, fsck healthy | REPRODUCED | CONFIRMED | `report/NATIVE-R1-EVIDENCE.md` (RAW_LOCAL_SOURCE: `work/native-runs/2026-08-14T21-43-52Z-8d51e361d168/PHASE1_FINAL_REPORT.md` — NOT AVAILABLE IN PUBLIC REPO) | BUG-B | — | SYNTHETIC_NATIVE_REPRODUCTION=CONFIRMED |
| GIT-004 | 2026-08-14 | C (R1-repair) | Where in build does loss occur? | R1 repair rerun (CASE A) | R1 observed non-clean worktree at post-final-checkout checkpoint but lacked a physical pre-final-checkout checkpoint, so the exact causal operation was NOT localized (CASE A "localized to final `git checkout master`" claim retracted) | RETRACTED (no localization achieved) | UNRESOLVED | `report/NATIVE-R1-EVIDENCE.md` (retraction note; RAW_LOCAL_SOURCE: `work/native-runs/2026-08-14T15-32-33Z-jf10pgjgdoiu/REPAIR_FINAL_REPORT.md` — NOT AVAILABLE IN PUBLIC REPO) | BUG-B | — | GIT_COMPONENT_CAUSE=UNRESOLVED |
| GIT-005 | 2026-08-15 | C (R2) | Reproduce again with 4 checkpoints? | R2 four-checkpoint harness | A/B/C/D all CLEAN, loss NOT reproduced in one controlled run | NEGATIVE CONTROL (this run) | CONFIRMED | `report/NATIVE-R2-EVIDENCE.md` (RAW_LOCAL_SOURCE: `work/native-runs/2026-08-15T06-51-51Z-c7de59f17452/REPAIR_R2_FINAL_REPORT.md` — NOT AVAILABLE IN PUBLIC REPO) | BUG-B | — | INTERMITTENT across runs |
| GIT-006 | 2026-08-15 | C (R2) | Which component causes Bug B? | synthesis of R1+R2 | no direct component-level evidence in either run | UNKNOWN (component) | UNRESOLVED | `report/NATIVE-R1-EVIDENCE.md` / `report/NATIVE-R2-EVIDENCE.md` (causal language) | BUG-B | — | not attributable to a specific file |
| GIT-007 | 2026-08-13→15 | A/C | Is the tsbx kernel filter the cause? | inference from policy + negative controls | leading candidate mechanism consistent with all facts; not directly observed denying an op (HIGH_CONFIDENCE_HYPOTHESIS, not established as the cause) | HIGH_CONFIDENCE_HYPOTHESIS | HIGH | `report/ROOT_CAUSE_CLOSURE_REPORT.md §B`, `report/NATIVE-R2-EVIDENCE.md` | BUG-B | — | do NOT upgrade to CONFIRMED |
| GIT-008 | 2026-08-15 | C (R2) | Is the loss WorkBuddy-associated? | native ancestry + R1 repro + R2 clean run | loss only under WorkBuddy-native chain; never from non-WB shell | OBSERVED_ASSOCIATION = STRONG | VERY_HIGH | `report/NATIVE-R2-EVIDENCE.md` (`WORKBUDDY_RUNTIME_ASSOCIATION=VERY_HIGH`, `OBSERVED_ASSOCIATION=STRONG`) | BUG-B, EXECUTIVE-SUMMARY | — | |
| F1-001 | 2026-08-14 | D | F1 natural incident shape? | `zhihu-grabber-toolkit` `git merge --ff-only` | 3-path delta (1 mod src + 1 add test + 1 mod test), 0 deletions; 18 unrelated test files missing | OBSERVED FACT | CONFIRMED | `report/NATURAL-INCIDENT-F1.md` | NATURAL-INCIDENT-F1, BUG-B | — | GitHub compare API verifies 3-path delta |
| F1-002 | 2026-08-14 | D | Recoverable? | `git restore --worktree -- zhihu-answer-grabber/test/` | all 18 recovered; no reset/clean/stash/history rewrite | PROVEN | CONFIRMED | `report/NATURAL-INCIDENT-F1.md` | NATURAL-INCIDENT-F1 | — | proves worktree-only |
| WB-R1-001 | 2026-08-14 | C (R1) | Native baseline harness valid? | GATE 0 + context + probes | GATE0=PASS; Probe A build interference (separate signal); Probe B repro | PROVEN (harness) | CONFIRMED | `report/NATIVE-R1-EVIDENCE.md` (RAW_LOCAL_SOURCE: `work/native-runs/2026-08-14T21-43-52Z-8d51e361d168/PHASE1_FINAL_REPORT.md` — NOT AVAILABLE IN PUBLIC REPO) | BUG-B | — | |
| WB-R2-001 | 2026-08-15 | C (R2) | Localize CLEAN→NON_CLEAN interval? | four-checkpoint build harness | A/B/C/D instrumented; all CLEAN in this run; harness proven correct | PROVEN (harness) | CONFIRMED | `report/NATIVE-R2-EVIDENCE.md`, `build-git-probe-f1-shape.ps1` (RAW_LOCAL_SOURCE: `work/native-runs/2026-08-15T06-51-51Z-c7de59f17452/REPAIR_R2_FINAL_REPORT.md` — NOT AVAILABLE IN PUBLIC REPO) | BUG-B | — | reviewer PASS |
| WB-REV-001 | 2026-08-15 | Independent | Was R2 harness reviewable? | independent reviewer | R2 HARNESS REVIEW = PASS; overclaim corrections applied | PROVEN | CONFIRMED | `report/INVESTIGATOR-CONTRIBUTIONS.md` | EXECUTIVE-SUMMARY | — | gates publication |
| ENV-004 | 2026-08-14 | D/A | `ModifyBackup` rule present? | sandbox config observation | `ModifyBackup enabled=true method=ipc max 100MB`; `$RECYCLE.BIN` `inherit_user` | OBSERVED FACT | MEDIUM | `report/NATURAL-INCIDENT-F1.md` env facts | ENVIRONMENT-MODEL, BUG-B | — | routing not directly observed |
| GIT-009 | 2026-08-14 | C (R1) | Is loss persistent across checkout-back? | Probe B step-1b | after switching back to master, 59 files STILL missing; not self-healing | PROVEN | CONFIRMED | `report/NATIVE-R1-EVIDENCE.md` (RAW_LOCAL_SOURCE: `work/native-runs/2026-08-14T21-43-52Z-8d51e361d168/PHASE1_FINAL_REPORT.md` — NOT AVAILABLE IN PUBLIC REPO) | BUG-B | — | distinguishes from transient scm state |

---

## Category counts (for completeness gate)

- OBSERVED FACT: GIT-001, GIT-008(assoc), F1-001, F1-002, ENV-001/002/004
- PROVEN: ENV-002/003, NPM-001/002/003/004, GIT-002(neg), GIT-003, GIT-009, WB-R1-001, WB-R2-001, WB-REV-001
- REPRODUCED: NPM-002, GIT-003
- NEGATIVE CONTROL: GIT-002 (shim), GIT-005 (R2 clean)
- FALSIFIED: GIT-002 (Node-shim-causes-B)
- HIGH_CONFIDENCE_INFERENCE: GIT-007 (tsbx filter hypothesis)
- RETRACTED: GIT-004 (prior CASE A "localized to final `git checkout master`" claim — no pre-final-checkout checkpoint existed, so the exact causal operation was not localized)
- HYPOTHESIS: GIT-007
- UNKNOWN: GIT-006

No category is silently merged into another.
