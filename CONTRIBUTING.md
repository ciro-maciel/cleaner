# Contributing

Thanks for helping. Cleaner deletes files on other people's Macs, so the bar is "never surprise anyone".

## The most useful contribution: rules

[`rules.json`](rules.json) decides what Cleaner offers to clear. A good rule change:

- names a folder that an app **recreates by itself**, or a file the person clearly no longer needs;
- says in `why` what the folder is, in one sentence a non-developer understands;
- sets `risk` honestly (`low`, `medium`, `high`) and `defaultOn: false` for anything above `low`;
- adds to `exclude` anything inside that must survive.

Tell us in the pull request which app creates the folder and how you checked that it comes back.

## Code

```bash
scripts/build.sh
CLEANER_NO_ADMIN=1 dist/Cleaner.app/Contents/MacOS/Cleaner --selftest
dist/Cleaner.app/Contents/MacOS/Cleaner --uninstall-test
```

Both tests must pass, and CI runs them on every pull request. If your change touches the screens, attach a capture from `--screenshots`.

House rules:

- Swift and SwiftUI only, built by `swiftc`. No Xcode project, no package manager, no dependencies.
- No network code. Cleaner never talks to the internet, and that is a promise in the README.
- Anything that removes goes through the quarantine. Nothing is deleted in place.
- Every removal asks for the 3-second hold.

## Reporting a bug

Say which macOS version, which Mac and what Cleaner showed. If a file was moved that shouldn't have been, it is still in the quarantine: tell us its original path, and restore it from the Quarantine screen.

For anything that could harm someone's data or security, read [SECURITY.md](SECURITY.md) first.
