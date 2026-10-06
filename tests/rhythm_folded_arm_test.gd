extends SceneTree
## Dancer entry can blend a folded glove through its shoulder. The real
## choreography path must keep both painted links bounded and continuous.
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Personality := preload("res://scripts/worker_personality.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var previous_continuous: bool=PoseArt._continuous
	PoseArt._continuous=false
	var shoulder := Vector2(13.125,-39.375)
	for direction: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,2).normalized()]:
		for distance: float in [0.0,.01,.1,.5,.99,1.01,2.0,12.0,22.8]:
			var hand := shoulder+direction*distance
			var elbow := Rhythm._elbow(shoulder,hand)
			check(elbow.is_finite() and shoulder.distance_to(elbow)<=11.0001,"A tightly folded dance arm never stretches its upper link beyond the actual rig")
			check(elbow.distance_to(hand)<=12.0001,"A tightly folded dance arm keeps its forearm on the original hand target")
			check(not PoseArt._continuous,"Dance IK does not change the static renderer's pixel rounding preference")
	var fractional := Rhythm._elbow(shoulder,shoulder+Vector2(3.17,7.29))
	check(fractional.distance_to(fractional.round())>.05,"The shared dance solver preserves fractional motion even during a raster-rendered character's frame")
	# Each actual character enters a real authored robot pose from a deeply
	# folded hand target. This exercises interpolation and its repair fallback,
	# rather than inspecting a second copy of the IK formula.
	var frame := {"active":true,"motion_gain":1.0,"dance_intensity":1.0,"bar":0,"beat":0,"phase":.23,"audible_seconds":.115,"last_kick_seconds":0.0,"last_kick_strength":1.0,"kick_count":1}
	for id: String in Rhythm.PROFILES:
		var rhythm := Rhythm.new()
		rhythm.configure(id)
		rhythm.weight=1.0
		rhythm._movement="robot"
		for blend: float in [.01,.05,.1,.25,.5,.75,.99]:
			rhythm._dance_blend=blend
			var pose := Personality.stance(PoseArt.neutral(),id)
			var original := PoseArt.torso_transform(pose)
			for index in 2:
				pose.hands[index]=original*PoseArt.shoulder_local(pose,index)+Vector2(.02,.03)
			rhythm.apply(pose,frame)
			var torso := PoseArt.torso_transform(pose)
			for index in 2:
				var arm_shoulder := torso*PoseArt.shoulder_local(pose,index)
				var elbow: Vector2=pose.elbows[index]
				check(elbow.is_finite() and arm_shoulder.distance_to(elbow)<=11.3501 and elbow.distance_to(pose.hands[index])<=12.1001,id+" preserves both arm links through its actual entry blend")
	PoseArt._continuous=previous_continuous
	print("RHYTHM FOLDED ARM: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
