# Security policy

Praxis Monitor is a **proprietary (all rights reserved)** local portfolio demonstration with synthetic data; the source is publicly viewable but not open source (see `LICENSE`). It has no authentication and no TLS and must not be exposed to untrusted networks or used with real patient data.

## Reporting a vulnerability

Please report suspected vulnerabilities privately via GitHub's **"Report a vulnerability"** (Security tab → Advisories) instead of opening a public issue. Expect an acknowledgement within a few days; this is a hobby/portfolio project without a service-level agreement.

## What is automated

- CodeQL (Java, JavaScript), gitleaks secret scanning, dependency review on pull requests, Dependabot updates (Maven, pub, GitHub Actions) – see `.github/workflows/security.yml` and `.github/dependabot.yml`.
- All GitHub Actions are pinned to commit SHAs and run with read-only permissions.
