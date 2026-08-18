# Vendor confirmation — Bug A

**Date:** 2026-08-18  
**Vendor:** Tencent WorkBuddy  
**Channel:** Tencent Cloud support ticket  
**Public disclosure basis:** the support engineer explicitly stated that the log-analysis conclusions may be quoted publicly.

## Status

```text
VENDOR_CONFIRMED=YES
REPRODUCED=YES
PRODUCT_CAUSE=CONFIRMED
COMPONENT_CAUSE=CONFIRMED
ROOT_CAUSE_COMPONENT=WorkBuddy safe-delete
PACKAGE_MANAGER_IMPACT=CONFIRMED
NON_ATOMIC_PARTIAL_MUTATION=STRONGLY_SUPPORTED
FIX_STATUS=UNKNOWN / VENDOR PRODUCT TEAM ANALYZING
```

## Vendor-confirmed conclusion

After reviewing the submitted WorkBuddy client logs and the public reproduction materials, a Tencent Cloud support engineer handling the WorkBuddy case stated that the reported issue is real and that the root cause is in the **safe-delete component injected by the WorkBuddy sandbox**.

The engineer later confirmed that the author may publicly quote the conclusions of that log analysis. This record therefore summarizes only those conclusions and does **not** publish private ticket contents, customer logs, signed attachment URLs, internal ticket identifiers, or personal information.

This is a vendor confirmation of the technical finding. It is **not** an endorsement by Tencent of this repository or its author.

## Public screenshot evidence

A sanitized composite screenshot of the support conversation is published in GitHub Issue #1. It preserves three points while removing ticket/account/contact identifiers and private support metadata:

1. Tencent WorkBuddy engineering confirmed that the reported issue is real and that the root cause is in WorkBuddy's sandbox-injected `safe-delete` component.
2. The production client logs independently corroborated package-manager failures caused by `SAFE_DELETE_BULK_CONFIRM_REQUIRED`.
3. The support engineer explicitly permitted the author to publicly quote the conclusions of the log analysis.

- Issue: https://github.com/FlapPearLabs/workbuddy-safedelete-rootcause/issues/1
- Permanent screenshot comment: https://github.com/FlapPearLabs/workbuddy-safedelete-rootcause/issues/1#issuecomment-5328612341
- Stable GitHub attachment: https://github.com/user-attachments/assets/84670e34-57f2-428d-8c79-18cb5c41038f
- Sanitized composite SHA256: `37e2d9c76d3d1549a59811b08047f730674785cc7228f31cfdf208e2234c059d`

The original uncropped support conversation remains private. The published image is a sanitized derivative, not the raw ticket record.

## What Tencent verified from the submitted logs

### 1. safe-delete injection exists in production WorkBuddy sessions

The engineer reported two injection paths in the customer logs:

- `NODE_OPTIONS=--require=.../genie-safe-delete.cjs` — patches Node filesystem deletion entry points at process startup.
- `BASH_ENV=.../safe-delete-bash-env.sh` — rewrites shell-side delete commands such as `rm` / `unlink` / `rmdir` through WorkBuddy wrappers.

The production logs also contained:

```text
CODEBUDDY_SAFE_DELETE_BULK_GUARD=...safe-delete-bulk-guard.cjs
CODEBUDDY_SAFE_DELETE_BULK_THRESHOLD=50
GENIE_TRASH_DIR=.../genie-trash
```

The public external reproduction in this repository used a shim build whose observed threshold was `20`. Tencent explicitly noted that the production threshold was `50` and that this numeric difference does **not** change the identified failure mechanism.

### 2. Package-manager cleanup triggered the same bulk-guard failure in production logs

Tencent reported that the submitted logs directly contained package-manager failures in a WorkBuddy sandbox session. In one observed `pnpm install` run on 2026-08-14, the command exited with code `1` and ended with:

```text
[safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED]
count=10006
threshold=50
scope=turn
```

A retry shortly afterwards again exited `1` with a cumulative count above `10000`.

Tencent stated that this matches the mechanism demonstrated by the repository's `npm ci` reproduction: the package manager performs legitimate high-volume cleanup, while WorkBuddy's safe-delete bulk guard treats the accumulated deletion count as requiring confirmation and aborts the command.

