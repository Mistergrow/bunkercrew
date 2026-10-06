extends SceneTree
## Actual main-scene navigation. Only fixtures are positioned; robot travel uses physics.
const Cleanup = preload("res://tests/scene_cleanup.gd")
const Schema = preload("res://scripts/network_replication_schema.gd")
const NetWorld = preload("res://scripts/network_world.gd")
var checks := 0
var failures := 0
var game
var medic
var crate
var mixer
var player
var largest_step := 0.0
var last_position := Vector2.ZERO
var saw_climb := false

func _initialize(): call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	print("LOGISTICS ","PASS " if ok else "FAIL ",label)
	if not ok:
		failures += 1
		push_error(label)
func frames(count := 3):
	for index in count: await physics_frame
func until(condition: Callable,timeout := 35.0) -> bool:
	var time := 0.0
	while time<timeout and not condition.call():
		await physics_frame
		time += game.get_physics_process_delta_time()
	return condition.call()
func seconds(duration: float): await until(func(): return false,duration)
func follow() -> void:
	if not is_instance_valid(medic): return
	largest_step = maxf(largest_step,medic.global_position.distance_to(last_position))
	last_position = medic.global_position
	saw_climb = saw_climb or medic.climbing
func stock_total() -> int:
	return crate.amount+mixer.input_amount+(0 if medic.logistics_cargo.is_empty() else 1)
func fresh_player() -> void:
	player.medical.interrupt()
	player.medical.bleeding=0
	player.medical.fractured=false
	player.medical.state="healthy"
	player.medical.recovery_time=0
	player.medical.recovery_kind=""
	player.hp=player.max_hp
	player.invulnerability=0
	player.hurt_stun=0
	player.down_time=0
	player.knockback=0
	player.since_hit=99
func setup(environment: String, placement: String):
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	game.start_scenario(1,{"environment":environment,"position":placement,"build_type":"bastion"})
	game.rounds.set_process(false)
	medic=game.medic
	player=game.players[0]
	for station in get_nodes_in_group("stations"):
		station.set_process(false)
		if station.kind=="mixer": mixer=station
		else: station.output_amount=1 # Fixture isolates sand from other valid jobs.
	for supply in get_nodes_in_group("supplies"):
		if supply.kind=="sand": crate=supply
	last_position=medic.global_position
	await frames(6)
func unlock() -> void:
	game.upgrades.points=6
	check(not game.upgrades.purchase("medic_logistics"),"Transport requires workshop research")
	check(game.upgrades.purchase("bunker_workshop") and game.upgrades.purchase("medic_logistics") and game.upgrades.points==0,"Workshop 2 TP plus transport 4 TP consumes exactly six points")
func pickup() -> bool:
	return await until(func(): return medic.logistics_cargo=="sand")
func delivered() -> bool:
	return await until(func(): return mixer.input_amount>0 and medic.logistics_cargo.is_empty())
