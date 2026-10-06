# Bunkercrew: eigener PC und optionaler Relay

## Online-Raum oder direkte Verbindung

Neue Online-Räume verwenden standardmäßig **`wss://bunkercrew.vibechain.rocks/ws`**. Der Gastgeber berechnet weiterhin die Welt; der Relay vermittelt Spielpakete über TLS. Gäste brauchen keine eingehende UDP-Freigabe. **Serveroptionen → LAN · Direkt** wählt den direkten Modus für LAN oder manuelle Routerfreigabe. Bereits geöffnete Räume behalten ihren Transport; für den neuen Standard neu erstellen.

Der direkte Modus verwendet den Rechner des Gastgebers als Spielserver. Der
Gastgeber öffnet eine Schicht, teilt den angezeigten Beitrittscode, und bis zu drei Gäste
verbinden sich damit. Ist der gemeinsame Freundesdienst verbunden, zeigt die Lobby
einen **sechsstelligen Raumcode**. Der Dienst löst ihn zur vollständigen Einladung
mit Host-Adresse und Port auf; die eigentliche Partie läuft weiter direkt zum PC.
Ohne diesen Dienst bleiben LAN- und vollständige Direktcodes verfügbar.
Der Standardport ist **UDP 24777**; ein abweichender Port steht ebenfalls im Code.

Der sechsstellige Code gilt nur für den geöffneten Raum. Er wird beim Schließen,
Abmelden, Spielstart oder einem vollen Raum ungültig. Er bleibt während einer
erreichbaren Lobby gleich; zehnsekündige Statusmeldungen erneuern seine
30-Sekunden-Frist. Die Auflösung ist an eine angemeldete Dienstverbindung gebunden,
wird pro Profil und IP begrenzt und gibt keine öffentlichen Raumlisten aus.
Blockierte Personen können den Code nicht auflösen. Schlägt die Auflösung fehl,
kann der Gastgeber unter **SERVEROPTIONEN** den vollständigen Ersatzcode kopieren.

Der LAN-Code hat 16 Zeichen in Vierergruppen und wird über UDP 24778 im lokalen Netz aufgelöst. Der direkte Ersatzcode enthält die Adresse und funktioniert bei blockierter LAN-Suche.

Ein direkter Standardcode hat 24 Zeichen zuzüglich Gruppentrennern.
Ein eigener Port benötigt 27 Zeichen zuzüglich Gruppentrennern. Der erste Teil
enthält IPv4-Adresse, gegebenenfalls Port und eine Prüfsumme. Die letzten 16
Zeichen sind eine neue zufällige Einladung mit 80 Bit Entropie. Der Gastgeber
prüft sie bei der ersten Anmeldung; ein alter reiner Adresscode genügt nicht.
Für Wiederverbindungen gilt ein separates Sitzungstoken. Nur eingeladenen
Mitspielern den vollständigen Code geben.

- **Dasselbe Netzwerk:** Der LAN-Code verbindet mit der lokalen Adresse des PCs.
- **Internet:** Der Internetcode benötigt eine öffentliche IPv4-Adresse und eine
  UDP-Freigabe zum Gastgeber. Die Betriebssystem-Firewall muss Godot bzw. das
  exportierte Spiel auf diesem UDP-Port zulassen.
- **Automatische Freigabe:** Das Spiel sucht im Hintergrund nach einem
  UPnP-Router. Es überschreibt keine vorhandenen Regeln. Eine selbst angelegte
  Regel gilt zehn Minuten, wird während der Sitzung erneuert und beim Schließen
  nur entfernt, wenn sie noch dieser Sitzung gehört.
- **UPnP ausgeschaltet:** UDP 24777 am Router manuell auf die lokale IPv4-Adresse
  des Gastgebers weiterleiten. Im Spiel vor **RAUM ERSTELLEN** unter
  **SERVEROPTIONEN** die öffentliche IPv4 eintragen. Der erzeugte Internetcode
  enthält diese Adresse; der zusätzliche LAN-Code bleibt verfügbar.
  Eine Routerfreigabe allein bestätigt noch nicht,
  dass der Gast den Rechner über das Internet erreichen kann.
- **DS-Lite oder CGNAT:** Der Router besitzt möglicherweise keine öffentliche
  IPv4-Adresse. Ein LAN-Code wird dadurch nicht zum Internetcode. Dann sind eine
  öffentliche IPv4 vom Anbieter oder ein öffentlich betriebener Relay nötig.

