extends SceneTree
## Genuine four-worker preparation/boarding/reload and InputMap actions.
## Later phase samples explicitly isolate shared UI/input/clock ownership.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
const Expedition := preload("res://scripts/expedition_controller.gd")
const NetInput := preload("res://scripts/network_input.gd")
const World := preload("res://scripts/network_world.gd")
const Protocol := preload("res://scripts/network_protocol.gd")
const CinematicArt := preload("res://scripts/travel_cinematic_art.gd")
const OUTPUT := "res://artifacts/travel-cinematics-20261004/integration/"
var game: Node
var checks:=0
var failures:=0
var evidence: Dictionary={}
var capture_enabled:=false
var captures: Array[Dictionary]=[]

class RemoteRoom extends Node:
	var active:=true
	var is_host:=true
	var local_player_id:=1
	var state:="playing"
	var _loading:=false
	func remote_input_for(_id: int) -> Dictionary:
		return {"held":{"fire":1.0,"interact":1.0},"pressed":["interact"],"released":["fire"],"mouse":true,"aim":[999.0,999.0]}

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	print("TRAVEL CINEMATIC %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)

func frames(count: int=3) -> void:
	for unused in count:
		await physics_frame
		await process_frame

func release_inputs() -> void:
	for id in range(1,5):
		for action in NetInput.ACTIONS:
			Input.action_release("p%d_%s"%[id,action])

func capture(id: String) -> void:
	if not capture_enabled: return
	var panel: Control=game.hud.travel_cinematic_panel
	panel.refresh(0)
	for unused in 4: await process_frame
	await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image()
	check(picture.save_png(OUTPUT+id+".png")==OK,"Native actual-panel sample saves "+id)
	check(panel.visible and not panel.caption_label.text.is_empty() and panel.skip_button.visible,"Native scene has actual title, spoken caption and host skip control "+id)
	var bounds:=Rect2(Vector2.ZERO,Vector2(picture.get_size()))
	var transform: Transform2D=panel.skip_button.get_global_transform_with_canvas()
	var top: Vector2=transform*Vector2.ZERO
	var bottom: Vector2=transform*panel.skip_button.size
	check(bounds.has_point(top) and bounds.has_point(bottom-Vector2.ONE),"Actual native skip layout stays within framebuffer "+id)
	captures.append({"id":id,"file":id+".png","size":[picture.get_width(),picture.get_height()],"elapsed":game.travel_cinematic.elapsed(),"context":game.travel_cinematic.context(),"caption":panel.caption_label.text,"speaker":panel.speaker_label.text,"prepared_state":true})

func _finish() -> void:
	release_inputs()
	paused=false
	if is_instance_valid(game): check(await Cleanup.free_scene(game,self),"Actual crew/cinematic/audio resources release cleanly")
	FileAccess.open(OUTPUT+("native-integration.json" if capture_enabled else "integration.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"passed":checks-failures,"failures":failures,"evidence":evidence,"captures":captures,"fixture":"Prepared actual four-worker wave20 victory, finite ammo crates/research, real garage/boarding/world reload. P2 is deliberately the actual driver. Initial scene controls and shared skip use actual InputMap/commands and native physics. Later elapsed/stop/pause/route values are explicit scenario samples for UI/clock ownership and native layout; no network sockets, performance claim or twenty-wave gameplay claim."},"\t"))
	print("TRAVEL CINEMATIC INTEGRATION: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)

func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	if "--no-profile-save" not in args or "--no-upnp" not in args: quit(2); return
	capture_enabled="--capture" in args
	if capture_enabled and DisplayServer.get_name()=="headless": quit(2); return
	if capture_enabled: root.size=Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.selected_characters=PartyConfig.normalize_characters(["mara","branko","ivo","mara"])
	game.start_scenario(4,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.audio.persistence_enabled=false
	game.campaign.persistence_enabled=false
	game.combat_events.persistence_enabled=false
	game.rounds.running=false
	game.rounds.wave=20
	game.upgrades.points=30
	game.players[0].inventory={"ammo":2}
	check(game.expedition.on_victory(),"Prepared finite victory opens actual travel boundary")
	check(game.upgrades.purchase("convoy_mg"),"Actual research unlocks finite crew MG")
	check(game.expedition.handle_command("prepare",{},1),"Actual garage opens")
	check(game.expedition.handle_command("route",{"id":"harbor"},1),"Actual route selects signal destination")
	check(game.expedition.handle_command("load",{"kind":"ammo","amount":2},1),"Actual departure loads exactly two finite ammo crates")
	var previous:=game.get_instance_id()
	check(game.expedition.handle_command("depart",{},1),"Actual command starts visible boarding")
	var roles: Array[String]=["gunner","driver","passenger_left","passenger_right"]
	var garage: Node2D=game.expedition.vehicle
	for index in 4:
		var person: Node2D=game.players[index]
		person.global_position=garage.global_position+Vector2(-100+index*20,0)
		check(garage.board(person,roles[index]),"Real P%d boards distinct %s role"%[index+1,roles[index]])
	var deadline:=Time.get_ticks_msec()+20000
	var launched:=false
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if not is_instance_valid(current_scene) or current_scene.get_instance_id()==previous: continue
		game=current_scene
		if game.started and game.expedition.stage=="travel" and is_instance_valid(game.expedition.vehicle) and game.expedition.vehicle.journey_state.phase=="starting":
			launched=true
			break
	check(launched,"Normal boarding countdown reloads the road into initial starting phase")
	if not launched: await _finish(); return
	var cinematic: Node=game.get("travel_cinematic")
	check(is_instance_valid(cinematic),"Real game constructs travel cinematic controller")
	if not is_instance_valid(cinematic): await _finish(); return
	var truck: Node2D=game.expedition.vehicle
	await process_frame
	var context: Dictionary=cinematic.context()
	var duration: float=float(context.get("duration",0))
	check(context.get("id")=="signal" and context.get("destination")=="harbor" and duration>0 and duration<=9.0,"Actual route derives bounded signal vignette")
	check(truck.driver_seat.occupant==game.players[1] and context.get("character_id")==game.players[1].character_id,"Shared cast/voice belongs to actual P2 driver, not host slot")
	var actual_ids: Array=game.players.map(func(person):return person.character_id)
	var shown_ids: Array=context.get("crew_ids",[]).duplicate()
	actual_ids.sort()
	shown_ids.sort()
	check(shown_ids==actual_ids,"Shared context retains all four actual crew identities")
	check(cinematic.active and cinematic.blocks_gameplay() and cinematic.is_presented(),"Fresh initial ignition presents cinematic and blocks gameplay")
	check(game.hud.overlay.is_empty() and not paused,"Cinematic owns no menu overlay and leaves network/physics running")
	check(not cinematic.skip(1),"First frames cannot immediately skip before minimum shared delay")
	check(Expedition.valid_command("cinematic_skip",{}) and not Expedition.valid_command("cinematic_skip",{"unexpected":1}),"Existing expedition command envelope accepts only empty skip arguments")
	var mags: Array=[]
	for person in game.players.slice(2):
		var weapon: WorkerWeapon=person.get_node("WorkerWeapon")
		mags.append([weapon.current_ammo(),weapon.reserve,weapon.reload_timer,weapon._shot_index])
	var positions: Array=truck.seats.map(func(seat):return seat.occupant)
	var cargo: Dictionary=truck.cargo.duplicate(true)
	var fuel: float=truck.fuel
	var start_x: float=truck.position.x
	var dialogue_clock: float=game.dialogue.elapsed
	var dialogue_age: float=game.dialogue.active_age
	for action in ["p1_fire","p1_reload","p1_interact","p2_right","p2_interact","p3_fire","p3_reload","p3_interact","p4_fire","p4_cycle_target"]: Input.action_press(action)
	check(game.players.all(func(person):return not NetInput.is_pressed(person,"fire") and not NetInput.just_pressed(person,"interact")),"Actual offline workers receive neutral gameplay input during cinematic")
	check(game.players.all(func(person):return not NetInput.mouse_aim(person)),"Cinematic controls cannot silently rotate mounted weapons with skip-button mouse aim")
	var real_room: Node=game.network
	var remote_room:=RemoteRoom.new()
	root.add_child(remote_room)
	game.network=remote_room
	check(NetInput.strength(game.players[2],"fire")==0 and not NetInput.just_pressed(game.players[2],"interact") and not NetInput.just_released(game.players[2],"fire") and not NetInput.mouse_aim(game.players[2]),"Shared lock rejects non-neutral guest input before remote/local branch")
	remote_room._loading=true
	check(not cinematic.is_presented() and cinematic.blocks_gameplay(),"Network-loading state hides presentation while retaining shared input lock")
	remote_room._loading=false
	remote_room.state="reconnecting"
	check(not cinematic.is_presented() and cinematic.blocks_gameplay(),"Reconnecting session state cannot expose stale cinematic over waiting UI")
	game.network=real_room
	remote_room.free()
	await frames(16)
	check(truck.seats.map(func(seat):return seat.occupant)==positions,"Held real interact/seat-cycle actions cannot dismount or switch any crew")
	check(truck.ammo==0 and truck.reload_timer==0 and truck.flash_tick==0 and truck.cargo==cargo,"Held MG fire/reload cannot consume cargo or create a hidden shot")
	var after_mags: Array=[]
	for person in game.players.slice(2):
		var weapon: WorkerWeapon=person.get_node("WorkerWeapon")
		after_mags.append([weapon.current_ammo(),weapon.reserve,weapon.reload_timer,weapon._shot_index])
	check(after_mags==mags,"Both real passenger magazines/reload clocks remain unchanged under held controls")
	check(is_equal_approx(truck.position.x,start_x) and is_equal_approx(truck.fuel,fuel) and not truck.driving_enabled,"Underlying starting truck neither travels nor spends fuel")
	check(not game.dialogue.canvas.visible and (not game.dialogue.voice.playing or game.dialogue.voice.stream_paused),"Existing story radio cannot overlay or talk over full travel scene")
	check(is_equal_approx(game.dialogue.elapsed,dialogue_clock) and is_equal_approx(game.dialogue.active_age,dialogue_age),"Underlying story dialogue preserves its queue/reading clock while travel is blocked")
	release_inputs()
	for action in ["restart","audio_settings","upgrades","personnel","help","friends","pause"]:
		if not InputMap.has_action(action): continue
		var event:=InputEventAction.new()
		event.action=action
		event.pressed=true
		game.hud._unhandled_input(event)
	check(game.hud.overlay.is_empty() and not paused and not game.hud.has_session_action(),"HUD restart/options/help/social/pause shortcuts cannot replace active vignette")
	var before_skip: float=truck.journey_state.phase_time
	check(not game.expedition.handle_command("cinematic_skip",{},2) and truck.journey_state.phase_time==before_skip,"Guest slot cannot advance shared cinematic")
	check(not game.expedition.handle_command("cinematic_skip",{"unexpected":true},1) and truck.journey_state.phase_time==before_skip,"Malformed skip cannot alter the shared clock")
	while cinematic.elapsed()<.5: await physics_frame
	var accepted_skip_clock: float=cinematic.elapsed()
	check(game.expedition.handle_command("cinematic_skip",{},1),"Host accepts skip after real minimum ignition time")
	check(is_equal_approx(float(truck.journey_state.phase_time),duration),"Shared skip advances only existing starting clock to vignette duration")
	check(not cinematic.active and cinematic.blocks_gameplay() and truck.journey_state.phase=="starting" and not truck.driving_enabled,"Skip retains blocked original ignition interval instead of immediately driving")
	await frames(8)
	check(truck.journey_state.phase=="starting" and cinematic.blocks_gameplay(),"Post-skip ignition remains physically blocked for its own countdown")
	deadline=Time.get_ticks_msec()+5000
	while truck.journey_state.phase=="starting" and Time.get_ticks_msec()<deadline: await physics_frame
	await process_frame
	check(truck.journey_state.phase=="driving" and truck.driving_enabled and not cinematic.blocks_gameplay() and game.hud.overlay.is_empty() and not paused,"Original ignition finishes into real unlocked driving without stale UI/pause")
	check(truck.flash_tick==0 and truck.seats.map(func(seat):return seat.occupant)==positions,"Cinematic/skip held controls never become delayed shots or seat exits")
	var world:=World.new()
	world.bind(game)
	var snapshot:=world.capture()
	check(world._validate(snapshot),"Actual road and cinematic controller preserve existing snapshot schema")
	check(Protocol.decode(Protocol.encode({"kind":"snapshot","generation":1,"sequence":1,"world":snapshot})).is_empty()==false,"Actual starting/driving snapshot survives existing protocol encoding")
	check(snapshot.entities.all(func(record):return not str(record.type).begins_with("travel_cinematic")),"Local presentation creates no additional wire entity kind")
	# Controlled samples below isolate UI ownership, resumed-stop gating and
	# pause semantics after the genuine initial launch/skip/input assertions.
	truck.driving_enabled=false
	truck.velocity=Vector2.ZERO
	truck.position.x=game.expedition.ROAD_START
	truck.journey_state=Journey.new_state("starting")
	truck.journey_state.phase_time=2.0
	game.expedition.stop_done=false
	await process_frame
	check(cinematic.active and is_equal_approx(cinematic.elapsed(),float(truck.journey_state.phase_time)),"Mid-vignette sample reads shared elapsed clock rather than starting a local timer")
	var panel: Control=game.hud.travel_cinematic_panel
	check(not panel.mouse_force_pass_scroll_events,"Fullscreen cinematic prevents scroll events reaching underlying player camera")
	game.hud.overlay="network"
	var elapsed: float=cinematic.elapsed()
	check(cinematic.blocks_gameplay() and not cinematic.is_presented(),"Network/reconnection overlay hides cinematic while preserving shared input lock")
	paused=true
	for unused in 4: await process_frame
	check(is_equal_approx(cinematic.elapsed(),elapsed) and game.hud.overlay=="network","External shared pause freezes existing journey clock and retains network-owned UI")
	paused=false
	game.hud.overlay=""
	check(cinematic.is_presented() and cinematic.elapsed()>=elapsed,"Returning from reconnect-style overlay resumes same elapsed vignette")
	game.expedition.set_physics_process(false)
	truck.set_physics_process(false)
	truck.journey_state.phase="driving"
	panel.refresh(0)
	truck.journey_state=Journey.new_state("starting")
	truck.journey_state.phase_time=.8
	panel.refresh(0)
	check(not panel.voice.playing and not panel.effect.playing,"Fresh pre-cue panel has no premature voice or effect")
	game.hud.overlay="network"
	truck.journey_state.phase_time=4.0
	panel.refresh(0)
	game.hud.overlay=""
	panel.refresh(0)
	check(not panel.voice.playing and not panel.effect.playing,"Same-vehicle hidden clock jump cannot replay past unfired voice or effect cues")
	check(panel.visible and not panel.caption_label.text.is_empty(),"Returning late still displays matching spoken subtitle at actual shared time")
	game.expedition.set_physics_process(true)
	truck.set_physics_process(true)
	game.hud.overlay="pause"
	game.expedition.stop_done=true
	check(not cinematic.active and not cinematic.blocks_gameplay() and not cinematic.is_presented() and game.hud.overlay=="pause","Secured stop suppresses replay without clearing another menu's overlay")
	game.hud.overlay=""
	truck.journey_state.phase_time=0
	await frames(4)
	check(truck.journey_state.phase=="starting","Secured-stop initial ignition uses the existing short countdown")
	deadline=Time.get_ticks_msec()+5000
	while truck.journey_state.phase=="starting" and Time.get_ticks_msec()<deadline: await physics_frame
	check(truck.journey_state.phase=="driving" and not cinematic.blocks_gameplay(),"Secured-stop continuation bypasses vignette and finishes normal ignition")
	check(not cinematic.skip(1),"Completed/non-cinematic travel cannot be skipped again")
	game.expedition.set_physics_process(false)
	truck.set_physics_process(false)
	for sample in [{"node":"harbor","id":"signal"},{"node":"mountain_pass","id":"storm"},{"node":"quarry","id":"supply"}]:
		truck.journey_state.phase="driving"
		panel.refresh(0)
		game.expedition.state.pending_node=sample.node
		game.expedition.route=CampaignCatalog.journey(sample.node)
		game.expedition.stop_done=false
		truck.journey_state=Journey.new_state("starting")
		truck.journey_state.phase_time=4.0
		panel.refresh(0)
		check(cinematic.context().get("id")==sample.id and panel.visible and panel.speaker_label.text==cinematic.context().dialogue.speaker_name,"Actual controller/panel samples matching "+sample.id+" route and driver")
		var drawn_crew: Array[String]=CinematicArt._crew(cinematic.context())
		var drawn_driver: String=drawn_crew[0] if not drawn_crew.is_empty() else ""
		drawn_crew.sort()
		check(drawn_driver==truck.driver_seat.occupant.character_id and drawn_crew==actual_ids,"Rendered "+sample.id+" driver matches actual non-host driver and retains duplicate crew identities")
		check(not panel.voice.playing and not panel.effect.playing,"Late "+sample.id+" sample preserves subtitle without restarting past audio")
		# process_frame is emitted before Node._process. Let the actual
		# StoryDialogue process the prepared route before inspecting its UI.
		for unused in 2: await process_frame
		check(not game.dialogue.canvas.visible and (not game.dialogue.voice.playing or game.dialogue.voice.stream_paused),"Ordinary radio stays hidden/silent behind "+sample.id+" full-panel sample")
		await capture("panel-"+sample.id)
	evidence={"actual_driver":str(context.get("character_id","")),"crew":context.get("crew_ids",[]),"duration":duration,"actual_skip_clock":accepted_skip_clock,"travel_snapshot_entities":snapshot.entities.size(),"human_count":game.players.size(),"no_hidden_mg_shots":truck.flash_tick==0,"final_phase":truck.journey_state.phase}
	await _finish()
