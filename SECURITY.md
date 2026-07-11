# Security Policy

## Reporting a vulnerability

If you discover a security vulnerability in safeinstall-verifier, **do not
open a public issue.** Report it privately via email:

**Michael@acpip.io**

Include a description, steps to reproduce, and impact assessment. Response
timeline as for SafeInstall itself: acknowledgement within 48 hours, initial
assessment within 5 business days, coordinated fix and disclosure.

## Scope

In scope:

- Any way a repository **being verified** can influence the verification
  logic, the pinned CLI resolution, or the check result (the candidate must
  remain inert data).
- Weaknesses in the sha512 pin gate (`scripts/install-pinned-cli.sh`).
- Adversarial-suite blind spots: a tampering class the suite claims to catch
  but does not.

Out of scope:

- Findings that require rewriting **this** repository's history or merging a
  PR here (that is what CODEOWNERS, the branch ruleset, and review are for).
- The documented K2 residual below.

## Honest residual (read before relying on this repo)

- A **fully consistent rewrite** of a protected repository's policy, trust
  lock, and ledger passes automated verification on any fresh machine
  (RFC-001 §13 K2 in the SafeInstall repository). The security boundary for
  that case is human review of the trust-surface diff.
- SafeInstall is currently maintained **solo** (owner decision, 2026-07-11,
  [SafeInstall#41](https://github.com/Mickdownunder/SafeInstall/issues/41)):
  there is no second trusted maintainer, so "independent human review" of
  trust-surface changes in the SafeInstall repository means review by the
  same single owner who merges. A second reviewer will be added organically
  from the contributor pool, not appointed for availability — every added
  key is added attack surface. Until then, treat the guarantee exactly as
  stated: automatic tamper-evidence against inconsistent changes, external
  SHA-pinned verification logic, single-human review as the last layer.

Last verified: 2026-07-11
