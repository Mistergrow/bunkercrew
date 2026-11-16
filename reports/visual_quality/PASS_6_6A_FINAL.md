# Bunkercrew – Pass 6 + 6A: Abschlussbericht

Stand 2026-11-15. Basis: Git `d87ffb0` (v0.1.0-beta) plus nicht committeter Arbeitsbaum auf
`fix/hardening-and-tests`. Es gibt keinen Commit, keinen Push und keinen Versionssprung.

| Dokument | Inhalt |
|---|---|
| `docs/art/BUNKERCREW_VISUAL_STYLE_BIBLE.md` | Verbindliche Regeln: Pixelraster, Skalierung, Lesbarkeit, Palette, Animation, Effekte, Logo, Prüfung |
| `reports/visual_quality/DEFECT_MAP.md` | Alle 61 Defekte aus Review 5 mit Zuständigkeit, Maßnahme und Status |
| `reports/visual_quality/gallery/GALLERY.md` | Kompakte Vorher-Nachher-Galerie (Pass 5 → Endstand) mit 18 Bögen |

## 1. Ablauf

| Pass | Bereich | Ergebnis |
|---|---|---|
| 0 / 1 | Bestandsaufnahme, Defektkarte, Style Bible | 61 Defekte zugeordnet; Pixelraster und Skalierungskonzept festgelegt |
| 6W | Welt und Effekte | Wetter, Blitz, Schockwellen, Erdschichten, Asche, Schild, Flak, Telegraph, Nachtgrading, Mündungslicht, Explosion |
| 6U | Oberfläche und Lokalisierung | Ganzzahlige UI-Skalierung, WOHNTRAKT, WELLE 01 / 20, Übergänge, Menülinks, Tags, Zahlen |
| 6A-1 | Gegner-Art | Neue Infanterie, Gegnerpaletten, Mech-Geschütze, Flugzeug-Pods, Bombenschacht |
| 6A-2 | Crew-Animation und Identität | Idle, Treffer, Zusammenbruch und Aufstehen, Arbeiten an der Station, Logo, Büsten |
| 6S | Einheitliche Pixeldichte | Stationen, Requisiten und Kulissen auf dem Welttexelraster, Presse, Munitionskiste, Keller |
| D | Leistung und QA | Hitch-Analyse, Kill-Sonde, Warm-up, Golden Scenes, Suite, Blind Review |
| 7D | Pixeldichte, Rest (nach Review 6) | Gegnerrümpfe (Flugzeuge, Chassis, Fahrzeuge) mit Lagestellungen in Welttexeln; Raumwände, Zaun, Tore, Türme und Hofmodule; Basalt-Nähte |
| 7U | Oberfläche und Lesbarkeit (nach Review 6) | Panels über gedimmtem Spiel statt Schwarz, Tabwechsel, Siegtafel, TEAMARBEIT und SAN-1 frei von Tags, Dezimalkomma, Zähler, Randmarker, Schalter, gesperrte Crew-Plätze, Wellenbanner mit Bewegung |
| 7A-crew | Crew-Animation (nach Review 6) | Stehende Idle-Grundhaltung, Gehzyklus mit Kontakt- und Passposen, Knien und Aufstehen beim Wiederbeleben, lesbarer Tanz, sichtbar arbeitender Mischer |
| 7A-enemies | Gegner-Animation und Infanteriedichte (nach Review 6) | Infanterie auf ihre gezeichnete Größe 0,82 gebacken; Gehschlüssel je Rolle, Fallposen und liegende Körper, Idle und Rückstoß, Mech-Ausholen, Federung und Radlauf, Walker- und Fahrzeuggeschütze sowie Schild in Welttexeln |

## 2. Pixelraster und Skalierung

Die vollständige Fassung steht in der Style Bible, §1 und §2.

### Pixelraster
**Ein Kunstpixel ist eine Welteinheit.**
- Figuren, Gegner, Gelände und Effekte nutzten dieses Raster bereits.
- Stationen, Requisiten, Kisten und Geschütze kamen aus hochauflösenden Atlanten und wurden
  zur Laufzeit verkleinert, ebenso die gemalten Kulissen. Sie zeigten deshalb Pixel, die bis
  zu dreimal feiner waren als die der Figuren.
- Pass 6S backt diese Teile jetzt offline auf ihre Weltgröße
  (`tools/bake_world_density_art.py`, gezeichnet über `WorldTexels`). Die Kulissenplatten
  werden in Welttexelblöcken abgetastet und rasten beim Scrollen in ganzen Blöcken ein.
- Die Quellatlanten bleiben als Provenienz erhalten.

Messung mit `tools/pixel_density_report.py`. Anteil der 1-px-Merkmale, niedriger ist besser:

| Region | vorher | nachher |
|---|---|---|
| Kisten | 0,60 | 0,01 |
| Ofen | 0,47 | 0,02 |
| Dachgeschütz | 0,58 | 0,01 |
| Nahe Kulisse | 0,24 | 0,00 |
| Figuren (Referenz) | ≈ 0,08 | ≈ 0,08 |

Das kleinste gemeinsame Pixel von Station, Kulisse und Figur ist jetzt gleich:
2 Bildschirmpixel bei 2 px je Einheit, 3 bei 3 px je Einheit.

