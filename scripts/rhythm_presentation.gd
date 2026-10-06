extends RefCounted
## Cached audible beat state is cosmetic. This helper never changes simulation,
## contact phases, weapon timing, materials or the number of drawing commands.

static func music_for(actor: Node):
	if not is_instance_valid(actor) or not "game" in actor:
		return null
	var game = actor.get("game")
	if not is_instance_valid(game) or not "audio" in game:
		return null
	var audio = game.get("audio")
	if not is_instance_valid(audio) or not "live_music" in audio:
		return null
	var music = audio.get("live_music")
	return music if is_instance_valid(music) and music.has_method("rhythm_frame") else null

static func frame_for(actor: Node) -> Dictionary:
	var music = music_for(actor)
	return music.rhythm_frame() if is_instance_valid(music) else {}

static func gain(frame: Dictionary) -> float:
	if not bool(frame.get("active", false)):
		return 0.0
	var amount := float(frame.get("motion_gain", 0.22 if frame.get("reduced_motion", false) else 1.0))
	return clampf(amount, 0.0, 1.0) if is_finite(amount) else 0.0

static func beat_period(frame: Dictionary, fallback: float = 0.5) -> float:
	# Kick spacing changes in sparse intros and syncopated arrangements. A
	# missing drum never changes the song tempo or stretches a visible nod.
	var period := float(frame.get("beat_period_seconds", 0.0))
	if is_finite(period) and period >= 0.25 and period <= 1.5:
		return period
	var tempo := float(frame.get("bpm", 0.0))
	if is_finite(tempo) and tempo >= 40.0 and tempo <= 240.0:
		return 60.0 / tempo
	return clampf(fallback, 0.30, 1.0) if is_finite(fallback) else 0.5

static func machine_accent(machine: Node2D) -> void:
	if not is_instance_valid(machine.body_part):
		return
	var frame := frame_for(machine)
	var pulse := clampf(float(frame.get("accent_pulse", frame.get("beat_pulse", 0.0))), 0.0, 1.0) * gain(frame)
	# The existing hull vertex color glints gently. Wheels, tracks, feet, recoil
	# and weather atlas materials keep their exact existing state.
	if float(machine.get("hit_flash")) > 0.0:
		pulse = 0.0
	var tint := Color(1.0 + pulse * 0.045, 1.0 + pulse * 0.027, 1.0 + pulse * 0.009)
	if machine.body_part.self_modulate != tint:
		machine.body_part.self_modulate = tint
