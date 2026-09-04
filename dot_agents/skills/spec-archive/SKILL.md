---
name: spec-archive
description: Archive a shipped evidence-first spec — the mechanical CLOSE step (Phase 6), run on the feature branch as its last commit before the merge. Flips the spec's status to `shipped`, moves `specs/<scope>/` to `specs/archive/<scope>/`, and commits, one fail-closed atomic act; `--check` detects forgotten closes. Use once the gate's final evidence is in (Tier 3 — after independent verification finalizes) and before the PR merges, or when an `approved` spec is found on the default branch (a close that was skipped), or when the user says "archive the spec", "close the spec", or「封存 spec」. Not for archiving anything other than evidence-first specs.
---

# Spec Archive

A shipped spec is an immutable intent record, not a living constraint — the
living truth moved into the tests its scenarios map 1:1 to. This skill is the
mechanical executor of the evidence-first workflow's Phase 6 (CLOSE): the
decision to archive is yours; correctness belongs to the script, never to
hand edits or hand moves.

## When

Before the change merges — on the feature branch, after the gate's final
`evidence` (Tier 3: after independent verification finalizes), as the branch's
last commit so the PR carries the shipped spec. Never before approval, never on
a dirty tree. An `approved` spec found on the default branch is a close that
was skipped: archive it there.

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
   commit (rc 1); already archived or already `shipped` (rc 1); no
   committed evidence report, or one whose header records a different
   `spec_version` than the spec (rc 1) — the report is read from git at
   `.scratch/<scope>/evidence.md` or `.gate/<scope>/evidence.md`, and its
   header must quote `spec_version: vN` (the gate's intent layer prints it in
   that form), so a report written against an earlier spec version cannot
   close a later one.
2. **Flips `status` to `shipped`** — the spec's one final mutation; after
   this commit the file is immutable.
3. **`git mv specs/<scope> specs/archive/<scope>`** and commits
   `chore(spec): archive <scope>` — one atomic commit.

`--check` prints `approved` specs still in the active directory (candidates —
archive before merging). It exits 1 on a `shipped` spec that never moved, and
on the default branch also on any candidate: `main` must never hold an
`approved` spec.

Report a refusal verbatim as the outcome rather than working around it, and
never move or edit spec files by hand in place of the script.
