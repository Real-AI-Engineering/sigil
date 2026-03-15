# Changelog

## [4.5.0] - 2026-03-15

### Added
- Contract schema v3.6: upstream staleness detection via four new optional fields inside `contextInheritance`:
  - `contextSnapshotHash` (string) — SHA-256 hex digest over concatenated byte contents of `staleIfChanged` files in array order, computed at contract creation time
  - `staleIfChanged` (string[]) — upstream artifact paths whose modification triggers staleness; at minimum includes `project.intent.md` when loaded
  - `stalenessStatus` (enum: `fresh|warning|stale`) — current staleness state updated by the pipeline
  - `stalenessPolicy` (enum: `block|warn`, default `warn`) — action when upstream hash differs
- `upstream_staleness_check` step in Phase 1 CONTRACT (after `adr_relevance_check`): recomputes SHA-256 over `staleIfChanged` paths, compares to `contextSnapshotHash`, emits BLOCK when `stalenessPolicy=block` or WARN when `warn` if hash differs; skips when `staleIfChanged` is absent or empty
- Contractor agent (Phase 4 upstream staleness tracking): automatically populates `staleIfChanged`, `contextSnapshotHash`, `stalenessStatus`, and `stalenessPolicy` at contract creation time when contextInheritance artifacts are loaded

### Changed
- Contract schema bumped to v3.6 (backward compatible with v3.0–v3.5)

## [4.4.0] - 2026-03-15

### Added
- Contract schema v3.5: four new optional fields for cross-contract graph queries:
  - `dependsOnContractIds` (string[]) — ordered dependency edges (user-declared)
  - `supersedesContractIds` (string[]) — obsolescence edges (user-declared)
  - `supersededByContractId` (string) — reverse obsolescence pointer
  - `interfacesTouched` (string[]) — named interfaces/APIs touched by the contract
- Phase 3 cross-contract coherence checks (all WARN-only, non-blocking):
  - `cross_contract_overlap_check`: detects inScope file overlap with active contracts in index.json; writes `overlap_warnings` to `spec_quality.json`
  - `assumption_contradiction_check`: compares assumption text pairs across related contracts for direct contradiction keywords; writes `assumption_warnings` to `spec_quality.json`
  - `adr_relevance_check`: scans `docs/adr/` and `docs/decisions/` for relevant ADRs against inScope paths; warns when `adrRefs` is absent/empty; graceful no-op when directories absent; writes `adr_warnings` to `spec_quality.json`
- Contractor agent documents all four new v3.5 fields with usage guidance

### Changed
- Contract schema bumped to v3.5 (backward compatible with v3.0–v3.4)

## [4.3.0] - 2026-03-15

### Added
- `glossaryVersion` field in contract schema v3.4 (optional string, set from `project.glossary.json`)
- `project.glossary.json` integration: contractor reads `canonicalTerms` and `aliases` from project root; omits `glossaryVersion` when file is absent
- `glossary_check`: deterministic lexical scan of goal, inScope, and AC descriptions for forbidden synonyms; WARN-only, non-blocking, results in `spec_quality.json` `glossary_warnings`
- `terminology_consistency_check`: cross-contract synonym proliferation detection across active contracts in `.signum/contracts/index.json`; WARN-only, non-blocking, skips gracefully when index absent or no active contracts
- Step 1.4 displays `Glossary: loaded (version X, N terms)` or `Glossary: not found`
- `lib/prose-check.sh` extended with `run_glossary_scan` function (accepts contract.json + project.glossary.json paths, exits 0 always)

### Changed
- Contract schema bumped to v3.4 (backward compatible with v3.0–v3.3)

## [4.2.0] - 2026-03-15

### Added
- Project intent layer: contractor reads `project.intent.md` from target project root
- `contextInheritance` block in contract schema v3.3 (projectRef, projectIntentSha256)
- Intent alignment check (LLM-based, medium/high risk, informational)
- Missing project intent blocks medium/high risk tasks with escapable question

## v4.1.0 (2026-03-09)

### Security
- **BREAKING**: Replace `eval` in holdout verification with typed DSL runner
- Zero shell execution in verification path — eliminates code injection risk
- Exec whitelist: only `test`, `ls`, `wc`, `cat`, `jq` allowed

### Added
- Typed verification DSL with primitives: `http`, `exec`, `expect`, `capture`
- `visibility` field on acceptance criteria (`visible` / `holdout`)
- `holdoutManifest` for tamper detection of redacted holdouts
- `trust: "local"` trust model declaration
- Detailed holdout report with per-criterion results
- DSL runner with validation + execution (`lib/dsl-runner.sh`)
- Test suite for DSL runner

