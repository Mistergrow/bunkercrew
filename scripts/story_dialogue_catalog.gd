class_name StoryDialogueCatalog
extends RefCounted
## Authored phrases are the only dialogue payload accepted from the network.

const VOICE_ROOT := "res://assets/audio/story_voices_v2/"
static var SPEAKERS: Array[String] = _speakers()
const LINES := {
	"story_open": {"text":"Hier ist San. Das Warnnetz ist ausgefallen. Wir müssen die anderen Bunker erreichen. Zuerst sichern wir die Front.", "priority":2},
	"wall_hint": {"text":"Baut die Frontmauer fertig. Schalung, dann Beton. Wartet, bis er ausgehärtet ist.", "priority":2, "cooldown":45.0},
	"wall_ready": {"text":"Die Front hält. Jetzt müssen wir die ersten Angriffe abwehren.", "priority":2},
	"relay_first": {"text":"Das Relais braucht zwei Stahlteile. Bringt sie zum Funkgerät im Bunker.", "priority":2},
	"relay_online": {"text":"Relais verbunden. Ein schwaches Signal kommt durch. Da draußen ist noch jemand.", "priority":2},
	"relay_failure": {"text":"Die Verbindung ist weg. Repariert das Funkrelais mit einem Stahlteil.", "priority":3},
	"relay_restore": {"text":"Verbindung steht wieder. Die anderen Bunker warten auf unser Warnsignal.", "priority":2},
	"storm_tree": {"text":"Blitzeinschlag am Außenposten! Der Baum brennt. Bleibt im Schutz des Bunkers.", "priority":3},
	"final_signal": {"text":"Das Warnnetz ist bereit. Haltet die Taste am Funkgerät, bis die Übertragung läuft.", "priority":3},
	"transmission_live": {"text":"Das Signal läuft. Schützt den Kern, bis alle Stationen geantwortet haben.", "priority":3},
	"story_victory": {"text":"Sie antworten. Mehrere Bunker haben das Signal empfangen. Wir sind nicht mehr allein.", "priority":5, "ending":true},
	"story_defeat": {"text":"Der Bunker ist verloren. Unser Signal bricht ab. Vielleicht hört uns beim nächsten Mal jemand.", "priority":5, "ending":true},
	"warning_ground": {"text":"Bodenkontakt. Maschinen nähern sich der Front.", "priority":2, "cooldown":45.0, "expires":8.0},
	"warning_grenadier": {"text":"Granatwerfer! Bleibt in Deckung.", "priority":3, "cooldown":45.0, "expires":8.0},
	"warning_air": {"text":"Flugmaschinen im Anflug. Besetzt die Luftabwehr.", "priority":3, "cooldown":45.0, "expires":8.0},
	"warning_boss": {"text":"Eine schwere Maschine kommt. Munition auffüllen und Abstand halten.", "priority":4, "cooldown":60.0, "expires":10.0},
	"core_low": {"text":"Der Bunkerkern ist kritisch beschädigt. Wir müssen ihn jetzt reparieren.", "priority":4, "cooldown":45.0, "expires":9.0},
	"ally_down": {"text":"Jemand liegt am Boden. Helft mit einem Verband, wenn der Weg frei ist.", "priority":4, "cooldown":12.0, "expires":8.0},
	"revived": {"text":"Wieder auf den Beinen. Bleibt zusammen.", "priority":2, "cooldown":12.0, "expires":8.0},
	"wave_clear": {"text":"Für den Moment ist Ruhe. Reparieren und Vorräte auffüllen.", "priority":1, "cooldown":60.0, "expires":8.0},
	"world_sector07": {"text":"Sektor sieben. Zwischen den alten Werken liegt noch eine Leitung zum Warnnetz.", "priority":1},
	"world_ash_foundry": {"text":"Das Aschewerk glüht noch. Unter der Asche könnte das alte Relais überlebt haben.", "priority":1},
	"world_abandoned_harbor": {"text":"Der Hafen ist verlassen. Sein Funkturm hat früher die ganze Küste erreicht.", "priority":1},
	"world_basalt_quarry": {"text":"Basaltbruch. Die Felswände schützen uns, aber der Funkweg führt mitten durch die Grube.", "priority":1},
	"world_overgrown_steelworks": {"text":"Das Stahlwerk wächst zu. Wir suchen die alte Leitung unter den Wurzeln.", "priority":1},
	"world_frozen_rail_yard": {"text":"Frostbahnhof. Die Schienen sind tot. Hoffentlich hält die Signalleitung noch.", "priority":1},
	"world_iron_canyon": {"text":"Eisenschlucht. Hier trägt jedes Geräusch weit. Unser Signal muss noch weiter kommen.", "priority":1},
	"world_flooded_power_station": {"text":"Das Kraftwerk steht unter Wasser. Nur der Bunker und die alte Funkanlage sind noch trocken.", "priority":1},
	"world_mountain_pass": {"text":"Gewitterpass. Das Relais liegt hoch genug, um die anderen Bunker zu erreichen. Wenn der Sturm es zulässt.", "priority":1},
	"crew_wall": {"variants":{
		"oskar":"Die Mauer braucht ein ordentliches Fundament. Ich bringe den schweren Kram.",
		"rika":"Ich halte den Zugang frei. Danach sichere ich die Leitungen an der Mauer.",
		"nora":"Die Schalung muss gerade sitzen. Dann hält auch der Beton.",
		"levin":"Ich behalte die Straße im Blick. Ihr kümmert euch um die Mauer.",
		"selma":"Ich helfe beim Material. Aber lasst den Zugang für Verletzte frei.",
		"mara":"Erst die Mauer. Ich übernehme die Schalung.",
		"branko":"Ich schaffe Material heran. Diese Front bleibt stehen.",
		"ivo":"Verstanden. Ich prüfe die Schalung, dann kommt der Beton."}, "priority":1},
	"crew_reply": {"variants":{
		"oskar":"Da ist wirklich jemand. Gut, dass wir nicht aufgegeben haben.",
		"rika":"Das Signal kommt durch. Ich halte die Kontakte sauber.",
		"nora":"Das Signal ist schwach, aber sauber. Ich kann die Leitung stabilisieren.",
		"levin":"Ich habe draußen Bewegung gesehen. Vielleicht sind das die anderen.",
		"selma":"Solange sie antworten, haben wir eine Chance. Wir holen sie da raus.",
		"mara":"Gut. Wir halten hier durch, bis die Verbindung steht.",
		"branko":"Wenn da noch jemand ist, lassen wir ihn nicht im Stich.",
		"ivo":"Ich höre es auch. Schwach, aber das ist eine Stimme."}, "priority":1},
	"crew_storm": {"variants":{
		"oskar":"Runter vom freien Gelände. Unter dem Dach sind wir sicherer.",
		"rika":"Finger weg von blanken Kabeln! Ich schalte die Anlage frei.",
		"nora":"Weg von den Leitungen. Nach dem Einschlag kann noch Spannung drauf sein.",
		"levin":"Der Baum steht in Flammen. Ich suche einen sicheren Weg zurück.",
		"selma":"Alle unter das Dach. Ich sehe nach, ob jemand verletzt ist.",
		"mara":"Alle rein. Um den Baum kümmern wir uns nach dem Sturm.",
		"branko":"Der Stamm ist getroffen. Weg da, unter das Dach!",
		"ivo":"Das war nah. Ich prüfe drinnen die Leitungen."}, "priority":2, "expires":10.0},
	"crew_final": {"variants":{
		"oskar":"Die anderen leben. Dafür hat sich jeder schwere Sack gelohnt.",
		"rika":"Alle Stationen antworten. Diese Leitung lassen wir nicht mehr los.",
		"nora":"Das Netz hält. Diesmal haben wir etwas gebaut, das bleibt.",
		"levin":"Überall Antworten. Gut, dass wir weitergefahren sind.",
		"selma":"Sie sind noch da. Jetzt bringen wir Hilfe zu den anderen Bunkern.",
		"mara":"Dann hat sich diese Schicht gelohnt. Wir bleiben auf Empfang.",
		"branko":"Habt ihr das gehört? Sie leben noch. Wir haben es geschafft.",
		"ivo":"So viele Antworten. Ich lasse den Empfänger an."}, "priority":5, "ending":true},
	"crew_contact": {"variants":{
		"oskar":"Ich halte die Front. Hinter mir könnt ihr weiterarbeiten.",
		"rika":"Kontakt vorne! Ich sichere drinnen die Stromversorgung.",
		"nora":"Kontakt an der Front. Ich halte die Anlagen am Laufen.",
		"levin":"Ich habe sie im Visier. Wartet, bis sie aus der Deckung kommen.",
		"selma":"Bleibt in Deckung. Wenn jemand fällt, komme ich zu euch.",
		"mara":"An die Front. Wir lassen sie nicht an den Kern.",
		"branko":"Ich sehe sie. Jetzt ruhig zielen und Munition sparen.",
		"ivo":"Die kommen näher. Mein Werkzeug kann kurz warten."}, "priority":1, "cooldown":60.0, "expires":10.0},
	"crew_air": {"variants":{
		"oskar":"Oben am Himmel! Ich halte euch den Weg zur Abwehr frei.",
		"rika":"Flieger über uns! Strom für die Abwehr ist bereit.",
		"nora":"Luftkontakt. Ich prüfe die Versorgung der Abwehr.",
		"levin":"Über dem Dach! Ich markiere die Flugrichtung.",
		"selma":"Runter von der freien Fläche. Drinnen können wir euch versorgen.",
		"mara":"Augen nach oben. Wir müssen das Dach verteidigen.",
		"branko":"Die holen wir runter. Ich decke den Zugang.",
		"ivo":"Rotoren über uns. Hoffentlich hält die Luftabwehr."}, "priority":1, "cooldown":60.0, "expires":10.0},
	"crew_clear": {"variants":{
		"oskar":"Die Luft ist wieder rein. Ich räume das Material zusammen.",
		"rika":"Endlich Ruhe. Ich prüfe Sicherungen und Kabel.",
		"nora":"Kurz durchatmen. Ich prüfe zuerst die beschädigten Anlagen.",
		"levin":"Die Straße ist frei. Ich bleibe noch einen Moment auf Wache.",
		"selma":"Wer ist verletzt? Kommt nacheinander zu mir.",
		"mara":"Kurze Pause. Erst die Schäden, dann die Vorräte.",
		"branko":"Noch stehen wir. Ich schaue nach der Mauer.",
		"ivo":"Endlich kurz Ruhe. Wo ist mein Werkzeug?"}, "priority":1, "cooldown":60.0, "expires":10.0},
}


