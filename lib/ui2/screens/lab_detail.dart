// Gesundheit › Labor › one marker (Strap Cockpit, Armin 2026-10-25).
//
// Every draw of one marker over time against its typical range, the list of
// draws, and what the sensors saw around each draw: the 7 days up to it next
// to the usual of the 60 days before. SIDE BY SIDE ONLY. A handful of draws
// is far too few to compute a relationship, so nothing here claims one.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/db.dart';
import '../../data/lab_catalogue.dart';
import '../../health/health_measurement_import.dart' show kKindWeight;
import '../../l10n/app_localizations.dart';
import '../../l10n/decimal_text.dart';
import '../../l10n/display_text.dart';
import '../../state/locale_controller.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../ui2.dart';
import 'metric_detail.dart' show detailScaffold;

/// A lab value as the marker rounds it (half away from zero), with the
/// display language's decimal mark ("0,70" in German).
String labNum(LabMarker m, double v) => m.format(v).replaceFirst(
    '.', NumberFormat('0', LocaleController.displayLanguageCode).symbols.DECIMAL_SEP);

/// The sensors worth reading beside a marker, by what the marker is about.
/// `training` is the sessions of the 3 days before the draw (hard training
/// lifts liver and muscle enzymes and CRP); the rest are `metric_series` keys
/// plus `weight` (the scale, `imported_measurement`).
const Map<LabCategory, List<String>> kLabContextSensors = {
  LabCategory.blood: ['rhr', 'vo2max'],
  LabCategory.iron: ['rhr', 'vo2max'],
  LabCategory.metabolic: ['weight', 'steps', 'vo2max'],
  LabCategory.lipids: ['weight', 'steps', 'vo2max'],
  LabCategory.hormones: ['rhr', 'rmssd', 'tst_min'],
  LabCategory.vitamins: ['training', 'tst_min'],
  LabCategory.inflammation: ['rhr', 'rmssd', 'resp_rate', 'training'],
  LabCategory.organ: ['training', 'weight', 'rhr'],
};

/// One sensor beside one draw: the mean of the [weekDays] days up to and
/// including [drawDate], and the median of the [usualDays] days before that.
/// Null parts where there is nothing to read; never a filled-in value.
({double? week, double? usual}) sensorAround(
  List<({String date, double v})> series,
  String drawDate, {
  int weekDays = 7,
  int usualDays = 60,
}) {
  final d = DateTime.parse(drawDate);
  String back(int n) {
    final x = DateTime(d.year, d.month, d.day - n);
    return '${x.year.toString().padLeft(4, '0')}-'
        '${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
  }

  final weekFrom = back(weekDays - 1);
  final usualFrom = back(weekDays - 1 + usualDays);
  final week = [
    for (final p in series)
      if (p.date.compareTo(weekFrom) >= 0 && p.date.compareTo(drawDate) <= 0) p.v
  ];
  final usual = [
    for (final p in series)
      if (p.date.compareTo(usualFrom) >= 0 && p.date.compareTo(weekFrom) < 0) p.v
  ]..sort();
  return (
    week: week.isEmpty ? null : week.reduce((a, b) => a + b) / week.length,
    // Under a week of history is no "usual".
    usual: usual.length < 7 ? null : usual[usual.length ~/ 2],
  );
}

class LabDetail extends StatefulWidget {
  final LabMarker marker;
  final String? sex;

  /// The Labor section's own remove flow (it names the draw and asks first).
  final Future<void> Function(Map<String, dynamic> row) remove;

  const LabDetail(this.marker,
      {super.key, required this.sex, required this.remove});

  @override
  State<LabDetail> createState() => _LabDetailState();
}

class _LabDetailState extends State<LabDetail> {
  List<Map<String, dynamic>>? _rows; // newest first
  final _series = <String, List<({String date, double v})>>{};
  List<Map<String, dynamic>> _sessions = const [];

  List<String> get _sensors =>
      kLabContextSensors[widget.marker.category] ?? const ['rhr'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = [
      for (final r in await LocalDb.labResults())
        if (r['marker'] == widget.marker.key && r['value'] is num) r,
    ];
    for (final k in _sensors) {
      if (k == 'training' || _series.containsKey(k)) continue;
      if (k == 'weight') {
        _series[k] = [
          for (final r in await LocalDb.importedMeasurements(kKindWeight,
              limit: 5000))
            (
              date: _label(DateTime.fromMillisecondsSinceEpoch(
                  (r['ts'] as num).toInt() * 1000)),
              v: (r['value'] as num).toDouble(),
            ),
        ];
        continue;
      }
      _series[k] = [
        for (final r in await LocalDb.metricSeries(k, measuredOnly: true))
          if (r['value'] is num)
            (date: r['date'].toString(), v: (r['value'] as num).toDouble()),
      ];
    }
    if (_sensors.contains('training') && rows.isNotEmpty) {
      final first = DateTime.parse(rows.last['taken_on'].toString());
      _sessions = await LocalDb.sessionsInRange(
          DateTime(first.year, first.month, first.day - 4)
                  .millisecondsSinceEpoch ~/
              1000,
          DateTime.now().millisecondsSinceEpoch ~/ 1000);
    }
    if (mounted) setState(() => _rows = rows);
  }

