# Signum — AI Agent Instructions

Signum is a Claude Code plugin that implements evidence-driven development:
contract-first spec, multi-model audit (Claude + Codex + Gemini), and
tamper-evident proofpacks.

## Architecture

- `commands/` — slash commands (entry points: `/signum`, `/signum:init`)
- `agents/` — subagents (contractor, engineer, reviewer-claude, synthesizer)
- `lib/` — shared shell modules (contract, audit, proofpack, policy scanner)
- `tests/` — test suite (run with `bash tests/run.sh`)
- `modules.yaml` — agent/skill/hook declarations

## Conventions

- Shell (bash 4+) for all pipeline code — no external runtimes required
- JSON for structured data (contract.json, proofpack manifests)
- Deterministic outputs: same input must produce same contract hash
- All file paths relative to project root
- Error messages go to stderr, structured output to stdout

## Contributing

- Bug fixes: include a failing test case
- New agents: must declare tools explicitly in frontmatter
- Security findings: open a private advisory, not a public issue
- Keep shell portable — no bashisms beyond bash 4.0
