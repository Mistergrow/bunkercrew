# Bunkercrew – Visual Style Bible

Verbindliche Regeln für alle Grafik, Animation, Effekte und Oberflächen von Bunkercrew.
Eine Regel gilt für neue Arbeit sofort. Wo der Bestand eine Regel noch verletzt, nennt
der Abschnitt „Stand“ die Abweichung und den zuständigen Pass (siehe
`reports/visual_quality/DEFECT_MAP.md`).

Technische Basis (Stand 2026-11-15, Git `d87ffb0` + Arbeitsbaum):

| Thema | Wert |
|---|---|
| Engine | Godot 4.7.2, Renderer `gl_compatibility` (Vulkan Forward Mobile als Option) |
| Design-Canvas | 1440 × 900, `canvas_items`-Stretch, Aspect `expand`, Minimum 960 × 600 |
| Stretch-Faktor | 1,2 bei 1920 × 1080 · 1,6 bei 2560 × 1440 und 3440 × 1440 · ≈0,67 bei 960 × 600 |
| Texturfilter | Projektweit `nearest` (`default_texture_filter=0`) |
| Weltkamera | `PlayerCamera` Zoom 0,45 … 2,5 (Standard 1,25); `PixelGrid` rastet auf ganze Gerätepixel je Welteinheit ein |
| Schrift | Bunkercrew Field (MSDF, Fließtext), Bunkercrew Signal (Bitmap, Überschriften ≥ 28 px) |

---

## 1. Das Pixelraster

**Ein Kunstpixel ist eine Welteinheit („Welttexel“).** Das gilt für alles, was im
Spielfeld steht oder sich darin bewegt: Figuren, Gegner, Fahrzeuge, Flugzeuge, Stationen,
Requisiten, Gelände, Erdschichten, Wetter, Effekte und die vorderen Parallaxebenen.

Warum diese Dichte: Figuren, Gelände, das Effektraster (`pixel_effect_grid`), die
Kamera-Einrastung (`pixel_grid.gd`) und die gebackenen Drehstellungen (RotSprite) arbeiten
bereits in ihr. Die feinere Dichte der generierten Stationsatlanten und der gemalten
Panoramen ist die Ausnahme. Alles auf die feinere Dichte zu heben, hieße, jede Figur und
jeden Effekt mindestens doppelt so groß neu zu zeichnen und die Spielgröße zu ändern. Das
ist ausdrücklich ausgeschlossen („nicht global vergrößern“).

Regeln:

1. **Spielfeldkunst wird in Welttexeln gebacken.** Hochaufgelöste Quellen (generierte
   Atlanten, Referenzen) bleiben als Quelle mit Provenienz erhalten und werden offline
   auf genau ein Texel je Welteinheit reduziert: flächengemittelt, auf eine Objektpalette
   quantisiert, verwaiste Pixel entfernt, 1-Texel-Kontur. Zur Laufzeit wird nie ein
   Quellbild herunterskaliert.
2. **Keine starre Rotation von Pixelsprites.** Drehungen kommen aus gebackenen
   Drehstellungen (`*_turns.png`) oder aus dem Texelblock-Shader (`actor_wreck`), der in
   Blöcken der eigenen Texelgröße rastert. Freie Rotation lässt Kanten flimmern.
3. **Keine Subpixel-Positionen für Spielfeldkunst.** Die Kamera rastet ein. Darstellungen
   folgen gerundeten Weltpositionen. Ruckeln durch Rundung wird über Animation gelöst,
   nicht über Subpixel.
4. **Effekte entstehen auf dem Welttexelraster.** Rauch, Feuer, Glut, Licht-Halos,
   Schockfronten und Blitze werden über `PixelEffectArt`/`pixel_effect_grid` gezeichnet.
   Linien sind gestufte Pixellinien, keine geglätteten Polylinien. Es gibt keine dünnen
   hellen Ringe, keine antialiasierten Kreise und keine halbtransparenten Fransen. Weiche
   Übergänge entstehen durch geordnetes Dithering in Texelblöcken.
5. **Hintergrundplatten in Welttexelgröße.** Gemalte Panoramen werden in Blöcken der
   aktuellen Gerätepixel je Welteinheit abgetastet, mit Vorfilterung gegen Aliasing. Ein
   Panoramapixel ist so nie kleiner als ein Figurenpixel. Ferne bleibt über Wert, Sättigung
   und Dunst lesbar, nicht über feinere Pixel.
