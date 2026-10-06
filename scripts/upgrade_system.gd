class_name UpgradeSystem
extends Node
## Shared points come from recovered machine cores; materials remain physical cargo.
signal changed

const NODES := [
	{"id":"bunker_workshop", "branch":0, "title":"FERTIGUNGSTECHNIK", "cost":2, "parent":"", "wave":1, "detail":"Betonmischer, Öfen und Munitionspressen benötigen 20 % weniger Zeit. Schaltet zusätzliche Produktionsanlagen im Tiefbau frei."},
	{"id":"medic_logistics", "branch":0, "title":"SAN-1 TRANSPORT", "cost":4, "parent":"bunker_workshop", "wave":1, "detail":"SAN-1 bringt jeweils einen Rohstoff aus vorhandenen Kisten zu wartenden Anlagen. Aufnahme und Abgabe dauern je 1,25 s; danach 3 s Pause. Heilung und Rettung haben Vorrang. Volle Anlagen: Ladung zurück zur Kiste."},
	{"id":"medic_collection", "branch":0, "title":"SAN-1 BERGUNG", "cost":4, "parent":"bunker_workshop", "wave":1, "detail":"SAN-1 sammelt lose Rohstoffe und räumt fertige Maschinenprodukte in passende Lagerkisten. Fehlende Materialkisten werden leer bereitgestellt. Fertige Produkte haben Vorrang vor Nachfüllen; Heilung vor jedem Transport. Keine Rohstoffe gehen verloren."},
	{"id":"bunker_dance", "branch":2, "title":"BUNKERDANCE I", "cost":2, "parent":"", "wave":1, "detail":"SAN-1 Softwarestufe 1: Kern-Takt. Der Sensorkopf nickt zu hörbaren Kick-Schlägen. SAN-1 tanzt nur in sicherer Bereitschaft ohne Ladung oder Auftrag. Alle Softwarestufen bleiben auf der Reise erhalten."},
	{"id":"bunker_dance_2", "branch":2, "title":"BUNKERDANCE II", "cost":2, "parent":"bunker_dance", "wave":1, "detail":"SAN-1 Softwarestufe 2: Servo-Lock. Kurze mechanische Stopps und Arm-Akzente im Takt. Wechselt zwischen beiden freigeschalteten Tänzen. Arbeit und medizinische Hilfe unterbrechen sofort."},
	{"id":"bunker_dance_3", "branch":2, "title":"BUNKERDANCE III", "cost":3, "parent":"bunker_dance_2", "wave":1, "detail":"SAN-1 Softwarestufe 3: Ketten-Shuffle. Gegenläufige Ketten und Schulterbewegungen im Takt; der Roboter bleibt an seinem Platz. Drei Tänze wechseln mit den Musikphrasen."},
	{"id":"bunker_dance_4", "branch":2, "title":"BUNKERDANCE IV", "cost":3, "parent":"bunker_dance_3", "wave":1, "detail":"SAN-1 Softwarestufe 4: Hydraulik-Welle. Eine fließende Welle durch Gelenke und Greifarm. Vier Tänze folgen der tatsächlich laufenden Musik, auch im Koop."},
	{"id":"bunker_dance_5", "branch":2, "title":"BUNKERDANCE V", "cost":4, "parent":"bunker_dance_4", "wave":1, "detail":"SAN-1 Softwarestufe 5: Bunker-Freeze. Präzise Stopps, Gewichtswechsel und Kopf-Akzente. Alle fünf eigenen Tänze sind freigeschaltet. Bei stummer Musik oder reduzierter Bewegung bleibt SAN-1 ruhig."},
	{"id":"bunker_armor", "branch":0, "title":"VERBUNDWÄNDE", "cost":5, "parent":"bunker_workshop", "wave":6, "detail":"Wandstufe II ab Welle 6, Panzerstahlwände ab Welle 11. Schaltet den Kernschutzraum im Tiefbau frei."},
	{"id":"bunker_fortress", "branch":0, "title":"FESTUNG", "cost":12, "parent":"bunker_armor", "wave":16, "detail":"Schaltet Wandstufe IV und die Schutzkuppel frei. Kuppelbau: 4 Stahl + 4 Panzerstahl + 12 Glas an der Kuppelkonsole."},
	{"id":"perimeter_automation", "branch":0, "title":"AUSSENWACHE", "cost":7, "parent":"bunker_armor", "wave":11, "detail":"Zwei kompakte Bodenwachen je Front feuern kurze Salven auf kleine Bodengegner. Je Anlage: 2 Stahl + 1 Beton. 1 Munitionskiste liefert 20 Schuss."},
	{"id":"weapon_handling", "branch":1, "title":"WAFFENTECHNIK", "cost":2, "parent":"", "wave":1, "detail":"Alle Handwaffen verursachen 20 % mehr Schaden. Persönlicher Waffendrill unter P: Personal erhöht den eigenen Schaden zusätzlich; beide Verbesserungen wirken zusammen."},
	{"id":"shotgun", "branch":1, "title":"SCHROTFLINTE", "cost":3, "parent":"weapon_handling", "wave":1, "detail":"Breite Salven auf kurze Distanz. Mit C / Num 0 / RS wechseln."},
	{"id":"arcgun", "branch":1, "title":"IMPULSGEWEHR", "cost":7, "parent":"shotgun", "wave":6, "detail":"Langsame, schwere Energiegeschosse gegen große Maschinen."},
	{"id":"boots", "branch":2, "title":"ARBEITSSTIEFEL", "cost":2, "parent":"", "wave":1, "detail":"Alle Spielerfiguren laufen und klettern 15 % schneller."},
	{"id":"harness", "branch":2, "title":"TRAGEGESTELL", "cost":3, "parent":"boots", "wave":1, "detail":"Alle Spielerfiguren erhalten zwei zusätzliche Trageplätze."},
	{"id":"craftsmanship", "branch":2, "title":"HANDWERK", "cost":6, "parent":"harness", "wave":6, "detail":"Abbauen, Material einfüllen und Bauen gehen 25 % schneller."},
	{"id":"core_resilience", "branch":0, "title":"KERNVERSTÄRKUNG", "cost":3, "parent":"bunker_workshop", "wave":1, "detail":"Verstärkt den Bunkerkern um 120 LP. Die zusätzliche Hülle wird sofort eingebaut; vorhandene Schäden bleiben bestehen."},
	{"id":"repair_tools", "branch":0, "title":"REPARATURWERKZEUG", "cost":3, "parent":"core_resilience", "wave":1, "detail":"Reparaturen an Bunkerkern und Wänden arbeiten 35 % schneller. Materialverbrauch und Heilmenge bleiben gleich."},
	{"id":"blast_baffles", "branch":0, "title":"SPLITTERSCHUTZ", "cost":6, "parent":"core_resilience", "wave":8, "detail":"Der Bunkerkern erleidet 15 % weniger Schaden. Schützt den Kern auch nach dem Verlust der Außenwände."},
	{"id":"precision_lines", "branch":0, "title":"PRÄZISIONSFERTIGUNG", "cost":5, "parent":"bunker_workshop", "wave":6, "detail":"Alle Produktionsanlagen benötigen zusätzlich 15 % weniger Zeit. Zusammen mit Fertigungstechnik: 32 % kürzere Herstellung."},
	{"id":"medical_station", "branch":0, "title":"SANITÄTSSTATION", "cost":4, "parent":"core_resilience", "wave":4, "detail":"SAN-1 füllt medizinische Vorräte am Bunkerkern 30 % schneller auf. Unter Beschuss bleibt das Nachfüllen unterbrochen."},
	{"id":"logistics_drive", "branch":0, "title":"TRANSPORTANTRIEB", "cost":4, "parent":"medic_logistics", "wave":6, "detail":"SAN-1 benötigt 25 % weniger Zeit für Aufnahme, Abgabe und die Pause zwischen Transporten. Medizinische Hilfe behält Vorrang."},
	{"id":"convoy_mg", "branch":3, "title":"MG-SCHÜTZENPLATZ", "cost":4, "parent":"", "wave":1, "detail":"Baut ein bemanntes MG ein. Ein zweiter Spieler kann schießen, während der Fahrer lenkt. Solo bedient der Fahrer beide Aufgaben. Munition wird aus der Fahrzeugladung nachgefüllt."},
	{"id":"convoy_armor", "branch":3, "title":"FAHRZEUGPANZERUNG", "cost":4, "parent":"", "wave":1, "detail":"Zusätzliche Stahlplatten erhöhen die Fahrzeughülle von 600 auf 800 LP. Vorhandene Schäden bleiben bestehen."},
	{"id":"convoy_armor_heavy", "branch":3, "title":"VERBUNDPANZERUNG", "cost":7, "parent":"convoy_armor", "wave":1, "detail":"Verstärkte Seiten und Motorabschirmung erhöhen die Fahrzeughülle von 800 auf 1100 LP. Vorhandene Schäden bleiben bestehen."},
	{"id":"convoy_cargo", "branch":3, "title":"LASTENTRÄGER", "cost":3, "parent":"", "wave":1, "detail":"Erweitert den Laderaum von 18 auf 36 Rohstoffplätze. Unverbrauchte Ladung unterstützt den Aufbau am nächsten Bunker."},
	{"id":"convoy_tank", "branch":3, "title":"ZUSATZTANK", "cost":3, "parent":"", "wave":1, "detail":"Erhöht das Tankvolumen von 30 auf 50 Liter. Der zusätzliche Tank wird leer eingebaut und muss befüllt werden."},
	{"id":"convoy_economy", "branch":3, "title":"SPARMOTOR", "cost":5, "parent":"convoy_tank", "wave":1, "detail":"Verbraucht auf Fahrten 25 % weniger Benzin. Größere Reichweite ohne zusätzliche Ladung oder kostenloses Auftanken."},
	{"id":"convoy_handling", "branch":3, "title":"FAHRWERKABSTIMMUNG", "cost":3, "parent":"", "wave":1, "detail":"Erhöht die Beschleunigung von 190 auf 250 und die Bremskraft von 350 auf 460. Das Fahrzeug reagiert schneller; die Höchstgeschwindigkeit bleibt unverändert."},
	{"id":"convoy_transmission", "branch":3, "title":"LANGSTRECKENGETRIEBE", "cost":5, "parent":"convoy_handling", "wave":1, "detail":"Erhöht die Höchstgeschwindigkeit von 125 auf 140. Der Kraftstoffverbrauch richtet sich weiter nach der tatsächlich gefahrenen Strecke."},
	{"id":"convoy_reload", "branch":3, "title":"SCHNELLVERSCHLUSS", "cost":4, "parent":"convoy_mg", "wave":1, "detail":"Verkürzt das Nachladen des Fahrzeug-MG von 1,40 auf 1,05 Sekunden. Magazin und Munitionsverbrauch bleiben unverändert."},
	{"id":"convoy_stabilizer", "branch":3, "title":"MG-STABILISIERUNG", "cost":5, "parent":"convoy_reload", "wave":1, "detail":"Erhöht den Schaden des Fahrzeug-MG von 18 auf 21 je Treffer. Verbraucht weiterhin einen Schuss aus dem endlichen Munitionsvorrat."},
	{"id":"convoy_support", "branch":3, "title":"MOBILER WERKZEUGSATZ", "cost":4, "parent":"convoy_cargo", "wave":1, "detail":"Fahrzeugreparaturen stellen mit demselben Stahleinsatz 30 % mehr LP wieder her. Benötigt weiterhin Material und eine abgeschlossene Reparatur."},
	{"id":"convoy_blast_lining", "branch":3, "title":"SPLITTERAUSKLEIDUNG", "cost":6, "parent":"convoy_armor_heavy", "wave":1, "detail":"Die Fahrzeughülle erleidet 15 % weniger Schaden. Vorhandene Schäden bleiben bestehen; schützt zusätzlich zur Verbundpanzerung."},
	{"id":"weapon_magazines", "branch":1, "title":"ERWEITERTE MAGAZINE", "cost":3, "parent":"weapon_handling", "wave":2, "detail":"Größere Magazine: Dienstgewehr 36, Schrotflinte 8, Impulsgewehr 16 Patronen. Seltene Waffen: 24, 6 und 12. Zusätzlicher Platz wird leer eingebaut."},
	{"id":"weapon_bolt", "branch":1, "title":"SCHNELLER VERSCHLUSS", "cost":4, "parent":"weapon_magazines", "wave":4, "detail":"Alle Handwaffen laden 15 % schneller nach. Stapelt sich mit persönlichen Nachladeboni. Patronen müssen weiterhin aus dem tatsächlichen Vorrat kommen."},
	{"id":"weapon_sights", "branch":1, "title":"FEINVISIERUNG", "cost":3, "parent":"weapon_handling", "wave":3, "detail":"Dienst- und Veteranengewehr streuen 45 % weniger. Präzisere Einzelschüsse auf Entfernung; Schaden, Feuerrate und Munitionsverbrauch bleiben gleich."},
	{"id":"weapon_choke", "branch":1, "title":"WÜRGEBOHRUNG", "cost":4, "parent":"shotgun", "wave":6, "detail":"Beide Schrotflinten bündeln ihre Schrotgarbe um 28 % enger. Mehr Pellets treffen schmale Ziele; die breite Flächenabdeckung wird kleiner."},
	{"id":"weapon_capacitor", "branch":1, "title":"DURCHSCHLAGSKONDENSATOR", "cost":6, "parent":"arcgun", "wave":10, "detail":"Impulsgeschosse durchdringen einen zusätzlichen Gegner: normal drei, selten vier Ziele. Wände stoppen das Geschoss weiterhin. Verbrauch bleibt 2 beziehungsweise 3 Patronen."},
	{"id":"weapon_pouches", "branch":1, "title":"PATRONENTASCHEN", "cost":3, "parent":"weapon_magazines", "wave":3, "detail":"Erweitert die Handwaffenreserve von 120 auf 180 Patronen. Schafft leeren Stauraum; Munition muss aus vorhandenen Kisten und Vorräten nachgefüllt werden."},
]
const CATEGORIES := ["Basis", "Waffen", "Besatzung", "Fahrzeug"]
var game
var points := 0
var earned := 0
var owned: Dictionary = {}

