extends RefCounted
## Observes gameplay without changing it. A reaction is discarded if the player
## resumes an action; it is never queued to unexpectedly block a later idle.

var work_elapsed := 0.0
var work_cooldown := 0.0
var previous_phase := ""
var pending := ""
var quiet_elapsed := 0.0

func reset() -> void:
	work_elapsed = 0.0
	work_cooldown = 0.0
	previous_phase = ""
	pending = ""
	quiet_elapsed = 0.0

func tick(delta: float,allowed: bool,working: bool,round_phase: String) -> String:
	work_cooldown = maxf(0.0,work_cooldown-delta)
	var finished_work := false
	if working:
		work_elapsed += delta
	else:
		finished_work = work_elapsed>=0.65
		work_elapsed = 0.0
	var cleared_wave := previous_phase=="attack" and round_phase=="salvage"
	previous_phase = round_phase
	if not allowed:
		pending = ""
		quiet_elapsed = 0.0
		return ""
	if cleared_wave:
		pending = "wave_clear"
		quiet_elapsed = 0.0
	elif finished_work and work_cooldown<=0.0 and pending.is_empty():
		pending = "work_finished"
		quiet_elapsed = 0.0
	if pending.is_empty():
		return ""
	quiet_elapsed += delta
	if quiet_elapsed<0.22:
		return ""
	var result := pending
	pending = ""
	quiet_elapsed = 0.0
	if result=="work_finished":
		work_cooldown = 8.0
	return result
