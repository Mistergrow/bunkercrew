extends Node2D
## Positions and maximum display sizes live here, independently of gameplay.
## Individual props have no collision and remain behind actors and interactables.

const PROP = preload("res://scenes/level_prop.tscn")
var game
var manifest: Array[Dictionary] = []
var _placed: Array[Node2D] = []

func _ready() -> void:
	z_index = -7
	# Main bunker: work equipment stays left of the steel supply and wall slots.
	_place("SwitchCabinet", 0, Vector2(320, 430), Vector2(52, 88))
	_place("MechanicBench", 1, Vector2(458, 430), Vector2(96, 64))
	_place("ToolsCrate", 3, Vector2(382, 430), Vector2(38, 35))
	_place("OilBarrel", 4, Vector2(530, 430), Vector2(31, 46))
	_place("MainVent", 6, Vector2(371, 337), Vector2(49, 49), 1)
	_place("MainFuseBox", 10, Vector2(555, 318), Vector2(29, 37), 1)
	_place("BenchLamp", 5, Vector2(433, 280), Vector2(24, 38), 1)
	_place("DefenseLamp", 5, Vector2(700, 280), Vector2(24, 38), 1)
	# Production floor: ladder corridors at x240 and x342 remain visually clear.
	_place("ServiceConsole", 11, Vector2(128, 600), Vector2(68, 72))
	_place("ServiceGas", 7, Vector2(195, 600), Vector2(36, 64))
	_place("BinderPallet", 8, Vector2(382, 600), Vector2(55, 43))
	_place("MaintenanceCrate", 3, Vector2(739, 600), Vector2(40, 36))
	_place("MixerVent", 6, Vector2(610, 512), Vector2(43, 43), 1)
	_place("ServiceLamp", 5, Vector2(144, 469), Vector2(23, 35), 1)
	_place("MixingLamp", 5, Vector2(710, 469), Vector2(23, 35), 1)
	# Mine props form the back of the room. The x285..810 walkway has no new bodies.
	_place("WestMineBrace", 15, Vector2(174, 800), Vector2(186, 149))
	_place("EastMineBrace", 15, Vector2(1093, 800), Vector2(190, 150))
	_place("RepairBench", 1, Vector2(548, 800), Vector2(85, 52))
	_place("FurnaceToolCrate", 3, Vector2(761, 800), Vector2(36, 33))
	_place("FurnaceGas", 7, Vector2(720, 800), Vector2(29, 61))
	_place("SpareSteelPipes", 2, Vector2(454, 800), Vector2(72, 29))
	_place("MiningBarrow", 9, Vector2(808, 800), Vector2(65, 43))
	_place("CableReel", 14, Vector2(389, 800), Vector2(38, 41))
	_place("MineServiceLamp", 5, Vector2(570, 653), Vector2(23, 34), 1)
	_place("FurnaceLamp", 5, Vector2(760, 653), Vector2(23, 34), 1)
	# Roof clutter stays away from the ladder, ammunition and turret approach.
	_place("RoofBarrel", 4, Vector2(399, 245), Vector2(29, 40))
	_place("RoofSupplyBox", 3, Vector2(451, 245), Vector2(41, 34))
	_place("RoofScrap", 13, Vector2(518, 245), Vector2(68, 27))

func _place(label: String, kind: int, at: Vector2, size: Vector2, anchor: int = 0) -> void:
	var prop = PROP.instantiate()
	prop.name = label
	prop.kind_index = kind
	prop.position = at
	prop.display_size = size
	prop.anchor = anchor
	# Background equipment is slightly subdued so resources and workers read first.
	prop.modulate = Color(0.83, 0.85, 0.79)
	if kind in [2, 3, 13, 15]:
		prop.modulate = Color(0.72, 0.76, 0.71)
	add_child(prop)
	_placed.append(prop)
	manifest.append({"name": label, "kind": kind, "position": at, "max_size": size, "anchor": anchor})

func _process(_delta: float) -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.scenery):
		return
	var shift: Vector2 = game.scenery.offset * 0.24
	for index in _placed.size():
		_placed[index].position = manifest[index].position - shift
