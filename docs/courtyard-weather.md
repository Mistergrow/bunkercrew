# Hof und Wetter: Umsetzung und Prüfung

Der Hof schließt die Fläche zwischen Bunker und äußerem Tor. Durchgehende Gitterfelder teilen sich einzelne Pfosten; die Endfelder werden zugeschnitten statt auseinandergerückt. Schienen und Pflaster verbinden beide Enden. Arbeitsleuchte, Servicekoffer und Kabelstation geben der Fläche einen Zweck. Die hintere Umzäunung liegt hinter den Figuren; das Außentor bleibt die tatsächlich angreifbare Barriere.

## Spielregeln und Darstellung

- Jeder aktive Bodenangriffsweg beginnt mit einem Feldzaun mit 120 LP und zwei unbebauten Anlagenplätzen. Mittellagen haben zwei Höfe; der klassische Bunker einen auf der Ostseite.
- Bodengegner greifen zuerst den geschlossenen äußeren Zaun und anschließend das vorhandene Bunkertor an. Eigene Figuren und SAN-1 öffnen das äußere Tor; in dieser Zeit ist der Durchgang auch für Gegner offen. Reparaturen und Ausbauten kosten weiterhin die angegebenen Materialien.
- Startzustände entstehen nur beim Aufbau einer neuen Welt. Übertragene zerstörte, beschädigte, unbebaute oder ausgebaute Zustände ersetzen diese Werte. Wiederverbindung belebt keinen Zaun wieder. Reguläre Missionsneustarts bauen die Infrastruktur wie bisher mit der Welt neu auf.
- Bei der Abfahrt verschwinden Hof und Außenanlagen aus der Straßenansicht. Ihre gespeicherten Zustände bleiben für Snapshots erhalten, während Simulation, Interaktion, Zielauswahl und Kollision deaktiviert sind. Ein späteres Synchronisieren darf die alte Kollision nicht wieder einschalten.
- Die Hofzeichnung benötigt keine laufende CPU- oder Physikfunktion. Alle Felder verwenden denselben Atlas und dasselbe Material; die Leuchten teilen sich ein kleines Shader-Material. Nearest-Sampling erhält die Pixelkanten. Pfosten, Tor und Pflaster folgen der tatsächlichen Bodenhöhe.

Der neue [Atlas](../assets/courtyard/modules_v1.png) wurde mit dem eingebauten Bildgenerator anhand des vorhandenen Bunkercrew-Atlas erstellt. [Vollständiger Prompt, Herkunft und Hash](../assets/courtyard/modules_v1.source.json) bleiben neben dem unveränderten PNG erhalten. Vorhandenes Servicegerät stammt aus `assets/perimeter/components_v3.png`.

## Technische Grundlage

Die [Godot-Dokumentation zur GPU-Optimierung](https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html) behandelt Materialwechsel, Texturatlanten, Batching und die Kosten überlappender transparenter Flächen. Daraus folgt für diese Szene: gemeinsame Materialien, kompakte Atlasregionen und statische Hofzeichnung. Der sichtbare Schauer bleibt begrenzt; Figuren und Oberflächen werden weiterhin mit ihren tatsächlichen Konturen geprüft.