Pass 7D und 7A-enemies stellten anschließend auch diese Teile um:
- alle Gegnerrümpfe, Flugzeuge, Chassis und Fahrzeuge, mit Lagestellungen statt starrer
  Drehung;
- die Infanterie, gebacken auf ihre gezeichnete Größe 0,82; Größe und Hitboxen bleiben;
- Walker- und Fahrzeuggeschütze;
- Raumwände, Zaun, Tore, Türme und Hofmodule;
- die Schildblase.

Gemessen (Anteil 1-px-Merkmale / Ausrichtung):

| Teil | vorher | nachher |
|---|---|---|
| Fahrzeugrümpfe | 0,52–0,57 / ≤ 0,03 | ≤ 0,01 / ≥ 0,97 |
| Flugzeuge | 0,48–0,61 / ≤ 0,12 | ≤ 0,02 / 0,82–1,00 |
| Mechs (10 von 12) | bis 0,70 | ≤ 0,06 / ≥ 0,77 |
| Infanterie (Figur) | ≈ 0,25 / 0,05 | ≤ 0,04 / ≥ 0,89 |

Noch nicht umgestellt:
- Walker-Beine als gedrehte Platten
- Variantenausrüstung von Demolisher und Repair-Crawler
- Mörserbeine (Schaft)
- Vegetationsatlas
- Ventilator- und Pressenrad
- `bunker_wall.png` der klassischen Karte

### Skalierung
- **Welt:** ganze Gerätepixel je Welteinheit (`PixelGrid`).
- **Oberfläche:**
  - Entworfen auf dem 1440 × 900-Canvas (Faktor 1,2 bei 1080p, 1,6 bei 1440p).
  - Pixelbilder werden über `UiArt.pixel_fit`, `pixel_snap`, `pixel_rect` und `pixel_glyph`
    in ganzzahligen Gerätepixel-Vielfachen gezeichnet.
  - Text bleibt MSDF (Field) beziehungsweise Bitmap ab 28 px (Signal). Das ist die
    festgelegte Strategie für die nicht ganzzahligen Faktoren.
  - Gemessen sind 100 % der Farbkanten der Charakterauswahl auf der Pixelphase.

## 3. Defekte: Stand

Die Einzelheiten stehen in `DEFECT_MAP.md`.

| Status | Anzahl | IDs |
|---|---|---|
| Behoben | 38 | D06, D08, D10–D13, D15, D18–D20, D22–D24, D25–D29, D32, D33, D35–D38, D41, D44, D45, D47–D49, D51, D53, D54, D56–D60 |
| Verbessert, Teilziel | 6 | D02, D03, D21, D31, D43, D46 |
| Teilweise oder marginal | 9 | D04, D05, D07, D16, D17, D40, D42, D52, D55 |
| Gemessen, kein Defekt im Spiel | 2 | D14 (kein Blitzlicht im Raum messbar), D39 (Einschläge in der Luft kommen aus dem Capture-Staging) |
| Strukturell, dokumentiert | 3 | D01 (Kampfkamera), D09 (Koop-Karten), D34 (gleicher Bunker in allen Welten) |
| Bewusst unverändert | 1 | D50 (`Build dev` in Entwicklungsbuilds) |
| Blockiert, Entscheidung des Projektinhabers | 1 | D30 |
| Offen | 1 | D61 (Expeditionskarte braucht neue Art) |

Zu D30: Die Bearbeitung von `scenario_bunker.gd` wurde vom Berechtigungssystem abgelehnt.
Ein fertiger Ersatzschrank liegt vor. Pfad und Begründung stehen in der Defektkarte.

## 4. Neue Art-Assets

Alle Assets sind deterministisch erzeugt und haben eine `.source.json` mit Werkzeug,
Parametern und Hashes. Die Vorgängerversionen bleiben jeweils daneben erhalten. Für diese
Passes wurden 0 Meshy-Credits verbraucht.