func run():
	Engine.time_scale=4.0
	Engine.physics_ticks_per_second=240
	await setup("sector07","left")
	physics_frame.connect(follow)
	var total := stock_total()
	await seconds(2)
	check(stock_total()==total and crate.amount==total and medic.logistics_cargo.is_empty(),"Unresearched robot never withdraws or supplies materials")
	unlock()
	check(await pickup(),"Robot physically climbs to the real roof crate and picks up sand")
	check(crate.amount==total-1 and stock_total()==total and mixer.input_amount==0,"Exactly one crate unit is carried before any station deposit")
	check(saw_climb and largest_step<8.0,"Roof trip uses real ladder travel without teleports")
	var cargo_position: Vector2=medic.position
	var progress: float=medic.logistics_progress
	paused=true
	await create_timer(.12,true,false,true).timeout
	check(medic.position==cargo_position and medic.logistics_cargo=="sand" and medic.logistics_progress==progress,"Tree pause freezes travel, cargo and hand-off clock")
	paused=false
	var net=game.network
	net.active=true
	net.is_host=false
	medic._physics_process(2.0)
	medic.logistics.tick(2.0)
	check(medic.position==cargo_position and stock_total()==total,"Client cannot advance transport or mutate authoritative inventory")
	net.active=false
	net.is_host=true
	# A lasting solo wound while SAN-1 carries a unit. A twelve-HP scratch
	# can regenerate near the core before the robot descends from the roof.
	# Forty-two damage produces a real fracture requiring treatment.
	player.position=Vector2(game.scenario_bunker.room_left+370,430)
	player.velocity=Vector2.ZERO
	player.invulnerability=0
	player.take_damage(42.0)
	player.knockback=0
	var prior: int=medic.treatments_completed
	await frames(2)
	check(medic.target==player and medic.logistics_phase=="medical" and medic.logistics_cargo=="sand","Medical need immediately preempts cargo travel without losing its unit")
	check(await until(func():return medic.treatments_completed>prior),"Cargo carrier still reaches and treats the actual patient")
	check(medic.logistics_cargo=="sand" and stock_total()==total,"Medical treatment preserves the complete material balance")
	fresh_player()
	check(await delivered(),"After medical restock SAN-1 resumes and completes its existing delivery")
	check(stock_total()==total and mixer.input_amount==1,"Successful station debit/credit conserves crate + carrier + station")
	var amount_before: int=crate.amount
	await seconds(2.8)
	check(crate.amount==amount_before,"Three-second trip delay prevents immediate next pickup")
	check(await pickup(),"A second independent one-unit trip becomes available")
	mixer.input_amount=mixer.input_cost("sand") # Player fills the target during travel.
	total=stock_total()
	check(await until(func():return medic.logistics_cargo.is_empty()),"Full destination causes a physical return to its existing crate")
	check(stock_total()==total and mixer.input_amount==2 and crate.amount==amount_before,"Full machine never consumes or duplicates returned cargo")
	mixer.input_amount=0
	check(await pickup(),"Robot can start a new trip after return")
	# A destroyed target cannot retain a remote reference or eat the cargo.
	mixer.queue_free()
	await frames()
	amount_before=crate.amount
	check(await until(func():return medic.logistics_cargo.is_empty()),"Destroyed destination returns its in-transit unit")
	check(crate.amount==amount_before+1,"Destroyed target produces exactly one credit at the crate")
	# Isolate a paused carried item to validate schema and malformed values.
	medic.set_physics_process(false)
	crate.amount-=1
	medic.logistics_cargo="sand"
	medic.logistics_phase="deliver"
	medic.logistics_progress=.625
	var replicator=NetWorld.new()
	replicator.game=game
	var state: Dictionary=replicator._capture_fields(medic,Schema.fields("field_medic"))
	check(Schema.valid_state("field_medic",state) and state.logistics_cargo=="sand" and state.logistics_progress==.625,"Snapshot carries one material and the bounded visible delivery phase")
	var mirror=FieldMedic.new()
	replicator._apply_fields(mirror,state)
	check(mirror.logistics_cargo=="sand" and mirror.logistics_phase=="deliver" and mirror.logistics_progress==.625,"Replica applies cargo without executing a second inventory transaction")
	for bad in [{"logistics_cargo":"invalid"},{"logistics_phase":"spawn"},{"logistics_progress":NAN},{"logistics_progress":2.0}]:
		var invalid=state.duplicate(true)
		invalid.merge(bad,true)
		check(not Schema.valid_state("field_medic",invalid),"Malformed logistics snapshot is rejected: "+str(bad))
	mirror.free()
	replicator=null
	# If both the target and all matching crates are removed, keep the item on board.
	medic.logistics.station=null
	medic.logistics.source=null
	crate.queue_free()
	await frames()
	medic.set_physics_process(true)
	await seconds(2.5)
	check(medic.logistics_cargo=="sand" and medic.logistics_phase=="holding","Missing return crate keeps cargo secured instead of spawning or deleting it")
	var replacement=Supply.new()
	replacement.game=game
	replacement.kind="sand"
	replacement.amount=0
	replacement.position=Vector2(game.scenario_bunker.room_left+310,430)
	game.add_child(replacement)
	check(await until(func():return medic.logistics_cargo.is_empty()),"A newly available crate is reached through the existing physical route")
	check(replacement.amount==1,"Previously secured item is returned exactly once")
	await Cleanup.free_scene(game,self)
	for selection in [["frozen_rail_yard","center"],["mountain_pass","right"]]:
		await setup(selection[0],selection[1])
		unlock()
		total=stock_total()
		check(await pickup() and await delivered(),"Actual relocated "+selection[1]+" bunker supports complete roof-to-station delivery")
		check(stock_total()==total,"Relocated bunker inventory remains conserved")
		if selection[1]=="right":
			mixer.input_amount=0
			check(await pickup(),"Blocked-route fixture starts with a real carried crate unit")
			var stock_before: int=crate.amount
			for offset in [-45,45]:
				game.add_terrain(Rect2(mixer.position+Vector2(offset,-110),Vector2(10,110)))
			await frames()
			var timer:=Time.get_ticks_usec()
			var found: bool=medic.logistics._find_job()
			print("BLOCKED JOB SEARCH MS: ",(Time.get_ticks_usec()-timer)/1000.0)
			check(not found,"An enclosed station cannot reserve another crate unit")
			check(await until(func():return medic.logistics_cargo.is_empty()),"A newly blocked destination retries briefly then physically returns cargo")
			check(crate.amount==stock_before+1 and mixer.input_amount==0,"Blocked route returns one unit without remote machine delivery")
		await Cleanup.free_scene(game,self)
	print("MEDIC LOGISTICS: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
