# Geschlossene Bunkercrew-Testrunde

Stand: 4. Oktober 2026. Diese Anleitung prüft den vorhandenen Inhalt der sechs P1-Bereiche. Grafik, Musikbalance und Inhalt bleiben eingefroren. Die menschliche Testrunde ist noch nicht durchgeführt: Alle Fälle in der [Ergebnisvorlage](beta-playtest-template.json) beginnen mit `NOT_RUN`. Automatisierte Regressionen, vorbereitete Siege, Wine und synthetische Controller-/Mikrofonsignale zählen nicht als menschliche Abnahme.

## Vorbereitung und Ergebnisführung

- Nur den ausdrücklich benannten, vollständig entpackten Ubuntu-/Windows-Kandidaten verwenden. `BUILD_INFO.json`, Paketname und SHA256 aus dem zugehörigen Manifest in die Vorlage übernehmen; alte R5c-Pakete enthalten nicht automatisch die späteren P1-Änderungen. Auf Windows die tatsächliche EXE nativ starten, auf Linux `Bunkercrew.x86_64`; Godot und das Quellprojekt dürfen dafür nicht nötig sein.
- Ein eigenes Testprofil verwenden und persönliche Spielstände erhalten. Unter Linux lassen sich Daten, Konfiguration und Cache über eigene `XDG_DATA_HOME`, `XDG_CONFIG_HOME` und `XDG_CACHE_HOME` trennen; unter Windows eignet sich ein eigener Testbenutzer. Das Profil über die gesamte Kampagne behalten. Nicht `--no-profile-save` verwenden, wenn gerade Speichern, Wiederaufnahme oder Freischaltung geprüft wird.
- Betriebssystem, CPU/GPU/RAM, Anzeigegröße, Renderer, Sprache, Eingabegeräte und Audioausgabe protokollieren. Keine Namen, IPs, Raumcodes, Freundesgeheimnisse oder Zugangsdaten eintragen. Raumcodes nur unmittelbar mit den Mitspielern teilen. Bildschirmfotos und eigene Kommentare vor Weitergabe prüfen.
- Pro Fall tatsächliche Schritte, erwartetes und beobachtetes Verhalten, Dauer und Belege getrennt eintragen. `PASS` setzt eine tatsächlich erfüllte Erwartung voraus; `FAIL` braucht einen konkreten Befund; fehlende Geräte oder Voraussetzungen ergeben `BLOCKED` mit Grund. Ungespielte Fälle bleiben `NOT_RUN`. Bei Versionswechsel eine neue Vorlagenkopie beginnen.
- Einstieg zunächst einem neuen Spieler überlassen: Das eingebaute Handbuch darf benutzt werden, der Beobachter erklärt nichts. Erst danach die Referenzschritte unten zur Ursachenprüfung heranziehen. Kampagnen werden ohne veränderte Positionen, Inventare, Siege, XP oder Wellenstände gespielt. Eine separate Laborvorschau darf als solche bewertet werden und ersetzt keine Freischaltungsprüfung.

## Tatsächliche Standardsteuerung

Die Anzeigen im Feldhandbuch (`F1`) und am aktuellen Ziel sind maßgeblich. Tastennamen sind physische Standardtasten; ein anders beschrifteter Controller kann andere Symbole zeigen.

| Aktion | Eigene Figur: Tastatur/Maus | Eigene Figur: Pad |
| --- | --- | --- |
| Laufen / Leiter | A D / W S | Linker Stick |
| Springen | Leertaste | A |
| Interaktion | E antippen oder halten | X antippen oder halten |
| Mitgeführtes Material wählen | Tab | LB |
| Anderes nahes Ziel / freier Sitz | F | RB |
| Ein Stück / Stapel ablegen | Q antippen / halten | B antippen / halten |
| Zielen / feuern | Maus / linke Maustaste | Rechter Stick / RT |
| Nachladen / Reserve an Munitionskiste auffüllen | R | Y |
| Handwaffe wechseln | C | Rechten Stick drücken |
| Werkbank: Fertigungsmenü öffnen; Bauplanbild wählen und bestätigen | E antippen; Maus oder Pfeile / Enter | X antippen; Steuerkreuz / A |
| Ausgewähltes Material in passender Vorratskiste einlagern | G halten | Linken Stick halten |
| Ausgewähltes Baugerät aufstellen | B | Steuerkreuz rechts |
| Personal / Technikbaum | P / T | Steuerkreuz oben / Back |
| Pause / Menü zurück / bestätigen | Esc / Esc / Enter | Start / B / A |

