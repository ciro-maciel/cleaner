# Every rule Cleaner cleans by

Cleaner only looks where a rule in [`rules.json`](../rules.json) tells it to. These are all 9 of them, written from that file by `scripts/rules-doc.mjs`. Whatever you remove waits 7 days in the quarantine first.

## App caches `app-caches`

| | |
| --- | --- |
| Why it is safe | Temporary files each app recreates by itself when it needs them. |
| Where | `~/Library/Caches` |
| What is removed | each item inside the folder |
| Left out | `com.apple.*`, `CloudKit`, `FamilyCircle`, `GeoServices`, `click.ciromaciel.cleaner`, `.*` |
| Risk | low · Skips apps that are running |
| On by default | yes |

## App logs `logs`

| | |
| --- | --- |
| Why it is safe | Journals apps write for diagnostics. Nobody reads them once the problem is gone. |
| Where | `~/Library/Logs` |
| What is removed | each item inside the folder |
| Left out | `.*` |
| Risk | low |
| On by default | yes |

## Trash `trash`

| | |
| --- | --- |
| Why it is safe | What you already sent to the Trash and still takes up space. |
| Where | `~/.Trash` |
| What is removed | each item inside the folder |
| Left out | `.DS_Store` |
| Risk | low |
| On by default | yes |

## Installers in Downloads `installers`

| | |
| --- | --- |
| Why it is safe | Disk images and install packages older than 7 days. The app is already installed; the installer is left over. |
| Where | `~/Downloads` |
| What is removed | files inside the folder |
| Only these extensions | `dmg`, `pkg`, `mpkg`, `xip`, `iso` |
| Only older than | 7 days |
| Risk | low |
| On by default | yes |

## Xcode builds `xcode-derived-data`

| | |
| --- | --- |
| Why it is safe | The DerivedData folder keeps intermediate builds. Xcode redoes everything on the next build. |
| Where | `~/Library/Developer/Xcode/DerivedData` |
| What is removed | each item inside the folder |
| Left out | `.*` |
| Risk | low |
| On by default | yes |

## Developer tool caches `dev-caches`

| | |
| --- | --- |
| Why it is safe | Packages downloaded by npm, Bun, pnpm, Gradle and Cargo. They download them again when needed. |
| Where | `~/.npm/_cacache`, `~/.bun/install/cache`, `~/Library/pnpm/store`, `~/.gradle/caches`, `~/.cargo/registry/cache` |
| What is removed | the folder itself |
| Risk | low |
| On by default | yes |

## Xcode device support `xcode-device-support`

| | |
| --- | --- |
| Why it is safe | Symbols for each iOS version that was ever plugged in. It comes back by itself when you plug the device in again, but it takes a while. |
| Where | `~/Library/Developer/Xcode/iOS DeviceSupport`, `~/Library/Developer/Xcode/watchOS DeviceSupport` |
| What is removed | each item inside the folder |
| Left out | `.*` |
| Risk | medium |
| On by default | no, you choose it |

## Attachments opened in Mail `mail-downloads`

| | |
| --- | --- |
| Why it is safe | Copies of the attachments you opened. The original stays in the email. |
| Where | `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads` |
| What is removed | each item inside the folder |
| Left out | `.*` |
| Risk | low |
| On by default | yes |

## Downloaded AI models `ai-models`

| | |
| --- | --- |
| Why it is safe | Models that tools like Hugging Face and LM Studio download, and download again when you use them. They often take gigabytes; check each one, because the app that uses a model needs it to work. |
| Where | `~/.cache/huggingface/hub`, `~/.lmstudio/models`, `~/.cache/lm-studio/models` |
| What is removed | each item inside the folder |
| Left out | `.*`, `CACHEDIR.TAG`, `version*.txt` |
| Risk | medium |
| On by default | no, you choose it |
