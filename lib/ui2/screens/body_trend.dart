// Gesundheit › Erkunden › Körper & Tragezeit › Gewicht / Körperfett
// (Strap Cockpit, docs/TODO.md 6b).
//
// The scale's own readings (Garmin Index → Garmin Connect → Apple Health),
// from `imported_measurement`: a chart, the newest reading with its source,
// and the change over 30 and 90 days. DISPLAY ONLY — nothing here judges a
// reading against a "normal" range, and nothing derived reads this series
// (see health_measurement_import.dart).

import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../health/health_measurement_import.dart' show kKindWeight;
import '../../l10n/app_localizations.dart';
import '../../l10n/decimal_text.dart';
import '../ui2.dart';
import 'metric_detail.dart' show detailScaffold;

/// One stored reading, oldest first in every list here.
typedef BodyReading = ({int ts, double value, String source});

/// The newest reading minus the one closest to [days] ago, or null when the
/// history does not reach that far back (a change over 90 days from a month
/// of readings would be a guess).
double? bodyChange(List<BodyReading> r, int days, {int? nowSec}) {
  if (r.length < 2) return null;
  final cutoff =
      (nowSec ?? DateTime.now().millisecondsSinceEpoch ~/ 1000) - days * 86400;
  if (r.first.ts > cutoff) return null;
  BodyReading? then;
  for (final x in r) {
    if (x.ts > cutoff) break;
    then = x;
  }
  return then == null ? null : r.last.value - then.value;
}

class BodyTrendDetail extends StatefulWidget {
  final String kind; // kKindWeight or kKindBodyFat
  const BodyTrendDetail(this.kind, {super.key});

  @override
  State<BodyTrendDetail> createState() => _BodyTrendDetailState();
}

class _BodyTrendDetailState extends State<BodyTrendDetail> {
  List<BodyReading>? _r;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await LocalDb.importedMeasurements(widget.kind, limit: 2000);
    if (!mounted) return;
    setState(() => _r = [
          for (final row in rows.reversed)
            (
              ts: (row['ts'] as num).toInt(),
              value: (row['value'] as num).toDouble(),
              source: (row['source'] as String?) ?? '',
            ),
        ]);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final weight = widget.kind == kKindWeight;
    final title = weight
        ? (l?.bodyWeightTitle ?? 'Weight')
        : (l?.bodyFatTitle ?? 'Body fat');
    final unit = weight ? 'kg' : '%';
    String fmt(double v) => '${displayFixed(v, 1)} $unit';
    String signed(double v) =>
        '${v > 0 ? '+' : v < 0 ? '−' : '±'}${displayFixed(v.abs(), 1)} $unit';
    final r = _r;
    if (r == null) {
      return detailScaffold(
          c, title, const [Center(child: CircularProgressIndicator())]);
    }
    if (r.isEmpty) {
      return detailScaffold(c, title, [
        StatusCard(
          l?.bodyNoReadingsTitle ?? 'No readings yet',
          l?.bodyNoReadingsBody ??
              'They come from Apple Health. Turn on weight and body fat in '
                  'Garmin Connect\'s Apple Health settings, and allow them in '
                  'Edit profile › Import from Apple Health.',
        ),
      ]);
    }
    final last = r.last;
    final c30 = bodyChange(r, 30), c90 = bodyChange(r, 90);
    final day = MaterialLocalizations.of(c)
        .formatMediumDate(DateTime.fromMillisecondsSinceEpoch(last.ts * 1000));
    // At most a year on the chart, one point per reading.
    final shown = r.length > 365 ? r.sublist(r.length - 365) : r;
    return detailScaffold(c, title, [
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fmt(last.value), style: F.n48.copyWith(color: p.ink)),
          const SizedBox(height: S.x1),
          Text(
              l?.bodyLatestFrom(day, last.source) ??
                  '$day · from ${last.source}',
              style: F.cap.copyWith(color: p.ink3)),
          const SizedBox(height: S.x4),
          SizedBox(
            height: 140,
            child: CustomPaint(
              size: Size.infinite,
              painter: LineChart([for (final x in shown) x.value],
                  p.on(C.blue),
                  dots: shown.length < 40),
            ),
          ),
        ]),
      ),
      const SizedBox(height: S.x3),
      Surface(
        child: InlineMetrics([
          (l?.bodyChange30 ?? '30 DAYS', c30 == null ? '—' : signed(c30), C.n500),
          (l?.bodyChange90 ?? '90 DAYS', c90 == null ? '—' : signed(c90), C.n500),
          (l?.bodyReadings ?? 'READINGS', '${r.length}', C.n500),
        ]),
      ),
      const SizedBox(height: S.x3),
      Text(
          l?.bodyDisplayOnly ??
              'Your scale\'s readings from Apple Health, shown as they are. '
                  'They are not used in any score.',
          style: F.cap.copyWith(color: p.ink3)),
    ]);
  }
}
