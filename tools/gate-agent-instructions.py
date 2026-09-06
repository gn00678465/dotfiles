#!/usr/bin/env python3
"""Verification gate entry point for the `global-agent-instructions` SPEC.

Scope is fixed at `global-agent-instructions`. This script never writes to,
reuses, or reads `.gate/windows-support`, and it does not touch
`tools/gate.sh`: that script's artifact directory, default `--base` lookup,
and manifest are hardwired to the windows-support scope (`tools/gate.sh`
lines 34-39, 42, 105), and this SPEC's Setup plan chose a scope-specific
sidecar over parameterizing shared history.

Reused as-is, because they are already scope-generic (take `<scope>` or
`--base` as a parameter): `tools/gate-intent.sh`, `tools/gate-source-state.sh`,
`tools/gate-manifest-audit.sh`, `tests/check_agent_doc_invariants.py`. Two
layers are this change's own tests: `tests/agent_instructions_test.py` (S1
render/word-budget checks) and `tests/spec_archive_test.py` (extended with
real-template fixtures, S4). `tools/gate-properties.py` and
`tools/gate-mutants.py` are windows-support's modify-template differential
and hand-written mutants — out of scope here and not called.

Fail closed: the first failing layer stops the run (its exit code is
preserved); a layer is recorded as run only after its command exits 0;
`gate-manifest-audit.sh` refuses to print success if any expected layer is
missing from that record — a heading is never evidence that a layer ran.
Source state is checked before and after the run; the two must be identical
or the whole run is void, whatever the layers reported. This script itself
must be committed before a real run: on the first run it would otherwise be
untracked, and `gate-source-state.sh`'s whitelist covers only `.gate/`, never
a product path such as `tools/`.

Usage: tools/gate-agent-instructions.py [--base <ref>]
Exit: 0 all layers ran and passed; 1 a layer failed, source state changed
across the run, or the manifest audit found a gap; 2 the entry point itself
is misconfigured (missing tool, no usable base ref).
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

SCOPE = "global-agent-instructions"
REPO = Path(__file__).resolve().parent.parent

MANIFEST = (
    "source-state-before",
    "intent",
    "agent-doc-invariants",
    "agent-instructions-render",
    "spec-archive-tests",
    "source-state-after",
)


def die(code: int, msg: str) -> None:
    print(f"gate-agent-instructions: {msg}", file=sys.stderr)
    sys.exit(code)


def require_tool(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        die(2, f"required tool not found on PATH: {name}")
    return path


def verify_base_reachable(base: str) -> None:
    r = subprocess.run(["git", "cat-file", "-e", f"{base}^{{commit}}"],
                        cwd=REPO, capture_output=True, text=True)
    if r.returncode != 0:
        die(2, f"--base {base} does not resolve to a commit reachable in this "
               f"repository (git cat-file -e {base}^{{commit}} failed): "
               f"{r.stderr.strip()}")


def resolve_base(explicit: str | None) -> str:
    if explicit:
        return explicit
    for cand in (REPO / "specs" / SCOPE / "SPEC.md",
                 REPO / "specs" / "archive" / SCOPE / "SPEC.md"):
        if not cand.is_file():
            continue
        m = re.search(r"^-\s*`base_ref`:\s*`([0-9a-f]+)`",
                       cand.read_text(encoding="utf-8"), re.MULTILINE)
        if m:
            return m.group(1)
    die(2, f"no --base given and no parsable `base_ref` in specs/{SCOPE}/SPEC.md "
           f"or specs/archive/{SCOPE}/SPEC.md")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", help="ref the change is measured against")
    args = ap.parse_args()

    base = resolve_base(args.base)
    verify_base_reachable(base)
    sh = require_tool("sh")
    py = sys.executable

    art = REPO / ".gate" / SCOPE
    if art.exists():
        shutil.rmtree(art)
    art.mkdir(parents=True)

    ran: list[str] = []

    def run_layer(name: str, cmd: list[str], outfile: Path) -> None:
        print(f"\n===== layer: {name} =====")
        r = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True,
                            encoding="utf-8")
        output = (r.stdout or "") + (r.stderr or "")
        outfile.write_text(output, encoding="utf-8")
        print(output)
        if r.returncode != 0:
            die(1, f"layer '{name}' failed (exit {r.returncode}); "
                   "later layers were not run")
        ran.append(name)

    run_layer("source-state-before", [sh, "tools/gate-source-state.sh"],
               art / "source-state-before.txt")
    run_layer("intent", [sh, "tools/gate-intent.sh", SCOPE],
               art / "intent.txt")
    run_layer("agent-doc-invariants", [py, "tests/check_agent_doc_invariants.py"],
               art / "agent-doc-invariants.txt")
    run_layer("agent-instructions-render", [py, "tests/agent_instructions_test.py"],
               art / "agent-instructions-render.txt")
    run_layer("spec-archive-tests", [py, "tests/spec_archive_test.py"],
               art / "spec-archive-tests.txt")
    run_layer("source-state-after", [sh, "tools/gate-source-state.sh"],
               art / "source-state-after.txt")

    before = (art / "source-state-before.txt").read_text(encoding="utf-8")
    after = (art / "source-state-after.txt").read_text(encoding="utf-8")
    if before != after:
        die(1, "source state changed during this run — every number this run "
               "produced describes a tree that no longer exists")

    manifest_file = art / "layers-manifest"
    ran_file = art / "layers-ran"
    # 明確以 LF 寫入：Windows 上 Path.write_text 預設會把 \n 轉成 \r\n，
    # 而 gate-manifest-audit.sh 的 `read -r` 與 `grep -qxF` 是逐位元組比對，
    # CRLF 會讓兩邊的層名稱永遠對不上（見本次 gate 修正輪次 1 的紅燈）。
    manifest_file.write_text("\n".join(MANIFEST) + "\n", encoding="utf-8", newline="\n")
    ran_file.write_text("\n".join(ran) + "\n", encoding="utf-8", newline="\n")

    audit = subprocess.run(
        [sh, "tools/gate-manifest-audit.sh", str(manifest_file), str(ran_file)],
        cwd=REPO, capture_output=True, text=True, encoding="utf-8",
    )
    print(audit.stdout)
    if audit.returncode != 0:
        print(audit.stderr, file=sys.stderr)
        die(1, "manifest audit failed")

    print(f"\ngate-agent-instructions: all layers green (base={base}). "
          f"artifacts in {art.relative_to(REPO)}/")


if __name__ == "__main__":
    main()
