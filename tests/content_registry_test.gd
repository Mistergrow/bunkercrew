extends SceneTree
const Content := preload("res://scripts/content_registry.gd")
var checked := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checked += 1
	if not value:
		failed += 1
		printerr("FAIL: " + label)

func _run() -> void:
	check(Content.diagnostics().is_empty(), "installed content validates: " + str(Content.diagnostics()))
	check(Content.entries("characters").size() >= 8, "original eight characters remain")
	check(Content.entries("workshop_recipes").size() >= 5, "original five workshop recipes remain")
	check(Content.entries("environments").size() >= 13, "original thirteen environments remain")
	var reads := Content.read_count()
	for index in 100:
		var item := Content.data("items", "steel")
		item["label"] = "changed copy"
		var characters := Content.entries("characters")
		characters[0]["hp"] = -1
	check(Content.read_count() == reads, "indexed lookup performs no repeated file reads")
	check(Content.data("items", "steel").label != "changed copy", "caller cannot mutate item definitions")
	check(Content.data("characters", "mara").hp == 100, "caller cannot mutate character definitions")
	check(Content.fingerprint().length() == 64, "content fingerprint is SHA256")
	check(Content.data("items", "missing").is_empty(), "missing ID has explicit empty result")
	var documents := installed_documents()
	var valid := Content.build_index(documents)
	check(valid.errors.is_empty(), "pure validator accepts installed documents")
	check(valid.fingerprint == Content.fingerprint(), "runtime and preflight fingerprints agree")
	var extension := example_pack()
	var with_extension := documents.duplicate(true)
	with_extension.append(extension)
	var accepted := Content.build_index(with_extension)
	check(accepted.errors.is_empty(), "new character using authored profiles accepted")
	check(accepted.index.characters.has("fixturepack:ninth"), "namespaced content joins character index")
	check(accepted.fingerprint != valid.fingerprint, "gameplay content changes fingerprint")
	var translated := with_extension.duplicate(true)
	translated[-1]["translations"] = {"de":{"Neue Meldung":"Neue Meldung"}, "en":{"Neue Meldung":"New message"}}
	var translated_state := Content.build_index(translated)
	check(translated_state.errors.is_empty(), "both translated languages accepted")
	check(translated_state.fingerprint == accepted.fingerprint, "localization does not change network content identity")
	var invalid := with_extension.duplicate(true)
	invalid[-1].entries.characters[0].visual_profile = "unknown"
	invalid[-1].entries["items"] = [{"id":"fixturepack:bad"}]
	var rejected := Content.build_index(invalid)
	check(not rejected.errors.is_empty(), "malformed pack diagnosed")
	check(not rejected.index.characters.has("fixturepack:ninth") and not rejected.index.items.has("fixturepack:bad"), "malformed pack is rejected atomically")
	check(rejected.index.characters.has("mara"), "invalid optional pack preserves core")
	var duplicate := with_extension.duplicate(true)
	duplicate.append(extension.duplicate(true))
	check(not Content.build_index(duplicate).errors.is_empty(), "duplicate pack ID rejected")
	var override := with_extension.duplicate(true)
	override[-1].entries.characters[0].id = "mara"
	check(not Content.build_index(override).errors.is_empty(), "base content cannot be overwritten")
	var dependency := with_extension.duplicate(true)
	dependency[-1].requires[0].version = "missing"
	check(not Content.build_index(dependency).index.characters.has("fixturepack:ninth"), "dependency version mismatch rejects dependent pack")
	var core_documents: Array = documents.filter(func(document): return document.id == Content.CORE).duplicate(true)
	var core_first := core_documents.duplicate(true)
	core_first.append(extension.duplicate(true))
	core_documents.push_front(extension.duplicate(true))
	check(Content.build_index(core_documents).fingerprint == Content.build_index(core_first).fingerprint, "core precedes its dependent regardless of manifest order")
	check(not Content.resource_path("res://assets/../private.json"), "resource traversal rejected")
	check(not Content.resource_path("user://friend.cfg"), "user profile path rejected")
	check(not Content.valid_id("Bad Name"), "unsafe identifiers rejected")
	for special in [["bad array"], "x".repeat(513)]:
		var malformed := with_extension.duplicate(true)
		malformed[-1].entries.characters[0]["special"] = special
		check(not Content.build_index(malformed).index.characters.has("fixturepack:ninth"), "malformed presentation text never reaches character menu")
	var malformed_slots := documents.duplicate(true)
	malformed_slots[0].entries.characters[0].starter_slot = 2.0
	check(not Content.build_index(malformed_slots).errors.is_empty(), "duplicate core starters fail before party construction")
	var bad_region := documents.duplicate(true)
	bad_region[0].entries.workshop_recipes[0].art.region = [100000,0,24,24]
	check(not Content.build_index(bad_region).errors.is_empty(), "out-of-bounds authored picture region rejected")
	var malformed_format := translated.duplicate(true)
	malformed_format[-1].translations = {"de":{"Prüfwert %d":"Prüfwert %d"}, "en":{"Prüfwert %d":"Test value %s"}}
	check(not Content.build_index(malformed_format).errors.is_empty(), "mismatched translation formatting rejected")
	print("CONTENT_REGISTRY ", checked - failed, "/", checked)
	quit(1 if failed else 0)

func installed_documents() -> Array:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Content.MANIFEST))
	var result: Array = []
	for path in manifest.packs:
		var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		document["entries"] = {}
		for kind in document.catalogs:
			var source: Dictionary = document.catalogs[kind]
			var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source.path))
			document.entries[kind] = parsed[source.field]
		result.append(document)
	return result

func example_pack() -> Dictionary:
	var ninth := Content.data("characters", "ivo")
	ninth.id = "fixturepack:ninth"
	ninth.title = "NINTH"
	ninth.erase("starter_slot")
	return {"schema":1, "id":"fixturepack", "version":"1", "requires":[{"id":Content.CORE,"version":"1"}], "entries":{"characters":[ninth]}}
