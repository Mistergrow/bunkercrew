extends SceneTree
const Catalog := preload("res://scripts/convoy_air_encounter_catalog.gd")
const Flybys := preload("res://scripts/convoy_air_encounters.gd")
const Schema := preload("res://scripts/network_replication_schema.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var mixer_capture: AudioEffectCapture

class AudioProbe extends Node:
	var sfx_volume := .5
	var acoustics = null

class WeatherProbe extends Node:
	var reduced_effects := false

class VehicleProbe extends Node2D:
	var game: Node
	var animation_time := 0.0
	var destroyed := false
	var hp := 600.0
	var ammo := 40
	var cargo := {"steel":3}
	var journey_state := ConvoyJourney.new_state("driving")

class ControllerProbe extends Node:
	var vehicle: Node2D
	var state: CampaignState
	var road_open := true
	var stage := "travel"
	var stop_done := false

class GameProbe extends Node2D:
	var started := true
	var camera: Camera2D
	var weather: WeatherProbe
	var audio: AudioProbe
	var scenario_options := {"environment":"ash_foundry"}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func sample_mix() -> Dictionary:
	var until:=Time.get_ticks_msec()+130
	while Time.get_ticks_msec()<until: await process_frame
	mixer_capture.clear_buffer()
	until=Time.get_ticks_msec()+240
	while Time.get_ticks_msec()<until: await process_frame
	var frames:=mixer_capture.get_buffer(mixer_capture.get_frames_available())
	var left:=0.0
	var right:=0.0
	for frame in frames:
		left+=frame.x*frame.x
		right+=frame.y*frame.y
	return {"frames":frames.size(),"left":sqrt(left/maxi(1,frames.size())),"right":sqrt(right/maxi(1,frames.size()))}

func _run() -> void:
	for site in CampaignCatalog.NODES:
		if site.id=="last_shift": continue
		var slots := Catalog.slots(str(site.id))
		check(slots.size()==2 and slots==Catalog.slots(str(site.id)),str(site.id)+" selects two deterministic route slots")
		check(slots[0].id!=slots[1].id and Catalog.slots(str(site.id),true)[0].id!=slots[0].id,str(site.id)+" varies the late slot and after-stop return leg")
	check(Catalog.slots("bad_route").is_empty() and Catalog.active("harbor",NAN).is_empty() and Catalog.active("harbor",-1).is_empty(),"Invalid route/clock cannot create a flyby")
	for id in Catalog.ORDER:
		var spec: Dictionary = Catalog.DEFINITIONS[id].duplicate(true)
		check(spec.count>0 and spec.count<=Catalog.MAX_AIRCRAFT and AirEnemyCatalog.is_air(spec.kind),id+" uses a bounded existing aircraft formation")
		spec.elapsed = float(spec.duration)*.5
		var middle := Catalog.pose(spec,0,Rect2(0,-100,1500,900))
		check(middle.position.is_finite() and middle.alpha==1 and middle.facing==-spec.direction,id+" yields a visible, correctly facing authored center pass")
		spec.elapsed = 0.0
		check(Catalog.pose(spec,0,Rect2(0,-100,1500,900)).alpha==0,id+" fades its distant approach")
		spec.elapsed = float(spec.duration)
		check(Catalog.pose(spec,0,Rect2(0,-100,1500,900)).alpha==0,id+" fades its departure")
		check(Catalog.pose(spec,2,Rect2(0,-100,1500,900)).is_empty(),id+" rejects an aircraft outside the finite formation")
	check(Catalog.active("harbor",3.99).is_empty() and Catalog.active("harbor",4.8).id=="survey_pair" and Catalog.active("harbor",22).is_empty() and Catalog.active("harbor",34).id=="low_transport" and Catalog.active("harbor",80).is_empty(),"Two short slots have a long quiet interval and no repeated spawn loop")
	var game := GameProbe.new()
	root.add_child(game)
	game.camera = Camera2D.new()
	game.camera.position = Vector2(1450,270)
	game.add_child(game.camera)
	game.camera.make_current()
	game.weather = WeatherProbe.new()
	game.add_child(game.weather)
	game.audio = AudioProbe.new()
	game.add_child(game.audio)
	var trip := ControllerProbe.new()
	trip.state = CampaignState.new()
	trip.state.persistence_enabled = false
	trip.state.pending_node = "harbor"
	game.add_child(trip)
	var truck := VehicleProbe.new()
	truck.game = game
	truck.position = Vector2(1480,430)
	game.add_child(truck)
	trip.vehicle = truck
	var flybys := Flybys.new()
	flybys.game = game
	flybys.controller = trip
	game.add_child(flybys)
	flybys.set_process(false)
	await process_frame
	game.camera.force_update_scroll()
	var before := {"hp":truck.hp,"ammo":truck.ammo,"cargo":truck.cargo.duplicate(true),"journey":truck.journey_state.duplicate(true),"position":truck.position}
	truck.animation_time=4
	flybys.update_state(0)
	check(flybys.active_id=="survey_pair" and flybys.aircraft[0].kind=="patrol_plane", "Exact slot entry configures the plane before its zero-alpha approach")
	truck.animation_time=9
	flybys.update_state(0)
	var proof := flybys.diagnostics()
	check(proof.visible_aircraft==2 and proof.playing_motors==2 and proof.allocated_aircraft==2 and proof.allocated_motors==2,"Actual paired pass uses exactly two visible hulls and two motor voices")
	check(flybys.aircraft[0].body!=null and flybys.aircraft[0].engines!=null and flybys.aircraft[0].chassis_atlas.resource_path==AircraftArtCatalog.TEXTURE_PATH,"Hull and propulsion use the existing authored atlas independently")
	check(not flybys.aircraft[0] is CollisionObject2D and not flybys.aircraft[0].is_in_group("enemies") and not flybys.aircraft[0].is_in_group("air_enemies") and Schema.kind(flybys.aircraft[0]).is_empty(),"A distant flyby cannot impersonate a hittable enemy or enter the wire schema")
	check(flybys.cloud_nodes[0].z_index<flybys.aircraft[0].z_index and flybys.cloud_nodes[1].z_index>flybys.aircraft[0].z_index and not flybys.cloud_nodes[1].region_enabled,"Clouds straddle actual aircraft; shader samples each atlas cell once")
	check(flybys.voices.all(func(voice):return voice.stream is AudioStreamWAV and voice.stream.loop_mode==AudioStreamWAV.LOOP_FORWARD and voice.volume_db<-20 and voice.panning_strength>0),"Actual finite motor loops use spatial SFX voices at a restrained distant level")
	var position_before: Vector2 = flybys.aircraft[0].position
	flybys.update_state(.04)
	check(flybys.clock==9.04 and truck.animation_time==9 and flybys.aircraft[0].position!=position_before,"Frozen replica sample extrapolates art without mutating the vehicle clock")
	flybys.update_state(.8)
	check(is_equal_approx(flybys.clock,9.12),"Extrapolation ends after the established 120 ms budget")
	paused=true
	var paused_clock: float = flybys.clock
	flybys.update_state(.4)
	check(flybys.clock==paused_clock,"Pause cannot advance local flyby time")
	paused=false
	truck.animation_time=9.3
	flybys.update_state(0)
	check(flybys.clock==9.3 and flybys.diagnostics().extrapolation==0,"New authoritative sample resets prediction exactly")
	flybys.update_state(NAN)
	check(flybys.clock==9.3,"Invalid delta cannot alter local flyby state")
	game.weather.reduced_effects=true
	flybys.update_state(0)
	check(flybys.cloud_nodes[1].material.get_shader_parameter("morph_amount")==.12 and flybys.diagnostics().visible_aircraft==2,"Reduced effects retain readable aircraft and reduce cloud deformation")
	game.audio.sfx_volume=0
	flybys.update_state(0)
	check(flybys.diagnostics().playing_motors==0,"SFX mute stops both actual flyby motor voices")
	game.audio.sfx_volume=.5
	truck.animation_time=24
	flybys.update_state(0)
	check(flybys.active_id.is_empty() and flybys.diagnostics().playing_motors==0 and flybys.diagnostics().visible_aircraft==0,"Quiet interval hides art and releases loop playback")
	truck.animation_time=39
	flybys.update_state(0)
	check(flybys.active_id=="low_transport" and flybys.diagnostics().visible_aircraft==1 and flybys.diagnostics().playing_motors==1,"Late slot switches to a distinct single transport and one engine voice")
	check(flybys.diagnostics().stream_families==2 and flybys.diagnostics().allocated_aircraft==2,"Distinct slots reuse the fixed node budget and cache only their two audio families")
	var listener:=AudioListener2D.new()
	listener.position=Vector2(1450,405)
	game.add_child(listener)
	listener.make_current()
	var bus:=AudioServer.get_bus_index("SFX")
	mixer_capture=AudioEffectCapture.new()
	mixer_capture.buffer_length=.5
	var effect_index:=AudioServer.get_bus_effect_count(bus)
	AudioServer.add_bus_effect(bus,mixer_capture)
	trip.state.pending_node="quarry"
	truck.animation_time=6.64
	flybys.update_state(0)
	var left_mix: Dictionary=await sample_mix()
	check(left_mix.frames>2000 and left_mix.left>left_mix.right*1.1 and left_mix.left>0.00001,"Actual mono transport engine reaches the mixer louder on the left during approach")
	truck.animation_time=13.36
	flybys.update_state(0)
	var right_mix: Dictionary=await sample_mix()
	check(right_mix.frames>2000 and right_mix.right>right_mix.left*1.1 and right_mix.right>0.00001,"Same actual engine crosses the physical listener and reaches the mixer louder on the right")
	check(not flybys.voices[0].stream.stereo,"Stereo placement comes from physical source/listener positions rather than a baked pan")
	var retired_capture: WeakRef=weakref(mixer_capture)
	AudioServer.remove_bus_effect(bus,effect_index)
	mixer_capture=null
	var retire_until:=Time.get_ticks_msec()+5000
	while retired_capture.get_ref()!=null and Time.get_ticks_msec()<retire_until: await process_frame
	check(retired_capture.get_ref()==null,"AudioServer retires the temporary mixer capture before test shutdown")
	listener.clear_current()
	var retired_motors: Array[WeakRef]=[]
	for voice: AudioStreamPlayer2D in flybys.voices:
		if voice.has_stream_playback(): retired_motors.append(weakref(voice.get_stream_playback()))
	trip.stage="failed"
	flybys.update_state(.02)
	check(flybys.active_id.is_empty() and flybys.diagnostics().playing_motors==0,"Terminal journey state cancels cosmetic art and audio")
	trip.stage="travel"
	truck.destroyed=true
	flybys.update_state(0)
	check(flybys.active_id.is_empty(),"Destroyed vehicle never starts a flyby")
	check(before=={"hp":truck.hp,"ammo":truck.ammo,"cargo":truck.cargo.duplicate(true),"journey":truck.journey_state.duplicate(true),"position":truck.position} and get_nodes_in_group("air_projectiles").is_empty(),"All cosmetic passes preserve real vehicle resources, journey, position and ordnance")
	check(await Cleanup.free_scene(game,self),"All flyby nodes and actual engine playback handles retire on scene teardown")
	retire_until=Time.get_ticks_msec()+5000
	while retired_motors.any(func(handle):return handle.get_ref()!=null) and Time.get_ticks_msec()<retire_until: await process_frame
	check(retired_motors.all(func(handle):return handle.get_ref()==null),"Motor handles stopped by a terminal-state assertion retire before test shutdown")
	var output:="res://artifacts/convoy-experience-20261004/air/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	FileAccess.open(output+"air-test.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"passed":checks-failures,"failures":failures,"left_approach_mix":left_mix,"right_departure_mix":right_mix,"fixture":"Isolated world with actual new flyby nodes, authored aircraft and looping mono WAVs; existing SFX bus plus temporary AudioEffectCapture and physical AudioListener2D. Vehicle clock/resources use probes so cosmetic determinism cannot alter gameplay. No user profile, sockets, microphone or editor. Native scene/routing hook is separately covered by the gallery and root journey runs."},"  "))
	print("CONVOY AIR ENCOUNTERS: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
