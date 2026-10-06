class_name SoloStoryCatalog
extends RefCounted
## Native solo encounters and journal prose. Trigger evidence is supplied by
## the authoritative story controller; this catalog never claims/unlocks/saves.
const L := preload("res://scripts/locale_text.gd")
const VERSION := 1
const EVENTS := ["arrival", "wave_cleared", "relay_completed", "guards_cleared", "site_secured", "find", "npc_rescued", "npc_after"]
const SPEAKERS := ["san", "log", "oskar", "rika", "nora", "levin", "selma"]

const CHAPTERS := {
	"last_shift": {
		"id": "last_shift",
		"title": "I · Die erste Antwort",
		"summary": "Ein einzelner Bunker hält noch. Von hier soll wieder gewarnt werden, bevor die nächste Kolonne anrückt.",
		"objective": "Front, Kern und Funkgerät sichern. Die erste Verbindung führt zur Küste.",
		"arrival_id": "last_shift:arrival",
		"completion_id": "last_shift:secured",
		"npc_ids": [],
		"find_ids": [
			"last_shift:find_1",
			"last_shift:find_2"
		]
	},
	"harbor": {
		"id": "harbor",
		"title": "II · Der Küstenverteiler",
		"summary": "Zwischen stillen Kränen antwortet die Hafenwache. Ihre Liste verbindet Bunker, Sammelpunkte und Menschen.",
		"objective": "Den Hafen sichern und die Verteilerliste für die Inlandroute übernehmen.",
		"arrival_id": "harbor:arrival",
		"completion_id": "harbor:secured",
		"npc_ids": [],
		"find_ids": [
			"harbor:find_1",
			"harbor:find_2"
		]
	},
	"quarry": {
		"id": "quarry",
		"title": "III · Die Leitung im Stein",
		"summary": "Grubenträger Oskar hält den Wartungsweg zur Kabeltrasse offen. Sein eigener Ausgang braucht neue Stützen.",
		"objective": "Den Steinbruch halten und den Funkweg zum Stahlwerk nachvollziehen.",
		"arrival_id": "quarry:arrival",
		"completion_id": "quarry:secured",
		"npc_ids": [
			"oskar"
		],
		"find_ids": [
			"quarry:find_1",
			"quarry:find_2"
		]
	},
	"steelworks": {
		"id": "steelworks",
		"title": "IV · Was noch gebaut werden kann",
		"summary": "Das Stahlwerk ist überwuchert. Unter den Pflanzen liegt die Versorgungslinie, die jeden weiteren Bunker tragen muss.",
		"objective": "Das Stahlwerk sichern und eine belastbare Verbindung zur Froststrecke schaffen.",
		"arrival_id": "steelworks:arrival",
		"completion_id": "steelworks:secured",
		"npc_ids": [],
		"find_ids": [
			"steelworks:find_1",
			"steelworks:find_2"
		]
	},
	"rail_yard": {
		"id": "rail_yard",
		"title": "V · Das Abfahrtsfenster",
		"summary": "Das gefrorene Stellwerk bewahrt die letzten Abfahrtsmeldungen. Auf der Radarkarte fehlt noch die sichere Passage ins Tal.",
		"objective": "Den Rangierhof halten und die Talroute mit der Höhenstation abgleichen.",
		"arrival_id": "rail_yard:arrival",
		"completion_id": "rail_yard:secured",
		"npc_ids": [],
		"find_ids": [
			"rail_yard:find_1",
			"rail_yard:find_2"
		]
	},
	"canyon": {
		"id": "canyon",
		"title": "VI · Die lange Verbindung",
		"summary": "In der Schlucht führen Förderbrücken und Kabel zum Kraftwerk. Ein verschütteter Wartungsweg bewahrt die alte Reparaturmatrix.",
		"objective": "Die Schlucht sichern und den Versorgungsweg zum Kraftwerk offen halten.",
		"arrival_id": "canyon:arrival",
		"completion_id": "canyon:secured",
		"npc_ids": [],
		"find_ids": [
			"canyon:find_1",
			"canyon:find_2"
		]
	},
	"power_station": {
		"id": "power_station",
		"title": "VII · Unter Wasser, auf Empfang",
		"summary": "Rika hält den trockenen Verteiler auf Empfang. Bevor sie zurückkehren kann, müssen Steg und Leitung im Wartungsbereich halten.",
		"objective": "Das Kraftwerk verteidigen und die Verbindung zur Evakuierungsstrecke sichern.",
		"arrival_id": "power_station:arrival",
		"completion_id": "power_station:secured",
		"npc_ids": [
			"rika"
		],
		"find_ids": [
			"power_station:find_1",
			"power_station:find_2"
		]
	},
	"mountain_pass": {
		"id": "mountain_pass",
		"title": "VIII · Niemand fährt ins Leere",
		"summary": "Am Pass treffen Warnungen, bestätigte Fahrzeuge und offene Vermisstenmeldungen zusammen. Die Route muss auch unter dem letzten Angriff halten.",
		"objective": "Den Pass sichern. Danach fehlende Außenposten und Vermisstenmeldungen abschließen.",
		"arrival_id": "mountain_pass:arrival",
		"completion_id": "mountain_pass:secured",
		"npc_ids": [],
		"find_ids": [
			"mountain_pass:find_1",
			"mountain_pass:find_2"
		]
	},
	"dam_vault": {
		"id": "dam_vault",
		"title": "Seitenroute · Die Schleusenwache",
		"summary": "Selma hält sich im Wartungsbereich des Damms. Seine Steuerung bewahrt den Bauplan für den Verbundkern.",
		"objective": "Wachen ausschalten und die Schleusensteuerung sichern.",
		"arrival_id": "dam_vault:arrival",
		"completion_id": "dam_vault:secured",
		"npc_ids": [
			"selma"
		],
		"find_ids": [
			"dam_vault:find_1",
			"dam_vault:find_2"
		]
	},
	"refinery_archive": {
		"id": "refinery_archive",
		"title": "Seitenroute · Die fehlende Ingenieurin",
		"summary": "Noras Wartungsmarken führen ins Formenarchiv. Die bewachte Raffinerie hält Material und präzise Bauunterlagen fest.",
		"objective": "Die Raffineriewachen besiegen und das Formenarchiv sichern.",
		"arrival_id": "refinery_archive:arrival",
		"completion_id": "refinery_archive:secured",
		"npc_ids": [
			"nora"
		],
		"find_ids": [
			"refinery_archive:find_1",
			"refinery_archive:find_2"
		]
	},
	"radar_archive": {
		"id": "radar_archive",
		"title": "Seitenroute · Der Späher auf der Höhe",
		"summary": "Levin hält die Radarstation, weil nur von hier die Zufahrt zum Pass früh genug gesehen werden kann.",
		"objective": "Wachen ausschalten und die Radarstation mit ihren Zieloptiken sichern.",
		"arrival_id": "radar_archive:arrival",
		"completion_id": "radar_archive:secured",
		"npc_ids": [
			"levin"
		],
		"find_ids": [
			"radar_archive:find_1",
			"radar_archive:find_2"
		]
	},
	"buried_archive": {
		"id": "buried_archive",
		"title": "Seitenroute · Das Reparaturarchiv",
		"summary": "Unter der verschütteten Großfabrik liegt ein geschütztes Archiv. Hier wartet keine bestätigte Stimme, aber ein Plan für die Bunker, die noch Schaden tragen.",
		"objective": "Die Werkswachen beseitigen und das Reparaturarchiv sichern.",
		"arrival_id": "buried_archive:arrival",
		"completion_id": "buried_archive:secured",
		"npc_ids": [],
		"find_ids": [
			"buried_archive:find_1",
			"buried_archive:find_2"
		]
	}
}

