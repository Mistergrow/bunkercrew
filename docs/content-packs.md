# Inhaltspakete und Erweiterungen

Die Spieldefinitionen stehen in `assets/content/core/`. `assets/content/packs.json`
legt fest, welche Pakete beim nächsten Start geladen werden. Der Kernschauplatz-
Katalog bleibt in `assets/environments/catalog.json`. Die bestehenden acht Figuren,
13 Schauplätze, 13 Gegenstände, fünf Werkbank- und fünf Maschinenrezepte behalten
ihre IDs, Werte und bisherigen Spielstände.

`ContentRegistry` liest und prüft diese Dateien einmal. Die Fachkataloge benutzen
Indizes und unveränderliche Daten. Es gibt keine Dateisuche oder JSON-Neuladung
pro Inventarabfrage, Figur oder Frame und keine Registrierung mitten in einer Runde.
`WorkerVisual` teilt außerdem die eingelesenen Animations- und Rüstungsmetadaten.

## Ein Paket anlegen

```bash
python3 tools/content_packs.py scaffold studio.expansion1
```

Das erzeugt ein **nicht aktiviertes Autorengerüst** in
`assets/content/studio.expansion1/`: Figur, Gegenstand, Herstellungsrezept,
Paketbeschreibung und DE/EN-Texte. Die Beispielbilder und Figurenprofile sind
vorhandene Ressourcen; sie sind beim Veröffentlichen durch geprüfte passende
Inhalte zu ersetzen. Es wird kein neuer Beispielgegenstand ins normale Spiel eingefügt.

Nach der Bearbeitung den Pfad `res://assets/content/studio.expansion1/pack.json`
zur `packs`-Liste hinzufügen. `scaffold ... --enable` erledigt das beim Anlegen
ausdrücklich mit. Nach dem Import prüfen:

```bash
godot --headless --path . --editor --import --quit
python3 tools/content_packs.py validate --report artifacts/content-preflight.json
python3 tools/verify_content_extension.py --output artifacts/content-extension-check --capture
```

Der letzte Befehl installiert ausschließlich in einer privaten Projektkopie ein
Prüfpaket mit neunter Figur, neuem Material, sechstem Bauplan und zusätzlichem
Schauplatz. Er prüft tatsächliches Aufheben, Ablegen, Lagertransfer, bezahlte
Herstellung, Figurenprofile, Netzwerkzustand und Kampagnenschutz. Auf einem
grafischen Bildschirm entstehen zusätzlich native Spielaufnahmen. Spielerprofile
und die aktive Paketliste bleiben unverändert.

## Paketformat

```json
{
  "schema": 1,
  "id": "studio.expansion1",
  "version": "1",
  "requires": [{"id": "bunkercrew.core", "version": "1"}],
  "catalogs": {
    "items": {
      "path": "res://assets/content/studio.expansion1/items.json",
      "field": "items"
    }
  },
  "translations": {
    "de": {"Neues Bauteil": "Neues Bauteil"},
    "en": {"Neues Bauteil": "New component"}
  }
}
```

Jede Katalogdatei enthält das benannte Array, zum Beispiel `{"items": [...]}`.
Abhängigkeiten werden vor ihrem Paket geladen und verlangen die angegebene
Paketversion. Neue IDs verwenden `paket_id:inhalt_id`, beispielsweise
`studio.expansion1:component`. Bestehende IDs werden weder ersetzt noch umbenannt.
Ein fehlerhaftes Paket wird als Ganzes abgewiesen; seine gültigen Teile werden
nicht versehentlich separat aktiviert. Die Installation startet bei Diagnosefehlern
mit einer verständlichen Fehlermeldung statt mit einer teilweise gebauten Welt.

| Katalog | Zuständigkeit und benötigte Angaben |
| --- | --- |
| `characters` / `CharacterCatalog` | ID, Name/Beschreibung, LP, Tempo, Schaden, Arbeit, Kapazität, Farbe; explizite `visual_profile`, `motion_profile`, `dance_profile`, `voice_profile`. Optional Nachlade-/Versorgungsmultiplikatoren und Freischaltort. |
| `items` / `ItemCatalog` | ID, Name, Farbe, Inventarreihenfolge, Lager-/Reisezulassung und Bild. Dasselbe Bild definiert Symbol, getragenen Gegenstand und Bodenfund; `world_region`, `world_width`, `pour_region` steuern passende Varianten. |
| `workshop_recipes` / `CraftingCatalog` | Stabile ID, Ausgabegegenstand in `kind`, Kosten, Zeit, Menge, Text und Auswahlbild. Bestehende Rüstungsrezepte behalten ihre Marker und Regeln. |
| `station_recipes` / `CraftingCatalog` | Gemeinsame Quelle der fünf vorhandenen Maschinenrezepte, einschließlich alternativer Eingaben. Ein neuer Maschinentyp benötigt zusätzlich seinen geprüften Laufzeit- und Zeichenadapter. |
| `environments` / `ScenarioCatalog` | Panorama, Maße, Namen, Farben und vorhandenes Wetterprofil; drei explizite `layer_paths` oder ein passendes bestehendes `background_profile`. Neue Kampagnenaufträge benötigen weiterhin ihre Auftragslogik. |

