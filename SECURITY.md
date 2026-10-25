# Security

Lookshift uses your Mac's camera and the Accessibility API, so security and privacy come first.

## Reporting a vulnerability

Please report it privately through [GitHub's private vulnerability reporting](https://github.com/samapara/Lookshift/security/advisories/new), not in a public issue. You'll get a reply within a few days, and a fix will be released as soon as it's ready, with credit to you if you'd like.

Only the [latest release](https://github.com/samapara/Lookshift/releases/latest) gets security fixes.

## What Lookshift does and doesn't do

- Camera frames are analysed in memory by Apple's Vision framework and dropped. Nothing is written to disk.
- The app has no networking code. CI and the release script refuse any build that links a networking API.
- It reads only the position and size of other apps' windows and panes, never their titles or contents, and never clicks or types.
- It checks how long ago a key was pressed, never which key.
- Release builds contain no developer or debug options.

## How the code and releases are checked

| Check | What it does |
|---|---|
| [CI](.github/workflows/ci.yml) | Unit tests, a universal build, and the no-networking and no-developer-options checks on every push |
| [CodeQL](.github/workflows/codeql.yml) | GitHub's code scanner looks for security bugs in the Swift code on every push and weekly |
| [OpenSSF Scorecard](.github/workflows/scorecard.yml) | Grades the repository's security practices; the score is public |
| [Dependabot](.github/dependabot.yml) | Keeps the GitHub Actions used in builds up to date |
| Pinned actions | Every action is pinned to an exact commit, so a compromised tag can't change a build |
| Build provenance | Each release file carries a signed attestation of the commit and workflow that built it |
| Secret scanning | GitHub blocks pushes that contain credentials |

## Verifying a download

Check that a file was built by this repository's release workflow:

```sh
gh attestation verify Lookshift-1.0.2.dmg -R samapara/Lookshift   # releases from 1.0.2 on
```

Or compare its checksum with `SHA256SUMS.txt` from the same release:

```sh
shasum -a 256 Lookshift-1.0.2.dmg   # use the file name you downloaded
```
