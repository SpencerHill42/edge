// The way into a tab: one number and a start button.
//
// One widget, two uses: Workout's "start a session" and Wellness's "start a
// sitting". They are the same card with a different count and noun, so they
// are the same code — a second copy is how the two drift a corner radius
// apart and nobody notices for a month.
//
// Strap Cockpit (Armin, 2026-10-17): minimal, like every other cockpit card.
// No mascots, no gradient, no shadow — a hairline [Surface] with the count and
// a start button in the signal colour. It used to bleed full width; the list
// still gives it no side padding, so the card pads itself to line up with
// the cards below it.
//
// LESSONS KEPT from the full-bleed version (a rendered check caught them):
//
//   · A negative `Container.margin` asserts and an [OverflowBox] in a
//     ListView takes an unbounded height and blanks the tab. Layout here stays
//     ordinary: positive padding only.
//   · The height must be a floor, never fixed: at 2x text the button clipped.
//   · No `Spacer` in the copy column: in a list it has no height bound.
//
// It is deliberately NOT in the gallery: `start_session_card_test.dart`
// renders it at a real phone width instead.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../ui2.dart';

class StartCard extends StatelessWidget {
  const StartCard({
    super.key,
    required this.label,
    required this.count,
    required this.noun,
    this.sub,
    this.onTap,
  });

  /// The overline — "START A SESSION".
  final String label;

  /// How many things are behind the tap, and what to call them. A number the
  /// screen can actually stand behind: the count of what the picker offers,
  /// never a total that includes things this tab cannot start.
  final int count;
  final String noun;

  /// The subline under the count, e.g. "Pick one and go". Nullable so the
  /// default copy can be localized in [build] rather than baked into a
  /// const-context default parameter value.
  final String? sub;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final subText = sub ?? (l?.startCardDefaultSub ?? 'Pick one and go');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x4),
      child: Surface(
        onTap: onTap,
        semanticLabel: label.toLowerCase(),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: F.tag(label).copyWith(color: p.ink3)),
                  const SizedBox(height: S.x2),
                  Text('$count $noun', style: F.t2.copyWith(color: p.ink)),
                  const SizedBox(height: S.x1),
                  Text(subText, style: F.cap.copyWith(color: p.ink3)),
                ],
              ),
            ),
            const SizedBox(width: S.x3),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: p.fill(C.signal), shape: BoxShape.circle),
              child: Icon(LucideIcons.play, size: 22, color: p.inkOnFill),
            ),
          ],
        ),
      ),
    );
  }
}
