# What I need from you

> Things only you can do (decisions, accounts, signing). Claude keeps this list current while working; newest items at the top of each section.
> Last updated: 25 Nov 2026.

## To do now

- [ ] **Add your Apple ID to Xcode** (Xcode → Settings → Accounts → +). A free Personal Team is enough to run Cofre on your Mac. Then copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and put your team ID in it (Xcode shows it under Accounts → your team, or in developer.apple.com → Membership). Without this, the app runs only with the in-memory store, because the data protection Keychain needs a signed app.

## Decisions (quick)

- [x] ~~**Name.**~~ Cofre (25 Nov 2026). Unique among Mac dev tools; "Cofre …" photo-vault apps exist on the iPhone App Store, and a small Rust CLI called `cofre` exists. If you ever publish on the App Store, use a longer display name ("Cofre — Dev Secrets").
- [x] ~~**Language.**~~ English + PT-BR (25 Nov 2026).
- [x] ~~**Git.**~~ Claude commits as it goes and asks before every push (25 Nov 2026).
