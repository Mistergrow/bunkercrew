class_name LocaleText
extends RefCounted
## German source messages are stable gettext-style IDs. Game IDs never change.
const Content := preload("res://scripts/content_registry.gd")
const SUPPORTED := ["de", "en"]
const MAX_MESSAGES := 2048
static var settings_path := "user://language.cfg"
static var _locale := "de"
static var _loaded := false
static var _tables: Dictionary = {}
static var _canonical: Dictionary = {}
static var _messages: Dictionary = {}
static var _message_order: Array[String] = []
static var _message_cursor := 0
static var _translations: Array[Translation] = []
static var _specs: Dictionary = {}

static func initialize() -> void:
	if _loaded: return
	_loaded = true
	for code: String in SUPPORTED:
		var parsed=JSON.parse_string(FileAccess.get_file_as_string("res://locales/"+code+".json"))
		_tables[code]=parsed if parsed is Dictionary else {}
		if not parsed is Dictionary: push_error("Invalid locale catalog: "+code)
		var additional: Dictionary = Content.translations(code)
		for source: String in additional:
			# Bundled content can add messages, never replace the game's wording.
			if not _tables[code].has(source): _tables[code][source] = additional[source]
	var sources: Dictionary=_tables.de
	for source: String in sources:
		if source.strip_edges().is_empty(): continue
		for variant in [source,source.to_upper(),source.capitalize()]:
			if variant.is_empty(): continue
			if not _canonical.has(variant): _canonical[variant]=variant
	for code: String in SUPPORTED:
		var expanded: Dictionary={}
		for source: String in sources:
			if source.strip_edges().is_empty(): continue
			var value: String=str(_tables[code].get(source,source))
			expanded[source]=value
			# Existing catalogs deliberately render headings in these two cases.
			if not expanded.has(source.to_upper()): expanded[source.to_upper()]=value.to_upper()
			if not expanded.has(source.capitalize()): expanded[source.capitalize()]=value.capitalize()
		_tables[code]=expanded
		for source: String in expanded:
			if not _canonical.has(expanded[source]): _canonical[expanded[source]]=source
	for code: String in SUPPORTED:
		var translation:=Translation.new()
		translation.locale=code
		for alias: String in _canonical:
			var source: String=_canonical[alias]
			translation.add_message(alias,str(_tables[code].get(source,source)))
		TranslationServer.add_translation(translation)
		_translations.append(translation)
	var config:=ConfigFile.new()
	if config.load(settings_path)==OK:
		var saved=config.get_value("language","locale","de")
		if saved is String and saved in SUPPORTED: _locale=saved
	TranslationServer.set_locale(_locale)

static func current_locale() -> String:
	initialize()
	return _locale

static func set_locale(code: String,persist: bool=true) -> bool:
	initialize()
	if code not in SUPPORTED: return false
	var changed:=code!=_locale
	_locale=code
	TranslationServer.set_locale(code)
	if persist and ("--no-profile-save" not in OS.get_cmdline_user_args() or settings_path!="user://language.cfg"):
		var config:=ConfigFile.new()
		config.set_value("language","locale",code)
		config.save(settings_path)
	if changed:
		var tree:=Engine.get_main_loop() as SceneTree
		if tree!=null:
			var service:=tree.root.get_node_or_null("Localization")
			if service!=null: service.emit_signal("locale_changed",code)
	return true

static func text(source: String) -> String:
	initialize()
	var key: String=str(_canonical.get(source,source))
	if _tables[_locale].has(key): return str(_tables[_locale][key])
	if _messages.has(source): return message_text(_messages[source])
	return source

