# Signum: Large-Project Support Roadmap

Date: 2026-03-15
Status: planning
Source: `/delve` research + 3 Codex sub-reports

## Context

Research across 7 production SDD systems, 15+ papers, and internal Signum analysis
identified gaps preventing Signum from scaling to large multi-contract projects.
Current Signum excels at task-local contract quality but lacks project-wide coherence.

Full research: `docs/research/2026-03-15-contract-hierarchy-clarification-architecture-2026.md`
Supporting Codex reports: `docs/research/2026-03-15-signum-*.md`, `docs/research/2026-03-15-codex-*.md`

---

## MVP Phases

### Phase 1: Project Intent Layer
- **Effort:** LOW
- **Leverage:** HIGH
- **Status:** not started

Tasks:
- [ ] Define `project.intent.md` template (goal, non-goals, glossary, success criteria, personas)
- [ ] Add `contextInheritance` block to contract schema v3.3:
  - `projectRef: string` — path to project.intent.md
- [ ] Update contractor agent to load `project.intent.md` before generating contract
- [ ] Add `intent_diff_check` as WARN-level sub-check in spec quality gate
  - Compares contract goal against project intent, surfaces divergence
- [ ] Document the new field in README / reference.md

Design questions to resolve:
- Exact template structure for `project.intent.md`
- Where to store: repo root vs `.signum/`
- How contractor loads it (always vs on-demand)

### Phase 2: Glossary Enforcement
- **Effort:** MEDIUM
- **Leverage:** HIGH
- **Status:** not started

Tasks:
- [ ] Add glossary section to `project.intent.md` OR standalone `project.glossary.json`
  - Canonical terms + alias table (forbidden synonyms)
- [ ] Add `glossaryVersion` field to contract schema
- [ ] Implement `glossary_check` in spec quality gate:
  - Lexical match for forbidden synonyms in goal/inScope/ACs
  - WARN on undefined critical domain terms
- [ ] Implement `terminology_consistency_check`:
  - Across active contracts in `.signum/contracts/index.json`
  - WARN on synonym proliferation

Design questions to resolve:
- Format: markdown section vs standalone JSON
- Scope: global repo vs per bounded-context
- Blocking policy: WARN vs BLOCK for undefined terms

### Phase 3: Cross-Contract Coherence
- **Effort:** MEDIUM
- **Leverage:** HIGH
- **Status:** not started

Tasks:
- [ ] Implement `cross_contract_overlap_check`:
  - Compare new contract inScope against active contracts
  - WARN on overlapping scope
- [ ] Implement `assumption_contradiction_check`:
  - Compare assumptions[] across related contracts
  - WARN on conflicting assumptions
- [ ] Implement `adr_relevance_check`:
  - Match touched paths against ADR file globs
  - WARN if adrRefs is empty but relevant ADRs exist
- [ ] Extend contract schema with dependency semantics:
  - `dependsOnContractIds: string[]` — ordering dependency
  - `supersedesContractIds: string[]` — obsolescence tracking
  - `supersededByContractId: string` — reverse pointer
  - `interfacesTouched: string[]` — named interfaces this contract modifies
- [ ] Enhance `.signum/contracts/index.json` for graph queries

Design questions to resolve:
- How to detect "relevant ADRs" without Archgate (file glob matching?)
- How fine-grained should overlap detection be (file-level vs interface-level)
- Should dependency edges be auto-detected or user-declared

### Phase 4: Upstream Staleness Detection
- **Effort:** HIGH
- **Leverage:** HIGH
- **Status:** not started

Tasks:
- [ ] Add `contextSnapshotHash` to contract schema:
  - SHA-256 hash over all inherited upstream artifacts at creation time
- [ ] Add `staleIfChanged: string[]`:
  - Upstream artifact refs that trigger staleness when modified
- [ ] Add `stalenessStatus: "fresh" | "warning" | "stale"`
- [ ] Implement `upstream_staleness_check`:
  - Recompute hash, compare against stored contextSnapshotHash
  - BLOCK if stale (configurable: BLOCK vs WARN)
- [ ] Contractor sets these fields automatically from contextInheritance refs

Design questions to resolve:
- What constitutes a "change" — any byte change vs semantic change
- BLOCK vs WARN policy for staleness
- How to handle cascading staleness (contract A depends on B, B becomes stale)

