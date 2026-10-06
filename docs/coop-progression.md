# Crewgröße, Erfahrung und Forschung

## Gegner für eine bis vier Figuren

Die Solo-Werte bleiben unverändert. `Balance.active_players()` zählt offline die vorhandene Crew und online die authentifizierten, verbundenen Plätze. Bewusstlose Figuren bleiben Teil der Crewgröße; absichtliches Niedergehen senkt die Schwierigkeit nicht.

| Aktive Crew | Gegnerzahl | LP beim Erscheinen | Angriffsschaden | Spawnabstand |
| --- | ---: | ---: | ---: | ---: |
| 1 | 1,00× | 1,00× | 1,00× | 5,50 s |
| 2 | 1,45× | 1,08× | 1,04× | 4,80 s |
| 3 | 1,90× | 1,16× | 1,08× | 4,26 s |
| 4 | 2,35× | 1,24× | 1,12× | 3,83 s |

Die Gegnerzahl wird aufgerundet. Beitritt oder Abbruch ändern nur das verbleibende Wellenbudget; bereits erschienene Gegner verschwinden nicht und erhalten keine neuen LP. Bodenmaschinen, Infanterie, Luftgegner und Bosse verwenden dieselben kleinen Stärkeaufschläge. Straßenwachen und Außenposten erhalten denselben Faktor für ihre Anzahl. Bei Online-Verbindungsabbruch pausiert die Sitzung bis zur Wiederverbindung.

## Ein gemeinsamer Kampfpool

Der Gastgeber vergibt Erfahrung einmal am tatsächlichen Schaden. Übertreffer, leere Schüsse und bereits besiegte Gegner erzeugen keine Erfahrung. Pro entferntem LP entstehen weiterhin 0,1 XP; ein Abschuss gibt 14 XP mit dem bestehenden begrenzten Kombobonus. Nur der tatsächliche Schütze erhält den persönlichen Abschusszähler.

Für `n` teilnehmende Figuren wird dieser Pool mit `1 + 0,35 × (n − 1)` multipliziert und gleich geteilt. Die persönlichen Anteile sind **1 / 0,675 / 0,5667 / 0,5125**. Vier Figuren erhalten zusammen höchstens 2,05 Solo-Pools, keine vier Kopien. Die zusätzlichen Gegner gleichen die Teilung aus: Bei einer Beispielwelle mit zwölf normalen 90-LP-Gegnern erhält jede aktive Figur ohne Kombos und Rollenboni rund **276 / 288 / 319 / 374 XP**.

Nützliche Arbeit, manuell abgefeuerte endliche Munition, Herstellung, Versorgung, medizinische Hilfe, Abbau und neuer Fahrfortschritt halten eine Figur 90 Spielsekunden beteiligt. Neue Figuren erhalten dieses begrenzte Startfenster ebenfalls. Danach bekommt eine untätige oder getrennte Figur keine Kampfanteile. Pausen und Menüs verbrauchen das Fenster nicht. Auch Arbeit nach Erreichen eines Rollenlimits hält die Beteiligung aufrecht. Bewegung oder eine gehaltene Taste allein reichen nicht. Automatische Anlagen erneuern die Aktivität ihres ursprünglichen Erbauers nicht; inaktive Erbauer erhalten daraus keine XP.

## Tatsächlich abgeschlossene Rollenarbeit

| Tätigkeit | Erfahrung | Grenze je Figur und Welle |
| --- | --- | ---: |
| Reparatur | 0,06 je wirklich repariertem LP, nach Materialverbrauch | 18 XP |
| Produktion | 4 XP je abgeschlossenem Batch, geteilt unter den tatsächlichen Einfüllern | 16 XP |
| Versorgung | 0,1 XP je tatsächlich ans Geschütz gelieferter Patrone; 2 XP je 20 Schuss, auch anteilig | 12 XP |
| Medizin | 0,05 je wiederhergestelltem LP, zusätzlich 4 bei Wiederbelebung; höchstens 6 je Behandlung | 12 XP |
| Herstellung/Bau | 4 je bezahltem Gegenstand oder Außenanlage; 2 je bezahlter Wandbaustufe | 12 XP |
| Fahren | 1 XP je 60 neue Vorwärtspixel | 40 XP je Fahrt insgesamt |

Herstellung wird erst beim fertigen Output gutgeschrieben. Einlagern, Auslagern oder bloßes Abholen verdoppeln keine Belohnung. Fehlgeschlagene Reparaturen und volles Leben geben keine XP. Fahr-XP sind auf die wirkliche Reise und ihren Zwischenhalt beschränkt; Garagenfahrten zählen nicht. Der Fahrstreckenrekord gehört dem Fahrzeug: Rückwärtsfahren, Zurückkehren und Fahrerwechsel wiederholen keine Strecke. Fahr-XP werden in ganzen Punkten gesammelt, nicht in einem Netzwerkereignis pro Frame. Kleine Rollenanzeigen sammeln jeweils zwei Sekunden Erfahrung in einem vorhandenen schwebenden Text; online sieht jeder seine eigenen Anzeigen.

Persönliche XP werden an den bisherigen sicheren Kampagnenübergängen gespeichert. Wiederholung lädt den gesicherten Zustand und übernimmt keine ungesicherten XP. Der Zuschuss für Rollen ist absichtlich begrenzt, obwohl verbrauchtes Material bereits knapp ist.

