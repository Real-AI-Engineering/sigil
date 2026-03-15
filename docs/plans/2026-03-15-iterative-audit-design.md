# Iterative AUDIT — Design Plan for Signum v4.2

**Date:** 2026-03-15
**Status:** Draft
**Authors:** Claude + Codex (GPT-5.4) review

## Problem

AUDIT is single-pass. If reviewers find MAJOR/CRITICAL bugs, pipeline stops and human must intervene. Code quality depends on engineer getting it right on first try after EXECUTE.

## Solution

Make AUDIT iterative: review → fix → re-review → repeat until convergence or max iterations. No human in the loop.

## Architecture Decision

Iterative AUDIT is a **loop within Phase 3**, not a new phase. Pipeline stays `CONTRACT → EXECUTE → AUDIT → PACK`. AUDIT internally runs multiple passes, each pass being a full repair subpipeline.

## Flow

```
EXECUTE → engineer produces code → combined.patch
  ↓
AUDIT pass 1:
  scope gate → policy check → mechanic → holdouts →
  AI reviews (risk-proportional) → synthesizer
  → ALL APPROVE, no regressions? → AUTO_OK → PACK ✓
  → MAJOR/CRITICAL findings OR mechanic regression OR holdout failure? ↓

AUDIT-FIX iteration N:
  fresh engineer agent (clean context) → gets repair brief →
  fixes → regenerate combined.patch →
  scope gate → policy check → mechanic → holdouts →
  AI reviews (full, from scratch) → synthesizer
  → ALL APPROVE? → AUTO_OK → PACK ✓
  → worse than best-so-far? → rollback to best candidate → next iteration
  → no improvement 2 iterations in a row? → early stop
  → max iterations reached? → terminal decision

Terminal decision (based on best-of-N candidate):
  → clean                    → AUTO_OK
  → only MINOR remaining     → AUTO_OK + remainingFindings
  → MAJOR remaining          → HUMAN_REVIEW + terminalReason + remainingSeverity
  → CRITICAL remaining       → AUTO_BLOCK
```

## Detailed Design

### 1. Iteration Config

```
SIGNUM_AUDIT_MAX_ITERATIONS=20  (default, configurable)
```

Early stop: if severity-weighted score doesn't improve for 2 consecutive iterations, stop. Best-of-N: pipeline always keeps the best candidate, not the last.

### 2. Repair Subpipeline (per iteration)

Each iteration runs the FULL safety chain, not just engineer + reviews:

1. **Engineer agent** (Sonnet, fresh spawn, clean context)
2. **Regenerate combined.patch** (git diff)
3. **Scope gate** (changed files within inScope)
4. **Policy compliance** (bash_deny_patterns, tool restrictions)
5. **Mechanic** (lint, typecheck, tests vs baseline)
6. **Holdout validation** (if medium/high risk)
7. **AI reviews** (risk-proportional: low=Claude, medium/high=full panel)
8. **Synthesizer** (deterministic verdict)

### 3. Risk-Proportional Review (preserved)

Iterations follow the same risk-proportional ceremony as pass 1:

| Risk | Reviews per iteration |
|------|----------------------|
| Low | Claude (Opus) only |
| Medium | Claude + available externals |
| High | Claude + Codex + Gemini (full panel) |

NOT escalated to full panel on iteration — stays consistent with contract riskLevel.

### 4. Models

| Role | Model | Notes |
|------|-------|-------|
| Engineer (fixer) | Sonnet | Fresh spawn each iteration |
| Claude reviewer | Opus | Always, from agent definition |
| Codex reviewer | GPT-5.4 | From emporium-providers.local.md |
| Gemini reviewer | Config/CLI default | From emporium-providers.local.md |
| Synthesizer | Sonnet | Deterministic rules |

Fresh-reviewer rule (Opus→Sonnet after repair) is **removed**. Review always uses best model.

### 5. What Triggers Next Iteration

Any of:
- MAJOR or CRITICAL reviewer findings
- Mechanic regressions (NEW failures vs baseline)
- Holdout failures or errors

Does NOT trigger:
- MINOR-only findings
- Parse failures alone (treated as unavailable reviewer)

### 6. Engineer Repair Brief

Order matters — deterministic signals first:

```
## Repair Brief (iteration N)

### Deterministic Failures
- Mechanic: lint regression on src/api.ts (was passing, now fails)
- Holdout: 1 failed (category: error handling)
  [NO details, NO scripts, NO expected values]

### Review Findings
- [f1a2b3c4] MAJOR bug src/handler.ts:42 — null dereference when input is empty array
  Evidence: `const first = items[0].name`
- [d5e6f7g8] CRITICAL security src/auth.ts:15 — SQL injection in query builder
  Evidence: `db.query("SELECT * FROM users WHERE id=" + userId)`

### Constraints
- Fix ONLY the listed findings
- Minimal diff — no unrelated refactors
- Do not break already-passing acceptance criteria
- Re-run visible AC verifies after fix
```