6. **Unterhalb von 1 Gerätepixel je Welteinheit** (sehr weite Übersicht, Couch-Koop mit
   vier verstreuten Spielern) existiert kein sauberes Raster. Dort gilt die exakte
   Einpassung als dokumentierte Ausnahme. Die Kampfkamera soll diesen Bereich meiden
   (Abschnitt 3).

Stand (Pass 7D, 7A): Figuren, Gegner, Gelände und Effekte erfüllen Regel 1–4 weitgehend.
Stationen (Mischer samt Trommel, Ofen, Kern, Geschützlafetten), alle Requisiten des
Requisitenatlas samt Pulten und Werkbank, die Vorratskisten, die Felsfläche von Abbauzellen
und Aushüben sowie die Raummaschine Presse (aus Ofen- und Kernstahl zusammengesetzt) sind
offline in Welttexeln gebacken. Die Geschützrohre von Dachgeschütz und Flak drehen über
gebackene Drehstellungen im 2°-Raster, die Munitionskiste ist von Hand in Welttexeln
gezeichnet. Die Panoramaplatten werden bei ganzzahligen Gerätepixeln je Welteinheit in
Welttexelblöcken abgetastet (Regel 5); ihr Ursprung rastet in ganzen Blöcken im
Bildschirmraum ein, Größe und Wolkendrift in ganzen Welteinheiten. Seit Pass 7D sind auch
alle Gegnerrümpfe gebacken und werden aufrecht auf ganzen Welttexeln gezeichnet
(`WorldTexels.draw_stance`, `*_world.png` in `assets/enemies/`): die zwölf Flugzeuge in
Fluglagen je 0,03 rad über ±0,30 rad (Starrflügler ±0,42 rad, die Wende in drei gebackenen
Breiten), die Konvoi-Überflieger je Breite, die Chassis der zwölf Läufer je Zeichen- und
Elitegröße in Neigungsstellungen über ±0,30 rad und die drei Fahrzeuge samt Elite, deren
Nicken als Scherung ganzer Texelspalten erscheint. Laufwerk, Waffenpods, Bombenschacht,
Lampen und Markierungen liegen auf denselben Texeln; erst jenseits der gebackenen Lagen
(stürzende Wracks) dreht der Rest starr und das Wrackmaterial rastert ihn in Welttexeln.
Gebacken sind außerdem die Rückwände der Szenarioräume (`walls_world.png`), Tore samt
Torflügel, Türme mit Geschützkopf in 2°-Stellungen, Ruinen und die Hofmodule (Zaunfelder,
Pfosten, Platten, Poller, Leuchte, Servicekiste). Die Basaltsäulen der Erdschicht stehen in
unregelmäßigen Fugen. Seit Pass 7A ist auch die Infanterie in ihrer Zeichengröße
gebacken (Menschenfaktor 0,82 aus `EnemyCatalog.profile`, Spielgröße und Trefferflächen
unverändert): `tools/bake_infantry_world.py` reduziert das handgepixelte v2-Feldgepäck
auf 0,82 (Farbvotum in der Rollenpalette, Tintenkante, Kreuze, Ohrschale und Kinnriemen
von Hand nachgesetzt), dreht daraus die Schlüsselstellungen in Weltdichte und legt
Oberschenkel, Schienbeine, Arme, Stiefel und Handschuhe als Weltdichte-Sprites in
48 Richtungen an; der Rig zeichnet alles 1:1 auf ganzen Welttexeln (`*_world.png`,
`infantry_limb_index.gd`). Ebenso gebacken sind die Kanonen der Läufer in jeder
Zeichengröße samt Elite (`machine_weapons_world.png`, `tools/bake_machine_weapons_world.py`)
und die Fahrzeuggeschütze in 2°-Zielstellungen (`vehicle_guns_world.png` aus der
8-fach-Aufnahme `vehicle_guns_src.png`); die Stützbeine des Mörserträgers stehen auf ganzen
Texeln, die Schildblase ist Weltdichte-Kunst (`shield_bubble_world.png`). Abweichungen:
Feiner als ein Welttexel sind noch die Beine der Läufer (gedrehte Plattentexturen in
`visual_scale`), die Ausrüstung der Gegnervarianten, die Bunkerrückwand der klassischen
Karte und der Ausbaubuchten (`bunker_wall.png`), Biom-Requisiten und Vegetationsatlas
sowie das Flügelrad des Ventilators und das Schwungrad der Presse (gedrehte Polygone).
Behoben in Pass 6W und 6A-1:
- Blitz mit allen Ästen in 2-Texel-Zellen (`lightning_art.gd`).
- Schockringe entfernt.
- Regen- und Windstreifen als gestufte Texelläufe.
- Waffenpods, Mech-Geschütze und Infanteriewaffen mit gebackenen Zielstellungen statt
  starrer Rotation.