Solo und online steuert der erste Controller die eigene Figur. Im lokalen Koop bleibt Tastatur/Maus bei Spieler 1; der erste Pad steuert Spieler 2, weitere Pads Spieler 3 und 4. Die zweite Tastaturbelegung lautet Pfeile, rechte Shift, Enter, Backspace, Entf, Einfg, Bild ab, Num 0, Num *, Num . und rechte Strg; Pos1/Ende zielen. Diese Zuordnung mit echten Geräten prüfen, einschließlich Ab-/Anstecken und Wechsel zwischen Maus und Pad.

Weitere Wege: `F1` Handbuch, `F4` Optionen, `F3` reduzierte Effekte, `F5` Neustartbestätigung, `F6` Erfolge, `F7` Freunde. `J` bzw. Pause → Logbuch öffnet das Solo-Logbuch. `M` öffnet nach gesicherter Mission die Konvoikarte. `N` beginnt nur in einer freigegebenen Baupause die nächste Warnphase, online nur beim Gastgeber. Mausrad zoomt. `F11` oder Alt+Enter wechselt Vollbild im eigenen Fenster; bei eingebetteter Editor-Ausführung das eigene Fenster aus dem Hauptmenü starten. Online öffnet Enter den Crew-Chat; `V` halten spricht nur bei aktivierter Sprachfunktion, gültiger Verbindung und ohne Texteingabe.

## 1 · Einstieg und erste Verteidigung

Je ein neuer Spieler pro Sprache startet Solo und erklärt danach seinen nächsten Schritt. Tastatur/Maus und physischer Pad werden getrennt beurteilt. Notieren: erster Handbuchaufruf, übersehene Zielhinweise, Irrwege, Verständnis von Antippen/Halten, erste wirksame Verteidigung und Zeitpunkt der ersten selbst gelösten Reifenpanne.

Referenz für den Beobachter, aus Feldhandbuch und bestehenden Rezepten:

1. Sand und Erz aus den vorhandenen Dachkisten oder Adern mit Interaktion halten holen. Ein normaler neuer Bunker hat 12 Sand, 12 Erz, 8 Stahl, 8 Beton und 18 Munitionskisten; Bauart Stahlwerk gibt zusätzlich 6 Stahl und 2 Beton. Wiederbesuche dürfen diese Startbestände nicht erneut verschenken.
2. Eine Charge einfüllen: **2 Sand + 1 Bindemittel → 2 Beton**, Grundzeit 5 s; **2 Erz oder ersatzweise 2 Schrott → 2 Stahl**, Grundzeit 6 s. Bindemittel stammt aus dem endlichen Mischervorrat. Fertiges Produkt mit Halten abholen; es blockiert bis dahin eine neue Charge.
3. Im Story-Modus die markierte Frontmauer bauen: kostenlose Schalung, **2 Stahl + 2 Beton**, anschließend **18 s** aushärten lassen. Vorhandene Bunkertore schützen bereits. Bei Mittellage beide Bodenfronten besetzen. Forschung kann bestehende Zeiten verändern; den tatsächlich gewählten Stand notieren.
4. Geschütz durch Antippen besetzen, zielen, feuern und nachladen. Getragene Munitionskisten beliefern Geschütze; R/Y an einem Vorrat füllt die persönliche Reserve und verbraucht echte Kisten. Nachladen allein erzeugt keine Patronen.
5. Pflichtauftrag und Funkablauf zuerst erfüllen; dann eine reguläre Angriffswelle abwehren und bergen. Eine Hauptbunkerschicht umfasst 20 Wellen. Frühe Versorgungsgalerie: ab Welle 1 insgesamt **4 Beton + 3 Stahl einschließlich Stützen**; ihre Munitionspresse macht **2 Stahl → 2 Munitionskisten**, Grundzeit 6 s.

