# What I need from you

> Things only you can do (decisions, accounts, signing). Claude keeps this list current while working; newest items at the top of each section.
> Last updated: 25 Nov 2026. Phases 0–5 are built: the logic has 109 passing tests, and the app builds with no warnings. It hasn't run against the real Keychain yet, because that needs your signing team.

## To do now

- [x] ~~**Sign it so it can use the Keychain.**~~ Personal Team added; `Config/Local.xcconfig` has its ID (25 Nov 2026).
- [x] ~~**First run in Xcode.**~~ Signed with your Personal Team, Keychain working, installed in `/Applications` (25 Nov 2026).
- [ ] **Enroll in the Apple Developer Program** (you're enrolling anyway, 25 Nov 2026). Until then the Personal Team profile expires on 2 Dec 2026; `scripts/install.sh` renews it.
- [ ] **After enrolling, switch teams without losing secrets.** The paid team has a **new team ID**, and Keychain items are tied to it: (1) File → Export… in the current Cofre, (2) put the new ID (developer.apple.com → Membership) in `Config/Local.xcconfig`, (3) `scripts/install.sh`, (4) File → Import…. Skip the export if there's nothing real in it yet.
- [ ] **Try it for real** (open Cofre from Applications), and tell me what breaks or feels off:
  1. Add a secret by typing, and one with **Paste from Clipboard** (try a multi-line one, like an SSH key).
  2. Double-click a row: Touch ID asks once; copy a second one, which shouldn't ask again. Paste somewhere, wait 30 s, paste again: the clipboard should be empty.
  3. ~~Press **⌃⌥K** from another app: the panel asks for Touch ID, then type, Enter, ⌘V into the app you were in.~~ Works (25 Nov 2026).
  4. Lock the screen (⌃⌘Q) and come back: the next copy asks for Touch ID again.
  5. File → Export…, then delete a secret, then File → Import… the file back (pick "Keep mine" and then "Use the backup's value").
  6. The menu bar key icon: search and copy from there.
- [ ] **Push.** Nothing is pushed yet; I'll run the security audit and ask first. The first push also runs CI (`macos-26` runner) for the first time.

## Decisions (quick)

- [x] ~~**Hotkey.**~~ ⌃⌥K stays the default (25 Nov 2026). Settings can't change it yet (roadmap task 30).
- [ ] **Dock icon.** Cofre shows in the Dock and the menu bar. Some people prefer menu bar only for this kind of tool; say if you want that (or a setting).
- [x] ~~**Name.**~~ Cofre (25 Nov 2026). Unique among Mac dev tools; "Cofre …" photo-vault apps exist on the iPhone App Store, and a small Rust CLI called `cofre` exists. If you ever publish on the App Store, use a longer display name ("Cofre — Dev Secrets").
- [x] ~~**Language.**~~ English + PT-BR (25 Nov 2026).
- [x] ~~**Git.**~~ Claude commits as it goes and asks before every push (25 Nov 2026).

## Later (needs you)

- [ ] **Release builds for other people** (roadmap tasks 33–34: Developer ID, notarization, Homebrew cask) become possible once you're enrolled.
- [ ] **README screenshots** of the main window: take them with ⇧⌘5 (my snapshot tool can't draw the list rows).
- [ ] **The empty `~/Dev/secure-vault` folder** from the first name idea can be deleted.
