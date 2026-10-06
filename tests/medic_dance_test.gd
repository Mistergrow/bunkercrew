extends SceneTree
## Cosmetic repertoire, audible native event gating and robot rig invariants.
const Catalog := preload("res://scripts/medic_dance_catalog.gd")
const Rhythm := preload("res://scripts/medic_rhythm_pose.gd")
const ExpressionCue := preload("res://scripts/medic_expression.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func heard(time: float) -> Dictionary:
	var beats := time * 2.0
	return {"active":true,"motion_gain":1.0,"dance_intensity":1.0,"reduced_motion":false,"bar":floori(beats / 4.0),"beat":floori(beats) % 4,"phase":fposmod(beats,1.0),"audible_seconds":time,"last_kick_seconds":floorf(beats)*0.5,"last_kick_strength":1.0,"kick_count":floori(beats)+1}

func establish(rhythm: RefCounted, level: int = 5) -> void:
	for tick in 181:
		rhythm.advance(1.0 / 60.0, true, heard(float(tick) / 60.0), level)

func _run() -> void:
	check(Catalog.STYLES.size() == 5 and Catalog.LABELS.size() == 5,"Five SAN-1 moves have dedicated localized names")
	check(Catalog.available_styles(0).is_empty() and Catalog.style_for(0,0).is_empty(),"No robotic dance exists before the software unlock")
	for level in 5:
		var learned := Catalog.available_styles(level + 1)
		check(learned.size() == level + 1,"Software level %d unlocks exactly its learned repertoire" % (level + 1))
		var cycle: Dictionary = {}
		for phrase in 10:
			var style := Catalog.style_for(level + 1, float(phrase) * Catalog.PHRASE_BEATS)
			cycle[style] = true
			check(style in learned and Catalog.required_level(style) <= level + 1,"Phrase %d respects software level %d" % [phrase,level + 1])
		check(cycle.size() == learned.size(),"Every unlocked dance appears at level %d" % (level + 1))
	check(Catalog.available_styles(-7).is_empty() and Catalog.available_styles(999).size() == 5,"Invalid levels remain bounded")
	check(Catalog.required_level("invalid") == 0 and Catalog.label("invalid").is_empty(),"Unknown move has no fictitious unlock or name")
	var traces: Dictionary = {}
	for style: String in Catalog.STYLES:
		var previous: Dictionary = {}
		var trace: Array = []
		var finite := true
		var connected := true
		var max_step := 0.0
		var min_hand := Vector2(INF,INF)
		var max_hand := Vector2(-INF,-INF)
		var maximum_nod := 0.0
		for tick in 1921:
			var beats := float(tick) / 120.0
			var pose := Rhythm.choreography(style,beats,fposmod(beats,1.0)*0.5,0.5,1.0,1.5)
			for key: String in ["body_offset","track_offset","elbow","hand"]:
				var point: Vector2 = pose[key]
				finite = finite and point.is_finite() and absf(point.x) < 45 and point.y >= -62 and point.y <= 4.5
			for key: String in ["body_angle","track_angle","head_drop","look"]:
				finite = finite and is_finite(float(pose[key]))
			connected = connected and Vector2(13,-22).distance_to(pose.elbow) <= 17.0001 and Vector2(pose.elbow).distance_to(pose.hand) <= 19.0001
			maximum_nod = maxf(maximum_nod,float(pose.head_drop))
			min_hand = Vector2(minf(min_hand.x,pose.hand.x),minf(min_hand.y,pose.hand.y))
			max_hand = Vector2(maxf(max_hand.x,pose.hand.x),maxf(max_hand.y,pose.hand.y))
			if not previous.is_empty():
				for key: String in ["body_offset","track_offset","elbow","hand"]:
					max_step = maxf(max_step,Vector2(pose[key]).distance_to(previous[key]))
				max_step = maxf(max_step,absf(float(pose.head_drop)-float(previous.head_drop)))
			previous = pose
			if tick % 120 == 24:
				trace.append(pose)
		check(finite,style+" has finite painted joints at maximum user intensity")
		check(connected,style+" retains attached bounded mechanical links")
		check(max_step < 0.6,style+" remains continuous across kick, beat and phrase boundaries (%.4f)" % max_step)
		check(maximum_nod >= 2.9,style+" includes a clearly visible sensor-head reaction")
		check(min_hand.distance_to(max_hand) > 3.0,style+" animates its medical arm with readable travel")
		traces[style] = trace
	for first: String in traces:
		for second: String in traces:
			if first < second:
				check(traces[first] != traces[second],first+" and "+second+" have different motion paths")
	var reference: Dictionary = {}
	for fps in [30,60,144]:
		var fixture_rhythm := Rhythm.new()
		for tick in fps * 3 + 1:
			fixture_rhythm.advance(1.0 / float(fps),true,heard(float(tick) / float(fps)),5)
		fixture_rhythm.advance(0.0,true,heard(3.125),5)
		check(fixture_rhythm.is_active() and fixture_rhythm.weight == 1.0,"Native kick stream establishes dance at %d FPS" % fps)
		if reference.is_empty(): reference = fixture_rhythm.state().pose
		check(reference == fixture_rhythm.state().pose,"The same audible sample yields identical robot pose at %d FPS" % fps)
		fixture_rhythm.advance(0.0,false,heard(3.125),5)
		check(not fixture_rhythm.is_active() and fixture_rhythm.pose.is_empty(),"A task preempts cosmetic dance immediately at %d FPS" % fps)
	var rhythm := Rhythm.new()
	var melody := heard(3.0)
	melody.last_kick_seconds = -1.0
	melody.last_kick_strength = 0.0
	melody.kick_count = 0
	rhythm.advance(3.0,true,melody,5)
	check(not rhythm.is_active(),"Beat-grid pulse without actual native kick never starts a dance")
	rhythm.advance(3.0,true,heard(10.0),5)
	check(not rhythm.is_active() and rhythm.state().heard_kicks == 1,"Joining a historical kick count waits for another newly heard kick")
	rhythm.advance(0.5,true,heard(10.5),5)
	check(rhythm.is_active(),"Second actually heard kick starts the researched dance")
	var stale := heard(10.5)
	stale.audible_seconds = 14.0
	rhythm.advance(0.0,true,stale,5)
	check(not rhythm.is_active(),"Drumless music restores ordinary standby immediately")
	for property: String in ["active","reduced_motion","dance_intensity","motion_gain"]:
		establish(rhythm)
		var disabled := heard(3.125)
		if property == "reduced_motion": disabled[property] = true
		elif property == "active": disabled[property] = false
		else: disabled[property] = 0.0
		rhythm.advance(0.0,true,disabled,5)
		check(not rhythm.is_active(),property+" preference suppresses the entire robot dance")
	establish(rhythm)
	rhythm.advance(0.0,true,heard(0.0),5)
	check(not rhythm.is_active() and rhythm.state().heard_kicks == 1,"Seek/restart clears historical dance readiness")
	for bad_key: String in ["audible_seconds","last_kick_seconds","last_kick_strength","dance_intensity","motion_gain"]:
		establish(rhythm)
		var invalid := heard(3.125)
		invalid[bad_key] = NAN
		rhythm.advance(0.0,true,invalid,5)
		check(not rhythm.is_active(),"Malformed "+bad_key+" cannot corrupt the robot paint pose")
	# These are real Node2D simulation properties. Choreography helpers receive
	# no writable actor during advance, so a full repertoire leaves them intact.
	var robot := CharacterBody2D.new()
	root.add_child(robot)
	robot.position = Vector2(271,430)
	robot.velocity = Vector2(37,-82)
	robot.collision_layer = 4
	robot.collision_mask = 9
	var before := [robot.transform,robot.velocity,robot.collision_layer,robot.collision_mask]
	for tick in 600:
		rhythm.advance(1.0 / 60.0,true,heard(float(tick) / 60.0),5)
	check(before == [robot.transform,robot.velocity,robot.collision_layer,robot.collision_mask],"Dance leaves physical position, velocity and collision masks unchanged")
	robot.free()
	var expression := ExpressionCue.new()
	expression.notice("alert",Vector2(-200,0))
	check(expression.is_active() and expression.direction == -1.0,"New task emits a bounded alert oriented toward its actual destination")
	expression.advance(0.14)
	check(expression.head_look(3.0) < -4.0,"Alert visibly turns the existing sensor head toward the task")
	expression.advance(1.0)
	check(not expression.is_active() and expression.head_look(3.0) == 3.0,"Alert fully retires and returns normal head control")
	expression.notice("search")
	expression.advance(0.2)
	var first_look := expression.head_look(0.0)
	expression.advance(0.8)
	check(first_look > 0.0 and expression.head_look(0.0) < 0.0,"Blocked route search looks both ways")
	expression.advance(1.0)
	check(not expression.is_active(),"Search cue expires without changing the navigation task")
	expression.notice("alert")
	expression.notice("invalid")
	check(not expression.is_active(),"Unknown expression is safely cleared")
	print("MEDIC DANCE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
