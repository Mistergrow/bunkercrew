extends RefCounted
## Stable public IDs survive saves; Steam names must match the partner backend.
const ENTRIES := [
	{"id":"first_kill","title":"ERSTER KONTAKT","detail":"Eine Maschine mit eigener Waffe oder Falle zerstören.","steam":"LS_FIRST_KILL","hidden":false},
	{"id":"combo_five","title":"FÜNF AUF EINEN STREICH","detail":"Fünf Abschüsse mit höchstens fünf Sekunden Abstand.","steam":"LS_COMBO_FIVE","hidden":false},
	{"id":"level_five","title":"SCHICHTVETERAN","detail":"Mit einer Figur Stufe 5 erreichen.","steam":"LS_LEVEL_FIVE","hidden":false},
	{"id":"armor","title":"STAHL AUF DER HAUT","detail":"Eine persönliche Rüstung herstellen.","steam":"LS_ARMOR","hidden":false},
	{"id":"trap","title":"BETRETEN VERBOTEN","detail":"Eine bezahlte Falle vor dem Bunker aufstellen.","steam":"LS_TRAP","hidden":false},
	{"id":"turret","title":"FEUERSTELLUNG","detail":"Ein hergestelltes Feldgeschütz aufstellen.","steam":"LS_TURRET","hidden":false},
	{"id":"wave_five","title":"DIE ERSTE NACHT","detail":"Welle 5 überstehen und den Tiefbau öffnen.","steam":"LS_WAVE_FIVE","hidden":false},
	{"id":"boss","title":"MUTTERMASCHINE GESTOPPT","detail":"Den Endgegner der zwanzigsten Welle besiegen.","steam":"LS_BOSS","hidden":false},
	{"id":"victory","title":"BIS ZUM MORGEN","detail":"Alle zwanzig Wellen gewinnen.","steam":"LS_VICTORY","hidden":false},
	{"id":"research_first","title":"EIN PLAN FÜR MORGEN","detail":"Die erste gemeinsame Technologie erforschen.","steam":"LS_RESEARCH_FIRST","hidden":false},
	{"id":"base_engineer","title":"FESTES FUNDAMENT","detail":"Drei unterschiedliche Basis-Technologien in einem Bunker erforschen.","steam":"LS_BASE_ENGINEER","hidden":false},
	{"id":"field_medic","title":"KEINER BLEIBT ZURÜCK","detail":"Eine andere Figur erfolgreich wiederbeleben.","steam":"LS_FIELD_MEDIC","hidden":false},
	{"id":"miner_50","title":"TIEFENSCHICHT","detail":"Insgesamt 50 Rohstoffeinheiten selbst abbauen.","steam":"LS_MINER_50","hidden":false},
	{"id":"craft_five","title":"FELDWERKSTATT","detail":"Insgesamt fünf Ausrüstungsgegenstände herstellen.","steam":"LS_CRAFT_FIVE","hidden":false},
	{"id":"cargo_full","title":"ALLES DABEI","detail":"Den Laderaum des Konvois vollständig beladen.","steam":"LS_CARGO_FULL","hidden":false},
	{"id":"convoy_route","title":"AUF EIGENEN RÄDERN","detail":"Eine Konvoi-Fahrt zum nächsten Bunker abschließen.","steam":"LS_CONVOY_ROUTE","hidden":false},
	{"id":"base_capture","title":"UNSER NEUER POSTEN","detail":"Die Besatzung eines neuen Bunkers ausschalten und ihn übernehmen.","steam":"LS_BASE_CAPTURE","hidden":false},
	{"id":"roadside","title":"KURZER ZWISCHENHALT","detail":"Einen bewachten Zwischenhalt sichern.","steam":"LS_ROADSIDE","hidden":false},
	{"id":"epic_weapon","title":"FUNDSTÜCK MIT GESCHICHTE","detail":"Eine seltene Waffe aus einem Straßendepot bergen.","steam":"LS_EPIC_WEAPON","hidden":false},
	{"id":"convoy_upgrade","title":"ROLLENDE WERKSTATT","detail":"Das erste Fahrzeug-Upgrade erforschen.","steam":"LS_CONVOY_UPGRADE","hidden":false},
	{"id":"all_dance_moves","title":"ALLE TANZMOVES","detail":"Alle 40 eigenen Tanzmoves freischalten: jede der acht Figuren auf Level 10 bringen.","steam":"LS_ALL_DANCE_MOVES","hidden":false},
	{"id":"solo_victory","title":"EIN LICHT BLEIBT AN","detail":"Alle zwanzig Wellen allein gewinnen.","steam":"LS_SOLO_VICTORY","hidden":true},
	{"id":"pristine_core","title":"KEIN KRATZER AM KERN","detail":"Alle zwanzig Wellen mit unbeschädigtem Bunkerkern gewinnen.","steam":"LS_PRISTINE_CORE","hidden":true},
	{"id":"last_drop","title":"AUF DEN LETZTEN TROPFEN","detail":"Eine Konvoi-Fahrt mit weniger als einem Liter im Tank beenden.","steam":"LS_LAST_DROP","hidden":true},
	{"id":"loaded_arrival","title":"UMZUG MIT AUSSICHT","detail":"Einen neuen Bunker mit mindestens 18 geladenen Rohstoffeinheiten übernehmen.","steam":"LS_LOADED_ARRIVAL","hidden":true},
	{"id":"all_routes","title":"DAS ENDE DER STRASSE","detail":"Alle acht Bunker der Hauptroute sichern.","steam":"LS_ALL_ROUTES","hidden":true},
]

static func entry(id: String) -> Dictionary:
	for value in ENTRIES:
		if value.id==id: return value
	return {}

static func steam_id(id: String) -> String:
	return str(entry(id).get("steam",""))
