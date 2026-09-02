#!/usr/bin/env python3
"""Supply-chain and secrets layer for the verification gate.

This repo's "dependencies" are chezmoi externals (pinned URL + sha256) and
package-manager IDs. Three checks:

  1. Every external URL this change ADDED or CHANGED is downloaded and its
     sha256 compared with the pin. A pin nobody ever verified is decoration.
     Externals untouched by this change are not re-downloaded every gate run.
  2. The diff is scanned for credentials.
  3. Capability diff: which outbound hosts and which external commands the
     source declares now, versus at the base ref. Declared surface only --
     import/URL/command literals -- no judgement about how they are used.

Fails closed: a download error, a hash mismatch, a secret hit, or an unreadable
input is a hard failure. There is no offline mode; a network the gate cannot
reach means the pins were not verified, which is not a pass.

Usage: tools/gate-supply-chain.py --base <ref>
"""

from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FIXTURES = REPO / "tests" / "fixtures"
OS_CONFIGS = ["os-linux.toml", "os-darwin-arm64.toml", "os-darwin-amd64.toml", "os-windows.toml"]

SECRET_PATTERNS = [
    (r"AKIA[0-9A-Z]{16}", "AWS access key id"),
    (r"-----BEGIN [A-Z ]*PRIVATE KEY-----", "private key block"),
    (r"gh[pousr]_[A-Za-z0-9]{20,}", "GitHub token"),
    (r"xox[baprs]-[A-Za-z0-9-]{10,}", "Slack token"),
    (r"(?i)\b(password|passwd|secret|api[_-]?key)\s*[:=]\s*['\"][^'\"]{8,}['\"]", "inline credential"),
]

# 這些 host 是這個 repo 本來就在用的下載來源。新出現的 host 會被列出來，
# 讓 evidence report 的讀者知道這次改動讓來源樹多對外聯絡了誰。
COMMAND_LITERALS = [
    "winget", "brew", "apt-get", "mise", "git", "chsh", "dpkg-query",
    "Install-PSResource", "Add-AppxPackage", "Invoke-WebRequest", "Invoke-RestMethod",
    "oh-my-posh", "git-lfs", "sudo", "curl",
]


def sh(cmd: list[str], cwd: Path = REPO) -> str:
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)} -> {p.returncode}\n{p.stderr}")
    return p.stdout


def render_externals(source: Path, config: str) -> str:
    src = (source / ".chezmoiexternal.toml.tmpl").read_text(encoding="utf-8")
    p = subprocess.run(
        ["chezmoi", "--source", str(source), "--config", str(FIXTURES / config),
         "--destination", "/tmp/gate-sc-dest", "--no-tty", "execute-template"],
        input=src, capture_output=True, text=True,
    )
    if p.returncode != 0:
        raise RuntimeError(f"render {config}: {p.stderr}")
    return p.stdout


def externals(source: Path) -> dict[str, str]:
    """url -> sha256, across all four platform renders."""
    found: dict[str, str] = {}
    for cfg in OS_CONFIGS:
        url = None
        for line in render_externals(source, cfg).splitlines():
            line = line.strip()
            if line.startswith("url ="):
                url = line.split("=", 1)[1].strip().strip('"')
            elif line.startswith("checksum.sha256 =") and url:
                found[url] = line.split("=", 1)[1].strip().strip('"')
    return found


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    args = ap.parse_args()

    failures: list[str] = []

    # ---------------------------------------------------------- 1. pins
    head_ext = externals(REPO)

    base_dir = Path("/tmp/gate-sc-base")
    subprocess.run(["rm", "-rf", str(base_dir)], check=True)
    base_dir.mkdir(parents=True)
    subprocess.run(f"git -C {REPO} archive {args.base} | tar -x -C {base_dir}",
                   shell=True, check=True)
    try:
        base_ext = externals(base_dir)
    except RuntimeError as e:
        raise SystemExit(f"gate-supply-chain: 讀不到 base ref 的 external：{e}")

    new_or_changed = {u: s for u, s in head_ext.items() if base_ext.get(u) != s}
    print(f"externals: {len(head_ext)} 個帶 checksum 的釘住下載，"
          f"其中 {len(new_or_changed)} 個是這次新增或變更的")

    for url, want in sorted(new_or_changed.items()):
        try:
            with urllib.request.urlopen(url, timeout=120) as r:
                data = r.read()
        except Exception as e:  # noqa: BLE001 - 任何取不到都算失敗
            failures.append(f"下載失敗（pin 因此未經驗證）: {url}: {e}")
            continue
        got = hashlib.sha256(data).hexdigest()
        if got != want:
            failures.append(f"sha256 不符: {url}\n  pinned={want}\n  actual={got}")
        else:
            print(f"  OK  {got[:16]}...  {url}")

    # ---------------------------------------------------------- 2. secrets
    diff = sh(["git", "diff", f"{args.base}...HEAD"])
    added = [l[1:] for l in diff.splitlines() if l.startswith("+") and not l.startswith("+++")]
    for pat, label in SECRET_PATTERNS:
        rx = re.compile(pat)
        for line in added:
            if rx.search(line):
                failures.append(f"疑似機密（{label}）出現在新增的行: {line[:120]}")
    print(f"secrets: 掃過 {len(added)} 行新增內容")

    # ---------------------------------------------------------- 3. capabilities
    def surface(text: str) -> tuple[set[str], set[str]]:
        hosts = set(re.findall(r"https?://([A-Za-z0-9.\-]+)", text))
        cmds = {c for c in COMMAND_LITERALS if re.search(rf"(?<![\w-]){re.escape(c)}(?![\w-])", text)}
        return hosts, cmds

    def tree_text(ref_dir: Path) -> str:
        out = []
        for p in sorted(ref_dir.rglob("*")):
            if p.is_file() and ".git/" not in str(p):
                try:
                    out.append(p.read_text(encoding="utf-8"))
                except (UnicodeDecodeError, OSError):
                    pass
        return "\n".join(out)

    h_hosts, h_cmds = surface(tree_text(REPO))
    b_hosts, b_cmds = surface(tree_text(base_dir))
    print("capability diff (declared surface only):")
    print(f"  新增的外部 host: {sorted(h_hosts - b_hosts) or '（無）'}")
    print(f"  移除的外部 host: {sorted(b_hosts - h_hosts) or '（無）'}")
    print(f"  新增的外部命令: {sorted(h_cmds - b_cmds) or '（無）'}")
    print(f"  移除的外部命令: {sorted(b_cmds - h_cmds) or '（無）'}")

    if failures:
        print("\ngate-supply-chain: 失敗", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1
    print("\ngate-supply-chain: 通過")
    return 0


if __name__ == "__main__":
    sys.exit(main())