## Zwölf Fahrzeugknoten

Zu MG, zwei Panzerungsstufen, Laderaum, Tank und Sparmotor kommen sechs Verbesserungen:

| Forschung | Voraussetzung | Kosten | Tatsächliche Wirkung |
| --- | --- | ---: | --- |
| Fahrwerkabstimmung | Fahrzeug verfügbar | 3 | Beschleunigung 190 → 250; Bremskraft 350 → 460 |
| Langstreckengetriebe | Fahrwerkabstimmung | 5 | Höchstgeschwindigkeit 125 → 140; Verbrauch weiterhin nach Strecke |
| Schnellverschluss | MG-Schützenplatz | 4 | MG-Nachladen 1,40 → 1,05 s |
| MG-Stabilisierung | Schnellverschluss | 5 | MG-Schaden 18 → 21; Magazin und Verbrauch bleiben gleich |
| Mobiler Werkzeugsatz | Lastenträger | 4 | 30 % mehr Reparatur je Material; Garage 150 → 195 LP für 2 Stahl |
| Splitterauskleidung | Verbundpanzerung | 6 | 15 % weniger eingehender Fahrzeugschaden |

Alle vier Sitzplätze existieren schon im Grundfahrzeug. Käufe sind auf die Vorbereitung beschränkt; Kosten, Voraussetzungen und gespeicherte Fahrzeugwerte werden geprüft. Ein fehlgeschlagener Speichervorgang rollt den Kauf zurück. Die zwölf Fahrzeugknoten bleiben auf weiteren Reisen erhalten.

## Nachweise und Grenzen

- `tests/team_progression_test.gd`: 96 Prüfungen mit echten Figuren, Boden-/Luftgegnern, Produktionsanlage, Reparatur, MG-Munitionsverbrauch und Behandlung; außerdem 1–4 Crew, Verbindungsstatus, AFK, Pause und Fahrstreckenmissbrauch.
- `tests/base_research_test.gd`: 132 Prüfungen für reale Forschungswirkungen, Kaufbedingungen und gespeicherte Abhängigkeiten.
- `tests/weapon_research_test.gd`: 56 Prüfungen für Magazine, Nachladen, Streuung, Durchschlag und endliche Vorräte.
- `tests/perimeter_party_test.gd`: 22 Prüfungen für bezahlte Außenanlagen, Rollen-XP und Replikation für P3/P4.
- `tests/research_categories_preview.gd`: 1047 Prüfungen; alle vier Kategorien auf Deutsch und Englisch bei 2560 × 1440 und 960 × 600 gerendert und die neuen Waffen-/Fahrzeugzweige visuell geprüft.
- `tests/combat_rewards_test.gd`, `tests/player_progression_test.gd`, `tests/round_test.gd`: reale Treffer, Projektilbesitz, persönliche Fähigkeiten und alle 20 Solo-Wellen.
- `tests/personal_ui_test.gd`: exakte geteilte Treffer-/Abschusswerte und gebündelte Rollenanzeige.

Die Formeln sind gezielt getestet. Ein vollständiger Balancelauf über zwölf Orte mit vier Menschen und eine erneute Beta auf getrennten Ubuntu-/Windows-Geräten stehen aus.

## Neun Waffenforschungen

Die bestehenden drei Freischaltungen bleiben erhalten. Sechs Ergänzungen ändern die tatsächliche Handwaffe; alle reisen mit der Crew weiter:

| Forschung | Voraussetzung / Welle | Kosten | Wirkung |
| --- | --- | ---: | --- |
| Erweiterte Magazine | Waffentechnik / 2 | 3 | Gewehr 36, Schrot 8, Impuls 16; seltene Varianten 24/6/12 |
| Schneller Verschluss | Erweiterte Magazine / 4 | 4 | Nachladezeit ×0,85; stapelt mit Levins ×0,85 |
| Feinvisierung | Waffentechnik / 3 | 3 | Gewehrstreuung ×0,55 |
| Würgebohrung | Schrotflinte / 6 | 4 | Schrotkegel ×0,72; engere Trefferfläche |
| Durchschlagskondensator | Impulsgewehr / 10 | 6 | Normales Impulsgeschoss trifft bis zu 3 Gegner statt 2; seltenes bis zu 4 statt 3 |
| Patronentaschen | Erweiterte Magazine / 3 | 3 | Reserve 120 → 180 |

Magazin- und Reservetechnik erzeugen ausschließlich leeren Platz. Ganze Entladungen passen auch bei den Impulswaffen ins Magazin. Die bestehende Waffentechnik erhöht Schaden um 20 %; persönlicher Waffendrill stapelt zusätzlich. Der Baum erklärt diese Beziehung im Waffentechnik-Detail, statt einen zweiten gleichartigen Schadensknoten einzubauen.

`tests/weapon_research_test.gd` prüft diese Werte an echten Nachladevorgängen und Geschossen, einschließlich eines physischen Impulsprojektils, das vier Gegner trifft und den fünften unbeschädigt lässt. Die Munitionsversorgungs- und Speicherregressionen prüfen separat Restpatronen angebrochener Kisten und Szenenwechsel.
