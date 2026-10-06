class_name WorkerIdentityArt
extends RefCounted
## Character identity is independent of the local player's amber/cyan label.
## All eight have separately authored head, hair, outfit and equipment shapes.
## The same 110-pose rig and clean side/rear body parts keep gameplay anchors.

const BODY := {
	"mara":preload("res://assets/workers/mara_body.png"),
	"branko":preload("res://assets/workers/branko_body.png"),
	"ivo":preload("res://assets/workers/ivo_body.png"),
	"nora":preload("res://assets/workers/nora_body.png"),
	"levin":preload("res://assets/workers/levin_body.png"),
	"selma":preload("res://assets/workers/selma_body.png"),
	"oskar":preload("res://assets/workers/oskar_body.png"),
	"rika":preload("res://assets/workers/rika_body.png"),
}
const ARMS := {
	"mara":preload("res://assets/workers/mara_arms.png"),
	"branko":preload("res://assets/workers/branko_arms.png"),
	"ivo":preload("res://assets/workers/ivo_arms.png"),
	"nora":preload("res://assets/workers/nora_arms.png"),
	"levin":preload("res://assets/workers/levin_arms.png"),
	"selma":preload("res://assets/workers/selma_arms.png"),
	"oskar":preload("res://assets/workers/oskar_arms.png"),
	"rika":preload("res://assets/workers/rika_arms.png"),
}
const TORSO := {
	"mara":preload("res://assets/workers/mara_torso.png"),
	"branko":preload("res://assets/workers/branko_torso.png"),
	"ivo":preload("res://assets/workers/ivo_torso.png"),
	"nora":preload("res://assets/workers/nora_torso.png"),
	"levin":preload("res://assets/workers/levin_torso.png"),
	"selma":preload("res://assets/workers/selma_torso.png"),
	"oskar":preload("res://assets/workers/oskar_torso.png"),
	"rika":preload("res://assets/workers/rika_torso.png"),
}
const HEAD := {
	"mara":preload("res://assets/workers/mara_head.png"),
	"branko":preload("res://assets/workers/branko_head.png"),
	"ivo":preload("res://assets/workers/ivo_head.png"),
	"nora":preload("res://assets/workers/nora_head.png"),
	"levin":preload("res://assets/workers/levin_head.png"),
	"selma":preload("res://assets/workers/selma_head.png"),
	"oskar":preload("res://assets/workers/oskar_head.png"),
	"rika":preload("res://assets/workers/rika_head.png"),
}
static var _profiles: Dictionary = {}
const BACK_TORSO := {
	"mara":preload("res://assets/workers/mara_back_torso.png"),
	"branko":preload("res://assets/workers/branko_back_torso.png"),
	"ivo":preload("res://assets/workers/ivo_back_torso.png"),
	"nora":preload("res://assets/workers/nora_back_torso.png"),
	"levin":preload("res://assets/workers/levin_back_torso.png"),
	"selma":preload("res://assets/workers/selma_back_torso.png"),
	"oskar":preload("res://assets/workers/oskar_back_torso.png"),
	"rika":preload("res://assets/workers/rika_back_torso.png"),
}
const BACK_HEAD := {
	"mara":preload("res://assets/workers/mara_back_head.png"),
	"branko":preload("res://assets/workers/branko_back_head.png"),
	"ivo":preload("res://assets/workers/ivo_back_head.png"),
	"nora":preload("res://assets/workers/nora_back_head.png"),
	"levin":preload("res://assets/workers/levin_back_head.png"),
	"selma":preload("res://assets/workers/selma_back_head.png"),
	"oskar":preload("res://assets/workers/oskar_back_head.png"),
	"rika":preload("res://assets/workers/rika_back_head.png"),
}

static func body(id: String) -> Texture2D:
	return BODY.get(CharacterCatalog.presentation_id(id,"visual"),BODY.mara)

static func arms(id: String) -> Texture2D:
	return ARMS.get(CharacterCatalog.presentation_id(id,"visual"),ARMS.mara)

static func torso(id: String, back: bool=false) -> Texture2D:
	return BACK_TORSO.get(CharacterCatalog.presentation_id(id,"visual"),BACK_TORSO.mara) if back else TORSO.get(CharacterCatalog.presentation_id(id,"visual"),TORSO.mara)

static func head(id: String, back: bool=false) -> Texture2D:
	return BACK_HEAD.get(CharacterCatalog.presentation_id(id,"visual"),BACK_HEAD.mara) if back else HEAD.get(CharacterCatalog.presentation_id(id,"visual"),HEAD.mara)

static func palette(id: String,base: Dictionary) -> Dictionary:
	id = CharacterCatalog.presentation_id(id,"visual")
	if _profiles.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/workers/character_visuals.json"))
		_profiles = data.identities if data is Dictionary else {}
	var colors := base.duplicate()
	for key in _profiles.get(id,_profiles.get("mara",{})).get("palette",{}):
		colors[key] = Color(_profiles.get(id,_profiles.mara).palette[key])
	return colors