### Phase 5: Within-Task Refinement Loop
- **Effort:** MEDIUM
- **Leverage:** MEDIUM
- **Status:** not started

Tasks:
- [ ] Implement explicit multi-pass critique in CONTRACT stage:
  - Pass 1: `ambiguity review` — structural + LLM-based
  - Pass 2: `missing-input review` — required context gaps
  - Pass 3: `contradiction review` — internal consistency
  - Pass 4: `goal reconstruction / coverage review` — Clover extension
- [ ] Typed findings (not freeform commentary):
  - `ambiguityCandidates: [{text, location, severity}]`
  - `contradictionsFound: [{claim_a, claim_b, type}]`
  - `clarificationDecisions: [{question, decision, rationale}]`
  - `assumptionProvenance: [{id, text, source, confidence}]`
- [ ] Cap auto-revision at 1-2 rounds, then escalate to user
- [ ] Add `readinessForPlanning` computed field (go/no-go summary)

Design questions to resolve:
- How many critique passes before contractor latency becomes unacceptable
- Should critique agents be separate subagents or inline in contractor
- How to prevent over-critique on simple tasks

---

## Beyond MVP

### B1: ADR Integration (MEDIUM effort, HIGH impact)
- [ ] Add `docs/adr/` convention to Signum projects
- [ ] Add `contextInheritance.adrRefs: string[]` to contract schema
- [ ] Contractor retrieves ADRs matching touched paths before generating contract
- [ ] Optional: Archgate-style `.rules.ts` companion files for executable enforcement

### B2: Initiative Layer (MEDIUM effort, MEDIUM impact)
- [ ] Add `docs/initiatives/INIT-NNN.md` template
- [ ] Add `contextInheritance.initiativeRef` to contract schema
- [ ] Initiative template: scope, contracts list, dependencies, timeline, status
- [ ] Heuristic: create initiative when 3+ contracts expected

### B3: Project Constitution (LOW effort, MEDIUM impact)
- [ ] Add `project.constitution.md` — stable engineering rules, preferences
- [ ] Separate from `project.intent.md` (intent changes, constitution is stable)
- [ ] Add `contextInheritance.constitutionRef` to contract schema

### B4: Asymmetric Context in Review (LOW effort, HIGH impact)
- [ ] Reviewer agents don't see draft history or prior revision attempts
- [ ] Each review evaluates the artifact independently
- [ ] Prevents spontaneous reward hacking (arXiv 2407.04549)

### B5: Kiro-style fileMatch Inclusion (LOW effort, MEDIUM impact)
- [ ] Domain-specific context loaded only when contract touches matching file patterns
- [ ] Reduces noise for unrelated work
- [ ] Implement via trigger tables in constitution or project.intent.md

### B6: Cross-Run Prompt Optimization (HIGH effort, MEDIUM impact)
- [ ] After 20+ completed contracts: DSPy MIPROv2 batch optimization
- [ ] Mutable: contractor prompt, spec-review prompt, rubric weights
- [ ] Frozen: spec quality gate, contradiction checks, goal reconstruction score
- [ ] Teacher/student model split for cost efficiency

### B7: Frozen Evaluator Design (HIGH effort, HIGH impact)
- [ ] GEPA-style: train LM-as-judge on human-labeled contract examples
- [ ] Freeze before optimization loop
- [ ] Stratified evaluation across contract complexity tiers
- [ ] Quarterly human audit of 10 random evaluator judgments
- [ ] Different model family from contractor to prevent shared blind spots

---

## Execution Protocol

For each phase:
1. **Assess readiness** — are design questions resolved? If not → research first
2. **Write detailed plan** — files to create/modify, schema changes, acceptance criteria
3. **Build via Signum** — `/signum` with the plan as feature request
4. **Review** — code review + test the new checks on real contracts
5. **Ship** — bump version, update CHANGELOG

---

## Key Research Sources

- `docs/research/2026-03-15-contract-hierarchy-clarification-architecture-2026.md` — main synthesis
- `docs/research/2026-03-15-signum-project-intent-contract-architecture-codex.md` — Codex: architecture
- `docs/research/2026-03-15-signum-context-inheritance-codex.md` — Codex: inheritance model
- `docs/research/2026-03-15-signum-codex-semantic-drift-across-contracts.md` — Codex: semantic drift
- `docs/research/2026-03-15-codex-contract-clarification-self-improvement-loops.md` — Codex: self-improvement
