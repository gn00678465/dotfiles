#!/usr/bin/env python3
"""Build the fixture repo for one eval case.

Usage: build.py <eval-id> <target-dir>

Each case gets a fresh repo shaped to match its prompt, so a grader can
compare the repo before and after the run instead of reading the agent's
own report. The target directory must not exist. Case 11 also creates
`<target-dir>-main`, the main worktree that `<target-dir>` is linked to.
"""
import pathlib
import subprocess
import sys


def git(cwd, *args, stdin=None):
    subprocess.run(["git", "-c", "core.autocrlf=false", "-c", "commit.gpgsign=false", *args],
                   cwd=cwd, check=True, capture_output=True, input=stdin)


def write(root, rel, text):
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(text.encode("utf-8"))


def lines(prefix, n):
    return "".join(f"{prefix} line {i}\n" for i in range(1, n + 1))


def base(root, branch):
    root.mkdir(parents=True)
    git(root, "init", "-q", "-b", branch)
    git(root, "config", "user.name", "dev")
    git(root, "config", "user.email", "dev@example.com")
    write(root, "src/auth.ts", "export const auth = () => {\n  return session();\n}\n")
    write(root, "src/security.ts", "export const secure = () => true;\n")
    write(root, "src/api/auth.ts", "export const login = (u) => session(u);\n")
    write(root, "src/utils/helper.ts", "export const trim = (s) => s.trim();\n")
    write(root, "src/app.ts", "export const app = 1;\n")
    write(root, "package.json", '{\n  "name": "app",\n  "version": "1.0.0"\n}\n')
    write(root, "pnpm-lock.yaml", "lockfileVersion: 9.0\npackages: {}\n")
    write(root, "README.md", "# App\n")
    write(root, "docs/api.md", "# API\n")
    commit(root, "chore: 初始化專案\n")


def commit(root, msg):
    git(root, "add", "-A")
    git(root, "commit", "-q", "-F", "-", stdin=msg.encode("utf-8"))


def c00(r):
    base(r, "feat/login")
    write(r, "src/components/Login.tsx", "export const Login = () => <form />;\n")
    git(r, "add", "-A")


def c01(r):
    # One purpose across two files: the refactor and the helpers it extracted.
    base(r, "refactor/auth")
    write(r, "src/auth.ts", "import { verify } from './auth-helpers';\n" + lines("export const authStep", 80))
    write(r, "src/auth-helpers.ts", lines("export const verifyStep", 40))
    git(r, "add", "-A")


def c02(r):
    base(r, "main")
    write(r, "src/feature.ts", 'export const feature = () => "new";\n')
    git(r, "add", "-A")


def c03(r):
    base(r, "chore/deps")
    write(r, "pnpm-lock.yaml", "lockfileVersion: 9.0\npackages:\n  left-pad@1.3.0: {}\n")
    git(r, "add", "-A")


def c04(r):
    base(r, "feat/oauth")
    write(r, "src/api/auth.ts", "export const login = (token) => oauth2(token);\n// session endpoints removed\n")
    git(r, "add", "-A")


def c05(r):
    base(r, "refactor/utils")
    git(r, "mv", "src/utils/helper.ts", "src/utils/string-helper.ts")


def c06(r):
    base(r, "feat/multi")
    write(r, "src/auth.ts", lines("export const authLogic", 90))
    write(r, "src/security.ts", lines("export const secureLogic", 90))
    write(r, "pnpm-lock.yaml", "lockfileVersion: 9.0\npackages:\n  zod@3.0.0: {}\n")
    write(r, "migrations/001_add_users.sql", "CREATE TABLE users (id INTEGER PRIMARY KEY);\n")
    git(r, "add", "-A")


def c07(r):
    base(r, "test/login")
    write(r, "src/auth/__tests__/login.test.ts", 'test("login", () => {});\n')
    git(r, "add", "-A")


def c08(r):
    base(r, "docs/api")
    write(r, "README.md", "# App\n\nUsage notes.\n")
    write(r, "docs/api.md", "# API\n\n## GET /login\n")
    git(r, "add", "-A")


