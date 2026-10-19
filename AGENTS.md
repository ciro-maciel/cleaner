# Notes for coding agents

Cleaner is a native macOS app in Swift and SwiftUI. It is built by `scripts/build.sh` with `swiftc`, so there is no Xcode project and no Swift package.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/Cleaner/Engine/` | Scanning, cleanup, quarantine, uninstall, startup items, privileges. No UI |
| `Sources/Cleaner/UI/` | SwiftUI screens; `Theme.swift` holds the design tokens |
| `Sources/Helper/` | The privileged helper (a launchd daemon inside the app bundle) |
| `Sources/Shared/` | The XPC protocol both sides compile |
| `rules.json` | The cleanup rules. Copied into the app at build time |
| `Resources/*.lproj/` | The interface text: `Localizable.strings` (keys are the English text) and `InfoPlist.strings` |
| `scripts/` | Build, local install, signing identity, asset regeneration |
| `scripts/release/` | Packing the `.dmg` and publishing it; used by `.github/workflows/release.yml` |

## Before you say it works

```bash
scripts/build.sh
CLEANER_NO_ADMIN=1 dist/Cleaner.app/Contents/MacOS/Cleaner --selftest
dist/Cleaner.app/Contents/MacOS/Cleaner --uninstall-test
```

## Rules that must hold

- No network code, anywhere: no `URLSession`, no sockets. Opening a link in the browser (`NSWorkspace.shared.open`) is allowed; the browser makes the request, not Cleaner.
- Every removal goes to the quarantine, and every removal button is a 3-second hold.
- `EACCES` asks for the password once per action; `EPERM` never asks, because a password can't fix it.
- The bundle identifiers (`click.ciromaciel.cleaner`, `click.ciromaciel.cleaner.helper`) never change: macOS ties Full Disk Access to them.
- Every user-facing string exists in English and Brazilian Portuguese (`Resources/en.lproj` / `Resources/pt-BR.lproj`, read through `L("English text")` in `Engine/L10n.swift`); a change that adds text adds both. A rule in `rules.json` carries `title`/`why` in Portuguese and `titleEn`/`whyEn` in English. The app follows the Mac: Portuguese when the first preferred language is Portuguese, English otherwise. Code, comments and file names are in English.