static func contains(id: String) -> bool:
	return LINES.has(id)


static func line(id: String, speaker_id: String = "san") -> Dictionary:
	var result := source_line(id, speaker_id)
	if result.is_empty(): return result
	result.source_text = result.text
	result.text = LocaleText.text(str(result.source_text))
	result.locale = LocaleText.current_locale()
	result.voice_path = recording_path(id, speaker_id, result.locale)
	return result


static func _speakers() -> Array[String]:
	var result: Array[String] = ["san"]
	for entry: Dictionary in CharacterCatalog.CHARACTERS: result.append(str(entry.id))
	return result

static func voice_profile(speaker_id: String) -> String:
	return "san" if speaker_id=="san" else CharacterCatalog.presentation_id(speaker_id,"voice")

static func source_line(id: String, speaker_id: String = "san") -> Dictionary:
	# Metadata always preserves the original German script, regardless of UI locale.
	if not LINES.has(id) or speaker_id not in SPEAKERS:
		return {}
	var result: Dictionary = LINES[id].duplicate(true)
	if result.has("variants"):
		var profile := voice_profile(speaker_id)
		if not result.variants.has(profile): return {}
		result.text = result.variants[profile]
		result.erase("variants")
	elif speaker_id != "san":
		return {}
	result.id = id
	result.speaker_id = speaker_id
	result.cooldown = float(result.get("cooldown", 2.0))
	result.expires = float(result.get("expires", 35.0))
	result.ending = bool(result.get("ending", false))
	return result


static func recording_path(id: String, speaker_id: String, locale: String) -> String:
	if locale not in LocaleText.SUPPORTED or source_line(id, speaker_id).is_empty(): return ""
	return VOICE_ROOT + ("en/" if locale == "en" else "") + voice_profile(speaker_id) + "_" + id + ".wav"


static func speaker_name(speaker_id: String) -> String:
	return LocaleText.text("SAN · FUNK") if speaker_id == "san" else str(CharacterCatalog.data(speaker_id).title).to_upper()


static func speaker_color(speaker_id: String) -> Color:
	return Color("a8b976") if speaker_id == "san" else Color(CharacterCatalog.data(speaker_id).accent)
