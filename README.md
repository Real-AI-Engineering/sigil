# Sigil

Risk-adaptive development pipeline with adversarial consensus code review for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

## What It Does

4-phase pipeline that scales review rigor to match task complexity:

- **Scope** — deterministic precompute: branch creation, risk assessment, agent planning (zero LLM)
- **Explore** — codebase mapping with parallel sonnet agents
- **Design** — architecture doc with user approval gate (opus for medium/high risk)
- **Build** — implementation + test execution + observer + adversarial code review

3 review strategies, auto-selected by risk level:

| Strategy | When | Agents | Rounds | Codex |
|----------|------|--------|--------|-------|
| simple | low risk | 1 reviewer | 1 | fallback only |
| adversarial | medium risk | Reviewer + Skeptic (blind parallel) | 1 | no |
| consensus | high risk | Reviewer + Skeptic | 1-2 + tiebreaker | yes |

## Install

```bash
claude plugin install Real-AI-Engineering/sigil
```

## Quick Start

```
/sigil add user authentication with JWT
```

The pipeline will:
1. Assess risk and create a feature branch
2. Explore the codebase with parallel agents
3. Design the implementation (requires your approval)
4. Build, test, review, and present a summary

## How It Works

```
┌─────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  Scope  │───>│ Explore  │───>│  Design  │───>│  Build   │
│ (bash)  │    │ (sonnet) │    │(son/opus)│    │ (sonnet) │
└─────────┘    └──────────┘    └──────────┘    └──────────┘
 risk=low:      1 agent         sonnet          1 impl
 risk=med:      2 agents        opus            2 impl + observer
 risk=high:     3 agents        opus            3 impl + observer + Codex
```

Each phase writes a structured artifact to `.dev/`:
- `scope.json` — risk level, agent counts, review strategy
- `exploration.md` — codebase map, patterns, constraints
- `design.md` — architecture, files, test plan, risks
- `review-verdict.md` + `review-summary.json` — review results

Post-checks validate each artifact before proceeding.

## Review Strategies

**Simple** — single code reviewer. Fast, cheap. Auto-selected for low-risk changes.

**Adversarial** — two agents review the same diff blind:
- *Reviewer*: finds code bugs, security issues, logic errors
- *Skeptic*: finds spec gaps, missing tests, hallucinated functionality
- Findings machine-validated (file exists, line range, evidence grep, scope check)
- Deduplication across agents

**Consensus** — adversarial + escalation:
- If Reviewer and Skeptic disagree (PASS vs BLOCK), Round 2 runs
- Both agents re-review with merged findings
- Codex CLI acts as tiebreaker if still blocked

## Cost Estimates

| Strategy | Agents | Est. Cost | Latency |
|----------|--------|-----------|---------|
| simple | 1 | ~$0.03-0.05 | 1-2 min |
| adversarial | 2 | ~$0.10-0.20 | 3-5 min |
| consensus | 2-4 + Codex | ~$0.20-0.40 | 5-10 min |

Costs are approximate and depend on diff size and codebase complexity.

## Optional: Codex Integration

Sigil optionally uses [Codex CLI](https://github.com/openai/codex) for:
- **Design review** (high risk) — independent second opinion on architecture
- **Tiebreaker** (consensus) — breaks deadlock between Reviewer and Skeptic
- **Fallback reviewer** (simple) — when feature-dev:code-reviewer is unavailable

If Codex is not installed, Sigil degrades gracefully — all Codex steps are skipped with a logged reason. The `codex_status` field in `.dev/review-summary.json` tracks what happened: `ok`, `not_installed`, `auth_expired`, `timeout`, `error`, or `skipped`.

Install Codex: `npm install -g @openai/codex`

## Session Resume

If you interrupt a `/sigil` session, the pipeline detects existing `.dev/` artifacts on restart and offers:
- **resume** — continue from the next incomplete phase
- **restart** — clear artifacts, start fresh
- **abort** — stop

Run history is archived to `.dev/runs/<timestamp>/` after each completed build.

## Configuration (v2 Roadmap)

Coming in v2:
- `.sigil.json` project overrides (custom risk thresholds, review strategy, agent counts)
- Configurable timeouts and cost limits

## License

MIT
