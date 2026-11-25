# Cofre

> *Your dev secrets, one keystroke away. Nothing leaves your Mac.*

A native macOS app for the passwords, API keys, tokens and connection strings you copy every day. Each item is a name and a value. The value is never shown: you paste it in once, and from then on you only copy it.

**Status:** early development. See `ROADMAP.md`.

## How it works

- **Keychain, not a home-made database.** Every secret is an item in the macOS data protection Keychain, bound to this Mac (`ThisDeviceOnly`), never synced, and readable only after Touch ID or your Mac password.
- **No network.** The app is sandboxed without the network entitlement; check `Cofre/Cofre.entitlements`.
- **Quick copy.** A global hotkey (⌃⌥K) opens a search panel: type a few letters, press Enter. The clipboard is cleared 30 seconds later, and clipboard managers are told to skip it.
- **Encrypted backup.** Export everything to a `.cofre` file protected by a passphrase (PBKDF2 + AES-256-GCM, format in `docs/EXPORT_FORMAT.md`) and import it on another Mac.

## Build

Requirements: macOS 15+, Xcode 16+.

```sh
git clone https://github.com/allbdev/cofre.git && cd cofre
scripts/check.sh            # lint + tests + unsigned build
open Cofre.xcodeproj
```

To use the real Keychain the app must be signed with your team (a free Apple ID works): copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set `DEVELOPMENT_TEAM`. Without it, run the Debug build with the argument `-CofreStore memory` (secrets live only while the app runs).

## License

MIT