Methode (Regel 1): Die Quellatlanten bleiben unverändert im Projekt.
`tools/bake_world_density_art.py` reduziert jede gezeichnete Region auf genau ihre
Weltgröße (Flächenmittel in linearem Licht, Objektpalette, Waisenbereinigung,
1-Texel-Tintenkante `#151b1e`) und schreibt `*_world.png` mit `.source.json` (Quelle mit
SHA-256, Parameter, Regionen) sowie `scripts/world_texel_index.gd`. Die Aufträge stehen in
`tools/world_density_bake.json`. Gezeichnet wird über `WorldTexels` 1:1 auf ganzen
Welteinheiten. Eine neue Zeichengröße braucht einen Auftrag und einen neuen Bake;
`WorldTexels.missing` und `tests/world_texels_test.gd` melden Größen ohne Bake.
`tools/pixel_density_report.py` misst die wirksame Pixelgröße einer Aufnahme je Region
(Abschnitt 8).

## 2. Skalierung

### Spielwelt
- Die Kamera rastet auf ganze Gerätepixel je Welteinheit ein (`PixelGrid.settle_scale`).
  Bei 1080p sind das 1, 2 oder 3 Gerätepixel je Texel (`MAX_ZOOM` 2,5).
- Figuren werden nie einzeln skaliert. Größe und Lesbarkeit regelt die Kamera.

### Oberfläche
Die Oberfläche bleibt auf dem 1440 × 900-Canvas entworfen. Der Stretch-Faktor ist bei den
Zielauflösungen nicht ganzzahlig (1,2 und 1,6). Daher gilt diese Strategie:

1. **Pixelbilder** (Porträts, Icons, Sprites, Schlüsselsymbole) werden in
   **Gerätepixeln** auf ein ganzzahliges Vielfaches ihrer Quellpixel gelegt. Position und
   Größe werden im Bildschirmraum auf ganze Gerätepixel gerundet. Ein 50-px-Icon wird
   also 2×, 3× oder 4× gezeichnet, nie 2,4×. Die Helfer in `scripts/ui_art.gd`:

   | Helfer | Aufgabe |
   |---|---|
   | `UiArt.pixel_fit(node, source_px, room)` | Größtes ganzzahliges Vielfaches m ≥ 1, das in den Raum passt. Gemessen am echten Ausgabemaßstab einschließlich Viewport-Stretch und HUD-Skalierung. |
   | `UiArt.pixel_snap(node, at)` | Rundet einen Punkt auf ganze Gerätepixel. |
   | `UiArt.pixel_rect(...)` | Verbindet beides: Bild mittig, auf dem Boden des Raums stehend. |
   | `UiArt.pixel_glyph(...)` | Zeichnet kleine Pixel-Symbole (Zahnrad, Schloss, Haken) in ganzen Gerätepixel-Zellen. |

   Geprüft wird das von `tests/ui_pixel_fit_test.gd`. Unterhalb eines Gerätepixels je
   Quelltexel (960 × 600) gibt es keinen ganzzahligen Schritt. Dort bleibt die exakte
   Einpassung.
2. **Schrift:** Field wird als MSDF gerendert. Das hält die quadratischen Konturen auch
   bei 1,2 und 1,6 scharf, ohne Zeilen zu verlieren. Größen kommen aus den Tokens:

   | Token | Größe |
   |---|---|
   | Hilfslabels | 11–13 |
   | `TEXT_NOTE`-Untergrenze für Sätze | 15 |
   | Primärtext | 16 |
   | Menüaktionen | 28 |

   Signal (Bitmap) nur ab 28 px. Kein horizontales Strecken, keine Schein-Outlines.
3. **Rahmen und Linien** der Panels sind ganze Gerätepixel breit. Haarlinien laufen nie
   durch Textzeilen.
4. **Unterstützte Ausgaben:** 1920 × 1080 (Referenz), 2560 × 1440, 3440 × 1440 (zentrierter
   16:9-Sicherheitsbereich) und 960 × 600 (Minimum, lesbar, aber nicht pixelgenau).
5. **Keine bilineare Filterung** für Pixelkunst. Lineare Filterung ist nur für
   Lichtabfall-Texturen und Verläufe erlaubt.

