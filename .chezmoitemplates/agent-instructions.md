# Agent Instructions

<!-- 唯一來源。~/.claude/CLAUDE.md 與 ~/.codex/AGENTS.md 都由這個模板產生，改這裡。 -->

## Engineering

- Implement against observed callers, runtime behavior, and contracts. Fix the owning source and direct dependents; restructure when the architecture conflicts with the fix.
- Prefer one established path. Add configuration, fallbacks, compatibility, caches, or abstractions only for an observed contract.
- Represent actionable outcomes as durable states. Give multiple writers one owner and an atomic boundary; make retries idempotent and external waits finite.
- Persist required state before best-effort side effects. Required side-effect failure fails the operation; otherwise log and reconcile it. Propagate unexpected failures at a recovery boundary.
- Test causal explanations against alternatives. When attempts stop producing evidence, instrument the fault. Match claim scope to current evidence; missing evidence stays unknown.
- A comment states the non-obvious reason at the owning boundary. Include a constraint or invalidation condition only when a maintainer needs it to know when the rationale or code stops being valid. Do not restate the operation, preserve intermediate attempts, or list speculative future work.
- When a root cause took more than one round of changes to locate, minimize the final diff before handing off. Every changed line maps to the root-cause fix or the target behavior; anything else is exploration residue, such as hypothesis scaffolding, defensive fallbacks, duplicated logic, or redundant refreshes, and gets deleted or reverted. Keep the fix consistent with the established pattern for comparable features. Surviving non-obvious constraints (field semantics, state lifecycle, timing boundaries) take the comment above, or the next investigation repeats the same wrong assumption.

{{ template "evidence-first-contract.md" . }}
