# To-do for Claude Code (state 2026-10-24)

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
- **Done 2026-10-18, by a different route.** The ldid step (PR #6) puts
  HealthKit in the IPA, but AltStore and Sideloadly both drop it with a free
  Apple ID (iOS log: "Missing com.apple.developer.healthkit entitlement").
  Installing from this Mac with Xcode and Armin's Personal Team (same bundle
  ID, in place) works: the Health permission sheet appeared and Armin granted
  it. How to install: `docs/MAC_SETUP.md` › "Install on the iPhone". Still to
  watch: the weight following Health on the next launches.
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

- **Done 2026-10-18:** every Health `requestPermission()` clears and, on a
  throw, records `lastHealthError` and writes it to `openstrap_sync.log`;
  callers show `healthNotGranted()`: the failure with its reason ("konnte
  nicht gefragt werden … liegt an der Installation") instead of "nicht
  freigegeben". Test: `test/health_error_message_test.dart`.

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

- **Done 2026-10-18 (Armin: 30 min after a confirmed wake):** `getToday`
  serves today's night when `recovery_state` is provisional
  (`overnight_provisional`), the sleep ring greyed like recovery; the
  settled readiness metric stays empty until `overnightSettled`, so the
  #448 guard and the pin are unchanged. Before the wake is confirmed the
  sleep ring says "Wird ausgewertet", not "Kein Schlaf". Test in
  `test/overnight_settled_test.dart`.

### 3b. Belastung stays empty: age and sex disappear from the profile (BUG)

- **Seen (2026-10-24, 19:16):** Home Belastung ring "–", card "Dein Alter fehlt,
  und dieser Wert wird daraus berechnet". Earlier the same day Armin had a
  strain value. Profil bearbeiten shows Geschlecht and Alter "Nicht
  festgelegt" (weight 74.5 is there). He says the fields "delete themselves";
  importing from Apple Health brought back only the weight.
- **Gate:** `onehz_pipeline.dart` (~line 975): `strainAbsentNote` is non-null
  without age (`hrMax == null`) or without sex, so strain, TRIMP and calories
  go absent. `needInputNote('age')` is the card text.
- **Found so far:** `AppState.updateProfile` only merges (`{...user, ...fields}`),
  nothing there clears a field; `signOut`/`resetAllData` remove the whole
  `local_profile_json`. `health_profile_import.dart` fills age and sex only
  when Health has birthday/sex, and Armin's Health probably holds neither.
  The cause of the loss is NOT found. Suspects to check: a reinstall via Xcode
  (since 2026-10-18) wiping SharedPreferences, the Garmin import or a backup
  restore writing a profile without these fields, the headless profile read
  (`ios_bg_task.dart` `_loadProfile`).
- **Do:** reproduce (log `local_profile_json` on launch, on foreground, after
  Garmin import and after Health import), find what drops age/sex, fix it.
  Then: when a field is missing, say so on the ring ("Alter und Geschlecht
  fehlen" with a tap into Profil bearbeiten) instead of a bare "–".
- **Done when:** age and sex survive restart, Garmin import, Health import and
  an Xcode reinstall; a regression test covers the merge.

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

### 4b. Sleep screen: skin temperature shown as raw numbers

On the sleep screen (night chart tooltip and legend) "Temp." reads `136.20`
or `-140.00`, and the legend reads "Hauttemp. -253,5–174,9 rel". These are
raw ADC-relative values with a dot decimal and no meaning to a reader
(screenshots 2026-10-18). Show the deviation from his own night baseline
instead, or leave the number out and keep only the curve. Use a German comma.

### 5. Design QA

Run `docs/DESIGN_QA.md` on the Simulator for v0.9/v0.10: every tab, light and
dark, plus the pushed sleep screen (Home sleep ring), Mehr and the metric
detail screens. Save the audit in `docs/design-qa/`. Fix S1/S2 before Armin
installs.

## Next feature: Strava sync (Armin, 2026-10-18)

### 6. Send workouts to Strava

- **Goal:** Workouts recorded in the app reach Armin's Strava account with
  heart rate:
  - Laufen (`Running`, with GPS) → Strava `Run`
  - Spazieren (`Walking`, with GPS) → `Walk`
  - Fußball (`Football`, no GPS) → `Soccer`
  - Padel (`Padel`, no GPS) → `Padel`
  The catalogue names are in `lib/ui2/activity/catalogue.dart`.
- **Exists today:** "Share to Strava" in the activity summary
  (`lib/ui2/activity/summary.dart` ~950–1090) writes a GPX file
  (`lib/gps/gpx_export.dart`, HR as `gpxtpx:hr`) and opens the share sheet.
  It is manual and only covers workouts with a route, so football and padel
  cannot be sent at all.
- **Approach: the Strava API, on Armin's own API app.**
  - **API app:** Armin registers it himself at strava.com/settings/api with
    his own login (created 2026-10-18 as "Turbo Health", category Mobile App,
    website https://github.com/SpencerHill42/edge, callback domain
    `localhost`). New apps start with 1 athlete, which is enough for him.
  - **Credentials, not in the build:** The IPA is built on GitHub, and
    artifacts of this public repo can be downloaded by anyone, so a baked-in
    secret would leak. Instead, the Strava screen in Mehr asks once for the
    client ID and secret (paste) and keeps them in the keychain, the same
    pattern as the coach's BYOK setup.
  - **OAuth:** in-app login (ASWebAuthenticationSession or similar) with
    scope `activity:write` (plus `activity:read` only if needed for the
    upload status). The redirect URI is `turbohealth://localhost`: its host
    matches the callback domain `localhost`. Register the `turbohealth` URL
    scheme in `Info.plist`. Keep the tokens in
    the keychain (`flutter_secure_storage` is already a dependency) and
    refresh them on expiry. Disconnecting revokes via
    `POST /oauth/revoke`.
  - **Upload:** use a file upload (`POST /api/v3/uploads`, multipart), not a
    manual activity, so the HR graph survives:
    - Format: TCX or FIT with a time and HR on every trackpoint, plus
      lat/lng only when the workout has a route. Strava documents position as
      optional. Verify that a GPS-less file with HR is accepted.
    - Set `external_id` to the session id, so a retry cannot create a duplicate.
    - Poll `GET /uploads/{id}` (≥ 1 s apart) until an activity id comes back.
    - If the file's sport did not map, set the type with
      `PUT /activities/{id}` and `sport_type`.
  - **Verify on Armin's account:**
    - Check that `sport_type: "Padel"` is accepted. Strava's app lists Padel,
      but older client enums lack it. Fallback: `Workout` named "Padel".
    - Check that `Soccer` is the API name for "Football (Soccer)".
  - **Store per session:** `strava_activity_id` and the upload state
    (queued / uploading / done / failed + reason). Show it in the summary
    ("Auf Strava ✓" or the error), with a retry button.
  - **Offline:** keep failed or offline uploads in a queue and retry them on
    the next foreground (the same moment the derive drains).
- **Strava API rules 2026 to respect:**
  - Strava data must not be used in AI features. We only write, never feed
    Strava responses to the coach.
  - Caching is limited to 7 days.
  - New base URL `api-v3.strava.com` from 2027-01-04.
  - Tokens must go in headers by 2027-06-01.
  - Check during registration whether a Strava subscription is required for
    API access (the 2026 change requires one for Standard Tier).
- **Not this route:**
  - Apple Health → Strava: Strava's Health import is documented for Apple
    Watch workouts, and HealthKit is broken in the AltStore build anyway
    (item 1).
  - A manual activity (`POST /activities`) has no HR, so use it only as a
    fallback when an upload fails for a workout without data.
- **Done when:** a run and a walk show on Strava with map and HR, football
  and padel with HR and the right sport, nothing is duplicated after a
  retry, and the status is visible in the app.

- **Status 2026-10-18:** built (v0.10, see `CLAUDE.md`). Connected on
  Armin's account, and a walk reached Strava after a retry. The first try
  had run before the band's beats were synced, so uploads now wait for them
  (`stravaReady`). Still to see on Strava: HR graph on the walk, a run with
  map, whether `Soccer` and `Padel` are accepted as sport types.

### 6b. Weight and body-fat trend (Armin, 2026-10-18)

- **Wanted:** a weight trend and a body-fat trend, under Gesundheit ›
  Erkunden › "Körper & Tragezeit".
- **Source:** Apple Health (Garmin Index → Garmin Connect → Health writes
  both `WEIGHT` and `BODY_FAT_PERCENTAGE`). HealthKit works since the Xcode
  install (item 1); the profile weight already follows Health (v0.9).
- **Do:** read the history (not only the newest value) into its own series,
  two rows in "Körper & Tragezeit" opening the usual metric detail (chart,
  latest value, change over 30/90 days). Display only: never an input to an
  OpenStrap metric or baseline, never judged against a "normal" range.
  `health_screen.dart` has a comment against a "body composition" section;
  it argues against judging weight, not against showing his own trend, so
  keep to that.
- **Done when:** both rows show Armin's Garmin history with a chart, and a
  new weigh-in appears after the next app start.
- **Done 2026-10-18** (PR #8 and the follow-up): weight and body fat show
  under Körper & Tragezeit with axes and a date axis; the body-fat grant is
  asked on launch once Health has been read by hand. Confirmed by Armin.

## Soon (analytics; most of it belongs upstream in OpenStrap/analytics)

### 7. Sleep: wake is hardly detected

- The analytics' own held-out numbers (`lib/src/onehz/sleep/cardio_stager.dart`):
  4-class κ **0.132**, wake sensitivity **11 %**. Consumer wearables reach
  κ 0.21–0.53 against PSG, and the WHOOP firmware on this band scores 0.37.
- **Effect:** total sleep is overstated; "Keine Wachphasen von 5 Minuten oder
  länger" is common, and deep/REM split is weak. This is the biggest accuracy
  gap compared with WHOOP and the Apple Watch.
- Research item, not a quick fix. Start by measuring on Armin's nights. There
  is no PSG reference, so look for systematic patterns, e.g. compare with the
  times he reports going to bed and getting up.

### 7b. Breathing rate is withheld at Armin's low sleeping heart rate

- **Seen:** On the night chart, the breathing line is only a short stroke
  around 01:00, and the summary has no breathing figure.
- **Cause:** RSA breathing comes from beat timing (`respiration/resp_rate.dart`).
  The tachogram's Nyquist is 0.5/NN, and the code withholds any window whose
  ceiling is below 0.40 Hz (24 br/min) to rule out aliasing. That needs
  HR ≥ 48 bpm. Armin sleeps at 39–61 bpm (mean 43), so almost every window is
  withheld. Correct by design, but it hits every fit sleeper.
- **Idea (upstream research):** Accept a window when the peak lies clearly
  below the ceiling and the RIIV (PPG) estimate agrees, instead of refusing
  everything under 48 bpm. This needs validation before it ships.

### 8. Active energy misses everyday movement

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

### 9. Sleep need of 11 h

A small-sample artifact: the baseline is the p75 of weekend nights, plus debt
and a strain bonus, capped at 11 h. Proposed: show the sleep need only after
enough weekend nights. Armin has not decided yet (see below). On 2026-10-18
the sleep screen said "Licht aus 19:58" from a need of 10h 44m, which is
absurd for an adult who sleeps ~7–8 h.

- **Done 2026-10-21 (kAlgoVersion 114):** Armin's 10h59 was OSD 9.1 h (p75
  of only two free nights, confidence 0.4) + the whole 1.4 h "debt" (which is
  OSD − habitual, not a recent deficit) + strain. The need now waits for 4
  free nights (absent before, the ring shows hours without a target) and adds
  at most 1 h of debt to a night. Goldens: only `algo_version` and the
  absent-need note changed.

## Garmin reference (Armin, 2026-10-24)

Armin's Garmin history (738 days, imported 2026-10-22, `garmin_import.dart`)
is the only long reference he has. There are NO nights where Garmin and the
WHOOP overlap (Cirqa sold 2026-10-13), so nothing here is trained on paired
sensor data. Garmin's scores are not imported today (decision 2026-10-22: no
foreign scores in baselines); here they may serve only as a learning target
and a comparison, in their own series, never in a baseline.

### 10. Check what the Garmin export really holds

List the files and fields of the ZIP: which scores (sleep score, body battery,
training readiness, stress), which time series (HR, stress, sleep movement),
and whether any raw signal exists. Write the result into this file. Everything
below depends on it.

### 11. Garmin sleep score: reproduce it, maybe

Fit Garmin's score on Garmin's own nightly inputs (duration, stage minutes,
restlessness, HRV, resting HR) over the old nights. Hold out the last ~100
nights; show nothing unless the error is small. Apply it to our nights as
"nachgebildet nach deinem Garmin-Verlauf", never as a Garmin value. Caveat: our
stages come from `cardio_stager` and differ from Garmin's, so expect a
systematic offset. Also the open question from Armin's 2026-10-24 remark: the
Home ring is time over need (103 %), not quality; a transparent 0–100 sleep
note (duration vs need, efficiency, deep/REM share, restlessness, regularity)
is the alternative.

### 12. Recovery: ours against a Garmin reproduction

Our readiness (HRV + RHR autonomic 0.70, RR, temp, 14-night baseline) next to
a reproduction of Garmin's Training Readiness / body battery from Garmin's own
inputs. Show both over the Garmin history to see where they disagree. Only
nights with a real input count; no fill.

### 13. VO2max: reverse-engineer and compare

Garmin's VO2max (`MetricsMaxMetData_*.json`) against our submax estimate
(`clinical/vo2max.dart`, one completed km, ACSM + %HRR). Use the runs in the
Garmin history that have both a Garmin value and a usable km to measure our
bias and spread. A correction only if it holds on held-out runs and is cited as
a calibration against this one watch; otherwise just report the gap. Feeds
CLAUDE.md items 8 and 9.

### 14. Garmin's counterpart to Belastung

Find out which Garmin metric plays the role of our strain (candidates:
training load / acute load, training effect, body battery drain, stress). Put
it next to our 0–21 strain over the history, then see whether it can be
reproduced from the HR data we have. Write down which Garmin metric it is and
why before building anything.

## Open decisions (ask Armin, bundled in one question)

- Keep the Aktivität and Gesundheit tabs? (He may track with Strava instead.)
- Does he have an Apple Watch? This decides whether Bevel would have its own
  data or only what Edge writes to Health.
- Sleep need: hide it until enough nights exist (item 9)?
- Provisional rings (item 3): right after waking, or 30 min later?
- Sleep stages: keep the ranges ("Tief 37m–1h 37m"), or show the point
  figure with "≈" and move the range behind ⓘ (Tier 3)?
- Strava (item 6): upload automatically after every finished workout of
  these four sports, or only on a tap in the summary?

## Parked

- Upstream bug: iOS ATT "Encryption/Authentication is insufficient" is not
  classified as a bond refusal (see "Band pairing" in `CLAUDE.md`).
- Device tile names "Bluetooth heart rate sensor" / "WHOOP 4".
- Size and contrast of the spinner in the bare-day status card.
- Branch `ci/test-report` (an experiment with `--reporter=github`; it gave no
  per-test annotations) can be deleted.
- `health_workout_export_delete_gate_test.dart` fails on upstream 0.11.3 too.
- `low_readiness_agreement_test.dart` (two "pinned day" cases) fails from
  2026-10-18 on, already on 4497ef5c (before any fork-test work): looks
  date-dependent. Not caused by Strava.
- `vendor_flag_off_families_test.dart` (4) and `device_use_switch_test.dart`
  (2) fail on main as of 2026-10-18 too (checked before merging TODO 3):
  pre-existing, not from the fork's changes of that day.

## Sources

Items 7–8 (accuracy):


- Keytel et al. 2005, J Sports Sci: https://pubmed.ncbi.nlm.nih.gov/15966347/
- Apple Watch meta-analysis 2025 (Choe & Kang, 56 studies):
  https://olemiss.edu/news/2025/06/apple-watch-accuracy-study/index.html
- Six wearables vs PSG (Miller et al. 2022): https://pubmed.ncbi.nlm.nih.gov/36016077/
- Six wearables incl. WHOOP 4.0 / Apple Watch S8 vs PSG (Univ. Antwerp 2025
  poster): https://medialibrary.uantwerpen.be/files/2246214/626e935b-2a41-4212-8788-0af3eec8611a.pdf

Item 6 (Strava):

- API reference: https://developers.strava.com/docs/reference/
- Uploads: https://developers.strava.com/docs/uploads/
- Supported sport types: https://support.strava.com/en-us/articles/15402005-what-sport-types-does-strava-support
- API changes 2026 (limits, policy): https://tryterra.co/blog/strava-api-changes-2026
