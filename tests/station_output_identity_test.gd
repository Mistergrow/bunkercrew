extends SceneTree
## Real paid concrete production, pickup and Q-drop retain one item identity.
## Optional native comparison exercises the actual machine renderer, not a mock.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const World := preload("res://scripts/network_world.gd")
const DEST := "res://artifacts/station-output/"
var checks := 0
var failures := 0
var game: Node
var view: SubViewport
var captures: Array = []

class ExpectedBuckets extends Node2D:
	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	func _draw() -> void:
		PickupArt.draw_world(self,"concrete",0,Vector2(64,0))
		PickupArt.draw_world(self,"concrete",0,Vector2(90,0))

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func frames(count: int = 3) -> void:
	for _index in count: await process_frame
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func capture(name: String, state: Dictionary) -> Image:
	await frames(4)
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	check(picture.save_png(DEST+name+".png")==OK,"Native capture: "+name)
	captures.append({"image":name+".png","state":state})
	return picture
func machine_pixels_equal(a: Image, b: Image, mixer: Node2D) -> bool:
	var rect := Rect2i(mixer.get_global_transform_with_canvas()*Rect2(50,-29,53,30))
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			if a.get_pixel(x,y)!=b.get_pixel(x,y): return false
	return true
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var native := DisplayServer.get_name()!="headless" and "--capture" in OS.get_cmdline_user_args()
	AudioServer.set_bus_mute(0,true)
	LocaleText.set_locale("de",false)
	if native:
		DirAccess.make_dir_recursive_absolute(DEST)
		root.size = Vector2i(320,180)
		root.position = Vector2i(2000,80)
		root.set_flag(Window.FLAG_NO_FOCUS,true)
		view = SubViewport.new()
		view.world_2d = World2D.new()
		view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		view.size = Vector2i(960,540)
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
	game = load("res://scenes/main.tscn").instantiate()
	if native: view.add_child(game)
	else: root.add_child(game)
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.set_process(false)
	game.medic.set_physics_process(false)
	game.expedition.set_physics_process(false)
	game.dialogue.reset()
	var mixer: ProductionStation
	for station in get_nodes_in_group("stations"):
		if station.game!=game: continue
		station.set_process(false)
		if station.kind=="mixer": mixer=station
	var worker: Worker = game.players[0]
	worker.set_physics_process(false)
	worker.position = mixer.position+Vector2(30,0)
	worker.inventory = {"sand":2}
	mixer.binder = 1
	mixer.interact(worker,Balance.TRANSFER_TIME)
	mixer.interact(worker,Balance.TRANSFER_TIME)
	check(worker.inventory.is_empty() and mixer.input_amount==2,"Two finite sand units enter the actual mixer through its interaction API")
	mixer._process(0.0)
	check(mixer.working and mixer.input_amount==0 and mixer.binder==0,"The actual paid batch consumes both inputs and its final binder")
	mixer._process(mixer.duration())
	check(not mixer.working and mixer.output_kind()=="concrete" and mixer.output_amount==2,"Completing the real batch leaves two concrete units in the machine output buffer")
	check(get_nodes_in_group("pickups").is_empty(),"Ready output pictures do not mint extra physical pickup entities")
	check(ItemCatalog.data("concrete").art.world_width==21,"Concrete keeps its original compact 21-pixel floor silhouette")
	if native:
		worker.position = Vector2(700,430)
		await create_timer(0.65).timeout
		freeze(game)
		for tween in get_processed_tweens(): tween.kill()
		game.hud.canvas.visible = false
		game.camera.position_smoothing_enabled = false
		game.camera.position = mixer.position+Vector2(40,-52)
		game.camera.zoom = Vector2.ONE*4
		game.camera.reset_smoothing()
		game.camera.force_update_scroll()
		var ready := await capture("paid-mixer-4x",{"prepared":"Actual finite sand deposit and completed final-binder batch; simulation held for inspection","output_kind":mixer.output_kind(),"output_amount":mixer.output_amount,"binder":mixer.binder,"camera_zoom":game.camera.zoom,"camera_position":game.camera.position,"mixer_position":mixer.position,"viewport":[960,540]})
		# Replace only the prepared output presentation while all simulation is
		# held. The authored reference silhouettes must match the real renderer.
		mixer.output_amount = 0
		mixer.queue_redraw()
		var expected := ExpectedBuckets.new()
		expected.position = mixer.position
		game.add_child(expected)
		var reference := await capture("expected-bucket-render",{"prepared":"Pixel-reference overlay using the registered concrete silhouettes; no gameplay transfer","reference_source":"res://assets/workers/material_props.png","region":[74,0,21,23]})
		check(machine_pixels_equal(ready,reference,mixer),"The actual ready-output renderer displays the registered bucket pixels instead of generic bars")
		expected.queue_free()
		mixer.output_amount = 2
		mixer.queue_redraw()
		await frames()
	worker.position = mixer.position+Vector2(30,0)
	mixer.interact(worker,Balance.TRANSFER_TIME)
	mixer.interact(worker,Balance.TRANSFER_TIME)
	mixer.queue_redraw()
	check(mixer.output_amount==0 and worker.inventory=={"concrete":2},"Both displayed buckets are collected from the existing finite machine buffer")
	mixer.interact(worker,Balance.TRANSFER_TIME)
	check(mixer.output_amount==0 and worker.inventory=={"concrete":2},"A repeated collection cannot recreate finished goods")
	worker.position = mixer.position+Vector2(90,0)
	worker.selected_kind = "concrete"
	worker.facing = 1.0
	await physics_frame
	await physics_frame
	Input.action_press(worker.action("drop"))
	worker._update_material_controls(0.1)
	Input.action_release(worker.action("drop"))
	worker._update_material_controls(0.016)
	await frames()
	var drops := get_nodes_in_group("pickups").filter(func(pile):return pile.game==game)
	check(drops.size()==1 and worker.inventory=={"concrete":1},"A real Q tap debits exactly one crafted concrete unit and creates one owned world pickup")
	if drops.size()==1:
		var pile: ResourcePickup = drops[0]
		if native: pile.set_physics_process(true)
		for _index in 30: await physics_frame
		pile.set_physics_process(false)
		check(pile.kind=="concrete" and pile.amount==1 and pile.supported() and absf(pile.position.y-429.5)<0.1,"The crafted Q-drop retains bucket identity and settles on the real floor")
		check(pile.material==PickupArt.cutout_material() and not pile.is_processing(),"The compact crafted drop shares the GPU material without a redraw callback")
		var authority := World.new()
		authority.bind(game)
		var snapshot: Dictionary = authority.capture()
		var records: Array = snapshot.entities.filter(func(record):return record.type=="resource_pickup")
		check(records.size()==1 and records[0].state.kind=="concrete" and records[0].state.amount==1,"The authoritative snapshot records one concrete unit rather than extra output pictures")
		if native:
			worker.drop_animation = 0.0
			worker.pickup_animation = 0.0
			worker.position = mixer.position+Vector2(-10,0)
			# Simulation is deliberately frozen in this gallery. Refresh the real
			# visual controller after the transfers so its cached load pose and
			# the machine drawing reflect the same finite state as the ledger.
			var visual: Node = worker.get_node("PixelVisual")
			visual._process(0.16)
			visual._process(0.16)
			mixer.queue_redraw()
			check(visual.pose_name=="carry_idle" and str(visual.pose_skeleton.get("cargo_kind",""))=="concrete","The native prepared worker pose holds its actual remaining concrete unit")
			await capture("crafted-carry-and-q-drop",{"prepared":"The same paid batch after two collections and one real Q tap; one unit carried and one physically supported pickup","machine_output":mixer.output_amount,"inventory":worker.inventory.duplicate(),"pickup":{"kind":pile.kind,"amount":pile.amount,"position":pile.position,"base_width":21},"camera_zoom":4})
		worker.position = pile.position+Vector2(-28,0)
		pile.interact(worker,0.016)
		check(pile.amount==0 and worker.inventory=={"concrete":2},"Picking up the crafted Q-drop conserves both original concrete units")
		pile.interact(worker,0.016)
		check(worker.inventory=={"concrete":2},"Repeated contact with the consumed bucket cannot duplicate its content")
	if native:
		var file := FileAccess.open(DEST+"captures.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(captures,"\t"))
	check(await Cleanup.free_scene(game,self),"Production and pickup fixture releases without profile changes")
	if is_instance_valid(view):
		view.queue_free()
		await process_frame
	print("STATION OUTPUT IDENTITY: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
