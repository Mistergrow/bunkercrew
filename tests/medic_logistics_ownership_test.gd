extends SceneTree
## Real finite SAN commits cannot cross physics worlds or outlive their robot.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var game: Node
var medic: FieldMedic
var logistics: RefCounted
var stock: Supply
var machine: ProductionStation

func _initialize() -> void: run.call_deferred()

func check(ok: bool, detail: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(detail)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children(): freeze(child)

func prepare(phase: String, source: Node2D, destination: Node2D, cargo: String) -> void:
	logistics._clear_trip()
	medic.logistics_cargo=cargo
	medic.logistics_phase=phase
	logistics.source=source
	logistics.station=destination
	logistics._resource="sand"
	logistics._job="supply"

func refused(target: Node2D, label: String) -> void:
	var cargo: String=medic.logistics_cargo
	var source_amount: int=logistics.source.amount if logistics.source is Supply or logistics.source is ResourcePickup else -1
	var buffer: int=logistics.station.input_amount if logistics.station is ProductionStation else -1
	check(not logistics._live(target),label+": target cannot own this handoff")
	logistics._handoff(target)
	check(medic.logistics_cargo==cargo,label+": carried unit unchanged")
	check((not logistics.source is Supply and not logistics.source is ResourcePickup) or logistics.source.amount==source_amount,label+": source quantity unchanged")
	check(not logistics.station is ProductionStation or logistics.station.input_amount==buffer,label+": machine buffer unchanged")

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_scenario(1,{"environment":"sector07","position":"left","build_type":"bastion"})
	freeze(game)
	medic=game.medic
	logistics=medic.logistics
	game.upgrades.owned={"bunker_workshop":true,"medic_logistics":true,"medic_collection":true}
	medic.position=Vector2(488,430)
	medic.velocity=Vector2.ZERO
	medic.climbing=false
	machine=ProductionStation.new()
	machine.kind="mixer"
	machine.game=game
	machine.position=Vector2(460,430)
	game.add_child(machine)
	freeze(machine)
	stock=Supply.new()
	stock.game=game
	stock.kind="sand"
	stock.amount=2
	stock.position=Vector2(512,430)
	game.add_child(stock)
	freeze(stock)
	var view := SubViewport.new()
	view.world_2d=World2D.new()
	root.add_child(view)
	var separate_stock := Supply.new()
	separate_stock.game=game
	separate_stock.kind="sand"
	separate_stock.amount=2
	separate_stock.position=stock.position
	view.add_child(separate_stock)
	freeze(separate_stock)
	var separate_machine := ProductionStation.new()
	separate_machine.game=game
	separate_machine.kind="mixer"
	separate_machine.position=machine.position
	view.add_child(separate_machine)
	freeze(separate_machine)
	var pickup := ResourcePickup.new()
	pickup.game=game
	pickup.kind="sand"
	pickup.amount=2
	pickup.position=stock.position
	view.add_child(pickup)
	freeze(pickup)
	for unused in 3: await physics_frame
	prepare("collect",stock,machine,"")
	check(logistics._in_reach(stock),"Native crate is physically reachable")
	logistics._handoff(stock)
	check(stock.amount==1 and medic.logistics_cargo=="sand","Native pickup debits exactly one of two units into SAN")
	logistics._handoff(machine)
	check(stock.amount==1 and machine.input_amount==1 and medic.logistics_cargo.is_empty(),"Native delivery conserves both units between crate and machine")
	prepare("collect",separate_stock,machine,"")
	refused(separate_stock,"Same Game reference in an independent World2D")
	prepare("deliver",stock,separate_machine,"sand")
	refused(separate_machine,"Foreign-world recipe delivery")
	prepare("return",separate_stock,machine,"sand")
	refused(separate_stock,"Foreign-world return crate")
	prepare("collect",pickup,machine,"")
	logistics._job="store"
	logistics._depot=stock
	refused(pickup,"Foreign-world loose-material collection")
	game.remove_child(stock)
	prepare("collect",stock,machine,"")
	refused(stock,"Detached source")
	game.add_child(stock)
	prepare("collect",stock,machine,"")
	game.remove_child(medic)
	refused(stock,"Detached SAN")
	game.add_child(medic)
	prepare("return",stock,machine,"sand")
	logistics._handoff(stock)
	check(stock.amount==2 and medic.logistics_cargo.is_empty() and machine.input_amount==1,"Valid native return works after rejected probes and conserves the held unit")
	var retiring_stock := Supply.new()
	retiring_stock.game=game
	retiring_stock.kind="sand"
	retiring_stock.amount=2
	retiring_stock.position=stock.position
	game.add_child(retiring_stock)
	freeze(retiring_stock)
	prepare("collect",retiring_stock,machine,"")
	retiring_stock.queue_free()
	refused(retiring_stock,"Queued native source cannot be debited")
	prepare("collect",stock,machine,"")
	medic.queue_free()
	check(not logistics.authoritative(),"Queued SAN cannot remain a transaction authority")
	refused(stock,"Queued SAN cannot withdraw another unit before retirement")
	var held_stock := stock
	await process_frame
	logistics._handoff(held_stock)
	check(held_stock.amount==2 and not logistics.authoritative(),"Retained logistics helper after actual SAN destruction performs no debit or invalid object access")
	medic=FieldMedic.new()
	medic.game=game
	medic.position=Vector2(488,430)
	game.add_child(medic)
	freeze(medic)
	logistics=medic.logistics
	prepare("collect",held_stock,machine,"")
	game.queue_free()
	refused(held_stock,"Queued owning Game cannot accept a handoff from still-valid SAN children")
	check(await Cleanup.free_scene(game,self),"Actual game, finite crates and machine release cleanly")
	check(await Cleanup.free_scene(view,self),"Independent physics world and its material fixtures release cleanly")
	print("MEDIC LOGISTICS OWNERSHIP: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
