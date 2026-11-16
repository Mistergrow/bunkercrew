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

## Head/torso in every leaning, bending and lying attitude, authored upright on
## the texel grid by generate_character_workers.py (turned_sheet): row 0 torso
## and row 1 head in TURN_STEPS steps from 0, row 2 the rear pieces for a
## ladder sway of -BACK_TURNS..BACK_TURNS steps (torso first, then head),
## row 3 the supine coat from SUPINE_FIRST to SUPINE_LAST.
const TURNS := {
	"mara":preload("res://assets/workers/mara_turns.png"),
	"branko":preload("res://assets/workers/branko_turns.png"),
	"ivo":preload("res://assets/workers/ivo_turns.png"),
	"nora":preload("res://assets/workers/nora_turns.png"),
	"levin":preload("res://assets/workers/levin_turns.png"),
	"selma":preload("res://assets/workers/selma_turns.png"),
	"oskar":preload("res://assets/workers/oskar_turns.png"),
	"rika":preload("res://assets/workers/rika_turns.png"),
}
## Follow-through layers (assets/workers/generate_crew_layers.py): coat
## without gear, gear at rest/swung back/swung forward, head without hanging
## hair, hair at rest/back/forward, each for steps -LAYER_STEPS..LAYER_STEPS.
const LAYERS := {
	"mara":preload("res://assets/workers/mara_layers.png"),
	"branko":preload("res://assets/workers/branko_layers.png"),
	"ivo":preload("res://assets/workers/ivo_layers.png"),
	"nora":preload("res://assets/workers/nora_layers.png"),
	"levin":preload("res://assets/workers/levin_layers.png"),
	"selma":preload("res://assets/workers/selma_layers.png"),
	"oskar":preload("res://assets/workers/oskar_layers.png"),
	"rika":preload("res://assets/workers/rika_layers.png"),
}
const LAYER_STEPS := 3
const LAYER_ROWS := {"coat":0, "gear":1, "head":4, "hair":5}
const TURN_STEPS := 48
const TURN_CELL := 68
const TURN_ORIGIN := Vector2(34,34)
const BACK_TURNS := 3
## Steps around lying on the back (-12) that use the supine coat (row 3),
## whose pack is pressed flat under the back instead of sticking into the floor.
const SUPINE_FIRST := -15
const SUPINE_LAST := -7

static func turns(id: String) -> Texture2D:
	return TURNS.get(CharacterCatalog.presentation_id(id,"visual"),TURNS.mara)

## Nearest authored attitude of a rotation (radians, clockwise on screen).
static func turn_step(angle: float) -> int:
	return roundi(angle/TAU*TURN_STEPS)

static func turn_angle(step: int) -> float:
	return float(step)*TAU/TURN_STEPS

## Atlas cell of a piece ("torso"/"head") at a step, or an empty rect when the
## rear piece leans further than its authored ladder sway.
static func turn_region(piece: String, step: int, back: bool=false) -> Rect2:
	if back:
		if absi(step)>BACK_TURNS: return Rect2()
		var column := step+BACK_TURNS+(2*BACK_TURNS+1 if piece=="head" else 0)
		return Rect2(Vector2(column,2)*TURN_CELL,Vector2.ONE*TURN_CELL)
	if piece=="torso":
		var lying := posmod(step-SUPINE_FIRST,TURN_STEPS)
		if lying<=SUPINE_LAST-SUPINE_FIRST: return Rect2(Vector2(lying,3)*TURN_CELL,Vector2.ONE*TURN_CELL)
	return Rect2(Vector2(posmod(step,TURN_STEPS),0 if piece=="torso" else 1)*TURN_CELL,Vector2.ONE*TURN_CELL)

static func layers(id: String) -> Texture2D:
	return LAYERS.get(CharacterCatalog.presentation_id(id,"visual"),LAYERS.mara)

## Cell of a follow-through layer ("coat", "gear", "head", "hair") at a turn
## step, swung -1 (behind), 0 or +1 (forward); empty beyond LAYER_STEPS.
static func layer_region(layer: String, step: int, swing: int=0) -> Rect2:
	if absi(step)>LAYER_STEPS: return Rect2()
	var row: int = LAYER_ROWS[layer]
	if layer in ["gear","hair"]:
		row += 1 if swing<0 else (2 if swing>0 else 0)
	return Rect2(Vector2(step+LAYER_STEPS,row)*TURN_CELL,Vector2.ONE*TURN_CELL)

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
