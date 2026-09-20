---
name: stage-manager
description: >-
  Route high-assurance work to the appropriate playbook. Triggers when the
  user asks for proven correctness ("prove it works", "TDD", "I won't read
  the code") or the change touches money, auth, data loss, concurrency, or a
  public API. Routine changes skip this skill.
---

# Stage Manager

Classify the change, select a playbook, and hand off. This skill owns the
trigger conditions and the contract properties; it does not execute any phase.

## Trigger Conditions

| Condition | Result |
|---|---|
| User requests high confidence: "prove it works", "TDD", "I won't read the code" | Enter this skill |
| Change touches money, auth, data loss, concurrency, or a public API | Enter this skill |
| Routine change | Skip — write good tests, no contract |

## Contract Properties

The repo must carry these five properties when the change is complete.
Verification reads them from git, never from the conversation.

1. **Intent on record.** A SPEC the human approved before implementation,
   committed at `specs/<scope>/SPEC.md`.
2. **Tests committed before implementation.** Test files committed before the
   code they cover.
3. **Every new test observed failing first (RED).** A test never seen to fail
   proves nothing.
4. **Tier declared in the spec.** 1 trivial / 2 normal / 3 high stakes
   (money, auth, data loss, concurrency, public API). Tier 3 adds a failure
   model.
5. **Anti-gaming held throughout.** Fix the implementation, never the test;
   change test or implementation, run, then the other; mock boundaries, not
   logic; coverage is a detector, not a target; report only checks that ran.

## Anti-Gaming Rules — Reference Table

Each rule lives in the skill that enforces it. This table is the index.

| Rule | Short name | Authoritative location |
|---|---|---|
| 1 | Never weaken a test | `tdd/SKILL.md` |
| 2 | Never edit test and implementation in the same step | `tdd/SKILL.md` |
| 3 | Never mock the unit under test | `tdd/SKILL.md` |
| 4 | Never chase the coverage number | `tdd/SKILL.md` |
| 5 | Never report a layer you didn't run | `verification-gate/SKILL.md` |
| 6 | Failing gate blocks done | `verification-gate/SKILL.md` |

## Playbook Dispatch

| Playbook | When | Location |
|---|---|---|
| `old-coder` | Full evidence-first 6-phase workflow (default) | `playbooks/old-coder.md` |

## Override

A project's `AGENTS.md` or `CLAUDE.md` may override this contract — say so
once; the evidence report then carries `contract: overridden by <path>`.

## Attribution

The contract properties, anti-gaming rules, and tier definitions are adapted
from the old-coder skill
(https://github.com/AmazingAng/old-coder, MIT, Copyright (c) 2026 amazingang).
See `verification-gate/NOTICE.md`.
