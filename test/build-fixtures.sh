#!/usr/bin/env bash
# Rebuild the committed adversarial fixtures with the PINNED safeinstall-cli.
#
# Run this only when bumping pin.json to a new CLI version, so the committed
# baselines are always the output of the exact CLI the action installs —
# never of an unreleased development build.
#
# Usage:
#   SAFEINSTALL_BIN="node /path/to/extracted/package/dist/cli.js" \
#     test/build-fixtures.sh
#
# The script is deterministic in content except for timestamps inside the
# ledger/lock, which are irrelevant to verification (hashes bind content).
set -euo pipefail

if [[ -z "${SAFEINSTALL_BIN:-}" ]]; then
  echo "Set SAFEINSTALL_BIN to the pinned CLI (e.g. 'node .../package/dist/cli.js')." >&2
  exit 2
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixtures="$here/fixtures"

rm -rf "$fixtures/project" "$fixtures/rewritten"
mkdir -p "$fixtures/project/.claude" "$fixtures/project/.github/workflows"

# --- Fixture project: a realistic locked repo ------------------------------

cat > "$fixtures/project/safeinstall.config.json" <<'JSON'
{
  "minimumReleaseAgeHours": 72,
  "registryUrl": "https://registry.npmjs.org",
  "allowedScripts": {},
  "allowedSources": ["registry", "workspace", "file", "directory"],
  "allowedPackages": [],
  "packageManagerDefaults": {
    "npm": { "ignoreScripts": true },
    "pnpm": { "ignoreScripts": true },
    "bun": { "ignoreScripts": true }
  }
}
JSON

cat > "$fixtures/project/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "safeinstall guard claude",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
JSON

# The CI trust workflow is enforcement-zone; inside the fixture it is inert
# data (fixtures do not live at a repository root, so Actions never runs it).
cat > "$fixtures/project/.github/workflows/safeinstall-trust.yml" <<'YAML'
name: SafeInstall Trusted Base Verification
on:
  pull_request_target:
    types: [opened, synchronize, reopened]
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  trust-base:
    runs-on: ubuntu-latest
    steps:
      - name: Check out pull request candidate as data
        if: github.event_name == 'pull_request_target'
        uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
        with:
          repository: ${{ github.event.pull_request.head.repo.full_name }}
          ref: ${{ github.event.pull_request.head.sha }}
          path: candidate
          persist-credentials: false
      - run: safeinstall trust status --require-lock
        working-directory: candidate
YAML

(cd "$fixtures/project" && $SAFEINSTALL_BIN trust lock)

# --- Rewritten variant: the internally CONSISTENT tampered baseline --------
# Simulates a scheme-aware attacker who weakens the policy and regenerates
# lock + ledger so every in-repo check agrees with itself. Used by the
# naive-consistent-rewrite case: overlaying these files onto a project whose
# out-of-workspace mirror already knows the honest chain must trip the
# mirror containment check.

cp -R "$fixtures/project" "$fixtures/rewritten"
rm -rf "$fixtures/rewritten/.safeinstall"
python3 - "$fixtures/rewritten/safeinstall.config.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    config = json.load(f)
config["minimumReleaseAgeHours"] = 0
config["registryUrl"] = "https://registry.attacker.example"
with open(path, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
PY
(cd "$fixtures/rewritten" && $SAFEINSTALL_BIN trust lock)

# Keep the rewritten variant minimal: only what the overlay needs.
rm -rf "$fixtures/rewritten/.claude" "$fixtures/rewritten/.github"

echo "Fixtures rebuilt. Commit test/fixtures/ so CI verifies against exactly these baselines."
