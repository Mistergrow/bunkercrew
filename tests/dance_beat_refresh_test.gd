extends SceneTree
## Heard sparse kicks, user intensity and planted boot contacts share one tempo.
const WorkerRhythm := preload("res://scripts/worker_rhythm_pose.gd")
const MedicRhythm := preload("res://scripts/medic_rhythm_pose.gd")
const Moves := preload("res://scripts/worker_dance_moves.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Presentation := preload("res://scripts/rhythm_presentation.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func audible(clock: MusicBeatClock, time: float, events: Array = []) -> Dictionary:
	clock.advance(roundi(time * 48000.0) + 2880,48000,0.0,0.06,events)
	var frame := clock.frame()
	# This is the authoritative native song tempo, including legacy clocks.
	frame.bpm = clock.bpm
	frame.beat_period_seconds = 60.0 / clock.bpm
	frame.motion_gain = 1.0
	frame.dance_intensity = 1.0
	frame.dance_profiles = {"mara":{"style":"head_nod","intensity":1.0}}
	return frame

func _run() -> void:
	for tempo: float in [40.0,92.0,118.0,132.0,146.0,240.0]:
		var clock := MusicBeatClock.new()
		clock.configure(tempo)
		var period := 60.0 / tempo
		var worker := WorkerRhythm.new()
		worker.configure("mara")
		var medic := MedicRhythm.new()
		# Every second kick is deliberately absent. Both actors still respond
		# with the song's quarter-note duration instead of halving its tempo.
		for kick in 5:
			var time := float(kick) * period * 2.0
			var kick_frame := audible(clock,time,[{"sample":roundi(time * 48000.0),"track":0,"kind":"hit","strength":1.0}])
			worker.advance(period * 2.0,true,kick_frame)
			medic.advance(period * 2.0,true,kick_frame,5)
		check(is_equal_approx(worker._beat_period,period) and is_equal_approx(medic._period,period),"%.0f BPM sparse kick spacing cannot slow worker or SAN-1 nods" % tempo)
		var hit := 8.375 * period
		var frame := audible(clock,hit,[{"sample":roundi(hit * 48000.0),"track":0,"kind":"hit","strength":1.0}])
		worker.advance(0.0,true,frame)
		medic.advance(0.0,true,frame,5)
		check(is_equal_approx(worker._beat_period,period) and is_equal_approx(medic._period,period),"%.0f BPM syncopation cannot stretch the reaction envelope" % tempo)
		var after := audible(clock,hit + period * 0.09)
		worker.advance(0.0,true,after)
		var dip := PoseArt.neutral()
		worker.apply(dip,after)
		check(float(dip.head_tilt) > 0.19 and Vector2(dip.head_shift).y > 0.79,"%.0f BPM head dip follows the actual off-grid kick" % tempo)
		var quiet := audible(clock,hit + period * 3.0)
		worker.advance(period,true,quiet)
		medic.advance(period,true,quiet,5)
		check(worker._heard_kicks == 0.0 and not medic.is_active(),"%.0f BPM drum break retires dance readiness" % tempo)
		var drop := hit + period * 3.1
		var restart := audible(clock,drop,[{"sample":roundi(drop * 48000.0),"track":0,"kind":"hit","strength":1.0}])
		worker.advance(0.0,true,restart)
		check(worker._heard_kicks == 1.0,"%.0f BPM new drop starts from the newly heard kick" % tempo)
	for value: float in [0.22,0.5,0.75,1.0]:
		var rhythm := WorkerRhythm.new()
		rhythm.configure("mara")
		rhythm._movement = "crew_bounce"
		rhythm._dance_blend = 1.0
		rhythm.weight = value
		var neutral := PoseArt.neutral()
		var pose := neutral.duplicate(true)
		var frame := {"bar":1,"beat":0,"phase":0.5,"audible_seconds":3.0,"last_kick_seconds":1.0,"last_kick_strength":1.0}
		rhythm.apply(pose,frame)
		var full := WorkerRhythm.choreography("crew_bounce",4.5,"mara",1.0)
		for index in 2:
			var expected: Vector2 = Vector2(neutral.feet[index]).lerp(full.feet[index],value)
			check(Vector2(pose.feet[index]).distance_to(expected) < 0.0001,"%.0f percent intensity scales boot travel once" % (value * 100.0))
	for style: String in ["crew_bounce","crew_two_step","mara_precision_step","branko_foundry_stomp","ivo_knee_wave","nora_flow_step","levin_toprock","selma_skip_step","selma_double_shuffle"]:
		for boundary in range(1,17):
			var beat := float(boundary) * 0.5
			var epsilon := 0.0001
			var before := Moves.choreography(style,beat - epsilon)
			var after := Moves.choreography(style,beat + epsilon)
			for index in 2:
				if is_equal_approx(Moves.choreography(style,beat).feet[index].y,-3.0):
					check(absf(Vector2(after.feet[index]).y - Vector2(before.feet[index]).y) / (2.0 * epsilon) < 0.03,style + " lands with zero vertical contact velocity at the musical anchor")
	check(Presentation.beat_period({"bpm":120.0},1.0) == 0.5,"BPM remains usable when a legacy frame lacks explicit period")
	check(Presentation.beat_period({},0.67) == 0.67,"Legacy fixtures retain their measured kick spacing")
	check(Presentation.gain({"active":true,"motion_gain":NAN}) == 0.0,"Invalid cosmetic gain cannot corrupt joint transforms")
	var malformed := WorkerRhythm.new()
	malformed.configure("mara")
	var invalid_frame := {"active":true,"motion_gain":1.0,"dance_intensity":NAN,"audible_seconds":2.0,"last_kick_seconds":2.0,"last_kick_strength":1.0,"kick_count":5}
	check(not malformed.follows_kicks(invalid_frame) and malformed.advance(2.0,true,invalid_frame) == 0.0 and malformed.weight == 0.0,"Invalid dance intensity cannot reserve or corrupt the worker rig")
	var path := "res://artifacts/music-beat-refresh/dance"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	var result := {"checks":checks,"failures":failures,"authoritative_tempos":[40,92,118,132,146,240],"sparse_and_syncopated_kicks":true,"single_intensity_blend":true,"smooth_contact_velocity":true}
	var report := FileAccess.open(path + "/regression.json",FileAccess.WRITE)
	report.store_string(JSON.stringify(result,"\t"))
	print("DANCE BEAT REFRESH: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
