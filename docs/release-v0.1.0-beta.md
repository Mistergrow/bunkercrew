# Bunkercrew v0.1.0-beta

## Deutsch

Bunkercrew verbindet Bunkerbau, Rohstoffarbeit und Verteidigung mit einer Solo-Geschichte und Koop für bis zu vier Spieler. Diese Beta eröffnet die öffentliche Versionsreihe; die bisherigen Entwicklungsstände und ihr Changelog bleiben erhalten.

### In dieser Ausgabe

- Geführter Solo-Einstieg: Die Anleitung erkennt echte Aktionen und erklärt die erste Verteidigung, Produktion, Werkbank, SAN-1 und Reise einschließlich Reifenpanne. Sie verändert keine Vorräte, Wellen oder Belohnungen und bleibt im Koop ausgeblendet.
- Bildauswahl an der Werkbank in der ersten freigegrabenen Etage, passende Maschinenprodukte und kompakte abgelegte Gegenstände. Fertiger Beton erscheint als Eimer.
- Acht unterschiedliche Figuren mit eigenen Tänzen, korrigierten Händen an den Waffengriffen und besser lesbaren Comic-Sprechblasen.
- Musik mit wechselnder Intensität und drei räumlichen Metall-/Stein-Abprallgeräuschen. Online-Koop verwendet kurze Raumcodes über das verschlüsselte Relay; LAN bleibt separat verfügbar.
- Sichtbare Version und Buildkennung, lokaler Änderungsverlauf und ein Fehlerbericht ohne automatischen Upload.

### Herunterladen und starten

Das passende **vollständige Archiv** herunterladen und entpacken:

- Ubuntu x86_64: `Bunkercrew-0.1.0-beta-Ubuntu-x86_64.tar.gz`; im entpackten Ordner `./Start.sh` ausführen.
- Windows x86_64: `Bunkercrew-0.1.0-beta-Windows-x86_64.zip`; `Bunkercrew.exe` starten. Die mitgelieferte DLL bleibt neben dem Spiel.

Godot muss nicht installiert sein. `SHA256SUMS.txt` enthält die Archiv-Prüfsummen. Für Koop verwenden alle dasselbe Paketpaar mit identischer `source_sha256` in `BUILD_INFO.json`; Netzwerkkennung **bunkercrew-net-20**, Weltdaten-Version **5**.

Für den Einstieg **Solo-Story** wählen. **F1 → Erste Schicht → Solo-Tutorial** bietet Starten/Fortsetzen, Beenden und Wiederholen; Wiederholen setzt nur die Anleitung zurück. Am Controller führt **Start → Handbuch** zur Hilfe. Vorhandene Spielstände über **Kampagne fortsetzen** öffnen. Für Internet-Koop **Online-Koop → Raum erstellen** wählen und den sechsstelligen Code teilen; im Standardmodus benötigen Spieler keine UDP-Routerfreigabe.

### Prüfen und Fehler melden

Die Pakete enthalten `QA.md`, `TEST_RESULTS.json`, `TESTING.md` und eine Vorlage für eigene Spieltests. Diese Dateien unterscheiden automatisierte Befunde von noch offenen menschlichen Tests. Windows-Prüfungen unter Proton/Wine ersetzen keine Abnahme auf nativer Windows-Hardware. Vier Spieler über zwei getrennte Internetanschlüsse, längere Spiel-/Hörtests und die Mindestleistung auf schwächeren Geräten bleiben eigene Abnahmen. Diese Testausgabe erklärt Beta 0.5 nicht für freigegeben.

**F4 → Fehlerbericht** öffnet einen lokalen Bericht zum Kopieren oder Speichern. Dazu Reproduktionsschritte, erwartetes/tatsächliches Ergebnis und gegebenenfalls einen Screenshot angeben. Eigene Screenshots und rohe Logs vor dem Teilen auf persönliche Angaben prüfen. Die mitgelieferten Lizenz- und Herkunftshinweise bleiben bei einer Weitergabe Bestandteil des Pakets.

## English

Bunkercrew combines bunker building, resource work and defense with a solo story and co-op for up to four players. This beta begins the public version series; earlier development milestones and their changelog are retained.

### Included in this release

- Guided solo onboarding recognizes real actions and explains the first defense, production, workbench, SAN-1 and travel, including tire repairs. It changes no supplies, waves or rewards and stays hidden in co-op.
- Picture-based crafting on the first excavated floor, appropriate machine products and compact dropped items. Finished concrete appears as a bucket.
- Eight distinct characters with individual dances, corrected firearm hand contacts and more readable comic speech bubbles.
- Music with changing intensity and three spatial metal/stone ricochet sounds. Online co-op uses short room codes through the encrypted relay; LAN remains separately available.
- Visible version and build identity, local change history and an issue report with no automatic upload.

### Download and launch

Download and extract the **entire matching archive**:

- Ubuntu x86_64: `Bunkercrew-0.1.0-beta-Ubuntu-x86_64.tar.gz`; run `./Start.sh` from the extracted directory.
- Windows x86_64: `Bunkercrew-0.1.0-beta-Windows-x86_64.zip`; run `Bunkercrew.exe`. Keep the included DLL beside the game.

No Godot installation is required. `SHA256SUMS.txt` contains the archive checksums. All co-op players must use this matching package pair with the same `source_sha256` in `BUILD_INFO.json`; network identity **bunkercrew-net-20**, world-data version **5**.

Choose **Solo story** to get started. **F1 → First shift → Solo tutorial** offers start/resume, stop and repeat; repeat resets only the guide. With a controller, use **Start → Field manual**. Open existing saves with **Continue campaign**. For Internet co-op, choose **Online co-op → Create room** and share the six-character code; the default mode requires no UDP router forwarding from players.

### Testing and reporting issues

Public player packages include license notices and release information. Detailed automated test reports remain local development evidence because their invocation and log paths contain machine-specific information. Automated findings do not replace human acceptance. Proton/Wine checks do not replace acceptance on native Windows hardware. Four players across two independent Internet connections, longer play/listening sessions and minimum performance on weaker devices remain separate acceptance steps. This test release does not establish Beta 0.5 acceptance.

**F4 → Issue report** opens a local report to copy or save. Include reproduction steps, expected/actual behavior and a screenshot when useful. Check your own screenshots and raw logs for personal information before sharing. Keep the included licenses and provenance notices with any redistributed package.