| Asset | Größe | Inhalt |
|---|---|---|
| `assets/enemies/infantry_parts_v2.png` | 1024² | 6 Rollen mit eigener Kopfbedeckung, eigenem Gesicht, Mantel, Ausrüstung und Waffe |
| `assets/enemies/infantry_turns_v2.png`, `infantry_living_turns_v2.png`, `infantry_gun_turns_v2.png` | 3888×536, 1008², 2184×624 | RotSprite-Drehstellungen, Waffen in 7,5°-Schritten |
| `assets/enemies/aircraft_hulls_v2.png`, `chassis_atlas_v2.png`, `vehicle_hulls_v2.png` | 1672×941, 1536×1024, 1536×1408 | Gradierte Rümpfe: Typfarbe, beleuchtete Oberkante, Sensor |
| `assets/enemies/machine_weapons_v2.png` | 1248×480 | 5 Familien × 13 Zielstellungen |
| `assets/enemies/aircraft_pods_v2.png` | 2304×288 | 5 Pod-Familien × 48 Zielstellungen plus Bombenschacht |
| `assets/workers/<id>_layers.png` (8×) | 476×544 | Ebenen für Ausrüstung und Haare mit Nachschwung |
| `assets/workers/portraits/portraits_v3.png` | 640×80 | Büsten: v1-Zeichnung mit 40-Farben-Palette (v1 und v2 bleiben zum Vergleich) |
| `assets/ui/logo/bunkercrew_logo_v1.png`, `_small.png` | 277×50, 130×24 | Eigenes Pixel-Logo: Schablonen-Plattenbuchstaben, Bunkerluke mit Gefahrenstreifen und Helm |
| `assets/machinery/components_world.png` | 512×156 | Mischer, Ofen, Kern, Lafetten, Trommel in Welttexeln |
| `assets/machinery/barrel_turns_world.png` | 1024×631 | 143 Rohrstellungen im 2°-Raster |
| `assets/machinery/authored_world.png` | 160×139 | Munitionskiste, Pressenrahmen, Pressenstößel |
| `assets/props/industrial_props_world.png` | 512×355 | 42 Requisitengrößen, Pulte, Werkbank |
| `assets/supplies/industrial_crate_world.png` | 64×38 | Vorratskiste |
| `assets/rock_world.png` | 480×480 | Felsfläche |
| `assets/enemies/aircraft_hulls_world.png` (7D) | 1024×1622 | 404 Einträge: alle Zeichengrößen inklusive Elite, Lagestellungen alle 0,03 rad |
| `assets/enemies/chassis_world.png` (7D) | 1024×1850 | 462 Einträge: Walker-Rümpfe mit Neigestellungen |
| `assets/enemies/vehicle_hulls_world.png` (7D) | 256×97 | Fahrzeugrümpfe; Neigung als Spaltenscherung in ganzen Texeln |
| `assets/environments/walls_world.png` (7D) | 640×1127 | Raumwände |
| `assets/perimeter/perimeter_world.png` (7D) | 256×662 | Tore (Rahmen, Flügel, Zierleiste), Turmsockel, Turmgeschütz in 2°-Stellungen, Wrack, Servicekoffer |
| `assets/courtyard/courtyard_world.png` (7D) | 256×92 | Gitterfeld, Pfosten, Pflaster, Poller, Lampe, Schutt |
| `assets/enemies/infantry_parts_world.png`, `_turns_world`, `_living_turns_world`, `_gun_turns_world`, `_limbs_world` (7A) | 864², 2580×446, 840², 1806×516, 512×808 | Infanterie in der gezeichneten Größe 0,82; Gliedmaßen in 48 Richtungen; handkorrigierte Gesichtsdetails |
| `assets/enemies/machine_weapons_world.png` (7A) | 512×493 | Walker-Kanonen, 5 Familien in allen 16 Zeichengrößen |
| `assets/enemies/vehicle_guns_world.png` (7A) | 256×2196 | Fahrzeuggeschütze in 2°-Zielstellungen, normal und Elite; Quelle `vehicle_guns_src.png` |
| `assets/enemies/shield_bubble_world.png` (7A) | 178×94 | Schildblase mit 2-Texel-Rand, gedithertem Inneren und Kronenlicht |

Neue Werkzeuge:
- `tools/generate_infantry_parts_v2.py`
- `tools/bake_infantry_turns_v2.py`
- `tools/grade_enemy_hulls.py`
- `tools/generate_machine_weapons_v2.py`
- `tools/generate_aircraft_pods_v2.py`
- `assets/workers/generate_crew_layers.py`
- `tools/build_bunkercrew_logo.py`
- `tools/build_crew_portraits_v3.py`
- `tools/bake_world_density_art.py`
- `tools/pixel_density_report.py`
- `tools/measure_enemy_contrast.py`
- `tools/bake_infantry_world.py`
- `tools/bake_machine_weapons_world.py`
- `tools/capture_vehicle_guns.gd`
- `tools/bake_shield_world.py`

Zum Werkzeug kommen neue Bake-Aufträge in `tools/world_density_bake.json`.

## 5. Neue Animationen

Alle Körperhandlungen sind als gehaltene Posen in ganzen Texeln abgelegt
(`scripts/worker_motion_keys.gd`). Gameplay-Timing, Rückstoß und Hitboxen sind unverändert;
Tests prüfen das.

