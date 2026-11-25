# What I need from you

> Things only you can do (decisions, accounts, signing). Claude keeps this list current while working; newest items at the top of each section.
> Last updated: 25 Nov 2026. Phases 0–5 are built: the logic has 106 passing tests, and the app builds with no warnings. It hasn't run against the real Keychain yet, because that needs your signing team.

## To do now

- [x] ~~**Sign it so it can use the Keychain.**~~ Personal Team added; `Config/Local.xcconfig` has its ID (25 Nov 2026).
- [ ] **First run in Xcode.** `open Cofre.xcodeproj`, then ⌘R. The first build asks Xcode to create your "Apple Development" certificate and register the app ID `br.com.vinicius-albuquerque.cofre` on your team; allow it (and type your Mac password if Keychain Access asks to store the certificate). If Xcode says the bundle ID is taken, set `COFRE_BUNDLE_ID_PREFIX` in `Config/Local.xcconfig` to something else.
- [ ] **Try it for real** (after signing: `open Cofre.xcodeproj`, ⌘R), and tell me what breaks or feels off:
  1. Add a secret by typing, and one with **Paste from Clipboard** (try a multi-line one, like an SSH key).
  2. Double-click a row: Touch ID asks once; copy a second one, which shouldn't ask again. Paste somewhere, wait 30 s, paste again: the clipboard should be empty.
  3. Press **⌃⌥K** from another app: the panel opens; type, Enter, then ⌘V into the app you were in.
  4. Lock the screen (⌃⌘Q) and come back: the next copy asks for Touch ID again.
  5. File → Export…, then delete a secret, then File → Import… the file back (pick "Keep mine" and then "Use the backup's value").
  6. The menu bar key icon: search and copy from there.
- [ ] **Push.** Nothing is pushed yet; I'll run the security audit and ask first. The first push also runs CI (`macos-26` runner) for the first time.

## Decisions (quick)

- [ ] **Hotkey.** ⌃⌥K by default ("K" for key). Settings shows it but can't change it yet (roadmap task 30). Want a different default?
- [ ] **Dock icon.** Cofre shows in the Dock and the menu bar. Some people prefer menu bar only for this kind of tool; say if you want that (or a setting).
- [x] ~~**Name.**~~ Cofre (25 Nov 2026). Unique among Mac dev tools; "Cofre …" photo-vault apps exist on the iPhone App Store, and a small Rust CLI called `cofre` exists. If you ever publish on the App Store, use a longer display name ("Cofre — Dev Secrets").
- [x] ~~**Language.**~~ English + PT-BR (25 Nov 2026).
- [x] ~~**Git.**~~ Claude commits as it goes and asks before every push (25 Nov 2026).

## Later (needs you)

- [ ] **Release builds** for other people need a paid Apple Developer account ($99/year) for notarization (roadmap task 33). Only for distributing; running it yourself doesn't need it.
- [ ] **README screenshots** of the main window: take them with ⇧⌘5 (my snapshot tool can't draw the list rows).
- [ ] **The empty `~/Dev/secure-vault` folder** from the first name idea can be deleted.