func add_points(amount: int) -> void:
	if amount <= 0:
		return
	points += amount
	earned += amount
	changed.emit()
	if is_instance_valid(game):
		game.notify(LocaleText.format("+%d Technikpunkt · T: Technik" if amount==1 else "+%d Technikpunkte · T: Technik", amount))

func has_upgrade(id: String) -> bool:
	return owned.has(id)

func node_data(id: String) -> Dictionary:
	for entry in NODES:
		if entry.id == id:
			return entry
	return {}

func requirement(id: String) -> String:
	var entry := node_data(id)
	if entry.is_empty():
		return LocaleText.text("Unbekannte Technik")
	if has_upgrade(id):
		return LocaleText.text("FREIGESCHALTET")
	if int(entry.branch) == 3:
		if not vehicle_unlocked(): return LocaleText.text("NACH DEM ERSTEN SIEG IN WELLE 20")
		var expedition = game.get("expedition")
		if expedition.has_method("can_manage") and not expedition.can_manage():
			return LocaleText.text("NUR IN DER FAHRZEUGVORBEREITUNG")
	var wave := 1
	if is_instance_valid(game) and "rounds" in game and is_instance_valid(game.rounds):
		wave = game.rounds.wave
	if wave < int(entry.wave):
		return LocaleText.format("AB WELLE %d", entry.wave)
	if not str(entry.parent).is_empty() and not has_upgrade(entry.parent):
		return LocaleText.text("VORHERIGE TECHNIK ERFORSCHEN")
	if points < int(entry.cost):
		var missing := int(entry.cost) - points
		return LocaleText.format("%d TECHNIKPUNKT FEHLT" if missing==1 else "%d TECHNIKPUNKTE FEHLEN", missing)
	return ""