Der [NVIDIA Rain SDK Whitepaper](https://developer.download.nvidia.com/SDK/10.5/direct3d/Source/rain/doc/RainSDKWhitePaper.pdf) beschreibt kamerabezogene Regenpartikel und gesonderte Verdeckungsprüfungen für eine 3D-DX10-Pipeline. Das ist eine Referenz für räumlich begrenzte Wetterdarstellung, keine unmittelbar verwendbare Implementierung für Godots 2D-Compatibility-Renderer. Die [Godot-Dokumentation zu 2D-Partikeln](https://docs.godotengine.org/en/stable/tutorials/2d/particle_systems_2d.html) beschreibt die verfügbaren CPU-/GPU-Systeme. Hier bleibt die vorhandene Kontaktlogik erhalten, damit Dächer, bewegte Körper und konkrete Oberflächen nicht durch eine rein optische Partikelumstellung verloren gehen.

Die [MultiMesh-Dokumentation](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html) erklärt den Vorteil vieler Instanzen und die gemeinsame Sichtbarkeitsgrenze eines MultiMesh. Für die wenigen statischen Hofmodule ist eine neue Instanzpipeline nicht erforderlich. Die vorliegende Änderung verbessert die gemessenen Abfragen und Konturen der bestehenden Wetterdarstellung.

Als visuelle Referenzen wurden die [Industrieszenen des Pixel-Art-Autors Brainwash Gang](https://brainwash-gang.itch.io/pixel-art-texturing-brushes-for-brainwashing) und [offizielle Metal-Slug-6-Aufnahmen](https://www.snk-corp.co.jp/official/ms6/screenshot/index.html) betrachtet. Übernommen wurde das Gestaltungsprinzip zusammenhängender Begrenzungen und lesbarer Arbeitsflächen. Die Assets selbst stammen aus Bunkercrew und seinem neuen Generatorauftrag; fremde Referenzbilder werden nicht als Spielressourcen eingebunden.

## Verbesserte Wetterabfragen

- Physikabfragen verwenden wiederverwendbare Parameterobjekte je Welt. Terrain-, Figuren- und ausdrücklich ausgeschlossene Kontakte haben eigene Objekte; ausgeschlossene RIDs dürfen nicht in eine spätere normale Abfrage geraten.
- Unveränderte Requisitenkonturen behalten ihre bereits transformierten Segmente. Änderung von Transform, Form, Material, Sichtbarkeit oder Besitzer führt zu aktuellen Konturen. Entfernte und verdeckte Objekte bleiben nicht dauerhaft im Cache.
- Gegner werden zunächst gegen die Hüllen ihrer tatsächlich gezeichneten, aktuell bewegten Körper-, Waffen- und Antriebsteile geprüft. Exakte Alpha-Konturen werden erst bei einem möglichen Kontakt erzeugt. Die Grenzen müssen auch Rückstoß, Spiegelung, Rotation und Skalierung vollständig abdecken.
- Die bereits vorhandene bedarfsgesteuerte Figuren-Zellstruktur bleibt erhalten. Eine untersuchte alternative Gitterstruktur wurde wegen einer gemessenen Verschlechterung verworfen.
- Die Zell-Durchquerung stoppt eine Achse, sobald deren Zielzelle erreicht ist. Zuvor konnten fast identische Fließkomma-Zeitpunkte an einer Ecke zu einem Überschreiten und einer Endlosschleife führen. Die Regression prüft 24 spiegelbare Grenzfälle für beide Zellgrößen.
- Auf dem sichtbaren Hofpflaster melden Bodenkontakte Beton. Außerhalb bleiben Erde, Bunkerdächer, Mine und andere Materialien unverändert. Diese Zuordnung wird aus den aktuellen Hofkoordinaten abgeleitet und gilt auch nach einer Transformation oder dem Ausblenden des Hofs.

## Nachweise

Die [Hofgalerie](../artifacts/courtyard-art-20261004/index.html) enthält tatsächliche Nah-, Weit-, Spiegel- und Torzustandsaufnahmen. Der [gemeinsame Prüfbericht](../artifacts/courtyard-weather-20261004/verification.md) hält den abschließenden Quellstand, Verhaltensprüfungen, lokale Direkt-/Relay-Läufe und die tatsächliche Paketprüfung fest. Die Wetterprofile liegen unter `artifacts/courtyard-weather-20261005/weather/`.

CPU-Kosten und gerenderte Bildrate werden getrennt ausgewiesen. Die Leistungsmessungen laufen bei 1080p mit vier Figuren und 40 Gegnern; Standard- und reduzierte Effekte werden getrennt erfasst. Beide Vergleichsvarianten verwenden denselben eingefrorenen Hof-/Gameplaystand. Die Vergleichsbasis enthält allein die notwendige Korrektur der sonst endlos laufenden Zell-Durchquerung, keine der neuen Cache-, Hüllen- oder Parameteroptimierungen. Der unkorrigierte Fehler und verworfene Versuche bleiben als Diagnosebelege erhalten.

Eine konkurrierende GPU-Rechenlast verhindert hier eine belastbare FPS-Abnahme auf einem Mindestgerät. Lokale ENet-/WebSocket-Prüfungen belegen weder zwei getrennte Internetanschlüsse noch einen Windows-/TLS-Relay-Abnahmelauf. Diese Änderung wird nicht als neue öffentliche Beta veröffentlicht.