Materialwahl, Zielwechsel, Einlagern und eine blockierte/fertige Anlage müssen ohne fremde Erklärung verständlich werden. Keine kostenlosen Zusatzvorräte als Testhilfe einsetzen.

## 2 · Oberfläche, Geräte und Sprachen

Die Vorlage enthält Linux/Windows × DE/EN × 960×600, 1440×900, 1920×1080 und 2560×1440. Falls eine Anzeigegröße nicht verfügbar ist, den Fall als `BLOCKED` erhalten. Jede Matrixzeile durchläuft Hauptmenü, Schauplatz-/Bauart-/Figurenwahl, Optionen mit allen vorhandenen Seiten, Handbuch, Lobby, Freunde/Chat, Pause, Neustartbestätigung und Fehlerbericht.

Nur Maus, anschließend nur Tastatur und anschließend nur physischer Pad: Auswahl sichtbar, Text vollständig, Scrollbereich erreichbar, deaktivierte Aktionen erklärt, Zurück eindeutig. Tab/Shift+Tab und Steuerkreuz durch alle sichtbaren Aktionen führen; Lesen/Scrollen darf den Fokus nicht verschlucken. Nach einem Unterdialog kehrt der Fokus zum Öffner zurück. Esc/B schließt zuerst den inneren Dialog. Mit getragenem Material dürfen B, Enter, T, P, F5 oder Bewegungstasten unter einem Modal weder Rohstoffe abwerfen noch darunter kämpfen, bauen oder neustarten.

In der echten Lobby Spieleraktionen, Freundesanfrage auf beiden Seiten, Stumm/Blockieren, Textchat und Schnelltexte prüfen. Texteingabe sperrt Bewegung/Schießen; eine aktive Eingabe darf V nicht aufnehmen. Eindeutige Verbindungsfehler, Abbrechen und erneutes Beitreten beurteilen. Gastgeber/Gast-Rollen und deaktivierte Start-/Forschungsaktionen prüfen. Online ist eine lokale Optionsansicht nicht automatisch eine gemeinsame Pause; der Gastgeber koordiniert diese. Zusätzlich native Windows-/Linux-Hosts über zwei echte Internetanschlüsse wechseln und LAN-Suche zwischen zwei physischen Geräten prüfen; [Koop-Anleitung](beta-coop-test.md) verwenden.

## 3 · Reguläre Story, Balance und Reifenrollen

Die Solo-Story umfasst dieselben zwölf Kampagnenorte wie der Koop-Fortschritt. Lokale Überlebendenbegegnungen und Solo-Logbuch sind Solo-Funktionen. Pro Sprache je eine vollständige Solo-Story und eine Koop-Kampagne mit echter Steuerung, endlichen Vorräten und regulär erreichten Siegen spielen. Hauptweg: Aschewerk → Verlassener Hafen → Basaltbruch → Verwachsenes Stahlwerk → Frostbahnhof → Eisenschlucht → Versunkenes Kraftwerk → Gewitterpass. Hinzu kommen die vier Sicherungsziele Sturmstaudamm, Schwefelraffinerie, Radarhöhen und Verschüttete Großfabrik. Die Vorlage enthält jeden Ort einzeln; Nebenrouten kosten zusammen 19 Bergungsdaten, getrennt von Technikpunkten.