const ENCOUNTERS := [
	{
		"id": "last_shift:arrival",
		"site": "last_shift",
		"event": "arrival",
		"wave": 0,
		"relay_stage": 0,
		"title": "Eine Leitung zur Küste",
		"body": "SAN-1 empfängt denselben Ruf alle zwölf Sekunden. Keine automatische Kennung: Jemand drückt den Sender von Hand. Erst muss unsere Front halten, dann können wir antworten.",
		"speaker": "san",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "last_shift:wave_3",
		"site": "last_shift",
		"event": "wave_cleared",
		"wave": 3,
		"relay_stage": 0,
		"title": "Zwischen zwei Angriffen",
		"body": "Im Rauschen steckt ein Wort: Hafen. SAN-1 markiert den Ursprung, aber für eine Antwort fehlt noch eine stabile Verbindung. Versorgt erst die Front und erledigt den Funkauftrag.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "last_shift:wave_10",
		"site": "last_shift",
		"event": "wave_cleared",
		"wave": 10,
		"relay_stage": 0,
		"title": "Der Ruf bleibt",
		"body": "Die Angriffe kommen aus derselben Richtung wie die ausgefallene Fernleitung. Im Hafen sitzt der Küstenverteiler; ohne ihn erreichen unsere Warnungen nur die Nachbarhalle.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "last_shift:wave_15",
		"site": "last_shift",
		"event": "wave_cleared",
		"wave": 15,
		"relay_stage": 0,
		"title": "Die Liste wird kürzer",
		"body": "SAN-1 führt Buch über jede Antwort. Hinter drei Kennungen stehen noch leere Felder. Wir senden weiter und halten genug Material für den nächsten Standort zurück.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "last_shift:secured",
		"site": "last_shift",
		"event": "site_secured",
		"wave": 0,
		"relay_stage": 0,
		"title": "Der Ruf hat eine Adresse",
		"body": "Der Küstensender antwortet aus dem Hafen. Dort liegen die alten Verteilerlisten. Wir lassen den Empfänger an und bereiten den Transporter vor; der nächste Bunker darf nicht wieder überrascht werden.",
		"speaker": "san",
		"npc_id": "",
		"priority": 3
	},
	{
		"id": "last_shift:find_1",
		"site": "last_shift",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Zettel am Schichtpult",
		"body": "Letzte handschriftliche Anweisung: „Nicht auf das Netz warten. Wenn jemand zurückruft, Namen und Uhrzeit aufschreiben.“ Darunter stehen drei Initialen, aber keine Rückmeldung.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "last_shift:find_2",
		"site": "last_shift",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Unterbrochene Leitung",
		"body": "Die Fernleitung ist sauber aus der Klemme gezogen. Keine Brandspur, kein gerissenes Kabel. Der Ausfall begann am Verteiler, nicht in diesem Bunker.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "last_shift:relay_first",
		"site": "last_shift",
		"event": "relay_completed",
		"wave": 0,
		"relay_stage": 3,
		"title": "Handschrift auf dem Empfangsstreifen",
		"body": "Der reparierte Empfänger zeichnet „HAFENWACHE“ auf. Die Nachricht wurde nicht für Maschinen gesprochen. Da draußen wartet jemand darauf, dass wir antworten.",
		"speaker": "san",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "last_shift:relay_restored",
		"site": "last_shift",
		"event": "relay_completed",
		"wave": 0,
		"relay_stage": 5,
		"title": "Zwei Übertragungswege",
		"body": "Der Empfänger ist wieder verbunden. Küste und Höhenleitung antworten mit unterschiedlichen Verzögerungen. SAN-1 hält beide Kennungen fest; die beschädigten Knoten müssen wir vor Ort erreichen.",
		"speaker": "san",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "last_shift:relay_transmitting",
		"site": "last_shift",
		"event": "relay_completed",
		"wave": 0,
		"relay_stage": 7,
		"title": "Warnung statt Daueralarm",
		"body": "Der Notruf läuft. SAN-1 sendet Abstände zwischen den Maschinenkolonnen mit, statt nur den Alarm zu wiederholen. Wer antwortet, bekommt Zeit zum Beladen und Ausrücken.",
		"speaker": "san",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "harbor:arrival",
		"site": "harbor",
		"event": "arrival",
		"wave": 0,
		"relay_stage": 0,
		"title": "Hafenwache auf Empfang",
		"body": "„Hier Hafenwache. Das Boot fährt nicht mehr; die Straße ist unser Ausgang.“ Der Posten nennt die Zufahrt zum Bunker und wartet auf Bestätigung. Auf seiner Karte sind noch Menschen eingetragen, keine verlorenen Standorte.",
		"speaker": "san",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "harbor:wave_3",
		"site": "harbor",
		"event": "wave_cleared",
		"wave": 3,
		"relay_stage": 0,
		"title": "Namen statt Nummern",
		"body": "Die Hafenwache fragt nicht nach Anlagenkennungen, sondern nach den Familien an der Küstenstraße. SAN-1 trennt vermisste Meldungen von bestätigten Antworten. Keine leere Zeile wird als Entwarnung gelesen.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "harbor:wave_10",
		"site": "harbor",
		"event": "wave_cleared",
		"wave": 10,
		"relay_stage": 0,
		"title": "Eine offene Schleife",
		"body": "Der Verteiler hört die Staudammleitung, kann aber nicht dorthin senden. Auf der Wartungskarte liegt ein Umweg. Wer Selma erreicht, kann den Kernbauplan und die Menschen im Damm sichern.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "harbor:wave_15",
		"site": "harbor",
		"event": "wave_cleared",
		"wave": 15,
		"relay_stage": 0,
		"title": "Keine Rückfahrt ohne Meldung",
		"body": "„Wenn ihr weiterfahrt, nennt den nächsten sicheren Halt“, fordert die Hafenwache. „Dann schicken wir niemanden auf eine Straße, die ihr noch nicht geprüft habt.“",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "harbor:secured",
		"site": "harbor",
		"event": "site_secured",
		"wave": 0,
		"relay_stage": 0,
		"title": "Die Inlandroute steht",
		"body": "Die Verteilerliste führt über den Basaltbruch ins Stahlwerk. Am Sturmdamm wartet eine zweite Kennung: Selma. Der Hafen bleibt unser Küstenposten, während die Crew den nächsten Abschnitt öffnet.",
		"speaker": "san",
		"npc_id": "",
		"priority": 3
	},
	{
		"id": "harbor:find_1",
		"site": "harbor",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Abfahrtsliste am Kai",
		"body": "Neben jeder Familie steht die Anzahl der Sitzplätze. Die letzte Spalte heißt nicht „abgereist“, sondern „am nächsten Halt angekommen“. Die Hafenwache hat keine dieser Bestätigungen gestrichen.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "harbor:find_2",
		"site": "harbor",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Rote Kreide an der Kaimauer",
		"body": "Ein Pfeil führt zur Straße, ein zweiter zum Wartungsweg des Damms. Neben dem zweiten steht „S · Verbände“. Selmas Weg ist noch auf der Karte.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "quarry:arrival",
		"site": "quarry",
		"event": "arrival",
		"wave": 0,
		"relay_stage": 0,
		"title": "Oskar am Wartungssteg",
		"body": "Die Fernleitung verschwindet unter der Fördertrasse. Grubenträger Oskar antwortet aus dem Wartungsbereich: „Ich halte den Weg frei. Meine Stützen nicht mehr.“ Erst drei abgewehrte Wellen schaffen ein Arbeitsfenster für seinen Zugang.",
		"speaker": "san",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "quarry:wave_3",
		"site": "quarry",
		"event": "wave_cleared",
		"wave": 3,
		"relay_stage": 0,
		"title": "Stützen für Oskars Rückweg",
		"body": "Die dritte Welle ist abgewehrt. Oskar braucht zwei Beton für den beschädigten Wartungszugang. Sprecht ihn an, wenn die Front ruhig ist; seine Aufnahme ersetzt nicht die weitere Verteidigung des Steinbruchs.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "quarry:wave_10",
		"site": "quarry",
		"event": "wave_cleared",
		"wave": 10,
		"relay_stage": 0,
		"title": "Die Wartungsmarke N",
		"body": "Unter einer verschmutzten Schaltkastentür steht ein frisches N. Nora hat hier eine Reparatur begonnen und ihren Rückweg markiert. Die Spur führt zur Raffinerie, nicht in die Grube.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "quarry:wave_15",
		"site": "quarry",
		"event": "wave_cleared",
		"wave": 15,
		"relay_stage": 0,
		"title": "Ein fester Punkt im Netz",
		"body": "Die Küstenkennung bleibt auch während der Angriffe lesbar. Ein gehaltener Steinbruch verbindet die Straße mit der Leitung. Er darf nicht wieder verstummen, sobald wir weiterfahren.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "quarry:secured",
		"site": "quarry",
		"event": "site_secured",
		"wave": 0,
		"relay_stage": 0,
		"title": "Wartungsweg zur Raffinerie",
		"body": "Die Leitung führt weiter zum Stahlwerk. Eine Abzweigung trägt Noras Werkstattnummer und endet an der Schwefelraffinerie. Die Hauptroute ist offen; das Formenarchiv bleibt ein eigener Einsatz.",
		"speaker": "san",
		"npc_id": "",
		"priority": 3
	},
	{
		"id": "quarry:find_1",
		"site": "quarry",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Werkzeugzettel im Schaltkasten",
		"body": "„Neue Kontakte aus dem Formenarchiv. Alte nicht wegwerfen.“ Das N darunter passt zur Wartungsmarke. Nora plante eine Reparatur, keine Flucht ohne Rückkehr.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "quarry:find_2",
		"site": "quarry",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Oskars Trageliste",
		"body": "Die erste Hälfte verzeichnet Werkzeug für die Trasse, die zweite offene Sitzplätze für Grubenarbeiter. Bei Oskars Namen fehlt die Rückmeldung. Darunter steht: „Zuerst die Stütze, dann die Last.“",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "steelworks:arrival",
		"site": "steelworks",
		"event": "arrival",
		"wave": 0,
		"relay_stage": 0,
		"title": "Werkhalle ohne Schichtsignal",
		"body": "Die Uhr am Werkstor steht, die Leitung zur Froststrecke ist noch angeschlossen. SAN-1 prüft, ob am anderen Ende jemand wartet. Für den nächsten Halt brauchen wir mehr als einen offenen Kanal: Material und einen Bunker, der hält.",
		"speaker": "san",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "steelworks:wave_3",
		"site": "steelworks",
		"event": "wave_cleared",
		"wave": 3,
		"relay_stage": 0,
		"title": "Rost auf den Ersatzteilen",
		"body": "An den Lagerkarten stehen noch die Bunkerkennungen. Einige Kisten wurden nie abgeholt. SAN-1 übernimmt die Zuordnung; was wir bergen, muss am nächsten Halt tatsächlich ankommen.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "steelworks:wave_10",
		"site": "steelworks",
		"event": "wave_cleared",
		"wave": 10,
		"relay_stage": 0,
		"title": "Der Winterkanal",
		"body": "Aus dem Rangierhof kommen kurze Morsegruppen. Eine Stimme spart ihre Worte: „Fahrbahn frei. Tal noch unbestätigt.“ Die Antworten haben einen Absender; jetzt braucht er unseren Wegbericht.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "steelworks:wave_15",
		"site": "steelworks",
		"event": "wave_cleared",
		"wave": 15,
		"relay_stage": 0,
		"title": "Ein Werk bleibt zurück",
		"body": "Wir bauen hier für die Besatzung, die nach uns kommt. Kein Raum wandert mit dem Konvoi. Eine sichere Anlage verkürzt den nächsten Rückweg für jede Crew, die Material braucht.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "steelworks:secured",
		"site": "steelworks",
		"event": "site_secured",
		"wave": 0,
		"relay_stage": 0,
		"title": "Antwort aus dem Rangierhof",
		"body": "Der Stellwerkskanal überträgt noch die bestätigten Gleis- und Straßenabschnitte. Die Strecke ins Tal bleibt unbestätigt. Wir beladen den Transporter und folgen der Versorgungslinie über die Frostgrenze.",
		"speaker": "san",
		"npc_id": "",
		"priority": 3
	},
	{
		"id": "steelworks:find_1",
		"site": "steelworks",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Kreidemarkierung am Lager",
		"body": "Über der alten Ausgabestelle steht „Nicht alles auf ein Fahrzeug“. Darunter ist Platz für mehrere Abfahrtszeiten. Der Plan war eine Folge von Fahrten, kein einziger letzter Transport.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "steelworks:find_2",
		"site": "steelworks",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Kupferlasche mit Gleisnummer",
		"body": "Die Gleisnummer gehört zur Froststrecke. Die Lasche steckt zwischen zwei noch brauchbaren Kontakten. Jemand hat das Stellwerk als nächsten Verbindungspunkt festgehalten.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "rail_yard:arrival",
		"site": "rail_yard",
		"event": "arrival",
		"wave": 0,
		"relay_stage": 0,
		"title": "Stellwerk, Kanal drei",
		"body": "Das Stellwerksbuch führt die Zufahrt zur Schlucht und einen ausstehenden Bericht von den Radarhöhen. Levin hat dort als Letzter Stellung bezogen. SAN-1 sucht seine Kennung zwischen den alten Zugmeldungen.",
		"speaker": "san",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "rail_yard:wave_3",
		"site": "rail_yard",
		"event": "wave_cleared",
		"wave": 3,
		"relay_stage": 0,
		"title": "Stillstand ist keine Deckung",
		"body": "Die Schienen glänzen zwischen den Schneefeldern. Eine freie Zufahrt allein reicht nicht: Jeder Halt braucht Wachen. Ein Abfahrtsfenster entsteht nur, wenn jemand die anrückenden Maschinen rechtzeitig meldet.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "rail_yard:wave_10",
		"site": "rail_yard",
		"event": "wave_cleared",
		"wave": 10,
		"relay_stage": 0,
		"title": "Levins letzte Peilung",
		"body": "Im Stellwerksbuch steht Levins Peilung zur Radarstation. Danach keine Entwarnung. SAN-1 streicht den Eintrag nicht als Verlust; ohne Bestätigung bleibt Levin auf der Liste.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "rail_yard:wave_15",
		"site": "rail_yard",
		"event": "wave_cleared",
		"wave": 15,
		"relay_stage": 0,
		"title": "Zeit statt Geschwindigkeit",
		"body": "Ein schneller Transport hilft nicht, wenn der nächste Halt noch bewacht ist. SAN-1 schreibt unsere bestätigten Streckenabschnitte neben die alten Abfahrtszeiten. So kann die nächste Besatzung selbst prüfen, wann sie aufbrechen kann.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "rail_yard:secured",
		"site": "rail_yard",
		"event": "site_secured",
		"wave": 0,
		"relay_stage": 0,
		"title": "Ein Weg ins Tal",
		"body": "Die Straße zur Eisenschlucht ist bestätigt. Die Höhenstation bleibt ein erreichbarer Seitenweg; dort können wir Levin und die Zieloptiken sichern. Der Rangierhof ist jetzt ein verlässlicher Sammelpunkt.",
		"speaker": "san",
		"npc_id": "",
		"priority": 3
	},
	{
		"id": "rail_yard:find_1",
		"site": "rail_yard",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Stellwerksbuch",
		"body": "Die letzte reguläre Schicht ist durchgestrichen. Darunter beginnt eine neue Liste: Fahrzeuge, Namen, Tankstand. Die Stellwerksbesatzung hat den Ablauf auf Straßenverkehr umgestellt.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "rail_yard:find_2",
		"site": "rail_yard",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Gefaltete Radarskizze",
		"body": "Eine schmale Sichtlinie verbindet Höhenstation und Pass. Levin hat tote Winkel eingezeichnet, keine Ziele. Seine Karte soll Menschen durchbringen, nicht nur Maschinen treffen.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "canyon:arrival",
		"site": "canyon",
		"event": "arrival",
		"wave": 0,
		"relay_stage": 0,
		"title": "Die Leitung über der Schlucht",
		"body": "Die Brücken tragen noch eine Leitung zum Kraftwerk. Jede Unterbrechung hier trennt Tal und Höhenposten. SAN-1 zählt die Knoten auf der Karte; die Großfabrik darunter antwortet nicht.",
		"speaker": "san",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "canyon:wave_3",
		"site": "canyon",
		"event": "wave_cleared",
		"wave": 3,
		"relay_stage": 0,
		"title": "Kein Platz für eine Umkehr",
		"body": "Zwischen den Felsen gibt es wenig Ausweichraum. SAN-1 hält die bestätigten Zufahrten fest. Der Konvoi braucht eine gedeckte Reparaturstelle, bevor die nächste Fahrt beginnt.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "canyon:wave_10",
		"site": "canyon",
		"event": "wave_cleared",
		"wave": 10,
		"relay_stage": 0,
		"title": "Ein Werkskanal im Rauschen",
		"body": "Der alte Fabrikkanal sendet nur eine wiederholte Prüfkennung. Kein Mensch antwortet. Der Wartungsweg ist auf der Karte; was dort noch liegt, müssen wir selbst prüfen.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "canyon:wave_15",
		"site": "canyon",
		"event": "wave_cleared",
		"wave": 15,
		"relay_stage": 0,
		"title": "Warnung von oben",
		"body": "Die Höhenleitung überträgt früher als die Talroute. SAN-1 vergleicht die Zeitstempel, statt einen der Kanäle abzuschalten. Zusammen geben sie der Besatzung am Kraftwerk mehr Vorlauf.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "canyon:secured",
		"site": "canyon",
		"event": "site_secured",
		"wave": 0,
		"relay_stage": 0,
		"title": "Strom aus dem Tal",
		"body": "Das Kraftwerk liegt am Ende der Talroute. Die Wartungskarte zeigt einen zweiten Weg zur verschütteten Großfabrik. Dort lagert die Reparaturmatrix, mit der beschädigte Kerne länger versorgt werden können.",
		"speaker": "san",
		"npc_id": "",
		"priority": 3
	},
	{
		"id": "canyon:find_1",
		"site": "canyon",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Schachtplan der Großfabrik",
		"body": "Ein Wartungsstempel bezeichnet das Reparaturarchiv als trockenen Raum unter dem Hauptwerk. Die eingezeichnete Treppe ist verschüttet; der Plan verspricht keinen freien Zugang.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "canyon:find_2",
		"site": "canyon",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Kabelmarken an der Brücke",
		"body": "Eine Marke nennt das Kraftwerk, die zweite den Pass. Beide hängen an derselben Strecke. Stromversorgung und Warnung wurden getrennt geführt, damit nicht ein einzelner Schaden alles beendet.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "power_station:arrival",
		"site": "power_station",
		"event": "arrival",
		"wave": 0,
		"relay_stage": 0,
		"title": "Rika am trockenen Verteiler",
		"body": "„Die Kennung vom Pass kommt durch. Mein Rückweg noch nicht.“ Elektrikerin Rika hält den trockenen Verteiler auf Empfang. Nach drei abgewehrten Wellen kann die Crew den Wartungssteg und seine Leitung für sie sichern.",
		"speaker": "rika",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "power_station:wave_3",
		"site": "power_station",
		"event": "wave_cleared",
		"wave": 3,
		"relay_stage": 0,
		"title": "Stahl für den Wartungssteg",
		"body": "Die dritte Welle ist abgewehrt. Rika braucht zwei Stahl, um den trockenen Wartungssteg und die Leitungsführung zu reparieren. Sprecht sie in einer ruhigen Phase an; der Kraftwerksbunker muss danach weiter gehalten werden.",
		"speaker": "rika",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "power_station:wave_10",
		"site": "power_station",
		"event": "wave_cleared",
		"wave": 10,
		"relay_stage": 0,
		"title": "Der Sammelpunkt antwortet",
		"body": "Vom Pass kommt eine kurze Frage: „Wie viele Fahrzeuge folgen?“ SAN-1 nennt keine Zahl, bevor die Standorte sie bestätigt haben. Eine geschätzte Liste würde Menschen zurücklassen.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "power_station:wave_15",
		"site": "power_station",
		"event": "wave_cleared",
		"wave": 15,
		"relay_stage": 0,
		"title": "Die letzte Talwache",
		"body": "Jede Meldung vom Pass läuft noch durch diesen Bunker. Die letzten Angriffe entscheiden, ob die Strecke nach unserer Abfahrt bewacht bleibt. Vorräte und Reparaturen gehören jetzt zur Route, nicht nur zu dieser Schicht.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "power_station:secured",
		"site": "power_station",
		"event": "site_secured",
		"wave": 0,
		"relay_stage": 0,
		"title": "Die Strecke zum Pass ist bestätigt",
		"body": "Tal- und Höhenkennung stimmen überein. Der nächste Halt ist der Gebirgspass. Die Crew lässt den Standort versorgt zurück; unsere Warnungen brauchen auch nach der Abfahrt einen Empfänger im Tal.",
		"speaker": "san",
		"npc_id": "",
		"priority": 3
	},
	{
		"id": "power_station:find_1",
		"site": "power_station",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Rikas Wasserstandsprotokoll",
		"body": "Der letzte Eintrag fordert nicht die Rettung der Turbinen, sondern einen trockenen Wartungsweg. Rika hat daneben zwei neue Stahlteile eingezeichnet. Ihre Reparatur soll eine Person zurückbringen, nicht eine ganze Anlage ersetzen.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "power_station:find_2",
		"site": "power_station",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Empfangsbestätigung vom Pass",
		"body": "Der Streifen ist durchfeuchtet, aber die Kennung lesbar. Dahinter steht: „Warten auf Talposten.“ Die Evakuierungsstrecke wurde nie als verloren bestätigt.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "mountain_pass:arrival",
		"site": "mountain_pass",
		"event": "arrival",
		"wave": 0,
		"relay_stage": 0,
		"title": "Der hohe Empfänger",
		"body": "Der Pass hört Küste und Tal. Noch ist das kein freier Weg: Die anrückenden Maschinen stehen zwischen uns und dem Sammelpunkt. SAN-1 legt die bestätigten Meldungen nebeneinander. Keine Kennung wird stillschweigend als gerettet gewertet.",
		"speaker": "san",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "mountain_pass:wave_3",
		"site": "mountain_pass",
		"event": "wave_cleared",
		"wave": 3,
		"relay_stage": 0,
		"title": "Antworten durch das Gewitter",
		"body": "Die Höhenkennung kommt mit Aussetzern, die Talverbindung bleibt lesbar. Zwei Wege tragen dieselbe Warnung. SAN-1 vergleicht die Meldungen, damit ein Blitz die Besatzung nicht wieder allein lässt.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "mountain_pass:wave_10",
		"site": "mountain_pass",
		"event": "wave_cleared",
		"wave": 10,
		"relay_stage": 0,
		"title": "Die offenen Namen",
		"body": "Auf der Empfangsliste stehen bestätigte Standorte und noch offene Namen getrennt. Wer schon gerettet wurde, braucht keinen zweiten Platz. Wer noch fehlt, bekommt keine erfundene Ankunftszeit.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "mountain_pass:wave_15",
		"site": "mountain_pass",
		"event": "wave_cleared",
		"wave": 15,
		"relay_stage": 0,
		"title": "Das letzte Abfahrtsfenster",
		"body": "Die schwere Kolonne nähert sich. SAN-1 hält die Übertragung kurz: Front, Munition, freie Zufahrt. Erst nach dem letzten abgewehrten Angriff bestätigen wir den Pass als sicheren Halt.",
		"speaker": "san",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "mountain_pass:secured",
		"site": "mountain_pass",
		"event": "site_secured",
		"wave": 0,
		"relay_stage": 0,
		"title": "Die Hauptroute hält",
		"body": "Der Pass ist gesichert. SAN-1 sendet die bestätigten Halte für jede nachfolgende Fahrt. Offene Außenposten bleiben auf der Karte, bis auch ihre Besatzungen und Archive gesichert sind; der Korridor ist der Anfang ihrer Rückkehr.",
		"speaker": "san",
		"npc_id": "",
		"priority": 3
	},
	{
		"id": "mountain_pass:find_1",
		"site": "mountain_pass",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Liste der Sammelpunkte",
		"body": "Keine große Zielmarke: Der Plan nennt mehrere kleine, bewachte Halte. Jede bestätigte Ankunft braucht eine Unterschrift. Der Weg bleibt nur offen, wenn jemand an diesen Punkten zurückbleibt.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "mountain_pass:find_2",
		"site": "mountain_pass",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Freie Zeile am Ende",
		"body": "Unter den alten Kennungen ist eine Zeile frei. SAN-1 trägt dort erst einen Standort ein, wenn er wirklich gesichert ist. Das Netz wächst aus bestätigten Antworten.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "dam_vault:arrival",
		"site": "dam_vault",
		"event": "arrival",
		"wave": 0,
		"relay_stage": 0,
		"title": "Selmas Kennung",
		"body": "Vom Wartungskanal kommt eine ruhige Stimme: „Ich bleibe bei den Verletzten.“ Selma braucht einen Beton, um den medizinischen Zugang abzustützen. Solange Wachen stehen, kann die Crew ihre Aufnahme nicht sicher abschließen.",
		"speaker": "selma",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "dam_vault:secured",
		"site": "dam_vault",
		"event": "site_secured",
		"wave": 0,
		"relay_stage": 0,
		"title": "Die Schleusensteuerung ist gesichert",
		"body": "Die Steuerung ist gesichert. Der Verbundkern-Bauplan liegt im Kampagnenarchiv und stärkt zukünftige Bunker. Selmas Behandlungsliste und ihre persönliche Aufnahme werden getrennt von der Schleusenmeldung geführt.",
		"speaker": "san",
		"npc_id": "",
		"priority": 3
	},
	{
		"id": "dam_vault:find_1",
		"site": "dam_vault",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Behandlungsliste hinter der Tür",
		"body": "Selma hat Vorräte und Behandlungen nebeneinander notiert. Kein Name ist wegen fehlendem Material gestrichen. Die Liste endet mit „Zugang sichern, dann verlegen“.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "dam_vault:find_2",
		"site": "dam_vault",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Schutzrippen im Wartungsplan",
		"body": "Der Kernplan zeigt massive Rippen zwischen Steuerung und Druckwand. Er trägt die Freigabe des Dammbetriebs. Nach gesicherter Steuerung kann die Crew ihn für neue Bunker übernehmen.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "dam_vault:guards_clear",
		"site": "dam_vault",
		"event": "guards_cleared",
		"wave": 0,
		"relay_stage": 0,
		"title": "Der Gang ist frei",
		"body": "Die letzte Wache ist ausgeschaltet. Selma wartet weiter im Wartungsbereich. Jetzt kann die Crew die Schleusensteuerung sichern; erst danach ist der Standort als gerettet bestätigt.",
		"speaker": "selma",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "dam_vault:rescue_selma",
		"site": "dam_vault",
		"event": "npc_rescued",
		"wave": 0,
		"relay_stage": 0,
		"title": "Selma nimmt die Behandlungsliste mit",
		"body": "Der Zugang hält. „Ich komme mit. Aber wir lassen an jedem Halt einen sicheren Platz für Verletzte.“ Selma nimmt ihre Liste und bestätigt ihre Aufnahme. Die Schleusensteuerung muss unabhängig davon gesichert werden.",
		"speaker": "selma",
		"npc_id": "selma",
		"priority": 3
	},
	{
		"id": "refinery_archive:arrival",
		"site": "refinery_archive",
		"event": "arrival",
		"wave": 0,
		"relay_stage": 0,
		"title": "Nora hinter dem Werkstor",
		"body": "„Die Formen sind vollständig. Die Notverriegelung klemmt.“ Nora braucht zwei Stahl für den Werkstattausgang. Sobald keine Wachen mehr im Weg stehen, kann die Crew ihre Rückkehr vorbereiten.",
		"speaker": "nora",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "refinery_archive:secured",
		"site": "refinery_archive",
		"event": "site_secured",
		"wave": 0,
		"relay_stage": 0,
		"title": "Das Formenarchiv ist geborgen",
		"body": "Die Raffinerie und ihre Fertigungsunterlagen sind gesichert. Präzisionsformen verkürzen die Produktion an späteren Standorten. Nora führt das Prüfblatt weiter. Eine persönliche Aufnahme wird auf der Personenliste bestätigt, nicht durch die Archivfreigabe.",
		"speaker": "san",
		"npc_id": "",
		"priority": 3
	},
	{
		"id": "refinery_archive:find_1",
		"site": "refinery_archive",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Noras Prüfblatt",
		"body": "Neben jeder Form steht ein Maß und eine Nachprüfung. Eine eilige Reparatur wurde verworfen, weil sie später mehr Material verbraucht hätte. Nora hat die brauchbaren Sätze vollständig gehalten.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "refinery_archive:find_2",
		"site": "refinery_archive",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Unversandte Werksmeldung",
		"body": "„Formenarchiv erhalten. Benötige gesicherte Abholung.“ Die Meldung liegt mehrfach am Sendeplatz. Die Ingenieurin blieb bei den Unterlagen, weil ohne sie der nächste Bunker dieselben Fehler wiederholen würde.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "refinery_archive:guards_clear",
		"site": "refinery_archive",
		"event": "guards_cleared",
		"wave": 0,
		"relay_stage": 0,
		"title": "Das Archiv wartet",
		"body": "Keine Raffineriewache steht mehr im Weg. Das Archiv muss noch gesichert werden. Nora prüft die Unterlagen, während die Crew die Freigabe an der Anlage abschließt.",
		"speaker": "nora",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "refinery_archive:rescue_nora",
		"site": "refinery_archive",
		"event": "npc_rescued",
		"wave": 0,
		"relay_stage": 0,
		"title": "Nora verlässt die Werkstatt",
		"body": "Die neue Verriegelung sitzt. „Beim nächsten Bunker machen wir es gleich richtig.“ Nora bestätigt ihre Aufnahme und nimmt das Prüfblatt mit. Das Formenarchiv wird erst durch die Sicherung der Anlage übernommen.",
		"speaker": "nora",
		"npc_id": "nora",
		"priority": 3
	},
	{
		"id": "radar_archive:arrival",
		"site": "radar_archive",
		"event": "arrival",
		"wave": 0,
		"relay_stage": 0,
		"title": "Levins Sichtlinie",
		"body": "„Ich sehe die Talstraße. Für meinen Rückweg fehlt Deckung.“ Levin fordert eine Munitionskiste für die Stellung. Erst ohne lebende Wachen kann die Crew den Auftrag und seine Aufnahme sicher abschließen.",
		"speaker": "levin",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "radar_archive:secured",
		"site": "radar_archive",
		"event": "site_secured",
		"wave": 0,
		"relay_stage": 0,
		"title": "Die Höhenmeldung ist bestätigt",
		"body": "Die Radarstation und ihre Zieloptiken sind gesichert. Die nächste Höhenwarnung hat wieder einen verlässlichen Absender. Levins eigene Rückmeldung bleibt ein gesonderter Eintrag; eine geborgene Optik wird nicht als geretteter Mensch gezählt.",
		"speaker": "san",
		"npc_id": "",
		"priority": 3
	},
	{
		"id": "radar_archive:find_1",
		"site": "radar_archive",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Peilkarte mit Strichen",
		"body": "Levin hat jede beobachtete Kolonne einzeln markiert. Zwischen den Strichen liegen freie Zeitfenster. Seine Karte kennt keine sichere Straße ohne Datum und Beobachter.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "radar_archive:find_2",
		"site": "radar_archive",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Verpackte Zieloptiken",
		"body": "Die Gläser liegen bereits im Transportschutz. Ein Zettel nennt Geschütze und Flak als Empfänger. Erst die gesicherte Station erlaubt, den Satz mitzunehmen.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "radar_archive:guards_clear",
		"site": "radar_archive",
		"event": "guards_cleared",
		"wave": 0,
		"relay_stage": 0,
		"title": "Sicht frei zur Anlage",
		"body": "Die Wachen sind ausgeschaltet. Levin hält noch den Beobachtungskanal offen. Sichert die Anlage, damit die Optiken und sein Rückweg offiziell freigegeben werden.",
		"speaker": "levin",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "radar_archive:rescue_levin",
		"site": "radar_archive",
		"event": "npc_rescued",
		"wave": 0,
		"relay_stage": 0,
		"title": "Levin verlässt den Beobachtungsposten",
		"body": "Die Deckung ist versorgt. „Jetzt kenne ich den Weg auch von unten.“ Levin bestätigt seine Aufnahme und faltet die Peilkarte. Die Station bleibt ein eigenes Sicherungsziel.",
		"speaker": "levin",
		"npc_id": "levin",
		"priority": 3
	},
	{
		"id": "buried_archive:arrival",
		"site": "buried_archive",
		"event": "arrival",
		"wave": 0,
		"relay_stage": 0,
		"title": "Eine Prüfkennung, keine Stimme",
		"body": "Der Archivkanal wiederholt seine Kennung. SAN-1 führt sie nicht als Überlebendenmeldung. Wir sichern die Anlage, weil ihre Reparaturpläne an den anderen Bunkern gebraucht werden.",
		"speaker": "san",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "buried_archive:secured",
		"site": "buried_archive",
		"event": "site_secured",
		"wave": 0,
		"relay_stage": 0,
		"title": "Die Matrix geht mit",
		"body": "Das Archiv ist gesichert. Die Reparaturmatrix liegt im Kampagnenbestand und erhöht den Nutzen späterer Kernreparaturen. SAN-1 beendet die automatische Prüfkennung; auf der Menschenliste bleibt kein erfundener Name.",
		"speaker": "san",
		"npc_id": "",
		"priority": 3
	},
	{
		"id": "buried_archive:find_1",
		"site": "buried_archive",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Reparaturfolge im Archiv",
		"body": "Der Plan beginnt mit dem bereits vorhandenen Schaden. Keine Zeile verspricht einen unversehrten Kern. Material soll gezielter eingesetzt werden, damit weniger Fahrten nur für Reparaturen nötig sind.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "buried_archive:find_2",
		"site": "buried_archive",
		"event": "find",
		"wave": 0,
		"relay_stage": 0,
		"title": "Abschaltvermerk",
		"body": "„Prüfkennung bis zur gesicherten Übernahme senden.“ Der letzte Vermerk stammt vom Wartungsdienst. Die Wiederholung war ein Wegweiser für Nachfolger, kein Hilferuf einer eingeschlossenen Person.",
		"speaker": "log",
		"npc_id": "",
		"priority": 1
	},
	{
		"id": "buried_archive:guards_clear",
		"site": "buried_archive",
		"event": "guards_cleared",
		"wave": 0,
		"relay_stage": 0,
		"title": "Übernahme noch offen",
		"body": "Die Werkswachen sind ausgeschaltet. Das Archiv sendet weiter, bis die Crew die Anlage gesichert hat. Sichert die Reparaturmatrix am markierten Ziel.",
		"speaker": "san",
		"npc_id": "",
		"priority": 2
	},
	{
		"id": "quarry:rescue_oskar",
		"site": "quarry",
		"event": "npc_rescued",
		"wave": 0,
		"relay_stage": 0,
		"title": "Oskar tritt aus dem Wartungsbereich",
		"body": "Die neuen Stützen halten. „Ich nehme die erste Last. Aber niemand trägt allein für zwei.“ Oskar meldet sich bei der Crew zurück. Die weitere Verteidigung des Steinbruchs bleibt notwendig.",
		"speaker": "oskar",
		"npc_id": "oskar",
		"priority": 3
	},
	{
		"id": "power_station:rescue_rika",
		"site": "power_station",
		"event": "npc_rescued",
		"wave": 0,
		"relay_stage": 0,
		"title": "Rika kommt über den trockenen Steg",
		"body": "Steg und Leitung sind repariert. „Ich lasse den Verteiler markiert. Die nächste Wache soll ihn finden.“ Rika bestätigt ihre Aufnahme. Ihre Rückkehr bedeutet noch keinen vollständig gesicherten Kraftwerksbunker.",
		"speaker": "rika",
		"npc_id": "rika",
		"priority": 3
	},
	{
		"id": "quarry:after_oskar",
		"site": "quarry",
		"event": "npc_after",
		"wave": 0,
		"relay_stage": 0,
		"title": "Oskar · Rückmeldung",
		"body": "Bei mir steht neben jeder Last der Zielort. Was wir verladen, soll am nächsten Bunker ankommen, nicht nur vom Boden verschwinden.",
		"speaker": "oskar",
		"npc_id": "oskar",
		"priority": 1
	},
	{
		"id": "power_station:after_rika",
		"site": "power_station",
		"event": "npc_after",
		"wave": 0,
		"relay_stage": 0,
		"title": "Rika · Rückmeldung",
		"body": "Zwei Wege für dieselbe Warnung. Wenn einer ausfällt, prüfen wir den zweiten, bevor wir jemanden als verloren melden.",
		"speaker": "rika",
		"npc_id": "rika",
		"priority": 1
	},
	{
		"id": "refinery_archive:after_nora",
		"site": "refinery_archive",
		"event": "npc_after",
		"wave": 0,
		"relay_stage": 0,
		"title": "Nora · Rückmeldung",
		"body": "Ein gutes Maß spart uns die nächste Nacharbeit. Wenn ihr baut, lasst den zweiten Blick nicht aus.",
		"speaker": "nora",
		"npc_id": "nora",
		"priority": 1
	},
	{
		"id": "dam_vault:after_selma",
		"site": "dam_vault",
		"event": "npc_after",
		"wave": 0,
		"relay_stage": 0,
		"title": "Selma · Rückmeldung",
		"body": "Nennt mir den letzten sicheren Halt, wenn jemand zurückbleibt. Nicht nur den Ort, an dem ihr ihn zum letzten Mal gesehen habt.",
		"speaker": "selma",
		"npc_id": "selma",
		"priority": 1
	},
	{
		"id": "radar_archive:after_levin",
		"site": "radar_archive",
		"event": "npc_after",
		"wave": 0,
		"relay_stage": 0,
		"title": "Levin · Rückmeldung",
		"body": "Eine Straße ist nicht sicher, weil sie gerade leer aussieht. Meldet, wann ihr sie geprüft habt. Ich ergänze den Beobachter.",
		"speaker": "levin",
		"npc_id": "levin",
		"priority": 1
	}
]