Stand nach Pass 6U:
- Charakterauswahl, Lobby, Personalakte und Werkbank zeichnen ganzzahlig: Büste 4×,
  Figur 3×, Werkbank-Vorschau 5×, Reitersymbole 2× bei 1080p.
- Die Material-Icons (`UiArt.material`, 40/28 px) laufen noch mit 1,2×. Sie sind der
  nächste Kandidat.

## 3. Lesbarkeit

Priorität im Kampf, in dieser Reihenfolge:

1. **Silhouette** – jede Einheitenart ist an ihrem Umriss erkennbar, auch einfarbig.
2. **Kontrast** – Spielfeldfiguren heben sich im Tonwert vom Hintergrund ab.
   - Feinde: mittlere Werte mit hellerer, beleuchteter Oberkante und einem feindlichen
     Akzent (rote Sensoren und Lampen).
   - Hintergründe: zum Horizont hin flacher und dunstiger.
3. **Bewegungslesbarkeit** – Antizipation vor Angriffen, klare Trefferreaktionen.
4. **Waffenidentität** – jede Waffe hat eigene Form, Farbe und eigenes Timing für Mündung,
   Projektil und Einschlag.
5. **Details** zuletzt.

Regeln:
- **Keine künstlichen Outline- oder Glow-Effekte als Ersatz für eine unlesbare Figur.**
  Die 1-Texel-Tintenkante der Figuren ist Teil der gezeichneten Kunst und erlaubt.
  Farbige Umriss-Leuchtränder zur Rettung schlechter Sprites sind es nicht.
- **Spielerfarben bleiben unter jeder Beleuchtung erkennbar:**

  | Spieler | Farbe |
  |---|---|
  | P1 | `#dfb35e` |
  | P2 | `#8dc9c8` |
  | P3 | `#a9c98b` |
  | P4 | `#d7a0ba` |

  Nachtgrading dämpft die Umgebung, nicht Spielerfarbe und Kante.
- Schwebende Zahlen sind kurz, zusammengefasst und hängen am Ziel.
- **Kampfkamera:** Mindestens 2 Gerätepixel je Welttexel bei 1080p, solange die Spieler
  nah genug beieinander stehen. Wird die Koop-Einpassung weiter, wird das dokumentiert.
  Die Einpassung wird nicht durch Vergrößern der Figuren ausgeglichen (offen: D01).

## 4. Farbe

Die Palette hält gute bestehende Details. Sie wird nicht pauschal reduziert, sondern über
Rampen geführt.

| Bereich | Rampe / Schlüsselwerte | Regel |
|---|---|---|
| Bunkerinnenraum | Beton `#2b2e2a` → `#6f6a5c`, Stahl `STEEL #3b453d`, Kante `EDGE #63726c` | Warmes Natriumlicht von oben, kühlere Schatten |
| Raumlicht nach Tiefe | Natrium `#f2a64a` · Kaltweiß `#d8e6ee` · Ofen `#ff7a2e` · Grünweiß `#c8e8c0` | Eine Lichtfarbe je Raum, nicht gemischt |
| Erdschichten | Je Welt eine kalte oder warme Gesteinsrampe mit 5–6 Stufen, dunkelster Wert ≥ `#121416` | Struktur über Gesteinsart, keine harten Bänder |
| Oberfläche | Boden- und Vegetationsrampe der Welt, Kanten hell vom Himmel | Bodenlinie deutlich heller als die Erdschicht darunter |
| Himmel | Aus `backdrop_light_keys.gd` gemessen je Welt und Tageszeit | Bestimmt Licht- und Kantenfarbe der Figuren |
| Metall | Olivgrauer Stahl `#3b453d` → `#8a9088`, Messing `#c79a52`, Rost `#8a4a2a` | Licht von links oben |
| Beton | `#4a4c48` → `#9a978a` | Grob gesprenkelt, nie glatt |
| Waffen | Brüniert `#2c2f31` → `#6d7276`, Messing an Verschlüssen | Mündung stets mit hellem Kern |
| Gegner | Rümpfe Oliv und Braun `#59615e`/`#493c31` mit beleuchteter Oberkante, Akzent Rot `#c65b47` | Wertabstand ≥ 15 % zum Hintergrund dahinter |
| Explosion / Feuer | `#fff3c4` → `#ffc65a` → `#f59a3e` → `#d5602c` → `#a8402a`, Rauch `#4b4e51` | Weißer Kern nur 1–2 Frames |
| Flak | Kurzer Blitz, dann Kohle `#241e1a` → `#514c47` | Dunkler Puff, nie Feuerball-Optik |
| Kälte / Energie | `#f2fffd` → `#c4f4ff` → `#8fd8f0` → `#6f9fd8` → `#5a6cb0` | Schild und Elektrik, nie Feuer |
| UI | Fläche `#19221e`, erhöht `#33423a`, Text Elfenbein `#e0decb`, gedämpft `#b6b49f`, Akzent Amber `#d9ac60`, Fehler `#c65b47`, deaktiviert `#979b8b` | Amber bedeutet Auswahl und Fokus und nichts anderes |

