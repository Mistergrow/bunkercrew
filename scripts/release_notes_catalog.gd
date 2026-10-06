extends RefCounted
## Versioned release notes are shipped with the game and need no connection.
const PATH := "res://assets/releases/changelog.json"
const L := preload("res://scripts/locale_text.gd")
static var _entries: Array[Dictionary] = []

static func entries() -> Array[Dictionary]:
	if _entries.is_empty():
		var file:=FileAccess.open(PATH,FileAccess.READ)
		if file==null or file.get_length()>262144: return []
		var value: Variant=JSON.parse_string(file.get_as_text())
		if not value is Dictionary or value.get("schema")!=1 or not value.get("releases") is Array: return []
		for entry: Variant in value.releases:
			if not entry is Dictionary or not entry.get("version") is String or not entry.get("date") is String or not entry.get("changes") is Array: continue
			if entry.changes.size()>24 or not _localized(entry.get("title")): continue
			var valid:=true
			for change: Variant in entry.changes: valid=valid and _localized(change)
			if valid: _entries.append(entry.duplicate(true))
			if _entries.size()>=64: break
	return _entries.duplicate(true)

static func _localized(value: Variant) -> bool:
	return value is Dictionary and value.get("de") is String and value.get("en") is String and not value.de.strip_edges().is_empty() and not value.en.strip_edges().is_empty() and value.de.length()<=1000 and value.en.length()<=1000

static func translated(value: Dictionary) -> String:
	return L.text(str(value.get(L.current_locale(),value.get("de",""))))

static func body_text() -> String:
	var paragraphs: Array[String]=[]
	for entry: Dictionary in entries():
		paragraphs.append("%s · %s\n%s" % [entry.version,entry.date,translated(entry.title)])
		for change: Dictionary in entry.changes: paragraphs.append("• "+translated(change))
		paragraphs.append("")
	return "\n".join(paragraphs)
