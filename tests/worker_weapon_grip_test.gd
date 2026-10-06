extends "res://tests/worker_weapon_grip_gallery.gd"
## Probes the native rendered pixels over the known opaque weapon foregrip.
## A renderer negative control removes only the foreground hand pass, leaving
## the complete body rig and weapon intact, so a stale skeleton cannot pass.

var cases: Array[Dictionary] = []
var failed_cases: Array[Dictionary] = []
var negative_controls := 0

func _gun_point(weapon: WorkerWeapon, contact: Vector2) -> Vector2:
	# Independent fixture contact contract from the common firearm drawing:
	# trigger (-1,1), foregrip (15,-1), both moving with native recoil.
	var scale_y := 1.0 if weapon.aim_direction.x>=0 else -1.0
	var gun := Transform2D(weapon.aim_direction.angle(), Vector2.ZERO).scaled_local(Vector2(1, scale_y))
	return weapon.get_global_transform_with_canvas()*(gun*(contact-Vector2(weapon.recoil, 0)))

func _palette_pixels(image: Image, center: Vector2, size: float, colors: Array[Color]) -> int:
	var found := 0
	var rect := Rect2i(Vector2i((center-Vector2(3, 2)*size).floor()), Vector2i(roundi(7*size), roundi(6*size))).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var color := image.get_pixel(x, y)
			for expected in colors:
				if color.is_equal_approx(expected):
					found += 1
					break
	return found

func _probe(image: Image, state: String, facing: float, kind: String, pitch: float, recoil: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for actor in board.actors:
		var visual := actor.get_node("PixelVisual") as WorkerVisual
		var weapon := actor.get_node("WorkerWeapon") as WorkerWeapon
		var palette := WorkerIdentityArt.palette(actor.character_id, WorkerPoseArt.C)
		var support := _gun_point(weapon, Vector2(15, -1))
		var trigger := _gun_point(weapon, Vector2(-1, 1))
		var support_pixels := _palette_pixels(image, support, actor.scale.x, [palette.leather_light, palette.leather, palette.skin_light])
		var trigger_pixels := _palette_pixels(image, trigger, actor.scale.x, [palette.leather, palette.skin])
		var tx := ActorWeatherGeometry.worker_transform(visual)
		var geometry_error := INF
		if visual.pose_skeleton.has("hands"):
			var actual: Vector2 = visual.get_global_transform_with_canvas()*(tx*Vector2(visual.pose_skeleton.hands[1]))
			geometry_error = actual.distance_to(support)/actor.scale.x
		var label := "%s %s side=%d pitch=%.2f recoil=%.1f scale=%d" % [actor.character_id, state, facing, pitch, recoil, actor.scale.x]
		var row := {"character":actor.character_id, "state":state, "weapon":kind, "facing":facing, "pitch":pitch, "recoil":recoil, "scale":actor.scale.x, "support_pixels":support_pixels, "trigger_pixels":trigger_pixels, "support_error_native_pixels":geometry_error, "support_pixel":[support.x, support.y], "trigger_pixel":[trigger.x, trigger.y], "pose":visual.pose_name}
		check(geometry_error<.01, label+": actual articulated support hand contacts firearm")
		check(support_pixels>=8*actor.scale.x*actor.scale.x, label+": character glove is visibly over opaque foregrip")
		check(trigger_pixels>=8*actor.scale.x*actor.scale.x, label+": character trigger hand is visibly over receiver")
		if geometry_error>=.01 or support_pixels<8*actor.scale.x*actor.scale.x or trigger_pixels<8*actor.scale.x*actor.scale.x:
			failed_cases.append(row)
		result.append(row)
	return result

func _control(positive: Image, state: String, facing: float) -> void:
	for actor in board.actors:
		var weapon := actor.get_node("WorkerWeapon") as HandlessWeapon
		weapon.omit_hands = true
		weapon.queue_redraw()
	var negative := await _rendered()
	for actor in board.actors:
		var weapon := actor.get_node("WorkerWeapon") as HandlessWeapon
		var palette := WorkerIdentityArt.palette(actor.character_id, WorkerPoseArt.C)
		var contact := _gun_point(weapon, Vector2(15, -1))
		var colors: Array[Color] = [palette.leather_light, palette.leather, palette.skin_light]
		var present := _palette_pixels(positive, contact, actor.scale.x, colors)
		var absent := _palette_pixels(negative, contact, actor.scale.x, colors)
		check(present-absent>=8*actor.scale.x*actor.scale.x, "%s %s side=%d: suppressing foreground glove fails the pixel contract" % [actor.character_id, state, facing])
		negative_controls += 1
		weapon.omit_hands = false
		weapon.queue_redraw()
	if state=="fracture_walk" and facing>0:
		negative.save_png(output+"negative-control-fractured-no-hands.png")
		positive.save_png(output+"positive-fractured-hands.png")

func _run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	_arguments()
	_make_board()
	for kind in KINDS:
		for facing in [1.0, -1.0]:
			for state in ["aim", "fire", "reload", "walk", "crouch", "jump", "fracture_walk", "flinch"]:
				for pitch in [-1.05, 0.0, 1.05]:
					var recoil := 8.0 if state=="fire" else 0.0
					_prepare(state, facing, kind, pitch, recoil)
					var image := await _rendered()
					cases.append_array(_probe(image, state, facing, kind, pitch, recoil))
					if kind=="rifle" and state in ["aim", "fracture_walk"] and pitch==0:
						await _control(image, state, facing)
	check(await CLEANUP.free_scene(view, self), "Actual rendered fixture retires cleanly")
	var file := FileAccess.open(output+"rendered-verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"release":ProjectSettings.get_setting("application/config/version"), "revision":revision, "checks":checks, "failures":failures, "renderer":RenderingServer.get_video_adapter_name(), "prepared_state":"Actual Worker/WorkerVisual/WorkerWeapon; simulation frozen after .2s visual update; 8 identities, both facings, six firearm variants, eight action states including damage flinch, three pitches, native 1x and 3x.", "negative_control":"Production weapon with only the foreground glove method suppressed; original body and firearm rendering remain active.", "negative_controls":negative_controls, "cases":cases, "failed_cases":failed_cases}, "\t"))
	file.close()
	print("WORKER WEAPON GRIP RENDERED: %d cases, %d checks, %d negative controls, %d failures" % [cases.size(), checks, negative_controls, failures])
	quit(1 if failures else 0)
