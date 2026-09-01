#!/bin/sh
set -eu

python3 -m unittest discover -s tests -p 'test_*.py' -v

pwsh_bin=${PWSH:-pwsh}
pwsh_state_root=${PWSH_STATE_ROOT:-${TMPDIR:-/tmp}/dotfiles-windows-support-pwsh}
for test_name in Test-WingetPackageContract Test-ElevationFailureStopsApply Test-PwshProfileManagedBlockPreservesUserContent Test-ProfilePolicyFailureIsVisible Test-GitLfsRunsAfterTargetsApplied Test-FirstBootstrapPreservesUniquePaths Test-MarkerPreventsRebootstrap; do
  XDG_CACHE_HOME="$pwsh_state_root/cache" XDG_DATA_HOME="$pwsh_state_root/data" XDG_CONFIG_HOME="$pwsh_state_root/config" \
    "$pwsh_bin" -NoLogo -NoProfile -File tests/windows_support.ps1 -Test "$test_name"
done
