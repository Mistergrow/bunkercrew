extends SceneTree
## Incremental presentation CPU cost: four crew + forty existing machine parts.
## Pose allocation, simulation and procedural drawing belong to baseline work.
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const Presentation := preload("res://scripts/rhythm_presentation.gd")
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")

class MusicStub extends Node:
	var state := {"active":true,"phase":0.2,"beat":0,"beat_pulse":0.7,"accent_pulse":0.8,"motion_gain":1.0,"dance_intensity":1.5,"dance_profiles":{},"audible_seconds":0.12,"last_kick_seconds":0.0,"last_kick_strength":1.0,"kick_count":1}
	func rhythm_frame() -> Dictionary: return state
class AudioStub extends Node:
	var live_music: MusicStub
class World extends Node2D:
	var audio: AudioStub
class Hull extends Node2D:
	var game: Node
	var body_part: Node2D
	var hit_flash := 0.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := World.new()
	root.add_child(world)
	world.audio = AudioStub.new()
	world.add_child(world.audio)
	world.audio.live_music = MusicStub.new()
	world.audio.add_child(world.audio.live_music)
	var rigs: Array = []
	for id: String in Dance.IDS.slice(0,4):
		var rig := Rhythm.new()
		rig.configure(id)
		for kick in 5:
			world.audio.live_music.state.kick_count = kick+1
			world.audio.live_music.state.last_kick_seconds = float(kick)*0.55
			world.audio.live_music.state.audible_seconds = float(kick)*0.55+0.12
			rig.advance(0.55,true,world.audio.live_music.state)
		rigs.append(rig)
	var hulls: Array[Hull] = []
	for index in 40:
		var hull := Hull.new()
		hull.game = world
		hull.body_part = Node2D.new()
		world.add_child(hull)
		hull.add_child(hull.body_part)
		hulls.append(hull)
	var measurements: Dictionary = {}
	var worst_p95 := 0.0
	var worst_mean := 0.0
	for style: String in ["character_default"]+Dance.FULL_BODY_STYLES:
		var state: Dictionary = world.audio.live_music.state
		state.dance_profiles = {}
		for index in 4:
			var id: String = Dance.IDS[index]
			state.dance_profiles[id] = {"style":style,"intensity":1.5}
			rigs[index].configure(id)
			for kick in 5:
				state.kick_count = kick+1
				state.last_kick_seconds = float(kick)*0.55
				state.audible_seconds = float(kick)*0.55+0.12
				rigs[index].advance(0.55,true,state)
		var times: Array[float] = []
		for frame in 1500:
			state.phase = float(frame%60)/60.0
			state.beat = (floori(float(frame)/60.0))%4
			state.bar = floori(float(frame)/240.0)
			state.audible_seconds = float(frame)/60.0
			state.last_kick_seconds = float(floori(float(frame)/60.0))
			state.kick_count = floori(float(frame)/60.0)+6
			var poses: Array = []
			for _index in 4: poses.append(WorkerPoseArt.neutral())
			var start := Time.get_ticks_usec()
			for index in 4:
				rigs[index].advance(1.0/60.0,true,state)
				rigs[index].apply(poses[index],state)
			for hull in hulls: Presentation.machine_accent(hull)
			if frame>=300: times.append(float(Time.get_ticks_usec()-start)/1000.0)
		times.sort()
		var mean := 0.0
		for value in times: mean += value
		mean /= times.size()
		var p95: float = times[floori(times.size()*.95)]
		measurements[style] = {"mean_ms":mean,"p95_ms":p95,"frames":times.size()}
		worst_p95 = maxf(worst_p95,p95)
		worst_mean = maxf(worst_mean,mean)
	var result := {"crew":4,"enemies":40,"frames":measurements.size()*1200,"mean_ms":worst_mean,"p95_ms":worst_p95,"styles":measurements,"budget_ms":0.3,"within_budget":worst_p95<=0.3,"scope":"Worst measured incremental GDScript rhythm transform/color updates across four matching rigs per style; simulation, source pose allocation and existing drawing excluded"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/rhythm-music"))
	var file := FileAccess.open("res://artifacts/rhythm-music/visual-budget.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("RHYTHM VISUAL BUDGET: "+JSON.stringify(result))
	await Cleanup.free_scene(world,self)
	quit(0 if result.within_budget else 1)
