# Bunkercrew · Changelog

Generated from [assets/releases/changelog.json](assets/releases/changelog.json). Use [the explicit milestone tool](docs/versioning.md); gameplay never changes the version.

## 0.1.0-beta · 2026-10-06

**Deutsch · Erste GitHub-Testbeta**

- Der geprüfte Entwicklungsstand erhält die öffentliche Kennung 0.1.0-beta und den GitHub-Tag v0.1.0-beta. Datierte Entwicklungseinträge und archivierte Pakete bleiben erhalten.
- Enthalten sind das adaptive Solo-Tutorial, die freigegrabene Werkbank mit Bildauswahl, passende Maschinenprodukte, lesbare Sprechblasen, korrigierte Waffenhände und räumliche Abprallklänge.
- Ubuntu- und Windows-Testpakete werden aus demselben eingefrorenen Quellstand gebaut; Netzwerkkennung bunkercrew-net-20 und Weltdaten-Version 5 bleiben kompatibel.
- Paket-, Musik-, Asset-, Tutorial- und Koopprüfungen werden für diese Exporte wiederholt. Windows unter Wine, menschliche Spieltests, native Windows-Hardware und Internet-Abnahmen sind im Prüfbericht getrennt ausgewiesen.

**English · First GitHub test beta**

- The reviewed development build receives public version 0.1.0-beta and GitHub tag v0.1.0-beta. Dated development entries and archived packages are retained.
- Includes adaptive solo guidance, picture-based crafting on the excavated floor, matching machine products, readable speech bubbles, corrected firearm grips and spatial ricochet cues.
- Ubuntu and Windows test packages are built from the same frozen source; network identity bunkercrew-net-20 and world revision 5 remain compatible.
- Package, music, asset, tutorial and co-op checks are repeated on these exports. Windows under Wine, human playtests, native Windows hardware and Internet acceptance are distinguished in the verification report.

## 0.1.12-beta.20261005 · 2026-10-05

**Deutsch · Geführtes Solo-Tutorial**

- Eine passive Anleitung im Solo-Modus erkennt echte Aktionen und führt durch Bewegung, Materialaufnahme und die erste Verteidigung, ohne Vorräte, Wellen oder Belohnungen zu verändern.
- Produktion, freigegrabene Werkbank, SAN-1, Abfahrt und Reifenreparatur werden passend zum erreichbaren Spielstand erklärt. Bei Gefahr haben Verteidigung und Versorgung Vorrang.
- F1 → Handbuch bietet Fortsetzen, Beenden und Wiederholen. Tutorial-Fortschritt und Einstellungen werden separat gespeichert und bleiben bei Szenenwechseln erhalten; im Koop bleibt die Anleitung ausgeblendet.
- Gezielte Prüfungen für Lernfortschritt, Speicherdateien, reale endliche Materialtransfers, Bedienung und Darstellung liegen mit Laufprotokollen unter artifacts/solo-tutorial-20261005. Menschliche Solo-/Koop-Spieltests bleiben eine eigene Abnahme.

**English · Guided solo tutorial**

- Passive solo guidance recognizes real actions and teaches movement, material collection and the first defense without changing supplies, waves or rewards.
- Production, the excavated workbench, SAN-1, departure and tire repair are explained when the actual game state allows them. Defense and medical care take priority during danger.
- F1 → Field manual offers resume, stop and repeat. Tutorial progress and preferences are saved separately and retained across scene changes; guidance stays hidden in co-op.
- Targeted checks for learning, saved records, real finite material transfers, controls and presentation are recorded with logs in artifacts/solo-tutorial-20261005. Human solo/co-op playtests remain a separate acceptance step.

## 0.1.11-beta.20261005 · 2026-10-05

**Deutsch · Abpraller auf Metall und Stein**

- Drei kurze Abprallgeräusche ergänzt: zwei Metallvarianten und ein Stein-/Beton-Abpraller. Quellen, Lizenzen und reproduzierbarer Audiogenerator sind erhalten.
- Ballistische Streifschüsse wählen den Klang nach Oberfläche und Trefferwinkel. Die Wiedergabe kommt räumlich vom Trefferpunkt; eigene Abstände zwischen Abprallern begrenzen Dauerfeuer.
- Regressionsprüfungen für echte Projektilkontakte sowie native PCM-Wiedergabe, Links-/Rechtsortung und Bus-Zuordnung ergänzt. Hörvorschau unter artifacts/ricochet-audio-20261005/index.html.

