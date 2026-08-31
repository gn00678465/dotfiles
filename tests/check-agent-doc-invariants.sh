#!/bin/sh
# Cross-file invariants for the evidence-first contract machinery.
# These documents promise each other things (status vocabularies, report
# fields, shared tier/anti-gaming definitions); this check makes drift
# between them a red exit instead of a silent divergence.
#
# Fail closed: no `set -e` reliance — every command status is handled
# explicitly. rc 1 = invariant broken, rc 2 = the check itself broke.
# Usage: tests/check-agent-doc-invariants.sh [repo-root]

set -u

ROOT=${1:-$(cd "$(dirname "$0")/.." && pwd)} || exit 2

CONTRACT="$ROOT/.chezmoitemplates/evidence-first-contract.md"
PROTOCOL="$ROOT/.chezmoitemplates/verifier-protocol.md"
WORKFLOW="$ROOT/dot_agents/workflow/evidence-first.md"
SPEC_T="$ROOT/dot_agents/workflow/templates/spec.md"
VERIF_T="$ROOT/dot_agents/workflow/templates/verification.md"
SKILL="$ROOT/dot_agents/skills/verification-gate/SKILL.md"
EVIDENCE_T="$ROOT/dot_agents/skills/verification-gate/assets/templates/evidence.md"

CHECKS=0

require() { # <file> <description> <fixed string that must be present>
  file=$1 desc=$2 pattern=$3
  [ -s "$file" ] || { echo "FAIL: missing or empty file: $file" >&2; exit 2; }
  grep -Fq -- "$pattern" "$file"
  rc=$?
  case $rc in
    0) CHECKS=$((CHECKS + 1)) ;;
    1) echo "FAIL: $desc — '$pattern' not found in $file" >&2; exit 1 ;;
    *) echo "FAIL: check itself broke (grep rc=$rc) on $file" >&2; exit 2 ;;
  esac
}

count_numbered_rules() { # <file> <section heading prefix> <expected count>
  file=$1 heading=$2 expected=$3
  [ -s "$file" ] || { echo "FAIL: missing or empty file: $file" >&2; exit 2; }
  n=$(awk -v h="$heading" '
    index($0, h) == 1 { flag = 1; next }
    /^## / { flag = 0 }
    flag && /^[0-9]+\./ { c++ }
    END { print c + 0 }
  ' "$file")
  rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: check itself broke (awk rc=$rc) on $file" >&2; exit 2; }
  if [ "$n" -eq "$expected" ]; then
    CHECKS=$((CHECKS + 1))
  else
    echo "FAIL: '$heading' in $file has $n numbered rules, expected $expected" >&2
    exit 1
  fi
}

# 1. Layer-status vocabulary: SKILL.md and the evidence template must carry
#    the same five states — a status one side names and the other cannot
#    record is exactly the drift this file exists to catch.
for status in "N-A" "UNAVAILABLE" "SUBSTITUTED" "NOT REACHED" "DEPENDENCY UNMET"; do
  require "$SKILL" "layer status vocabulary" "$status"
  require "$EVIDENCE_T" "layer status vocabulary" "$status"
done

# 2. Report fields the contract promises must exist in the template.
require "$CONTRACT" "contract override marker" "overridden by"
require "$EVIDENCE_T" "contract header field" '`contract`:'
require "$EVIDENCE_T" "override value in contract field" "overridden by"
require "$EVIDENCE_T" "headline roll-up field" '`headline`'

# 3. Anti-gaming rules: same six on both sides of the split.
count_numbered_rules "$SKILL" "## Anti-Gaming Rules" 6
count_numbered_rules "$WORKFLOW" "## Anti-Gaming Rules" 6

# 4. Tier 3 domain list: one definition, all carriers.
for f in "$CONTRACT" "$SKILL" "$WORKFLOW" "$SPEC_T"; do
  require "$f" "tier 3 domain list" "money, auth, data"
done

# 5. Structured approval: contract states the rule; workflow and spec
#    template carry the artifact that satisfies it.
require "$CONTRACT" "structured approval rule" "structured act"
require "$WORKFLOW" "approval section reference" '`## Approval`'
require "$SPEC_T" "approval section" "## Approval"

# 6. Handoff wiring: the workflow points at artifacts that must exist.
require "$WORKFLOW" "spec template reference" "templates/spec.md"
require "$WORKFLOW" "verification template reference" "templates/verification.md"
require "$VERIF_T" "declared-downgrade state" "not performed"
require "$PROTOCOL" "verifier fail-closed state" "blocked"
require "$CONTRACT" "gate handoff" "verification-gate"

echo "OK: $CHECKS invariants hold"