### 3. Non-atomic partial mutation is strongly supported

Tencent was explicit about the evidence boundary here.

The exported WorkBuddy log bundle did **not** contain the detailed `codebuddy-safe-delete/report-*.jsonl` files from the local Temp directory, so Tencent could not independently reconstruct the exact per-file ordering of:

```text
.package-lock.json trashed
        ↓
bulk guard fires
        ↓
npm ci aborts
```

However, the engineer described the non-atomic interpretation as strongly supported by three independent observations:

1. `scope=turn` means the bulk counter is cumulative during the session rather than a single preflight decision before cleanup begins.
2. The customer logs contain repeated later cleanup commands such as removal of `node_modules`, lockfiles, and related leftovers after failed package-manager operations, which is consistent with an interrupted partial-cleanup state.
3. The public fresh-clone A/B in this repository independently observed the `.package-lock.json` trash event before the later bulk-guard abort.

Therefore the repository keeps the following evidence boundary:

```text
ROOT_CAUSE_COMPONENT=WorkBuddy safe-delete          # vendor confirmed
PACKAGE_MANAGER_ABORT=CONFIRMED                     # vendor logs + public repro
EXACT_TRASH_BEFORE_ABORT_ORDERING=PUBLIC_REPRO      # not independently reconstructed from exported vendor logs
NON_ATOMIC_PARTIAL_MUTATION=STRONGLY_SUPPORTED
```

## Vendor workaround

Until a product fix is available, Tencent recommended:

1. Prefer running `npm ci` / `pnpm install` from a normal system Git Bash, PowerShell, or `cmd`, outside the WorkBuddy embedded shell, so the WorkBuddy safe-delete injection is not present.
2. If `SAFE_DELETE_BULK_CONFIRM_REQUIRED` has already occurred, do **not** assume `node_modules` is complete. Recreate a clean dependency tree from a non-WorkBuddy shell before trusting later test failures.
3. A local `NODE_OPTIONS` override may bypass the Node-layer shim in some package-manager scenarios, but Tencent noted that this does not bypass the separate Bash-side safe-delete wrapper and is therefore only a temporary workaround, not a full fix.

## Fix status

When asked whether a formal product fix/version had been scheduled, the support engineer said the support team could not confirm a specific repair plan or version at that time. The WorkBuddy product team was continuing to analyze and process defects, and the user was advised to watch WorkBuddy release/update announcements and open a new support ticket for follow-up if needed.

```text
VENDOR_FIX_COMMITTED=UNKNOWN
FIXED_VERSION=TBD
REGRESSION_VERIFICATION=PENDING
```

## Public reproduction and evidence

- Standalone Bug A report: [`BUG-A-NPM-SAFE-DELETE.md`](BUG-A-NPM-SAFE-DELETE.md)
- Structured npm A/B record: [`results-npm-ci.txt`](results-npm-ci.txt)
- Full orchestrator record: [`results-latest.txt`](results-latest.txt)
- One-command repro: [`../bin/repro-all.ps1`](../bin/repro-all.ps1)
- npm-specific repro: [`../bin/repro-npm-ci.ps1`](../bin/repro-npm-ci.ps1)
- Node-delete repro: [`../bin/repro-node-delete.mjs`](../bin/repro-node-delete.mjs)

## Repro chain

```text
Observed package-manager failure
        ↓
Minimal disposable fixture
        ↓
NORMAL vs WorkBuddy-shim A/B
        ↓
Fresh-clone external validation
        ↓
Partial-mutation evidence
        ↓
Submitted WorkBuddy client logs
        ↓
Tencent log analysis
        ↓
Vendor confirms root cause = WorkBuddy safe-delete
        ↓
Product fix / regression verification pending
```

## Disclosure note

The original support conversation and client logs are retained privately. This public record intentionally excludes:

- customer/account identifiers;
- Tencent Cloud ticket identifiers;
- signed COS attachment URLs or tokens;
- local user-profile paths;
- raw WorkBuddy client logs;
- internal or private support metadata.

The public claims above are limited to the conclusions the Tencent Cloud support engineer explicitly permitted the author to quote.
