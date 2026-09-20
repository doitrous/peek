# Contributing to Peek

Thanks for your interest in Peek! Issues and pull requests are welcome.

## Ground rules

- Be kind — see the [Code of Conduct](CODE_OF_CONDUCT.md).
- For **security issues, do not open a public issue** — follow the
  [Security Policy](SECURITY.md).
- Small, focused PRs are easier to review than large ones. If you're planning
  something big, open an issue first so we can align.

## Getting set up

Peek is a Swift Package (no Xcode project needed). You need **macOS 14+** and a
**Swift 6** toolchain (Xcode 16+ or the matching command-line tools).

```bash
git clone https://github.com/doitrous/peek.git
cd peek
swift build          # compile
swift test           # run the PeekCore tests
bash setup-signing.sh   # once: stable self-signed identity so permission grants persist
bash make-app.sh        # build + install /Applications/Peek.app
```

Peek needs **Accessibility** and **Screen Recording** permission to run (see the
README). Grant both in System Settings → Privacy & Security.

## Project layout

- `Sources/PeekCore/` — pure, testable logic (no AppKit): ranking, aggregation,
  JSON persistence. **New logic belongs here with a test.**
- `Sources/Peek/` — the app (AppKit + SwiftUI): hotkey tap, switcher panel,
  window activation, dashboard, settings, localization.
- `Tests/PeekCoreTests/` — `swift test` runs these; CI runs them on every PR.

## Making a change

1. Fork and branch from `main` (`git checkout -b my-change`).
2. Make your change. Match the surrounding style — the code favors small, clear
   units and semantic SwiftUI colors over hardcoded values.
3. **Add or update tests** for logic in `PeekCore`.
4. Run `swift build` and `swift test` — both must pass (CI enforces this).
5. If you add user-facing strings, wrap them in `L("…")` and add the key to each
   `Sources/Peek/Resources/*.lproj/Localizable.strings` (English falls back
   automatically; translations can come in a follow-up).
6. Open a PR describing **what** changed and **why**. Link any related issue.

## Commit & PR style

- Present-tense, imperative commit subjects ("Add …", "Fix …"), a blank line,
  then a short body explaining the reasoning.
- Keep the diff to the change at hand; unrelated cleanup goes in its own PR.

## Regenerating the README screenshots

```bash
./make-screenshots.sh   # runs Peek in showcase mode and recaptures docs/images/*
```

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