| Bewegung | Umsetzung |
|---|---|
| Idle (alle 8 Crew) | 24 Frames bei 8 fps: Gewichtsverlagerung, Atembogen, Rucksack und Haare schwingen nach, gelegentlicher Blick |
| Treffer | Aufprallpose, gehaltene Spitze und 3 Erholungsposen in 0,58 s; Schultern 6 Texel, Stiefel tritt nach; auch über Verletzt- und Hinkpose |
| Zusammenbruch | 6 Posen in 0,75 s: einknicken, Knie, kippen, aufschlagen, liegen und atmen |
| Aufstehen | Geschlüsselt über 1,1 s: Ellbogen, sitzen, knien, abdrücken, stehen |
| Arbeiten an der Station | Schleife über 1,5 s: zwei Hammerschläge an die Trommel, dann Blick in die Öffnung |
| Infanterie | Treffer mit 1 Aufprall- und 3 Erholungsposen; Zusammenbruch und Ausholen mit gehaltenen 12 fps |
| Mechs, Bodenwracks | Aufprall und Zusammenbruch mit gehaltenen 12 fps |
| Crew-Idle (7A) | Stehende Grundhaltung: Füße unter der Hüfte, ein Standbein, freie Ferse; vorher eine eingefrorene Schrittstellung |
| Crew-Gehen (7A) | Je Schritt 4 Schlüssel (Kontakt, tief, Pass, hoch), Abrollen von Ferse zu Spitze, Armbogen, Rucksack setzt verzögert auf |
| Wiederbeleben (7A) | Hinknien neben dem Körper, Drück-Schleife, Aufstehen über 4 Schlüssel |
| Tanz (7A) | Ein Takt aus Beat-Posen (Stoß, Pumpen, V-Arme, Zeigen), Hüftschritt, Kopfnicken |
| Mischer (7A) | Grundierungsband zeigt die Drehung, Rumpeln je Plattennaht, Zementspritzer, Hammerschläge mit Funken |
| Infanterie-Gehen (7A) | Eigene gehaltene Schlüssel je Rolle (Marsch, Duckgang, Trab, Stapfen, Pirsch); Standfuß bleibt verankert |
| Infanterie-Tod (7A) | Rückwärts in 4 Frames, Aufprall, zwei liegende Körperposen mit fallengelassener Waffe |
| Gegner-Idle und Rückstoß (7A) | Atmen, Gewichtswechsel, Schusskick; Walker atmen, Motorzittern bei Fahrzeugen |
| Mech-Angriff (7A) | 3 Duckframes während des Windups, Hochnicken beim Schuss |
| Fahrzeuge (7A) | Federung über Bodenwellen, 24 Rad-Drehschlüssel |

## 6. Leistung

### Ursache und Behebung des Erstabschuss-Hitches
- **Schritt 1:** Die Kill-Sonde zeigte, dass die erste Bodenexplosion einer Sitzung einen
  Frame für 150–280 ms (GPU) beziehungsweise bis 1,2 s (Software) anhielt.
- **Schritt 2:** Die Phasenmessung (Physik, Prozess, Deferred Draw, Renderserver) legte die
  Zeit in den Renderserver.
- **Schritt 3:** Die Bisektion fand die Ursache. Die Effektebenen der Explosion liegen bei
  z 24–25, oberhalb des Lampen-z-Bereichs (−8…20). Das ist eine eigene Shader-Variante,
  die beim ersten Gebrauch vorbereitet wurde.
- **Behebung:** `scripts/render_warmup.gd` zeichnet beim Laden des Szenarios die
  Ereignis-Materialien für 4 Frames unsichtbar vor, sowohl bei z 0 als auch bei z 24. Das
  verbessert den echten ersten Kill im Spiel, nicht nur die Messung. Es ist mit
  `tests/render_warmup_test.gd` abgedeckt.
- **Vorher behoben:** Der erste Flugzeugabschuss wartete auf die beleuchtete Variante des
  Wrack-Shaders (450–720 ms), weil die Warm-up-Probe außerhalb des Lampen-z-Bereichs lag.

### Messwerte
Endstand nach Pass 7, 1920×1080, alle Werte in ms.
- GPU: Messung im finalen Render `artifacts/visual-review/pass-7`.
- Software: Nachmessung nach der Warm-up-Erweiterung (siehe unten).

| Sonde | Mittel | P95 | P99 | Max | Spikes | Erster Kill | Weitere Kills |
|---|---|---|---|---|---|---|---|
| perf.wave_night.gpu | 36,9 | 38,7 | 42,1 | 50,9 | 0 | 39,3 | – |
| perf.wave_bright.gpu | 37,2 | 39,1 | 40,8 | 44,2 | 0 | 39,3 | – |
| perf.kills_night.gpu | 34,1 | 36,2 | 39,3 | 45,3 | 0 | 34,3 | 34,9–41,5 |
| perf.kills_bright.gpu | 34,3 | 36,8 | 39,2 | 45,7 | 0 | 34,2 | 35,1–37,4 |
| perf.wave_night.software | 49,8 | 66,1 | 72,7 | 80,5 | 0 | 49,4 | – |
| perf.wave_bright.software | 50,5 | 68,0 | 73,3 | 84,9 | 0 | 73,7 | – |
| perf.kills_night.software | 45,4 | 58,7 | 64,4 | 68,6 | 0 | 55,8 | 43,1–64,7 |
| perf.kills_bright.software | 44,9 | 57,5 | 62,0 | 70,6 | 0 | 47,5 | 42,1–70,6 |

Software-Erstnutzung nach Pass 7:
- **Befund:** Die neuen Welttexel-Atlanten haben überwiegend keine Zweierpotenz-Größe.
  llvmpipe baut je Textur-Größenklasse und Format eine eigene Shader-Variante.
- **Wirkung:** Erste Infanterieleiche, erstes Flugzeugwrack und erste Bodenexplosion mit
  Wrack hielten im Software-Renderer wieder 150–300 ms an. Die GPU war nicht betroffen.
- **Behebung:** Das Warm-up zeichnet die Wrack-, Leichen- und Pickup-Materialien zusätzlich
  einmal mit jedem echten Ereignis-Atlas und lädt diese Atlanten dabei vor.
- **Ergebnis:** In der Nachmessung (Tabelle) gibt es keine Spikes mehr.

Einordnung:
- **Erster Kill:** Er hebt sich nicht mehr von den Wiederholungen ab. Vorher lagen erste
  Explosion und erstes Flugzeugwrack bei 150–720 ms (GPU).