**English · Metal and stone ricochets**

- Added three short ricochet cues: two metal variants and one stone/concrete cue. Source provenance, licenses and the reproducible audio generator are preserved.
- Ballistic glancing contacts select their cue by surface and impact angle. Playback is spatially positioned at the contact; independent ricochet cooldowns keep sustained fire bounded.
- Added regression checks for actual projectile contacts and native PCM playback, left/right positioning and bus routing. Audio preview: artifacts/ricochet-audio-20261005/index.html.

## 0.1.10-beta.20261005 · 2026-10-05

**Deutsch · Sichtbare Hände am Gewehr**

- Alle acht Figuren verwenden gemeinsame Griffpunkte für Waffenpose und sichtbare Handschuhe. Zielen, Blickrichtung, Rückstoß und Trefferreaktion halten die Hände an den tatsächlichen Waffengriffen.
- Beim Schießen während des Hinkens bleiben beide Hände sichtbar vor der Waffe. Die verletzten Beine behalten ihren Gang; sitzende Bedien- und Nachladeposen verwenden weiter ihre eigenen Handkontakte.
- Regressions- und native Bildprüfungen kontrollieren alle acht Figuren in beiden Richtungen mit allen sechs Waffen. Vorbereitete Zustände und Nachweise liegen unter artifacts/weapon-grip-20261005.

**English · Visible hands on firearms**

- All eight characters share grip contacts for firearm poses and visible gloves. Aim, facing, recoil and damage reactions keep both hands on the actual gun grips.
- Both hands remain visible in front of the gun when firing while limping. Injured legs retain their gait; seated operation and reload poses continue to use their own hand contacts.
- Regression and native image checks cover all eight characters facing both ways with all six firearms. Prepared states and evidence are under artifacts/weapon-grip-20261005.

## 0.1.9-beta.20261005 · 2026-10-05

**Deutsch · Maschinenprodukte und lesbare Sprechblasen**

- Fertige Maschinenprodukte verwenden ihre tatsächlichen Gegenstandsbilder: der Betonmischer zeigt Betoneimer, der Ofen passende Metallbarren und Glas.
- Mit Q abgelegte Gegenstände bleiben kompakt. Ein gemeinsamer Shader lässt sie am festen Bodenkontakt nur um drei Prozent pulsieren; Physik, Mengen und laufende Zeichenabfragen bleiben unverändert.
- Comic-Sprechblasen erhalten größere Pixelschrift und passende Innenabstände; kleine Fenster behalten mindestens 14 Ausgabepixel Schrift. Wortgetreuer Chat, übersetzte Schnelltexte und Blockieren bleiben erhalten.
- Gezielte Produktions-, Abhol-, Ablege- und Darstellungsprüfungen sowie native Spielaufnahmen halten die Korrekturen fest. Nachweise liegen unter artifacts/content-architecture-20261005.

**English · Machine products and readable speech bubbles**

- Finished machine products use their actual item artwork: the concrete mixer shows concrete buckets and the furnace appropriate metal bars and glass.
- Items dropped with Q remain compact. One shared shader pulses them by only three percent around a fixed ground contact; physics, quantities and draw scheduling stay unchanged.
- Comic speech bubbles use larger pixel lettering and matching padding; small windows retain at least 14 output pixels of text. Literal chat, localized quick messages and blocking are preserved.
- Focused production, collection, drop and presentation regressions plus native game captures record the corrections. Evidence is under artifacts/content-architecture-20261005.

## 0.1.8-beta.20261005 · 2026-10-05

**Deutsch · Inhaltspakete, Gegenstandsbilder und Sprechblasen**

