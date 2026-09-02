#Requires -Version 7
# Windows 的工具清單。對應 POSIX 端的 30-install-brew-packages：新工具加在這裡，
# 兩邊要一起加，不然 Windows 會少東西。
#
# Microsoft.PowerShell 與 Git.Git 刻意不在這張清單裡：chezmoi 要有 git 才能 clone
# 這個 repo，要有 pwsh 7 才能執行本檔（chezmoi 對 .ps1 的預設 interpreter 就是
# `pwsh -NoLogo -File`）。它們是 init.ps1 的自舉責任，跑到這裡時必然已經在了。
$ErrorActionPreference = 'Stop'

# chezmoi 跑腳本時不帶互動 shell 的 PATH（AGENTS.md 對 POSIX 端寫的
# `eval "$(brew shellenv)"` 就是同一個問題）。Windows 這邊還多一層：PATH 是
# process 啟動時的快照，所以同一次 apply 裡「前一支腳本剛用 winget 裝好的東西」
# 也不會出現在後一支腳本的 PATH 裡。這段是那兩件事共同的解法。
foreach ($dir in @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
    (Join-Path $env:LOCALAPPDATA 'mise\shims')
    (Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\bin')
    (Join-Path $env:ProgramFiles 'Git\cmd')
)) {
    if ((Test-Path -LiteralPath $dir) -and (($env:PATH -split ';') -notcontains $dir)) {
        $env:PATH = "$dir;$env:PATH"
    }
}


# zig 是給 nvim-treesitter 用的 C compiler。nvim-treesitter 的 main 分支用
# `tree-sitter build` 編每一個 parser，在 Windows 上預設找 MSVC 的 cl.exe；
# zig 是不必裝整套 Visual Studio Build Tools 的替代路徑。對應 Debian 那邊的
# build-essential。細節見 docs/research/windows-native-support.md。
$packages = @(
    'jdx.mise'
    'junegunn.fzf'
    'GitHub.GitLFS'
    'BurntSushi.ripgrep.MSVC'
    'sharkdp.fd'
    'JesseDuffield.lazygit'
    'tree-sitter.tree-sitter-cli'
    'JanDeDobbeleer.OhMyPosh'
    'zig.zig'
)

foreach ($id in $packages) {
    # winget list 找不到套件時退出碼非零。--exact 關掉前綴比對，否則
    # 'jdx.mise' 之類的 ID 會被別的套件名撞到。
    winget list --exact --id $id --accept-source-agreements *> $null
    if ($LASTEXITCODE -eq 0) { continue }

    Write-Output "chezmoi: winget install $id"
    # --source winget 把來源釘在社群 repo，避免同名套件在 msstore 那邊造成
    # 「需要選擇來源」的互動提示 —— chezmoi 是無人值守跑這支腳本的。
    winget install --exact --id $id --source winget --silent `
        --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "winget install $id failed with exit code $LASTEXITCODE"
    }
}
