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
                "scripts",
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


if __name__ == "__main__":
    unittest.main()
