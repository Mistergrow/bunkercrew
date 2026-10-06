extends RefCounted
## Plain room text. The session authenticates authors and owns delivery.
const MAX_CHARACTERS := 240
const MAX_BYTES := 1024
const MAX_NAME_CHARACTERS := 24
const MAX_NAME_BYTES := 96
const MAX_HISTORY := 80
const MAX_SEQUENCE := 9007199254740991
const SEND_RATE := 1.0
const SEND_BURST := 3.0
const PRESETS := ["ready","help","ammo","thanks","nice","defend"]
const PRESET_TEXTS := {"ready":"Bereit!","help":"Brauche Hilfe!","ammo":"Brauche Munition!","thanks":"Danke!","nice":"Gut gemacht!","defend":"Bunker verteidigen!"}
const PRESET_LABELS := {"ready":"Bereit","help":"Hilfe","ammo":"Muni","thanks":"Danke","nice":"Stark","defend":"Verteidigen"}
const ERRORS := ["unavailable","invalid","controls","rate","pending","transport","timeout","preset","stale","blocked"]
var history: Array[Dictionary] = []
var highest_id := 0
var _budgets: Dictionary = {}

static func clean_text(value: String) -> String:
	return value.strip_edges()

static func forbidden_controls(value: String) -> bool:
	for character in value.length():
		var codepoint := value.unicode_at(character)
		if codepoint<32 or (codepoint>=127 and codepoint<160) or codepoint in [0x00AD,0x061C,0x180E,0x200B,0x200E,0x200F,0x2028,0x2029,0xFEFF] or (codepoint>=0x202A and codepoint<0x202F) or (codepoint>=0x2060 and codepoint<0x2070) or (codepoint>=0xFFF9 and codepoint<0xFFFC) or (codepoint>=0xE0000 and codepoint<0xE0080): return true
	return false

static func valid_text(value: Variant,allow_empty: bool=false) -> bool:
	return value is String and (allow_empty or not value.is_empty()) and value.length()<=MAX_CHARACTERS and value.to_utf8_buffer().size()<=MAX_BYTES and value==clean_text(value) and not forbidden_controls(value)

static func valid_name(value: Variant,allow_empty: bool=false) -> bool:
	return value is String and (allow_empty or not value.is_empty()) and value.length()<=MAX_NAME_CHARACTERS and value.to_utf8_buffer().size()<=MAX_NAME_BYTES and value==clean_text(value) and not forbidden_controls(value) and not value.contains(String.chr(0x200C)) and not value.contains(String.chr(0x200D))

static func valid_content(text: Variant,preset: Variant) -> bool:
	return preset is String and ((preset.is_empty() and valid_text(text)) or (preset in PRESETS and text is String and text.is_empty()))

static func valid_row(row: Variant) -> bool:
	if not row is Dictionary or row.size() not in [6,10]: return false
	if row.size() == 10:
		if row.get("private") != true or not row.get("recipient_id") is int or row.recipient_id < 1 or row.recipient_id > 4 or row.recipient_id == row.get("player_id"): return false
		for key in ["sender_key", "recipient_key"]:
			if not row.get(key) is String or row[key].length() != 48 or not row[key].is_valid_hex_number(false): return false
	for key in ["id","player_id","name","text","preset","time"]:
		if not row.has(key): return false
	var timestamp: Variant=row.time
	return row.id is int and row.id>=1 and row.id<=MAX_SEQUENCE and row.player_id is int and row.player_id>=1 and row.player_id<=4 and valid_name(row.name) and valid_content(row.text,row.preset) and (timestamp is int or timestamp is float) and is_finite(float(timestamp)) and timestamp>=0.0 and timestamp<1.0e12

static func valid_history(rows: Variant) -> bool:
	if not rows is Array or rows.size()>MAX_HISTORY: return false
	var previous := 0
	for row in rows:
		if not valid_row(row) or row.id<=previous: return false
		previous=row.id
	return true

static func error_text(code: String) -> String:
	var keys := {
		"unavailable":"Chat ist nur in einem verbundenen Online-Raum verfügbar.",
		"invalid":"Bitte eine Nachricht mit höchstens 240 Zeichen eingeben.",
		"controls":"Die Nachricht enthält nicht erlaubte Steuerzeichen.",
		"rate":"Bitte kurz warten, bevor du erneut schreibst.",
		"pending":"Eine Nachricht wird noch gesendet.",
		"transport":"Die Nachricht konnte nicht gesendet werden. Dein Entwurf bleibt erhalten.",
		"timeout":"Die Nachricht wurde noch nicht bestätigt. Dein Entwurf bleibt erhalten.",
		"preset":"Ungültiger Schnelltext.",
		"stale":"Die Nachricht konnte nicht gesendet werden. Dein Entwurf bleibt erhalten.",
		"blocked":"Diese private Nachricht kann wegen einer Blockierung nicht zugestellt werden.",
	}
	return LocaleText.text(str(keys.get(code,keys.transport)))

func allow_sender(key: String,now: float) -> bool:
	var bucket: Dictionary=_budgets.get(key,{"at":now,"tokens":SEND_BURST})
	bucket.tokens=minf(SEND_BURST,float(bucket.tokens)+maxf(0.0,now-float(bucket.at))*SEND_RATE)
	bucket.at=now
	var accepted: bool=bucket.tokens>=1.0
	if accepted: bucket.tokens-=1.0
	_budgets[key]=bucket
	return accepted

func refund_sender(key: String) -> void:
	if _budgets.has(key): _budgets[key].tokens=minf(SEND_BURST,float(_budgets[key].tokens)+1.0)

func append_authoritative(row: Dictionary) -> bool:
	if not valid_row(row) or row.id<=highest_id: return false
	highest_id=row.id
	history.append(row.duplicate(true))
	while history.size()>MAX_HISTORY: history.pop_front()
	return true

func clear() -> void:
	history.clear()
	highest_id=0
	_budgets.clear()
