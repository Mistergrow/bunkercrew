extends SceneTree
## Learned repertoires use distinct joint paths, grounded phrase transitions,
## and the same heard beat clock as the existing dance gate.
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Moves := preload("res://scripts/worker_dance_moves.gd")
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func heard_frame(beats: float,character: String,level: int,requested := "character_default") -> Dictionary:
	return {"active":true,"phase":fposmod(beats,1),"bar":floori(beats/4),"beat":floori(beats)%4,"audible_seconds":beats*.5,"last_kick_seconds":floorf(beats)*.5,"last_kick_strength":1.0,"kick_count":floori(beats)+1,"motion_gain":1.0,"dance_intensity":1.0,"dance_profiles":{character:{"style":requested,"intensity":1.0}},"genre":"minimal_techno","character_level":level,"dance_preview":false}

func floor_contact(pose: Dictionary) -> bool:
	return is_equal_approx(pose.feet[0].y,-3) or is_equal_approx(pose.feet[1].y,-3)

func _run() -> void:
	check(Moves.IDS.size()==43,"forty unique character moves and three shared dances have authored geometry")
	var signatures: Dictionary = {}
	for character: String in Dance.IDS:
		var learned: Array = Dance.UNIQUE_STYLES[character]
		check(learned.size()==5,"%s owns five unique choreography paths"%character)
		check(Dance.available_styles(character,1)==Dance.SHARED_STYLES,"%s begins with the three shared dances"%character)
		for index in learned.size():
			var style: String = learned[index]
			check(Moves.owns(style) and Dance.owner(style)==character,"%s has actual geometry for its unique %s"%[character,style])
			check(Dance.allowed(character,style,Dance.UNLOCK_LEVELS[index]) and not Dance.allowed(character,style,Dance.UNLOCK_LEVELS[index]-1),"%s respects its character XP milestone"%style)
			var trace: Array = []
			for tick in 65:
				var pose := Rhythm.choreography(style,float(tick)/8,character,1.0)
				trace.append([pose.hip,pose.shoulder,pose.feet.duplicate(),pose.hands.duplicate(),pose.head_tilt])
				check(floor_contact(pose),style+" preserves a real support foot")
				check(not pose.has("front_weight"),style+" retains the original side view without frontal pose output")
				if pose.dance_stage in ["floorwork","freeze"]: check(not pose.has("front_weight"),style+" floorwork retains the articulated side silhouette")
			signatures[style] = trace
		var rhythm := Rhythm.new()
		rhythm.configure(character)
		for beat in 10: rhythm.advance(.5,true,heard_frame(float(beat),character,10))
		check(rhythm._dance_blend==1.0,character+" responds to mature real kicks before a repertoire transition")
		var previous: Dictionary = {}
		for tick in 121:
			var beats := 15.75+float(tick)/120
			var frame := heard_frame(beats,character,10)
			rhythm.advance(1.0/240.0,true,frame)
			var pose := PoseArt.neutral()
			rhythm.apply(pose,frame)
			check(floor_contact(pose),character+" changes repertoire through a planted stance")
			if not previous.is_empty():
				var displacement := 0.0
				for key: String in ["hip","shoulder"]: displacement = maxf(displacement,Vector2(pose[key]).distance_to(previous[key]))
				for key: String in ["hands","feet"]:
					for index in 2: displacement = maxf(displacement,Vector2(pose[key][index]).distance_to(previous[key][index]))
				check(displacement<2.0,character+" repertoire changes stay continuous at the audible phrase boundary")
			previous = pose
		check(rhythm._movement==learned[1] and rhythm._transition_pose.is_empty(),character+" completes its next learned move at the next sixteen-beat phrase")
		var locked := heard_frame(17.0,character,1,learned[4])
		rhythm.advance(.1,true,locked)
		check(rhythm._movement in Dance.SHARED_STYLES,character+" cannot perform a saved high-level preference before its XP unlock")
		locked.dance_preview = true
		rhythm.advance(.1,true,locked)
		check(rhythm._movement==learned[4],character+" developer preview can demonstrate its own locked move")
		var other := "levin_six_step" if character!="levin" else "mara_precision_step"
		locked.dance_profiles = {character:{"style":other,"intensity":1.0}}
		rhythm.advance(.1,true,locked)
		check(rhythm._movement!=other,character+" never borrows another character's exclusive move")
	for first: String in signatures:
		for second: String in signatures:
			if first<second: check(signatures[first]!=signatures[second],first+" and "+second+" have different authored body/leg/arm paths")
	for style: String in Dance.SHARED_STYLES:
		check(Moves.owns(style),style+" has its own geometry and is shared by the whole crew")
		for character: String in Dance.IDS: check(Dance.allowed(character,style,1),character+" may perform "+style+" at level one")
		for tick in 17: check(not Rhythm.choreography(style,float(tick)*.5).has("front_weight"),style+" shared choreography also remains in the original side view")
	print("DANCE REPERTOIRE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
