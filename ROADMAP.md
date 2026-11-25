# Roadmap — Cofre

> Tasks **in order**. Work top to bottom; move to the next phase only when the current phase's exit criteria are met.
> **The logic comes first:** the store protocol, the export format and the clipboard rules are built and tested in `CofreKit` before any UI.
> Design: `PLAN.md`. Rules: `CLAUDE.md`. Things only the developer can do: `TODO_FOR_YOU.md`.

**Definition of done:** a task is `[x]` only when it's implemented **and covered by passing tests** (see `CLAUDE.md`).

**Legend:** `[ ]` todo · `[~]` in progress · `[x]` done

---

## Phase 0 · Setup

1. [x] `git init`, public repo `allbdev/cofre`, MIT `LICENSE`, `.gitignore`, planning docs
2. [x] `CofreKit` Swift package (Swift 6 language mode, macOS 15) with targets `CofreKit` and `CofreKeychain`, Swift Testing, a first test
3. [x] Xcode project `Cofre.xcodeproj` (app target, synchronized folders, local package), sandbox entitlements without network, `Config/*.xcconfig` with a git-ignored `Local.xcconfig` for the team ID
4. [x] `swift-format` config; `scripts/check.sh` (format lint + `swift test` + unsigned `xcodebuild build`)
5. [~] GitHub Actions: `scripts/check.sh` on every push and pull request — workflow written; first run happens on the first push

**Exit:** the empty app builds unsigned, `scripts/check.sh` is green locally and in CI. (Green locally, 25 Nov 2026.)

---

## Phase 1 · Core logic (CofreKit, no UI)

6. [x] `SecretValue`: holds bytes, redacted `description`/`debugDescription`, not `Codable`
7. [x] Name rules: trim, 1–100 characters, single line, unique by case- and accent-insensitive key; readable errors
8. [x] `SecretStore` protocol + `InMemorySecretStore` (list, add, rename, replace value, delete, read value, lock/unlock)
9. [x] Search ranking: name prefix > word prefix > substring > subsequence, case- and accent-insensitive; property tests
10. [x] Export codec (`docs/EXPORT_FORMAT.md`): PBKDF2-HMAC-SHA256 + AES-256-GCM, versioned JSON; wrong passphrase, tampering, bad versions, absurd iteration counts and oversized files fail with clear errors; round-trip property test
11. [x] Import planner: new vs clashing names; skip / replace / keep both (`name (2)`)
12. [x] Clipboard guard: clear after the delay only if the clipboard's change count is still ours
13. [x] Lock policy: idle timeout, lock on sleep / screen lock
14. [x] `VaultModel`: list, search, add / rename / replace / delete, copy, lock state, error messages, export / import, "last export" staleness

**Exit:** every rule in `PLAN.md` §2 that doesn't need AppKit or the Keychain is covered by tests. ✅ (106 tests)

---

## Phase 2 · Keychain

15. [~] `KeychainSecretStore` on the data protection Keychain: generic passwords, `WhenUnlockedThisDeviceOnly`, not synchronizable, `.userPresence`; name and dates in attributes — built and unit-tested; not yet run against the real Keychain (needs a signed build, see `TODO_FOR_YOU.md`)
16. [~] Auth session: one `LAContext` per unlock, reused for reads, invalidated on lock — built and unit-tested; not yet run against the real Keychain (needs a signed build, see `TODO_FOR_YOU.md`)
17. [~] Error mapping (missing entitlement → "app must be signed with a team", user cancelled, item missing) with messages in both languages — built and unit-tested; not yet run against the real Keychain (needs a signed build, see `TODO_FOR_YOU.md`)
18. [~] Integration tests against the real Keychain (skipped when unsigned) — written; skipped until a signed test host exists

**Exit:** with a signed build, add → list → copy → delete works against the real Keychain.

---

## Phase 3 · The app

19. [x] App shell: main window, store selection (Keychain; `-CofreStore memory` in debug builds), String Catalog EN + PT-BR with a test that every interface string has both
20. [x] List + search, empty state, copy button and context menu
21. [x] Add sheet: name + password field or "Paste from clipboard" (multi-line), length shown, optional clipboard clear
22. [x] Rename, replace value, delete with confirmation
23. [x] Pasteboard adapter: concealed + transient types, auto-clear via the clipboard guard, "Copied — clears in 30 s" feedback
24. [~] Lock: toolbar lock button and state, auto-lock on idle, sleep and screen lock — built; idle/sleep/screen-lock triggers need a manual check

**Exit:** the app is usable day to day from the main window.

---

## Phase 4 · Quick access

25. [~] Menu bar item: search + list + copy, "Open Cofre", "Lock", "Quit" — built; needs a manual check
26. [x] Global hotkey (Carbon `RegisterEventHotKey`, no Accessibility permission) opening a floating panel: type, ↑/↓, Enter copies and closes, Esc closes. Locked, the panel asks for Touch ID as it opens (the Keychain needs it even for names) — checked by hand with Touch ID (25 Nov 2026)

**Exit:** a secret gets to the clipboard in one hotkey, a few letters and Enter.

---

## Phase 5 · Backup

27. [~] Export: passphrase sheet (twice, min 12 characters), unlock, save panel, write `.cofre`; remember the date — logic tested end to end; the save/open panel flow needs a manual check
28. [~] Import: open panel, passphrase, conflict choice, summary ("8 added, 2 replaced, 1 skipped") — logic tested end to end; the save/open panel flow needs a manual check
29. [x] Stale-backup banner: never exported, or items changed since the last export

**Exit:** export on one Mac, import on another (or after wiping), same items.

---

## Phase 6 · Polish and release

30. [ ] Settings: clipboard clear delay, auto-lock timeout, hotkey recorder, launch at login
31. [ ] App icon, About window
32. [ ] README with screenshots (debug snapshot mode exists: `-CofreSnapshotDir`; the list itself needs ⇧⌘5), `docs/SECURITY.md` (threat model in plain words)
33. [ ] Signed, notarized release build attached to a GitHub release (needs a paid Apple Developer account)
34. [ ] Homebrew cask

---

## Phase 7 · CLI (later)

35. [ ] `cofre` command inside the app bundle sharing the Keychain access group: `cofre list`, `cofre get <name>`, `cofre run -- <command>` (env vars from a `.cofre-env` mapping)

## Phase 8 · Sync (later)

36. [ ] Automatic encrypted export into a user-chosen folder (iCloud Drive / Google Drive) and import on change
