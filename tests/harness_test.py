#!/usr/bin/env python3
"""Regression tests for the test harness itself.

A defect in the runner is invisible in exactly the way that matters: the run
stays green. The two properties asserted below were each a real fail-open,
reproduced before being fixed:

  * `tests/run.sh` counted `ok N # SKIP` as a contribution, so a layer that
    could not run here sat inside the green total and satisfied the guard meant
    to catch a layer that contributes nothing.
  * `tests/fixtures/os-*.toml` pinned the distro but not `ID_LIKE`, so the host
    leaked into the seam that exists to keep it out.

Each case is paired with a mutant of the script under test: the mutant removes
the fix and must go green on the same input. A regression test nobody has seen
fail on the old code proves nothing about the new code.

Exit codes: 0 all assertions hold; 1 an assertion failed; 2 the harness itself
broke (git or chezmoi unavailable, a script under test missing). Stdlib only.
Usage: tests/harness_test.py
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # < 3.11
    tomllib = None

ROOT = Path(__file__).resolve().parent.parent
RUNNER = ROOT / "tests/run.sh"
LIB = ROOT / "tests/lib.sh"
FIXTURES = ROOT / "tests/fixtures"

PASSES = 0
FAILURES = 0


def die(msg: str) -> None:
    print(f"FAIL: harness — {msg}", file=sys.stderr)
    sys.exit(2)


def check(desc: str, ok: bool, detail: str = "") -> None:
    global PASSES, FAILURES
    if ok:
        PASSES += 1
        print(f"ok: {desc}")
    else:
        FAILURES += 1
        print(f"FAIL: {desc}" + (f"\n  {detail}" if detail else ""), file=sys.stderr)


def sh_run(args: list[str], cwd: Path, env: dict[str, str] | None = None):
    try:
        return subprocess.run(args, cwd=cwd, capture_output=True, text=True,
                              encoding="utf-8", env=env)
    except OSError as e:
        die(f"cannot execute {args[0]}: {e}")


def swap(text: str, old: str, new: str, count: int = 1) -> str:
    """Replace every occurrence of `old`, asserting there are exactly `count`
    of them. Presence alone is not enough — the fail-open this mutant removes
    lives in two read loops, and patching one of them proves nothing."""
    found = text.count(old)
    if found != count:
        die(f"mutant anchor matched {found}x, expected {count}: {old!r}")
    return text.replace(old, new)




# ----------------------------------------------------------- runner skip counting

SYNTHETIC_CASES = {
    "L2-measures.sh": 'assert_eq "合成：真的量了一件事" a a\n',
    "L4-declared.sh": 'skip "合成：宣告過環境前提的層" "沒有 WSL interop"\n',
    "L5-undeclared.sh": 'skip "合成：沒有宣告過環境前提的層" "隨便一個理由"\n',
    "L6-silent.sh": "return 0\n",
}


def runner_tree(tmp: Path, name: str, runner_text: str) -> Path:
    tree = tmp / name / "tests"
    (tree / "cases").mkdir(parents=True)
    (tree / "run.sh").write_text(runner_text, encoding="utf-8", newline="\n")
    (tree / "lib.sh").write_text(LIB.read_text(encoding="utf-8"),
                                 encoding="utf-8", newline="\n")
    for fname, body in SYNTHETIC_CASES.items():
        (tree / "cases" / fname).write_text(body, encoding="utf-8", newline="\n")
    return tree


def test_runner_counts(tmp: Path) -> None:
    text = RUNNER.read_text(encoding="utf-8")
    tree = runner_tree(tmp, "runner-real", text)
    run = str(tree / "run.sh")

    r = sh_run(["sh", run, "L2", "L4"], tree)
    check("runner：宣告過前提的 skip-only 層維持綠燈（TAP 的 ok # SKIP 不動）",
          r.returncode == 0 and "ok 2 - [L4]" in r.stdout and "# SKIP" in r.stdout,
          f"rc={r.returncode} out={r.stdout!r}")
    check("runner：skip-only 層在診斷裡具名",
          "層 L4 的 1 條斷言全部是 SKIP" in r.stdout, r.stdout)
    check("runner：skip-only 層進入結尾摘要而不是被吸收進總數",
          "# skip-only 層（沒有量測任何東西）: L4" in r.stdout, r.stdout)

    r = sh_run(["sh", run, "L2"], tree)
    check("runner：沒有 skip-only 層時摘要明講「無」",
          r.returncode == 0 and "# skip-only 層（沒有量測任何東西）: 無" in r.stdout,
          f"rc={r.returncode} out={r.stdout!r}")

    r = sh_run(["sh", run, "L5"], tree)
    check("runner：沒宣告過前提卻整層 SKIP → 紅",
          r.returncode == 1 and "沒有宣告過環境前提" in r.stdout,
          f"rc={r.returncode} out={r.stdout!r}")

    r = sh_run(["sh", run, "L6"], tree)
    check("runner：一條斷言都沒有的層 → 紅",
          r.returncode == 1 and "一條斷言都沒有貢獻" in r.stdout,
          f"rc={r.returncode} out={r.stdout!r}")

    # 控制項：把量測數改回斷言數，skip-only 層就消失在綠燈裡。
    mutant = runner_tree(tmp, "runner-mutant",
                         swap(text, '_measured=$((_n - _s))', '_measured=$_n'))
    r = sh_run(["sh", str(mutant / "run.sh"), "L2", "L4"], mutant)
    check("控制項：量測數若等於斷言數，skip-only 層不會被指出來",
          r.returncode == 0 and "全部是 SKIP" not in r.stdout
          and "沒有量測任何東西）: 無" in r.stdout,
          f"rc={r.returncode} out={r.stdout!r}")


# ------------------------------------------------------------- fixture seam

# 只有註解提到 key 的 fixture。子字串搜尋會放它過，解析不會 —— 這裡的修正本身
# 就是在幾個 fixture 上加註解，所以「搜尋得到」正是最容易誤判的形狀。
DECOY = ('# distroLikeOverride 沒有釘住，只在這行註解裡出現\n'
         '[data]\n    osOverride = "linux"\n    distroOverride = "debian"\n')


def pinned_idlike(text: str):
    """(是否釘住, 說明或值)。讀 data.distroLikeOverride 本身，不搜尋字串。"""
    data = tomllib.loads(text).get("data", {})
    if "distroLikeOverride" not in data:
        return False, "沒有 data.distroLikeOverride"
    value = data["distroLikeOverride"]
    if not isinstance(value, str):
        return False, f"值不是字串：{value!r}"
    return True, value


def render_pkg_manager(cfg: Path, tmp: Path) -> str:
    dest = tmp / ("dest-" + cfg.stem)
    dest.mkdir(exist_ok=True)
    r = subprocess.run(
        [shutil.which("chezmoi"), "--source", str(ROOT), "--config", str(cfg),
         "--destination", str(dest), "--persistent-state", str(dest / "s.boltdb"),
         "--no-tty", "execute-template"],
        input='{{- $p := includeTemplate "platform.toml" . | fromToml -}}{{ $p.pkgManager }}',
        capture_output=True, text=True, encoding="utf-8", cwd=ROOT)
    if r.returncode != 0:
        die(f"chezmoi execute-template failed for {cfg.name}: {r.stderr.strip()}")
    return r.stdout.strip()


def test_fixture_seam(tmp: Path) -> None:
    if tomllib is None:
        die("tomllib unavailable (needs Python 3.11+); cannot parse the fixtures")

    ok, why = pinned_idlike(DECOY)
    check("控制項：只在註解裡提到 key 的 fixture 不算釘住", not ok, why)
    check("控制項：純子字串搜尋會被那行註解騙過", "distroLikeOverride" in DECOY)

    linux = [p for p in sorted(FIXTURES.glob("*.toml"))
             if tomllib.loads(p.read_text(encoding="utf-8"))
                       .get("data", {}).get("osOverride") == "linux"]
    if not linux:
        die("no Linux fixture found — the seam this asserts about is gone")

    for cfg in linux:
        data = tomllib.loads(cfg.read_text(encoding="utf-8"))["data"]
        ok, value = pinned_idlike(cfg.read_text(encoding="utf-8"))
        check(f"fixture {cfg.name} 釘住了 data.distroLikeOverride", ok, str(value))
        if not ok:
            continue
        expected = "pacman" if (data.get("distroOverride") == "arch"
                                or "arch" in value.split()) else "apt"
        actual = render_pkg_manager(cfg, tmp)
        check(f"fixture {cfg.name} 渲染出的 pkgManager 由釘住的值決定（{expected}）",
              actual == expected, f"actual={actual!r} idLike={value!r}")

    # 控制項：這個 key 真的會左右結果。釘 debian 卻把 ID_LIKE 釘成 arch 必須渲染
    # 成 pacman —— 沒釘的 fixture 交給主機決定的就是這個分支。
    decoy_cfg = tmp / "os-decoy.toml"
    decoy_cfg.write_text('[data]\n    osOverride = "linux"\n'
                         '    archOverride = "amd64"\n'
                         '    distroOverride = "debian"\n'
                         '    distroLikeOverride = "arch"\n    isWSL = false\n',
                         encoding="utf-8", newline="\n")
    check("控制項：ID_LIKE 含 arch 的 Linux fixture 渲染成 pacman",
          render_pkg_manager(decoy_cfg, tmp) == "pacman")


def main() -> None:
    for tool in ("git", "sh", "chezmoi"):
        if shutil.which(tool) is None:
            die(f"required tool not found on PATH: {tool}")
    for f in (RUNNER, LIB):
        if not f.is_file():
            die(f"script under test is missing: {f}")

    with tempfile.TemporaryDirectory(prefix="harness-test-") as tmp_s:
        tmp = Path(tmp_s)
        test_runner_counts(tmp)
        test_fixture_seam(tmp)

    print(f"\n{PASSES} checks hold, {FAILURES} failed")
    sys.exit(1 if FAILURES else 0)


if __name__ == "__main__":
    main()
