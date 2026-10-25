# Contributing to Lookshift

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Ground rules

Lookshift watches people through their camera, so a few things are fixed:

- **Everything stays on the Mac.** No networking code, no analytics, no crash reporting. CI rejects any build that links a networking API.
- **Nothing from the camera is stored.** Frames are analysed in memory and dropped; only a few numbers per frame are kept, briefly.
- **No new permissions** beyond Camera and Accessibility without a discussion first.
- **No third-party dependencies** in the app. Apple's frameworks only.

## Reporting bugs and ideas

Use the [issue forms](https://github.com/samapara/Lookshift/issues/new/choose). Please never attach photos or recordings of your face. Security problems go through [private reporting](https://github.com/samapara/Lookshift/security/advisories/new) instead (see [SECURITY.md](SECURITY.md)).

## Working on the code

You need macOS 14 or later and Swift 6 (Xcode 16, or just the Command Line Tools).

```sh
scripts/test.sh          # unit tests for LookshiftCore
swift build              # debug build with developer options
.build/debug/Lookshift --print-readings   # raw head and eye numbers
scripts/build-app.sh     # dist/Lookshift.app
```

- `Sources/LookshiftCore` holds the logic: measurements, calibration, switching rules. It has no camera or UI code, so put anything testable here and add a test in `Tests/LookshiftCoreTests`.
- `Sources/Lookshift` is the app: camera, Vision, windows, menus and settings.
- Match the style around you: small types, plain names, short comments that say why.
- Ad-hoc builds need Accessibility granted again after each rebuild.

## Pull requests

1. Fork, create a branch, make your change.
2. Run `scripts/test.sh` and try the app on a real Mac.
3. Open a pull request using the template. CI and CodeQL must pass, and the maintainer reviews every change.

Pull requests are squash-merged, so the title becomes the commit message: keep it short and imperative ("Fix pane focus in Terminal").

## Code of conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
