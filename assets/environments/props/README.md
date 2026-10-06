# Animierte Vegetation und Außenrequisiten

Die sechs Baumgrafiken wurden mit dem eingebauten Werkzeug `image_gen.imagegen`
erzeugt. Die vollständigen Prompts und ursprünglichen Ausgabepfade stehen in
[prompts.json](prompts.json) und [prompts_variants.json](prompts_variants.json).
Alle PNG-Dateien sind unveränderte Originale mit
echtem Alphakanal:

- `deciduous_tree.png`: Laubbaum für Stahlwerk und Kraftwerk.
- `conifer_tree.png`: Nadelbaum für Frostbahnhof und Gewitterpass.
- `dead_tree.png`: kahler Baum für die trockenen und industriellen Schauplätze.
- `oak_tree.png`: breite, knorrige Eiche für Stahlwerk und Kraftwerk.
- `birch_tree.png`: schlanke Birke für gemischte Laubbestände sowie Sektor und Hafen.
- `spruce_tree.png`: dichtere, asymmetrische Fichte für Frostbahnhof und Gewitterpass.

Godot verwendet zugeschnittene UV-Bereiche aus
`scripts/scenario_prop_catalog.gd`; die Quelldateien werden dabei nicht verändert.
Die UV-Angaben schließen fast unsichtbare Randpixel aus und vermeiden eine
Texturrücklesung beim Betreten eines Schauplatzes.

Die Stammfüße wurden auf den Originalbildern (1254 × 1254 Pixel) vermessen:

| Grafik | Stammanker im Original |
| --- | --- |
| Laubbaum | `(623, 1050)` |
| Nadelbaum | `(614, 1135)` |
| Kahler Baum | `(839, 1030)` |
| Eiche | `(704, 1172)` |
| Birke | `(716, 1228)` |
| Fichte | `(627, 1201)` |

Diese Punkte liegen im Spiel auf dem tatsächlichen Boden bei `y = 430`.
Das Netz richtet sich am Stammanker aus; der Shader schneidet die darunter
liegenden, frei gezeichneten Wurzelspitzen an der Bodenlinie ab. Die ursprünglichen
PNG-Dateien und ihre Herkunft bleiben erhalten. Auch entfernte Bäume bleiben
innerhalb der vorhandenen Bodenfläche. Asymmetrische Kronen und ihr maximaler
Bewegungsbereich halten Abstand zu beiden Bunkertüren.

## Blatt- und Nadelursprünge

`tools/generate_tree_metadata.py` liest die Originalbilder mit Pillow und NumPy
und schreibt ausschließlich `tree_metadata.json`. Die Bilder werden nicht
verändert; ihre SHA-256-Prüfsummen stehen in den Metadaten. Die Datei wird
ausdrücklich mit dem Spiel exportiert.

Jede Art besitzt 192 Ursprünge über 155–192 belegte Kronenzellen. Die Auswahl
verwendet deckende grüne Blatt-/Nadelpixel, Abstand zum transparenten Rand und
einen ausgeschlossenen, vermessenen Stammkorridor. Kahle Bäume verwenden
stattdessen Rindenflächen oberhalb des unteren Stamms. Familien heißen
`broadleaf`, `conifer` und `dead`; Effekte hängen dadurch nicht an einzelnen
Dateinamen. In Frostwelten tragen Koniferen Schnee, sonst Nadeln.

Die Metadaten werden einmal geladen. `canopy_point()` interpoliert dieselben
zwölf Meshbänder, Dreiecke und Windterme wie der Baumshader einschließlich
Spiegelung und Skalierung. Dadurch entstehen Blätter an der tatsächlich
bewegten Krone. Im laufenden Spiel werden keine Bildpixel zurückgelesen.

```bash
python3 tools/generate_tree_metadata.py --check
```

## Animation und Platzierung

`scripts/scenario_props.gd` zeichnet die Bäume auf Netzen mit zwölf waagerechten
Abschnitten. `shaders/scenario_prop_wind.gdshader` hält die Wurzelzone fest und
biegt Stamm und Krone abhängig von Höhe, Windstärke und Standort. Jeder Baum
erhält eine deterministische Phase, Geschwindigkeit und Steifigkeit; eine Böe
wandert durch den Bestand, feinere Zweige bewegen sich zusätzlich. Gespiegelte
Varianten behalten dieselbe Windrichtung. Texturen und Netze werden geteilt;
eigene Materialien halten die individuellen Bewegungswerte. Sichtbare Bäume
erhalten höchstens 30 Materialaktualisierungen pro Sekunde, unter F3 höchstens zwölf.
Stehende Bäume und fallende Originalkronen empfangen das örtliche Feuerlicht
über die normale Canvas-Lichtmaske 1.

Gräser, Schilf, Efeu, Seile, Warnbänder, Windsäcke, Signale, Rohre und Ventilatoren
entstehen aus der bearbeitbaren Pixelgeometrie in
`scripts/scenario_prop_art.gd`. Tragende Teile bleiben fest; bewegliche Teile
werden getrennt animiert. Die Zusammenstellung und Farben stehen je Schauplatz
im Katalog.

Die Gegenstände sind Kulisse und besitzen keine Kollision oder Bedienaktion.
`scenery_damage.gd` verwaltet dennoch replizierte Treffer-, Brand- und
Bruchzustände. Getroffene Bäume reagieren oberhalb der feststehenden Wurzel;
verkohlte Originale werden dunkler. Gebrochene Originale verschwinden, während
`scenery_prop_effects.gd` fallende Fragmente, Stümpfe und Wracks darstellt.
Ihre Platzierung berücksichtigt beide Bunkerkanten. Gleiche Szenariooptionen
erzeugen dieselbe Anordnung auf Host und Gast. Eine gemeinsame Spielpause stoppt
die Bewegung. F3 reduziert Wind, Zeichentakt und optionale Details; Elemente
außerhalb des sichtbaren Bereichs werden ausgeblendet.

## Prüfen

```bash
godot --path . --script tests/scenario_props_test.gd -- --no-profile-save
godot --path . --script tests/scenario_props_preview.gd -- --no-profile-save
```

Die Vorschau verwendet die echte Hauptszene bei normaler Kamera. Nur die Wellen
sind für die Aufnahme angehalten. Bilder und Clips liegen unter
`artifacts/scenery-props/`.
