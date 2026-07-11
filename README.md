# safeinstall-verifier

The external verification anchor for [SafeInstall](https://github.com/Mickdownunder/SafeInstall)'s
Agent Trust Surface. This repository exists so that the logic which verifies a
SafeInstall-protected repository **does not live inside the repository being
verified** — a pull request against the protected repo cannot weaken its own
verification, because the verification comes from here, referenced by full
commit SHA (RFC-001 §13, finding K1; owner decision of 2026-07-10).

## What it does

The composite action installs an **integrity-pinned** `safeinstall-cli`
(exact version + sha512 of the registry tarball, recorded in
[`pin.json`](pin.json)) and runs

```
safeinstall trust status --require-lock
```

against a candidate checkout that is treated strictly as data — no code from
the candidate is executed. Planned next (RFC-001 §10): `safeinstall decisions
verify` / `decisions authorize` for dependency decision records (L1).

## How to invoke it

From a workflow that is itself loaded from the protected base branch
(`pull_request_target`), with the candidate checked out as data:

```yaml
- name: Check out pull request candidate as data
  uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
  with:
    repository: ${{ github.event.pull_request.head.repo.full_name }}
    ref: ${{ github.event.pull_request.head.sha }}
    path: candidate
    persist-credentials: false

- name: SafeInstall trusted verification
  uses: Mickdownunder/safeinstall-verifier@<FULL 40-HEX COMMIT SHA>
  with:
    candidate-path: candidate
```

**Reference this action by full commit SHA only.** A branch or tag reference
re-introduces exactly the mutable indirection this repository exists to
remove. Bumping the SHA in the calling repository is an enforcement-zone
change there (the trust workflow is a locked file), so it is drift-visible
and review-required by construction.

## Why the layering holds

| Layer | Property | Where it comes from |
|---|---|---|
| Workflow definition | A PR cannot change what runs for its own check | `pull_request_target` loads the caller from the protected base branch |
| Verification steps | A PR against the caller cannot touch them at all | this repository, referenced by full commit SHA |
| Verifier binary | The registry cannot swap bytes for the pinned version | sha512 content pin in `pin.json` |
| Registry identity for future L1 re-fetching | Not repository configuration | verifier-side constant (RFC-001 §14 D3) |
| Changes to this repository | Owner-reviewed | CODEOWNERS on `*`, branch ruleset, required adversarial checks |

## What the adversarial suite proves — and what it cannot

[`test/run-adversarial.sh`](test/run-adversarial.sh) runs on every PR and
push. Each case asserts an expectation and prints a machine-readable
`RESULT` line; any violation fails CI:

| Case | Expectation |
|---|---|
| `clean` | the untampered fixture **passes** (the suite is not vacuous) |
| `tampered-workflow` | editing the locked CI workflow fails verification |
| `tampered-policy` | weakening `minimumReleaseAgeHours` fails verification |
| `tampered-registry` | redirecting `registryUrl` fails verification |
| `forged-lock` | editing the committed lock without the ledger fails (`lock-forged`) |
| `neutered-same-name` | a no-op workflow with identical workflow/job names fails on content |
| `removed-baseline` | a candidate without `.safeinstall/` fails `--require-lock` |
| `naive-consistent-rewrite` | a regenerated-but-consistent baseline overlaid where a mirror knows the honest chain fails (`mirror-mismatch`) — same-machine only |
| `corrupt-tarball` | the sha512 gate refuses a tarball that does not match the pin |

**Honest limits, stated so nobody relies on more than is delivered:**

- A **fully consistent rewrite** of policy + lock + ledger, evaluated on a
  machine with no prior mirror (every fresh CI clone), passes automated
  trust verification. This is RFC-001 §13 K2. The boundary for that case is
  human review of the trust-surface diff in the pull request — which is
  exactly what such a rewrite must appear in.
- The platform half of the anchor — GitHub loading `pull_request_target`
  workflow definitions from the base branch, and required status checks
  matching by name — is established platform behavior that this suite
  cannot reproduce in-process. The `neutered-same-name` case covers the
  content half (such a workflow is enforcement drift); the platform half is
  documented, not tested here.
- SafeInstall's maintainer model is currently **solo** (owner decision,
  2026-07-11, [SafeInstall#41](https://github.com/Mickdownunder/SafeInstall/issues/41)):
  platform-enforced second-party review of trust-surface paths does not
  exist yet and is deliberately not simulated. See SECURITY.md.

## Pin provenance

`pin.json` pins `safeinstall-cli@0.12.0` by the sha512 of its registry
tarball. Recorded 2026-07-11 from `https://registry.npmjs.org`
(`dist.integrity`), cross-checked by an independent download + local
`sha512` of the tarball bytes on the same day. The 0.12.0 release itself was
verified as a byte-identical rebuild from the `v0.12.0` tag at release time,
with Sigstore provenance via GitHub Actions trusted publishing.

### Bumping the pin

1. Open a PR here changing `pin.json` (version, tarball URL, sha512 from
   `dist.integrity` — cross-check with an independent download).
2. Rebuild the committed fixtures with the new pinned CLI:
   `SAFEINSTALL_BIN=… test/build-fixtures.sh` (see the script header).
3. CI must be green (the adversarial suite now runs against the new CLI).
4. After merge, bump the commit SHA reference in the calling repository —
   an enforcement-zone change there, requiring the owner's interactive
   `safeinstall trust approve`.

## License

MIT.