func purchase(id: String) -> bool:
	if is_instance_valid(game):
		var session = game.get("network")
		if is_instance_valid(session) and session.active and not session.is_host: return false
	if not requirement(id).is_empty():
		return false
	var entry := node_data(id)
	var previous_points := points
	var previous_owned := owned.duplicate()
	points -= int(entry.cost)
	owned[id] = true
	if is_instance_valid(game):
		var expedition = game.get("expedition")
		if is_instance_valid(expedition) and expedition.has_method("commit_research") and not expedition.commit_research():
			points = previous_points
			owned = previous_owned
			return false
	apply_world_effects()
	changed.emit()
	if is_instance_valid(game):
		game.sound(preload("res://scripts/upgrade_audio.gd").KINDS[int(entry.branch)])
		game.notify(LocaleText.format("Technik freigeschaltet: %s", entry.title))
	return true

func movement_multiplier() -> float:
	return 1.15 if has_upgrade("boots") else 1.0

func work_multiplier() -> float:
	return 1.25 if has_upgrade("craftsmanship") else 1.0

func production_multiplier() -> float:
	return (0.8 if has_upgrade("bunker_workshop") else 1.0) * (0.85 if has_upgrade("precision_lines") else 1.0) * CampaignBonus.production_multiplier(game)

func weapon_multiplier() -> float:
	return 1.2 if has_upgrade("weapon_handling") else 1.0

