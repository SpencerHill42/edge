# Strap Cockpit — private fork of OpenStrap Edge

Armin's personal iPhone app for his WHOOP 5.0 band, built on OpenStrap Edge.
Private use only, never distributed. UI copy is German. Home-screen name
"Turbo Health" (part of Armin's "Turbo" app family) since v0.6; inside the
app the wordmark is still STRAP.

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
- Type (canvas → `F`): Instrument Sans for headings/body, IBM Plex Mono for
  labels, Barlow Condensed for figures, all bundled under `assets/fonts`.
  display 34/600 (hero) · t1 26 (screen title) · t2 20 (section, "Mein Tag")
  · head 16 (card title) · body 15/1.5 · cap 13 · over 11 (small text,
  sentences too) · label = mono 10.5/500 +8 % (short UPPERCASE labels only;
  `F.tag(s)` picks label vs over) · chip 11 (status chips, tab labels).
  Figures n34 36 (rings), n24 28, n17 18; `F.value(s)` keeps words like
  "Keine" out of the figure face. Radii: inset 14 (`R.md`), tile 18 (`R.lg`),
  card 24, chip 999. Cards: `card` + 1px `line`, no shadow on dark.
- Every tab starts with a 40 pt title row (`ScreenTitle`, Home's greeting
  matches it) with the app mark (`AppMark`, the Turbo Health icon,
  `assets/images/app_mark.png`) at its right; list top inset `S.x2`. No
  "STRAP" wordmark bar since v0.9 and no avatar since v0.7. Selected
  sub-tabs use the signal colour, not Edge's domain accents.
- Sleep stages: one violet family (`C.stage*`); zones Z1–Z5 blue ramp on dark
  only (`C.zone*`), hue ramp on white (solved blues collapse there).
- Rings: 270° segmented scale (`Ring`, `DashedRing` in `lib/ui2/charts.dart`).
- App icon (since 2026-10-17): the grayscale pulse ("Health") from the icon
  canvas https://claude.ai/artifact/5qyxBj2LV27jaYsMxLvcEY (board "Pro-Look –
  Graustufen"): chrome pulse line and dot on a dark gray gradient. Source
  `assets/branding/turbo-health-icon-mono.svg` (full square, iOS masks the
  corners); rendered with headless Chrome to 1024 px and resized with `sips`
  into `ios/Runner/Assets.xcassets/AppIcon.appiconset`. The earlier "TH"
  wordmark icon (board "Turbo – L4 optimiert", v0.6) stays as
  `assets/branding/turbo-health-icon.svg`.

## Build and install

- No Flutter SDK in the cloud sessions (pub.dev and Google storage are
  blocked). The compile check is `flutter analyze` in `.github/workflows/test.yml`
  on GitHub.
- Local loop on Armin's Mac (Claude Code, Simulator, hot reload, design QA on
  Simulator screenshots): `docs/MAC_SETUP.md`. Prefer it over the CI round
  trip for anything visual.
- `.github/workflows/cockpit-ipa.yml` builds an unsigned `StrapCockpit.ipa` on
  every push to `main` (Actions → run → Artifacts). The build fake-signs
  `Runner` with `ios/sideload/Runner-sideload.entitlements` (`ldid`,
  HealthKit only).