Pro Ort Dauer, Versuche, gelesenen Pflichtauftrag, Signalprüfung, Unwetter-/Versorgungshinweise, Material-/Munitionsstände vor und nach der Mission sowie nachvollziehbare Dialoganlässe notieren. Zwischenhalt, Ladezustand, Abfahrt, Einsteigen, Reise und Ankunft regulär ausführen. Forschung, persönliche Erfahrung und Freischaltungen nach einem echten Programmneustart prüfen. Mindestens eine tatsächliche Niederlage mit Retry erleben; gespeicherter Missionsbeginn darf keine zusätzlichen Rohstoffe, Munition oder Belohnungen erzeugen. Einen echten Koop-Stand offline fortsetzen: nur die eigene Figur, keine zweite ehemalige Koop-Figur.

Für die verpasste Aufnahme **Oskar im Basaltbruch** zunächst bewusst auslassen und den Ort regulär sichern. Später auf der Einsatzkarte den gesicherten Ort als sicheren Wiederbesuch wählen, **2 Beton tatsächlich transportieren**, vor Ort sprechen und Crew aufnehmen. Es entsteht keine neue Verteidigungsschicht; für einen bereits gesicherten Ort ist keine zweite Drei-Wellen-Abwehr erforderlich. Danach erneut besuchen und Programm neu starten: dauerhafte Freischaltung, kein zweiter Materialpreis, keine neuen Dachvorräte/XP/Bauplan-/Zwischenhaltbelohnungen. Pflichtabschluss bleibt von optionaler Aufnahme getrennt.

Reifenpanne mindestens einmal auf der Hafenroute solo und einmal im Koop natürlich erreichen. Fahrer, Schütze und Mitfahrer müssen vorher sichtbar einsteigen; Fahrer lenkt links/rechts, Mitfahrer zielen/feuern/nachladen mit eigenen endlichen Vorräten. Bei der Panne übernimmt genau ein Spieler das Hinterrad mit E/X halten: **Wagenheber 2,0 s → Rad abnehmen 1,8 s → Ersatzrad 2,0 s → drei Schrauben → senken 1,5 s**. Schrauben im grünen Fenster antippen oder je Schraube 2,6 s halten. Loslassen, Weggehen, falsches Timing und Rollenwechsel prüfen; die übrige Crew verteidigt Mechaniker/Fahrzeug. Solo müssen die vorhandenen bewaffneten Begleiter tatsächlich Deckung geben; SAN-1 kann den Reifen übernehmen, solange niemand medizinische Hilfe braucht. Knall, platten Reifen, Werkzeug, Schüsse, Sitz-/Fahrzeugbewegungen und anschließendes Wieder-Einsteigen/Weiterfahren beobachten. SAN-1 besitzt endliche Heilvorräte; Transport und Bergung müssen im Technikbaum regulär freigeschaltet sein.

## 4 · Musik, Tanz und tatsächliche Audioeffekte

Ein frisches Profil startet mit **50 % Musik, Effekten, Sprache und Partnerlautstärke**. Das ist die vereinbarte Mischung mit unterschiedlich abgestimmten internen Kanalpegeln, keine Forderung nach gleicher hörbarer Lautstärke. Alte Profile dürfen gespeicherte eigene Werte behalten. Standards nicht pauschal auf 100 % setzen; Ausgangsgerät und eigene Änderungen notieren.

Pro Sprache mindestens **30 Minuten** bewusst hören: Menü, ruhiger Materialtransport, Sammeln, Warnphase, Gefecht, Sprache, Sieg/Niederlage, Reise und Rückkehr. Lautstärkespitzen, Verständlichkeit, Ducking-Rückkehr, Wiederholungen und Stilwechsel mit Zeitpunkt und Situation festhalten. Kopfhörer und Lautsprecher sowie ein echtes Ausgabegerät-Wechsel-/Neustart-Szenario prüfen. Physische Mikrofone nur ausdrücklich aktivieren: Push-to-talk, Loslassen, Texteingabe, Fensterfokusverlust, Stumm und Dialoge dürfen keine ungewollte Aufnahme erzeugen. Voice- und Spielsprache getrennt beurteilen.