Der eigene Freundesdienst kann die Quell-IPv4 der ausgehenden Verbindung mitteilen.
Diese Information bestätigt keine Routerfreigabe. Eine öffentliche Einladung wird
erst mit bestätigter UPnP-Freigabe oder der ausdrücklich eingetragenen öffentlichen
Adresse erzeugt. Ein Kurzcode macht einen privaten LAN-Host nicht über das Internet
erreichbar; bei DS-Lite/CGNAT den Relay verwenden.
Diese Umsetzung folgt den Godot-Dokumentationen zu
[ENet und UDP](https://docs.godotengine.org/en/stable/classes/class_enetmultiplayerpeer.html)
sowie [UPnP und Hintergrundthreads](https://docs.godotengine.org/en/stable/classes/class_upnp.html).

Direkte Verbindung und Codes prüfen, ohne Routerregeln anzulegen:

```bash
godot --headless --path . --script tests/network_join_code_test.gd -- --no-profile-save
python3 tests/network_transport_test.py
python3 tests/network_session_lobby_test.py
python3 tests/network_gameplay_test.py
python3 tests/network_four_test.py
python3 tests/network_four_test.py --relay
```

Der zweite Test startet zwei getrennte Godot-Prozesse und überträgt Eingaben
sowie einen 64-KiB-Zustand über einen echten lokalen UDP-Socket. Der dritte
öffnet die tatsächliche Spielszene auf beiden Seiten und prüft Anmeldung,
Figurenwahl und Szenarioabgleich. Außerdem müssen Teilnehmer mit falscher
Version oder ohne abgeschlossene Anmeldung ihren Platz für einen gültigen
Beitritt freigeben. Derselbe Lobbyablauf läuft zusätzlich über einen lokal
gestarteten Relay; dieser Teil benötigt `aiohttp` aus den Server-Abhängigkeiten.
Der Gameplay-Test steuert zwei getrennte Instanzen der Hauptszene über die echte
InputMap und ENet. Er prüft Bewegung, Schießen, getrennte Magazine,
Ressourcen-/Gegnerzustände, Kaufberechtigungen, Pause, Wiederverbindung und einen
gemeinsamen Neustart. Positionen und einzelne Zustände sind für die Prüfung
vorbereitet. Alle Netzwerkprüfungen laufen ohne UPnP und ohne Profilspeicherung;
sie öffnen keine Routerfreigaben.

Die zusätzlichen Tests `tests/network_lifecycle_boundary_test.gd` und
`tests/network_structure_validation_test.gd` prüfen verspätete Eingaben nach
einem Neustart, Wiederverbindung nach Sieg/Niederlage sowie ungültige
Bauzustände. Eingaben gehören immer zu genau einer Schicht; Ergebnisanzeigen
und die angehaltene Simulation bleiben nach dem Wiederbeitritt erhalten.

## Freunde, Bereitschaft und Einladungen

Der aktualisierte Prozess bietet zwei getrennte WebSocket-Endpunkte am selben
Port an: **`/ws`** für den Spiel-Relay und **`/social`** für Freunde, Status und
Einladungen. **`/healthz`** bestätigt den gestarteten Dienst und dessen Build.
Der native Standardport bleibt **TCP 8765**; der öffentliche TLS-Proxy verwendet **443**.
Spieler verbinden sich ausschließlich ausgehend. UDP 24777/24778 wird weiter
für direkte Spiele und die LAN-Raumsuche verwendet.

Der eingerichtete öffentliche Dienst ist **`wss://bunkercrew.vibechain.rocks/social`**.
Neue Profile verbinden sich automatisch; ausdrücklich offline geschaltete Profile
und gewählte andere Dienste bleiben erhalten. **F7 → Freunde** zeigt Verbindung,
eigenen Freundescode und Kontakte. Für einen eigenen Dienst einmal dessen Adresse
speichern und verbinden. Eine vorhandene `wss://domain/ws`-Adresse
wird zu `wss://domain/social` abgeleitet. Öffentlich benötigt der Dienst ein
gültiges TLS-Zertifikat. Ein Freundescode ist ein öffentlicher Bezeichner und
kein Zugangsschlüssel. Eine Anfrage muss von der anderen Person bestätigt
werden; auch zwei gegenseitig gesendete Anfragen ersetzen diese Bestätigung nicht.
Ausgehende Anfragen bleiben nach einer erneuten Anmeldung sichtbar und können
zurückgezogen werden. Nur bestätigte Freunde sehen Status und Schauplatz. Es gibt keine
öffentliche Benutzerliste. Wer blockiert wird, verliert die Freundschaft,
offene Anfragen und Einladungen und kann keine neuen Anfragen senden.

Einladungen kommen aus einem tatsächlich geöffneten Gastgeber-Raum und laufen
nach zwei Minuten ab. Beim Spielstart, bei vollem oder geschlossenem Raum sowie
bei Abmeldung werden sie ungültig. Für Räume auf demselben Relay prüft der Dienst
zusätzlich das private Host-Sitzungstoken; dieses wird keinem Freund mitgeteilt.
Für direkte Spiele bleibt die tatsächliche Erreichbarkeit von Router und
Firewall abhängig. Ein gemeinsamer öffentlicher Relay vermeidet diese
Portweiterleitungen. Ein Einladungsbeitritt beendet niemals eine laufende Runde.

Freundschaften, Anfragen, Sperren und Profilnamen liegen in SQLite. Bei einem
nativen Python-Start ist der Standard
`$XDG_DATA_HOME/bunkercrew-relay/social.sqlite3`, ersatzweise
`~/.local/share/bunkercrew-relay/social.sqlite3`. **`SOCIAL_DB`** setzt einen
anderen absoluten Pfad. SQLite arbeitet auf einem begrenzten Hintergrundpfad;
Status und Einladungen werden im Arbeitsspeicher gehalten. Ein Serverneustart
erhält die Freundschaften und setzt den Verbindungsstatus zurück. Die Datenbank
und bei laufendem Server ihre WAL-Datei gehören in die Datensicherung. Einen
konsistenten Snapshot mit SQLite-Backup anfertigen oder den Dienst vor einer
Dateikopie sauber beenden.

Docker Compose bindet das benannte Volume **`social_data`** an **`/data`** ein.
Der Prozess läuft als Benutzer 10001, das übrige Dateisystem bleibt schreibgeschützt.
**`docker compose down -v` löscht auch die dauerhaften Freundschaften**;
normales `down` oder ein Containerwechsel erhält sie. Für entfernte Clients
TLS über den vorgesehenen Caddy oder einen ausdrücklich vertrauten TLS-Proxy
verwenden. Ein Docker-Port, der nur an Host-Loopback gebunden ist, ersetzt keine
TLS-Proxy-Konfiguration für die Profile: im Container kann der Verbindungspeer
als Docker-Gateway erscheinen. Für einen lokalen Test ohne Proxy den nativen
Python-Prozess und `ws://127.0.0.1:8765/social` verwenden.

Das lokale Spielprofil **`user://social_v1.json`** enthält je Dienst einen
eigenen zufälligen 256-Bit-Zugangsschlüssel; der Server speichert nur dessen
Hash. Hauptdatei, atomische Ersatzdatei und Sicherung sind auf Unix nur für den
Besitzer les- und schreibbar. Die Freundschaft gehört zu diesem Profil und dem
gewählten Server. Den Profilordner vertraulich sichern; ohne dieses Profil kann
ein öffentlicher Freundescode keinen alten Zugang wiederherstellen.
**Trennen** schaltet die automatische Anmeldung beim nächsten Spielstart aus.
Testläufe mit `--no-profile-save` lesen und schreiben das reguläre Profil nicht.

In der Lobby öffnet ein Klick auf einen belegten fremden Crew-Platz dessen
Aktionen: Stummschalten, Blockieren, private Nachricht und Freundesanfrage.
Freundesanfragen verwenden ausschließlich die beim Dienst geprüfte Identität.
Bei einer Prüfung oder einem anderen Dienst zeigt die Oberfläche den Grund,
statt einen fremden Profilcode als bestätigt zu behandeln. Stummschalten betrifft
nur die Stimme dieser Person. Sperren werden bei bestätigten Profilen dauerhaft
gespeichert; ohne gemeinsame geprüfte Identität gelten sie für den aktuellen Raum.
Wiederverbindung und wechselnde Platznummern übertragen diese Aktionen nicht auf
einen neuen Mitspieler.

## Textchat in Lobby und Spiel

Der Crew-Chat benötigt keinen Freundesdienst: Er läuft über die authentifizierte
direkte oder Relay-Spielverbindung auf dem zuverlässigen Steuerkanal. Der Host
ordnet Absender, Platz, laufenden Raum und Nachrichtennummer zu. Freie Texte
haben höchstens 240 Zeichen und 1024 UTF-8-Bytes; Steuerzeichen und irreführende
Richtungsmarker werden zurückgewiesen. Namen und Texte werden als Klartext ohne
RichText-Auswertung angezeigt. Schnelltexte übertragen eine feste ID und werden
erst beim Empfänger übersetzt. Chatnachrichten werden weder im Freundesdienst
noch auf der Festplatte protokolliert.

Pro Teilnehmer sind drei sofortige Nachrichten und danach eine Nachricht pro
Sekunde erlaubt. Die letzten 80 Nachrichten werden nach Anmeldung und
Wiederverbindung in der richtigen Reihenfolge geliefert und bleiben beim
Missionsneustart erhalten. Ein neuer Raum hat einen neuen Verlauf. Der Host
bestätigt jede zugelassene Sendung; bei Transportfehler, Rate-Limit oder fehlender
Bestätigung bleibt der Entwurf erhalten. Chat erzeugt keine Welt-Snapshots und
kann dem Sender keine Spielberechtigungen geben.

Private Nachrichten gehen vom Absender über den Host nur zum gewählten
Empfänger. Andere Gäste bekommen sie weder live noch beim Wiederbeitritt als
Verlauf. Der Host verarbeitet sie als Vermittler. Der Verlauf und offene
Entwürfe bleiben an die konkrete Person gebunden, auch wenn später jemand
anderes denselben Platz oder Namen übernimmt. Ein blockierter oder nicht mehr
erreichbarer Empfänger erzeugt eine negative Bestätigung; der Entwurf bleibt
stehen. Der Freundesdienst transportiert und speichert diese Texte nicht.

**Enter** öffnet im Online-Spiel den Chat, im Lobby-Menü gibt es einen Chat-Knopf.
Enter sendet, **Esc** schließt. Das Tippen sperrt eigene Spielaktionen und
Push-to-Talk, während die gemeinsame Simulation weiterläuft. Die sechs
Schnelltexte funktionieren vollständig ohne Headset.

Die gemeinsamen Prüfungen laufen ohne reguläre Spielerprofile:

```bash
python3 tests/social_service_test.py
godot --headless --debug --path . --script tests/social_hub_test.gd -- --no-profile-save
godot --headless --debug --path . --script tests/social_game_bridge_test.gd -- --no-profile-save
python3 tests/social_reconnect_test.py
python3 tests/social_end_to_end_test.py
godot --headless --debug --path . --script tests/social_chat_ui_test.gd -- --no-profile-save
python3 tests/network_chat_test.py
```

Der Ende-zu-Ende-Lauf benutzt zwei echte Spielprozesse und einen isolierten
lokalen Dienst: Freundschaft bestätigen, über den Einladungs-Knopf beitreten,
Lobby- und Spielchat benutzen und die gemeinsame Mission neu starten.

## Optionalen Relay betreiben

### Bereitgestellter Dienst für Bunkercrew

Der eigene öffentliche Server bietet **`wss://bunkercrew.vibechain.rocks/social`**
für Freunde und kurze Codes sowie **`wss://bunkercrew.vibechain.rocks/ws`** für
Partien ohne direkte Routerfreigabe. **`https://bunkercrew.vibechain.rocks/healthz`**
liefert Status und Build. Der Spielstand bleibt beim Gastgeber.

Die Installation liegt getrennt unter **`/opt/bunkercrew`**. Der eigene
Compose-Projektname ist `bunkercrew`, das dauerhafte SQLite-Volume
`bunkercrew_social_data`. Der Anwendungsport **18765** ist ausschließlich an
`127.0.0.1` gebunden. Ein eigener Nginx-VHost stellt HTTPS/WSS bereit; bestehende
Domains verwenden ihre bisherigen Dateien und Dienste. Die Anwendung läuft
ohne Linux-Capabilities mit schreibgeschütztem Dateisystem und begrenzten
Ressourcen; nur das Datenvolume ist beschreibbar.

Das eigene Let's-Encrypt-Zertifikat liegt unter **`/opt/bunkercrew/tls`**.
`/opt/bunkercrew/bin/renew-certificate.sh` prüft zweimal täglich auf Erneuerung
und lädt Nginx erst nach erfolgreicher Konfigurationsprüfung neu.
`/opt/bunkercrew/bin/backup-social.sh` erzeugt täglich einen konsistenten
SQLite-Snapshot unter **`/opt/bunkercrew/backups`** und behält sieben Snapshots.
Beide Jobs stehen separat in **`/etc/cron.d/bunkercrew`**. Profilschlüssel und
Beitrittscodes gehören weder in Diagnoseausgaben noch in öffentliche Berichte.

Der Nginx-VHost übernimmt `CF-Connecting-IP` ausschließlich von den ausdrücklich
vertrauten Cloudflare-Netzen. Die Anwendung vertraut anschließend nur ihrem
eigenen Docker-Gateway für diese Weiterleitung. Ungeprüfte Header direkter
Origin-Verbindungen können dadurch keine fremde Client-IP vorgeben.

Die wiederverwendbaren Dateien liegen unter **`server/deploy/vibechain/`**.
Auf dem Server zeigt **`/opt/bunkercrew/current`** auf die eigene Release-Kopie.
Ein Update baut ausschließlich dieses Compose-Projekt neu; das benannte
Datenvolume bleibt bestehen. Zum ausdrücklichen Zurücknehmen der Installation
steht **`/opt/bunkercrew/bin/rollback.sh`** bereit. Es entfernt nur den eigenen
VHost-Link nach erfolgreicher Nginx-Prüfung, stoppt die eigene Anwendung und
deaktiviert deren Cron-Datei. Datenvolume, Sicherungen und Zertifikate bleiben
erhalten. Die Prüfberichte liegen unter
**`artifacts/server-deploy/bunkercrew/`**; sie enthalten keine Profilschlüssel.

Der mitgelieferte optionale Relay verbindet bis zu vier Spieler über einen
sechsstelligen Raumcode. Alle Clients öffnen eine ausgehende
WebSocket-Verbindung zum selben Relay. Der
Gastgeber berechnet die Partie; der Relay leitet Spielpakete unverändert weiter.
Der Spiel-Relay speichert keine Spielstände. Der zusätzliche Freundesdienst speichert bestätigte Freundschaften, Anfragen, Sperren und Profilnamen in SQLite; Zugangsdaten liegen dort ausschließlich als SHA-256-Hash eines zufälligen 256-Bit-Schlüssels vor.

### Lokal starten und prüfen

```bash
python3 -m venv server/.venv
server/.venv/bin/pip install -r server/requirements.txt
server/.venv/bin/python server/relay.py
# In einem zweiten Terminal:
server/.venv/bin/python tests/relay_test.py
```

Standardadresse: `ws://127.0.0.1:8765/ws`. `/healthz` liefert den Serverstatus und
die Protokollversion. Unverschlüsseltes `ws://` akzeptiert das Spiel nur für
`localhost`, `127.0.0.1` und `[::1]` auf demselben Rechner. Jeder externe Relay,
auch auf einem anderen LAN-Rechner, benötigt `wss://` mit gültigem Zertifikat.

### Auf einem eigenen Internetserver starten

Benötigt werden ein eigener Server mit Docker Compose, eine Domain mit passendem
DNS-Eintrag und eingehende TCP-Ports 80 und 443. Spieler benötigen keine
Portweiterleitung an ihrem Router.

```bash
cp server/.env.example server/.env
# In server/.env RELAY_DOMAIN auf die eigene Domain setzen.
docker compose --env-file server/.env -f server/compose.yaml --profile public up -d --build
```

Caddy beschafft und erneuert das TLS-Zertifikat. Im Spiel verwenden alle
Spieler `wss://<eigene-domain>/ws`. Der Relay-Port 8765 wird nur an die
Loopback-Adresse des Servers veröffentlicht. Ohne Caddy lässt sich der Relay mit
`docker compose -f server/compose.yaml up -d --build relay` hinter einem vorhandenen
TLS-Proxy betreiben. Ein öffentlicher Dienst wird durch diese Dateien noch nicht
bereitgestellt; er muss auf dem eigenen Server gestartet werden.

`RELAY_MAX_ROOMS` und `RELAY_MAX_CONNECTIONS` begrenzen die Kapazität; Standard
sind 256 Räume und 768 Verbindungen. Native Godot-Clients senden keinen
`Origin`-Header und sind zugelassen. Für Browserclients muss
`RELAY_ALLOWED_ORIGINS` die exakten erlaubten Ursprünge kommagetrennt enthalten.
Wildcard-Ursprünge werden nicht akzeptiert. Zugangsdaten und Raumcodes werden
nicht protokolliert. Nur vertrauenswürdige Spieler sollten den Beitrittscode
erhalten. Der Code dient der Einladung; es gibt keine öffentliche Raumliste.

Zusätzlich begrenzt `RELAY_MAX_CONNECTIONS_PER_IP` gleichzeitige Verbindungen
derselben Quelladresse; Standard sind 64 einschließlich laufender Handshakes.
Neue Verbindungen haben je Adresse ein Budget von 2 pro Sekunde mit einem
Startpuffer von 64. Raumbeitritte, Raumerstellung und Wiederverbindungsversuche
teilen sich 0,2 Anfragen pro Sekunde und einen Puffer von 16. Diese Budgets
bleiben nach einem Socketwechsel erhalten. IPv6-Adressen werden pro `/64`
zusammengefasst. Die Tabelle enthält höchstens 4.096 Einträge; ungebundene,
zehn Minuten unbenutzte Einträge werden entfernt. Ist sie voll, werden neue
Adressen zunächst abgewiesen.

Hinter einem Reverse Proxy erscheint sonst dessen Adresse als Absender.
`RELAY_TRUSTED_PROXIES` akzeptiert deshalb optional eine kommagetrennte Liste
exakter Proxy-Adressen oder vertrauenswürdiger CIDR-Netze. Nur von solchen
Socket-Gegenstellen wird `X-Forwarded-For` ausgewertet, von rechts bis zum
ersten nicht vertrauenswürdigen Hop. Ohne diese Einstellung bleiben
Forwarding-Header unbeachtet. Die Variable bei Docker ausdrücklich an den
Relay-Container weitergeben, beispielsweise durch eine Compose-Override-Datei.
Keine öffentlichen Clientnetze oder `0.0.0.0/0` als Proxy eintragen. Die
mitgelieferte Compose-Datei vertraut standardmäßig keinen Proxys; Betreiber
müssen bei Verwendung von Caddy dessen internes Netz passend konfigurieren.

### Relay-Protokoll 1

Textnachrichten sind JSON-Objekte. `host`, `join` und `resume` enthalten
`"version":1` und `"build":"bunkercrew-net-20"`. Alle Spiele und der Relay müssen
diesen Build verwenden. Ältere Builds werden beim Verbindungsaufbau abgewiesen;
Die Fassung bindet jedes Eingabepaket an die angemeldete Verbindung, den Spielerplatz und die laufende Schicht.
Die Spiele handeln zusätzlich `world_revision: 5` im Hello/Welcome aus. Darin
sind Sitzrollen, Motorstart, der aktuelle Reifenwechsel und zwölf kataloggebundene
Luftgegnerprofile sowie die acht gültigen Crewprofile einschließlich Oskar und Rika enthalten. Spiele mit älteren Weltdaten-Versionen werden vor
dem Weltabgleich abgewiesen. Der Relay
transportiert diese Binärpakete unverändert; sein Build bleibt `bunkercrew-net-20`.
Unbekannte Kontrollfelder, doppelte JSON-Schlüssel und nicht endliche Zahlen
werden abgewiesen. Leere, `null`- und mehrfache Origin-Header gelten ebenfalls
als ungültig. Ein fehlender Origin bleibt für native Clients zulässig.

| Anfrage | Antwort / Ereignis |
| --- | --- |
| `host`, `name` | `hosted`: `code`, `role`, `token`, `resume_token`, `started`, `player_id` |
| `join`, `code`, `name` | `joined`: `code`, `role`, `resume_token`, `started`, `peer_connected`, `player_id` |
| `resume`, `token` | `resumed`: gleiche Sitzungsdaten; ein neues `resume_token` ersetzt das alte |
| `status`, `started` (Boolean, nur Host) | `status` an alle Spieler |
| `ping`, `id` | `pong` mit derselben Kennung |
| `leave` | `left`; Host schließt zusätzlich den Raum |
| `kick`, `player_id` (nur Host) | Nur der bezeichnete Gast wird getrennt; dessen Platz und Wiederverbindungstoken werden freigegeben |

Beim Verbinden erhalten Host und Gast `peer_joined` mit `role`, `name`,
`resumed` und `player_id`. Vor Binärnachrichten bis 512 KiB steht ein zusätzliches
Routingbyte: Gäste dürfen ausschließlich an 1 (Host), der Host an 2–4 senden. Ziel 0 ist als Broadcast an alle Relay-Gastplätze definiert; Spielzustände verwenden stattdessen gezielt die IDs der im Spiel bereits authentifizierten Gäste. Bit 7 kennzeichnet verwerfbare Sprachdaten.
Der Relay ersetzt dieses Byte durch die tatsächliche Absenderkennung. Gäste
können weder andere Gäste direkt adressieren noch deren Absenderkennung
behaupten. Der restliche Inhalt bleibt unverändert; der Relay dekodiert keine Spielobjekte. Bei kurzzeitigem
Verbindungsverlust bleibt der Platz 30 Sekunden reserviert; `peer_left` enthält
`role`, `player_id`, `reason` und `reconnect_seconds`. Explizites Verlassen reserviert keinen
Platz. Läuft die Host-Frist ab, erhalten verbundene Gäste `room_closed` mit
`reason:"host_timeout"`. Ein Serverneustart schließt alle Räume.

`error` enthält `code` und eine deutsche `message`. Häufige Fehler sind
`invalid_code`, `room_not_found`, `room_full`, `version_mismatch`,
`host_unavailable`, `resume_expired`, `already_connected` und `server_full`.
Eine ungültige Anfrage verändert keine bestehende Sitzung.

Pro Verbindung sind dauerhaft 160 Spiel-/Sprachpakete und 2 MiB pro Sekunde erlaubt,
mit einem kurzen Puffer für 320 Pakete beziehungsweise 4 MiB. Der Host darf 640 Pakete/s mit 1280 Paketen Puffer sowie 6 MiB/s mit 12 MiB Puffer übertragen. Das deckt drei parallele Snapshotströme und alle weitergeleiteten Stimmen ab und bleibt nach Wiederverbindung erhalten. Textanfragen sind
auf 12 pro Sekunde, einen Puffer von 32 und 4 KiB pro Nachricht begrenzt.
Überschreitungen beenden die Verbindung mit Code 1008; zu große Nachrichten mit
1009. Langsame Empfänger werden nach zwei Sekunden blockiertem Schreiben
getrennt. Jeder Empfänger hat eine begrenzte asynchrone Warteschlange mit 64 Nachrichten beziehungsweise vier maximalen Binärnachrichten. Binär- und JSON-Nachrichten teilen dieselbe FIFO-Reihenfolge und denselben Schreiber, damit eine Abbruchmeldung die vorherige Verlassen-Nachricht nicht überholt. Ein langsamer Gast blockiert die übrigen Empfänger nicht. Ungebundene Verbindungen verfallen nach 20 Sekunden.
WebSocket-Ping/Pong-Kontrollframes teilen das Kontrollbudget. Ein laufender
Handshake reserviert bereits Kapazität und hat maximal drei Sekunden Zeit.

### Sprache und Zustandsübernahme

Sprachpakete enthalten mono PCM16 mit 16 kHz: 20 ms beziehungsweise 640 Byte
Nutzdaten, höchstens 50 Pakete pro Sekunde. Der direkte Modus verwendet einen
eigenen unzuverlässigen ENet-Kanal. Kurzer Rückstau wird verworfen, ohne die Partie zu beenden. Der Transport scannt zusätzlich zu seinem Spielpaketbudget bis zu 256 empfangene Pakete pro Frame und lässt pro Gast höchstens vier Sprachpakete weiter; Eingaben anderer Gäste bleiben bedienbar. Beim Relay werden Gaststimmen vor der gemeinsamen Eingangswarteschlange auf 55 Pakete/s mit einem kurzen Puffer begrenzt. Erst eine über mindestens zwei Sekunden dauerhaft überhöhte Senderate (mehr als dreifache normale Rate) trennt den betreffenden Absender; einzelne kurze Bursts zählen dafür nicht. Über WebSocket werden neue Sprachpakete bei
mehr als 8 KiB ausstehenden Ausgangsdaten verworfen, damit sich keine lange
Sprachwarteschlange aufbaut. Direkter UDP-Verkehr ist unverschlüsselt. Externe
Relays erfordern `wss://`, das die Verbindung zum Relay verschlüsselt. Der Relay
ist dabei ein vertrauenswürdiger Vermittler; die Verbindung bietet keine
Ende-zu-Ende-Verschlüsselung zwischen den Spielern.

Der Gast prüft vollständige Snapshots vor dem Anhalten der Simulation oder
dem Bau lokaler Räume. Pflichtobjekte, bekannte Katalogprofile, Wertebereiche,
Elternbeziehungen, Referenzklassen und neu benötigte Bauobjekte müssen stimmen.
Feste Bauteile dürfen nicht verschoben werden; Spieler, Gegner und lokale
Waffenposen erhalten weiterhin ihre autoritativen Bewegungsdaten. Der Gastgeber
bleibt für Spielregeln und Fortschritt zuständig.

### Prüfumfang des Relays

`tests/relay_test.py` startet echte HTTP-/WebSocket-Server auf freien lokalen
Ports und verbindet mehrere unabhängige Clients. Geprüft werden unter anderem
beidseitige Binärübertragung, Einladungen, Rollen, belegte Räume, Versionen,
Wiederverbindung, Tokenwechsel, Zeitablauf, Größen- und Ratenlimits, erlaubte
Ursprünge sowie die Bereinigung geschlossener Räume. Ein Test ersetzt keine
Verbindungsmessung zwischen zwei Internetanschlüssen.

Zusätzliche lokale Prüfungen:

```bash
godot --headless --debug --audio-driver Dummy --path . --script tests/network_snapshot_boundary_test.gd -- --no-profile-save --no-upnp
godot --headless --debug --audio-driver Dummy --path . --script tests/network_control_validation_test.gd -- --no-profile-save --no-upnp
```

Die Snapshotprüfung verändert vorbereitete Pakete einer echten Hauptszene und
vergleicht nach jeder Ablehnung den vollständigen erfassten Zustand sowie den
Processing-Status. Die Relayprüfung verwendet eigene freie lokale Ports und
prüft zusätzlich Versuche über neue Sockets, gefälschte Forwarding-Header,
parallele Handshakes, Kontrollframes und die begrenzte Adresstabelle.

### Korrekturen am aktuellen Quellstand

Client und Relay verwenden `bunkercrew-net-20`. LAN-Codes enthalten 16 zufällige Base32-Zeichen (80 Bit), formatiert in vier Gruppen. Fehlende Gäste behalten ihren Platz zunächst 30 Sekunden; danach scheidet nur dieser Platz aus und die übrige Crew spielt weiter. Ein absichtlich beendeter Host schließt die Sitzung sofort. Fehlgeschlagene Relay-Versuche verlängern die ursprüngliche Wiederverbindungsfrist nicht.

Der Sitzungsping erkennt ausgefallene Partner nach fünf Sekunden, während des Ladens nach 35 Sekunden. Die längeren nativen ENet-Zeitlimits von 15–30 Sekunden schützen Szenenwechsel. Überzählige gültige Sprachpakete werden verworfen; zuverlässige Spielnachrichten behalten ihr eigenes Budget. Der Host zeigt bei mehreren Gästen den höchsten Ping.

Gäste dekodieren begrenzte Pakete auf einem Worker-Thread und prüfen den Weltzustand vor dem Anwenden. Dauerhaft abgewiesene Snapshots lösen eine Neusynchronisationsanfrage und anschließend eine verständliche Fehlermeldung aus. Der Host erfasst und kodiert einen gemeinsamen Snapshot pro Takt. In der Pause laufen Snapshots und unveränderte Eingaben mit zwei Aktualisierungen pro Sekunde.

Die mitgelieferte Compose-Konfiguration vertraut nur Caddys fester Adresse `172.30.247.3/32` im separaten Netz `172.30.247.0/29`. So gelten Verbindungslimits pro tatsächlicher Client-IP. Bei einem bereits belegten Subnetz können `RELAY_PROXY_SUBNET` und `RELAY_CADDY_IP` gemeinsam angepasst werden; die Proxy-Adresse muss im gewählten Netz liegen. Direkte Clients dürfen keine vertrauenswürdigen Weiterleitungsheader setzen.
