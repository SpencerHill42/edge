# Design-QA größte Schrift – 17.10.2026

Grundlage: iPhone 14 Pro Simulator (393 pt), iOS-Textgröße
„Bedienungshilfen XXXL“ (≈ 3,1×), hell, Debug-Build, Tag ohne Banddaten.
Geprüft: Home, Aktivität › Für dich, Gesundheit › Übersicht, Mehr (jeweils
ganz durchgescrollt). Nur Befunde zu Umbruch und Abschneiden.

## Befunde

| ID | Schwere | Screen | Element | Befund | Ursache | Fix |
|---|---|---|---|---|---|---|
| 1 | S1 | Mehr | Section „Schnellzugriff“ | „Schnellzugr / iff“ | `F.t2` wächst auf 62 pt, Wort breiter als die Zeile | `WordSafeText`: Überschriften max. 2× (`kHeadingMaxScale`), weiter nur so weit das längste Wort passt |
| 2 | S1 | Home | Begrüßung | „Guten …“ | `maxLines: 1` + Ellipse | `WordSafeText`, bis 3 Zeilen |
| 3 | S1 | Aktivität | Section „Trainingsbelastung“ mit Link | „Trainingsbelastun / g“, Link „Belast…“ | Titel und Link teilen sich die Zeile 50/50 | bei großer Schrift Link unter den Titel |
| 4 | S1 | Aktivität | Schnellstart-Kacheln | „Runni / ng“, „Weig / ht tra / ining“ | Drittelbreite | `WordSafeText` |
| 5 | S1 | Aktivität, Gesundheit | StatusCard-Titel | „Tr / ainingsbelast / ung“ | lange Komposita | `WordSafeText` |
| 6 | S2 | Aktivität | Start-Karte | „76 Akti…“, „Auswählen …“ | `maxLines: 1` | Karte seit PR #2 neu (ohne Maskottchen, ohne Zeilenlimit); dort `WordSafeText` |
| 7 | S2 | Gesundheit | Section „Kopf, Gewohnheiten und Medikamente“ | „… u…“ | `maxLines: 2` | bei großer Schrift ohne Zeilenlimit |
| 8 | S2 | Mehr | Einstellungszeile | „Systemstandar / d“ | Untertitel `F.over` | `WordSafeText` (Fließtext skaliert weiter voll) |
| 9 | S3 | Aktivität | Start-Karte (Debug) | `Spacer` in einer Column ohne Höhengrenze | Liste gibt keine Höhe vor | echt; mit PR #2 entfallen (Karte ohne `Spacer`) |

Alle neun behoben. Unterreiter („Aktivit ›“, „Erku ›“) sind horizontal
scrollbar mit Ausblendung: gewollt, kein Befund.

## Offen (nicht Teil dieses Durchgangs)

- Englische Texte: „Export and backup“ (Mehr), „Running / Weight training /
  Cycling“ (Aktivität).
- Home mit echten Daten (Ringe, Kacheln) nicht geprüft: der Simulator hat
  keine Banddaten.
- Dunkles Theme nicht separat fotografiert; die Änderung betrifft nur
  Schriftgröße und Umbruch, keine Farben.