- **Gegner-Art (6A-1):**
  - Unter Last war ein Mehraufwand von etwa +1,4 ms GPU gemessen worden.
  - Eine erneute, verschränkte A/B-Messung zeigte unter vergleichbarer Last keinen
    messbaren Unterschied: 41,7 gegen 38,3 ms und 46,6 gegen 46,9 ms.
  - Das Rauschen der geteilten Maschine liegt bei ±10 ms. Eine Messung auf einer ruhigen
    Maschine steht noch aus.
- **Speicher:**
  - Pass 6S lädt die großen Quellatlanten nicht mehr (`industrial_props.png`,
    `industrial_crate.png`, je etwa 6,3 MB). Neue Atlanten kommen auf etwa 4,7 MB VRAM.
    Netto sind das etwa −8 MB je Szenario.
  - `components.png` und `rock.png` werden weiter geladen.
- **Messwerkzeug:** Die Sonde in `tests/visual_review_capture.gd` liefert jetzt P95,
  Kill-Kosten (erster Kill und Wiederholungen) und für jeden Spike eine Aufschlüsselung:
  Physik, Prozess, Deferred Draw, Renderserver, Speicher, neue und entfernte Knotentypen
  sowie Rundenphase.

## 7. Golden Reference Scenes

Die drei Referenzszenen sind feste Shots in `tools/visual_review.py`
(`tests/visual_review_shots.gd`, Stages in `tests/visual_review_stage_action.gd`) und
damit reproduzierbar. Gleiche Shot-Definition und gleicher Seed ergeben dieselbe Szene.

| Shot | Inhalt |
|---|---|
| `golden.combat`, `golden.combat.seq` | Hell, Schnee. Zwei Spieler: Dachgeschütz und Dachgewehr. HUD. Zwei Bodenmaschinen am Bunker, Flak, Flugzeuge, Projektile und Explosionen, gerahmt in der Zweispieler-Skala des Spiels (2 px je Einheit) |
| `golden.interior` | Erster Keller: Werkbank und Raummaschine, zwei Arbeiter, getragene Ladung, HUD mit Inventar |
| `golden.dark`, `golden.dark.seq` | Nachtwelt mit Flakturm, zwei Spielern, Lampen, Schatten, Effekten und Animation |

Die Aufnahmen liegen in `artifacts/visual-review/pass-6/golden.*`.

Befund beim Aufbau: Die Folgekamera mit zwei Spielern auf dem Dach zeigt angreifende
Bodenmaschinen gar nicht im Bild, nur die Randmarker. Die Maschinen feuern aus ihrer
Reichweite. Das gehört zu D01 und ist als strukturelle Kamerafrage dokumentiert.

## 8. Tests und Builds

Die vollständige Suite lief zweimal: nach Pass 6 und auf dem finalen Pass-7-Baum.
- Alle `tests/*_test.gd`, zuerst headless; die Fehlschläge erneut grafisch auf dem isolierten
  Display :78.
- Danach alle `tests/*_test.py` (ohne Live-Dienst) und die Lokalisierungsprüfung.
- Arbeitsbaum und Profile blieben durch die Suite unverändert (`--no-profile-save`, eigenes
  `XDG_DATA_HOME`).

| Teil | Ergebnis (finaler Lauf) |
|---|---|
| GDScript-Tests | 466 Tests; 440 bestehen headless, die übrigen laufen grafisch erneut |
| Grafisch erneut | Alle bestehen bis auf die bekannten Fälle (unten) und `room_lining_test` (siehe unten) |
| Python-Treiber | 68 Läufe, davon 3 ausgelassen (Live-Dienst und Geräte); alle bestehen bis auf die bekannten Fälle und `social_reconnect_test` (siehe unten) |
| Lokalisierung | `check_locales.py`: 0 Probleme |
| Netzwerktreiber (air, ground_infantry, combat_polish) | Bestehen, zuletzt auf dem Endstand. Sie schlagen bei jeder Engine-Warnung fehl und wurden nach jedem Pass erneut ausgeführt. |

Neue Fehler im finalen Lauf, beide geklärt:
- **`room_lining_test`:** Der Test erwartete „härtet 8.0 s“. Seit dem deutschen Dezimalkomma
  (7U, N28) zeigt der Prompt korrekt „8,0 s“. Die Erwartung beachtet jetzt die Sprache. Das
  ist eine bewusste Pin-Änderung. Ergebnis: 33/33.
- **`social_reconnect_test`:** Zeitüberschreitung (20 s) unter Suite-Last. Der Test läuft
  vollständig lokal mit eigenem Relay auf 127.0.0.1, ohne Live-Dienst. Er bestand danach zwei
  Läufe hintereinander.

Nach dem Suite-Lauf wurden noch zwei Dateien geändert:
- das Warm-up um die Ereignis-Atlanten (Abschnitt 6);
- die Basaltfugen in `terrain_strata.gdshader` (Abschnitt 10).

Danach liefen erneut: `render_warmup_test`, `terrain_strata_test` (56/56), die drei
Netzwerktreiber und die Leistungssonden. Alle bestehen.

