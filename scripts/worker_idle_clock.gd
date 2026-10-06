class_name WorkerIdleClock
extends RefCounted
## Long, interruptible idle gestures. A shuffled bag avoids immediate repetition
## and lets both local workers keep independent timing without global RNG state.

const GESTURES: Array[String] = ["helmet","boot","thoughtful","stretch"]
const DURATIONS := {"helmet":2.8,"boot":3.1,"thoughtful":3.7,"stretch":3.8}
const Personality := preload("res://scripts/worker_personality.gd")
var character_id := ""
var gesture := ""
var elapsed := 0.0
var wait_remaining := 8.0
var previous := ""
var _bag: Array[String] = []
var _rng := RandomNumberGenerator.new()
var _was_allowed := false

func configure(seed_value: int,identity: String="") -> void:
	character_id = identity
	_rng.seed = seed_value
	_bag.clear()
	previous = ""
	gesture = ""
	elapsed = 0.0
	_was_allowed = false
	_wait()

func _wait() -> void:
	var bounds := Personality.wait_range(character_id)
	wait_remaining = _rng.randf_range(bounds.x,bounds.y)

func tick(delta: float, allowed: bool) -> void:
	if not allowed:
		if _was_allowed or not gesture.is_empty():
			cancel()
		_was_allowed = false
		return
	_was_allowed = true
	if not gesture.is_empty():
		elapsed += delta
		if elapsed >= duration():
			cancel()
		return
	wait_remaining -= delta
	if wait_remaining<=0:
		if _bag.is_empty():
			_bag = GESTURES.duplicate() if character_id.is_empty() else Personality.gestures(character_id)
			for index in range(_bag.size()-1,0,-1):
				var other := _rng.randi_range(0,index)
				var swap := _bag[index]
				_bag[index] = _bag[other]
				_bag[other] = swap
			if _bag.back()==previous:
				var swap := _bag[0]
				_bag[0] = _bag[-1]
				_bag[-1] = swap
		begin(_bag.pop_back())

func begin(kind: String) -> void:
	if not DURATIONS.has(kind) and not Personality.has_animation(kind):
		return
	gesture = kind
	previous = kind
	elapsed = 0.0

func cancel() -> void:
	gesture = ""
	elapsed = 0.0
	_wait()

func duration() -> float:
	return float(DURATIONS.get(gesture,Personality.duration(gesture)))

func progress() -> float:
	return clampf(elapsed/duration(),0.0,1.0)
