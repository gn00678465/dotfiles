"""Public chezmoi rendering contracts for the supported operating systems."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
UNIX_INSTALL_TEMPLATES = tuple(sorted((REPOSITORY / ".chezmoiscripts").glob("*.sh.tmpl")))
WINDOWS_PROFILE_TEMPLATE = (
    REPOSITORY / ".chezmoiscripts" / "run_onchange_after_45-powershell-profile.ps1.tmpl"
)


def chezmoi_arguments(os_name: str, arch: str = "amd64") -> list[str]:
    return ["--override-data", json.dumps({"chezmoi": {"os": os_name, "arch": arch}})]


def render(source: Path, os_name: str, arch: str = "amd64") -> str:
    result = subprocess.run(
        [
            "chezmoi",
            "execute-template",
            *chezmoi_arguments(os_name, arch),
            "--file",
            str(source),
        ],
        cwd=REPOSITORY,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout


def applied_paths(os_name: str, arch: str = "amd64") -> set[str]:
    with tempfile.TemporaryDirectory() as destination:
        persistent_state = Path(destination) / "chezmoistate.boltdb"
        subprocess.run(
            [
                "chezmoi",
                "apply",
                "--source",
                str(REPOSITORY),
                "--destination",
                destination,
                "--persistent-state",
                str(persistent_state),
                "--force",
                "--no-tty",
                "--exclude",
                "scripts,externals",
                "--refresh-externals=never",
                *chezmoi_arguments(os_name, arch),
            ],
            cwd=REPOSITORY,
            check=True,
            capture_output=True,
            text=True,
        )
        destination_path = Path(destination)
        return {
            path.relative_to(destination_path).as_posix()
            for path in destination_path.rglob("*")
            if path.is_file()
        }


class ChezmoiTemplateContractTests(unittest.TestCase):
    def test_windows_renders_powershell_not_zsh_shell_config(self) -> None:
        """A native Windows source state contains no Unix shell artifacts."""
        for template in UNIX_INSTALL_TEMPLATES:
            self.assertEqual("", render(template, "windows"), template.name)

        self.assertTrue(WINDOWS_PROFILE_TEMPLATE.is_file())
        self.assertIn(
            "oh-my-posh init pwsh --config 'powerlevel10k_rainbow' --strict | Invoke-Expression",
            render(WINDOWS_PROFILE_TEMPLATE, "windows"),
        )

        paths = applied_paths("windows")
        self.assertNotIn(".zshrc", paths)
        self.assertNotIn(".p10k.zsh", paths)
        self.assertNotIn("tests/test_chezmoi_templates.py", paths)

    def test_unix_renders_only_unix_scripts_and_zsh_config(self) -> None:
        """Linux/macOS retain their shell contract and render no PowerShell scripts."""
        for os_name in ("linux", "darwin"):
            self.assertEqual("", render(WINDOWS_PROFILE_TEMPLATE, os_name))
            self.assertNotEqual("", render(REPOSITORY / "dot_zshrc.tmpl", os_name))
            self.assertNotEqual("", render(REPOSITORY / "dot_zprofile.tmpl", os_name))
            self.assertIn(".oh-my-zsh", render(REPOSITORY / ".chezmoiexternal.toml.tmpl", os_name))
            self.assertNotIn(".zshrc", render(REPOSITORY / ".chezmoiignore", os_name))
            self.assertNotIn(".zprofile", render(REPOSITORY / ".chezmoiignore", os_name))
            self.assertNotIn(".p10k.zsh", render(REPOSITORY / ".chezmoiignore", os_name))

        self.assertTrue((REPOSITORY / "dot_p10k.zsh").is_file())

        for template in UNIX_INSTALL_TEMPLATES:
            self.assertNotEqual("", render(template, "linux"), template.name)

        for template in (
            REPOSITORY / ".chezmoiscripts" / "run_once_before_20-install-homebrew.sh.tmpl",
            REPOSITORY / ".chezmoiscripts" / "run_onchange_before_30-install-brew-packages.sh.tmpl",
            REPOSITORY / ".chezmoiscripts" / "run_onchange_after_40-git-lfs.sh.tmpl",
            REPOSITORY / ".chezmoiscripts" / "run_onchange_before_50-neovim.sh.tmpl",
        ):
            self.assertNotEqual("", render(template, "darwin"), template.name)

        for template in (
            REPOSITORY / ".chezmoiscripts" / "run_after_default-shell.sh.tmpl",
            REPOSITORY / ".chezmoiscripts" / "run_onchange_before_10-install-packages.sh.tmpl",
        ):
            self.assertEqual("", render(template, "darwin"), template.name)

    def test_windows_nvim_target_path(self) -> None:
        """Windows applies this repository's Nvim override at LocalAppData."""
        paths = applied_paths("windows")
        self.assertIn("AppData/Local/nvim/lua/plugins/completion.lua", paths)
        self.assertNotIn(".config/nvim/lua/plugins/completion.lua", paths)


if __name__ == "__main__":
    unittest.main()
