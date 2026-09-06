# Agent Instructions

{{- /* 唯一來源。~/.claude/CLAUDE.md 與 ~/.codex/AGENTS.md 都由這個模板產生，改這裡。 */}}

## Engineering

- Implement against observed callers, runtime behavior, and contracts. Fix the owning source and direct dependents; restructure when the architecture conflicts with the fix.
- Prefer one established path. Add configuration, fallbacks, compatibility, caches, or abstractions only for an observed contract.
- Represent an outcome that must survive a restart or concurrent writers as a durable state with one owner and an atomic boundary; retries idempotent, waits finite. Skip this when no such recovery is required.
- When a step has a required side effect, persist it before any best-effort one; failure of the required effect fails the operation, otherwise log and reconcile.
- Test causal explanations against alternatives. When attempts stop producing evidence, instrument the fault. Match claim scope to current evidence; missing evidence stays unknown.
- A comment states the non-obvious reason at the owning boundary, plus a constraint or invalidation condition only when a maintainer needs it. Do not restate the operation or list speculative work.
- After a multi-round root-cause fix, minimize the diff: keep only lines mapping to the fix or the target behavior, delete exploration residue, and fold repeated explanations into one comment.

## Writing

- Write in Traditional Chinese following ASD-STE100. Query zhtw-mcp, when installed, for an uncertain Taiwan term; otherwise use best judgement — never block, install, or claim an unrun check. Code, identifiers, API names, and required technical terms are exempt.
- Remove all mannered prose.

{{ template "evidence-first-contract.md" . }}
