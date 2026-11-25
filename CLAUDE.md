# CLAUDE.md — Cofre

A native macOS app for a developer's everyday secrets (passwords, API keys, tokens). Item = name + value; the value is never shown, only copied. **Swift 6 + SwiftUI (AppKit where needed), macOS 15+, data protection Keychain, no network.** Design: `PLAN.md`. Ordered task list: `ROADMAP.md`. Things only the developer can do: `TODO_FOR_YOU.md`. Export format: `docs/EXPORT_FORMAT.md`.

Repo: https://github.com/allbdev/cofre (remote `origin`, branch `main`).

## Security audit before every push (strict)

- **Run the `security-audit` skill on the changes being pushed before every `git push`.** No exceptions.
- Fix every finding, or get the developer to explicitly accept it, before pushing. Mention the audit result when you push.
- If the audit can't run, don't push; say why.

## Security rules (strict)

This app's whole job is keeping secrets. These are not style preferences:

- **No network, ever.** Never add the `com.apple.security.network.*` entitlements, `URLSession` calls, analytics, crash reporters or update checkers. `SecurityRulesTests` checks the entitlements file and scans the sources for networking and logging APIs.
- **Values are never displayed.** No "reveal" button, no value in a `Text`, tooltip, accessibility label, log, error message or notification. Input is a `SecureField` or "Paste from clipboard".
- **`SecretValue` only.** Secret bytes travel as `SecretValue` (redacted `description`, not `Codable`). Never convert to `String` except in the pasteboard adapter and the export codec. Never `print`, `Logger` or `dump` one.
- **No home-made crypto.** Storage is the Keychain; the export uses CryptoKit AES-GCM and CommonCrypto PBKDF2 exactly as `docs/EXPORT_FORMAT.md` says. Format changes bump `version` and keep reading old versions.
- **Keychain items** are always `kSecUseDataProtectionKeychain`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable = false`, `.userPresence`. Changing any of these needs the developer's OK and a `PLAN.md` decision.
- **Clipboard writes** always go through the pasteboard adapter (concealed + transient types, auto-clear).
- New dependencies (Swift packages) need the developer's OK. Today there are none.

## Language rules (strict)

| What | Language |
|---|---|
| Code: identifiers, file/folder names, test names | **English** |
| Code comments, commit messages, PR descriptions | **English** |
| Docs (`*.md`, including this file) | **English** |
| **Interface text** (windows, menus, buttons, alerts, errors, accessibility labels) | **English** and **Brazilian Portuguese (PT-BR)**, always both |

- Interface text is written as English literals in SwiftUI (`Text("Add secret")`) or `String(localized:)`, and translated in `Cofre/Localizable.xcstrings`. Error messages from `CofreKit` are `LocalizedStringResource`s resolved in the app, translated in the same catalog.
- Xcode only extracts strings from the app target, so catalog entries for `CofreKit` messages and `#if DEBUG` text are marked `"extractionState" : "manual"` (otherwise Xcode flags them stale and offers to delete them). Keep Xcode's own JSON formatting in the catalog.
- Every new interface string gets its PT-BR translation in the same change. `LocalizationTests` fails when a literal in `Cofre/` or a message in `CofreKit` is missing from the catalog or has no PT-BR.
- Don't build strings by concatenation; use interpolation (`Text("Copied \(name)")` → key `Copied %@`).

## Testing rules

- **Every feature ships with tests.** A roadmap task isn't done until its tests are written and passing.
- Framework: **Swift Testing** (`import Testing`, `@Test`, `#expect`). Property-style tests loop over generated inputs with a seeded generator (`Tests/CofreKitTests/Support/`); no testing dependencies.
- Logic lives in `CofreKit` so it's tested with `swift test`, without signing or UI. Tests mirror sources (`Sources/CofreKit/Search.swift` → `Tests/CofreKitTests/SearchTests.swift`).
- Keychain integration tests (`Tests/CofreKeychainTests`) run only when the test binary can use the data protection Keychain; otherwise they're skipped, and the skip is printed.
- Bug fixes start with a failing test that reproduces the bug.
- Run the full check before every commit, and don't commit when it fails:
  ```sh
  scripts/check.sh && git commit ...
  ```
  (`scripts/check.sh` = `swift-format lint --strict` + `swift test` + unsigned `xcodebuild build` of the app.) Check the exit code.

## Git workflow

- **Commit as you go** on the current branch: small Conventional Commits (`feat(kit): …`, `feat(app): …`, `fix(keychain): …`, `docs: …`), one roadmap task or chore each, each one passing `scripts/check.sh`.
- **Ask before every push.** Run the `security-audit` skill first (see the top).
- Never commit `Config/Local.xcconfig` (team ID), `.cofre` files, or anything from a real Keychain.

## Code conventions

- Swift 6 language mode, strict concurrency, no warnings. `swift-format` config in `.swift-format`; `scripts/format.sh` fixes formatting.
- `CofreKit` imports Foundation, CryptoKit, CommonCrypto and Observation only: no AppKit, no SwiftUI, no Security. `CofreKeychain` adds Security and LocalAuthentication. The app target holds views and AppKit adapters only; if something can be tested without AppKit, it belongs in `CofreKit`.
- Types `PascalCase`, everything else `camelCase`, one main type per file named after it.
- Views stay small; they bind to `VaultModel` and never call a store directly.
- No force unwraps outside tests.

## Architecture notes

- **Layout.** `CofreKit/` (Swift package: `CofreKit` pure logic, `CofreKeychain` Keychain store), `Cofre/` (app: `App/`, `Views/`, `Adapters/`, `Localizable.xcstrings`), `Config/` (xcconfigs, `Cofre.entitlements`, `Info.plist` with the `.cofre` file type), `scripts/`, `docs/`. The Xcode project uses a synchronized folder for `Cofre/`: new files there are picked up without editing the project.
- **Stores.** `SecretStore` protocol; `KeychainSecretStore` in release; debug builds accept `-CofreStore memory` (unsigned runs, screenshots). The app shows a clear message if the Keychain says the app isn't entitled (unsigned build).
- **Signing.** `Config/Base.xcconfig` includes an optional, git-ignored `Config/Local.xcconfig` that sets `DEVELOPMENT_TEAM`. CI and `scripts/check.sh` build with signing off.
- **Unlock.** `KeychainSecretStore` keeps one `LAContext` per unlocked session; `lock()` invalidates it. Listing names needs the unlocked session too (the Keychain refuses attributes of `.userPresence` items otherwise); locked, `list()` fails with `.locked` instead of letting the Keychain show its own prompt, and `VaultModel.namesAreLocked` turns that into a "locked" state.
- **Checking the UI without clicking.** Debug builds accept `-CofreStore memory -CofreDemoData YES -CofreSnapshotDir <dir>` (add `-AppleLanguages '(pt-BR)'` for Portuguese): the app fills itself with made-up secrets, draws its windows to PNGs and quits. The main window's list rows don't draw this way; everything else does. Use it after UI changes, in both languages.
- **Accessibility.** Every control is keyboard-reachable; icon-only buttons have accessibility labels; the panel works with VoiceOver.

## Workflow

- Work through `ROADMAP.md` in order. Mark tasks `[~]` when started and `[x]` when done and tested.
- Don't add scope that isn't in the roadmap without asking first.
- Keep `TODO_FOR_YOU.md` current: anything that needs the developer (signing, decisions, accounts) goes there, newest at the top of each section.
