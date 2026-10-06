extends SceneTree
const Cleanup=preload("res://tests/scene_cleanup.gd")
var checks:=0
var failures:=0
var game
var medic
func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	print("TRANSACTION ","PASS " if ok else "FAIL ",label)
	if not ok:
		failures+=1
		push_error(label)
func frames():
	await physics_frame
	await physics_frame
func run():
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	game.start_scenario(1,{"environment":"sector07","position":"left","build_type":"bastion"})
	game.rounds.set_process(false)
	medic=game.medic
	medic.set_physics_process(false)
	game.upgrades.owned={"bunker_workshop":true,"medic_logistics":true}
	for candidate in get_nodes_in_group("stations"):
		candidate.set_process(false)
		candidate.output_amount=1
	for recipe_id: String in Balance.RECIPES:
		var machine=ProductionStation.new() if recipe_id in ["mixer","furnace"] else RecipeStation.new()
		machine.kind=recipe_id
		machine.game=game
		machine.position=Vector2(460,430)
		game.add_child(machine)
		machine.set_process(false)
		for resource: String in machine.input_kinds():
			machine.input_amount=0
			if machine is RecipeStation: machine.ingredient_amounts.clear()
			var stock=Supply.new()
			stock.game=game
			stock.kind=resource
			stock.amount=2
			stock.position=Vector2(512,430)
			game.add_child(stock)
			medic.position=Vector2(488,430)
			medic.velocity=Vector2.ZERO
			medic.climbing=false
			medic.logistics_cargo=""
			medic.logistics_phase="collect"
			medic.logistics.source=stock
			medic.logistics.station=machine
			medic.logistics._resource=resource
			medic.logistics._destination=null
			await frames()
			medic.logistics._visit(stock,.60)
			medic.logistics._visit(stock,.64)
			check(stock.amount==2 and medic.logistics_cargo.is_empty(),recipe_id+" "+resource+": incomplete 1.24 s pickup preserves the crate")
			medic.logistics._visit(stock,.02)
			check(stock.amount==1 and medic.logistics_cargo==resource,recipe_id+" "+resource+": one completed hold takes exactly one item")
			medic.logistics._visit(machine,.5)
			var before:int=machine.amount_for(resource) if machine is RecipeStation else machine.input_amount
			check(before==0 and medic.logistics_cargo==resource,recipe_id+" "+resource+": short delivery keeps cargo secured")
			medic.logistics._visit(machine,.76)
			var stored:int=machine.amount_for(resource) if machine is RecipeStation else machine.input_amount
			check(stored==1 and stock.amount==1 and medic.logistics_cargo.is_empty(),recipe_id+" "+resource+": crate + exact recipe buffer conserves both units")
			if machine is RecipeStation:
				check(machine.ingredient_amounts.size()==(0 if resource==machine.input_kind() else 1),recipe_id+": other ingredient buffers remain untouched")
			stock.queue_free()
		machine.input_amount=machine.input_cost(machine.input_kind())
		check(not medic.logistics.needs_input(machine,machine.input_kind()),recipe_id+": full ingredient buffer refuses another unit")
		machine.input_amount=0
		machine.output_amount=1
		check(not medic.logistics.needs_input(machine,machine.input_kind()),recipe_id+": finished output blocks automation")
		machine.output_amount=0
		machine.working=true
		check(not medic.logistics.needs_input(machine,machine.input_kind()),recipe_id+": working batch owns its inputs")
		machine.working=false
		if recipe_id=="mixer":
			machine.binder=0
			check(not medic.logistics.needs_input(machine,"sand"),"Spent binder prevents stranded automated sand")
		machine.queue_free()
		await frames()
	var return_crate=Supply.new()
	return_crate.game=game
	return_crate.kind="sand"
	return_crate.amount=10000
	return_crate.position=Vector2(512,430)
	game.add_child(return_crate)
	medic.logistics_cargo="sand"
	medic.logistics_phase="return"
	medic.logistics.source=return_crate
	medic.logistics.station=null
	medic.logistics._search_clock=2.0
	medic.logistics.tick(.02)
	check(return_crate.amount==10000 and medic.logistics_cargo=="sand" and medic.logistics_phase=="holding","Full 10000-unit crate cannot exceed network bounds or delete its returned unit")
	medic.logistics.source=return_crate
	medic.logistics_phase="return"
	medic.logistics._handoff(return_crate)
	check(return_crate.amount==10000 and medic.logistics_cargo=="sand","Commit repeats the crate capacity check after a simultaneous player deposit")
	return_crate.amount=0
	medic.logistics.source=return_crate
	medic.logistics_phase="return"
	var barrier=game.add_terrain(Rect2(498,390,6,40))
	await frames()
	medic.logistics._handoff(return_crate)
	check(return_crate.amount==0 and medic.logistics_cargo=="sand","Physical wall blocks a close-range handoff without inventory changes")
	barrier.queue_free()
	await frames()
	game.upgrades.owned.erase("medic_logistics")
	medic.logistics._destination=null
	medic.logistics.tick(1.25)
	check(return_crate.amount==1 and medic.logistics_cargo.is_empty(),"Cancelling the unlock still permits a physical return of existing cargo")
	var pending_machine=get_nodes_in_group("stations")[0]
	pending_machine.output_amount=0
	pending_machine.input_amount=0
	return_crate.kind="ore"
	medic.logistics.source=return_crate
	medic.logistics.station=pending_machine
	medic.logistics._resource="sand"
	medic.logistics_phase="collect"
	game.upgrades.owned.medic_logistics=true
	medic.logistics._handoff(return_crate)
	check(return_crate.amount==1 and medic.logistics_cargo.is_empty(),"A changed source material cannot be converted into the reserved ingredient")
	var other=Node2D.new()
	root.add_child(other)
	var foreign=Supply.new()
	foreign.game=other
	other.add_child(foreign)
	check(not medic.logistics._live(foreign),"Another scene's crate cannot participate in this world's ledger")
	foreign.queue_free()
	other.queue_free()
	await Cleanup.free_scene(game,self)
	print("MEDIC TRANSACTIONS: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