Bei normalem Spielzoom **Mara, Branko, Ivo, Nora, Levin, Selma, Oskar und Rika** in der vorhandenen Seitenansicht prüfen. Drei gemeinsame Moves sind ab Stufe 1 verfügbar; fünf eigene je Figur folgen auf **Charakterstufen 2, 4, 6, 8, 10**. Die Vorlage listet alle 64 Figur/Move-Kombinationen, darunter 40 einmalige Moves und die drei gemeinsamen Moves bei jeder Figur. Freischaltungen regulär erreichen und nach Neustart wiederfinden; eine Laborvorschau allein gilt nicht als Freischaltung.

Hörbaren Kick mit Kopf-/Schulter-/Beinakzent vergleichen: ein melodischer Einstieg ohne Kick darf keinen erfundenen Volltanz erzeugen. Beginn, Phasenwechsel, Tempowechsel und Automatikwechsel nach 16 Beats müssen flüssig wirken; bei mehreren erlernten Moves keine unmittelbare Wiederholung. Mit vollen Armen nur sichtbares Kopfnicken bei unverändertem Griff/Ladung. Laufen, Springen, Klettern, Interaktion, Schuss, Treffer und reale nahe Gegner/Projektile übernehmen sofort. Ruhige Laborfiguren dürfen durch Gegner in der getrennten Spielwelt nicht blockiert werden. SAN-1s fünf erforschbare Bunkerdance-Stufen zusätzlich bei echten Leerlauf-/Heil-/Logistikwechseln beobachten.

Das **Musik-Labor** unter Optionen → Takt bietet Thema, Stil, BPM, Seed, Musikspannung und Tanzprofile; dort gibt es aktuell **keinen eigenen Synthese-FX-Regler**. Die eingebauten Stilrichtungen Minimal Techno, Schranz, Hip-Hop und Breakbeat getrennt hören; Laboränderungen und ausdrücklich angewendete Einstellungen auseinanderhalten. Die vorhandenen [Dry/Wet-Hörproben](../artifacts/p1-beta-readiness-20261004/music-dance/index.html) vergleichen den echten Syntheseparameter bei identischer Musik. Diese Hörbewertung ist eine gesonderte Aufgabe; sie verändert keine Spielbusse.

**Godot-Audiobus-FX** sind eine andere Prüfung: nur für Tester mit dem passenden Quellstand und Godot 4.7.2, in einer eigenen Projektkopie mit eigenem Audio-Layout. Im eigenen laufenden Spiel auf Music oder SFX einen deutlich wahrnehmbaren Effekt, etwa PitchShift, mit vernünftigem Pegel aktivieren/deaktivieren; selben Klang vergleichen, anschließend Teständerungen verwerfen. Pegelregler, Bus-Effektparameter und Syntheseeffekte getrennt protokollieren. Ein ausgelieferter Desktop-Kandidat braucht keinen Godot-Audioeditor. Nicht verfügbare Editorprüfung bleibt `BLOCKED`, kein erfundener Laborregler und kein Schluss aus einem ausgeschlagenen Pegelmesser.

## 5 · Paketpflege und zwei Stunden Betrieb

Beide Plattformen aus vollständigem Paket starten; Musik, Sprachen, alle freigeschalteten Figuren, Reisen, Freunde/Chat und Optionen auch außerhalb des Quellverzeichnisses öffnen. Fehlende Bibliothek, Asset, Lizenz-/Herkunftsbeleg oder abweichende Build-Identität konkret melden. Alte Archive nicht mit dem neuen Kandidaten vermischen. Fenster/Vollbild, Auflösungs-/Rendererwechsel mit gegebenenfalls gefordertem Neustart und anschließender Wiederaufnahme prüfen; echtes Windows bleibt eine eigene Zeile.