Bilder verwenden `{"texture":"res://assets/...png","region":[x,y,w,h]}`;
Gegenstandsbilder enthalten zusätzlich `"kind":"sprite"`. Regionen werden gegen
die tatsächlichen Bildmaße geprüft. Paketressourcen liegen unter `res://assets/`;
relative Pfadtraversierung, Benutzerdateien, unbekannte Renderer, ungültige Zahlen,
fehlende Bilder und nicht registrierte Materialverweise werden abgewiesen.
Nicht unterstützte Inhaltsfelder sind Fehler und verschwinden nicht still.

Für Figuren sind die acht vollständig animierten, vertonten Profile ausdrücklich
verfügbar. Die vier Profile dürfen unabhängig gewählt werden. Eine neue Figur
behält dabei ihre eigene Identität, Werte, Freischaltungen und Tanzeinstellungen.
Eine vollständig neue Silhouette, Stimme oder Choreografie benötigt die dazugehörigen
authentischen Art-/Audioressourcen und einen zusätzlichen Profiladapter; ein fehlendes
Profil wird nicht automatisch durch Mara ersetzt. Neue freigeschaltete Figuren
verändern weder die vier Spielerplätze noch die ursprünglichen Sammelerfolge.

Eine Figur mit `unlocked:true` ist sofort wählbar. `unlock_site` allein beschreibt
einen gesperrten Fund und seine Hilfe; eine konkrete Rettungsaktion muss
`CrewRoster.unlock(id)` ausführen. Soll ein bereits vom Kampagnensystem ausgelöstes
Sichern eines Ortes die Figur automatisch freigeben, wird zusätzlich
`legacy_auto_unlock:true` gesetzt. Die bestehenden Oskar-/Rika-Begegnungen behalten
ihre ausdrückliche Rettung. Ein lediglich benannter neuer Ort erzeugt keinen neuen
Auftrag und keine erfundene Rettungssequenz.

Neue Materialrezepte produzieren den registrierten Gegenstand mit der definierten
Menge. Die drei tatsächlich implementierten Feldverteidigungen bleiben ausdrücklich
einsetzbare Typen. Ein unbekanntes Objekt wird nicht als Falle oder Geschütz behandelt.
Die Werkbank kann weitere bebilderte Baupläne durch einen fokussierbaren Bildlauf
anzeigen. Historische bezahlte Aufträge mit `1:0` bleiben gültig; neue Aufträge
benutzen stabile Rezept-IDs und werden semantisch vor der Netzwerkübernahme geprüft.

## Koop, Spielstände und Pakete

Hello und Welcome vergleichen einen SHA256-Fingerabdruck der tatsächlich geladenen
Definitionen und Paketversionen **vor** der Spielerzulassung. Unterschiedliche Pakete,
abweichende Werte oder ein älteres Spiel ohne diese Prüfung liefern eine klare
Meldung. Sprache, Quelldokumentation und Betriebssystem verändern diesen Fingerabdruck
nicht. Der vollständige Build-Hash bleibt ein gesonderter Herkunftsnachweis.
Relay-Steuernachrichten und die bestehende Relay-Version bleiben unverändert;
die Inhaltsprüfung liegt in den Spielnachrichten für Direkt- und Relay-Verbindungen.

Kampagnen speichern Anforderungen für tatsächlich verwendete Erweiterungen.
Fehlende IDs oder falsche Paketversionen werden vor der Wiederaufnahme, einem
Backup-Fallback und dem Schreiben erkannt. Der betroffene Spielstand bleibt erhalten.
Nicht geladene Figurenfreischaltungen und Tanzeinstellungen werden beim Speichern
ebenfalls bewahrt. Zusätzliche unbenutzte Pakete sperren einen Kernspielstand nicht.

Der Beta-Builder prüft aktivierte Pakete vor dem Export und schreibt
`content_sha256` sowie die Paket-IDs/Versionen in `BUILD_INFO.json`.
Alle Desktop-Presets enthalten die Inhaltsmanifeste und Kataloge im Spielpaket;
`beta_asset_export_test.gd` lädt sie auch aus einem tatsächlichen Export.
Ressourcenherkunft und Lizenzen bleiben neben den Assets und in den Paketnachweisen.

Diese Schnittstelle betrifft mit dem Spiel gebündelte, vor dem Start festgelegte
Inhalte. Installation über einen Shop, Download während einer Runde und beliebiger
fremder Skriptcode sind keine Funktionen dieses Formats.
