{{- /* managed-by: chezmoi | source: .chezmoitemplates/evidence-first-contract.md | v0.7 */ -}}
<!-- evidence-first:contract -->
<workflow name="evidence-first" role="contract">

# Evidence-First Contract

Applies when the user asks for high-assurance work ("prove it works", "TDD",
"I won't read the code") or the change touches money, auth, data loss,
concurrency, or a public API. Routine changes: write good tests, skip this
contract. A project's own AGENTS.md / CLAUDE.md overrides this file on any
conflict — say so once; the evidence report then carries
`contract: overridden by <path>`.

Any workflow may produce the change — /tdd, spec-kitty, manual work; when none
fits, follow the reference implementation at
`{{ .chezmoi.homeDir }}/.agents/workflows/evidence-first.md`. The repo must
carry these properties — verification reads them from git, never the
conversation:

```
SPEC → approve+commit → RED → GREEN (per behavior) → gate → evidence
```

1. **Intent on record.** A spec the human approved BEFORE implementation,
   committed at `specs/<scope>/SPEC.md` — CLOSE reads it only there — with
   scenarios, Must NOT constraints, and a declared tier. Approval is a
   structured act bound to one spec version: quote the approving words
   verbatim into the spec's own approval record and commit them together. An
   answer to a question is not an approval. No human available → proceed,
   record `approval: not obtained`.
2. Tests committed before the implementation they cover.
3. Every new test observed failing first (RED) — a test never seen to fail
   proves nothing.
4. Tier declared in the spec — 1 trivial / 2 normal / 3 high stakes (the
   domains above); tier 3 adds a failure model mapping each harm to a check.
5. Anti-gaming held throughout: fix the implementation, never the test;
   change test or implementation, run, then the other; mock boundaries, not
   logic; coverage is a detector, not a target; report only checks that ran.

Handoff: once green, invoke `verification-gate` — `gate` while fixing,
`evidence` once at the end — with the base ref, tier, and spec path as
intent. The skill owns the layers and report. A failing gate blocks done.
Tier 3 may dispatch the `verifier` agent.

Skipping a property is never silent: the gate records intent, ordering, and
RED status, turning every shortcut into a downgrade the human can price.

</workflow>
<!-- /evidence-first:contract -->
