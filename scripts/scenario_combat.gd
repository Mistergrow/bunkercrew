class_name ScenarioCombat
extends RefCounted
## Physical approach lanes for optional expedition scenarios. Coordinates belong
## to the arena; actor artwork alone changes facing, never the entire world.
var position_mode := "left"
var arena_left := 0.0
var arena_right := 1440.0
var ground_y := 430.0
var bunker_left := 400.0
var bunker_right := 1000.0
var core_x := 700.0

func configure(mode: String, left: float, right: float, floor_y: float, room_left: float, room_right: float, center_x: float) -> void:
	position_mode = mode if mode in ["left","center","right"] else "left"
	arena_left = minf(left,right)
	arena_right = maxf(left,right)
	ground_y = floor_y
	bunker_left = minf(room_left,room_right)
	bunker_right = maxf(room_left,room_right)
	core_x = center_x

func approach_direction(index: int) -> float:
	if position_mode == "right": return 1.0
	if position_mode == "center": return 1.0 if posmod(index,2)==1 else -1.0
	return -1.0

func configure_enemy(enemy: Node2D, _wave: int, index: int) -> void:
	var direction := approach_direction(maxi(0,index))
	enemy.set("attack_direction",direction)
	var airborne := enemy is AirMachine
	var spawn_x := arena_left-60.0 if direction>0 else arena_right+60.0
	enemy.position = Vector2(spawn_x,ground_y-330.0 if airborne else ground_y)
	if airborne:
		enemy.set("scenario_lanes",air_bounds(direction))
		enemy.set("scenario_floor",ground_y)

func air_bounds(direction: float) -> Vector2:
	if direction>0:
		var west_edge := minf(bunker_left-90.0,core_x-150.0)
		return Vector2(minf(arena_left+90.0,west_edge-110.0),west_edge)
	var edge := maxf(bunker_right+90.0,core_x+150.0)
	return Vector2(edge,maxf(edge+110.0,arena_right-90.0))

func field_position_allowed(x: float, half_width: float=0.0) -> bool:
	if x-half_width<arena_left+30 or x+half_width>arena_right-30: return false
	return x+half_width<bunker_left-12 or x-half_width>bunker_right+12

static func for_game(owner: Node) -> ScenarioCombat:
	if is_instance_valid(owner) and "scenario_combat" in owner:
		return owner.get("scenario_combat") as ScenarioCombat
	return null
