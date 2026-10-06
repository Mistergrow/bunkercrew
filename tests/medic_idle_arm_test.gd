extends SceneTree
## The actual assistant's drawn inspection grip follows either travel facing.
## Native captures separately check the unchanged paint and other arm modes.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children(): freeze(child)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var game := load("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(game)
	game.start_scenario(1,{"environment":"sector07","build_type":"bastion","position":"left"})
	freeze(game)
	var medic: FieldMedic = game.medic
	check(is_instance_valid(medic),"Fixture uses the physical assistant created by the real bunker")
	medic._idle_time=4.0
	medic.elapsed=7.2
	medic.rhythm_pose.clear()
	medic.logistics_cargo="steel"
	var position := medic.global_position
	var velocity := medic.velocity
	var supplies := medic.medical_supplies
	var cargo := medic.logistics_cargo
	for bob: float in [-1.0,0.0,1.0]:
		medic.facing=1.0
		var right := medic._inspection_arm_pose(bob)
		medic.facing=-1.0
		var left := medic._inspection_arm_pose(bob)
		var right_shoulder: Vector2=right.shoulder
		var right_hand: Vector2=right.hand
		var right_casing: Rect2=right.casing
		var left_shoulder: Vector2=left.shoulder
		var left_hand: Vector2=left.hand
		var left_casing: Rect2=left.casing
		check(left_shoulder==right_shoulder*Vector2(-1,1),"Inspection shoulder follows the assistant's real facing")
		check(left_hand==right_hand*Vector2(-1,1),"Inspection hand stays in front on either travel side")
		check(left_casing.position==Vector2(-right_casing.end.x,right_casing.position.y) and left_casing.size==right_casing.size,"The complete rectangular hand casing mirrors without a width offset")
		check(left_casing.has_point(left_hand) and right_casing.has_point(right_hand),"The painted hand grip remains attached inside its real casing")
		check(left_hand.x<left_shoulder.x and right_hand.x>right_shoulder.x,"Changing facing cannot leave the inspection arm pointing behind the robot")
		check(right_hand.distance_to(right_shoulder)<12.0 and left_hand.distance_to(left_shoulder)==right_hand.distance_to(right_shoulder),"The reflected arm keeps its original compact mechanical reach")
	check(medic.global_position==position and medic.velocity==velocity and medic.medical_supplies==supplies and medic.logistics_cargo==cargo,"Sampling the idle grip cannot move the physical assistant or consume cargo/supplies")
	check(not medic.rhythm_pose.is_active(),"Inspection does not start or alter robotic dance software")
	check(await Cleanup.free_scene(game,self),"The actual assistant and game release all scene/audio handles")
	print("MEDIC IDLE ARM: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
