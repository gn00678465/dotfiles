---
name: spec-archive
description: Archive a shipped evidence-first spec — the mechanical CLOSE step (Phase 6) after a change merges. Flips the spec's status to `shipped`, moves `specs/<scope>/` to `specs/archive/<scope>/`, and commits, one fail-closed atomic act; `--check` detects forgotten closes. Use after a merge (Tier 3 — after independent verification finalizes), when a merged change's spec still sits in the active directory, or when the user says "archive the spec", "close the spec", or「封存 spec」. Not for archiving anything other than evidence-first specs.
---

# Spec Archive

A shipped spec is an immutable intent record, not a living constraint — the
living truth moved into the tests its scenarios map 1:1 to. This skill is the
mechanical executor of the evidence-first workflow's Phase 6 (CLOSE): the
decision to archive is yours; correctness belongs to the script, never to
hand edits or hand moves.

## When

After the change merges — at Tier 3, after independent verification
finalizes. Never before approval, never on a dirty tree.

## How

Run the script beside this file (stdlib only; any python3):

```bash
python3 <skill-dir>/scripts/spec-archive.py <scope>     # archive one spec
python3 <skill-dir>/scripts/spec-archive.py --check     # find forgotten closes
```

`<scope>` is the feature slug under `specs/` **of the product repository** —
the script resolves its root mechanically via `git rev-parse
--show-toplevel` from the working directory, so all reads, moves, and the
commit land in the repo you are standing in (the machinery lives in `~/`;
the artifacts live in the project). Inside a linked worktree that is the
worktree's root and its checked-out branch — a run inside an isolation copy
touches only that copy. The script, fail closed:

1. **Refuses** — spec missing or status line unparseable (rc 2); status not
   `approved` (rc 1); working tree dirty — archiving must be one atomic
   commit (rc 1); already archived or already `shipped` (rc 1).
2. **Flips `status` to `shipped`** — the spec's one final mutation; after
   this commit the file is immutable.
3. **`git mv specs/<scope> specs/archive/<scope>`** and commits
   `chore(spec): archive <scope>` — one atomic commit.

`--check` prints `approved` specs still in the active directory (candidates —
archive once merged) and exits 1 on a `shipped` spec that never moved (a
violation).

Report a refusal verbatim as the outcome rather than working around it, and
never move or edit spec files by hand in place of the script.