### Changed
- Contract schema bumped to v3.1 (backward compatible with v3.0)
- Contractor agent generates DSL verify blocks instead of shell commands
- Engineer contract strips holdout-visibility ACs (not just holdoutScenarios)
- Synthesizer handles detailed holdout report format (results array, errors count)

## [4.0.0] - 2026-03-04

### Changed
- **BREAKING**: proofpack.json schema v3.0 → v4.0
- All artifact fields changed from file path strings to envelope objects with embedded content
- `checksums` top-level field removed (per-artifact sha256 in each envelope)
- `checks.audit_summary` renamed to `checks.auditSummary` (camelCase unification)
- `auditChain` fields renamed: `contract_sha256` → `contractSha256`, `approved_at` → `approvedAt`, `base_commit` → `baseCommit`
- Hash format changed from `sha256:hex` prefix to plain hex string

### Added
- Self-contained proofpack: all artifact contents embedded in single JSON file
- Envelope format: `{ content, sha256, sizeBytes, status, omitReason? }`
- Envelope status field: `present | omitted | error` for each artifact
- Contract redaction: holdouts stripped from embedded content, `fullSha256` preserves original hash
- Diff omit-but-hash: patches >100KB stored as hash + size only
- Dynamic review provider keys (not limited to claude/codex/gemini)
- `signumVersion` and `createdAt` top-level fields
- `baseline` and `executeLog` as first-class proofpack artifacts

## [3.0.0] - 2026-03-03

### Added
- Trustless baseline capture: orchestrator runs lint/typecheck/tests BEFORE Engineer, saves to baseline.json
- Deterministic scope gate: verifies all changed files are within inScope after execute phase
- Holdout scenarios: hidden acceptance criteria in contract that Engineer never sees, run as blind validation
- Adversarial review templates: Codex gets security-focused template, Gemini gets performance-focused template
- Confidence scoring: weighted metric (execution health + baseline stability + review alignment) in audit summary
- Cross-platform sha256: auto-detects sha256sum or shasum (macOS compatibility)
- allowNewFilesUnder field in contract schema for explicit new file directory permissions

### Changed
- Schema version bumped to 3.0 (contract, proofpack)
- Mechanic now compares post-change results with baseline, flags regressions only
- AUTO_BLOCK triggers on NEW regressions vs baseline, not pre-existing failures
- Engineer reads baseline (does not capture it), removes self-reporting bias
- Codex/Gemini receive only goal + diff (adversarial isolation, no contract/mechanic context)
- Template substitution uses python3 instead of sed (fixes shell injection vulnerability)
- Extracted JSON temp files use .signum/ instead of /tmp/ (fixes race condition)
- HUMAN_REVIEW message now suggests refining acceptance criteria instead of manual code review
- Execute gate requires SUCCESS status explicitly (was only checking for non-FAILED)
- Engineer handles verify.type: "manual" gracefully (skips in repair loop, logs as manual)

### Planned (v3.1)
- Multi-path execution: parallel implementation strategies with winner selection via worktree isolation

## [2.0.1] - 2026-03-02

### Changed
- Rename plugin: sigil → signum (lat. signum — "sign, seal")

## [2.0.0] - 2026-03-02

### Changed
- Complete rewrite: 4-phase pipeline (CONTRACT -> EXECUTE -> AUDIT -> PACK)
- Multi-model audit panel (Claude + Codex + Gemini) replaces single-model review
- contract.json replaces narrative design.md
- proofpack.json replaces review-verdict.md
- Decomposed agents replace 1188-line monolith

### Added
- Contractor agent (haiku/sonnet) for structured contract generation
- Engineer agent (sonnet) with 3-attempt repair loop
- Reviewer-Claude agent (opus) for semantic review
- Synthesizer agent (sonnet) for multi-model verdict
- CLI adapter for Codex and Gemini external reviews
- JSON schemas for contract and proofpack validation
- Deterministic synthesis rules for audit decisions

### Removed
- Observer agent (replaced by multi-model audit)
- Reviewer/Skeptic/Round2 prompts (replaced by unified review template)
- Diverge/diverge-lite build strategies (deferred to future)
- Triage/fast-path/bugfix-path (deferred to future)

## [1.0.0] - 2026-02-25

### Added
- 4-phase development pipeline: Scope → Explore → Design → Build
- 3 review strategies: simple, adversarial, consensus
- Risk-adaptive agent scaling (low/medium/high)
- Observer agent for post-build plan compliance checking
- Session resume and run archiving
- Codex CLI integration with graceful degradation
