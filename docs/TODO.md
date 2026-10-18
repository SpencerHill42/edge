# To-do for Claude Code (state 2026-10-18)

Collected in the claude.ai chat with Armin, written for the next Claude Code
session on his Mac. Order = priority. Each item says what Armin saw, the cause
found in the code, and what "done" means. The long-term backlog stays in
`CLAUDE.md` (items 2–9); this file is the near-term work plus the context
behind it. Tick items off here and move the outcome into "What the fork
changed" in `CLAUDE.md`.

## Now (next build, v0.10)

### 1. HealthKit does not work in the AltStore build (blocker)

- **Seen:** Mehr › Von deinem Smartphone › "Aus Apple Health lesen" →
  "Apple Health hat keinen Zugriff auf diese Werte gewährt". In iOS
  Settings › Health › Data Access & Devices, "Turbo Health" is **not listed**.
- **Cause (very likely):** `cockpit-ipa.yml` builds with
  `flutter build ios --no-codesign`, so `Runner.entitlements` is never embedded
  in the binary. AltStore (like other sideload signers) requests capabilities
  from the entitlements it finds in the Mach-O, so the app is signed without
  HealthKit and iOS never registers it with Health.
- **Also blocked by this:** v0.9's `autoWeightFromHealth` (weight from
  Garmin Index → Garmin Connect → Health), "In Apple Health schreiben",
  backlog item 2 (weight/body-fat trend), the RHR seed and measurement import.
- **Fix to try:** in `cockpit-ipa.yml`, after the build and before zipping,
  fake-sign the main binary with a resolved entitlements plist, e.g.
  `brew install ldid` and `ldid -Sent.plist build/ios/iphoneos/Runner.app/Runner`.
  `ent.plist` holds `com.apple.developer.healthkit = true` only to start with.
  Drop `com.apple.developer.healthkit.access` (clinical records, not needed)
  and leave App Groups out unless AltStore needs them. Check the result with
  `ldid -e` before packaging.
- **Done when:** after an AltStore install over the existing app (never
  delete it, see "Band pairing"), "Turbo Health" is listed under Health ›
  Data Access, the read button works, and the profile weight follows Health.
- **If the free Apple ID refuses HealthKit:** say so to Armin. The fallback is
  installing from Xcode with his personal team, and it has to be the
  same app (same bundle ID) so that only one app owns the band.

### 2. HealthKit errors read as "you denied it"

- `requestPermission()` in `lib/health/health_measurement_import.dart`
  (and the RHR seed and weight importers) returns `false` on any exception.
  `lib/ui2/profile/phone_import.dart` then shows
  `phoneImportMeasurementsDenied` ("… hat keinen Zugriff gewährt").
- iOS never tells an app that read access was denied (reads just come back
  empty), so `false` here means the request **failed**, not that Armin said no.
- **Do:** separate "request failed / Health not available for this install"
  from "nothing came back", with German copy for each, and write the
  exception to `openstrap_sync.log` so it shows up in the Files app.

### 3. Home rings stay empty for an hour after waking

- **Seen (2026-10-18, 07:46):** Woke at 07:22. The sleep screen already
  showed the night (7h 02m, 23:53 → 07:22), but on Home all rings read "–":
  "Kein Schlaf", "Schläft noch…", and "Die letzte Nacht wird noch ausgewertet".
- **Cause:** `getToday` (`lib/data/db.dart`, around the `overnightSettled`
  check, ~line 11506) skips today's overnight until
  `overnightSettled()` (`lib/compute/derivation_engine.dart`, ~line 2106).
  That needs the band's data edge to be ≥ wake + `_headlineFreezeMarginSec`
  (60 min). This guards #448 (a half-drained night shown as this morning's).
  The sleep screen computes from whatever is there, so the two screens disagree.
- **Wanted:** Home shows the night as soon as the wake is confirmed
  (`kWakeConfirmMarginSec`, 30 min; or right away, Armin to decide), marked
  **"vorläufig"**. The readiness pin keeps the 60-min rule, so the final value
  still never comes from a partial night.
- **Copy bug:** While the overnight state is `building`, the sleep ring must
  not say `homeRingNoSleep` ("Kein Schlaf"). It should say that it is being
  worked out.
- Keep the #448 tests green and add one for "provisional night on Home".

### 4. Detail values in the wrong font, method texts in English

