extends SceneTree
## Measure real blended, constrained joint motion rather than dance names.
## The shared crew steps remain shared while arms retain each identity.
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Defaults := preload("res://scripts/audio_defaults.gd")
const SAMPLES := 129
const OUTPUT := "res://artifacts/character-dance-identity-20261005/regression.json"
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func heard_frame(beats: float,id: String,style: String,gain: float) -> Dictionary:
	return {"active":true,"phase":fposmod(beats,1.0),"bar":floori(beats/4.0),"beat":floori(beats)%4,"audible_seconds":beats*.5,"last_kick_seconds":floorf(beats)*.5,"last_kick_strength":1.0,"kick_count":floori(beats)+1,"bpm":120.0,"beat_period_seconds":.5,"motion_gain":1.0,"dance_intensity":gain,"dance_profiles":{id:{"style":style,"intensity":1.0}},"genre":"minimal_techno","character_level":10,"dance_preview":false}

func _trace(id: String,style: String,gain: float) -> Array:
	var rhythm := Rhythm.new()
	rhythm.configure(id)
	for beat in 8:
		rhythm.advance(.5,true,heard_frame(float(beat),id,style,gain))
	check(rhythm._dance_blend==1.0 and is_equal_approx(rhythm.weight,gain),id+": real heard kicks establish "+style+" at the requested intensity")
	var trace: Array = []
	var safe := true
	for sample in SAMPLES:
		var frame := heard_frame(8.0+float(sample)/16.0,id,style,gain)
		rhythm.advance(1.0/32.0,true,frame)
		var pose := PoseArt.neutral()
		rhythm.apply(pose,frame)
		var body := PoseArt.torso_transform(pose)
		for index in 2:
			var hip: Vector2 = pose.hip+Vector2(-4 if index==0 else 4,0)
			var shoulder := body*PoseArt.shoulder_local(pose,index)
			safe = safe and Vector2(pose.feet[index]).is_finite() and Vector2(pose.hands[index]).is_finite()
			safe = safe and hip.distance_to(pose.feet[index])<=23.801 and shoulder.distance_to(pose.hands[index])<=22.901
		safe = safe and not pose.has("front_weight") and not bool(pose.get("back",false))
		safe = safe and (is_equal_approx(pose.feet[0].y,-3.0) or is_equal_approx(pose.feet[1].y,-3.0))
		trace.append([pose.hip,pose.shoulder,pose.feet[0],pose.feet[1],pose.hands[0],pose.hands[1]])
	check(safe,id+": "+style+" stays in the grounded side rig with connected limbs")
	return trace

func _distance(first: Array,second: Array) -> float:
	var squared := 0.0
	for sample in SAMPLES:
		for joint in 6:
			squared += Vector2(first[sample][joint]).distance_squared_to(second[sample][joint])
	return sqrt(squared/float(SAMPLES*6))

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var defaults := Defaults.dance_profiles()
	check(Dance.IDS.all(func(id): return defaults[id].style=="character_default" and defaults[id].intensity==1.0),"All eight existing character defaults retain automatic repertoire and their authored motion strength")
	var own_minimum := INF
	var shared_minimum := INF
	var metrics: Array[Dictionary] = []
	for gain: float in [Defaults.DANCE_INTENSITY,1.0,.5]:
		var unique: Dictionary = {}
		for id: String in Dance.IDS:
			for style: String in Dance.UNIQUE_STYLES[id]:
				unique[style] = _trace(id,style,gain)
		check(unique.size()==40,"Forty personal moves reach their own character through the actual audible dance gate")
		var minimum := INF
		var nearest: Array[String] = []
		for first: String in unique:
			for second: String in unique:
				if first>=second:
					continue
				var distance := _distance(unique[first],unique[second])
				check(distance>minf(gain,1.0)*1.7,first+" and "+second+" retain visibly separate constrained motion at "+str(gain)+" strength")
				if distance<minimum:
					minimum = distance
					nearest.assign([first,second])
		own_minimum = minf(own_minimum,minimum)
		metrics.append({"kind":"personal","gain":gain,"minimum_joint_rms_native_px":minimum,"nearest":nearest})
		for style: String in Dance.SHARED_STYLES:
			var shared: Dictionary = {}
			for id: String in Dance.IDS:
				shared[id] = _trace(id,style,gain)
			minimum = INF
			for first: String in shared:
				for second: String in shared:
					if first>=second:
						continue
					var distance := _distance(shared[first],shared[second])
					check(distance>minf(gain,1.0)*.75,first+" and "+second+" keep their own shoulders and arms in "+style)
					minimum = minf(minimum,distance)
					var same_steps := true
					for sample in SAMPLES:
						for joint in [0,2,3]:
							same_steps = same_steps and Vector2(shared[first][sample][joint]).is_equal_approx(shared[second][sample][joint])
					check(same_steps,style+": character phrasing preserves the shared step pattern and exact boot anchors")
			shared_minimum = minf(shared_minimum,minimum)
			metrics.append({"kind":"shared","style":style,"gain":gain,"minimum_joint_rms_native_px":minimum})
	for id: String in Dance.IDS:
		for beat in range(0,9):
			var pose := Rhythm.choreography("crew_clap",float(beat),id)
			check(Vector2(pose.hands[0]).distance_to(pose.hands[1])<.0001,id+": common clap palms meet on the actual musical kick")
	var path := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(OUTPUT,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":metrics,"own_minimum_rms":own_minimum,"shared_minimum_rms":shared_minimum,"existing_global_default":Defaults.DANCE_INTENSITY,"existing_character_default":1.0,"fixture":"Eight character IDs, 40 unlocked exclusive moves plus 3 shared dances. Real WorkerRhythmPose advance/apply at 120 BPM over 8 beats after 8 heard kicks. Existing global default 1.5 with character gain 1.0 is preserved and tested; global gains 1.0 and 0.5 add quieter-motion comparisons. Geometric difference supports visual review and does not replace it."},"  "))
	file.close()
	print("WORKER DANCE IDENTITY: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
