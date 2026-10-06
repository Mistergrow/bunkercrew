extends Node
## A short extrapolation of authoritative aircraft age keeps replica rotors alive
## between snapshots. This clock never moves a hull or fires a weapon.
var aircraft: Node2D
var clock := 0.0
var _sample := -1.0
var _since_sample := 0.0
var _redraw_clock := 0.0

func _ready() -> void:
	aircraft = get_parent()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	clock = aircraft.age

func _process(delta: float) -> void:
	if not is_instance_valid(aircraft) or aircraft.dead or get_tree().paused or not is_finite(delta) or delta <= 0.0: return
	var sample: float = aircraft.age
	if not is_finite(sample): return
	if sample != _sample:
		_sample = sample
		_since_sample = 0.0
	else:
		_since_sample = minf(0.12,_since_sample+delta)
	clock = sample+_since_sample
	_redraw_clock += delta
	var interval := 1.0/20.0 if preload("res://scripts/aircraft_art.gd").reduced(aircraft) else 1.0/60.0
	if _redraw_clock<interval: return
	_redraw_clock = 0.0
	aircraft._pose_parts()
	for part in [aircraft.body_part,aircraft.propulsion_part,aircraft.weapon_part]:
		if is_instance_valid(part): part.queue_redraw()
	aircraft.queue_redraw()
