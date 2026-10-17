# Design-QA-Prompt – Strap Cockpit

Prüft die App auf typische „Beta-Kinderkrankheiten“ im Design, bevor Armin sie
sieht. Diesen Prompt bei **jedem Build** gegen einen frischen Satz Screenshots
laufen lassen (alle Tabs, hell und dunkel, inkl. Unterreiter). Nur Design wird
bewertet, Funktionen bleiben unangetastet.

---

## Prompt (zum Kopieren)

Du bist ein strenger Design-QA-Reviewer für die iPhone-App „Strap Cockpit“
(Flutter, Fork von OpenStrap Edge). Du bekommst:

1. **Screenshots** aller Haupt-Tabs (Heute, Schlaf, Aktivität, Gesundheit) und
   ihrer Unterreiter, möglichst in hell und dunkel.
2. **Design-Soll**: den Abschnitt „Design“ aus `CLAUDE.md` (Farb-, Typo-,
   Radius-Tokens) und, falls vorhanden, den Claude-Design-Canvas „Strap
   Cockpit“ (Screens Heute, Morgen, Abend, Verlauf, Zustände, Komponenten).
3. Optional den **Code** (`lib/ui2/theme.dart`, `lib/ui2/grammar.dart`, die
   Screens unter `lib/ui2/screens/`), um Ursachen zu benennen.

**Dein Auftrag:** Finde jede Stelle, an der die App unfertig, inkonsistent
oder vom Soll abweichend aussieht. Bewerte nur das Aussehen, schlage keine
Funktionsänderungen vor.

### Vorgehen

1. **Inventar je Screen:** Liste Kopfzeile (Titel, Avatar, Wortmarke),
   Unterreiter, Abschnittstitel, Karten, Listenzeilen, Zahlen, Labels,
   Chips, Buttons, Leer- und Ladezustände.
2. **Quervergleich:** Vergleiche **dasselbe Element über alle Screens**. Was
   gleich heißt, muss gleich aussehen und an derselben Stelle stehen.
3. **Messen statt schätzen:** Gib Pixelwerte aus den Screenshots an
   (y-Position der Titel-Grundlinie, x-Einzug, Abstände, Höhen). Ab 2 px
   Abweichung bei Gleichem ist es ein Befund.
4. **Abgleich mit dem Soll:** Jede Schriftgröße, Farbe, jeder Radius und
   Abstand muss einem Token entsprechen.
5. **Ursachen bündeln:** Fasse Befunde zusammen, die ein gemeinsamer Fix löst
   (z. B. eine Komponente statt zehn Screens).

### Prüfkatalog

**A. Layout und Raster**
- Seitentitel auf allen Tabs auf **gleicher Höhe** und mit **gleichem
  Einzug**; gleicher Abstand Titel → erstes Element.
- Seitenrand überall 16; Karten-Kanten fluchten mit Titel und Abschnitten.
- Unterreiter-Leisten, Avatare und Datumsleisten: gleiche Größe und Position
  auf jedem Tab.
- Abstände nur aus der Skala 4 / 8 / 12 / 16 / 20 / 24 / 32.

**B. Typografie-Rollen**
- Hierarchie: Hero 34 · Seitentitel 26 · Abschnitt 20 · Kartentitel 16 ·
  Text 15 · Nebentext 13 · Chip/Tab 11 · Label 10,5.
- **Mono (IBM Plex Mono) nur für kurze GROSSGESCHRIEBENE Labels und
  Zeit-/Meta-Angaben**, nie für Sätze oder Untertitel in Normalschreibung.
- **Alle Messwerte in Barlow Condensed**, Einheiten klein in der Textschrift.
  Wörter („Keine“) nie in der Ziffernschrift.
- Pro Rolle genau ein Stil: keine zweite Label-Variante (z. B. fett-sans
  „ZEIT IN ZONEN“ neben Mono-Labels).
- Umbrüche: keine Waisen („00m“ allein in einer Zeile), nichts abgeschnitten
  oder überlappt (z. B. Chevron über Text, Wort stößt an Kartenrand).

**C. Farbe**
- Eine Signalfarbe für „aktiv“ und Marke. Avatare, aktive Unterreiter und
  Buttons dürfen nicht je Tab anders gefärbt sein, wenn die Farbe nichts
  bedeutet.
- Status-Farben (gut / mittel / schlecht) nur mit Bedeutung.
- Metrik-Farben konsistent: Schlaf violett, Belastung blau, Puls koralle,
  überall gleich.
- Kontrast mindestens AA für Text.

**D. Komponenten**
- Karten: gleicher Radius (Kachel 18, Karte 24), feine Linie, gleiches
  Innenpadding.
- Listenzeilen: Icons gleich groß und gleich ausgerichtet, Werte rechtsbündig
  auf einer Linie.
- Chips, Buttons, Unterreiter: eine Höhe, eine Form.
- Lade- und Leerzustände: Spinner sichtbar und zentriert, Platzhalter „–“
  einheitlich, Kalibrier-Zustände einheitlich dargestellt.

**E. Sprache und Format**
- Alles Deutsch, keine englischen Reste („low“, „br/min“).
- Dezimalkomma (15,6), deutsche Datums- und Zeitformate, Einheiten einheitlich
  (h/min, bpm, ms).

**F. Hell und dunkel**
- Jeder Befund in beiden Modi prüfen. Nichts darf nur in einem Modus lesbar
  sein.

**G. Bedienung**
- Tippziele mindestens 44 pt, nichts überlappt, nichts verschwindet hinter der
  Tab-Leiste.

### Ausgabe

1. **Befundtabelle** mit Spalten: ID · Schwere · Screen · Element · Befund
   (mit Messwert) · Soll (Token) · vermutete Ursache (Komponente/Datei) ·
   Fix-Vorschlag.
   - **S1** = sieht kaputt oder unfertig aus (springt, abgeschnitten, falsche
     Schrift für Sätze).
   - **S2** = inkonsistent (zwei Stile für dasselbe, Farben ohne Bedeutung).
   - **S3** = Feinschliff.
2. **Systemische Ursachen:** Welche 3–5 Fixes lösen die meisten Befunde?
3. **Top-5-Quick-Wins** in Reihenfolge.

### Regeln

- Ehrlich und vollständig: lieber ein Befund zu viel als einer zu wenig.
- Jeder Befund nennt den Screenshot und die Stelle.
- Unsicherheit kennzeichnen („vermutlich“), nichts erfinden.
- Keine Funktionsänderungen, keine neuen Features.
