# Grafiken für Zwischensequenzen

Die bestehenden Draufsichtgrafiken für Luftkontakt behalten ihre ursprünglichen
Quellenangaben in den benachbarten `.source.json`-Dateien.

`storm_charred_tree_v1.png` ergänzt die vorhandene Unwetter-Reiseszene. Das
eingebaute Werkzeug `image_gen.imagegen` hat den vorhandenen kahlen Baum in
eine verkohlte Variante überführt. Die PNG-Ausgabe wurde unverändert kopiert;
sie besitzt echte Transparenz und dieselben 1254 × 1254 Quelldimensionen.
Der vollständige Prompt, Referenzhash und Ausgabehash stehen in
[storm_charred_tree_v1.source.json](storm_charred_tree_v1.source.json).

Der vorhandene Stammanker und UV-Ausschnitt halten beide Zustände am gleichen
Bodenpunkt. `scripts/travel_cinematic_art.gd` zeigt die Brandspur nach dem Blitz;
Wind, Feuer, Rauch und Beleuchtung bleiben separate Animationen der Engine.
Die unbeschädigte Originalgrafik wird weiterhin verwendet und bleibt erhalten.

Die neue Grafik wurde für die Verwendung und Verteilung mit Bunkercrew erstellt.
Sie verändert keine Lizenz bestehender Grafiken, des Spielcodes oder der
separat lizenzierten Musik-Engine.
