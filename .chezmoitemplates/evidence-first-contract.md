<!-- managed-by: chezmoi | source: .chezmoitemplates/evidence-first-contract.md | v0.4 -->
<!-- TODO(v0.x): finalize the spec-approval keyword list (kotek-7-style gate) -->
<workflow name="evidence-first" role="contract">

# Evidence-First Contract

Applies when the user asks for high-assurance work ("prove it works", "TDD",
"I won't read the code") or the change touches money, auth, data loss,
concurrency, or a public API. For routine changes, write good tests directly
and ignore this contract. A project's own AGENTS.md / CLAUDE.md overrides
this file on any conflict — but an override is never silent: say so once,
and the evidence report carries `contract: overridden by <path>`.

Any workflow may produce the change — /tdd, spec-kitty, manual work; when no
tool fits, follow the reference implementation at
`{{ .chezmoi.homeDir }}/.agents/workflow/evidence-first.md`. Whatever runs,
the repository must end up carrying these five properties, because the
verification step reads them from git, never from this conversation:

```
SPEC → approve+commit → RED → GREEN (per behavior) → gate → evidence
```

1. **Intent on record.** A spec the human approved BEFORE implementation,
   committed to the repo: scenarios with concrete inputs and outputs, Must
   NOT constraints, and a declared tier. An answer to a question is not an
   approval: if you cannot quote the words that approved THIS spec —
   whichever workflow's artifact carries it — you do not have approval. No
   human available → proceed, and record `approval: not obtained`.
2. **Tests committed before the implementation they cover.**
3. **Every new test observed failing first (RED).** A test you never saw
   fail proves nothing.
4. **Tier declared in the spec** — 1 trivial / 2 normal / 3 high stakes
   (the domains above). Tier 3 adds a failure model: how this change can
   hurt, each mode mapped to a check.
5. **Anti-gaming held throughout** — the one property nothing can verify
   after the fact: fix the implementation, never the test (a wrong-looking
   test is a spec conversation); change test or implementation, run, then
   the other; mock boundaries, not logic; coverage is a detector, not a
   target; report only checks that ran.

Handoff: when the change is green, invoke the `verification-gate` skill —
`gate` iteratively while fixing, `evidence` exactly once after the last
edit. Hand it the base ref, the tier, and the committed spec path as the
intent record. The skill owns the layers and the report; never run them by
hand in its place. **A failing gate blocks done.** Tier 3 may add
independent verification: dispatch the `verifier` agent; orchestration
rules are in the reference implementation.

Skipping a property is not fatal, but never silent: the gate records
intent, ordering, and RED status in the evidence report, so every shortcut
becomes a visible downgrade the human can price — not a hidden one.

</workflow>