Im Lauf nach Pass 6 fanden sich zwei neue Fehler. Beide sind behoben:
- **`beta_asset_audit_test`:** Pass 6S hatte `industrial_props.png`, `props/*.tres` und
  `industrial_crate.png` aus dem Export genommen, obwohl `level_prop.gd`, `supply_art.gd`
  und `world_texels.gd` sie als Rückfall noch laden. Die Ausschlüsse sind wieder entfernt.
  Exportierte Builds behalten damit ihren Rückfall (etwa +12 MB Paket). Im Spiel werden die
  Dateien weiter nur im Rückfall geladen. Der Audit-Test besteht mit 111/111.
- **`combat_art_batching_test`:** Die Provenienz des v1-Infanterieatlas war nach den
  Posenänderungen in `worker_pose_art.gd` veraltet. Der Atlas wurde auf :78 neu gebacken und
  ist byteidentisch. Nur der Hash wurde aktualisiert. Ergebnis: 15/15.

Bekannte Fehler, die vor diesen Passes schon bestanden und unverändert sind:
- **Abbruch nach Zeitlimit:** `distant_water_test`, `microphone_ui_test`.
- **Nur über den Launcher lauffähig (Exit 2 = nicht ausgeführt):** `audio_profile_isolation`,
  `content_startup_guard`, `fullscreen_handoff_preferences`, `menu_progression`,
  `microphone_routing`, `microphone_settings`, `social_default_startup`.
- **Python-Treiber, die einen Fenstermanager, Docker oder echte Netzwerkports brauchen:**
  `display_fullscreen_handoff`, `display_standalone`, `expedition_network`,
  `expedition_resume_network`, `network_relay_json`, `network_session_lobby`,
  `renderer_switch`, `social_container`.

Gameplay und Spielstände:
- Alle Änderungen sind Darstellung.
- Simulation, Netzwerkschema, Hitboxen, Schadensradien und Speicherformat sind unverändert.
  Die Gameplay-, Netzwerk- und Speichertests der Suite bestätigen das.
- Im Netzwerk wurde in diesen Passes nur der UI-Teil von `network_panel.gd` geändert.
- Ein echter Export-Build (`--export-release`) wurde nicht ausgeführt. Die Exportlisten prüft
  der Asset-Audit.

## 9. Unabhängiger Blind Review

Review 6 (nach Pass 6/6A) und Review 7 (nach Pass 7, Abschluss) liefen mit demselben Prompt
und denselben Kriterien wie R4 und R5:
- Zusätzlich mussten die Reviewer die fünf Golden-Reference-Aufnahmen ansehen.
- Beide kannten frühere Bewertungen, Berichte und Quellen nicht.
- Sie hatten jeweils nur den eigenen Render-Ordner.
- Die Ergebnisse liegen in `scratchpad/review6/scores.json` (63 Defekte: 22 major,
  41 minor) und `scratchpad/review7/scores.json` (50 Defekte). Blocker gab es in keinem.

| Bereich | R4 | R5 | R6 | **R7** | Δ R5 → R7 |
|---|---|---|---|---|---|
| Licht und Atmosphäre | 6,5 | 6,0 | 6,5 | **6,5** | +0,5 |
| VFX | 5,5 | 5,5 | 6,5 | **6,0** | +0,5 |
| Animation | 5,0 | 5,5 | 5,0 | **6,0** | +0,5 |
| UI und Typografie | 6,0 | 6,0 | 6,0 | **6,0** | ±0 |
| Stil und Schärfe | 5,0 | 5,0 | 5,5 | **5,5** | +0,5 |
| Lesbarkeit | 6,0 | 5,0 | 6,0 | **6,0** | +1,0 |
| **Mittel** | 5,6 | 5,5 | 5,9 | **6,0** | +0,5 |

Ehrliche Einordnung:
- Die Bewertungen steigen messbar, aber moderat. R7 urteilt: „gutes Indie-Spiel mit
  sichtbaren Kanten, unter AAA+“.
- Die Streuung der Reviewer liegt bei etwa ±0,5 bis 1. Die einzelnen Bereichsänderungen
  liegen damit nahe am Rauschen; die Richtung über drei Reviews ist aber konsistent.
- Am deutlichsten belegt sind die objektiven Verbesserungen. Pixeldichte, Defektzahl
  (63 → 50) und Frame-Hitches sind gemessen, nicht nur bewertet.

Was R7 im Vergleich zu R6 nicht mehr nennt:
- **Dichtebruch:** die Gegnerrümpfe als „glatte Renders“ (N01–N07) und die 1×-Innenwände.
- **Animation:**
  - Infanterie-Leiche als „Kiste“;
  - eingefrorene Idle-Schrittstellung;
  - statische Gegnergruppe;
  - fehlende Federung;
  - kein Mech-Ausholen.
- **Oberfläche:**
  - Panels durch Schwarz;
  - TEAMARBEIT über den Tags;
  - Dezimalpunkt;
  - Zählerwiderspruch 02/09 gegen 02/13;
  - winzige Schalter;
  - „?“-Platzhalter.

Was R7 neu oder weiterhin nennt:
- **Fichte bei 1×:** Vegetation ist noch nicht umgestellt.
- **Gegner kleben an der HUD-Leiste:** Kamerafrage, D01 und N44.
- **Treffer am Torpfosten in `combat.mg_sustained`:** Das kommt aus dem Capture-Staging.
- **Gleicher Bunker in allen Biomen** (D34).
- **Basalt-Fugengitter:** R7 nennt es als Major-Defekt. Behoben nach R7 (Abschnitt 10).
- **Blitz hebt das Bunkerinnere an:** R7 misst Luma 31 → 55, 6W hatte für den Raum keinen
  Anstieg gemessen. Das ist offen und widersprüchlich.
