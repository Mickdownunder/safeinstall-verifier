#!/usr/bin/env bash
# Adversarial suite: every tampering class this verifier claims to catch must
# actually FAIL verification, and the clean fixture must PASS (so a vacuous,
# always-failing or always-passing verifier can never go green).
#
# Each case prints one machine-readable line:
#   RESULT case=<name> expected=<pass|fail> observed=<pass|fail> verdict=<ok|VIOLATION>
#
# Usage:
#   SAFEINSTALL_BIN=safeinstall test/run-adversarial.sh
#
# Honest scope (do not widen it): a FULLY consistent rewrite of config + lock
# + ledger on a machine with no prior mirror — e.g. any fresh CI clone — is
# NOT caught by trust verification. That is RFC-001 §13 K2; the boundary for
# it is human review of the trust-surface diff, documented in SECURITY.md.
set -uo pipefail

BIN=${SAFEINSTALL_BIN:-safeinstall}
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixtures="$here/fixtures"
work="$(mktemp -d)"
violations=0

run_case() {
  local name="$1" expected="$2" setup="$3"
  local dir="$work/$name"
  cp -R "$fixtures/project" "$dir"
  (cd "$dir" && eval "$setup") || {
    echo "RESULT case=$name expected=$expected observed=setup-error verdict=VIOLATION"
    violations=$((violations + 1))
    return
  }
  local observed
  if (cd "$dir" && $BIN trust status --require-lock >/dev/null 2>&1); then
    observed=pass
  else
    observed=fail
  fi
  local verdict=ok
  if [[ "$observed" != "$expected" ]]; then
    verdict=VIOLATION
    violations=$((violations + 1))
  fi
  echo "RESULT case=$name expected=$expected observed=$observed verdict=$verdict"
}

# 0. The clean fixture verifies. Everything below only means something
#    because this line stays green.
run_case clean pass ':'

# 1. Tampered CI workflow (the anchor itself) — enforcement drift.
run_case tampered-workflow fail \
  'printf "\n      - run: echo neutered\n" >> .github/workflows/safeinstall-trust.yml'

# 2. Weakened policy — enforcement drift.
run_case tampered-policy fail \
  'python3 -c "
import json
c = json.load(open(\"safeinstall.config.json\"))
c[\"minimumReleaseAgeHours\"] = 0
json.dump(c, open(\"safeinstall.config.json\", \"w\"), indent=2)
"'

# 3. Redirected registry — enforcement drift (and, once decision records
#    land, additionally a hard registry-not-default finding per RFC-001 D3).
run_case tampered-registry fail \
  'python3 -c "
import json
c = json.load(open(\"safeinstall.config.json\"))
c[\"registryUrl\"] = \"https://registry.attacker.example\"
json.dump(c, open(\"safeinstall.config.json\", \"w\"), indent=2)
"'

# 4. Forged lock: edit the committed lock without the ledger — the baseline
#    hash recorded in the hash-chained ledger no longer matches (lock-forged).
run_case forged-lock fail \
  'python3 -c "
import json
lock = json.load(open(\".safeinstall/trust-surface.lock\"))
lock[\"mode\"] = \"warn\" if lock[\"mode\"] == \"strict\" else \"strict\"
json.dump(lock, open(\".safeinstall/trust-surface.lock\", \"w\"), indent=2)
"'

# 5. Identically-named-but-neutered check: a no-op workflow that keeps the
#    workflow name AND job name. Required status checks match by name, so
#    this must fail on content, not on naming. (The platform half of the
#    defense — pull_request_target loading the definition from the base
#    branch, so a PR cannot swap what runs for itself — is GitHub behavior
#    this suite cannot reproduce; see README "What this suite proves".)
run_case neutered-same-name fail \
  'cat > .github/workflows/safeinstall-trust.yml <<EOF
name: SafeInstall Trusted Base Verification
on:
  pull_request_target:
    types: [opened, synchronize, reopened]
permissions:
  contents: read
jobs:
  trust-base:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
EOF'

# 6. Removed baseline — --require-lock must refuse an unlocked candidate.
run_case removed-baseline fail 'rm -rf .safeinstall'

# 7. Naive consistent rewrite: config + lock + ledger regenerated into an
#    internally consistent state (attacker replicating the baseline format),
#    overlaid on a machine whose out-of-workspace mirror knows the honest
#    chain. The mirror containment check must flag the foreign chain.
#    Same-machine only, by design — see the honest-scope note above.
run_case naive-consistent-rewrite fail \
  "$BIN trust status --require-lock >/dev/null 2>&1;
   cp \"$fixtures/rewritten/safeinstall.config.json\" safeinstall.config.json &&
   rm -rf .safeinstall && cp -R \"$fixtures/rewritten/.safeinstall\" .safeinstall"

# 8. Corrupt verifier tarball: the sha512 gate in install-pinned-cli.sh must
#    refuse bytes that do not match the pin, whatever the registry serves.
corrupt_tarball_case() {
  local name=corrupt-tarball expected=fail observed verdict=ok
  local tmpdir="$work/$name"
  mkdir -p "$tmpdir"
  local url sha
  url=$(jq -r .tarballUrl "$here/../pin.json")
  curl -fsSL "$url" -o "$tmpdir/original.tgz"
  cp "$tmpdir/original.tgz" "$tmpdir/corrupt.tgz"
  printf 'X' >> "$tmpdir/corrupt.tgz"
  if "$here/../scripts/install-pinned-cli.sh" --tarball "$tmpdir/corrupt.tgz" \
      --prefix "$tmpdir/prefix" >/dev/null 2>&1; then
    observed=pass
  else
    observed=fail
  fi
  if [[ "$observed" != "$expected" ]]; then
    verdict=VIOLATION
    violations=$((violations + 1))
  fi
  echo "RESULT case=$name expected=$expected observed=$observed verdict=$verdict"
}
corrupt_tarball_case

if [[ "$violations" -gt 0 ]]; then
  echo "ADVERSARIAL SUITE: $violations violation(s)." >&2
  exit 1
fi
echo "ADVERSARIAL SUITE: all expectations held."