def c09(r):
    # Exactly what the prompt says: 11 files, +612/-23, 440 test lines.
    base(r, "fix/gate")
    for i in range(1, 5):
        write(r, f"src/gate{i}.ts", lines(f"export const gate{i}", 10))
    commit(r, "chore: 新增 gate 模組\n")
    for i, keep in zip(range(1, 5), (4, 4, 4, 5)):
        write(r, f"src/gate{i}.ts", lines(f"export const gate{i}", keep) + lines(f"export const gate{i}Fixed", 43))
    for i, n in zip(range(1, 8), (63, 63, 63, 63, 63, 63, 62)):
        write(r, f"tests/t{i}.test.ts", lines(f"test gate regression t{i}", n))
    git(r, "add", "-A")


def c10(r):
    base(r, "fix/isolation")
    write(r, "src/isolation.ts", "export const isolate = () => true;\n")
    write(r, "tests/isolation.test.ts", 'test("iso", () => {});\n')
    git(r, "add", "-A")


def c11(r):
    # r is the linked worktree; the main worktree lives beside it.
    main = r.parent / (r.name + "-main")
    base(main, "main")
    git(main, "worktree", "add", "-q", str(r), "-b", "feat/worktree")
    write(r, "src/app.ts", "export const a = 2;\n")
    write(r, "src/security.ts", "export const secure = () => false;\n")
    git(r, "add", "-A")


def c12(r):
    # 49-line message: subject, blank line, 47 lines of narrative.
    base(r, "feat/essay")
    write(r, "src/essay.ts", "export const essay = 1;\n")
    body = "".join(f"這是一段像作文一樣的說明第 {i} 行，描述過程與心路歷程。\n" for i in range(1, 48))
    commit(r, "feat: 新增 essay 模組\n\n" + body)


def c13(r):
    base(r, "feat/profile")
    write(r, "src/components/Profile.tsx", "export const Profile = () => null;\n")
    git(r, "add", "-A")


def c14(r):
    base(r, "main")
    write(r, "src/search.ts", "export const search = () => [];\n")
    git(r, "add", "-A")


def c15(r):
    base(r, "feat/auth-hardening")
    write(r, "src/auth.ts", lines("export const authHardened", 130))
    write(r, "src/security.ts", lines("export const secureHardened", 130))
    write(r, "tests/auth.test.ts", 'test("auth", () => {});\n')
    write(r, "docs/auth.md", "# Auth\n\nHardening notes.\n")
    git(r, "add", "-A")


def c16(r):
    # README.md partially staged: the install guide is staged, the draft paragraph is not.
    base(r, "feat/two-purposes")
    write(r, "src/auth.ts", lines("export const authFix", 5))
    write(r, "README.md", "# App\n\nInstall guide.\n")
    git(r, "add", "-A")
    write(r, "README.md", "# App\n\nInstall guide.\n\nUNSTAGED: draft paragraph\n")


def c17(r):
    base(r, "feat/long-msg")
    write(r, "src/x.ts", "export const x = 1;\n")
    commit(r, "feat: 新增 x 模組\n\n" + "".join(f"- 冗長的說明第 {i} 項\n" for i in range(1, 21)))
    write(r, "src/unrelated.ts", "export const unrelated = true;\n")
    git(r, "add", "src/unrelated.ts")


def c18(r):
    base(r, "feat/approved")
    write(r, "src/y.ts", "export const y = 1;\n")
    commit(r, "feat: 新增 y 模組並調整相關設定與說明文件的內容\n\n" + "".join(f"- 說明第 {i} 項\n" for i in range(1, 11)))


def c19(r):
    base(r, "fix/records")
    write(r, "src/rec.ts", "export const rec = 1;\n")
    git(r, "add", "-A")


def c20(r):
    base(r, "feat/remove-session")
    write(r, "src/api/auth.ts", "export const login = (token) => oauth2(token);\n")
    git(r, "add", "-A")


CASES = {i: globals()[f"c{i:02d}"] for i in range(21)}


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    case, target = int(sys.argv[1]), pathlib.Path(sys.argv[2]).resolve()
    if target.exists():
        sys.exit(f"target exists: {target}")
    CASES[case](target)
    print(target)


if __name__ == "__main__":
    main()
