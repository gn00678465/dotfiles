#!/usr/bin/env python3
"""Manual mutation runner for the verification gate.

No mutation tool exists for chezmoi templates, POSIX shell or PowerShell, so the
mutants are hand-written: each one is a plausible bug in code this change
introduced or touched, paired with the test layer that must notice it.

Two properties this runner must have, because a hand-rolled runner that can
report a kill it never ran inflates the score and no red gate would surface it:

  * It proves each mutant was actually applied -- the patch must change the file,
    and the file must be restored afterwards, both asserted.
  * It fails closed. A patch that does not apply, a layer that cannot run, an
    unexpected exit code: all are hard failures, never a pass.

Mutants are applied inside a throwaway git worktree, never the product tree. A
verification run must not modify the code it is verifying, and "restore
afterwards" is not good enough -- an interrupt would leave the tree mutated.

Usage: tools/gate-mutants.py [--jobs N]
Exit:  0 every mutant killed, 1 any survivor or any runner failure.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


@dataclass(frozen=True)
class Mutant:
    name: str
    path: str
    old: str
    new: str
    layer: str
    rationale: str


# Each mutant is a bug someone could plausibly write, not a random character
# swap. `layer` is the test layer that must go red; the runner only runs that
# layer, which keeps the round cheap enough to be part of every gate run.
MUTANTS: list[Mutant] = [
    Mutant(
        name="platform-darwin-arch",
        path=".chezmoitemplates/platform.toml",
        old='{{-   $brewPrefix = (eq $arch "arm64") | ternary "/opt/homebrew" "/usr/local" -}}',
        new='{{-   $brewPrefix = "/usr/local" -}}',
        layer="L1",
        rationale="Apple Silicon 與 Intel Mac 的 brew prefix 搞混",
    ),
    Mutant(
        name="ignore-windows-block",
        path=".chezmoiignore",
        old=".zshrc\n.zprofile\n.p10k.zsh\n",
        new="",
        layer="L3",
        rationale="Windows 上忘了忽略 zsh 那一套，於是它們被裝進 %USERPROFILE%",
    ),
    Mutant(
        name="posix-nvim-delete",
        path=".chezmoiscripts/run_onchange_before_50-neovim.sh.tmpl",
        old='  mv "$1" "$dest"',
        new='  rm -rf "$1"',
        layer="L7",
        rationale="POSIX 端把既有 nvim 設定刪掉而不是搬開（M2）",
    ),
    Mutant(
        name="windows-nvim-marker",
        path=".chezmoiscripts/run_onchange_before_50-neovim.ps1.tmpl",
        old="if (-not (Test-Path -LiteralPath $marker)) {",
        new="if ($true) {",
        layer="L7",
        rationale="Windows 端 marker 守衛失效，重跑把使用者自己的設定搬走（M3）",
    ),
    Mutant(
        name="windows-nvim-data-backup",
        path=".chezmoiscripts/run_onchange_before_50-neovim.ps1.tmpl",
        old="    Backup-NvimDirectory $nvimData\n",
        new="",
        layer="L7",
        rationale="漏備份 %LOCALAPPDATA%\\nvim-data，外掛與 state 全部遺失（M2）",
    ),
    Mutant(
        name="loader-idempotency",
        path=".chezmoitemplates/pwsh-profile-loader.ps1",
        old="if ($existing | Where-Object { $_.Trim() -eq $loader }) { return }",
        new="if ($false) { return }",
        layer="L7",
        rationale="profile loader 每次 apply 都再追加一次（M10）",
    ),
    Mutant(
        name="codex-duplicate-keys",
        path="dot_codex/modify_private_config.toml",
        old=(
            "{{-       if not (hasKey $done $k) -}}\n"
            "{{-         $buf = append $buf (get $want $k) -}}\n"
            "{{-         $_ := set $done $k true -}}\n"
            "{{-       end -}}\n"
        ),
        new=(
            "{{-       $buf = append $buf (get $want $k) -}}\n"
            "{{-       $_ := set $done $k true -}}\n"
        ),
        layer="L6",
        rationale="重複的受管 key 沒有被收斂成一個（M4）",
    ),
    Mutant(
        name="codex-trailing-blank",
        path="dot_codex/modify_private_config.toml",
        old="{{-       $out = concat $out $head -}}",
        new="{{-       $out = concat $out $buf -}}",
        layer="L6",
        rationale="補寫的 key 插到 [tui] 的結尾空行之後，跑進下一個 table（M4）",
    ),
    Mutant(
        name="external-checksum",
        path=".chezmoiexternal.toml.tmpl",
        old='    checksum.sha256 = "d75ac08c2c8af5a6a0478787b0f11fabbe24951973b7841ae963431e2070ee9a"\n',
        new="",
        layer="L5",
        rationale="外部下載少了 checksum（Must NOT #5）",
    ),
    Mutant(
        name="apt-script-guard",
        path=".chezmoiscripts/run_onchange_before_10-install-packages.sh.tmpl",
        old='{{ if eq $p.os "linux" -}}',
        new="{{ if true -}}",
        layer="L2",
        rationale="apt 腳本失去平台守衛，在 Windows 上非空 → 整個 apply 中斷（M1）",
    ),
    Mutant(
        name="claude-statusline-windows",
        path="dot_claude/modify_settings.json",
        old='{{-   $ccCommand = "~/.claude/cc-statusline/cc-statusline.exe" -}}',
        new='{{-   $ccCommand = "~/.claude/cc-statusline/cc-statusline" -}}',
        layer="L6",
        rationale="Windows 的 statusLine 指到不存在的無副檔名檔案",
    ),
    Mutant(
        name="pwsh-profile-target",
        path=".chezmoiscripts/run_after_60-pwsh-profile.ps1.tmpl",
        old="$target = $PROFILE.CurrentUserAllHosts",
        new="$target = $PROFILE.CurrentUserCurrentHost",
        layer="L2",
        rationale="loader 寫進只有裸 pwsh.exe 會載入的 profile；Windows Terminal 與 VS Code 都吃不到",
    ),
    Mutant(
        name="loader-line-content",
        path=".chezmoitemplates/pwsh-profile-loader.ps1",
        old="$loader = '. \"$HOME/.config/powershell/profile.ps1\"'",
        new="$loader = '. \"$HOME/.config/powershell/profile.ps1.disabled\"'",
        layer="L7",
        rationale="loader 指向不存在的檔案：每次開 shell 報錯，設定永遠載不到",
    ),
    Mutant(
        name="backup-timestamp-collision",
        path=".chezmoiscripts/run_onchange_before_50-neovim.sh.tmpl",
        old=(
            '    local stamp="$(date +%Y%m%d%H%M%S)"\n'
            '    dest="$1.bak.$stamp"\n'
            "    local n=1\n"
            "    while [[ -e $dest ]]; do\n"
            '      dest="$1.bak.$stamp.$n"\n'
            "      n=$((n + 1))\n"
            "    done"
        ),
        new='    dest="$1.bak.$(date +%Y%m%d%H%M%S)"',
        layer="L7",
        rationale="同一秒內連續備份會撞名，把上一份備份埋進新的備份裡",
    ),
    Mutant(
        name="backup-timestamp-collision-windows",
        path=".chezmoiscripts/run_onchange_before_50-neovim.ps1.tmpl",
        old=(
            "        $stamp = Get-Date -Format 'yyyyMMddHHmmss'\n"
            '        $dest = "$Path.bak.$stamp"\n'
            "        $n = 1\n"
            "        while (Test-Path -LiteralPath $dest) {\n"
            '            $dest = "$Path.bak.$stamp.$n"\n'
            "            $n++\n"
            "        }"
        ),
        new="        $dest = \"$Path.bak.$(Get-Date -Format 'yyyyMMddHHmmss')\"",
        layer="L7",
        rationale=(
            "Windows 端同一秒內連續備份會撞名，把上一份備份埋進新的裡。"
            "這個 mutant 的鏡像（POSIX 版）本來就有，Windows 版沒有，"
            "所以它一度可以存活整個套件"
        ),
    ),
    Mutant(
        name="external-checksum-empty",
        path=".chezmoiexternal.toml.tmpl",
        old='"win32-arm64"      "dd4fd5ea2811f91031953f806e0a65855c1d623fae4732d554f6489db33f7abd"',
        new='"win32-arm64"      ""',
        layer="L5",
        rationale=(
            "空字串的 pin 讓 chezmoi「不驗證就安裝」（實測），比錯的 pin 更危險；"
            "而且 win32-arm64 這個分支原本沒有任何 fixture 會渲染到它"
        ),
    ),
    Mutant(
        name="cc-statusline-arch-swap",
        path=".chezmoiexternal.toml.tmpl",
        old='{{-   $ccStatuslineAsset = (eq $p.arch "arm64") | ternary "darwin-arm64" "darwin-x64" -}}',
        new='{{-   $ccStatuslineAsset = (eq $p.arch "arm64") | ternary "darwin-x64" "darwin-arm64" -}}',
        layer="L5",
        rationale=(
            "Intel Mac 拿到 arm64 的執行檔（Bad CPU type）。supply-chain 看不到這種錯："
            "sum 是按 asset 名稱查的，URL 與 pin 仍然一致、雜湊也仍然相符"
        ),
    ),
    Mutant(
        name="windows-path-not-included",
        path=".chezmoiscripts/run_onchange_before_50-neovim.ps1.tmpl",
        old='{{ includeTemplate "windows-path.ps1" . }}',
        new="",
        layer="L2",
        rationale=(
            "chezmoi 跑腳本時的 PATH 看不到 winget 剛裝好的 mise，於是走"
            "「mise not found, skipping neovim」那條路 —— 而那條路以 exit 0 結束，"
            "整個 neovim/LazyVim 安裝靜靜地沒發生"
        ),
    ),
    Mutant(
        name="pwsh-profile-theme-name",
        path="private_dot_config/powershell/profile.ps1.tmpl",
        old="'.config/oh-my-posh/powerlevel10k_rainbow.omp.json'",
        new="'.config/oh-my-posh/p10k_rainbow.omp.json'",
        layer="L2",
        rationale=(
            "external 裝的檔名與 profile 讀的檔名不一致，profile 的 Test-Path 守衛"
            "會靜靜跳過 oh-my-posh 初始化：使用者只看到沒有主題的提示字元，沒有錯誤"
        ),
    ),
    Mutant(
        name="posix-script-content-drift",
        path=".chezmoiscripts/run_onchange_before_30-install-brew-packages.sh.tmpl",
        old="for formula in mise fzf git-lfs ripgrep fd lazygit tree-sitter; do",
        new="for formula in mise fzf git-lfs ripgrep fd lazygit; do",
        layer="L10",
        rationale=(
            "把 AGENTS.md 明文禁止修剪的 tree-sitter 拿掉 —— 改變了 Linux/macOS 的"
            "既有行為（Must NOT #2）。L10 原本帶 --exclude=scripts，腳本內容從來"
            "沒有跟 base 比對過，這個 mutant 一度可以存活整套測試"
        ),
    ),
    Mutant(
        name="pwsh-profile-loader-not-called",
        path=".chezmoiscripts/run_after_60-pwsh-profile.ps1.tmpl",
        old='{{ includeTemplate "pwsh-profile-loader.ps1" . }}',
        new="",
        layer="L11",
        rationale=(
            "腳本設好 $target 之後什麼都不做：$PROFILE 永遠拿不到那一行 loader，"
            "於是 oh-my-posh、PSReadLine、PSFzf、mise 全部不會載入 —— "
            "整個 Windows shell 設定靜靜地不存在"
        ),
    ),
    Mutant(
        name="windows-nvim-plugin-content",
        path="AppData/Local/nvim/lua/plugins/completion.lua.tmpl",
        old='{{ template "nvim-plugins-completion.lua" . }}',
        new="return {}",
        layer="L11",
        rationale="Windows 的 nvim plugin 落點內容被換掉，與 POSIX 那一份不再是同一個東西",
    ),
    Mutant(
        name="winget-drop-tree-sitter",
        path=".chezmoiscripts/run_onchange_before_30-install-winget-packages.ps1.tmpl",
        old="    'tree-sitter.tree-sitter-cli'\n",
        new="",
        layer="L11",
        rationale=(
            "AGENTS.md 明文禁止修剪的那一項，Windows 版。"
            "POSIX 的鏡像（posix-script-content-drift）由 L10 對 base ref 比對擋下，"
            "Windows 沒有 base 可比，這一條就是 L11 存在的理由"
        ),
    ),
    Mutant(
        name="windows-path-drop-git",
        path=".chezmoitemplates/windows-path.ps1",
        old="    (Join-Path $env:ProgramFiles 'Git\\cmd')\n",
        new="",
        layer="L11",
        rationale="PATH 補強少了 Git，腳本在 git 只裝在 Program Files 的機器上會找不到它",
    ),
    Mutant(
        name="codex-empty-tui-crash",
        path="dot_codex/modify_private_config.toml",
        old="{{-       if ge $last 0 -}}{{- $head = slice $buf 0 (add $last 1) -}}{{- end -}}",
        new="{{-       $head = slice $buf 0 (add $last 1) -}}",
        layer="L6",
        rationale="空的 [tui] 讓 slice 得到 nil，concat 解參考它 → 整個 apply 以非零結束",
    ),
]


def run(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", type=Path, default=None)
    args = parser.parse_args()

    # 產品樹必須乾淨：mutant 是在 HEAD 的複本上套的，工作樹有未提交的東西就代表
    # 複本跟被驗證的東西不是同一份。
    status = run(["git", "status", "--porcelain"], REPO)
    dirty = [
        line
        for line in status.stdout.splitlines()
        if line and not line.startswith("?? .gate/")
    ]
    if dirty:
        print("gate-mutants: 工作樹不乾淨，拒絕執行：", file=sys.stderr)
        print("\n".join(dirty), file=sys.stderr)
        return 1

    tmp = Path(tempfile.mkdtemp(prefix="gate-mutants-"))
    worktree = tmp / "wt"
    created = run(["git", "worktree", "add", "--detach", str(worktree), "HEAD"], REPO)
    if created.returncode != 0:
        print("gate-mutants: 建不出 worktree", created.stderr, file=sys.stderr)
        shutil.rmtree(tmp, ignore_errors=True)
        return 1

    results = []
    failed = False
    try:
        # 先確認未突變的複本本身是綠的。這是「基線」控制：如果它本來就紅，
        # 後面每一個 mutant 的 kill 都可能是它造成的，整輪分數沒有意義。
        env = dict(os.environ)
        baseline_layers = sorted({m.layer for m in MUTANTS})
        base = run(["sh", "tests/run.sh", *baseline_layers], worktree)
        if base.returncode != 0:
            print("gate-mutants: 未突變的基線就是紅的，本輪分數無效", file=sys.stderr)
            print(base.stdout[-3000:], file=sys.stderr)
            return 1
        baseline_out = base.stdout

        for m in MUTANTS:
            target = worktree / m.path
            original = target.read_text(encoding="utf-8")

            if m.old not in original:
                print(
                    f"gate-mutants: [{m.name}] 找不到要替換的內容於 {m.path}"
                    " —— 程式碼變了就要同步更新這個 mutant",
                    file=sys.stderr,
                )
                failed = True
                results.append({"name": m.name, "status": "PATCH-FAILED"})
                continue

            mutated = original.replace(m.old, m.new, 1)
            if mutated == original:
                print(f"gate-mutants: [{m.name}] 套用後檔案沒有變化", file=sys.stderr)
                failed = True
                results.append({"name": m.name, "status": "PATCH-NOOP"})
                continue

            target.write_text(mutated, encoding="utf-8")
            # 證明它真的被套上去了，而不是只在記憶體裡改過。
            assert target.read_text(encoding="utf-8") == mutated

            proc = run(["sh", "tests/run.sh", m.layer], worktree)
            target.write_text(original, encoding="utf-8")
            assert target.read_text(encoding="utf-8") == original

            killed = proc.returncode != 0
            failing = [
                line for line in proc.stdout.splitlines() if line.startswith("not ok")
            ]
            results.append(
                {
                    "name": m.name,
                    "path": m.path,
                    "layer": m.layer,
                    "rationale": m.rationale,
                    "status": "KILLED" if killed else "SURVIVED",
                    "exit_code": proc.returncode,
                    "failing_assertions": failing,
                }
            )
            if killed:
                print(f"KILLED   {m.name} ({m.layer}, {len(failing)} 條斷言失敗)")
            else:
                print(f"SURVIVED {m.name} ({m.layer}) -- {m.rationale}")
                failed = True
    finally:
        run(["git", "worktree", "remove", "--force", str(worktree)], REPO)
        shutil.rmtree(tmp, ignore_errors=True)

    killed_n = sum(1 for r in results if r.get("status") == "KILLED")
    print(f"\ngate-mutants: {killed_n}/{len(MUTANTS)} killed")

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(
            json.dumps(
                {"baseline_tail": baseline_out[-2000:], "mutants": results},
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
