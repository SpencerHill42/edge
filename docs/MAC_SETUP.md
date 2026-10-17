# Local development on Armin's Mac (Claude Code)

Goal: see a change in seconds (Flutter hot reload in the iOS Simulator)
instead of a 20-minute GitHub build plus an AltStore install. The cloud
sessions cannot do this (no Flutter SDK, no Xcode), so this loop belongs to
Claude Code running on the Mac.

## Ground rules

- Talk to Armin in German: core statement first, short bullets, one
  "Nächster Schritt" at the end. Bundle questions; do things yourself.
- Never type a password, Apple ID or token. Armin does every login himself
  (App Store / Xcode → Accounts, `gh auth login`, `sudo` prompts). Say exactly
  which command he should run, then continue.
- Prefer installs into the user's home (no `sudo`) where possible.
- **The band:** only one app may own the WHOOP. Do not install a second copy
  of the app on Armin's iPhone and do not delete the AltStore app (deleting an
  app drops the Bluetooth bond, see "Band pairing" in `CLAUDE.md`). UI work
  happens in the Simulator, which has no Bluetooth anyway.

## Toolchain (versions match CI)

| Tool | Version / source | Notes |
|---|---|---|
| Xcode | Mac App Store, current | Armin installs it (Apple ID). Then `sudo xcode-select -s /Applications/Xcode.app`, `sudo xcodebuild -license accept`, `xcodebuild -downloadPlatform iOS` (simulator runtime, ~8 GB). |
| Flutter | **3.41.6**, pinned | e.g. `git clone -b 3.41.6 --depth 1 https://github.com/flutter/flutter.git ~/development/flutter`, add `~/development/flutter/bin` to PATH in `~/.zshrc`. Not `stable`: CI pins this version. |
| CocoaPods | Homebrew (`brew install cocoapods`) | If Homebrew is missing, Armin installs it (needs his password). |
| flutterfire_cli | 1.4.0 | `dart pub global activate flutterfire_cli 1.4.0`; the Crashlytics build phase calls it. |
| gh | Homebrew | Only needed to push; Armin runs `gh auth login`. |

Check with `flutter doctor -v`; Android parts can stay red.

## Project setup

1. Clone `https://github.com/SpencerHill42/edge` (public) to `~/Developer/edge`.
2. Read `AGENTS.md`, `CLAUDE.md`, `docs/DESIGN_QA.md`.
3. `.env` in the repo root (gitignored), same as CI:
   ```
   COMPANION_URL=
   BACKEND_URL=
   ```
4. `flutter pub get`, then `cd ios && pod install`.
5. Simulator run: `flutter run -d <iPhone simulator> --dart-define-from-file=.env`.
   Hot reload `r`, hot restart `R`. Keep the session running while editing.
6. If the Simulator build fails on signing for the widget / watch targets,
   fix it for local builds only (e.g. `ios/Config/Signing.xcconfig`, which is
   gitignored; see `Signing.xcconfig.example`). Do not commit signing changes.

### State on Armin's Mac (set up 2026-10-17)

- Repo `~/Developer/edge`, Flutter 3.41.6 in `~/development/flutter`
  (PATH and `LANG=en_US.UTF-8` in `~/.zshrc`), CocoaPods 1.17 via Homebrew,
  Xcode with the iOS 27.0 and 27.1 runtimes.
- Simulator "iPhone 14 Pro" (Armin's phone) on **iOS 27.0**, created by hand:
  Xcode only ships current models, and the 27.1 runtime refuses the 14 Pro.
  `xcrun simctl create "iPhone 14 Pro" com.apple.CoreSimulator.SimDeviceType.iPhone-14-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0`
- Before the first `pod install`: `flutter precache --ios` (or just
  `flutter run`, which does both).
- `flutterfire --version` hangs at 100 % CPU (update check); the CLI itself
  is installed and the build phase works. Kill it, don't wait.
- The log line `Firebase init failed … duplicate-app` on launch is harmless.
- First run without a band: Mein Band einrichten → scroll to the end →
  Vorerst überspringen → Über dich: Keine Angabe → Weiter → Home.
- Hot reload from a script: `flutter run … --pid-file <file>`, then
  `kill -USR1 $(cat <file>)` (reload) or `-USR2` (restart).
- `flutter pub get` rewrites `pubspec.lock` (quoted SHAs only). Do not
  commit that: `git checkout pubspec.lock`.

## Real data in the Simulator

The Simulator cannot pair the band. For real numbers: Armin exports a full
backup in the app (Mehr → Export und Backup), AirDrops it to the Mac, and it is
imported in the Simulator's copy of the app (drag the file onto the Simulator
window → Files, then import in the app). Without it the app shows its
empty/first-run states, which are worth checking too.

## The loop for every change

1. Edit → hot reload → look.
2. Design QA per `docs/DESIGN_QA.md` on Simulator screenshots:
   `xcrun simctl io booted screenshot <file>.png`, light and dark
   (`xcrun simctl ui booted appearance dark|light`, and the app's own theme
   setting). Every tab plus the screens the change touched. Fix S1/S2 first,
   keep the audit in `docs/design-qa/`.
3. `flutter analyze` and the affected tests (`flutter test test/<file>`).
4. Commit, push to `main`: CI builds the IPA for AltStore (Armin's phone).
   Docs-only commits get `[skip ci]`.

## CI test status

Since v0.3 the CI test job was red. On 2026-10-17 the full suite ran locally
(6182 tests): 22 failures, 21 from the fork, all fixed on `fix/fork-tests`.
Causes: the cockpit's wider figure face (Barlow, n24 28 / n48 52) and the
1 px card border overflowing rows at 2.0–3.1x text; ring values now read
"28 %"; v0.7 tabs (no Sleep tab, "Mehr"); `CockpitBar` missing from the
gallery; a Russian key; a test-wide sqflite FFI setup that hung Home's
past-day load. The one remaining failure,
`health_workout_export_delete_gate_test.dart`, fails on upstream 0.11.3 too
and is left to upstream.
