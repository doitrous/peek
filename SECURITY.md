# Security Policy

## Supported Versions

Peek is pre-1.0 and ships from `main`. Security fixes are applied to the latest
release only; please update before reporting.

| Version | Supported |
| ------------------------------- | :-------: |
| Latest release / current `main` | ✅ |
| Any older build                 | ❌ |

## Reporting a Vulnerability

**Please do not open a public issue for security problems** — that discloses the
vulnerability before there's a fix.

Instead, report it privately through GitHub's private vulnerability reporting:

1. Open the **Security** tab of this repository.
2. Click **Report a vulnerability** (under *Reporting*).
3. Include the affected version, steps to reproduce, and impact.

This creates a private advisory visible only to you and the maintainers. If private
reporting is unavailable to you, open a normal issue that says only *"security report,
please enable private reporting"* — with **no details** — and a maintainer will follow up.

### What to expect

- **Acknowledgement:** within about 3 business days.
- **Assessment:** we confirm the issue and its severity, and keep you updated.
- **Fix & disclosure:** a fix is prepared privately, released, and the advisory is
  published crediting you (unless you'd prefer to stay anonymous).

## Scope

Peek is a local macOS app with no backend. It requests **Accessibility** (to intercept
`⌘-Tab` and raise windows) and **Screen Recording** (window titles and thumbnails), and
stores its data as local JSON under `~/Library/Application Support/Peek`. Nothing is sent
off the machine except update checks against the app's signed [Sparkle](https://sparkle-project.org)
appcast, whose downloads are verified with an EdDSA signature.

Reports especially welcome for: bypassing the update signature check, privilege or
permission escalation via the event tap or Accessibility use, or any local
information disclosure.
