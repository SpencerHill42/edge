import 'package:openstrap_edge/ui2/grammar.dart';
import 'package:openstrap_edge/ui2/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// Strap Cockpit: at the largest iOS size (3.1x) "Schnellzugriff" rendered as
// "Schnellzugr / iff". A word must stay on one line; the heading shrinks.
void main() {
  Future<int> lines(
    WidgetTester t,
    String text,
    double width, {
    double maxScale = double.infinity,
    TextStyle style = F.t2,
    bool intrinsic = false,
  }) async {
    Widget box = SizedBox(
      width: width,
      child: WordSafeText(text, style: style, maxScale: maxScale),
    );
    // Home's glance pairs: an IntrinsicHeight asks the height first.
    if (intrinsic) box = IntrinsicHeight(child: box);
    await t.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(3.1)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: box),
        ),
      ),
    );
    final para = t.renderObject<RenderParagraph>(
      find.byWidgetPredicate((w) => w is RichText),
    );
    final boxes = para.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    return boxes.map((b) => b.top.round()).toSet().length;
  }

  testWidgets('a long word shrinks instead of breaking', (t) async {
    expect(await lines(t, 'Schnellzugriff', 300), 1);
    expect(
      await lines(t, 'Schnellzugriff', 300, maxScale: kHeadingMaxScale),
      1,
    );
    expect(await lines(t, 'Systemstandard', 200, style: F.over), 1);
  });

  testWidgets('works inside an IntrinsicHeight', (t) async {
    expect(await lines(t, 'Trainingsbelastung', 250, intrinsic: true), 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('words still wrap between each other', (t) async {
    expect(await lines(t, 'Guten Morgen Armin', 300, style: F.t1), 3);
  });
}
