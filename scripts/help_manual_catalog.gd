class_name HelpManualCatalog
extends RefCounted
## Read-only player guidance. Open panels request a fresh view; this catalog
## never advances a timer, spends material or changes a mission/profile.

const L := preload("res://scripts/locale_text.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
const Vehicle := preload("res://scripts/convoy_vehicle.gd")
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Workshop := preload("res://scripts/field_workshop.gd")
const PAGES: Array[Dictionary] = [
	{"id":"first_shift", "title":"Erste Schicht", "detail":"Vom ersten Rohstoff bis zur sicheren Front."},
	{"id":"controls", "title":"Steuerung", "detail":"Tastatur, Maus, Controller und Online-Koop."},
	{"id":"workshop", "title":"Produktion", "detail":"Rezepte, Vorräte und persönliche Ausrüstung."},
	{"id":"construction", "title":"Bunkerbau", "detail":"Aushub, Stützen, Räume und Luftabwehr."},
	{"id":"crew", "title":"Crew & Forschung", "detail":"Verletzungen, SAN-1 und gemeinsame Technik."},
	{"id":"travel", "title":"Konvoireise", "detail":"Beladen, einsteigen, verteidigen und weiterfahren."},
]

static func sections(page_id: String, game: Node = null) -> Array[Dictionary]:
	match page_id:
		"first_shift": return _first_shift(game)
		"controls": return _control_sections(game)
		"workshop": return _workshop()
		"construction": return _construction(game)
		"crew": return _crew()
		"travel": return _travel()
	return []

static func _section(title: String, body: String) -> Dictionary:
	return {"title":L.text(title), "body":L.text(body)}

static func _first_shift(game: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		_section("1 · Sand und Erz holen", "Gehe an eine Vorratskiste oder Rohstoffader. Halte E / X, bis du Material trägst. Hole zuerst Sand und Eisenerz; liegt ein anderes Objekt im Weg, wechsle mit F / RB das Ziel. Der Hinweis an der Figur zeigt die ausgewählte Aktion."),
		_section("2 · Eine Charge je Anlage", L.format("Betonmischer: %s. Stahlofen: %s. Halte E / X zum Einfüllen, warte auf das fertige Produkt und halte erneut zum Abholen. Eine fertige Charge blockiert die nächste, bis sie abgeholt ist. Der Mischer braucht außerdem Bindemittel aus seinem Vorrat.", [_recipe("mixer"), _recipe("furnace")])),
		_section("3 · Deine erste sichere Wand", L.format("Vorhandene Bunkertore schützen bereits. Im Story-Modus baust du zusätzlich die markierte Frontmauer: Für eine verstärkte Wand brauchst du %d Stahl und %d Beton. Am Bauplatz E / X halten: kostenlose Schalung, Stahl, Beton. Warte %.0f s bis zum Aushärten. In Mittellage beide Bodenfronten besetzen, am West- oder Ostrand eine.", [Balance.WALL_STEEL_COST, Balance.WALL_CONCRETE_COST, Balance.CURE_TIME])),
		_section("4 · Geschütz und Munition", "Antippen steigt in ein freies Geschütz ein; nochmals Interaktion verlässt es. Zielen, feuern und nachladen haben eigene Tasten. Munitionskisten sind endliche Vorräte: Liefere sie an Geschütze oder fülle deine Waffenreserve direkt an einer Munitionskiste auf."),
		_section("5 · Bauen, verteidigen, bergen", L.format("Eine Schicht hat %d Wellen. In Baupausen verarbeitest du Material und reparierst Schäden; nach einem Angriff birgst du Schrott und Technikpunkte. N startet die nächste Warnphase nur in einer Baupause und erst nach einem offenen Storyauftrag.", Balance.TOTAL_WAVES)),
		_section("6 · Neue Räume erreichen", "In den Schauplätzen führt die Folge Aushub → Abstützen → Raumausbau → Aushärten zu neuen Anlagen. Die Seite Bunkerbau nennt Baupläne und Materialkosten. Freigegebene Räume entstehen nicht automatisch."),
	]
	if _classic(game):
		result[5] = _section("6 · Klassischer Bunker", "Im klassischen Bunker öffnen Ausbauwellen zunächst vorhandene Ebenen und Anlagen. Der zusätzliche Tiefbau beginnt am Schachtbauplatz: Schacht fertigstellen, Raumfläche ausgraben und den jeweiligen Raum-Bauplatz beliefern. Seine Anlagen erfordern eigene Forschung.")
	result.append(_section("7 · SAN-1 hilft der Crew", "SAN-1 heilt und rettet zuerst. Im Technikbaum T / Back schalten SAN-1 TRANSPORT und SAN-1 BERGUNG Nachfüllen beziehungsweise Einsammeln und Einlagern frei. Für Herstellung und Lagerung brauchst du weiterhin echte Rohstoffe, erreichbare Anlagen und passende Kisten."))
	result.append(_section("Wenn etwas nicht klappt", "Halte die Interaktion statt nur anzutippen. Prüfe den Zielhinweis, freien Trageplatz und die Zutaten in deinen Händen. Bei mehreren Objekten das Ziel wechseln. Ist die Anlage fertig, erst das Produkt abholen. Starte die Warnphase erst, wenn Wand und Munition bereit sind."))
	result.append(_section("Handbuch und laufende Partie", "Das Handbuch erklärt bestehende Abläufe. Es erledigt keine Aufträge und vergibt keine Rohstoffe. Ob die Welt pausiert, richtet sich nach dem Spielmodus; im Online-Koop entscheidet der Gastgeber über die gemeinsame Pause."))
	return result

static func _control_sections(game: Node) -> Array[Dictionary]:
	return [
		_section("Antippen oder halten", "Antippen nimmt einen Fund auf, steigt in einen Sitz ein oder verlässt ihn. Halten baut ab, füllt Anlagen, baut und hilft Verletzten. Vorratskisten und fertige Maschinenprodukte werden mit Halten entnommen. Der aktuelle Zielhinweis nennt die genaue Aktion."),
		_section("Eigene Tasten im Online-Spiel" if _online(game) else "Lokale Crew", "Online verwendet jeder Spieler seine Tastatur und Maus oder den ersten Controller; die Kamera bleibt auf dem eigenen Rechner. Enter öffnet den Crew-Chat; Texteingabe sperrt Bewegung und Kampf." if _online(game) else "Solo steuert der erste Controller deine Figur; alternativ Tastatur und Maus. Im lokalen Koop gehört der erste Controller Spieler 2, Tastatur und Maus Spieler 1. Weitere Controller steuern Spieler 3 und 4. Bei mehreren nahen Objekten erst das Ziel wechseln."),
		_section("Kamera und Menüs", "Mausrad zoomt. F4 öffnet Bild-, Kamera-, Ton- und Takteinstellungen; F3 reduziert Effekte. F11 oder Alt + Enter wechselt Vollbild. Esc/B geht im Menü zurück. Pfeile oder Steuerkreuz wählen, Enter/A bestätigt."),
		_section("Solo-Story und Logbuch", "J öffnet das Solo-Logbuch, ebenso Logbuch im Pausenmenü. Sprich Überlebende und lies Feldaufzeichnungen vor Ort mit E. Eine Crewaufnahme braucht eine sichere Umgebung und die angegebenen Materialien in deinen Händen; erst der Aufnahme-Knopf verbraucht sie. Entdeckte Hinweise bleiben beim Neustart erhalten, Kampf- und Materialfortschritt folgt dem gesicherten Kampagnenstand."),
	]

static func controls(game: Node = null) -> Array[Dictionary]:
	var definitions := [
		["Laufen / Leiter", "A D / W S", "Pfeile / linker Stick"],
		["Springen", "Leertaste", "Rechte Shift / A"],
		["Interaktion: tippen / halten", "E", "Enter / X"],
		["Material wählen", "Tab", "Einfg / LB"],
		["Anderes Ziel / freier Sitz", "F", "Bild ab / RB"],
		["Ein Stück / Stapel ablegen", "Q tippen / halten", "Backspace / B tippen / halten"],
		["Zielen / feuern", "Maus / linke Maustaste", "Pos1 Ende + R-Strg / R-Stick + RT"],
		["Nachladen / Reserve am Vorrat", "R", "Entf / Y"],
		["Handwaffe wechseln", "C", "Num 0 / R-Stick drücken"],
		["Werkbank: Fertigungsmenü öffnen", "E", "Enter / X"],
		["Vorrat: ausgewähltes Material einlagern", "G halten", "Num * / L3 halten"],
		["Baugerät aufstellen", "B", "Num . / Pad rechts"],
		["Personal / Erfolge", "P / F6", "P / F6 · Pad oben"],
		["Technikbaum", "T", "T / Back"],
		["Nächste Welle: Baupause", "N", "N"],
		["Konvoikarte nach gesicherter Mission", "M", "M"],
		["Pause / Handbuch", "Esc / F1", "Start / F1"],
		["Optionen / Effekte", "F4 / F3", "F4 / F3"],
		["Mission neu starten", "F5", "F5"],
		["Freunde / Crew-Chat online", "F7 / Enter", "F7 / Enter"],
	]
	var result: Array[Dictionary] = []
	for row: Array in definitions:
		var primary := str(row[1])
		if _online(game) or _workers(game).size() <= 1:
			primary = str({
				"Laufen / Leiter":"A D / W S · linker Stick", "Springen":"Leertaste / A", "Interaktion: tippen / halten":"E / X", "Material wählen":"Tab / LB", "Anderes Ziel / freier Sitz":"F / RB", "Ein Stück / Stapel ablegen":"Q / B tippen / halten", "Zielen / feuern":"Maus / LMB · R-Stick / RT", "Nachladen / Reserve am Vorrat":"R / Y", "Handwaffe wechseln":"C / R-Stick drücken", "Werkbank: Fertigungsmenü öffnen":"E / X", "Vorrat: ausgewähltes Material einlagern":"G / L3 halten", "Baugerät aufstellen":"B / Pad rechts", "Technikbaum":"T / Back", "Pause / Handbuch":"Esc / Start · F1"
			}.get(str(row[0]), primary))
		result.append({"action":L.text(str(row[0])), "primary":L.text(primary), "secondary":L.text(primary if _online(game) else str(row[2]))})
	if _online(game):
		for row: Dictionary in result:
			if row.action == L.text("Nächste Welle: Baupause"):
				row.primary = L.text("N · nur Gastgeber")
				row.secondary = row.primary
	return result

static func _workshop() -> Array[Dictionary]:
	var result: Array[Dictionary] = [_section("Material bleibt körperlich", "Trageplätze sind begrenzt. Tab wählt die mitgeführte Materialart; Q legt ein Stück oder bei Halten einen Stapel ab. Wähle an einer passenden Vorratskiste das Material und halte G zum Einlagern. Eine Anlage mit fertigem Produkt muss zuerst geleert werden, bevor sie weiterproduziert.")]
	for id: String in Balance.RECIPES:
		var recipe: Dictionary = Balance.RECIPES[id]
		var body := L.format("%s · Grundzeit %.1f s. Forschung und geborgene Baupläne können die Produktionszeit verkürzen.", [_recipe(id), float(recipe.time)])
		if id == "furnace": body += " " + L.text("Schrott ersetzt Eisenerz Stück für Stück; beide sind keine getrennten Pflichtzutaten.")
		if int(recipe.get("binder", 0)) > 0: body += " " + L.format("Der Betonmischer braucht zusätzlich %d Bindemittel pro Charge. Sein Vorrat ist begrenzt; leerer Binder verhindert weitere Chargen.", int(recipe.binder))
		result.append(_section(str(recipe.label), body))
	var orders := PackedStringArray()
	for recipe: Dictionary in Workshop.RECIPES:
		orders.append(L.format("%s: %s · %.1f s · %s", [recipe.label, _materials(recipe.cost), float(recipe.time), recipe.note]))
	result.append(_section("Feldwerkbank", L.text("In der ersten freigegrabenen Etage öffnet Interaktion das Fertigungsmenü. Wähle ein Bauplanbild und bestätige Materialeinbau oder Abholung. Jeder Spieler hat eigene Aufträge; Wechseln löscht keine Einzahlungen. Stahlweste I muss vor Panzerweste II hergestellt werden.") + "\n" + "\n".join(orders)))
	result.append(_section("Fallen und Feldgeschütz", L.format("Fertige Baugeräte mit Tab auswählen und draußen mit B aufstellen. Der Boden muss frei und tragfähig sein; eine Vorschau zeigt den Platz. Höchstens %d Feldverteidigungen bleiben gleichzeitig aktiv. Das Feldgeschütz benötigt einen Bediener und eigene Munition.", Workshop.MAX_DEFENSES)))
	result.append(_section("Endliche Munition", "Nachladen verschiebt vorhandene Patronen aus der Reserve ins Magazin. R an einer Munitionskiste füllt die persönliche Reserve; die Kiste wird dabei tatsächlich verbraucht. Getragene Kisten beliefern Dachgeschütz, Flak oder Fahrzeug. Neue Forschung und Nachladen erzeugen keine kostenlosen Patronen."))
	return result

static func _construction(game: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _classic(game):
		result.append(_section("Klassischer Bunker: vorhandene Ebenen", "Die klassische Welt hat ihre eigene Ausbaufolge. Welle 5 gibt das Glaswerk frei, Welle 10 den tieferen Schacht. Zusätzliche Tiefbauräume verwenden eigene Bauplätze und Forschungsbedingungen; die folgenden Schauplatz-Raumsummen gelten dort nicht."))
	else:
		result.append(_section("1 · Ausheben", "Freigegebenen Schacht und die markierte Raumfläche abtragen. Geborgene Rohstoffe bleiben nutzbar. Ein freigeräumter Gang allein genügt nicht: Der ganze Baubereich muss ausgehoben sein, bevor die Stützen eingebaut werden können."))
		result.append(_section("2 · Abstützen", L.format("Am Raum-Baupult %s liefern und %.1f s arbeiten. Diese Stützen sind bereits in den unten genannten Gesamtkosten enthalten; sie werden nicht zusätzlich berechnet.", [_materials(ScenarioRoomCatalog.SUPPORT_COST), ScenarioRoomCatalog.SUPPORT_TIME])))
		result.append(_section("3 · Ausbauen und aushärten", L.format("Die restlichen Raumzutaten zum selben Baupult bringen und %.1f s arbeiten. Danach härtet der Raum %.1f s. Erst der fertiggestellte Raum schaltet seine Anlagen, Adern und den Kernbonus frei.", [ScenarioRoomCatalog.BUILD_TIME, ScenarioRoomCatalog.CURE_TIME])))
		for room: Dictionary in ScenarioRoomCatalog.ROOMS:
			result.append(_section(str(room.title), L.format("Bauplan ab Welle %d · Gesamtmaterial %s · Kern +%d LP. %s.", [int(room.wave), _materials(room.cost), int(room.core_bonus), room.benefit])))
	var stages := PackedStringArray()
	for tier: int in FlakStation.SPECS:
		var spec: Dictionary = FlakStation.SPECS[tier]
		stages.append(L.format("%s: ab Welle %d · %s · %.1f s Bauarbeit", [spec.label, int(spec.wave), _materials(spec.cost), float(spec.time)]))
	result.append(_section("Flak bauen und versorgen", "\n".join(stages) + "\n" + L.text("Luftwellen beginnen frühestens ab Welle 7 und nur mit einer funktionsfähigen Luftabwehr. Eine gebaute Flak braucht weiterhin echte Munition. Wache kann automatisch schießen; du kannst den Turm auch selbst besetzen. Höhere Stufen verschenken keine neue Munition.")))
	result.append(_section("Kern reparieren", L.format("Am beschädigten Kern Interaktion halten. Eine Reparatur braucht 1 Stahl oder 1 Schrott und heilt grundsätzlich %d LP; Reparaturmatrix kann den Betrag erhöhen. Wände, Kuppel und Geschütze haben eigene Reparaturhinweise. Ein zerstörter Kern beendet die Mission.", int(Balance.CORE_REPAIR))))
	result.append(_section("Später Kernschutz", _upgrade_details(["bunker_armor", "bunker_fortress"])))
	return result

static func _crew() -> Array[Dictionary]:
	return [
		_section("Behandlung und Wiederbelebung", L.format("Neben dem Verletzten Interaktion halten. Behandlung dauert %.1f s, stoppt Blutung und Bruch und heilt bis zu %d LP. Wiederbelebung dauert %.1f s und stellt %d %% der maximalen LP her. Nach %.0f s Bewusstlosigkeit dauert die Rettung %.1f s; die Figur bleibt rettbar.", [MedicalCatalog.TREAT_TIME, int(MedicalCatalog.HEAL_AMOUNT), MedicalCatalog.REVIVE_TIME, roundi(MedicalCatalog.REVIVE_HEALTH_RATIO*100), MedicalCatalog.CRITICAL_DELAY, MedicalCatalog.CRITICAL_REVIVE_TIME])),
		_section("Verbände und sichere Versorgung", L.format("Jeder Arbeiter hat höchstens %d medizinische Vorräte außerhalb des Materialinventars. Erfolgreiche Hilfe verbraucht einen. Bewegung, Treffer, Loslassen oder blockierte Sicht unterbrechen ohne Verbrauch. Nach %.1f trefferfreien Sekunden am Kern kommt alle %.1f s ein Verband zurück; aktive Blutungen und Brüche benötigen Behandlung.", [MedicalCatalog.MAX_CHARGES, Balance.WORKER_REGEN_DELAY, MedicalCatalog.REFILL_TIME])),
		_section("Gemeinsame Technik · T", "Geborgene Technikpunkte gehören der Crew. Forschung gilt für alle Arbeiter; benötigte Vorgänger und Wellenfreigaben stehen im Technikbaum. Forschung verbraucht Punkte, aber transportiert keine Rohstoffe und baut bezahlte Anlagen nicht automatisch. Im Online-Spiel bestätigt der Gastgeber die Änderung."),
		_section("Persönliche Erfahrung · P", "Treffer, Abschüsse und gewertete Arbeiten geben persönliche Erfahrung. Level liefern Fähigkeitspunkte für Vitalität, Waffendrill und Handwerk. Diese Punkte sind von gemeinsamen Technikpunkten getrennt. Körperliche Rüstung wird an der Feldwerkbank hergestellt."),
		_section("SAN-1: Transport und Bergung", _upgrade_details(["medic_logistics", "medic_collection", "logistics_drive"])),
		_section("SAN-1: Medizin vor Logistik", "SAN-1 behandelt erreichbare Verletzte und holt Vorräte am Kern. Heilung und Rettung unterbrechen Transporte. Fertige Maschinenprodukte haben nach erforschter Bergung Vorrang vor weiterem Nachfüllen; passende freie Lagerkisten bleiben erforderlich. Der Roboter erzeugt keine Rohstoffe und überwindet keinen versperrten Schacht."),
		_section("Tänze und Musik", L.format("Jede Figur hat %d gemeinsame Moves und %d eigene Tänze. Eigene Moves werden auf Charakterstufen %s freigeschaltet, nicht durch besuchte Schauplätze. Ruhige Figuren reagieren auf die hörbare Musik; Arbeit, Gefahr und stumme Musik unterbrechen den Tanz. SAN-1 erhält seine fünf Tänze über Bunkerdance I–V im Technikbaum; diese Software reist mit.", [Dance.SHARED_STYLES.size(), Dance.UNLOCK_LEVELS.size(), _levels(Dance.UNLOCK_LEVELS)])),
		_section("Crew und Verständigung", "Alle können bauen, bergen und kämpfen. Online öffnet Enter den Crew-Chat, F7 die bestätigte Freundesliste. Die Schnelltexte helfen ohne Headset. Ein Gast nutzt seine eigene Kamera und seine eigenen Tasten; gemeinsame Forschung und Missionswechsel bleiben unter Host-Autorität."),
	]

static func _travel() -> Array[Dictionary]:
	return [
		_section("Deine Aufgabe bei einer Reifenpanne", "Ein Arbeiter übernimmt das hintere Rad und hält E / X für den Werkzeugschritt. Alle anderen bleiben bei Fahrzeug und Mechaniker, zielen auf Angreifer und feuern. Eine weitere Hand am selben Reifen beschleunigt nichts. Solo geben bewaffnete Begleiter Deckung; SAN-1 kann den Reifen übernehmen, solange niemand medizinische Hilfe braucht."),
		_section("1 · Gesicherten Bunker vorbereiten", "Nach einem gesicherten Kampagnenstand führt M zur Einsatzkarte. Wähle ein freigegebenes Ziel und gegebenenfalls einen Zwischenhalt. Über den Garagen-Rückweg kehrst du zum Fahrzeug zurück, um Crew und Vorräte vorzubereiten."),
		_section("2 · Laden und tanken", L.format("Der Grundtransporter trägt %d Rohstoffplätze und %.0f Liter Kraftstoff; Ausbauten erhöhen diese Grenzen. Stahl, Beton und andere Vorräte müssen wirklich geladen werden. Prüfe Route, Tank, Fahrzeughülle und Munition vor Abfahrt. Zusatztank und Panzerung füllen vorhandene Schäden oder leere Tanks nicht kostenlos auf.", [Vehicle.BASE_CARGO, Vehicle.BASE_FUEL])),
		_section("3 · Sichtbar einsteigen", L.format("Interaktion antippen steigt in einen freien Platz. Fahrer lenkt; ein erforschtes MG wird vom Schützen oder solo vom Fahrer bedient. Heck- und Seitenwache feuern ihre eigenen Handwaffen mit eigener Munition. Ziel wechseln und Interaktion wechseln freie Sitze. Erst wenn die benötigte Crew sitzt, folgt der %.1f-s-Countdown und anschließend der Motorstart.", Journey.DEPARTURE_TIME)),
		_section("4 · Reise verteidigen", "Lenke mit links/rechts. Geschützschütze und Mitfahrer zielen und feuern unabhängig; Nachladen braucht Vorräte. Hinterhalte und Stopps sind echte Begegnungen. Während ein Arbeiter einen Reifen wechselt, verteidigen die anderen Fahrzeug und Mechaniker."),
		_section("Reifenwechsel: fünf Arbeitsschritte", L.format("Am hinteren Rad Interaktion halten: Wagenheber %.1f s → defektes Rad abnehmen %.1f s → Ersatzrad aufsetzen %.1f s → drei Schrauben anziehen → Wagenheber senken %.1f s. Bei Schrauben im grünen Timingfenster antippen; alternativ pro Schraube %.1f s halten. Nach Abschluss wieder einsteigen. Solo unterstützt SAN-1.", [float(Journey.HOLD_TIMES.jack), float(Journey.HOLD_TIMES.remove), float(Journey.HOLD_TIMES.fit), float(Journey.HOLD_TIMES.lower), Journey.BOLT_HOLD_TIME])),
		_section("Zwischenhalte und Ladung", "Tankstelle liefert begrenzten Kraftstoff, Versorgungskonvoi Stahl und Munition, Waffendepot eine seltene Waffe. Besiege die Wachen und sichere den Halt; beladene Rohstoffe benötigen freien Laderaum. Nicht geborgene Straßenbeute wird beim sicheren Szenenwechsel erhalten und zusammengeführt."),
		_section("Neue Bunker und Außenposten", L.format("Die Kampagne umfasst %d Orte. Hauptbunker brauchen eine sichere Schicht; die %d Außenposten haben bewachte Sicherungsziele und bringen dauerhafte Baupläne. Waffen, persönliche Entwicklung, Fahrzeugforschung und geborgene Baupläne reisen mit; Bunkerräume und Infrastruktur gehören zum jeweiligen Standort.", [CampaignCatalog.NODES.size(), CampaignCatalog.OUTPOST_OBJECTIVES.size()])),
		_section("Gesicherter Fortschritt", "Ein vollständiger Kampagnenabschluss umfasst alle Bunker und Außenposten. Mission neu starten lädt den letzten gesicherten Missionsbeginn; laufende Kämpfe werden nicht als zusätzliche Belohnung gesichert. Im Online-Koop koordiniert der Gastgeber Abfahrt, Ankunft und Neustart."),
	]

static func _materials(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for kind: String in cost:
		parts.append(L.format("%d %s", [int(cost[kind]), Balance.RESOURCE_NAMES.get(kind, kind)]))
	return " + ".join(parts)

static func _recipe(id: String) -> String:
	var recipe: Dictionary = Balance.RECIPES.get(id, {})
	if recipe.is_empty(): return ""
	return _materials(recipe.inputs) + " → " + L.format("%d %s", [int(recipe.amount), Balance.RESOURCE_NAMES.get(str(recipe.output), str(recipe.output))])

static func _levels(values: Array) -> String:
	var parts := PackedStringArray()
	for value in values: parts.append(str(value))
	return ", ".join(parts)

static func _upgrade_details(ids: Array) -> String:
	var parts := PackedStringArray()
	for id: String in ids:
		for entry: Dictionary in UpgradeSystem.NODES:
			if entry.id == id:
				parts.append(L.format("%s · %d Technikpunkte · %s", [entry.title, int(entry.cost), entry.detail]))
				break
	return "\n".join(parts)

static func _valid(value: Variant) -> bool:
	return is_instance_valid(value) and value is Node and not value.is_queued_for_deletion()

static func _value(owner: Variant, key: String, fallback: Variant = null) -> Variant:
	return owner.get(key) if _valid(owner) and key in owner else fallback

static func _online(game: Node) -> bool:
	return bool(_value(_value(game, "network"), "active", false))

static func _classic(game: Node) -> bool:
	if not _valid(game) or not bool(_value(game, "started", false)) or _valid(_value(game, "scenario_bunker")): return false
	var stage := str(_value(_value(game, "expedition"), "stage", "defense"))
	if stage != "defense": return false
	var options: Variant = _value(game, "scenario_options", {})
	return not options is Dictionary or not options.has("environment")

static func _workers(game: Node) -> Array:
	var value: Variant = _value(game, "players", [])
	return value if value is Array else []

static func _local_worker(game: Node) -> Node:
	var online := _online(game)
	var local_id := int(_value(_value(game, "network"), "local_player_id", 1))
	for worker in _workers(game):
		if _valid(worker) and (not online or int(_value(worker, "player_id", 0)) == local_id): return worker
	return null

static func _advice(id: String, title: String, body: String, page: String) -> Dictionary:
	return {"id":id, "title":L.text(title), "body":L.text(body), "page":page}

static func current_advice(game: Node = null) -> Dictionary:
	if not _valid(game) or not bool(_value(game, "started", false)):
		return _advice("first_shift", "Deine erste Schicht", "Beginne mit Sand für Beton und Erz für Stahl. Die Seite Erste Schicht führt dich von der Vorratskiste bis zur verteidigten Front.", "first_shift")
	var worker := _local_worker(game)
	var medical: Variant = _value(worker, "medical")
	if _valid(medical) and medical.has_method("incapacitated") and medical.incapacitated():
		return _advice("self_downed", "Du brauchst Hilfe", "Bleibe rettbar: Ein anderer Arbeiter oder SAN-1 kann dich am Körperort versorgen. Die Seite Crew & Forschung erklärt Wiederbelebung und kritische Verletzungen.", "crew")
	for teammate in _workers(game):
		if not _valid(teammate) or teammate == worker: continue
		var patient: Variant = _value(teammate, "medical")
		if _valid(patient) and patient.has_method("incapacitated") and patient.incapacitated():
			return _advice("crew_downed", "Ein Crewmitglied liegt am Boden", "Sichere den Weg zum Verletzten. Mit einem medizinischen Vorrat daneben stehen und Interaktion halten; Bewegung und Treffer unterbrechen die Hilfe.", "crew")
	var expedition: Variant = _value(game, "expedition")
	var stage := str(_value(expedition, "stage", "defense"))
	var vehicle: Variant = _value(expedition, "vehicle")
	var journey: Variant = _value(vehicle, "journey_state", {})
	if journey is Dictionary and str(journey.get("phase", "")) == "repair":
		var operator := int(journey.get("repair_operator", 0))
		if _valid(worker) and operator > 0 and operator != int(_value(worker, "player_id", 0)):
			return _advice("tire_repair", "Deine Aufgabe: Deckung geben", L.format("P%d wechselt den Reifen. Verteidige Fahrzeug und Mechaniker mit deiner Waffe; halte Abstand zum Hinterrad. Nach dem Wechsel wieder einsteigen.", operator), "travel")
		if operator == 0 and bool(journey.get("solo_assist", false)) and _valid(vehicle) and vehicle.has_method("_solo_service_medic") and _valid(vehicle._solo_service_medic()):
			return _advice("tire_repair", "SAN-1 arbeitet, du verteidigst", "SAN-1 übernimmt den Reifenwechsel. Halte Angreifer vom Fahrzeug fern und bleibe für Verletzte verfügbar. Sobald das Rad fertig ist, wieder einsteigen.", "travel")
		return _advice("tire_repair", "Deine Aufgabe: Reifen wechseln", "Am hinteren Rad E / X halten. Werkzeugschritte halten, Schrauben im grünen Fenster antippen oder je Schraube weiter halten. Die übrige Crew sichert Fahrzeug und Mechaniker; nach dem Wechsel wieder einsteigen.", "travel")
	var core: Variant = _value(game, "core")
	var core_hp := float(_value(core, "hp", 0.0))
	var core_max := float(_value(core, "max_hp", 0.0))
	if stage == "defense" and core_hp > 0 and core_max > 0 and core_hp < core_max*0.3:
		return _advice("critical_core", "Kernschutz hat Vorrang", "Bringe Stahl oder Schrott zum beschädigten Kern und halte Interaktion für die Reparatur. Andere Arbeiter decken dich und halten die Front besetzt.", "construction")
	var story: Variant = _value(game, "story")
	if _valid(story) and story.has_method("blocks_build") and story.blocks_build() and story.has_method("objective"):
		return _advice("story_objective", "Aktueller Storyauftrag", str(story.objective()), "first_shift")
	if _valid(worker) and worker.has_method("carried_count") and worker.has_method("capacity") and worker.carried_count() >= worker.capacity():
		return _advice("inventory_full", "Erst Platz im Inventar schaffen", "Beliefere eine wartende Anlage oder wähle mit Tab Material und lagere es mit G halten in eine passende Kiste ein. Q legt ein Stück ab; Halten legt den Stapel ab.", "workshop")
	var weapon := worker.get_node_or_null("WorkerWeapon") if _valid(worker) else null
	var mount: Variant = _value(worker, "mounted_turret")
	var personal_weapon_active: bool = not _valid(mount) or (mount.has_method("allows_personal_weapon") and mount.allows_personal_weapon())
	if personal_weapon_active and _valid(weapon) and weapon.has_method("current_ammo") and weapon.current_ammo() <= 0:
		var inventory: Variant = _value(worker, "inventory", {})
		var carried_ammo := int(inventory.get("ammo", 0)) if inventory is Dictionary else 0
		if int(_value(weapon, "reserve", 0)) > 0 or int(_value(weapon, "open_pack", 0)) > 0 or carried_ammo > 0:
			return _advice("reload", "Magazin leer, Munition vorhanden", "Nachladen nutzt die vorhandene Reserve und bei Bedarf eine mitgeführte Munitionskiste. Lade vor dem nächsten Gefecht nach; leere Magazine erzeugen keine kostenlosen Patronen.", "controls")
		return _advice("ammo_supply", "Munition nachführen", "Gehe an eine gefüllte Munitionskiste und lade dort nach, um die persönliche Reserve zu füllen. Eine Munitionspresse verarbeitet Stahl zu neuen Kisten.", "workshop")
	var rounds: Variant = _value(game, "rounds")
	if stage == "defense" and str(_value(rounds, "phase", "build")) == "attack":
		return _advice("defend", "Front halten, Crew decken", "Geschütze und Handwaffen brauchen freie Schusslinien und echte Munition. Reparaturen und Versorgung aufteilen; Technikpunkte und Rohstoffe werden nach dem Gefecht geborgen.", "crew")
	var focus: Variant = _value(worker, "focus")
	if _valid(focus) and focus.has_method("output_kind") and int(_value(focus, "output_amount", 0)) > 0:
		return _advice("collect_output", "Fertiges Produkt abholen", "Halte Interaktion an dieser Anlage, bis das Produkt entnommen ist. Die nächste Charge wartet, solange noch fertiges Material in der Anlage liegt.", "workshop")
	if stage in ["preparation", "map"]:
		return _advice("prepare_convoy", "Nächste Etappe vorbereiten", "Wähle ein Ziel auf der Einsatzkarte, kehre zur Garage zurück und prüfe Tank, Ladung und Munition. Danach steigt die benötigte Crew sichtbar in freie Sitze ein.", "travel")
	if stage in ["travel", "stop"]:
		return _advice("road_defense", "Fahrt und Sicherung", "Fahrer lenkt; Schütze und Mitfahrer decken die Reise. Hinterhalte räumen, sichere Halte nutzen und Munition aus echten Vorräten nachladen.", "travel")
	var wave := int(_value(rounds, "wave", 1))
	var flak: Variant = _value(game, "flak_station")
	if wave >= int(FlakStation.SPECS[1].wave) and _valid(flak) and bool(_value(flak, "available", false)) and not bool(_value(flak, "built", false)):
		return _advice("build_flak", "Luftabwehr vorbereiten", L.format("Am Flak-Baupult %s liefern und fertigbauen. Luftwellen brauchen funktionsfähige Luftabwehr; halte trotzdem genügend echte Munition bereit.", _materials(FlakStation.SPECS[1].cost)), "construction")
	var turret: Variant = _value(flak, "turret")
	if _valid(turret) and float(_value(turret, "hp", 0.0)) > 0 and int(_value(turret, "ammo", 0)) + int(_value(turret, "reserve", 0)) <= 0:
		return _advice("flak_ammo", "Flak gebaut, Munition fehlt", "Bringe eine Munitionskiste zur Flak. Wache und manuelle Bedienung verbrauchen echte Patronen; die gebaute Anlage allein hält keinen Luftangriff auf.", "construction")
	var bunker: Variant = _value(game, "scenario_bunker")
	var modules: Variant = _value(bunker, "modules", [])
	if modules is Array:
		for site in modules:
			if not _valid(site) or bool(_value(site, "built", false)) or not site.has_method("spec"): continue
			var spec: Variant = site.spec()
			if spec is Dictionary and wave >= int(spec.get("wave", 1)):
				return _advice("next_room", "Freigegebenen Raum ausbauen", L.format("%s: Aushub vollständig räumen, Stützen montieren, Restmaterial einbauen und aushärten lassen. Gesamtmaterial %s.", [str(spec.get("title", "")), _materials(spec.get("cost", {}))]), "construction")
	return _advice("build_pause", "Baupause nutzen", "Produkte abholen, Material verarbeiten, Fronten reparieren und Munition laden. Bereite die freigegebenen Räume vor; N startet anschließend die Warnphase.", "first_shift")
