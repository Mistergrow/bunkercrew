# Versionen und Änderungsverlauf

`application/config/version` in `project.godot` bleibt die einzige Quelle für die aktuelle Spielversion. Hauptmenü, Spielansicht und Fehlerbericht zeigen diese Version. Exportierte Ubuntu- und Windows-Paare zeigen zusätzlich die ersten zwölf Zeichen ihres gemeinsamen `source_sha256` aus `BUILD_INFO.json`; Quellläufe tragen `Build dev`. Die Netzwerkkennung beschreibt getrennt die Transportkompatibilität und wird durch einen gewöhnlichen Versionswechsel nicht verändert.

Ein abgeschlossener Meilenstein erhält ausdrücklich eine neue Beta-Version. Das geschieht nach dem Inhalts- und Prüfabschluss, niemals beim Starten des Spiels. Ein Versionswechsel veröffentlicht kein Paket und bestätigt keine Internet-, Leistungs- oder menschliche Spielabnahme. Vorhandene Paketordner bleiben erhalten.

Die erste GitHub-Testausgabe verwendet **0.1.0-beta** im Spiel und den Tag **v0.1.0-beta**. Die bisherigen datierten Entwicklungsstände, etwa `0.1.12-beta.20261005`, bleiben unverändert im Verlauf. Das Versionswerkzeug unterscheidet diese beiden Reihen: öffentliche Betas stehen zuerst, darunter folgt die erhaltene Entwicklungsreihe. Das `v` gehört zum GitHub-Tag, nicht zur Projektversion.

```bash
python tools/bump_version.py --bump patch --date 2026-10-06 \
  --title-de "Werkstatt und Tanzposen" --title-en "Workshop and dance poses" \
  --change-de "Beschreibe hier eine abgeschlossene Verbesserung." \
  --change-en "Describe a completed improvement here." --dry-run
# Nach Prüfung desselben konkreten Eintrags --dry-run entfernen.
python tools/bump_version.py --check
```

`--bump minor` und `--bump major` setzen untergeordnete Zahlen zurück. Nach dem Beginn der öffentlichen Reihe führt `--bump patch` beispielsweise von `0.1.0-beta` zu `0.1.1-beta`; das Veröffentlichungsdatum bleibt im Changelog. Die frühere Entwicklungsreihe verwendet weiter `MAJOR.MINOR.PATCH-beta.YYYYMMDD`. Titel und jeder Verbesserungspunkt benötigen Deutsch und Englisch. Unvollständige, doppelte, rückläufige oder widersprüchliche Einträge werden vor dem Schreiben abgewiesen.

Nur der ausdrückliche einmalige Übergang erlaubt eine kleinere Zahl beim Beginn der öffentlichen Reihe:

```bash
python tools/bump_version.py --start-public-series --to 0.1.0-beta --date 2026-10-06 \
  --title-de "Erste GitHub-Testbeta" --title-en "First GitHub test beta" \
  --change-de "Der geprüfte Entwicklungsstand erhält eine öffentliche Beta-Kennung." \
  --change-en "The reviewed development build receives a public beta identity." --dry-run
```

Dieser Übergang wurde für `v0.1.0-beta` durchgeführt. Bei folgenden Änderungen normale Versionssteigerungen verwenden. Alte Paketordner werden weder umbenannt noch überschrieben.

Das Werkzeug aktualisiert zusammen die Projektversion, Windows-Datei-/Produktmetadaten, versionierte Beta-Exportpfade, `assets/releases/changelog.json` und den daraus erzeugten `CHANGELOG.md`. Ein fehlgeschlagener Schreibvorgang stellt den bisherigen Stand wieder her. Die lokale Ansicht **Änderungen** im Hauptmenü und in den Optionen verwendet dieselben übersetzten Daten; sie benötigt weder Internet noch ein Profil.

`tools/build_beta.py` prüft Versions- und Changelog-Konsistenz vor dem Export und nimmt den Changelog in die Paketdokumentation auf. `BUILD_INFO.json` wird weiterhin aus dem eingefrorenen Quellmanifest erstellt. Die Versionsanzeige liest begrenzte, geprüfte öffentliche Builddaten und gibt keine Freunde, Raumcodes, Adressen oder Profilgeheimnisse weiter.
