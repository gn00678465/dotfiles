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

每個 mutant 預設跑兩輪。單跑一輪沒辦法區分「這個 mutant 一定會被殺」與
「這一次剛好被殺」——suite-health 那一層重跑的是**未突變**的套件，看不到這件事。
獨立驗證就是在這裡抓到一個 kill 取決於兩次執行是否落在同一個 wall-clock 秒
（7 次裡存活 2 次），而報告當時寫的是「17/17，逐一檢查」。

Usage: tools/gate-mutants.py [--repeat N]
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
        name="backup-timestamp-fallback",
        path=".chezmoiscripts/run_onchange_before_50-neovim.sh.tmpl",
        old=(
            "  if [[ -e $dest ]]; then\n"
            '    dest="$1.bak.$(date +%Y%m%d%H%M%S)"\n'
            "  fi\n"
        ),
        new="",
        layer="L7",
        rationale="第二次 bootstrap 直接沿用 dir.bak，把上一份備份埋進新的備份裡",
    ),
    Mutant(
        name="backup-timestamp-fallback-windows",
        path=".chezmoiscripts/run_onchange_before_50-neovim.ps1.tmpl",
        old=(
            "    if (Test-Path -LiteralPath $dest) {\n"
            "        $dest = \"$Path.bak.$(Get-Date -Format 'yyyyMMddHHmmss')\"\n"
            "    }\n"
        ),
        new="",
        layer="L7",
        rationale=(
            "Windows 端第二次 bootstrap 直接沿用 dir.bak，把上一份備份埋掉。"
            "POSIX 那半有 L10 逐位元組比對兜底，Windows 這半沒有 base 可比，"
            "只有 L7 能證偽它"
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
        name="neovim-skip-aborts-apply",
        path=".chezmoiscripts/run_onchange_before_50-neovim.ps1.tmpl",
        old="    Write-Warning 'chezmoi: mise not found, skipping neovim'",
        new="    Write-Error 'chezmoi: mise not found, skipping neovim'",
        layer="L7",
        rationale=(
            "$ErrorActionPreference = 'Stop' 之下 Write-Error 是終止性的，後面的 exit 0 "
            "到不了。這支是 run_onchange_before_，非零退出會在任何檔案被寫出來之前中止"
            "整個 apply —— 使用者連 PowerShell profile 都拿不到"
        ),
    ),
    Mutant(
        name="seam-leaks-into-production-config",
        path=".chezmoi.toml.tmpl",
        old="[data]\n    isWSL = {{ $isWSL }}",
        new='[data]\n    osOverride = "linux"\n    isWSL = {{ $isWSL }}',
        layer="L1",
        rationale=(
            "測試接縫漏進生產用的 config：Windows 上會拿 .sh 去 exec 而中止 apply（M1、"
            "Must NOT #4），managed 也會變成 POSIX 的那一組（M7）。整個 Windows 與 macOS "
            "的證據都建立在這個檔案沒有那兩個 key 上"
        ),
    ),
    Mutant(
        name="init-drops-git-bootstrap",
        path="init.ps1",
        old="Install-IfMissing -Id 'Git.Git'              -Command 'git'\n",
        new="",
        layer="L11",
        rationale=(
            "乾淨的 Windows 11 沒有 git，chezmoi 因此 clone 不了，自舉直接死掉。"
            "supply-chain 只驗『列出來的 ID 解析得到』，少一個它不會失敗"
        ),
    ),
    Mutant(
        name="probe-drops-m12-check",
        path="tests/sandbox/_probe.ps1",
        old="Check 'nvim-treesitter builds a parser (SPEC M12)' {",
        new="Check 'nvim-treesitter parser (skipped)' {",
        layer="L11",
        rationale=(
            "sandbox 探針是 M12 唯一的量測工具；它悄悄少掉那項檢查，我們會拿到一份"
            "看起來通過、實際上沒問過那個問題的結果"
        ),
    ),
    Mutant(
        name="init-git-bootstrap-commented-out",
        path="init.ps1",
        old="Install-IfMissing -Id 'Git.Git'              -Command 'git'",
        new="# Install-IfMissing -Id 'Git.Git'              -Command 'git'",
        layer="L11",
        rationale=(
            "把整行註解掉而不是刪掉。子字串斷言仍然看得到它，supply-chain 的正則也"
            "仍然會在註解裡匹配到那個 ID —— 兩者都不會失敗，但乾淨的 Windows 11 上"
            "git 不會被裝，chezmoi 因此 clone 不了"
        ),
    ),
    Mutant(
        name="init-owner-overridden-later",
        path="init.ps1",
        old="Write-Host \"init: chezmoi $($chezmoiArgs -join ' ')\"",
        new=(
            "$chezmoiArgs = @('init', '--apply', 'attacker/dotfiles')\n"
            "Write-Host \"init: chezmoi $($chezmoiArgs -join ' ')\""
        ),
        layer="L11",
        rationale=(
            "在正確的那一行之後再賦值一次別的帳號。子字串斷言只驗「正確那行存在」，"
            "覆寫它的那一行看不到 —— irm | iex 會 clone 並套用別人的 dotfiles"
        ),
    ),
    Mutant(
        name="probe-m12-body-gutted",
        path="tests/sandbox/_probe.ps1",
        old="    $job = Start-Job -ScriptBlock {",
        new="    return 'skipped'\n    $job = Start-Job -ScriptBlock {",
        layer="L11",
        rationale=(
            "保留 M12 檢查的標題、把內容換掉。這正是那條斷言的註解說它要防的事："
            "拿到一份看起來通過、實際上沒問過那個問題的結果"
        ),
    ),
    Mutant(
        name="test-layer-L8-deleted",
        path="tests/cases/L8-windows-seam.sh",
        old="# L8 — 用 Windows 主機上真實的 chezmoi 驗證測試接縫本身。",
        new="return 0\n# L8 — 用 Windows 主機上真實的 chezmoi 驗證測試接縫本身。",
        # 跑 L8 本身：runner 的「這一層貢獻了幾條斷言」檢查只涵蓋被選到的層，
        # 而那正是它該有的範圍（跑子集是正當用法）。
        layer="L8",
        rationale=(
            "L8 是 SPEC 對 M8 唯一指名的程序，而沒有任何 mutant 指向它 —— "
            "整層失效不會讓 gate 變紅。這份報告每一條 Windows 與 macOS 的主張"
            "都是經由那個接縫推導出來的"
        ),
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
    # errors="replace" 不是防禦性寫法，是對一段實測輸出的處理：L7 的 Windows 半邊
    # 用 pwsh.exe 跑腳本，而 pwsh.exe 的工作目錄是 UNC 路徑（\\wsl.localhost\...）時，
    # cmd.exe 會先吐一行「不支援 UNC 路徑」的警告，用主機的 ANSI 代碼頁編碼
    # （這台是 CP950）。那行只會在斷言失敗、_fail 把 pwsh 的輸出印進診斷時出現，
    # 也就是**只在 mutant 被殺掉的時候**。嚴格 UTF-8 解碼會在那一刻拋例外，
    # 於是「這個 mutant 死了」被誤報成「跑不完」，整個 gate 中斷。實際發生過一次。
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                          errors="replace")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", type=Path, default=None)
    parser.add_argument("--repeat", type=int, default=2,
                        help="每個 mutant 重複幾輪；全部輪次都要致死才算 KILLED")
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

            rounds = []
            for _ in range(max(1, args.repeat)):
                proc = run(["sh", "tests/run.sh", m.layer], worktree)
                rounds.append(
                    (proc.returncode,
                     [l for l in proc.stdout.splitlines() if l.startswith("not ok")])
                )
            target.write_text(original, encoding="utf-8")
            assert target.read_text(encoding="utf-8") == original

            # 每一輪都要紅。有一輪沒紅就是「這個 kill 不是決定性的」，
            # 那跟存活一樣不能算數。
            killed = all(rc != 0 for rc, _ in rounds)
            failing = rounds[0][1]
            unstable = len({rc != 0 for rc, _ in rounds}) > 1
            results.append(
                {
                    "name": m.name,
                    "path": m.path,
                    "layer": m.layer,
                    "rationale": m.rationale,
                    "status": "KILLED" if killed else ("UNSTABLE" if unstable else "SURVIVED"),
                    "rounds": [{"exit_code": rc, "failing": len(f)} for rc, f in rounds],
                    "failing_assertions": failing,
                }
            )
            if killed:
                print(f"KILLED   {m.name} ({m.layer}, {len(failing)} 條斷言失敗, "
                      f"{len(rounds)}/{len(rounds)} 輪皆致死)")
            elif unstable:
                print(f"UNSTABLE {m.name} ({m.layer}) -- kill 不是決定性的: "
                      f"{[rc for rc, _ in rounds]}")
                failed = True
            else:
                print(f"SURVIVED {m.name} ({m.layer}) -- {m.rationale}")
                failed = True
    finally:
        run(["git", "worktree", "remove", "--force", str(worktree)], REPO)
        shutil.rmtree(tmp, ignore_errors=True)

    killed_n = sum(1 for r in results if r.get("status") == "KILLED")
    print(f"\ngate-mutants: {killed_n}/{len(MUTANTS)} killed"
          f"（每個 mutant 跑 {max(1, args.repeat)} 輪，全部輪次都要紅才算 killed）")

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