const PROFILES := [
	{
		"id": "oskar",
		"site": "quarry",
		"name": "Oskar",
		"role": "Grubenträger",
		"detail": "Oskar brachte Werkzeug und Verletzte durch die Grube. Beim Ausfall blieb er, weil der Wartungsweg sonst mit den alten Stützen nachgeben würde. Er zählt Lasten, nicht Heldentaten.",
		"job_title": "Wartungszugang abstützen",
		"cost": {
			"concrete": 2
		},
		"min_wave": 3,
		"intro": [
			"Ich bin Oskar. Wenn dieser Zugang fällt, kommt hier keiner mehr raus. Zwei Beton für die Stützen, dann gehe ich mit.",
			"Wehrt erst drei Wellen ab und wartet, bis keine Wache mehr steht. Unter Beschuss baue ich keine neue Last auf eine kaputte Stütze."
		],
		"rescue": [
			"Die Stützen sitzen. Ich habe meine Trageliste und komme zur Crew. Der Steinbruch braucht trotzdem weiter eine Front."
		],
		"after": [
			"Bei mir steht neben jeder Last der Zielort. Was wir verladen, soll am nächsten Bunker ankommen, nicht nur vom Boden verschwinden."
		],
		"intro_id": "quarry:arrival",
		"rescue_id": "quarry:rescue_oskar",
		"after_id": "quarry:after_oskar"
	},
	{
		"id": "rika",
		"site": "power_station",
		"name": "Rika",
		"role": "Elektrikerin und Funkerin",
		"detail": "Rika hielt den trockenen Verteiler in Betrieb, während die Turbinenhallen vollliefen. Sie markiert jeden brauchbaren Kontakt für die nächste Wache und verwechselt eine Prüfkennung nie mit einer Stimme.",
		"job_title": "Trockenen Steg und Leitung reparieren",
		"cost": {
			"steel": 2
		},
		"min_wave": 3,
		"intro": [
			"Rika. Ich höre den Pass, aber mein Wartungssteg hält nicht mehr. Zwei Stahl für Steg und Leitung, dann kann ich zurück.",
			"Nach drei abgewehrten Wellen reparieren wir in einer ruhigen Phase. Wenn noch Wachen leben, bleibe ich am Verteiler."
		],
		"rescue": [
			"Der Steg ist trocken und die Leitung befestigt. Ich komme mit. Der Verteiler bleibt beschriftet, damit die nächste Besatzung übernehmen kann."
		],
		"after": [
			"Zwei Wege für dieselbe Warnung. Wenn einer ausfällt, prüfen wir den zweiten, bevor wir jemanden als verloren melden."
		],
		"intro_id": "power_station:arrival",
		"rescue_id": "power_station:rescue_rika",
		"after_id": "power_station:after_rika"
	},
	{
		"id": "nora",
		"site": "refinery_archive",
		"name": "Nora",
		"role": "Ingenieurin",
		"detail": "Nora blieb im Formenarchiv, weil die geprüften Unterlagen mit jeder verlorenen Schicht schwerer zu ersetzen wären. Ihr eigener Werkstattausgang wurde zur Falle.",
		"job_title": "Notverriegelung der Werkstatt richten",
		"cost": {
			"steel": 2
		},
		"min_wave": 0,
		"intro": [
			"Nora. Die Formen sind geprüft, aber die Notverriegelung klemmt. Zwei Stahl richten den Ausgang.",
			"Erst die Wachen. Dann kann ich die Verriegelung richten und meine Aufnahme bestätigen. Das Archiv sichert ihr separat an der Anlage."
		],
		"rescue": [
			"Die Verriegelung hält. Ich nehme das Prüfblatt und komme mit. Die Formen gehören erst nach gesicherter Übernahme zum Kampagnenbestand."
		],
		"after": [
			"Ein gutes Maß spart uns die nächste Nacharbeit. Wenn ihr baut, lasst den zweiten Blick nicht aus."
		],
		"intro_id": "refinery_archive:arrival",
		"rescue_id": "refinery_archive:rescue_nora",
		"after_id": "refinery_archive:after_nora"
	},
	{
		"id": "selma",
		"site": "dam_vault",
		"name": "Selma",
		"role": "Sanitäterin",
		"detail": "Selma blieb bei den Verletzten im Wartungsbereich. Ihre Liste trennt Behandlung und bestätigte Verlegung; eine freie Tür allein ist für sie noch kein sicherer Rückweg.",
		"job_title": "Medizinischen Zugang stabilisieren",
		"cost": {
			"concrete": 1
		},
		"min_wave": 0,
		"intro": [
			"Selma hier. Ein Beton stabilisiert den medizinischen Zugang. Ich verlasse den Wartungsbereich erst, wenn der Weg trägt.",
			"Solange Wachen stehen, kann ich nicht mitkommen. Sichert erst den Weg; die Schleusensteuerung bleibt euer eigener Auftrag."
		],
		"rescue": [
			"Der Zugang hält. Ich nehme meine Behandlungsliste und komme zur Crew. Für den Damm fehlt gegebenenfalls noch die gesicherte Steuerung."
		],
		"after": [
			"Nennt mir den letzten sicheren Halt, wenn jemand zurückbleibt. Nicht nur den Ort, an dem ihr ihn zum letzten Mal gesehen habt."
		],
		"intro_id": "dam_vault:arrival",
		"rescue_id": "dam_vault:rescue_selma",
		"after_id": "dam_vault:after_selma"
	},
	{
		"id": "levin",
		"site": "radar_archive",
		"name": "Levin",
		"role": "Späher",
		"detail": "Levin hielt die Höhenstellung, um freie Zeitfenster auf der Talstraße zu melden. Sein Beobachtungsposten ist nützlich, sein eigener Rückweg aber unversorgt.",
		"job_title": "Deckung für den Rückweg versorgen",
		"cost": {
			"ammo": 1
		},
		"min_wave": 0,
		"intro": [
			"Levin. Ich brauche eine echte Munitionskiste für die Deckung meines Rückwegs. Die leere Verpackung reicht nicht.",
			"Wenn keine Wache mehr lebt, versorgen wir die Stellung und ich komme mit. Die Zieloptiken nehmt ihr über die gesicherte Radarstation mit."
		],
		"rescue": [
			"Die Deckung ist versorgt. Ich nehme die Peilkarte und bestätige meine Aufnahme. Die Anlage bleibt ein eigenes Sicherungsziel."
		],
		"after": [
			"Eine Straße ist nicht sicher, weil sie gerade leer aussieht. Meldet, wann ihr sie geprüft habt. Ich ergänze den Beobachter."
		],
		"intro_id": "radar_archive:arrival",
		"rescue_id": "radar_archive:rescue_levin",
		"after_id": "radar_archive:after_levin"
	}
]