Auf Linux und Windows je **mindestens zwei Stunden** echten Betrieb beobachten: mehrere Wellen, Bauen/Bergen, eingesammelte und liegengebliebene Beute, Welt-/Reisewechsel und wiederholte Menü-/Lobby-/Chatwechsel. Alle 15 Minuten Uhrzeit, verfügbare Speicherbelegung aus einem OS-Werkzeug, beobachtete Frameprobleme, Rohstoffmengen und auffällige Audio-/Verbindungszustände notieren. Nach Neustart erhaltene Mengen prüfen; bloßes Stehen im Labor zählt nicht als Dauerbetrieb. Laufzeit, Geräte und konkurrierende Programme offen dokumentieren; diese Beobachtung ersetzt keine isolierte FPS-Abnahme.

## 6 · Fehlerbericht und Meldung eines Befunds

**F4 / Optionen → Fehlerbericht** öffnet die lokale Vorschau. `Aktualisieren` sammelt den aktuellen technischen Stand; `Bericht kopieren` schreibt erst auf Knopfdruck in die Zwischenablage; `Bericht speichern` speichert erst auf Knopfdruck unter `user://reports`. Die angezeigte Speicherstelle verwenden. Es erfolgt **kein automatischer Upload**.

Der JSON-Bericht enthält freigegebene technische Werte: Version/Netzwerkstand/Weltrevision, Engine, tatsächlich verwendeten Renderer/Treiber, Plattform, DE/EN, UTC-Zeit, ausgewählten Story-/Freie-Schicht-Modus, getrennten Kampagnenstatus, Schauplatz/Kapitel/Phase/Reisestufe, Rollen-/Verbindungszustand, numerische Einstellungen und einen auf **128 Zustandsänderungen** begrenzten Verlauf. Er enthält keine rohen Engine-Logs, Profile, Namen, Identitäten, Chats, Raumcodes, IPs oder Freundesgeheimnisse. Er ersetzt die selbst formulierten Reproduktionsschritte nicht.

Im Menü ohne Spieler und in pausiertem Spiel öffnen, Refresh/Tab/Shift+Tab/Steuerkreuz/Scrollen/Zurück prüfen und Copy/Save lokal kontrollieren. Story, freie Schicht trotz aktivem Kampagnencontainer, Reise und tatsächliche fehlgeschlagene Reise sollen korrekt benannt sein. Einen lokalen Speicherfehler nur in einem vom Betreuer vorbereiteten, nicht beschreibbaren Testziel prüfen: verständliche Fehlermeldung, weiterhin bedienbar, kein behaupteter Speichererfolg. Persönliche Speicherrechte nicht verändern.

Jeder Befund erhält in der Vorlage eine eigene Kennung, genaue Schritte, Erwartung, tatsächliches Verhalten, Häufigkeit und optional den lokal gespeicherten Bericht als Datei. Keine Codes/IPs/Geheimnisse in diese Beschreibung oder Fotos übernehmen. Bericht und Kommentare erst nach eigener Prüfung bewusst an das Team weitergeben. Ein Absturz ohne nutzbaren Bericht wird trotzdem mit den letzten Schritten, Paketidentität und Zeitpunkt gemeldet; es wird kein ausgefüllter Bericht erfunden.

## Quellen und Abnahme

Bedienung und Rezepte: [Feldhandbuch](../scripts/help_manual_catalog.gd), [InputMap](../scripts/input_setup.gd), [aktive Zielhinweise](../scripts/input_labels.gd), [Balance](../scripts/config.gd), [Kampagnenorte](../scripts/campaign_catalog.gd), [Reifenablauf](../scripts/convoy_journey.gd), [Tanzfreischaltungen](../scripts/worker_dance_catalog.gd), [Audio-Standards](../scripts/audio_defaults.gd), [technischer Bericht](../scripts/support_diagnostics.gd). Automatische Belege stehen separat im [Beta-Plan](beta-0.5-plan.md); sie befüllen keine menschlichen Ergebniszeilen.

Vor einer Freigabe wertet das Team offene `FAIL`, `BLOCKED` und `NOT_RUN` aus, reproduziert bestätigte Fehler und wiederholt die betroffenen Fälle auf dem korrigierten Kandidaten. Dieses Kit enthält keine bereits erteilte Beta-0.5-Freigabe.
