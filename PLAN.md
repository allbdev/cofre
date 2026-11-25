# Cofre — Plan

> *Your dev secrets, one keystroke away. Nothing leaves your Mac.*
> A native macOS app for the passwords, API keys, tokens and connection strings a developer copies every day. Each item is a name and a value; the value is never shown, only copied.
> Free, open-source. A portfolio piece: the code is part of the product.

**Author:** Vinícius Albuquerque Barros · **Written:** 25 Nov 2026 · **Status:** phases 0–5 built (logic tested; not yet run against the real Keychain, which needs signing)

Ordered task list: `ROADMAP.md`. Project rules: `CLAUDE.md`. Things only the developer can do: `TODO_FOR_YOU.md`. Export file format: `docs/EXPORT_FORMAT.md`.

---

## 1. Pitch

Press a hotkey, type three letters, hit Enter: the secret is on the clipboard, and 30 seconds later it's gone. Adding one is a name plus a paste. No accounts, no sync, no network, no master password to forget: Touch ID (or the Mac's password) guards every read.

**Honest positioning.** Mac apps in this niche already exist (NoxKey, Slinky, Secret Store, Krypt, Fidelius, EnvVault…). Cofre isn't a new idea. It's my own take, built to be small, boring, auditable and pleasant to use, and a showcase of native macOS work.

## 2. Decisions

| # | Decision | Choice | Why |
|---|---|---|---|
| D1 | Concept | A list of items; item = **name + value**. The value is write-only in the UI: it can be typed, pasted, replaced and copied, never displayed | The user asked for exactly this; less to show is less to leak |
| D2 | Platform | Native macOS 15+, SwiftUI with AppKit where SwiftUI can't (global hotkey, floating panel, pasteboard) | Native feel, Touch ID, Keychain |
| D3 | Storage | The macOS **data protection Keychain**: one generic-password item per secret, `WhenUnlockedThisDeviceOnly`, not synchronizable, guarded by `.userPresence`. Name and dates live in the item's attributes. **No database, no home-made storage crypto** | Apple's audited storage; boring on purpose |
| D4 | Network | None. App Sandbox **without** the network entitlement | "Nothing leaves the Mac" is something anyone can verify in the entitlements, not a promise |
| D5 | Unlock | Touch ID or the Mac password unlocks a session; values are readable until it locks: after 5 minutes idle (setting), on sleep, screen lock or quit. **Names are listed without unlocking** | One prompt per burst of work, not per copy; names alone aren't secrets |
| D6 | Clipboard | Written with `org.nspasteboard.ConcealedType` and `TransientType` (clipboard managers skip it), cleared after 30 s (setting), but only if the clipboard still holds our value | Don't leave secrets around; never clobber something the user copied since |
| D7 | Quick access | Global hotkey (default ⌃⌥K, setting) opens a floating search panel: type, ↑/↓, Enter copies, Esc closes. Menu bar item with the same search. Main window for managing items | Speed is the whole product |
| D8 | Backup | Encrypted export file (`.cofre`): passphrase → PBKDF2-HMAC-SHA256 (600 000 iterations) → AES-256-GCM. Import asks what to do with name clashes (skip / replace / keep both). The app reminds you when the last export is stale | `ThisDeviceOnly` items don't survive a dead Mac or a migration; without export, security becomes data loss |
| D9 | Names | Unique (case- and accent-insensitive), 1–100 characters, single line | The CLI (later) gets secrets by name |
| D10 | Language | Interface in **English** and **PT-BR** (String Catalog, follows the system language). Code, comments, docs and git in English | Same habit as my web projects |
| D11 | Signing | Debug builds can run unsigned with an in-memory store (`-CofreStore memory`); the real Keychain store needs the app signed with a team (a free Personal Team is enough to run locally) | The data protection Keychain requires an application identifier |
| D12 | Repo | Public, MIT, `allbdev/cofre` | The README is what a recruiter reads |

## 3. Architecture

```
CofreKit/ (Swift package, no AppKit)
  CofreKit      pure logic: SecretValue (redacted), name rules, SecretStore protocol + in-memory store,
                search ranking, export codec, import planner, clipboard guard, lock policy, VaultModel
  CofreKeychain the Keychain-backed SecretStore and the LocalAuthentication session
Cofre/ (app target)
  views (SwiftUI) + AppKit adapters: pasteboard, hotkey (Carbon), floating panel, lock triggers
```

- **CofreKit is pure and tested with `swift test`** (no signing, no UI). The app is a thin layer of views and adapters over it.
- `SecretValue` never prints itself (`description` is `••••••`), isn't `Codable`, and only the export codec and the pasteboard adapter read its bytes.
- One `SecretStore` protocol, two implementations: `KeychainSecretStore` (real) and `InMemorySecretStore` (tests, unsigned debug runs).
- `VaultModel` (`@Observable`, main actor) is what the views bind to: the list, search, add / rename / replace / delete, copy, lock state, export / import.

## 4. Screens

1. **Main window.** Search field, list of names (with "updated" date), copy button per row, ⌘N to add, context menu (copy, rename, replace value, delete). Lock state and a lock button in the toolbar. A banner when the last export is stale.
2. **Add / replace sheet.** Name field; value: a password field **or** "Paste from clipboard" (for multi-line values like PEM keys), showing only "42 characters ✓". Optionally clears the clipboard after taking the value.
3. **Quick panel** (hotkey) and **menu bar** menu: search + list + Enter to copy.
4. **Export / import sheets.** Passphrase (twice for export, min 12 characters) and the conflict choice on import.
5. **Settings.** Clipboard clear delay, auto-lock timeout, hotkey, launch at login.

## 5. Later (not in the first version)

- **CLI** inside the app bundle: `cofre get <name>`, `cofre run -- <command>` (injects secrets as env vars), same Keychain access group, Touch ID per session.
- **Sync**: the boring path first, an automatic encrypted export into a folder the user picks (iCloud Drive, Google Drive). iCloud Keychain sync only if that proves too weak.
- Notes and tags per item, secret generator, expiry reminders.

## 6. Known limits

- Swift can't reliably wipe a `String` from memory; secrets live as short as possible in `Data` and are dropped right after use.
- Anyone with the Mac's login password can unlock (that's how `.userPresence` works). Cofre protects against people and processes, not against your own account's password.
- The clipboard is readable by any app while the value sits there; the 30 s clear is the mitigation.
