extends SceneTree
## Prepared finite inventories with real workers, stores and gun handlers.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Vehicle := preload("res://scripts/convoy_vehicle.gd")
var game
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("AMMUNITION %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok: failures+=1
func frames(count: int=2) -> void:
	for unused in count: await physics_frame
func round_count(worker: Node) -> int:
	return worker.get_node("WorkerWeapon").total_ammunition()+int(worker.inventory.get("ammo",0))*20
func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(4,{"environment":"ash_foundry","build_type":"workshop","position":"left"})
	game.combat_events.persistence_enabled=false
	game.rounds.running=false
	game.rounds.set_process(false)
	game.expedition.set_physics_process(false)
	for player in game.players:
		player.set_physics_process(false)
		player.get_node("WorkerWeapon").set_physics_process(false)
	await frames()
	for player in game.players:
		var slot_weapon: WorkerWeapon=player.get_node("WorkerWeapon")
		slot_weapon.loaded.rifle=30
		slot_weapon.reserve=119
		slot_weapon.open_pack=0
		player.inventory={"ammo":1}
		var total:=round_count(player)
		check(slot_weapon.request_reload() and slot_weapon.reserve==120 and slot_weapon.open_pack==19 and player.inventory.is_empty(),"P%d fills last reserve round while retaining nineteen in opened box"%player.player_id)
		check(round_count(player)==total,"P%d partial refill conserves all carried rounds"%player.player_id)
		check(not slot_weapon.start_reload() and slot_weapon.open_pack==19 and round_count(player)==total,"P%d full magazine and reserve consume no extra box"%player.player_id)
		slot_weapon.loaded.rifle=3
		slot_weapon.reserve=5
		slot_weapon.open_pack=0
		player.inventory={"ammo":2}
		total=round_count(player)
		check(slot_weapon.start_reload(),"P%d starts one complete reload from a partial reserve"%player.player_id)
		slot_weapon._physics_process(2)
		check(slot_weapon.current_ammo()==30 and slot_weapon.reserve==0 and slot_weapon.open_pack==18 and round_count(player)==total,"P%d fills magazine in one animation without discarding partial box"%player.player_id)
	var player=game.players[0]
	var weapon: WorkerWeapon=player.get_node("WorkerWeapon")
	var source:=Supply.new()
	source.game=game
	source.kind="ammo"
	source.amount=9
	source.position=Vector2(1200,-300)
	game.add_child(source)
	player.position=source.position
	player.focus=source
	player.inventory={"ore":player.capacity()}
	weapon.loaded.rifle=30
	weapon.reserve=113
	weapon.open_pack=0
	await frames()
	check(source.can_interact(player) and weapon.request_reload(),"R at actual ammunition crate bypasses a cargo bag full of ore")
	check(source.amount==8 and weapon.reserve==120 and weapon.open_pack==13 and player.carried_count()==player.capacity(),"direct refill spends one physical crate and retains thirteen rounds without moving ore")
	for expected in [8,3]:
		weapon.reserve=115
		check(weapon.refill_from_inventory()==5 and weapon.reserve==120 and weapon.open_pack==expected and source.amount==8,"repeated partial refill consumes only five saved rounds")
		check(weapon.refill_from_supply(source)==0 and weapon.open_pack==expected and source.amount==8,"full reserve never opens another physical crate")
	weapon.reserve=115
	check(weapon.refill_from_supply(source)==5 and weapon.open_pack==18 and source.amount==7,"last partial refill uses three old rounds before opening exactly one new crate")
	weapon.reserve=100
	player.position.x+=500
	check(weapon.refill_from_supply(source)==0 and source.amount==7,"distant supply cannot teleport ammunition")
	player.position=source.position
	var obstacle:=StaticBody2D.new()
	obstacle.collision_layer=2
	var collider:=CollisionShape2D.new()
	var box:=RectangleShape2D.new()
	box.size=Vector2(8,80)
	collider.shape=box
	obstacle.add_child(collider)
	obstacle.position=source.position+Vector2(-15,-20)
	game.add_child(obstacle)
	player.position.x-=30
	await frames()
	check(weapon.refill_from_supply(source)==0 and source.amount==7,"physical wall blocks direct ammunition transfer")
	obstacle.queue_free()
	player.focus=null
	var roof=game.turret
	roof.set_physics_process(false)
	roof.enter(player)
	roof.ammo=2
	roof.reserve=5
	weapon.open_pack=0
	player.inventory={"ammo":3}
	check(roof.start_reload(),"roof gun reload begins with existing five-round reserve")
	roof._physics_process(2)
	check(roof.ammo==60 and roof.reserve==0 and weapon.open_pack==7 and player.inventory.is_empty(),"roof reload collects enough finite crates for full magazine and keeps seven rounds")
	roof.reserve=179
	weapon.open_pack=0
	player.inventory={"ammo":1}
	check(roof.start_reload() and roof.reserve==180 and weapon.open_pack==19,"roof R tops up partial reserve even when magazine is full")
	roof.exit()
	var flak:=FlakTurret.new()
	flak.game=game
	flak.position=Vector2(1150,-300)
	game.add_child(flak)
	flak.set_physics_process(false)
	flak.reserve=119
	weapon.open_pack=0
	player.inventory={"ammo":1}
	check(flak.accept_ammo(player) and flak.reserve==120 and weapon.open_pack==19,"flak accepts one final round from a real crate")
	var station:=FlakStation.new()
	station.game=game
	station.available=true
	station.built=true
	station.tier=1
	station.turret=flak
	game.add_child(station)
	game.rounds.wave=12
	flak.reserve=115
	player.inventory.clear()
	player.selected_kind=""
	check(station._maintenance(player)=="ammo","opened box remains usable at flak console despite upgrade availability")
	station.interact(player,Balance.TRANSFER_TIME)
	check(flak.reserve==120 and weapon.open_pack==14,"console moves five remaining rounds rather than requiring another full crate")
	var sentry=game.perimeter.sites.filter(func(site):return site.role=="ground")[0]
	sentry.set_physics_process(false)
	sentry.tier=1
	sentry.hp=160
	sentry.max_hp=160
	sentry.ammo=33
	player.position=sentry.position
	player.inventory={"ammo":1}
	player.selected_kind="ammo"
	weapon.open_pack=0
	for unused in 4: sentry.interact(player,.25)
	check(sentry.ammo==40 and weapon.open_pack==13 and player.inventory.is_empty(),"ground sentry can fill last seven rounds and preserves remainder")
	var truck:=Vehicle.new()
	truck.game=game
	game.add_child(truck)
	truck.set_physics_process(false)
	truck.has_mg=true
	truck.ammo=40
	truck.reserve=239
	truck.cargo={"ammo":1}
	check(truck.start_reload() and truck.reserve==240 and truck.open_pack==19 and truck.cargo.is_empty(),"convoy fills final reserve round and preserves nineteen from the standard twenty-round crate")
	var durable: Dictionary=truck.vehicle_data()
	check(CampaignState.valid_vehicle(durable),"opened convoy crate is a bounded durable vehicle field")
	truck.ammo=3
	truck.reserve=5
	truck.open_pack=0
	truck.cargo={"ammo":1}
	check(truck.start_reload(),"convoy reload works with partial reserve plus cargo")
	truck._physics_process(2)
	check(truck.ammo==28 and truck.reserve==0 and truck.open_pack==0 and truck.cargo.is_empty(),"convoy partial reload preserves all twenty cargo rounds when a full magazine is unaffordable")
	truck.cargo={"ammo":1}
	check(truck.start_reload(),"another real crate can complete the partial vehicle magazine")
	truck._physics_process(2)
	check(truck.ammo==40 and truck.reserve==0 and truck.open_pack==8 and truck.cargo.is_empty(),"convoy consumes only twelve additional rounds and preserves eight")
	for worker in game.players:
		var item: WorkerWeapon=worker.get_node("WorkerWeapon")
		item.loaded.rifle=8+worker.player_id
		item.loaded.shotgun=worker.player_id
		item.loaded.arcgun=2+worker.player_id
		item.loaded.veteran_rifle=1+worker.player_id
		item.loaded.breacher_shotgun=worker.player_id
		item.loaded.storm_arcgun=worker.player_id
		item.reserve=11+worker.player_id
		item.open_pack=worker.player_id
		worker.inventory.clear()
		var original:=item.capture_ammunition()
		var snapshot:=CampaignBonus.snapshot_player(worker)
		check(CampaignBonus.valid_snapshot(snapshot) and snapshot.ammunition==original,"P%d snapshot contains every finite magazine and open box"%worker.player_id)
		item.loaded.rifle=30
		item.reserve=90
		item.open_pack=0
		game.campaign.snapshots[str(worker.player_id)]=snapshot
		check(CampaignBonus.restore_player(worker,game.campaign) and item.capture_ammunition()==original,"P%d restore replaces startup ammunition with exact saved stores"%worker.player_id)
	var invalid:=weapon.capture_ammunition()
	invalid.open_pack=20
	check(not WorkerWeapon.valid_ammunition(invalid),"forged standard remainder above nineteen rejected")
	invalid=truck.vehicle_data()
	invalid.open_pack=40
	check(not CampaignState.valid_vehicle(invalid),"forged vehicle remainder above thirty-nine rejected")
	game.network.active=true
	game.network.is_host=false
	var ammo_before:=weapon.capture_ammunition()
	player.inventory={"ammo":1}
	check(not weapon.start_reload() and weapon.refill_from_inventory()==0 and weapon.capture_ammunition()==ammo_before,"replica cannot reload or unpack personal ammunition")
	var stock_before: int=source.amount
	player.position=source.position
	source.interact(player,2)
	check(source.amount==stock_before and player.inventory=={"ammo":1},"replica cannot withdraw or deposit physical supply")
	check(not flak.accept_ammo(player) and not truck.start_reload(),"replica cannot supply flak or convoy")
	game.network.active=false
	await Cleanup.free_scene(game,self)
	print("AMMUNITION SUPPLY: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