## 5. Animation

- **Echte Frames** für Körperhandlungen:
  - Ruhe, Bewegung, Treffer, Angriff, Zusammenbruch und Tod bestehen aus gezeichneten
    oder gebackenen Pixel-Posen.
  - Shader dürfen tönen, blitzen und dithern, aber keinen Körper bewegen.
- **Timing:**
  - Körper 8–12 Bilder/s mit Haltebildern.
  - Effekte 12–24 Bilder/s.
  - Angriffe mit 2–3 Frames Antizipation.
  - Treffer: 1 Aufprallpose, 2–4 Erholungsframes und Rückstoß in Texeln.
  - Zusammenbruch: mindestens 3 Fallframes.
- **Bögen und Gewicht:** Kopf und Rumpf beschreiben Bögen. Rucksack, Gurt und Haare folgen
  1–2 Frames später (Follow-through).
- **Spieltempo hat Vorrang:** Keine Animation verzögert Eingabe, Treffer oder
  Reaktionszeiten. Antizipation steht nur dort, wo das Spiel ohnehin eine Vorwarnzeit hat
  (Gegner-Windup).
- **Übergänge:** Wechsel zwischen Zuständen über eine Zwischenpose, nie mit Sprung.

## 6. Effekte und Licht

- **Lichtquellen** (Lampen, Mündungen, Explosionen, Feuer, Blitz) beleuchten Boden, Figuren
  und Zaun in ihrer Reichweite.
- **Blitz:** Der Himmelsblitz endet an Dach und Gestein. Innenräume bekommen höchstens
  Streulicht durch Öffnungen.
- **Wetter** endet an der Bodenlinie und an geschlossenen Räumen, liegt auf dem Texelraster
  und bleibt bei Kamerabewegung stabil.
- **Mündungsfeuer, Projektil und Einschlag** sind je Waffenfamilie unterscheidbar. Einschläge
  sitzen auf Oberflächen und hinterlassen Spuren.
- **Telegraphen** (Angriffsvorbereitung) gehören zur Welt: Glühen an Waffe oder Mündung,
  Markierung am Boden. Debug-Formen wie flache Balken oder dünne Fadenkreuze sind nie
  finale Effekte.

## 7. Logo und Identität

- Das Logo ist ein eigenes, gezeichnetes Pixel-Lockup. Eine Standardschrift mit Schatten
  gilt nicht als Logo.
  - Thema: Bunker, Schicht, Industrie.
  - Lesbar ab 1× auf 160 px Breite.
  - Freigestellt (PNG mit Transparenz).
  - Je eine Variante für Titelbild und Kleinformat.
- Quelle und Provenienz liegen neben dem Asset. Bestehende Marken- und Projektdateien
  werden nicht ohne Vergleich überschrieben.

## 8. Prüfung

- **Golden Reference Scenes**
  - Shots: `golden.combat`, `golden.interior`, `golden.dark` in `tools/visual_review.py`.
  - Prüfpunkte in jeder Szene: Pixeldichte, Licht, Kontrast, Animation, UI-Skalierung,
    Materialkonsistenz und Lesbarkeit.
- **Pixeldichte messen:** Lauflängenanalyse gleicher Pixel in Ausschnitten. Figur,
  Station und Hintergrund müssen im selben Bild dieselbe Blockgröße zeigen.
- **Leistung:** `perf.*`-Sonden mit Mittelwert, P95, P99, Maximum, `spikes` und
  Erstabschuss-Zeit. Budget: höchstens +1 ms GPU-Mittel und +3 % Software je Pass.
- **Abnahme:** unabhängiger Blind Review mit denselben Kriterien wie R4 und R5. Eine Zahl
  allein ist kein Abnahmekriterium. Jeder der 61 Review-5-Defekte braucht einen
  nachvollziehbaren Status.