func carry_capacity() -> int:
	return 8 if has_upgrade("harness") else Balance.CARRY_CAPACITY

func vehicle_unlocked() -> bool:
	if not is_instance_valid(game): return false
	var expedition = game.get("expedition")
	return is_instance_valid(expedition) and expedition.has_method("vehicle_unlocked") and expedition.vehicle_unlocked()

func nodes_for_category(category: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in NODES:
		if int(entry.branch) == category: result.append(entry)
	return result

func is_persistent(id: String) -> bool:
	var entry := node_data(id)
	return not entry.is_empty() and int(entry.branch) != 0

func persistent_owned() -> Array:
	var result: Array = []
	for entry: Dictionary in NODES:
		if is_persistent(entry.id) and has_upgrade(entry.id): result.append(str(entry.id))
	return result

func apply_world_effects() -> void:
	if not is_instance_valid(game): return
	if has_upgrade("medic_collection"):
		preload("res://scripts/medic_storage.gd").provision(game)
	var core = game.get("core")
	if not is_instance_valid(core): return
	var desired := 120.0 if has_upgrade("core_resilience") else 0.0
	var previous := float(core.get_meta("research_core_bonus", 0.0))
	if is_equal_approx(desired, previous): return
	core.set_meta("research_core_bonus", desired)
	core.max_hp += desired - previous
	if core.hp > 0: core.hp = clampf(core.hp + desired - previous, 0.0, core.max_hp)

func repair_multiplier() -> float:
	return 1.35 if has_upgrade("repair_tools") else 1.0

func core_damage_multiplier() -> float:
	return 0.85 if has_upgrade("blast_baffles") else 1.0

func medic_refill_multiplier() -> float:
	return 0.7 if has_upgrade("medical_station") else 1.0

func logistics_time_multiplier() -> float:
	return 0.75 if has_upgrade("logistics_drive") else 1.0

func medic_dance_level() -> int:
	# A malformed partial save cannot unlock a later move without its software.
	var level := 0
	for id: String in CampaignCatalog.MEDIC_UPGRADES:
		if not has_upgrade(id): break
		level += 1
	return level
