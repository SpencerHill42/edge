# Design-Review: Strap Cockpit v0.5 gegen die WHOOP-Designprinzipien

Quelle: 925Studios, „WHOOP Design Breakdown“
(https://www.925studios.co/blog/whoop-design-breakdown), gelesen am 17.10.2026.
Nur die allgemeinen UX-Prinzipien dienen als Maßstab. Nichts davon heißt,
WHOOP-Screens, Namen oder Logos nachzubauen.

## Die Prinzipien des Artikels (Kurzfassung)

1. **Drei Ebenen (Progressive Disclosure), jede ein eigener Screen:**
   - Tier 1: Überblick mit drei Zahlen (Erholung, Belastung, Schlaf).
   - Tier 2: Wochentrends, ein Tipp auf die Kachel.
   - Tier 3: Rohdaten (HRV, Ruhepuls, Atmung, Hauttemperatur) hinter einer
     weiteren bewussten Geste, laut Artikel für rund 15 % der Nutzer.
2. **Eine Primärzahl** fasst die Komplexität zusammen.
3. **Farbe mit fester Bedeutung:** nur Grün / Gelb / Rot, keine beliebigen
   Akzentfarben.
4. **Große Primärzahlen** (Erholung ≈ 72 pt), Nebentext klein.
5. **Dunkle Oberfläche** für Checks am Morgen und Abend. Laut Artikel nicht
   pauschal besser, sondern abhängig vom Nutzungszeitpunkt.
6. **Übergänge**, die die räumliche Orientierung zwischen den Ebenen halten.
7. **Coaching in den Daten:** Erholung setzt das Belastungsziel, der
   Schlafcoach leitet Bettzeit und Dauer ab.
8. **Automatisieren:** Aktivitäten automatisch erkennen, Journal optional.
9. **Kritik an WHOOP, die man vermeiden sollte:** robotische Fachsprache in
   den Coaching-Texten, keine anpassbaren Schwellen, Datenverlust nach
   Kündigung.

## Bewertung der App (v0.5, Screenshots vom 17.10.)

| # | Prinzip | Stand in Strap Cockpit | Urteil |
|---|---|---|---|
| 1 | Tier 1 auf einen Blick | Ringe Schlaf · Erholung · Belastung vorhanden, aber erst in der unteren Bildschirmhälfte. Davor stehen Begrüßung, Datum, Sync, Akku, Tagesnavigation und eine Statuskarte. Darunter folgen weitere Feed-Karten. | ⚠️ |
| 1 | Tier 2 ein Tipp entfernt | Trends gibt es, aber verteilt (Gesundheit › Trends, Aktivität › Verlauf). Ein Tipp auf den Ring öffnet eine Detail-Analyse statt eines Wochenverlaufs. Der Verlauf-Screen aus dem Canvas fehlt noch. | ⚠️ |
| 1 | Tier 3 hinter bewusster Geste | Edge zeigt die Tiefe direkt: Hypnogramm mit Erklärabsätzen auf dem Schlaf-Tab, Begriffe wie „RMSSD“, „PRV“, „R-Zacken“, fünf Unterreiter in Gesundheit. Die Tabs sind nach **Thema** gebaut (Heute / Schlaf / Aktivität / Gesundheit), nicht nach **Tiefe**. | ❌ |
| 2 | Eine Primärzahl | Erholung kalibriert noch (2 von 14 Nächten), also gibt es heute keine Primärzahl. Ab Nacht 14 kann sie diese Rolle übernehmen. | ⚠️ (Daten) |
| 3 | Farbe mit fester Bedeutung | Der Erholungsring nutzt die Ampel ✅. Aber Grün steht auch für Schritte-Icon, HRV-Icon, Zone 3 und „96 %“. Rot ist das Herz-Icon (Kategorie, keine Warnung). In der Gesundheits-Liste haben fünf Zeilen fünf Icon-Farben. | ❌ |
| 4 | Große Primärzahl | Schlaf-Tab ✅ („9h 46m“ groß). Heute ❌: Ringzahlen 36 pt, die Begrüßung (26 pt) zieht mehr Blick als die Werte. Viele lange Erklärtexte. | ⚠️ |
| 5 | Dunkel für Morgen und Abend | Weiß ist Standard (Armins Wunsch). Die App kann „System“: hell am Tag, dunkel nach iOS-Zeitplan. | ⚠️ (Option) |
| 6 | Übergänge mit Orientierung | Standard-iOS-Übergänge, nichts Ebenen-spezifisches. | ⚠️ (gering) |
| 7 | Coaching in den Daten | Belastungsziel und Schlafplan sind vorhanden ✅. Bei dünner Datenlage falsch (Schlafbedarf 11 h), Texte technisch. | ⚠️ |
| 8 | Automatisieren | Aktivitätserkennung („2 zu prüfen“), automatischer Sync, Journal mit Auswertungen ✅. | ✅ |
| 9 | WHOOP-Kritik vermieden | Daten bleiben lokal, kein Verlust ✅. Fachsprache und lange Texte: dasselbe Problem ❌. | ⚠️ |

## Fazit

Die **Optik** stimmt seit v0.4/v0.5 weitgehend. Die **Informationsarchitektur**
ist noch Edge: Tiefe überall, Gliederung nach Thema, Farben als Kategorie statt
als Bedeutung. Genau das ist der Hebel für den geplanten Umbau. Der Canvas
(Heute · Morgen · Abend · Verlauf) passt schon zum Ebenen-Modell.

## Empfehlungen für den Umbau (Reihenfolge)

1. **Tabs nach Tiefe statt Thema:** Heute (Tier 1 + Coaching), Morgen- und
   Abend-Briefing (Tier 1 zur Tageszeit), Verlauf (Tier 2). Tier 3 nur hinter
   einem Tipp auf Ring, Kachel oder Wert, nie als eigener Tab.
2. **Heute neu ordnen:** Kopf auf eine Zeile (STRAP · Datum · Sync/Akku),
   direkt darunter die drei Ringe mit Zahl 56–72 pt. Status- und
   Erkennungskarten unter die Ringe.
3. **Farbregel festschreiben:** Ampel nur für Bewertungen. Metrikfarben
   (Schlaf violett, Belastung blau, Puls koralle) nur für ihre Metrik. Icons
   in Tinte statt bunt. Signalfarbe nur für Auswahl und Marke.
4. **Texte hinter „ⓘ“ statt im Fluss:** Erklärungen und Methodik (RMSSD, PRV,
   Wachphasen-Regeln) auf Tier 3. Auf Tier 1/2 Klartext („Herzfrequenz-
   Variabilität“, „ruhiger als üblich“).
5. **Darstellung „System“ anbieten:** hell tagsüber, dunkel abends und
   morgens. Armin entscheidet.

Datenseitig (keine Design-Frage): Primärzahl Erholung ab Nacht 14,
Schlafbedarf erst mit genug Wochenend-Nächten (11-h-Artefakt), Garmin-Import
für die Historie.
