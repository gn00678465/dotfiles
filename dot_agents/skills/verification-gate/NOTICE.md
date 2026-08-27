# NOTICE

This skill is adapted from the `old-coder` skill.

- **Upstream:** https://github.com/AmazingAng/old-coder
- **License:** MIT
- **Copyright:** Copyright (c) 2026 amazingang

## What was taken

The layer stack, the baseline / mutation / checker notes, the fail-closed
checker rules and negative-control requirement, the equivalent-mutant rule, the
manual mutation procedure, the entry-point contract and its layer-manifest
audit, the anti-gaming rules, the tier calibration, and the evidence report
structure (including the pass/fail/unverified/n-a row status and the
N-A / UNAVAILABLE / SUBSTITUTED three-way split) are taken from upstream, in
most places verbatim. Terminology was changed from "gauntlet" to "gate", and
references to the upstream SPEC artifact were changed to the intent record this
skill acquires instead.

## What was not taken

The upstream SPEC stage and its human-approval loop, the RED/GREEN/REFACTOR
development cycle, and the independent-verification protocol (`verifier.md`)
are not included. `old-coder` is a full development workflow; this skill is only
the post-implementation verification gate, usable after any workflow.

## What was added

The acquisition step (git for facts, one human question for intent, never the
conversation; the `confirmed` / `unconfirmed` / `absent` intent status), the
changed-unit mapping table derived from the diff, and RED reconstruction from
the base ref — all of which exist because this skill runs detached from the
session that wrote the code, which upstream never has to handle.

## Upstream license

```
MIT License

Copyright (c) 2026 amazingang

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