- Metric detail › "Detailwerte" (`lib/ui2/screens/metric_detail.dart`
  ~2206/2214, `lib/ui2/screens/investigate.dart` ~1066) hard-code
  `fontFamily: 'Menlo'` for key/value rows and citations. This breaks the v0.5
  rule that mono is only for short UPPERCASE labels (`F.label`). Values go in
  the figure face (`F.n17`/`F.value`) or body text. Sentences such as "ein Wert
  pro berechnetem Tag" and "Band-Aufzeichnungen · auf diesem Smartphone
  berechnet" go in Instrument Sans.
- The `MetricSpec(method: …)` texts in `metric_detail.dart` (~100–260) are
  English and not in the ARB files. Example: Aktive Energie › METHODE
  "Heart-rate-to-energy regression over the waking span…". Translate them via
  l10n (the citation line already is).

### 5. Design QA

Run `docs/DESIGN_QA.md` on the Simulator for v0.9/v0.10: every tab, light and
dark, plus the pushed sleep screen (Home sleep ring), Mehr and the metric
detail screens. Save the audit in `docs/design-qa/`. Fix S1/S2 before Armin
installs.

## Soon (analytics; most of it belongs upstream in OpenStrap/analytics)

### 6. Sleep: wake is hardly detected

- The analytics' own held-out numbers (`lib/src/onehz/sleep/cardio_stager.dart`):
  4-class κ **0.132**, wake sensitivity **11 %**. Consumer wearables reach
  κ 0.21–0.53 against PSG, and the WHOOP firmware on this band scores 0.37.
- **Effect:** total sleep is overstated; "Keine Wachphasen von 5 Minuten oder
  länger" is common, and deep/REM split is weak. This is the biggest accuracy
  gap compared with WHOOP and the Apple Watch.
- Research item, not a quick fix. Start by measuring on Armin's nights. There
  is no PSG reference, so look for systematic patterns, e.g. compare with the
  times he reports going to bed and getting up.

### 7. Active energy misses everyday movement

- `Calories.dailyEnergy` (analytics `workout/calories.dart`) bills a minute
  only at HR ≥ RHR + 40 % HRR (~100 bpm for Armin). Below that it bills
  0 kcal, unless cadence is ≥ 100 spm during a **live** phone link.
  Walking and easy cycling therefore add almost nothing, so the numbers can't
  be compared with Apple's "Aktivitätskalorien".
- The Keytel 2005 equation itself is fine for Armin: with his VO2max (~57) the
  equations with and without VO2max differ by ~2 %. The error comes from the
  gate and from the population line (R² 0.73 in the lab). Wearables in general:
  ~28 % MAPE for energy (meta-analysis of 56 studies, 2025).
- **Options:**
  - Use the band's per-minute step counts for the cadence/MET path, not only
    the live cadence.
  - Personal calibration from power-meter rides: Armin has a power meter, and
    ride work in kJ ≈ kcal burned at 20–25 % gross efficiency.
- **Benchmark first:** 3–5 rides, app workout kcal against the ride's kJ.

### 8. Sleep need of 11 h

A small-sample artifact: the baseline is the p75 of weekend nights, plus debt
and a strain bonus, capped at 11 h. Proposed: show the sleep need only after
enough weekend nights. Armin has not decided yet (see below).

## Open decisions (ask Armin, bundled in one question)

- Keep the Aktivität and Gesundheit tabs? (He may track with Strava instead.)
- Does he have an Apple Watch? This decides whether Bevel would have its own
  data or only what Edge writes to Health.
- Sleep need: hide it until enough nights exist (item 8)?
- Provisional rings (item 3): right after waking, or 30 min later?

## Parked

- Upstream bug: iOS ATT "Encryption/Authentication is insufficient" is not
  classified as a bond refusal (see "Band pairing" in `CLAUDE.md`).
- Device tile names "Bluetooth heart rate sensor" / "WHOOP 4".
- Size and contrast of the spinner in the bare-day status card.
- Branch `ci/test-report` (an experiment with `--reporter=github`; it gave no
  per-test annotations) can be deleted.
- `health_workout_export_delete_gate_test.dart` fails on upstream 0.11.3 too.

## Sources behind items 6–7

- Keytel et al. 2005, J Sports Sci: https://pubmed.ncbi.nlm.nih.gov/15966347/
- Apple Watch meta-analysis 2025 (Choe & Kang, 56 studies):
  https://olemiss.edu/news/2025/06/apple-watch-accuracy-study/index.html
- Six wearables vs PSG (Miller et al. 2022): https://pubmed.ncbi.nlm.nih.gov/36016077/
- Six wearables incl. WHOOP 4.0 / Apple Watch S8 vs PSG (Univ. Antwerp 2025
  poster): https://medialibrary.uantwerpen.be/files/2246214/626e935b-2a41-4212-8788-0af3eec8611a.pdf