- Gemeinsame geprüfte Kataloge für Figuren, Gegenstände, Werkbankrezepte, Maschinen und Schauplätze; stabile Erweiterungs-IDs und einmaliges Laden.
- Koop prüft geladene Inhaltspakete vor dem Beitritt; fehlende oder abweichende verwendete Pakete sperren das Überschreiben von Kampagnenständen.
- Zusätzliche Baupläne bleiben per Bildlauf erreichbar. Gegenstandsbilder werden für Tragen, Symbole und Ablegen gemeinsam verwendet; Betoneimer am Boden besser erkennbar. Funde innerhalb von Zaunpfosten fallen auf den tatsächlichen Boden.
- Comic-Sprechblasen für Figurendialoge und öffentlichen Crew-Chat; Sprachzeichen über dem richtigen Sprecher. Private Nachrichten bleiben im Chat. Dicht beieinanderliegende Sprecher werden auch am Bildschirmrand entzerrt. Freie Texte bleiben wörtlich; Schnellnachrichten folgen der Sprache. Blockierte Chatblasen werden auch unter geöffneten Optionen entfernt.
- Autorentool, Paket-Vorabprüfung und isolierte Erweiterungsregressionen ergänzt; Prüfbelege unter artifacts/content-architecture-20261005.

**English · Content packs, item identity and speech bubbles**

- Shared validated catalogs for characters, items, workshop recipes, machines and environments; stable extension IDs and one-time loading.
- Co-op verifies loaded content packs before admission; missing or incompatible required packs prevent campaign save replacement.
- Additional recipes remain reachable in the picture strip. Carrying, icons and dropped items share item definitions; grounded concrete buckets are easier to recognize. Drops inside fence posts fall onto the actual floor.
- Comic speech bubbles for character dialogue and public crew chat; voice cues over the correct speaker. Private messages remain in chat. Nearby speakers are separated at screen edges as well. Free text stays literal; quick messages follow the selected language. Blocked chat bubbles are retired even beneath open Options.
- Added authoring tools, pack preflight and isolated extension regressions; validation evidence under artifacts/content-architecture-20261005.

## 0.1.7-beta.20261005 · 2026-10-05

**Deutsch · Werkstatt, Tanzposen und sichtbare Version**

- Die Werkbank steht neben der Munitionspresse in der ersten freigegrabenen Etage und wird erst nach dem tatsächlichen Aushub zugänglich.
- E / Enter / X öffnet ein kleines Fertigungsmenü mit fünf Bauplanbildern, Zutaten und persönlichem Auftragsstatus. Materialeinbau und Abholung werden ausdrücklich bestätigt; Teilzahlungen bleiben erhalten. Im Startraum stützt eine eigene Funkkonsole das Radio.
- Seitliche Tanzposen erhalten korrigierte Vorderarme und weichere Ellbogenübergänge. Branko tanzt seinen Stechschritt im Takt auf der Stelle; die Spielposition bleibt unverändert. Seitenansicht und eigene Bewegungen aller acht Figuren bleiben erhalten.
- Die Spielansicht zeigt ständig Version und Build. Im Hauptmenü und den Optionen öffnet Änderungen den lokalen deutschen oder englischen Verlauf; Fehlerberichte verwenden dieselbe öffentliche Buildkennung.
- Versionswechsel werden ausdrücklich mit übersetzten Meilensteinen durchgeführt und vor dem Paketbau geprüft. Dieser Entwicklungsstand ersetzt keine Internet-, Windows-, Leistungs- oder menschliche Spielabnahme; vorhandene Beta-Archive bleiben unverändert.

**English · Workshop, dance poses and visible version**

- The workbench is beside the ammunition press on the first excavated floor and opens only after its earth has been cleared.
- E / Enter / X opens a compact crafting menu with five blueprint pictures, ingredients and personal order status. Confirm material supply and collection explicitly; partial payments remain. A separate radio console supports the radio in the starting room.
- Side-view dances receive corrected front arms and smoother elbow transitions. Branko dances his Goose Step in time without moving his game position. Side views and the distinct movements of all eight characters are preserved.
- The game view always shows the version and build. Changes in the main menu and Options opens the local German or English history; error reports use the same public build identity.
- Version changes use explicit translated milestones and are checked before packaging. This development milestone does not replace Internet, Windows, performance or human play acceptance; existing beta archives remain unchanged.

## 0.1.6-beta.20261003 · 2026-10-03

**Deutsch · Bisherige Beta-Basis**

- Der bisherige Entwicklungsstand verwendet die Version 0.1.6-beta.20261003.
- Archivierte Ubuntu- und Windows-Pakete dieser Version bleiben erhalten.

**English · Previous beta baseline**

- The previous development baseline uses version 0.1.6-beta.20261003.
- Archived Ubuntu and Windows packages of this version are preserved.
