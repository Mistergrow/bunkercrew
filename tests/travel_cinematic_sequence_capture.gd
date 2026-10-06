extends SceneTree
## Prepared campaign boundaries; full natural scene clocks and actual audio.
## Record with native MovieMaker60Hz, never a realtime FPS claim.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/travel-cinematics-20261004/sequence/"
const DESTINATIONS: Array[String]=["harbor","mountain_pass","quarry"]
var game: Node
var checks:=0
var failures:=0
var sequences: Array[Dictionary]=[]
var movie_frame_start:=0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	print("CINEMATIC SEQUENCE %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)

func movie_seconds() -> float:
	return float(Engine.get_process_frames()-movie_frame_start)/60.0

func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	if "--no-profile-save" not in args or "--no-upnp" not in args or DisplayServer.get_name()=="headless": quit(2); return
	root.size=Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	movie_frame_start=Engine.get_process_frames()
	LocaleText.set_locale("de",false)
	for destination: String in DESTINATIONS:
		game=load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene=game
		game.selected_characters=PartyConfig.normalize_characters(["mara","branko","ivo","mara"])
		game.start_scenario(4,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
		game.rounds.running=false
		game.rounds.wave=20
		check(game.expedition.on_victory(),"Prepared wave20 boundary unlocks actual vehicle for "+destination)
		# Explicitly prepare the visited main-route ancestors for later scenes.
		# No twenty-wave playthrough or complete campaign is claimed by this film.
		var ancestor: String=str(CampaignCatalog.node(destination).parent)
		while not ancestor.is_empty():
			if ancestor not in game.campaign.completed:
				game.campaign.completed.append(ancestor)
				game.campaign.claimed_missions.append("%s:%s"%[game.campaign.campaign_id,ancestor])
			ancestor=str(CampaignCatalog.node(ancestor).parent)
		check(game.campaign.select_destination(destination),"Prepared valid ancestry allows real route selection "+destination)
		game.expedition.route=game.campaign.begin_journey()
		check(not game.expedition.route.is_empty() and CampaignState.valid_checkpoint(game.campaign.checkpoint()),"Actual finite departure checkpoint validates "+destination)
		game.expedition._start_road(false,["gunner","driver","passenger_left","passenger_right"])
		var truck: Node2D=game.expedition.vehicle
		var panel: Control=game.hud.travel_cinematic_panel
		var context: Dictionary=game.travel_cinematic.context().duplicate(true)
		var original_fuel: float=truck.fuel
		var original_cargo: Dictionary=truck.cargo.duplicate(true)
		var start: float=movie_seconds()
		var samples: Array[Dictionary]=[]
		var last_voice:=false
		var last_effect:=false
		var voice_starts:=0
		var effect_starts:=0
		var previous_clock:=0.0
		var monotonic:=true
		var last_sample_clock:=0.0
		check(context.character_id=="branko" and context.crew_ids==["mara","branko","ivo","mara"],"Scene preserves actual P2 driver and duplicate crew identities "+destination)
		for _tick in 800:
			await process_frame
			if truck.journey_state.phase!="starting": break
			var clock: float=truck.journey_state.phase_time
			monotonic=monotonic and clock>=previous_clock
			previous_clock=clock
			if panel.voice.playing and not last_voice: voice_starts+=1
			if panel.effect.playing and not last_effect: effect_starts+=1
			last_voice=panel.voice.playing
			last_effect=panel.effect.playing
			if clock-last_sample_clock>=1.0/12.0:
				last_sample_clock=clock
				samples.append({"movie_seconds":movie_seconds(),"clock":clock,"visible":panel.visible,"voice_playing":panel.voice.playing,"effect_playing":panel.effect.playing,"voice_bus":panel.voice.bus,"effect_bus":panel.effect.bus,"speaker":panel.speaker_label.text,"caption":panel.caption_label.text,"normal_radio_visible":game.dialogue.canvas.visible,"normal_radio_playing":game.dialogue.voice.playing,"normal_radio_paused":game.dialogue.voice.stream_paused})
		check(truck.journey_state.phase=="driving" and truck.driving_enabled,"Full scene naturally completes original ignition without skip "+destination)
		check(monotonic,"Shared starting clock stays monotonic "+destination)
		check(previous_clock>=float(context.duration)+.75,"Native clock covers whole scene and final ignition "+destination)
		check(voice_starts==1 and effect_starts==1,"Actual Voice/SFX players each start exactly once "+destination)
		check(samples.any(func(sample):return sample.visible and sample.voice_playing and not sample.caption.is_empty()),"Actual spoken captions coexist with running scene "+destination)
		check(samples.all(func(sample):return not sample.normal_radio_visible and (not sample.normal_radio_playing or sample.normal_radio_paused)),"Ordinary radio remains silent and hidden for the entire protected start "+destination)
		check(truck.position.x==game.expedition.ROAD_START and truck.fuel==original_fuel and truck.cargo==original_cargo and game.players.all(func(worker):return is_instance_valid(worker.mounted_turret)),"Natural scene completion retains exact parked crew and finite resources "+destination)
		sequences.append({"id":context.id,"destination":destination,"start_seconds":start,"end_seconds":movie_seconds(),"context":context,"voice_starts":voice_starts,"effect_starts":effect_starts,"samples":samples,"prepared_state":true})
		for _tick in 30: await process_frame
		check(await Cleanup.free_scene(game,self),"Actual game, panel, speech and crew clean up "+destination)
	FileAccess.open(OUTPUT+"sequences.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"passed":checks-failures,"failures":failures,"sequences":sequences,"renderer":RenderingServer.get_video_adapter_name(),"fixture":"Three independent prepared ash_foundry wave20 victories and finite vehicle departures; later route ancestors explicitly prepared. Actual CampaignState.select_destination/begin_journey and Expedition._start_road instantiate the native truck with P2Branko driver and duplicate Mara crew. Every scene then runs its full real starting phase using ordinary engine60Hz physics/process and genuine Voice/SFX streams, without phase_time/position/speed/ammo/audio overrides or shared skip. Native1440x900 MovieMaker film is offline animation/audio-mix evidence, not realtime performance or a full campaign/garage playthrough; real garage and network handoffs are separately tested. Fresh XDG/no-profile-save/no-upnp."},"\t"))
	print("TRAVEL CINEMATIC SEQUENCE: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
