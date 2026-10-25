# Changelog

All notable changes to Lookshift. Versions follow [semantic versioning](https://semver.org).

## Unreleased

- Release files carry signed build provenance (`gh attestation verify`).
- Security checks: CodeQL, OpenSSF Scorecard, pinned actions, Dependabot.

## 1.0.1 · 25 October 2026

- **Security:** the developer options `--print-readings` and `--preview-onboarding` are no longer in release builds. Another program could start the app with them and read head and eye measurements under Lookshift's camera permission. CI and the release script now refuse builds that contain them.

## 1.0.0 · 25 October 2026 (withdrawn)

First release: window, pane and screen focus from head and eye tracking, setup guide, settings, and a .dmg installer. Withdrawn because of the issue fixed in 1.0.1.