- **Trefferreaktionen nur als Silhouettenblitz:** Die Crew hat seit 6A-2 eine gezeichnete
  Trefferpose; R7 sieht in den Sequenzen vor allem den Blitz.
- **Entwickler-Changelog:** Das ist Inhalt des Projektinhabers.
- **Grüne Säule hinter P1 in `golden.interior`:** D30, blockiert.

Der Mittelwert steigt von 5,5 auf 5,9. Die Streuung des Reviewers liegt erfahrungsgemäß bei
etwa ±0,5 bis 1.

**Major-Defekte aus R5, die R6 nicht mehr nennt:**
- Flugzeuge vor Wald und Zügen getarnt (D02, D04)
- Wetter im Erdreich (D10, D11)
- Harte Bänder und Haarlinien im Gestein (D13, D18)
- Nicht ganzzahlige Porträts (D20)
- Flache Waffenpods (D25)
- Gesichtslose Infanterie (D28)
- LEBENSRAUM (D35)
- Vektor-Blitz (D36)
- Schockring (D37)
- Fehlendes Logo (D48)

**Minor-Defekte aus R5, die R6 nicht mehr nennt** (Auswahl): Asche wie Schnee (D15), Schild
als UI-Kasten (D27, jetzt nur „dünn“), Streupixel am Geschütz (D32), WELLE-Abstände (D51),
Kostensymbol (D53), Trennlinie (D54), Hilfe-Ausblendung (D56), Munitionskiste (D33),
Pressenmaterial (D31).

**Weiter genannt:**
- Gegnerklumpen mit gestapelten Balken (D03 → R6 N39, N40)
- Kampfkamera (D01 → N63)
- Steife Animation (D43–D46 → N29–N36; Treffer und Zusammenbruch sind jetzt gezeichnet, R6
  bemängelt Grundhaltung, Infanteriegang und Infanterieleiche)
- Rauch (D42 → N22, N23)
- Untergrund-Einheitlichkeit (D17, D19 → N18, N19)

**Neu in R6:**
- Gemischte Dichte jetzt nur noch bei den Gegnerrümpfen: Flugzeuge, Fahrzeuge, Panzer (N01,
  N03–N05, N07). Die Stationen nennt R6 ausdrücklich als sauber auf dem Raster.
- Nachtfiguren zu hell gegenüber dem Hintergrund (N14).
- Panels blenden durch Schwarz (N50). Das ist eine Nebenwirkung der Geisterbild-Korrektur
  D58/D59.
- TEAMARBEIT über den Spieler-Tags (N42).
- Dezimalpunkt im deutschen Kill-Popup (N28).
- Basalt-Kachelnähte (N12).
- Innenwände mit 1× (N08).

Nachgeprüft: Die Behauptung „Idle in 78 Frames identisch“ (N29) stimmt so nicht. Rucksack,
Zopf, Kopf und Hände wechseln sichtbar. Die Grundhaltung liest sich aber tatsächlich als
Schrittstellung.

## 10. Offene Qualitätsprobleme

Nach R7 behoben:
- **Basalt-Fugengitter:** Die Säulenfugen des Gesteinstyps „Basalt“ ersetzten den Stein
  durch flache, dunkle 1-Texel-Linien. In der Weitsicht ergab das ein durchgehendes
  Nahtgitter.
- **Änderung:** Die Fugen tönen den Stein jetzt nur noch (×0,84 längs, ×0,90 quer). Die
  Säulen bleiben über ihre Flächenwerte erkennbar.
- **Prüfung:** neu gerendert und verglichen; `terrain_strata_test` 56/56.

### Entscheidungen des Projektinhabers
1. **Kampfkamera (D01, N44, N63):**
   - Mit zwei Spielern auf dem Dach bleiben angreifende Bodenmaschinen außerhalb des Bildes.
   - Die HUD-Karten liegen auf der Bodenspur, über die Gegner laufen.
   - Abhilfe wäre eine geänderte Rahmung in `player_camera.gd`: Bedrohungen gewichten und
     einen Abstand zur HUD-Leiste halten.
   - Das ist eine Spielgefühl-Entscheidung und wurde nicht ohne Zustimmung geändert.
2. **`scripts/scenario_bunker.gd`:**
   - Betrifft den grünen Platzhalterkasten (D30) und die Raumbeschriftungen mit etwa 8 px
     (N61).
   - Die Bearbeitung wurde vom Berechtigungssystem abgelehnt.
   - Ein fertiger Ersatzschrank liegt bereit; Pfad in der Defektkarte.
3. **Büsten:** v3 (v1-Zeichnung mit 40 Farben) ist aktiv. v1 (detailreich) und v2 (aus der
   Sprite-Geometrie) bleiben zum Wechsel. Der Wechsel ist eine Zeile in
   `character_select_panel.gd`.
4. **Changelog:** Der spielerseitige Changelog ist Entwicklertext (R6, R7). Das ist Inhalt des
   Projektinhabers.

