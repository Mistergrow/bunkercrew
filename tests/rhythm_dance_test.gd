extends SceneTree
## Choreography checks cover the entire sixteen-beat phrase, actual kick entry,
## visual floor support and unchanged real worker/collider/action state.
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const VisualTest := preload("res://tests/rhythm_visual_test.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func contact(pose: Dictionary) -> bool:
	return is_equal_approx(pose.feet[0].y,-3.0) or is_equal_approx(pose.feet[1].y,-3.0) or (pose.get("dance_stage","") in ["floorwork","freeze"] and (is_equal_approx(pose.hands[0].y,-3.0) or is_equal_approx(pose.hands[1].y,-3.0)))

func _run() -> void:
	InputSetup.install()
	check(Dance.FULL_BODY_STYLES.size()==50 and Dance.FULL_BODY_STYLES.has("breakdance") and Dance.FULL_BODY_STYLES.has("moonwalk"),"Seven classic dances and forty-three repertoire moves are selectable")
	var distinct: Dictionary = {}
	for id: String in Dance.IDS:
		distinct[Dance.DEFAULT_STYLES[id]] = true
	check(distinct.size() == 6,"Six character defaults use distinct full-body dances")
	var paths: Dictionary = {}
	for style: String in Dance.FULL_BODY_STYLES:
		var character := Dance.owner(style)
		if character.is_empty(): character = "levin"
		var trace: Array = []
		var max_foot_lift := 0.0
		var max_foot_travel := 0.0
		var previous: Dictionary = {}
		var phases: Dictionary = {}
		for frame in 1921:
			var beat := float(frame)/120.0
			var pose := Rhythm.choreography(style,beat,character,1.5)
			phases[pose.get("dance_stage","standing")] = true
			check(contact(pose),style+" always has a painted floor support")
			var finite := true
			for key: String in ["hip","shoulder"]:
				var point: Vector2 = pose[key]
				finite = finite and point.is_finite() and absf(point.x)<40 and point.y>=-65 and point.y<0.1
			var head_shift: Vector2 = pose.head_shift
			finite = finite and head_shift.is_finite() and absf(head_shift.x)<4.0 and absf(head_shift.y)<4.0
			for key: String in ["hands","feet"]:
				for point: Vector2 in pose[key]:
					finite = finite and point.is_finite() and absf(point.x)<45 and point.y>=-75 and point.y<=-2.999
			check(finite,style+" keeps all painted joints inside the rig bounds")
			var body := PoseArt.torso_transform(pose)
			var connected := true
			for index in 2:
				var hip: Vector2 = pose.hip+Vector2(-4 if index==0 else 4,0)
				var shoulder := body*PoseArt.shoulder_local(pose,index)
				connected = connected and hip.distance_to(pose.feet[index])<=23.8001 and shoulder.distance_to(pose.hands[index])<=22.9001
				if pose.has("elbows"):
					connected = connected and shoulder.distance_to(pose.elbows[index])<=11.3501 and Vector2(pose.elbows[index]).distance_to(pose.hands[index])<=12.1001
				var boot := PoseArt.foot_transform(pose.feet[index],pose.foot_angles[index])
				var fixture_low := maxf((boot*Vector2(-5,3)).y,(boot*Vector2(8,3)).y)
				check(fixture_low<=0.001,style+" rotating boot never penetrates the floor")
				max_foot_lift = maxf(max_foot_lift,-3.0-float(pose.feet[index].y))
				max_foot_travel = maxf(max_foot_travel,absf(float(pose.feet[index].x)))
			check(connected,style+" retains finite two-bone arm and leg reach")
			if not previous.is_empty():
				var speed := 0.0
				for key: String in ["hip","shoulder"]:
					speed = maxf(speed,Vector2(pose[key]).distance_to(previous[key]))
				for key: String in ["hands","feet"]:
					for index in 2:
						speed = maxf(speed,Vector2(pose[key][index]).distance_to(previous[key][index]))
				check(speed<1.8,style+" is continuous across beat and phrase transitions")
			previous = pose
			if frame%120 == 45:
				trace.append([pose.hip,pose.shoulder,pose.feet.duplicate(),pose.hands.duplicate()])
		paths[style] = trace
		var low: Array[Vector2] = [Vector2(INF,INF),Vector2(INF,INF),Vector2(INF,INF),Vector2(INF,INF)]
		var high: Array[Vector2] = [Vector2(-INF,-INF),Vector2(-INF,-INF),Vector2(-INF,-INF),Vector2(-INF,-INF)]
		for sample in 481:
			var normal := Rhythm.choreography(style,float(sample)/30.0,character,1.0)
			for index in 2:
				var root_joint: Vector2 = normal.hip+Vector2(-4 if index==0 else 4,0)
				var knee := PoseArt._joint(root_joint,normal.feet[index],12,12,-1)
				for joint in 2:
					var point: Vector2 = normal.feet[index] if joint==0 else knee
					var slot := index*2+joint
					low[slot] = Vector2(minf(low[slot].x,point.x),minf(low[slot].y,point.y))
					high[slot] = Vector2(maxf(high[slot].x,point.x),maxf(high[slot].y,point.y))
		var leg_travel := 0.0
		for slot in 4:
			leg_travel = maxf(leg_travel,high[slot].distance_to(low[slot]))
		var floor_minimum := 8.0 if style in ["crew_bounce","crew_clap"] else 12.0 if preload("res://scripts/worker_dance_moves.gd").owns(style) else 15.0
		check(leg_travel>=floor_minimum,style+" has readable knee/ankle travel at normal intensity (%.2f px)"%leg_travel)
		print("DANCE LEG TRAVEL: ",style," ",leg_travel)
		check(max_foot_travel>7.0,style+" expresses real lower-body weight support")
		if style in ["shuffle","running_man","breakdance"]:
			check(max_foot_lift>3.0,style+" includes actual visual foot lifts")
		if style == "breakdance":
			check(phases.has("toprock") and phases.has("drop") and phases.has("floorwork") and phases.has("freeze") and phases.has("rise"),"Breakdance contains toprock, drop, floorwork, freeze and return")
			check(Rhythm.choreography(style,12.0).hip.y>-17.0,"Breakdance freeze brings the full torso down near the floor")
		for id: String in Dance.IDS:
			var owned := Dance.owner(style).is_empty() or Dance.owner(style)==id
			check(Dance.valid_profiles({id:{"style":style,"intensity":1.5}})==owned,id+" validates ownership for the "+style+" feedback preference")
	for first: String in paths:
		for second: String in paths:
			if first<second:
				check(paths[first]!=paths[second],first+" and "+second+" have different choreographies")
	var reference: Dictionary = {}
	for fps in [30,60,144]:
		var rhythm := Rhythm.new()
		rhythm.configure("levin")
		for tick in 5*fps+1:
			var time := float(tick)/float(fps)
			rhythm.advance(1.0/float(fps),true,heard_frame(time))
		var exact := heard_frame(5.125)
		rhythm.advance(0.0,true,exact)
		var pose := PoseArt.neutral()
		rhythm.apply(pose,exact)
		check(rhythm._dance_blend == 1.0,"Mature audible dance is established at %d FPS"%fps)
		if reference.is_empty(): reference = pose
		check(pose == reference,"The same heard sample has identical steps at %d FPS"%fps)
		var muted := exact.duplicate(true)
		muted.active = false
		rhythm.advance(0.0,true,muted)
		var stopped := PoseArt.neutral()
		rhythm.apply(stopped,muted)
		check(stopped == PoseArt.neutral(),"Pause immediately restores the functional pose at %d FPS"%fps)
		for tick in 5*fps+1:
			rhythm.advance(1.0/float(fps),true,heard_frame(float(tick)/float(fps)))
		rhythm.advance(0.0,true,heard_frame(0.08))
		check(rhythm._dance_blend == 0.0 and rhythm._heard_kicks <= 1.0,"Seeking back waits for a fresh audible kick stream at %d FPS"%fps)
	check(Dance.character_style("mara","hip_hop")=="body_roll" and Dance.character_style("mara","minimal_techno")=="shuffle","Character defaults adapt to genre without rewriting explicit preferences")
	var override := Rhythm.new()
	override.configure("mara")
	var preference := heard_frame(0.08)
	preference.genre = "hip_hop"
	preference.dance_profiles = {"mara":{"style":"moonwalk","intensity":1.0}}
	override.advance(2.0,true,preference)
	check(override._movement == "moonwalk","Explicit user dance choice stays intact across genre changes")
	var fixture := VisualTest.Fixture.new()
	root.add_child(fixture)
	fixture.audio = VisualTest.AudioStub.new()
	fixture.add_child(fixture.audio)
	fixture.audio.live_music = VisualTest.MusicStub.new()
	fixture.audio.add_child(fixture.audio.live_music)
	var music = fixture.audio.live_music
	var actor: Worker = preload("res://scenes/player.tscn").instantiate()
	actor.game = fixture
	actor.character_id = "levin"
	fixture.add_child(actor)
	var visual: WorkerVisual = actor.get_node("PixelVisual")
	_freeze(actor)
	visual.idle_clock.wait_remaining = 10000
	var actor_transform := actor.transform
	var actor_velocity := actor.velocity
	var collider := actor.get_node_or_null("CollisionShape2D")
	var collider_shape: Shape2D = collider.shape if collider!=null else null
	check(collider!=null and collider_shape is RectangleShape2D,"Gameplay fixture owns the production collision shape")
	var collider_transform: Transform2D = collider.transform
	var collider_size: Vector2 = collider_shape.size
	var collision_layer := actor.collision_layer
	var collision_mask := actor.collision_mask
	visual._process(2.0)
	check(visual.rhythm._dance_blend == 0.0,"An audible melodic grid without actual kicks does not start a dance")
	for style: String in Dance.STYLES:
		music.state.dance_profiles = {"levin":{"style":style,"intensity":1.0}}
		visual._process(1.0)
		check(not visual.pose_skeleton.has("dance_style") and visual.rhythm._dance_blend==0.0,style+" cannot mistake a beat-grid pulse for a heard kick")
	music.state.dance_profiles = {"levin":{"style":"breakdance","intensity":1.0}}
	for kick in 5:
		music.state.kick_count = kick+1
		music.state.last_kick_seconds = float(kick)*0.55
		music.state.audible_seconds = music.state.last_kick_seconds+0.09
		music.state.last_kick_strength = 1.0
		music.state.beat = kick%4
		music.state.bar = floori(float(kick)/4.0)
		visual._process(0.55)
		if kick==0:
			check(visual.rhythm._reaction>0.0 and visual.rhythm._dance_blend==0.0,"First audible BUM produces an individual head/shoulder reaction")
	check(visual.rhythm._dance_blend>0.99,"Several actual audible kicks bring the selected full-body dance in")
	for frame in 600:
		var beats := float(frame)/60.0*104.0/60.0
		music.state.bar = floori(beats/4.0)
		music.state.beat = floori(beats)%4
		music.state.phase = fposmod(beats,1.0)
		music.state.kick_count = floori(beats)+6
		music.state.last_kick_seconds = floorf(beats)*60.0/104.0
		music.state.audible_seconds = float(frame)/60.0
		visual._process(1.0/60.0)
		check(actor.transform==actor_transform and actor.velocity==actor_velocity and collider.shape==collider_shape and collider.transform==collider_transform and collider.shape.size==collider_size and actor.collision_layer==collision_layer and actor.collision_mask==collision_mask,"Dance never writes production transform, velocity, collision shape or masks")
	Input.action_press(actor.action("right"))
	visual._process(0.0)
	check(visual.rhythm.weight == 0.0 and visual.rhythm._dance_blend == 0.0,"Input immediately cancels the complete floor dance")
	Input.action_release(actor.action("right"))
	check(await Cleanup.free_scene(fixture,self),"Full-body choreography fixture releases cleanly")
	print("RHYTHM DANCE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)

func heard_frame(time: float) -> Dictionary:
	var beats := time*2.0
	return {"active":true,"phase":fposmod(beats,1.0),"bar":floori(beats/4.0),"beat":floori(beats)%4,"audible_seconds":time,"last_kick_seconds":floorf(beats)*0.5,"last_kick_strength":1.0,"kick_count":floori(beats)+1,"motion_gain":1.0,"dance_intensity":1.0,"dance_profiles":{},"genre":"minimal_techno"}
