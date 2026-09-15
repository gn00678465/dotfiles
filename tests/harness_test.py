#!/usr/bin/env python3
"""Regression tests for the verification harness itself.

Every number in an evidence report is produced by this machinery, so a defect
here is invisible in exactly the way that matters: the run stays green. The
four properties asserted below were each a real fail-open, reproduced before
being fixed:

  * `gate-manifest-audit.sh` skipped a record file's last line when it had no
    trailing newline, and counted lines instead of distinct layers.
  * `gate.sh` deleted the previous run's artifacts before validating the base
    ref, the scope and the tools, so a run refused on a configuration error
    destroyed the last good evidence and measured nothing.
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

import os
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
AUDIT = ROOT / "tools/gate-manifest-audit.sh"
GATE = ROOT / "tools/gate.sh"
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


def cut(text: str, start: str, end: str) -> str:
    """Delete the block from `start` through `end`. The start anchor must
    appear exactly once: an anchor that matches twice deletes a block the
    author never inspected, and the mutant then tests something else."""
    if text.count(start) != 1:
        die(f"mutant anchor matched {text.count(start)}x, expected 1: {start!r}")
    i = text.index(start)
    j = text.find(end, i)
    if j < 0:
        die(f"mutant end anchor not found: {end!r}")
    return text[:i] + text[j + len(end):]


def swap(text: str, old: str, new: str, count: int = 1) -> str:
    """Replace every occurrence of `old`, asserting there are exactly `count`
    of them. Presence alone is not enough — the fail-open this mutant removes
    lives in two read loops, and patching one of them proves nothing."""
    found = text.count(old)
    if found != count:
        die(f"mutant anchor matched {found}x, expected {count}: {old!r}")
    return text.replace(old, new)


def snapshot(d: Path) -> dict[str, bytes]:
    return {str(p.relative_to(d)): p.read_bytes()
            for p in sorted(d.rglob("*")) if p.is_file()}


# --------------------------------------------------------------- manifest audit

def audit_case(script: Path, tmp: Path, manifest: str, ran: str):
    m, r = tmp / "manifest", tmp / "ran"
    m.write_text(manifest, encoding="utf-8", newline="\n")
    r.write_text(ran, encoding="utf-8", newline="\n")
    return sh_run(["sh", str(script), str(m), str(r)], tmp)


def test_manifest_audit(tmp: Path) -> None:
    mutants = tmp / "mutants"
    mutants.mkdir()
    text = AUDIT.read_text(encoding="utf-8")

    # 末行沒有換行：`read` 讀得到內容卻回非零，迴圈漏掉最後一行。
    no_nl = mutants / "no-final-newline.sh"
    no_nl.write_text(swap(text, ' || [ -n "$layer" ]', "", count=2),
                     encoding="utf-8", newline="\n")
    # 重複層名：grep -qxF 只答在不在，層數也跟著虛報。
    no_dup = mutants / "no-dup-check.sh"
    no_dup.write_text(
        swap(cut(text, "# 重複項：", "    exit 1\nfi\n"),
             'n=$(sort "$manifest" | grep -v \'^$\' | uniq | grep -c .)',
             'n=$(grep -c . "$manifest")'),
        encoding="utf-8", newline="\n")

    cases = [
        ("兩邊相同且有結尾換行 → 通過", "a\nb\n", "a\nb\n", 0, "2 層"),
        ("漏一層、有結尾換行 → 拒絕", "a\nb\n", "a\n", 1, None),
        ("漏一層、manifest 末行無換行 → 拒絕", "a\nb", "a\n", 1, None),
        ("多一層、ran 末行無換行 → 拒絕", "a\n", "a\nb", 1, None),
        ("manifest 有重複層名 → 拒絕", "a\na\n", "a\n", 1, None),
        ("ran 有重複層名 → 拒絕", "a\n", "a\na\n", 1, None),
        ("空行不計入層數", "a\n\nb\n", "a\nb\n", 0, "2 層"),
    ]
    for desc, manifest, ran, rc, out in cases:
        r = audit_case(AUDIT, tmp, manifest, ran)
        ok = r.returncode == rc and (out is None or out in r.stdout)
        check(f"manifest 稽核：{desc}", ok,
              f"rc={r.returncode} stdout={r.stdout.strip()!r} stderr={r.stderr.strip()!r}")

    r = sh_run(["sh", str(AUDIT), str(tmp / "does-not-exist"), str(tmp / "ran")], tmp)
    check("manifest 稽核：讀不到輸入 → rc 1", r.returncode == 1, f"rc={r.returncode}")
    r = sh_run(["sh", str(AUDIT), str(tmp / "ran")], tmp)
    check("manifest 稽核：參數個數不對 → rc 2", r.returncode == 2, f"rc={r.returncode}")

    # 控制項：拔掉修正的版本必須在同一份輸入上變綠，否則上面兩條紅燈不是它們宣稱的東西。
    r = audit_case(no_nl, tmp, "a\nb", "a\n")
    check("控制項：沒有 `|| [ -n \"$layer\" ]` 的版本在無換行輸入上 fail open",
          r.returncode == 0, f"rc={r.returncode} stdout={r.stdout.strip()!r}")
    r = audit_case(no_dup, tmp, "a\na\n", "a\n")
    check("控制項：沒有重複檢查的版本把 1 層虛報成 2 層",
          r.returncode == 0 and "2 層" in r.stdout,
          f"rc={r.returncode} stdout={r.stdout.strip()!r}")


# ------------------------------------------------------- gate.sh preflight order

def fake_repo(tmp: Path, name: str, gate_text: str) -> Path:
    repo = tmp / name
    (repo / "tools").mkdir(parents=True)
    (repo / "tools/gate.sh").write_text(gate_text, encoding="utf-8", newline="\n")
    for cmd in (["git", "init", "-q"], ["git", "config", "user.email", "t@t"],
                ["git", "config", "user.name", "t"],
                ["git", "commit", "-q", "--allow-empty", "-m", "base"]):
        if sh_run(cmd, repo).returncode != 0:
            die(f"cannot build the temp repo in {repo}")
    art = repo / ".gate/selftest"
    art.mkdir(parents=True)
    # 這一份是上一輪的證據，而且沒有任何層會重新寫出它 —— versions.txt 之類的
    # 名字會被這一輪自己的 versions 層重建，看起來像沒被刪過。
    (art / "prev-run.txt").write_text("last good run\n", encoding="utf-8", newline="\n")
    (art / "suite.tap").write_text("1..1\nok 1\n", encoding="utf-8", newline="\n")
    escape = repo / "escape"
    escape.mkdir()
    (escape / "keep.txt").write_text("outside .gate\n", encoding="utf-8", newline="\n")
    return repo


def test_gate_preflight(tmp: Path) -> None:
    text = GATE.read_text(encoding="utf-8")
    repo = fake_repo(tmp, "gate-real", text)
    art = repo / ".gate/selftest"
    before = snapshot(art)

    r = sh_run(["sh", "tools/gate.sh", "--scope", "selftest",
                "--base", "0" * 40], repo)
    check("gate.sh：解不到的 base → rc 2", r.returncode == 2, f"rc={r.returncode}")
    check("gate.sh：被 base 擋下時上一輪產出逐位元組不變", snapshot(art) == before,
          f"after={sorted(snapshot(art))}")

    r = sh_run(["sh", "tools/gate.sh", "--scope", "../escape", "--base", "HEAD"], repo)
    check("gate.sh：scope 帶路徑分隔 → rc 2", r.returncode == 2, f"rc={r.returncode}")
    check("gate.sh：被 scope 擋下時 .gate/ 外的目錄沒有被刪",
          (repo / "escape/keep.txt").is_file())
    check("gate.sh：被 scope 擋下時上一輪產出逐位元組不變", snapshot(art) == before)

    # 缺工具：PATH 只留 gate.sh 走到檢查前需要的東西，chezmoi 不放進去。
    bin_dir = tmp / "bin"
    bin_dir.mkdir()
    for tool in ("dirname", "git", "sed", "zsh", "python3", "diff", "rm", "mkdir"):
        real = shutil.which(tool)
        if real:
            (bin_dir / tool).symlink_to(real)
    env = dict(os.environ, PATH=str(bin_dir))
    r = sh_run([shutil.which("sh") or "/bin/sh", "tools/gate.sh",
                "--scope", "selftest", "--base", "HEAD"], repo, env=env)
    check("gate.sh：PATH 上缺 chezmoi → rc 2", r.returncode == 2,
          f"rc={r.returncode} stderr={r.stderr.strip()!r}")
    check("gate.sh：被缺工具擋下時上一輪產出逐位元組不變", snapshot(art) == before)

    # 正向控制：設定正確時 rm -rf 照樣發生。少了這條，上面三條「產出還在」
    # 可能只是因為這支腳本從來不刪東西。
    r = sh_run(["sh", "tools/gate.sh", "--scope", "selftest", "--base", "HEAD"], repo)
    check("正向控制：設定正確時上一輪產出真的被清掉",
          r.returncode != 2 and not (art / "prev-run.txt").is_file(),
          f"rc={r.returncode} files={sorted(snapshot(art))}")

    # 控制項：拔掉 preflight 呼叫的版本，會在同一個無效 base 上把產出刪光。
    mutant = fake_repo(tmp, "gate-mutant", swap(text, "require_sane_config || exit $?\n", ""))
    m_art = mutant / ".gate/selftest"
    m_before = snapshot(m_art)
    r = sh_run(["sh", "tools/gate.sh", "--scope", "selftest", "--base", "0" * 40], mutant)
    check("控制項：沒有 preflight 的版本會銷毀上一輪產出",
          snapshot(m_art) != m_before and not (m_art / "prev-run.txt").is_file(),
          f"rc={r.returncode} files={sorted(snapshot(m_art))}")


# ------------------------------------------------------------- versions layer

def test_versions_layer(tmp: Path) -> None:
    """`command -v` proves a tool exists, not that it runs. The version line is
    part of the evidence, so a tool that cannot report one has to fail the
    layer instead of printing an empty value into the report."""
    text = GATE.read_text(encoding="utf-8")
    stub_dir = tmp / "stub-bin"
    stub_dir.mkdir()
    stub = stub_dir / "chezmoi"
    stub.write_text("#!/bin/sh\necho 'chezmoi: cannot start' >&2\nexit 1\n",
                    encoding="utf-8", newline="\n")
    stub.chmod(0o755)
    env = dict(os.environ, PATH=f"{stub_dir}{os.pathsep}{os.environ['PATH']}")

    repo = fake_repo(tmp, "gate-versions", text)
    r = sh_run(["sh", "tools/gate.sh", "--scope", "selftest", "--base", "HEAD"],
               repo, env=env)
    ran = repo / ".gate/selftest/layers-ran"
    check("gate.sh：工具在 PATH 上但問不出版本 → 這一輪失敗",
          r.returncode == 1, f"rc={r.returncode} stderr={r.stderr.strip()!r}")
    check("gate.sh：問不出版本的 versions 層沒有被記成完成",
          ran.is_file() and "versions" not in ran.read_text(encoding="utf-8"),
          f"layers-ran={ran.read_text(encoding='utf-8') if ran.is_file() else None!r}")

    # 正向：版本問得到時，這一層要被記成完成、輸出落在它自己的檔案裡，而且這一輪
    # 要往下一層走。只斷言「舊產出被刪掉」看不到這些：版本字串蓋掉 run_layer 的
    # 輸出檔路徑時，刪除照樣發生，失敗的是後面的 cat。
    good = fake_repo(tmp, "gate-versions-ok", text)
    r = sh_run(["sh", "tools/gate.sh", "--scope", "selftest", "--base", "HEAD"], good)
    g_ran = good / ".gate/selftest/layers-ran"
    g_out = good / ".gate/selftest/versions.txt"
    check("gate.sh：版本問得到時 versions 記成完成",
          g_ran.is_file() and "versions" in g_ran.read_text(encoding="utf-8"),
          f"stderr={r.stderr.strip()!r}")
    check("gate.sh：versions 的輸出落在它自己的檔案裡（沒被版本字串蓋掉路徑）",
          g_out.is_file() and "chezmoi:" in g_out.read_text(encoding="utf-8"),
          f"stderr={r.stderr.strip()!r}")
    check("gate.sh：versions 通過後這一輪繼續走到下一層",
          "===== layer: source-state-before =====" in r.stdout,
          f"stdout={r.stdout[-400:]!r}")

    # 控制項：把版本行改回 `printf '%s' "$(tool --version)"`，退出碼就被吞掉，
    # 這一層帶著一行空版本進入 completed 清單。
    mutant = fake_repo(tmp, "gate-versions-mutant", swap(
        text, "    _ver 'chezmoi:' chezmoi --version || return 1\n",
        "    printf 'chezmoi: %s\\n' \"$(chezmoi --version)\"\n"))
    sh_run(["sh", "tools/gate.sh", "--scope", "selftest", "--base", "HEAD"],
           mutant, env=env)
    m_ran = mutant / ".gate/selftest/layers-ran"
    check("控制項：吞掉退出碼的寫法會把 versions 記成完成",
          m_ran.is_file() and "versions" in m_ran.read_text(encoding="utf-8"),
          f"layers-ran={m_ran.read_text(encoding='utf-8') if m_ran.is_file() else None!r}")


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
    for f in (AUDIT, GATE, RUNNER, LIB):
        if not f.is_file():
            die(f"script under test is missing: {f}")

    with tempfile.TemporaryDirectory(prefix="harness-test-") as tmp_s:
        tmp = Path(tmp_s)
        test_manifest_audit(tmp)
        test_gate_preflight(tmp)
        test_versions_layer(tmp)
        test_runner_counts(tmp)
        test_fixture_seam(tmp)

    print(f"\n{PASSES} checks hold, {FAILURES} failed")
    sys.exit(1 if FAILURES else 0)


if __name__ == "__main__":
    main()