### Noch feiner als ein Welttexel
- Vegetation und Bäume (die Fichte in `golden.combat`)
- Walker-Beine als gedrehte Platten
- Variantenausrüstung von Demolisher und Repair-Crawler
- Mörserbeinschaft
- Ventilator- und Pressenrad
- `bunker_wall.png` der klassischen Karte
- In der Oberfläche: Material-Icons mit Faktor 1,2

### Licht und Effekte (R6/R7)
- Der Bunker ist in allen Biomen gleich gegradet, ohne Biom-Schlüssellicht oder Randlicht.
- Rauch ist unbeleuchtet und deckend (Cel-Ballen).
- Mündungsfeuer ist eine flache Form.
- Tracer sind 1–2 px breit.
- Explosionen haben wenige Ebenen.
- Der Blitz hebt laut R7 das Bunkerinnere an. Die Messung von 6W widerspricht; offen.
- Nachtfiguren sind heller als die Umgebung (R6). Das steht im Zielkonflikt mit der
  Lesbarkeit.
- Untergrund und untere Bildhälfte wirken leer und gleichförmig.

### Animation (R7)
- Infanterie-Gang wirkt laut R7 noch geschoben. Die Gehschlüssel sind in der
  66-ms-Abtastung kaum zu sehen.
- Infanterie-Tod springt in der Sequenz von Knien zu Liegen; der Abtastabstand verdeckt die
  Zwischenframes.
- Treffer an Gegnern lesen sich vor allem als Blitz.
- Die Leiter hat einen doppelten Frame.
- Tänze mit eigenen Armketten bekommen nur einen kleinen Hub.

### Oberfläche
- Expeditionskarte (D61) und Sieg- und Niederlagenschirm ohne eigene Illustration
- Kleiner, kontrastarmer Nebentext an einigen Stellen
- Unkonsistente Ortsnamen auf der Konvoikarte (R7)

### Technik
- Ein echter Export-Build (`--export-release` für Linux und Windows) wurde nicht ausgeführt.
- Eine Leistungsmessung auf einer ruhigen Maschine mit Release-Build steht aus. Die geteilte
  Maschine rauscht um ±10 ms.

## 11. Quality Gates

| # | Kriterium | Stand | Beleg |
|---|---|---|---|
| 1 | Alle 61 Defekte haben einen nachvollziehbaren Status | **erfüllt** | `DEFECT_MAP.md`: 38 behoben, 6 verbessert, 9 teilweise oder marginal, 2 kein Defekt im Spiel, 3 strukturell, 1 bewusst unverändert, 1 blockiert, 1 offen |
| 2 | Pass-6-Korrekturen umgesetzt und getestet | **erfüllt** | Abschnitte 1, 3 und 8 |
| 3 | Pass 6A enthält neue oder überarbeitete Art-Assets | **erfüllt** | Abschnitt 4: Infanterie, Pods, Waffen, Rümpfe, Crew-Ebenen, Büsten, Logo; alle mit Provenienz |
| 4 | Das Pixelraster ist konsistent | **weitgehend erfüllt** | Figuren, Gegner, Stationen, Requisiten, Kulissen, Wände, Zaun: kleinstes Pixel gleich dem Figurenpixel (Abschnitt 2). Ausnahmen in Abschnitt 10 (Vegetation, Walker-Beine, Variantenausrüstung, Räder) |
| 5 | UI ohne unbeabsichtigte Unschärfe | **weitgehend erfüllt** | Ganzzahlige Bildskalierung, MSDF-Text. Dokumentierte Ausnahmen: Welt unter 1 px je Einheit bei 960×600, Material-Icons mit 1,2× |
| 6 | Drei reproduzierbare Referenzszenen | **erfüllt** | `golden.*` in `tools/visual_review.py`, Abschnitt 7 |
| 7 | Erster Kill profiliert | **erfüllt und behoben** | Abschnitt 6: Kill-Sonde mit Phasenaufschlüsselung; GPU- und Software-Hitches beseitigt |
| 8 | Builds funktionieren weiterhin | **teilweise belegt** | Suite, Asset-Audit (Exportlisten) und Export-Abhängigkeiten bestehen; ein echter Export wurde nicht ausgeführt |
| 9 | Gameplay und Savegames unbeschädigt | **erfüllt** | Nur Darstellung; Gameplay-, Netzwerk- und Speichertests der Suite bestehen |
| 10 | Unabhängiger Blind Review durchgeführt | **erfüllt** | R6 und R7, Abschnitt 9 |

Laut Auftrag ist eine Review-Zahl allein kein Abnahmekriterium. Nach den Kriterien oben sind
die Passes 6/6A abgeschlossen. Offen bleiben zwei Punkte:
- Gate 4 hat dokumentierte Restausnahmen.
- Gate 8 braucht einen echten Export-Lauf.

Das Ziel „AAA+“ (R7: 6,0 von 10) ist nicht erreicht. Die größten verbleibenden Hebel sind
Inhalt und Spielgefühl, also Arbeit über einzelne Darstellungs-Passes hinaus:
- Kamerarahmung;
- biomspezifischer Bunker;
- Licht auf Figuren und Rauch;
- Vegetation im Raster;
- illustrierte Ergebnis- und Kartenansichten.