  static String _label(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _date(BuildContext c, String label) =>
      // With the year: draws are months or years apart.
      MaterialLocalizations.of(c).formatShortDate(DateTime.parse(label));

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final m = widget.marker;
    final title = m.custom ? m.label : uiText(c, m.label);
    final rows = _rows;
    if (rows == null) {
      return detailScaffold(
          c, title, const [Center(child: CircularProgressIndicator())]);
    }
    if (rows.isEmpty) {
      return detailScaffold(c, title, [
        StatusCard(l?.healthNoLabResults ?? 'No lab results',
            l?.labDetailEmpty ?? 'No result for this marker any more.'),
      ]);
    }
    final range = m.rangeFor(widget.sex);
    final latest = rows.first;
    final v = (latest['value'] as num).toDouble();
    final unit = (latest['unit'] ?? m.unit).toString();
    final inRange = m.inRange(v, sex: widget.sex);

    return detailScaffold(c, title, [
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic, children: [
            Text(labNum(m, v),
                style: F.n48.copyWith(
                    color: inRange == false ? p.on(C.orange) : p.ink)),
            const SizedBox(width: S.x2),
            Text(unit, style: F.cap.copyWith(color: p.ink3)),
          ]),
          const SizedBox(height: S.x1),
          Text(
              range == null
                  ? (l?.healthNoReferenceInterval(
                          _date(c, latest['taken_on'].toString())) ??
                      'No reference interval · ${latest['taken_on']}')
                  : (l?.healthTypicalRange(labNum(m, range.low),
                          labNum(m, range.high), _date(c, latest['taken_on'].toString())) ??
                      'Typical ${range.low}–${range.high}'),
              style: F.cap.copyWith(color: p.ink3)),
        ]),
      ),
      const SizedBox(height: S.x3),
      _chart(c, p, l, rows, range, unit),
      Section(
        l?.labDetailDraws ?? 'Results',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4),
            child: Column(children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(color: p.line, height: 1),
                _draw(c, p, rows[i]),
              ],
            ]),
          ),
          const SizedBox(height: S.x2),
          Text(l?.labDetailRemoveHint ?? 'Swipe left to remove a result.',
              style: F.over.copyWith(color: p.ink3)),
        ]),
      ),
      Section(
        l?.labDetailAround ?? 'Around the blood draw',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final r in rows) ...[
            _context(c, p, l, r['taken_on'].toString()),
            const SizedBox(height: S.x3),
          ],
        ]),
      ),
      Text(
          l?.labDetailAroundBody ??
              'Your sensors in the 7 days up to each draw, next to your usual '
                  '(the 60 days before). Side by side only: a few draws are '
                  'too few to compute a relationship.',
          style: F.over.copyWith(color: p.ink3, height: 1.6)),
      const SizedBox(height: S.x3),
      Text(l?.healthRangesDifferByLab ??
              'Ranges differ by lab. Use the one on your report.',
          style: F.over.copyWith(color: p.ink3, height: 1.6)),
    ]);
  }

  Widget _chart(BuildContext c, P p, AppLocalizations? l,
      List<Map<String, dynamic>> rows, LabRefRange? range, String unit) {
    // One slot per calendar day from the first draw to today; a draw is a dot
    // on its day, joined dimly to the next one (no value of its own).
    final today = DateTime.now();
    final day0 = DateTime(today.year, today.month, today.day);
    final first = DateTime.parse(rows.last['taken_on'].toString());
    final span = day0.difference(first).inDays + 1;
    final slots = List<double?>.filled(span < 2 ? 2 : span, null);
    for (final r in rows) {
      final i = DateTime.parse(r['taken_on'].toString()).difference(first).inDays;
      if (i >= 0 && i < slots.length) slots[i] = (r['value'] as num).toDouble();
    }
    final joined = List<double?>.of(slots);
    int? prev;
    for (var i = 0; i < joined.length; i++) {
      if (slots[i] == null) continue;
      if (prev != null && i - prev > 1) {
        final a = slots[prev]!, b = slots[i]!;
        for (var k = prev + 1; k < i; k++) {
          joined[k] = a + (b - a) * (k - prev) / (i - prev);
        }
      }
      prev = i;
    }
    final vals = [for (final v in slots) ?v];
    final band = range == null ? null : UsualRange(range.low, range.high);
    // Scaled to the draws and the typical range together, so both are on
    // the card and neither is a sliver.
    final axis = AxisSpec.of(
        [...vals, if (range != null) ...[range.low, range.high]],
        ticks: 3,
        format: widget.marker.decimals == 0 ? axisInt : axisFixed);
    final loc = MaterialLocalizations.of(c);
    return ChartFrame(
      title: l?.labDetailHistory ?? 'History',
      unit: unit,
      height: 150,
      yAxis: axis,
      band: band,
      bandColor: p.wash(C.blue),
      xLabels: [
        loc.formatShortDate(first),
        l?.metricDetailToday ?? 'Today',
      ],
      series: slots,
      child: Stack(children: [
        CustomPaint(
          size: Size.infinite,
          painter: LineChart(joined, p.ink3, fill: false, axis: axis),
        ),
        CustomPaint(
          size: Size.infinite,
          painter: LineChart(slots, p.on(C.blue),
              dots: true, fill: false, dotInk: p.card, axis: axis),
        ),
      ]),
    );
  }

  Widget _draw(BuildContext c, P p, Map<String, dynamic> r) {
    final m = widget.marker;
    final v = (r['value'] as num).toDouble();
    final inRange = m.inRange(v, sex: widget.sex);
    final note = (r['note'] ?? '').toString();
    return Dismissible(
      key: ValueKey('${r['marker']}|${r['taken_on']}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await widget.remove(r);
        await _load();
        return false; // the reload redraws the list
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: S.x2),
        child: Icon(LucideIcons.trash2, size: 18, color: p.on(C.red)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: inRange == null
                  ? p.ink3
                  : (inRange ? p.on(C.green) : p.on(C.orange)),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_date(c, r['taken_on'].toString()),
                  style: F.body.copyWith(color: p.ink)),
              if (note.isNotEmpty)
                Text(note, style: F.over.copyWith(color: p.ink3)),
            ]),
          ),
          Text(labNum(m, v),
              style: F.n17.copyWith(
                  color: inRange == false ? p.on(C.orange) : p.ink)),
          const SizedBox(width: 3),
          Text((r['unit'] ?? m.unit).toString(),
              style: F.over.copyWith(color: p.ink3)),
        ]),
      ),
    );
  }

  Widget _context(BuildContext c, P p, AppLocalizations? l, String date) {
    final lines = <(String, String, String?)>[]; // label, week, usual
    for (final k in _sensors) {
      if (k == 'training') {
        final d = DateTime.parse(date);
        final from = DateTime(d.year, d.month, d.day - 3).millisecondsSinceEpoch ~/ 1000;
        final to = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 1000;
        final s = [
          for (final x in _sessions)
            if ((x['start_ts'] as num) >= from && (x['start_ts'] as num) < to) x
        ];
        // No sensor history at all that far back: no claim of "no training".
        if (s.isEmpty && !_hasAnySeries(date)) continue;
        final min = s.fold<int>(
            0, (a, x) => a + ((x['duration_min'] as num?)?.toInt() ?? 0));
        lines.add((
          l?.labDetailTraining3d ?? 'Training, 3 days before',
          s.isEmpty
              ? (l?.labDetailNoTraining ?? 'none')
              : (l?.labDetailSessions(s.length, min) ?? '${s.length} × · $min min'),
          null,
        ));
        continue;
      }
      final a = sensorAround(_series[k] ?? const [], date);
      if (a.week == null) continue;
      String f(double x) => _fmt(k, x);
      lines.add((
        _sensorName(l, k),
        f(a.week!),
        a.usual == null ? null : (l?.labDetailUsual(f(a.usual!)) ?? 'usual ${f(a.usual!)}'),
      ));
    }
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_date(c, date), style: F.head.copyWith(color: p.ink)),
        const SizedBox(height: S.x2),
        if (lines.isEmpty)
          Text(l?.labDetailNoSensors ?? 'No sensor data for this date.',
              style: F.cap.copyWith(color: p.ink3))
        else
          for (final (label, week, usual) in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.x1),
              child: Row(children: [
                Expanded(
                    child: Text(label, style: F.body.copyWith(color: p.ink2))),
                Text(week, style: F.body.copyWith(color: p.ink)),
                if (usual != null) ...[
                  const SizedBox(width: S.x2),
                  Text(usual, style: F.over.copyWith(color: p.ink3)),
                ],
              ]),
            ),
      ]),
    );
  }

  bool _hasAnySeries(String date) => _series.values.any((s) => s.any(
      (p) => p.date.compareTo(date) <= 0 && p.date.compareTo(_back(date, 7)) >= 0));

  static String _back(String date, int n) {
    final d = DateTime.parse(date);
    return _label(DateTime(d.year, d.month, d.day - n));
  }

  String _sensorName(AppLocalizations? l, String k) => switch (k) {
        'rhr' => l?.cycleRestingHeartRate ?? 'Resting HR',
        'rmssd' => l?.healthRowHrv ?? 'HRV',
        'resp_rate' => l?.healthRowRespRate ?? 'Breathing rate',
        'tst_min' => l?.healthRowSleep ?? 'Sleep',
        'steps' => l?.dayStepsTitle ?? 'Steps',
        'weight' => l?.bodyWeightTitle ?? 'Weight',
        'vo2max' => 'VO₂max',
        _ => k,
      };

  String _fmt(String k, double v) => switch (k) {
        'rhr' => '${v.round()} bpm',
        'rmssd' => '${v.round()} ms',
        'resp_rate' => '${displayFixed(v, 1)} /min',
        'tst_min' => '${displayFixed(v / 60, 1)} h',
        'steps' => '${v.round()}',
        'weight' => '${displayFixed(v, 1)} kg',
        'vo2max' => displayFixed(v, 0),
        _ => displayFixed(v, 1),
      };
}
