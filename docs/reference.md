# Sigil Reference

## Usage

```
/sigil <feature description>
```

Sigil parses the feature description and runs the full pipeline automatically.

## Examples

### Simple feature (low risk)

```
/sigil add a health check endpoint to the API
```

Pipeline: 1 explore agent → sonnet design → 1 build agent → simple review (1 reviewer).
Estimated time: 1-2 minutes. Cost: ~$0.05-0.10.

### Authentication (medium risk)

```
/sigil add user authentication with JWT tokens
```

Pipeline: 2 explore agents → opus design (approval gate) → 2 build agents + observer → adversarial review (Reviewer + Skeptic + optional Codex).
Estimated time: 3-5 minutes. Cost: ~$0.15-0.30.

### Database migration (high risk)

```
/sigil migrate user table from MongoDB to PostgreSQL
```

Pipeline: 3 explore agents → opus design (approval gate) → 3 build agents + observer → consensus review (Reviewer + Skeptic + Codex + Gemini + Round 2 if needed).
Estimated time: 5-10 minutes. Cost: ~$0.30-0.60.

### Interrupt and resume

```
# Start a pipeline
/sigil refactor the payment module

# ...interrupt (Ctrl+C or close session)...

# Reopen and run the same command
/sigil refactor the payment module
# Sigil detects .dev/ artifacts and asks: resume / restart / abort
```

### Skip external providers

When prompted for external provider consent:
```
> Send diff to external providers for review? (yes/skip-external)
skip-external
```

Review continues with Claude agents only.

### Force simple review

For quick iterations where you don't need full adversarial review:
```
/sigil fix typo in README
```

Low-risk descriptions automatically use simple review (1 reviewer, no external providers).

## Artifacts

All artifacts are stored in `.dev/` (auto-added to `.gitignore`):

| File | Phase | Contents |
|------|-------|----------|
| `scope.json` | Scope | Risk level, agent counts, review strategy, branch name |
| `exploration.md` | Explore | Codebase map, patterns, constraints, relevant files |
| `design.md` | Design | Architecture, file changes, test plan, risks |
| `review-diff.txt` | Build | Full git diff used for review |
| `review-verdict.md` | Build | Review findings, verdicts, recommendations |
| `review-summary.json` | Build | Machine-readable review results |
| `runs/<timestamp>/` | Archive | Previous run artifacts |

## Review Output Format

### review-summary.json

```json
{
  "verdict": "PASS|WARN|BLOCK",
  "strategy": "simple|adversarial|consensus",
  "risk": "low|medium|high",
  "findings": [
    {
      "id": "F001",
      "file": "src/auth.ts",
      "line_start": 42,
      "line_end": 45,
      "severity": "critical|important|informational",
      "category": "bug|security|performance|spec-gap|missing-test",
      "description": "...",
      "evidence": "...",
      "sources": ["reviewer", "codex"],
      "validated": true
    }
  ],
  "providers": {
    "reviewer": { "status": "ok", "findings_count": 3 },
    "skeptic": { "status": "ok", "findings_count": 2 },
    "codex": { "status": "ok|not_installed|auth_expired|timeout|error|skipped" },
    "gemini": { "status": "ok|not_installed|auth_expired|timeout|error|skipped" }
  }
}
```

## Requirements

| Dependency | Required | Version | Purpose |
|-----------|----------|---------|---------|
| Claude Code | Yes | v2.1.47+ | Runtime environment |
| git | Yes | any | Branch management, diffs |
| jq | Yes | any | Scope parsing, post-checks |
| Codex CLI | No | any | External review (medium/high risk) |
| Gemini CLI | No | any | External review (high risk) |

## Troubleshooting

### `jq: command not found`

Install jq:
- macOS: `brew install jq`
- Ubuntu/Debian: `apt install jq`
- Other: [jq downloads](https://jqlang.github.io/jq/download/)

### External provider auth errors

```
codex: auth expired → run: codex auth
gemini: auth expired → run: gemini login
```

Sigil continues without the provider if auth fails.

### Provider timeout

External providers are killed after 120 seconds. The review continues with remaining providers. Check `.dev/review-summary.json` for provider status.

### `.dev/` exists from previous run

Normal behavior. Sigil detects existing artifacts and offers:
- **resume**: continue from next incomplete phase
- **restart**: clear artifacts, start fresh
- **abort**: stop without changes

### Plugin not loading

1. Verify the command file exists:
   ```bash
   ls ~/.claude/plugins/sigil/commands/sigil.md
   ```
2. Check `~/.claude/settings.json` has `"sigil@local": true` in `enabledPlugins`
3. Open a new Claude Code session (plugins load at session start)

### Review finds too many issues

For iterative development, low-risk descriptions trigger simple review (1 reviewer). Use specific, focused descriptions to keep risk assessment accurate.

## Cost Estimates

Costs depend on diff size, codebase complexity, and model pricing. Rough estimates:

| Strategy | Claude Tokens | External Calls | Total Est. |
|----------|--------------|----------------|------------|
| simple | ~10K-30K | 0 | $0.05-0.10 |
| adversarial | ~30K-80K | 1 (Codex) | $0.15-0.30 |
| consensus | ~60K-150K | 2 (Codex + Gemini) | $0.30-0.60 |

These are Claude Code API costs only. External provider costs depend on your Codex/Gemini subscription.