### 7. Holdout Sanitization

Engineer NEVER sees holdout details. Sanitized message format:

```
N holdout(s) failed (categories: <list>)
```

Categories derived from holdout description via simple keyword extraction:
- "boundary" / "edge case" / "limit" → boundary input
- "error" / "exception" / "fail" → error handling
- "concurrent" / "race" / "parallel" → concurrency
- "empty" / "null" / "missing" → null/empty input
- fallback → "unspecified"

### 8. Per-Iteration Storage

```
.signum/
  iterations/
    01/
      combined.patch
      mechanic_report.json
      holdout_report.json
      reviews/
        claude.json
        codex.json
        gemini.json
      audit_summary.json
      repair_brief.json      # what was sent to engineer
    02/
      ...
  audit_iteration_log.json   # summary of all iterations
```

Each iteration's artifacts stored separately. No overwrites. Working copies in `.signum/` still updated for compatibility.

### 9. Best-of-N with Rollback

Score each iteration deterministically:

```
score = -(criticals * 1000) - (mechanic_regressions * 500)
        - (holdout_failures * 200) - (majors * 50) - (minors * 1)
```

Higher = better (0 = perfect).

Rules:
- Track `best_score` and `best_iteration`
- If iteration N score < best_score: rollback working tree to best candidate's patch before next iteration
- Final proofpack packages the **best candidate**, not the last attempt
- `audit_iteration_log.json` records all iterations including rollbacks

### 10. Finding Fingerprints

Stable ID for cross-iteration tracking:

```
fingerprint = sha256(category + file + normalized_comment)[:8]
```

- Severity NOT in hash (drifts between models/iterations)
- `normalized_comment` = lowercase, strip whitespace, remove line numbers
- Synthesizer tracks: resolved (was in N-1, not in N), persisting (in both), new (only in N)

### 11. Terminal Verdicts (NO new verdict type)

Keep existing 3 verdicts. Add metadata fields to audit_summary:

```json
{
  "decision": "HUMAN_REVIEW",
  "iterationsUsed": 4,
  "iterationsMax": 20,
  "earlyStop": true,
  "earlyStopReason": "no improvement for 2 consecutive iterations",
  "bestIteration": 3,
  "terminalReason": "1 MAJOR finding persists after 4 iterations",
  "remainingSeverity": "MAJOR",
  "remainingFindings": [...],
  "resolvedFindings": [...],
  "ciRecommendation": "review remaining MAJOR finding manually"
}
```

Terminal mapping:
| Best candidate state | Decision |
|---------------------|----------|
| Clean (all APPROVE, no regressions) | AUTO_OK |
| Only MINOR remaining | AUTO_OK + remainingFindings |
| MAJOR remaining | HUMAN_REVIEW + metadata |
| CRITICAL remaining | AUTO_BLOCK |

CI strict/relaxed mode decides how to handle HUMAN_REVIEW:
- strict: exit 78 (block)
- relaxed: exit 0 (pass with warning)

### 12. Proofpack Extension

Add to proofpack schema:

```json
{
  "auditIterations": [
    {
      "pass": 1,
      "score": -50,
      "findingsCount": { "critical": 0, "major": 1, "minor": 2 },
      "mechanicRegressions": false,
      "holdoutFailures": 0,
      "decision": "HUMAN_REVIEW"
    },
    {
      "pass": 2,
      "score": -1,
      "findingsCount": { "critical": 0, "major": 0, "minor": 1 },
      "mechanicRegressions": false,
      "holdoutFailures": 0,
      "decision": "AUTO_OK"
    }
  ],
  "bestIteration": 2,
  "resolvedFindings": ["f1a2b3c4"],
  "remainingFindings": []
}
```

Full per-iteration artifacts stored in `.signum/iterations/` but NOT embedded in proofpack (too large). Proofpack embeds summaries only.

### 13. Synthesizer Changes

Synthesizer needs iteration-awareness:

- Read `audit_iteration_log.json` to know iteration number
- Apply same deterministic rules per iteration
- Additional output: `iterationScore`, `resolvedSinceLastPass`, `newSinceLastPass`
- Early stop recommendation: if score didn't improve → set `recommendEarlyStop: true`

### 14. signum-ci.sh Changes

No new exit codes needed:

```
0  — AUTO_OK
1  — AUTO_BLOCK
78 — HUMAN_REVIEW
```

New env vars:
```
SIGNUM_AUDIT_MAX_ITERATIONS — default 20
SIGNUM_AUDIT_TIMEOUT — default 45m (total AUDIT budget, graceful stop)
SIGNUM_CI_RELAXED — if "true", HUMAN_REVIEW maps to exit 0 instead of 78
```

## Files to Modify

