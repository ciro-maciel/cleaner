# Cleaner

**A Mac cleaner that shows you everything before it deletes anything.**

Every rule it cleans by is in one readable file, [`rules.json`](rules.json). Nothing is deleted on the spot: whatever you remove waits 7 days in a quarantine and goes back where it was with one click. A native Swift app for macOS 14+ on Apple Silicon, with no network code at all.

[Português](README.pt-BR.md)

![Cleaner overview: 2.7 GB that can be freed, disk usage and the four tools](docs/overview.webp)

## Install

```bash
curl -fsSL https://blob.ciromaciel.click/tools/cleaner/install.sh | bash
```

The script downloads the latest `.dmg`, copies Cleaner to `/Applications` and opens it.

Prefer the disk image? [Download Cleaner-macos.dmg](https://blob.ciromaciel.click/tools/cleaner/latest/Cleaner-macos.dmg). Cleaner is not notarized by Apple yet, so a browser download is blocked the first time. Clear the flag once:

```bash
xattr -dr com.apple.quarantine /Applications/Cleaner.app
```

For a complete scan, turn on Cleaner in **System Settings → Privacy & Security → Full Disk Access**. Without it, macOS hides the Trash, Mail and app containers, and Cleaner tells you so instead of pretending.

## Why another Mac cleaner

The well-known cleaners ask you to trust a "junk" number. Cleaner shows you how it gets that number:

- **The rules are public.** `rules.json` lists every folder Cleaner looks at, why it is safe to clear and what is excluded. If a rule is wrong, you can read it, and you can send a fix.
- **Nothing disappears.** Removal moves items to a quarantine batch that remembers each original path. Restore is one click; after 7 days the batch empties itself.
- **Removal takes a 3-second hold.** No accidental clicks.
- **It says what it can't do.** When macOS refuses a file, Cleaner tells you why: the item belongs to the system and needs your password, or it is protected and no password would help.

![Cleanup: every item, the rule that found it and its size](docs/cleanup.webp)

## What it does

| Screen | What it does |
| --- | --- |
| Overview | One scan for everything: space you can free, disk, apps, startup items, quarantine |
| Cleanup | Applies the rules in `rules.json`: app caches, logs, Trash, old installers, Xcode, developer caches, Mail downloads |
| Uninstaller | Lists apps with size and last use, then removes the app and its leftovers in 38 places, .pkg receipts included |
| Disk map | Measures a whole folder in parallel and lets you walk into the biggest parts |
| Startup | Turns LaunchAgents and LaunchDaemons on and off without deleting the file |
| Quarantine | Batches with their original paths: restore with a click, emptied after 7 days |
| Menu bar | CPU, memory, network, disk and battery, live, plus how much you can free right now |

<img src="docs/menubar.webp" alt="The menu bar panel: processor, memory, network, disk and battery" width="300">

## The rules

Eight rules today. Each one says what it is, why it is safe, how risky it is and whether it is on by default:

```json
{
  "id": "app-caches",
  "title": "Caches de aplicativos",
  "why": "Arquivos temporários que cada app recria sozinho quando precisa.",
  "risk": "low",
  "mode": "children",
  "paths": ["~/Library/Caches"],
  "exclude": ["com.apple.*", "CloudKit", "FamilyCircle", "GeoServices", "click.ciromaciel.cleaner", ".*"],
  "skipRunningApps": true,
  "defaultOn": true
}
```

The other seven are `logs`, `trash`, `installers`, `xcode-derived-data`, `dev-caches`, `xcode-device-support` and `mail-downloads`. A new rule or a better exclusion is the most useful contribution you can make.

## Build it yourself

You need the Xcode Command Line Tools. Xcode itself is optional.

```bash
git clone https://github.com/ciro-maciel/cleaner.git
cd cleaner
scripts/build.sh                 # dist/Cleaner.app
open dist/Cleaner.app
```

`scripts/signing-identity.sh` creates a local signing certificate once. With it, Full Disk Access survives each rebuild; without it, the build is signed ad hoc and macOS asks again every time.

Tests run against your own Mac without changing it:

```bash
CLEANER_NO_ADMIN=1 dist/Cleaner.app/Contents/MacOS/Cleaner --selftest   # reads only; quarantine runs in a temp folder
dist/Cleaner.app/Contents/MacOS/Cleaner --uninstall-test                # fakes an app with every leftover, removes, checks, restores
dist/Cleaner.app/Contents/MacOS/Cleaner --screenshots /tmp/shots        # captures every screen
```

## Limits

- Apple Silicon and macOS 14 or newer only.
- The interface is in Portuguese for now.
- Not notarized yet, so a downloaded `.dmg` needs the `xattr` line above.
- Items protected by System Integrity Protection stay where they are. That is macOS working as intended.
- No duplicate finder, no malware scan and no app updater.

## Contributing

Issues and pull requests are welcome, especially for `rules.json`. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). Fonts and icons keep their own licenses: see [NOTICE](NOTICE).

---

Made by [Ciro Cesar Maciel](https://ciromaciel.click/?ref=oss-cleaner). I build tools and show how to use them: more [free tools](https://ciromaciel.click/tools?ref=oss-cleaner) and [Mac apps](https://ciromaciel.click/tools/cleaner?ref=oss-cleaner).
