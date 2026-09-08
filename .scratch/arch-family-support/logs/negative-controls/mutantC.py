import io
p = "/tmp/verify/mutant1/tests/sandbox/_probe.sh"
with io.open(p, "r", encoding="utf-8", newline="") as f:
    content = f.read()
old = 'if [ $arch = 1 ] && pacman -Q omarchy-nvim >/dev/null 2>&1; then omarchy=1; fi'
new = 'if [ $arch = 1 ] && pacman -Q some-other-pkg >/dev/null 2>&1; then omarchy=1; fi'
assert content.count(old) == 1, content.count(old)
content = content.replace(old, new)
with io.open(p, "w", encoding="utf-8", newline="") as f:
    f.write(content)
print("patched")
