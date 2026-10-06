extends SceneTree
## Catalog integrity, actual engine translation, neutral network text and settings.
var checks:=0
var failures:=0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func _run() -> void:
	var german=JSON.parse_string(FileAccess.get_file_as_string("res://locales/de.json"))
	var english=JSON.parse_string(FileAccess.get_file_as_string("res://locales/en.json"))
	check(german is Dictionary and english is Dictionary and german.size()>900,"Both complete catalogs are exported and readable")
	check(german.size()==english.size(),"Both languages contain the same number of messages")
	for key: String in german:
		check(english.has(key) and english[key] is String and not str(english[key]).strip_edges().is_empty(),"English translation exists: "+key)
		check(LocaleText._format_specs(str(german[key]))==LocaleText._format_specs(str(english.get(key,""))),"Positional format values remain compatible: "+key)
	LocaleText.set_locale("de",false)
	check(LocaleText.text("BUNKERCREW")=="BUNKERCREW","German title uses the new shared brand")
	check(LocaleText.text("KO")=="KO","German compact downed label is explicit")
	var native:=Button.new()
	native.text="Beton"
	root.add_child(native)
	LocaleText.set_locale("en",false)
	check(LocaleText.text("BUNKERCREW")=="BUNKERCREW","English title preserves the same brand")
	check(LocaleText.text("KO")=="DOWN","English compact downed label follows the downed timer")
	check(LocaleText.format("P%d %s",[4,"Mara"])=="P4 Mara","Lobby crew format preserves slot and name")
	check(LocaleText.text("Spielt mit zwei bis vier Personen an einem Rechner.")=="Play with two to four people on one computer.","Local co-op description matches the supported crew size")
	check(str(TranslationServer.translate(native.text))=="Concrete","Native controls share the Godot translation server")
	check(LocaleText.text("Beton")=="Concrete" and LocaleText.text("BETON")=="CONCRETE","Case variants translate before text measurement")
	var template:="Manuelle Internetadresse: %s. UDP %d muss auf diesen Rechner zeigen."
	var english_message:=LocaleText.format(template,["203.0.113.42",24777])
	var wire:=LocaleText.message_payload(english_message)
	check(wire.key==template and LocaleText.valid_message_payload(wire),"Network notice carries the stable message and typed parameters")
	LocaleText.set_locale("de",false)
	check(LocaleText.message_text(wire)=="Manuelle Internetadresse: 203.0.113.42. UDP 24777 muss auf diesen Rechner zeigen.","German peer receives a German notice from an English host")
	check(LocaleText.text(english_message)==LocaleText.message_text(wire),"Cached formatted notices follow a live language switch")
	check(str(TranslationServer.translate("Concrete"))=="Beton","Already translated native controls can switch back")
	check(str(TranslationServer.translate("Copy"))=="Kopieren" and str(TranslationServer.translate("Select All"))=="Alles auswählen","Built-in text-field context menus also have German translations")
	check(not LocaleText.valid_message_payload({"key":template,"args":[{"literal":"host"},{"literal":"wrong type"}]}),"Malformed numeric network format values are rejected before formatting")
	check(not LocaleText.valid_message_payload({"key":template,"args":[1]}),"Missing network arguments are rejected")
	check(not LocaleText.valid_message_payload({"key":"not an authored message"}),"Unknown network message IDs are rejected")
	check(not LocaleText.valid_message_payload({"key":"BUNKERCREW","unexpected":"field"}),"Unknown network payload fields are rejected")
	check(LocaleText.valid_message_payload({"literal":"ABCD-1234"}),"Literal join codes remain untouched")
	var bonus:="Alle Spielerfiguren laufen und klettern 15 % schneller."
	check(LocaleText.valid_message_payload(LocaleText.message_payload(bonus)),"A written percent sign is not mistaken for a format placeholder")
	var data: Dictionary=LocaleText.data({"id":"steel","kind":"wall","label":"Beton"})
	check(data.id=="steel" and data.kind=="wall","Machine-readable world identifiers never change")
	check(not LocaleText.set_locale("fr",false) and LocaleText.current_locale()=="de","Unsupported locales cannot break the selected language")
	var previous_path:=LocaleText.settings_path
	LocaleText.settings_path="user://locale-test-%d.cfg" % OS.get_process_id()
	LocaleText.set_locale("en")
	var config:=ConfigFile.new()
	check(config.load(LocaleText.settings_path)==OK and config.get_value("language","locale")=="en","Language preference saves independently from player progress")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LocaleText.settings_path))
	LocaleText.settings_path=previous_path
	LocaleText.set_locale("de",false)
	native.queue_free()
	await process_frame
	print("LOCALIZATION CORE: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