- **Installing on Armin's iPhone, since 2026-10-18: from this Mac with Xcode,
  not AltStore.** AltStore and Sideloadly both dropped HealthKit with his free
  Apple ID (iOS log: "Missing com.apple.developer.healthkit entitlement"),
  while Xcode's own free provisioning for his Personal Team grants it. Same
  team and bundle ID as the AltStore install (`PY4FST339R`,
  `com.example.openstrapEdge.PY4FST339R`), so it replaces that app in place:
  data and band bond stay. Steps in `docs/MAC_SETUP.md` ("Install on the
  iPhone"). Valid 7 days, then re-run. **Never refresh or reinstall Turbo
  Health from AltStore any more**: its re-sign strips HealthKit again.
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
- v0.4: design pass only (Armin, 2026-10-17: change the look, keep every
  function and the four tabs). Canvas type scale and radii in `theme.dart`,
  bundled Instrument Sans + IBM Plex Mono, hairline cards, chips, section
  titles, tab bar; tab names back to Heute · Schlaf · Aktivität · Gesundheit
  so name and content match. Restructuring tabs/screens is a later phase.
- v0.5: fixes from the first design QA (`docs/design-qa/2026-10-17-v0.4.md`):
  one header for all tabs, mono only for labels, figures in Barlow, one
  selection colour, no clipped sub-tabs, German stress level / unit / comma.
- v0.6: app icon and home-screen name "Turbo Health" (`Info.plist`).
- v0.7: first restructure step (Armin, 2026-10-17). Tabs Home · Aktivität ·
  Gesundheit · Mehr (`ShellDomain`: no `sleep`, new `more`; `tabToday` =
  "Home" in de/en, `tabMore` = "Mehr").
  - Sleep tab removed: the Home sleep ring pushes `SleepTab(day:)`, the same
    sleep screen with plan, alarm and body clock. `/sleep` notifications land
    on Home and push it; `/alarm` pushes the alarm over Home.
  - Profile avatar removed from every header; Profile is the "Mehr" tab
    (`ProfileHome(embedded: true)`, menu icon). `/profile` lands there.
  - Home: "Plan für heute" (step, strain, sleep goals) removed; the briefing
    door under it stays. Day timeline: no "double-tapped the band" line
    (event 14; always accidental for Armin).
  - Saved tab under `Prefs.shellTabV3`; the four-tab index is translated once.
  - Aktivität and Gesundheit: Armin is still deciding whether to keep them.
- v0.8: no status card on Home while a sync or derive runs and the day
  already has values; the "Synchronisiert bis" line gets a small spinner and
  "wird aktualisiert …" instead (`syncedThroughLine(showActivity:)`). The big
  card stays for a bare day. Cause: iOS defers derivation to the foreground
  (`derive_scheduler.dart`), so almost every launch derives.
- v0.9 (Armin, 2026-10-17): minimal and private.
  - No mascots: `StartCard` is a hairline card with a start button.
  - No "STRAP" bar (`CockpitBar` deleted); the app mark sits top right.
  - Mehr: no Community group (GitHub, Reddit, Discord, Sponsor).
  - Gesundheit: no "Kopf, Gewohnheiten und Medikamente" section; breathing,
    mood, habits and medication are gone. `WellnessScreen` only shows the
    cycle, and the row to it only while cycle tracking is on.
  - Weight follows Apple Health (Garmin Index → Garmin Connect → Health) on
    launch and every foreground (`autoWeightFromHealth` in `app.dart`), once
    the store was read by hand in Profil bearbeiten.

- v0.10 (Armin, 2026-10-18): Strava sync (`lib/strava/`, docs/TODO.md item 6).
  - Laufen → Run, Spazieren → Walk, Fußball → Soccer, Padel → Padel
    (Workout if refused), uploaded as TCX with HR (and the route) via
    `/api/v3/uploads`, `external_id` = session id, then `PUT sport_type`.
  - Automatic: queued on finish, uploaded once the band's beats reach the
    session end (they arrive in the sync after the workout; `stravaReady`),
    drained after every derive (`insightsRevision`) and every foreground.
  - Keys and tokens only in the keychain (Mehr › Strava, `StravaVault`);
    login via ASWebAuthenticationSession (`StravaAuthBridge` in
    `AppDelegate.swift`), redirect `turbohealth://localhost`. Write only:
    nothing from Strava reaches the coach.

- Commute rides (Armin, 2026-10-18; `lib/strava/commute.dart`): he forgets to
  start rides to work. The iPhone's activity log (CMMotionActivityManager,
  `MotionActivityBridge` in `AppDelegate.swift`, kept 7 days, same Motion
  grant as the pedometer) gives the cycling spans; a span of 5–60 min with
  the band's HR covering half of it at ≥ 85 bpm and no overlapping session
  is saved as a `Cycling` session (`source: auto_commute`) and uploaded as a
  commute Ride named "Pendelfahrt". Longer rides are Wahoo tours and are
  left alone. No GPS, so no map. Runs on launch, foreground and every derive.

## Design QA (every build)

- Before telling Armin a build is ready, run `docs/DESIGN_QA.md` against
  screenshots of every tab (light and dark) and fix S1/S2 findings first. Keep
  each audit in `docs/design-qa/`. He should never be the one to spot a jumping
  title or a wrong font.

## Band pairing (learned the hard way, 2026-10-17)

- One app owns the band. AccessorySetupKit removals (in-app "Band
  entfernen", iOS "Gerät ignorieren", deleting an app) drop the iPhone's bond
  for every app, but the WHOOP 5 keeps its side.
- After that the link comes up and then fails with "Encryption is
  insufficient" / "Authentication is insufficient" (see `openstrap_sync.log`
  in the app's Documents folder, visible in the Files app). The app only
  shows "Verbindung wird hergestellt" — it does not classify these iOS ATT
  errors as a bond refusal (fix candidate, upstream bug).
- Fix: remove the band in the app and in iOS Bluetooth, take the band off the
  wrist, tap it until the LED flashes blue (pairing mode, 3 min), then pair.

## Backlog (Armin's order)

Near-term work with full context (HealthKit in the AltStore build, provisional
rings on Home, detail typography, sleep/energy accuracy, open decisions):
`docs/TODO.md`. Read it at the start of a session.


1. ~~White app design~~ (v0.3).
2. Weight and body fat from Apple Health (Garmin Index scale → Garmin Connect →
   Apple Health) as a trend card in Verlauf. The profile WEIGHT already follows
   Health automatically (v0.9); the trend card and body fat are open, and body
   fat stays display only.
3. Heute cards from the design: Vitalwerte, Stress in Ruhe, Mein Tag,
   Kennzahlen.
4. Own Morgen- and Abend-Briefing screens (after the design pass; v0.7 has
   Home · Aktivität · Gesundheit). The restructure follows
   `docs/design-review-whoop-principles.md`: tabs by depth (Tier 1 overview,
   Tier 2 trends, Tier 3 only behind a tap), colour = meaning, prose behind ⓘ.
5. Verlauf screen from the design.
6. Garmin history from the GDPR export (requested 2026-10-16): its own series
   beside OpenStrap's, never blended into baselines.
7. ~~App icon~~ (v0.6, Turbo Health).
8. VO2max in the app (Armin, 2026-10-17): its own card/trend, not only in
   the run summary. Exists today: a submax estimate per run, from one
   completed km at steady state (`sessions.vo2max_estimate`, analytics
   `clinical/vo2max.dart`, shown in `ui2/activity/summary.dart`). Show the
   latest value and its trend; no run with a valid km → "—", never a guess.
9. Fitness age (Armin, 2026-10-17): an estimate from that measured VO2max
   against age/sex norms, with "X Jahre jünger/älter als dein Alter" next
   to it. Edge deliberately deleted its old `physiologicalAge` (15.3·maxHr/rhr
   was a fabricated input, see `derivation_engine.dart`), so: only from a
   real VO2max, needs age and sex from the profile, abstains otherwise, and
   the norm table is cited. A new metric belongs in OpenStrap/analytics.
