# Strap Cockpit — private fork of OpenStrap Edge

Armin's personal iPhone app for his WHOOP 5.0 band, built on OpenStrap Edge.
Private use only, never distributed. UI copy is German.

Read `AGENTS.md` first: Edge's invariants (commit before ACK, never fabricate a
metric, local day labels, heavy compute off the UI isolate, …) apply here
unchanged. This file only adds what is specific to the fork.

## Design

- Source: Claude Design canvas "Strap Cockpit"
  https://claude.ai/artifact/Y7w5vF3qQeYJej85yTsfEz (screens Heute, Morgen,
  Abend, Verlauf, Zustände, Komponenten & Tokens).
- Tokens live in two places, keep them in step:
  `lib/ui2/theme.dart` (`C`, `P`, `F`) and `lib/theme/tokens.dart`
  (`kLightPalette`, `kDarkPalette`).
- Dark tokens: ground #0B0D0F, card #14181B, inset #1A1F23, line #1E2428,
  ink #F1F3F2 / #A9B1B7 / #808990, signal lime #D4F25C, sleep #9C8CFF,
  strain #46C3F2, pulse #FF9E7A, status #3FD69B / #F4B740 / #F26457.
- Light tokens ("white", the default since v0.3; not in the canvas, derived
  from the dark set): ground #F3F4F2, card #FFFFFF, inset #ECEEEC, line
  #E1E4E2, track #E3E6E4, ink #0B0D0F / #474F55 / #5F676E. Accents stay the
  same pigments; `P.on()` solves them to AA on white (lime → olive #637131),
  so never paint a raw pigment as text or a thin mark on white.
- Figures: Barlow Condensed (bundled). Rings: 270° segmented scale
  (`Ring`, `DashedRing` in `lib/ui2/charts.dart`).

## Build and install

- No Flutter SDK in the cloud sessions (pub.dev and Google storage are
  blocked). The compile check is `flutter analyze` in `.github/workflows/test.yml`
  on GitHub.
- `.github/workflows/cockpit-ipa.yml` builds an unsigned `StrapCockpit.ipa` on
  every push to `main` (Actions → run → Artifacts). Installed with AltStore
  Classic and a free Apple ID: valid 7 days, AltServer re-signs over Wi-Fi.
- Docs-only commits: put `[skip ci]` in the message so no 20-minute build runs.
- Upstream: `git remote add upstream https://github.com/OpenStrap/edge`,
  then `git fetch upstream && git merge upstream/main`. Expect conflicts only
  in the theme/shell files listed below.

## What the fork changed

- v0.1: cockpit palette (dark default), Barlow Condensed figures, segmented
  rings, tabs Heute · Morgen · Abend · Verlauf (`lib/ui2/app_shell.dart`, tab
  labels in `lib/l10n/app_de.arb` / `app_en.arb`), app name "Strap Cockpit"
  (`ios/Runner/Info.plist`), IPA workflow.
- v0.2: Heute ring trio Schlaf · Erholung · Belastung with the value inside the
  ring and the label in its opening; STRAP wordmark
  (`lib/ui2/screens/home_screen.dart`).
- v0.3: white cockpit palette as the default theme (`theme_controller.dart`
  `_parse`: no stored choice → light); German for the visible untranslated
  strings and "Belastung" instead of "Strain" in short labels
  (`app_de.arb`); no Discord nudge on Heute.
- Known gap: the Morgen, Abend and Verlauf tabs still show Edge's Sleep,
  Activity and Health screens under the new names (backlog 4 and 5).

## Backlog (Armin's order)

1. ~~White app design~~ (v0.3).
2. Weight and body fat from Apple Health (Garmin Index scale → Garmin Connect →
   Apple Health) as a trend card in Verlauf. Display only: never an input to
   any OpenStrap metric.
3. Heute cards from the design: Vitalwerte, Stress in Ruhe, Mein Tag,
   Kennzahlen.
4. Own Morgen- and Abend-Briefing screens (today they show Edge's Sleep and
   Activity tabs).
5. Verlauf screen from the design.
6. Garmin history from the GDPR export (requested 2026-10-16): its own series
   beside OpenStrap's, never blended into baselines.
7. App icon.