static func chapter(site_id: String) -> Dictionary:
	if not CHAPTERS.has(site_id): return {}
	var result := _translated(CHAPTERS[site_id])
	result.site_kind = CampaignCatalog.site_kind(site_id)
	var location := CampaignCatalog.node(site_id)
	result.environment = str(location.get("environment", ""))
	result.blueprint = str(location.get("blueprint", ""))
	return result

static func profiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for person: Dictionary in PROFILES: result.append(_translated(person))
	return result

static func profile(id: String) -> Dictionary:
	for person: Dictionary in PROFILES:
		if person.id == id: return _translated(person)
	return {}

static func entry_ids() -> Array[String]:
	var result: Array[String] = []
	for row: Dictionary in ENCOUNTERS: result.append(str(row.id))
	return result

static func entry(id: String) -> Dictionary:
	for row: Dictionary in ENCOUNTERS:
		if row.id == id: return _translated(row)
	return {}

static func entries_for(site_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not CHAPTERS.has(site_id): return result
	for row: Dictionary in ENCOUNTERS:
		if row.site == site_id: result.append(_translated(row))
	return result

static func _translated(record: Dictionary) -> Dictionary:
	var result := record.duplicate(true)
	for field: String in ["title", "summary", "objective", "body", "name", "role", "detail", "job_title"]:
		if result.get(field) is String: result[field] = L.text(str(result[field]))
	for field: String in ["intro", "rescue", "after"]:
		if not result.get(field) is Array: continue
		var lines: Array[String] = []
		for line: String in result[field]: lines.append(L.text(line))
		result[field] = lines
	return result

static func _integer(value: Variant, low: int, high: int) -> bool:
	return value is int and int(value) >= low and int(value) <= high

static func _completed(value: Variant) -> bool:
	if not value is Array or value.size() > CampaignCatalog.NODES.size(): return false
	var seen: Array[String] = []
	for site in value:
		if not site is String or not CHAPTERS.has(site) or seen.has(site): return false
		seen.append(site)
	return true

static func _phase(context: Dictionary) -> String:
	var value: Variant = context.get("phase", context.get("stage", ""))
	return str(value) if value is String else ""

static func _cleared_wave(context: Dictionary) -> int:
	if context.has("cleared_wave"):
		return int(context.cleared_wave) if _integer(context.cleared_wave, 0, Balance.TOTAL_WAVES) else -1
	if context.get("stage") is String and str(context.stage) == "preparation": return Balance.TOTAL_WAVES
	var wave: Variant = context.get("wave", 0)
	if not _integer(wave, 0, Balance.TOTAL_WAVES): return -1
	match _phase(context):
		"salvage": return int(wave)
		"build": return maxi(0, int(wave)-1)
		"preparation": return Balance.TOTAL_WAVES
	return 0

static func _trigger_matches(row: Dictionary, context: Dictionary) -> bool:
	match str(row.event):
		"arrival":
			# The caller's actual arrival callback is the evidence. Explicit false
			# or malformed arrival claims still cannot schedule a scene.
			return not context.has("arrived") or (context.arrived is bool and bool(context.arrived))
		"wave_cleared":
			return _cleared_wave(context) == int(row.wave) and context.get("enemies_remaining") is int and int(context.enemies_remaining) == 0 and _phase(context) in ["salvage", "build"]
		"relay_completed":
			return row.site == CampaignCatalog.ENTRY and _integer(context.get("relay_stage"), 0, 9) and int(context.relay_stage) == int(row.relay_stage)
		"guards_cleared":
			return CampaignCatalog.site_kind(str(row.site)) == "outpost" and context.get("enemies_remaining") is int and int(context.enemies_remaining) == 0
		"site_secured":
			return _completed(context.get("completed")) and context.completed.has(row.site)
		"find":
			return context.get("entry_id") is String and context.entry_id == row.id
		"npc_rescued":
			if not context.get("recruited") is bool or not bool(context.recruited) or not context.get("npc_id") is String or context.npc_id != row.npc_id: return false
			if not context.get("enemies_remaining") is int or int(context.enemies_remaining) != 0: return false
			var person := profile(str(row.npc_id))
			if person.is_empty() or person.site != row.site: return false
			var phase := _phase(context)
			var in_preparation: bool = context.get("stage") is String and str(context.stage) == "preparation"
			var completed_site: bool = _completed(context.get("completed")) and context.completed.has(row.site)
			var in_map: bool = context.get("stage") is String and str(context.stage) == "map" and completed_site and phase in ["convoy", "victory", "preparation", "build", "salvage"]
			var outpost_phase: bool = CampaignCatalog.site_kind(str(row.site)) == "outpost" and (phase in ["occupation", "defense"] or (context.get("stage") is String and str(context.stage) in ["occupation", "defense"]))
			# Outposts have finite occupation guards, not an active wave roster.
			# With actual zero guards, their retained rounds phase may still say attack.
			var safe_phase: bool = in_preparation or in_map or outpost_phase or phase in ["build", "salvage", "preparation"]
			return safe_phase and (completed_site or _cleared_wave(context) >= int(person.min_wave))
		"npc_after":
			return context.get("recruited") is bool and bool(context.recruited) and context.get("npc_id") is String and context.npc_id == row.npc_id
	return false

static func due(site_id: String, event: String, context: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not CHAPTERS.has(site_id) or not event in EVENTS: return result
	for row: Dictionary in ENCOUNTERS:
		if row.site == site_id and row.event == event and _trigger_matches(row, context):
			result.append(_translated(row))
	return result

static func epilogue(completed: Array) -> Dictionary:
	if not _completed(completed) or not CampaignCatalog.main_complete(completed): return {}
	if CampaignCatalog.all_complete(completed):
		return {"id":"all_sites", "title":L.text("Jeder Standort hat geantwortet."), "body":L.text("Alle zwölf Standorte sind gesichert. Das Warnnetz trägt bestätigte Halte, geborgene Baupläne und einen bewachten Evakuierungskorridor. Die Namensliste bleibt ehrlich: Menschen, deren Aufnahme noch aussteht, sind ein eigener Auftrag der Crew.")}
	return {"id":"main_route", "title":L.text("Die Route ist offen, das Netz noch nicht vollständig."), "body":L.text("Die acht Hauptbunker sind gesichert. Die Crew hat einen bestätigten Korridor von der Küste bis zum Pass. Noch offene Außenposten bleiben eigenständige Einsätze; fehlende Menschen werden erst nach ihrer persönlichen Aufnahme als gerettet gemeldet.")}