static func data(value: Variant) -> Variant:
	if value is String: return text(value)
	if value is Array:
		var result: Array=[]
		for item in value: result.append(data(item))
		return result
	if value is Dictionary:
		var result: Dictionary=value.duplicate()
		for key in result:
			# Preserve machine-readable data even if an identifier resembles a word.
			if str(key) in ["id","kind","type","parent","icon","portrait","path","voice_path","source_text","weapon","state","environment","build_type","position","texture","layer_paths","visual_profile","motion_profile","dance_profile","voice_profile","background_profile","surface_profile","unlock_site","output","inputs","alternates","cost","recipe_id","accent","color","palette","sky_color","earth_tint"]:
				if result[key] is Array or result[key] is Dictionary: result[key] = result[key].duplicate(true)
				continue
			result[key]=data(result[key])
		return result
	return value

static func format(source: String,values: Variant) -> String:
	initialize()
	var key: String=str(_canonical.get(source,source))
	var translated_values=data(values)
	var result: String=text(key)%translated_values
	if _tables.de.has(key):
		if not _messages.has(result):
			if _message_order.size()<MAX_MESSAGES:
				_message_order.append(result)
			else:
				_messages.erase(_message_order[_message_cursor])
				_message_order[_message_cursor] = result
				_message_cursor = (_message_cursor+1)%MAX_MESSAGES
		_messages[result]={"key":key,"args":_encode_values(values)}
	return result

static func _encode_values(value: Variant,depth: int=0) -> Variant:
	if depth>6: return ""
	if value is String: return message_payload(value,depth+1)
	if value is Array:
		var result: Array=[]
		for item in value: result.append(_encode_values(item,depth+1))
		return result
	if value is int or value is float or value is bool: return value
	return str(value)

static func message_payload(value: String,depth: int=0) -> Dictionary:
	initialize()
	if depth>6: return {"literal":value.left(2048)}
	if _messages.has(value): return _messages[value].duplicate(true)
	var key: String=str(_canonical.get(value,value))
	if _tables.de.has(key): return {"key":key}
	return {"literal":value.left(2048)}

static func _decode_values(value: Variant,depth: int=0) -> Variant:
	if depth>6: return ""
	if value is Dictionary: return message_text(value,depth+1)
	if value is Array:
		var result: Array=[]
		for item in value.slice(0,24): result.append(_decode_values(item,depth+1))
		return result
	if value is int or value is bool: return value
	if value is float: return value if is_finite(value) else 0.0
	return ""

static func message_text(payload: Variant,depth: int=0) -> String:
	initialize()
	if not valid_message_payload(payload,depth): return ""
	if payload.get("key") is String and _tables.de.has(payload.key):
		var key: String=payload.key
		if payload.has("args"):
			return format(key,_decode_values(payload.args,depth+1))
		return text(key)
	if payload.get("literal") is String: return text(payload.literal.left(2048))
	return ""

static func valid_message_payload(payload: Variant,depth: int=0) -> bool:
	initialize()
	if depth>6 or not payload is Dictionary or payload.size()>2: return false
	if payload.has("literal"):
		return payload.size()==1 and payload.literal is String and payload.literal.length()<=2048
	for field in payload:
		if field not in ["key","args"]: return false
	if not payload.get("key") is String or not _tables.de.has(payload.key): return false
	var spec: Array=_format_specs(payload.key)
	if not payload.has("args"): return spec.is_empty()
	var values: Array=payload.args if payload.args is Array else [payload.args]
	if values.size()!=spec.size() or values.size()>24: return false
	for index in values.size():
		var value=values[index]
		if spec[index] in ["s","c"]:
			if value is Dictionary:
				if not valid_message_payload(value,depth+1): return false
			elif not (value is int or value is float or value is bool): return false
		elif not (value is int or value is float): return false
		if value is float and not is_finite(value): return false
	return true

static func _format_specs(source: String) -> Array:
	if _specs.has(source): return _specs[source]
	var expression:=RegEx.new()
	expression.compile("%[-+0-9]*(?:\\.[0-9]+)?([scdiouxXfFeEgGv%])")
	var result: Array=[]
	for found in expression.search_all(source):
		if found.get_string(1)!="%": result.append(found.get_string(1))
	_specs[source]=result
	return result
