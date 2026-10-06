extends SceneTree
## Real bunker floors, spatial audio, canonical enemy state and viewport cover.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const Schema := preload("res://scripts/network_replication_schema.gd")
const Layout := preload("res://scripts/background_layout.gd")
const IDS := ["mara","branko","ivo","nora","levin","selma"]
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func run() -> void:
	root.size = Vector2i(1440,900)
	var pictures: Dictionary = {}
	for entry: Dictionary in ScenarioCatalog.environments(true):
		var texture := ScenarioCatalog.texture(entry.path)
		check(texture!=null and texture.get_width()>=1600 and texture.get_height()>=900,entry.id+" has a complete high-resolution background")
		var digest := FileAccess.get_sha256(entry.path)
		check(not pictures.has(digest),entry.id+" has its own generated image")
		pictures[digest] = true
		for screen in [Vector2(960,600),Vector2(1440,900),Vector2(2560,1440),Vector2(3440,1440),Vector2(900,1440)]:
			for zoom in [.25,.5,1.0,2.0,2.5]:
				var view := Rect2(Vector2(720,200)-screen/zoom*.5,screen/zoom)
				var background := Layout.frame(view,float(texture.get_width())/texture.get_height(),zoom)
				var above_ground := Rect2(view.position,Vector2(view.size.x,maxf(0,430.0-view.position.y)))
				check(background.encloses(above_ground),entry.id+" covers the complete above-ground view across resolution and zoom")
	check(pictures.size()==13,"All thirteen locations have distinct continuous art")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start(1)
	for index in 4: await physics_frame
	freeze(game)
	game.audio.set_sfx_volume(.65)
	var actor: Worker = game.players[0]
	var visual: WorkerVisual = actor.get_node("PixelVisual")
	var last_pitches: Dictionary = {}
	for floor_y in [430.0,600.0,800.0]:
		game.camera.position = Vector2(350,floor_y-70)
		game.camera.zoom = Vector2.ONE
		game.camera.force_update_scroll()
		for identity: String in IDS:
			actor.character_id = identity
			actor.position = Vector2(200,floor_y)
			actor.velocity = Vector2(150,0)
			actor._airborne = false
			actor._landing_time = 0
			actor._jump_windup = 0
			actor.climbing = false
			actor.wetness._last_position = actor.position
			actor.wetness._previous_contacts.clear()
			actor.wetness._pending_contacts.clear()
			actor.wetness._travel = 0
			actor.wetness._last_step_time = -10
			var before: int = game.audio.movement.steps_played
			for tick in 120:
				actor.position.x += 150.0/60.0
				visual._process(1.0/60.0)
				actor.wetness.advance(1.0/60.0)
			check(game.audio.movement.steps_played>=before+3,"%s emits real steps on bunker floor %.0f"%[identity,floor_y])
			var steps: int = game.audio.movement.steps_played
			actor.velocity = Vector2.ZERO
			for tick in 60:
				visual._process(1.0/60.0)
				actor.wetness.advance(1.0/60.0)
			check(game.audio.movement.steps_played==steps,identity+" standing produces no footsteps")
			var latest: AudioStreamPlayer2D = null
			for voice: AudioStreamPlayer2D in game.audio.movement.voices:
				if latest==null or int(voice.get_meta("serial",0))>int(latest.get_meta("serial",0)): latest=voice
			check(latest!=null and latest.get_meta("character_id","")==identity and str(latest.get_meta("kind","")).begins_with("boot_"),identity+" uses recorded character-weighted boots")
			if latest!=null: last_pitches[identity]=latest.pitch_scale
	check(last_pitches.values().size()==6 and last_pitches.values().all(func(value):return last_pitches.values().count(value)==1),"Six identities have distinct boot pitches")
	for identity: String in IDS:
		check(Personality.wait_range(identity).y<=7.0,identity+" gestures become visible within seven idle seconds")
		check(not Personality.reaction(identity,"work_finished").is_empty() and not Personality.reaction(identity,"wave_clear").is_empty(),identity+" has work and wave reactions")
		var base := Personality.stance(WorkerPoseArt.neutral(),identity)
		for gesture: String in Personality.gestures(identity):
			var pose := WorkerPoseArt.sample(gesture,.5,0,Vector2(24,-13),identity)
			check(pose.hands!=base.hands and pose.feet==base.feet,identity+" gesture articulates hands with both boots planted")
		if identity in ["nora","levin","selma"]:
			var gestures: Array[String] = Personality.gestures(identity)
			gestures.append(Personality.reaction(identity,"work_finished"))
			gestures.append(Personality.reaction(identity,"wave_clear"))
			for gesture: String in gestures:
				for phase in 61:
					var pose := WorkerPoseArt.sample(gesture,phase/60.0,0,Vector2(24,-13),identity)
					var body := WorkerPoseArt.torso_transform(pose)
					check(pose.feet==base.feet and pose.hands[0].distance_to(body*Vector2(-6,0))<=23.0 and pose.hands[1].distance_to(body*Vector2(3,0))<=23.0,gesture+" keeps finite connected arms and planted boots throughout its animation")
	for kind: String in EnemyCatalog.GROUND_CLASSES:
		var enemy = load("res://scenes/ground_infantry.tscn" if EnemyCatalog.is_human(kind) else "res://scenes/enemy.tscn").instantiate()
		enemy.kind = kind
		enemy.game = game
		enemy.position = Vector2(1000,430)
		game.add_child(enemy)
		freeze(enemy)
		var source: Dictionary = EnemyCatalog.PROFILES[kind]
		check(enemy.visual_scale<float(source.scale),kind+" has a reduced actual visual scale")
		check(enemy.get_node("MachineHitbox").shape.size.x<source.hitbox.x,kind+" collision width follows the reduced art")
		var entity_kind := "ground_infantry" if EnemyCatalog.is_human(kind) else "enemy"
		var state: Dictionary = {}
		for field: String in Schema.fields(entity_kind): state[field]=enemy.get(field)
		check(Schema.valid_state(entity_kind,state),kind+" compact profile is valid for network replication")
		enemy.free()
	var args: PackedStringArray = game.hud.display_settings.standalone_arguments()
	check("--fullscreen" in args and "--wid" not in args and "--remote-debug" not in args,"Separate fullscreen launch omits editor embedding and debugger flags")
	check(await Cleanup.free_scene(game,self),"Real presentation fixture releases all playback and actor resources")
	print("CREW BACKGROUNDS: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