| File | Change |
|------|--------|
| `commands/signum.md` | Add iteration loop in Phase 3, repair subpipeline, per-iteration storage |
| `agents/synthesizer.md` | Iteration-aware scoring, early stop, cross-iteration tracking |
| `agents/reviewer-claude.md` | Remove fresh-reviewer rule, always Opus |
| `agents/engineer.md` | Document repair brief format (engineer itself unchanged) |
| `lib/schemas/proofpack.schema.json` | Add auditIterations, resolvedFindings, remainingFindings, metadata fields |
| `lib/signum-ci.sh` | Add SIGNUM_AUDIT_MAX_ITERATIONS, SIGNUM_CI_RELAXED |
| `lib/templates/signum-gate.yml` | Add iteration config vars |
| `docs/how-it-works.md` | Update AUDIT section for iterative flow |
| `docs/reference.md` | Document new env vars, iteration behavior |
| `CHANGELOG.md` | v4.2.0 entry |

### 15. Flaky Test Handling in Mechanic

Add retry logic to mechanic's test runner (Step 3.1):

```bash
# On NEW test failure (not in baseline):
# Retry failing tests up to 2 more times
for failing_test in $NEW_FAILURES; do
  RETRY_PASS=0
  for attempt in 1 2; do
    if run_single_test "$failing_test"; then
      RETRY_PASS=$((RETRY_PASS + 1))
    fi
  done
  if [ $RETRY_PASS -ge 1 ]; then
    # Mixed results → flaky, exclude from regression
    mark_flaky "$failing_test"
  fi
done
```

Flaky state persisted in `.signum/flaky_tests.json`:
```json
{
  "tests": [
    { "name": "test_concurrent_write", "firstSeen": 1, "flipFlops": 2, "status": "knownFlaky" }
  ]
}
```

### 16. Wall-Clock Budget Enforcement

Check before each iteration:

```bash
AUDIT_START=$(date +%s)
TIMEOUT_SECONDS=$((${SIGNUM_AUDIT_TIMEOUT_MINUTES:-45} * 60))
DEADLINE=$((AUDIT_START + TIMEOUT_SECONDS))

# Before each iteration:
NOW=$(date +%s)
if [ $NOW -ge $DEADLINE ]; then
  echo "Wall-clock budget exceeded. Finalizing from best iteration."
  # earlyStop + finalize from bestIteration
fi
```

## Risks

1. **Cost explosion** — mitigated by early stop + best-of-N (won't burn 20 iterations on oscillation)
2. **Holdout leakage** — mitigated by sanitization (category only, no details)
3. **Scope creep in fixes** — mitigated by scope gate + policy check every iteration
4. **Artifact bloat** — mitigated by proofpack embeds summaries, not full iteration artifacts

## Resolved Questions

### Q1: Wall-clock budget

**Yes. Total AUDIT budget, not per-iteration. Default 45m. Graceful stop.**

```
SIGNUM_AUDIT_TIMEOUT=45m  (default, configurable)
```

Behavior:
- Check deadline before starting each repair iteration
- If budget expires mid-iteration: let current iteration finish, then stop
- Finalize from `bestIteration`, write `earlyStopReason: "wall_clock_budget_exceeded"`
- Signum never hard-kills itself — outer CI job timeout (set slightly above 45m) serves as crash protection

Rationale: CI expects `proofpack.json`; hard kill would leave no artifact. Per-iteration timeout is wrong granularity — high-risk passes are naturally slower. Total budget controls runaway runtime.

### Q2: Rollback mechanism

**Restore immutable baseline + re-apply best iteration's `combined.patch`.**

Procedure:
1. `git checkout $BASE_COMMIT -- .` (BASE_COMMIT from `execution_context.json`, captured in Step 2.0)
2. `git apply .signum/iterations/<best>/combined.patch`
3. Regenerate working `.signum/combined.patch`
4. If apply fails → stop, return `HUMAN_REVIEW` with `terminalReason: "rollback_patch_apply_failed"`

Each iteration's `combined.patch` already persisted in `iterations/N/`. No git stash, no worktrees, no temporary commits.

Rejected alternatives:
- git checkout to commits — too dependent on git state, clobbers working tree
- git stash — opaque, operationally brittle
- worktrees — overkill for rollback; save for broader "ephemeral Signum" design

Constraint: iterative AUDIT assumes clean CI checkout or stable baseline.

### Q3: Flaky tests

**Retry + track. No default baseline double-run.**

When mechanic detects a NEW test failure:
1. Retry the failing test(s) **2 more times** (3 total observations)
2. **2 of 3 fail** → real regression, counted in `hasRegressions` and score
3. **Mixed results** (1 of 3 or 2 of 3 pass) → `flaky candidate`, excluded from `hasRegressions` and score
4. Persist in `.signum/flaky_tests.json` (run-local, not committed)
5. If same test flip-flops across iterations → promote to `knownFlaky`
6. If instability is suite-level (not attributable to specific tests) → cap at `HUMAN_REVIEW`

Rationale: current mechanic is single-shot and synthesizer treats any regression as blocking. Without flaky handling, one flaky test can force 20 useless fix iterations. Targeted retry only costs extra time when there's actual instability, unlike mandatory double-run baseline which doubles test cost on every pipeline run.
