extends SceneTree
## Drawn elbow reach stays bounded when a wrist folds onto its shoulder.
## Valid grips keep both bone lengths, the authored bend and fractional motion.
const POSE := preload("res://scripts/worker_pose_art.gd")
const PERSONALITY := preload("res://scripts/worker_personality.gd")
const IDS := ["mara","branko","ivo","nora","levin","selma","oskar","rika"]
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
	var previous_continuous := POSE._continuous
	POSE._continuous = true
	for distance: float in [0.0,.0001,.01,.1,.25,.5,.99,1.0,1.01,2.0,5.0,12.0,22.8]:
		for direction in 24:
			var shoulder := Vector2(3.25,-42.125)
			var wrist := shoulder+Vector2.from_angle(float(direction)*TAU/24.0)*distance
			for bend: float in [-1.0,1.0]:
				var elbow := POSE._joint(shoulder,wrist,11.0,12.0,bend)
				var label := "folded wrist d=%.4f direction%d bend%.0f"%[distance,direction,bend]
				check(elbow.is_finite(),label+": elbow stays finite")
				check(absf(shoulder.distance_to(elbow)-11.0)<.002,label+": upper arm cannot shoot away from its shoulder")
				check(wrist.distance_to(elbow)<=12.002,label+": forearm remains bounded with its real wrist endpoint")
				if distance>=1.01:
					check(absf(wrist.distance_to(elbow)-12.0)<.002,label+": reachable grips preserve the exact forearm length")
	# Every identity uses the same arm renderer but different resting anchors.
	# Their native fractional skeletons and both world facings remain supported.
	for id: String in IDS:
		var pose := PERSONALITY.stance(POSE.neutral(),id)
		var body := POSE.torso_transform(pose)
		for index in 2:
			var shoulder := body*POSE.shoulder_local(pose,index)
			var wrist: Vector2 = pose.hands[index]
			var elbow := POSE._joint(shoulder,wrist,11.0,12.0)
			for facing: float in [-1.0,1.0]:
				var mirror := Vector2(facing,1)
				check(absf((shoulder*mirror).distance_to(elbow*mirror)-11.0)<.002,id+": reflected upper arm stays connected")
				check(absf((wrist*mirror).distance_to(elbow*mirror)-12.0)<.002,id+": reflected forearm keeps its actual glove")
	# Rounding belongs only to the old raster wrapper. Fractional dance solves
	# must not depend on whether another actor last drew a discrete atlas pose.
	var fractional_shoulder := Vector2(2.35,-41.7)
	var fractional_wrist := Vector2(9.1,-28.4)
	POSE._continuous = false
	var raster := POSE._joint(fractional_shoulder,fractional_wrist,11,12)
	var fractional := POSE.joint_position(fractional_shoulder,fractional_wrist,11,12)
	check(raster==raster.round(),"raster wrapper preserves pixel rounding")
	check(fractional!=fractional.round(),"pure elbow solve retains subpixel motion")
	check(not POSE._continuous,"pure solve does not mutate another actor's drawing mode")
	POSE._continuous = true
	check(POSE._joint(fractional_shoulder,fractional_wrist,11,12).is_equal_approx(fractional),"continuous draw and dance use the same elbow geometry")
	POSE._continuous = previous_continuous
	print("WORKER ARM GEOMETRY: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
