# Diff Progression for Iterative AUDIT

**Date:** 2026-03-15
**Status:** Draft
**Inspiration:** ralphex (umputun/ralphex) — first iteration shows full branch diff, subsequent iterations show only uncommitted delta

## Problem

In iterative AUDIT, reviewers see the full `combined.patch` (entire feature diff from base) on every iteration. On iteration 5 of a 500-line feature, the reviewer re-reads all 500 lines to find whether a 12-line fix resolved the previous finding. This causes:

1. **Reviewer noise** — re-discovering old issues that were already accepted or are outside the fix scope
2. **Wasted tokens** — Opus/GPT-5.4/Gemini process the full diff every time (~$0.10-0.30 per review)
3. **Slow convergence** — findings that aren't about the fix delay resolution
4. **Context dilution** — the actual fix is buried in hundreds of unchanged lines

## Solution

Provide reviewers with **two artifacts** starting from iteration 2:

1. `combined.patch` — full feature diff from base (unchanged, for full context)
2. `iteration_delta.patch` — only what changed since the previous best candidate

The reviewer prompt instructs: "Focus your review on the delta. Use the full patch for context only."

## Design

### Delta Computation

After engineer produces a fix and before launching reviews:

```bash
# Compute delta: diff between best candidate and current candidate
if [ "$CURRENT_ITERATION" -gt 1 ] && [ -f ".signum/iterations/$(printf '%02d' $BEST_ITERATION)/combined.patch" ]; then
  # Create temp files with applied states
  BEST_PATCH=".signum/iterations/$(printf '%02d' $BEST_ITERATION)/combined.patch"
  CURRENT_PATCH=".signum/combined.patch"

  # Diff the two patches to get what changed
  # Method: apply best patch to base, save state; apply current patch to base, diff the two
  BASE=$(jq -r '.base_commit' .signum/execution_context.json)

  # Simple approach: diff the patch files themselves (shows what lines were added/removed/changed)
  diff -u "$BEST_PATCH" "$CURRENT_PATCH" > .signum/iteration_delta.patch 2>/dev/null || true

  DELTA_LINES=$(wc -l < .signum/iteration_delta.patch 2>/dev/null || echo 0)
  echo "Delta patch: $DELTA_LINES lines (vs $(wc -l < "$CURRENT_PATCH") full patch)"
else
  # First iteration or no previous — no delta
  rm -f .signum/iteration_delta.patch
fi
```

**Better approach** — diff the applied states, not the patches:

```bash
if [ "$CURRENT_ITERATION" -gt 1 ]; then
  BEST_DIR=".signum/iterations/$(printf '%02d' $BEST_ITERATION)"
  if [ -f "$BEST_DIR/combined.patch" ]; then
    # Generate delta: what changed from best candidate to current candidate
    # Use git diff between two applied states via temp worktree comparison
    BASE=$(jq -r '.base_commit' .signum/execution_context.json)

    # Apply best patch to get its file state, then diff against current working tree
    DELTA_DIR=$(mktemp -d)
    git archive "$BASE" | tar -x -C "$DELTA_DIR"
    (cd "$DELTA_DIR" && git apply "$OLDPWD/$BEST_DIR/combined.patch" 2>/dev/null || true)

    # Diff best-applied state vs current working tree (only inScope files)
    diff -ruN "$DELTA_DIR" . --exclude='.signum' --exclude='.git' > .signum/iteration_delta.patch 2>/dev/null || true
    rm -rf "$DELTA_DIR"

    DELTA_LINES=$(wc -l < .signum/iteration_delta.patch 2>/dev/null || echo 0)
    echo "Delta: $DELTA_LINES lines changed from iteration $BEST_ITERATION"
  fi
fi
```

**Simplest practical approach** — engineer generates delta as part of repair:

Since the engineer starts from the best candidate (after rollback), `git diff` at the end of repair IS the delta. We just need to capture it separately:

```bash
# After engineer completes repair and before generating combined.patch:
# The working tree diff IS the iteration delta (engineer started from best candidate)
git diff > .signum/iteration_delta.patch
# Then generate full combined.patch from base
git diff $BASE > .signum/combined.patch
```

This is the cleanest approach. The engineer always starts from the best candidate state (after rollback), so `git diff` (unstaged changes) = exactly what the fix changed.

### Reviewer Prompt Changes

**Pass 1** (no delta available):
```
Review the full diff against the contract requirements.
[existing prompt unchanged]
```

**Pass 2+** (delta available):
```
Review this code change. Two diffs are provided:

1. FULL DIFF (complete feature from base):
{combined_patch}

2. DELTA (what changed in this fix iteration):
{iteration_delta}

FOCUS your review on the DELTA — these are the changes made to fix previous findings.
Use the full diff only for context (understanding how the delta fits into the larger change).
Do NOT re-report findings about code in the full diff that was NOT changed in the delta.
Only report NEW issues introduced by the delta, or issues in the delta that fail to fix the reported problem.
```

### Storage

```
.signum/
  iteration_delta.patch          # current delta (working copy)
  iterations/
    01/
      combined.patch             # full diff (no delta for pass 1)
    02/
      combined.patch             # full diff
      iteration_delta.patch      # what changed from iteration 01
    03/
      combined.patch
      iteration_delta.patch      # what changed from best candidate
```

### Review Template Changes

Add `{iteration_delta}` template variable to all review templates. Templates already have `{diff}` for the full patch.

For `review-template.md` (Claude):
- Pass `iteration_delta` alongside `contract_json`, `diff`, `mechanic_report`
- If delta is empty or absent, reviewer falls back to full-diff-only behavior

For `review-template-security.md` and `review-template-performance.md` (Codex/Gemini):
- Add delta to the prompt with the "FOCUS on delta" instruction
- External CLIs get both in a single prompt

### Impact on Convergence

Expected improvements:
- **Fewer false re-discoveries** — reviewer won't flag the same line 42 issue on iteration 5 if it wasn't changed
- **Faster token processing** — delta is typically 10-50 lines vs 200-500 full patch
- **More targeted findings** — findings directly related to the fix, not the whole feature
- **Better fix quality signal** — clear whether the fix actually addressed the previous finding

### Edge Cases

1. **Rollback changes the base** — delta is always computed from the ACTIVE best candidate, not the previous iteration. If rollback happened, delta reflects "what's different from the best candidate."
2. **First iteration** — no delta, full diff only. Business as usual.
3. **Engineer creates entirely new files** — delta shows the new file. Full patch also shows it. No conflict.
4. **Delta is empty** — engineer made no changes (repair failed or no-op). This triggers the existing "REPAIR_SKIP" path.
5. **Delta is larger than full patch** — theoretically impossible since delta is a subset of the full change. If it happens due to rollback artifacts, fall back to full-diff-only review.

## Files to Modify

| File | Change |
|------|--------|
| `commands/signum.md` | Capture `iteration_delta.patch` after repair, pass to reviewers |
| `agents/reviewer-claude.md` | Add delta-aware review instructions |
| `lib/prompts/review-template.md` | Add `{iteration_delta}` variable and focus instructions |
| `lib/prompts/review-template-security.md` | Same |
| `lib/prompts/review-template-performance.md` | Same |
| `agents/synthesizer.md` | No changes needed (reads findings, not diffs) |

## What Does NOT Change

- Scoring formula
- Best-of-N logic
- Rollback mechanism
- Proofpack assembly (embeds full combined.patch, not delta)
- Holdout validation (tests behavior, not diff)
- Mechanic (runs checks, not diff-dependent)
