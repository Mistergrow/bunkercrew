extends SceneTree
## Actual target actions and drawn grips; no separate cosmetic work state can
## manufacture a pour, consume cargo or mutate the authoritative work clock.
const Work := preload("res://scripts/worker_work_pose.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Locomotion := preload("res://scripts/worker_locomotion.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const IDS := ["mara","branko","ivo","nora","levin","selma","oskar","rika"]
var checks := 0
var failures := 0

class RoundFixture extends Node:
	var wave := 16
	var phase := "salvage"

class UpgradeFixture extends Node:
	func has_upgrade(_id: String) -> bool:
		return true
	func carry_capacity() -> int:
		return Balance.CARRY_CAPACITY

class WorldFixture extends Node2D:
	var rounds: Node
	var upgrades: Node
	var network: Node

class NetworkFixture extends Node:
	var active := false
	var is_host := false

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func _anatomy(pose: Dictionary,label: String) -> void:
	var body := PoseArt.torso_transform(pose)
	for index in 2:
		var shoulder := body*PoseArt.shoulder_local(pose,index)
		check(Vector2(pose.hands[index]).distance_to(shoulder)<22.91,label+" keeps both actual tool/load gloves connected")
		check(is_equal_approx(float(pose.feet[index].y),-3.0),label+" keeps both soles supported")
		check(Vector2(pose.feet[index]).distance_to(Vector2(pose.hip)+Vector2(-2.0 if index==0 else 2.0,0.0))<24.05,label+" bends the supported knee without stretching a shin")
	check(not pose.has("front_weight") and not bool(pose.get("back",false)),label+" preserves the side-facing identity")

func _run() -> void:
	InputSetup.install()
	var world := WorldFixture.new()
	world.rounds = RoundFixture.new()
	world.upgrades = UpgradeFixture.new()
	world.add_child(world.rounds)
	world.add_child(world.upgrades)
	root.add_child(world)
	var worker := Worker.new()
	world.add_child(worker)
	worker.set_physics_process(false)
	worker.game = world
	var visual := WorkerVisual.new()
	visual.name = "PixelVisual"
	worker.add_child(visual)
	visual.set_process(false)
	visual.set_physics_process(false)
	var wall := DefenseWall.new()
	wall.game = world
	world.add_child(wall)
	wall.set_process(false)
	for id: String in IDS:
		worker.configure_character(id)
		check(Locomotion.PROFILES.has(id),id+" has an explicit authored gait")
		for facing: float in [-1.0,1.0]:
			worker.facing = facing
			for distance: float in [34.0,58.0,88.0]:
				wall.position.x = distance*facing
				for kind: String in ["form","reinforce","pour","repair","upgrade"]:
					wall.state = DefenseWall.State.EMPTY if kind=="form" else DefenseWall.State.FORM if kind in ["reinforce","pour"] else DefenseWall.State.HARD
					wall.max_hp = 250
					wall.hp = 100 if kind=="repair" else 250
					wall.tier = 1
					worker.inventory = {"concrete":6} if kind in ["pour","repair"] else {"steel":6,"concrete":6}
					for frame in 61:
						wall.work = float(frame)/60.0
						var before := [wall.state,wall.hp,wall.work,wall.work_action,wall.tier,worker.inventory.duplicate(true),worker.position,worker.velocity]
						var pose := Work.sample(worker,wall)
						check(pose.work_action==kind,id+" reads the actual "+kind+" wall action")
						_anatomy(pose,id+" "+kind)
						check(before==[wall.state,wall.hp,wall.work,wall.work_action,wall.tier,worker.inventory,worker.position,worker.velocity],"Sampling never changes gameplay material, health, clock or motion")
						if kind=="pour":
							check(pose.cargo_kind=="concrete" and pose.hands[0]==pose.cargo+Vector2(-7,0) and pose.hands[1]==pose.cargo+Vector2(5,3),"Pour has two exact rigid bucket grips")
							check(bool(pose.cargo_pour)==(frame>9 and frame<60),"Concrete flows during the actual target pour phase and ends on recovery")
						else:
							check(not bool(pose.get("cargo_pour",false)),"Other wall work never invents a concrete stream")
	var station := ProductionStation.new()
	station.kind = "furnace"
	station.position = Vector2(48,0)
	world.add_child(station)
	station.set_process(false)
	worker.character_id = "mara"
	worker.facing = 1.0
	worker.inventory = {"ore":2,"concrete":3}
	worker.selected_kind = "concrete"
	for phase in [0.0,0.2,0.45,0.7,1.0]:
		station.transfer[worker.get_instance_id()] = phase*Balance.TRANSFER_TIME
		var pose := Work.sample(worker,station)
		check(pose.work_action=="deposit" and pose.cargo_kind=="ore" and not pose.cargo_pour,"Furnace receives its real ore input even when concrete is selected")
		_anatomy(pose,"Machine handoff")
	worker.inventory = {"scrap":2,"concrete":2}
	check(Work.sample(worker,station).cargo_kind=="scrap","The furnace alternate scrap matches the actual input rule")
	station.output_amount = 2
	check(Work.sample(worker,station).work_action=="collect","Actual finished goods select an output collection pose")
	worker.inventory = {"concrete":worker.capacity()}
	check(Work.sample(worker,station).work_action=="wait","A full load cannot fabricate another output transfer")
	station.output_amount = 0
	station.working = true
	worker.focus = station
	worker._interacting = true
	worker.velocity = Vector2.ZERO
	visual._process(0.15)
	check(visual.work_pose.work_action=="wait" and visual.pose_skeleton.has("cargo") and not visual.pose_skeleton.cargo_pour,"An operating furnace preserves held cargo without pretending it can receive concrete")
	station.working = false
	worker.inventory = {"ore":2,"concrete":3}
	visual._process(0.0)
	check(visual.work_pose.work_action=="deposit" and visual.pose_skeleton.cargo_kind=="ore" and not visual.pose_skeleton.cargo_pour,"Actual WorkerVisual uses the target handoff instead of its selected-material pouring flag")
	var helper := Worker.new()
	helper.game = world
	world.add_child(helper)
	helper.set_physics_process(false)
	helper.inventory = {"steel":2}
	wall.state = DefenseWall.State.FORM
	wall.work = 0.0
	wall.work_action = ""
	worker.inventory = {"concrete":6}
	wall.interact(helper,0.05)
	var shared_work := wall.work
	wall.interact(worker,0.05)
	check(wall.work_action=="reinforce" and is_equal_approx(wall.work,shared_work),"Real concurrent interaction preserves the active reinforcement instead of accepting a second worker's pour")
	check(Work.sample(helper,wall).work_action=="reinforce" and Work.sample(worker,wall).work_action=="wait","The visible work rig follows the actual same-frame wall conflict gate")
	wall.last_work_frame = Engine.get_physics_frames()-4
	check(Work.sample(worker,wall).work_action=="pour","The existing four-frame grace expiry allows the actual next worker action")
	world.network = NetworkFixture.new()
	world.add_child(world.network)
	world.network.active = true
	for offset: int in [-10000,10000]:
		wall.last_work_frame = Engine.get_physics_frames()+offset
		check(Work.sample(worker,wall).work_action=="wait" and Work.sample(helper,wall).work_action=="reinforce","A replica with a different physics clock follows the actual host action and never fabricates blocked pouring")
	world.network.active = false
	for multi: RecipeStation in [GlassFurnace.new(),DeepProductionStation.new()]:
		if multi is DeepProductionStation:
			multi.kind = "alloy"
		world.add_child(multi)
		multi.position = Vector2(48,0)
		multi.set_process(false)
		var primary: String = multi.input_kind()
		var secondary: String = multi.recipe().inputs.keys()[1]
		multi.set_amount(primary,multi.input_cost(primary))
		worker.inventory = {secondary:1}
		worker.selected_kind = secondary
		multi.interact(worker,0.05)
		var actual_phase: float = float(multi.transfer[worker.get_instance_id()])/Balance.TRANSFER_TIME
		var material_pose := Work.sample(worker,multi)
		check(material_pose.work_action=="deposit" and material_pose.cargo_kind==secondary and is_equal_approx(material_pose.work_phase,actual_phase),"A real "+multi.kind+" handoff with the primary buffer full renders its remaining secondary ingredient")
		multi.set_amount(primary,0)
		multi.set_amount(secondary,0)
		worker.inventory = {primary:1,secondary:1}
		multi.interact(worker,0.05)
		worker.focus = multi
		visual._process(0.0)
		check(visual.work_pose.work_action=="deposit" and visual.pose_skeleton.cargo_kind==secondary,"Actual WorkerVisual respects the selected secondary ingredient in "+multi.kind)
		worker.selected_kind = ""
		var before := [worker.selected_kind,worker.inventory.duplicate(true),multi.input_amount,multi.ingredient_amounts.duplicate(true),multi.transfer.duplicate(true)]
		Work.sample(worker,multi)
		check(before==[worker.selected_kind,worker.inventory,multi.input_amount,multi.ingredient_amounts,multi.transfer],"Recipe presentation preserves even an unset player material selection and all authoritative ingredient/transfer values")
	worker._interacting = false
	worker.focus = null
	visual._process(1.0/60.0)
	check(visual.work_pose.is_empty() and not visual.pose_skeleton.has("work_action"),"Releasing interaction immediately gives locomotion ownership")
	worker.inventory = {"ore":2}
	worker.velocity = Vector2(80,0)
	worker.position = Vector2.ZERO
	worker._interacting = true
	worker.focus = station
	var feet_before: Array = []
	for frame in 30:
		worker.position.x+=80.0/60.0
		visual._process(1.0/60.0)
		if frame==10:
			feet_before = visual.pose_skeleton.feet.duplicate()
	check(visual.pose_name=="work" and visual.locomotion.phase>0.1 and visual.pose_skeleton.feet!=feet_before,"Moving while working retains displacement-driven steps instead of sliding with fixed work boots")
	worker.velocity = Vector2.ZERO
	worker._interacting = true
	worker.focus = station
	station.queue_free()
	visual._process(0.0)
	check(visual.work_pose.is_empty(),"Queued targets cannot retain a work stream")
	check(is_equal_approx(Work.pressure(0.42),1.0) and is_equal_approx(Work.pressure(0.55),1.0) and Work.pressure(0.3)<0.0 and is_zero_approx(Work.pressure(1.0)),"Work reads as preparation, held contact and slower recovery")
	check(await Cleanup.free_scene(world,self),"Work fixtures release cleanly")
	print("WORKER WORK POSE: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
