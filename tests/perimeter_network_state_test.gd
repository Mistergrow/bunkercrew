extends SceneTree
const World=preload("res://scripts/network_world.gd")
const Wire=preload("res://scripts/combat_gore_protocol.gd")
const Cleanup=preload("res://tests/scene_cleanup.gd")
var checks:=0
var failures:=0

func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	print("PERIMETER STATE %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)

func scene():
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(2,{"environment":"sector07","build_type":"workshop","position":"center"})
	game.rounds.set_process(false)
	game.medic.set_physics_process(false)
	for player in game.players: player.set_physics_process(false)
	for site in game.perimeter.sites: site.set_physics_process(false)
	return game

func frames(count:=2):
	for index in count:
		await process_frame
		await physics_frame

func event(point: Vector2) -> Dictionary:
	return {"serial":1,"actor":"player:2","data":{"material":"flesh","point":point,"direction":Vector2.RIGHT,"strength":1.0,"part":2,"joint":point,"tip":point+Vector2(9,8),"character":"branko","front":true,"facing":1.0,"player_id":2}}

func run():
	var host=scene()
	var authority=World.new()
	authority.bind(host)
	check(host.perimeter.sites.size()==6,"Central bunker has one fence and two distinct sentries on both fronts")
	var snapshot: Dictionary=authority.capture()
	check(authority._validate(snapshot),"Starter fencing and unbuilt sentries are valid persistent entities: "+authority.last_error)
	var p=host.players[0]
	var fence=host.perimeter.sites.filter(func(site):return site.role=="fence" and site.side==1)[0]
	fence.take_damage(10000)
	p.position=fence.position-Vector2(45,0)
	p.inventory={"steel":2}
	for index in 30: fence.interact(p,.2)
	check(fence.tier==1 and p.inventory.get("steel",0)==0,"Real material transfer constructs a paid gate before capture")
	var gun=host.perimeter.sites.filter(func(site):return site.role=="ground" and site.side==1)[0]
	host.rounds.wave=16
	host.upgrades.owned={"bunker_workshop":true,"bunker_armor":true,"perimeter_automation":true}
	p.position=gun.position-Vector2(35,0)
	p.inventory={"steel":2,"concrete":1}
	for index in 45: gun.interact(p,.2)
	p.inventory={"ammo":1}
	for index in 6: gun.interact(p,.2)
	check(gun.tier==1 and gun.ammo==20 and p.inventory.get("ammo",0)==0,"Automatic gun starts empty and consumes one real crate for20 rounds")
	gun.ammo=17
	gun.shot_serial=3
	gun.burst_left=2
	gun.cooldown=.12
	gun.aim_angle=-.21
	fence.gate_open=true
	fence.gate_amount=1.0
	fence.sync_replica()
	p.gore_mask=4
	p.hp=0
	p.medical.incapacitate()
	var unfinished=host.perimeter.sites.filter(func(site):return site.role=="ground" and site.side==1 and site!=gun)[0]
	p.hp=p.max_hp
	p.medical.state="healthy"
	p.position=unfinished.position
	p.inventory={"steel":1}
	unfinished.interact(p,.2)
	check(unfinished.transfer.has("1"),"Partial deposit tracks progress with a stable player ID")
	p.hp=0
	p.medical.incapacitate()
	snapshot=authority.capture()
	check(authority._validate(snapshot),"Paid gate, gun, medical KO and limb state validate: "+authority.last_error)
	await Cleanup.free_scene(host,self)
	var guest=scene()
	var replica=World.new()
	replica.bind(guest)
	guest.network.world=replica
	check(replica.apply(snapshot),"Guest applies all static defense state: "+replica.last_error)
	if not replica.last_error.is_empty():
		await Cleanup.free_scene(guest,self)
		quit(1)
		return
	var remote=guest.perimeter.sites.filter(func(site):return site.role=="ground" and site.side==1)[0]
	check(remote.tier==1 and remote.ammo==17 and remote.burst_left==2 and remote.builder_player_id==1 and is_equal_approx(remote.aim_angle,-.21),"Gun tier, ammo, ownership, remaining burst and aim replicate together")
	check(guest.perimeter.sites.filter(func(site):return site.role=="fence" and site.side==1)[0].collision_layer==0,"Open gate collision is rebuilt from the authoritative animation state")
	check(not remote.is_physics_processing() and not remote.fire(),"Replica cannot autonomously spend ammo or fire")
	check(guest.players[0].is_downed() and guest.players[0].gore_mask==4,"Recoverable player KO and limb mask survive snapshot reconstruction")
	var site_record: Dictionary=snapshot.entities.filter(func(record):return record.type=="perimeter_site" and record.state.role=="ground" and record.state.side==1)[0]
	for mutation in [{"role":"flak"},{"side":-1},{"slot_index":5},{"ammo":999},{"max_hp":999.0},{"materials":{"scrap":2}},{"transfer":{"@bad":.1}},{"gate_amount":1.0},{"shot_serial":-1},{"burst_left":3},{"cooldown":1.71}]:
		var bad:=snapshot.duplicate(true)
		var record: Dictionary=bad.entities.filter(func(item):return item.id==site_record.id)[0]
		record.state.merge(mutation,true)
		check(not replica.apply(bad) and remote.ammo==17,"Invalid site state rejected atomically: "+str(mutation.keys()))
	var bad_mask:=snapshot.duplicate(true)
	bad_mask.entities.filter(func(record):return record.id=="player:1")[0].state.gore_mask=16
	check(not replica.apply(bad_mask),"Unknown limb bits reject the snapshot")
	check(replica.apply(snapshot),"Valid snapshot still applies after hostile state rejection")
	var payload:=event(guest.players[1].global_position-Vector2(0,22))
	check(Wire.valid_event(payload),"Bounded cosmetic descriptor is accepted")
	for key in ["point","joint","tip","direction"]:
		var bad:=payload.duplicate(true)
		bad.data[key]=Vector2(INF,0)
		check(not Wire.valid_event(bad),"Nonfinite "+key+" is rejected")
	for mutation in [{"part":3},{"character":"res://rogue.gd"},{"player_id":0},{"strength":30.0},{"tip":Vector2(1000,1000)},{"material":"metal"}]:
		var bad:=payload.duplicate(true)
		bad.data.merge(mutation,true)
		check(not Wire.valid_event(bad),"Invalid cosmetic descriptor rejected: "+str(mutation.keys()))
	guest.combat_gore.set_level(0)
	guest.network._receive_gore(payload)
	check(guest.combat_gore.parts.is_empty() and guest.combat_gore.particles.is_empty(),"Off ignores another player's authoritative gore event")
	guest.combat_gore.set_level(2)
	guest.network._receive_gore(payload)
	check(guest.combat_gore.particles.is_empty(),"Replayed serial cannot redisplay after an option change")
	payload.serial=2
	payload.data.part=0
	payload.data.joint=payload.data.point
	payload.data.tip=payload.data.point
	payload.data.front=false
	guest.network._receive_gore(payload)
	var count: int=guest.combat_gore.particles.size()
	check(count>0,"A fresh accepted event creates local blood")
	guest.network._receive_gore(payload)
	check(guest.combat_gore.particles.size()==count,"Duplicate event cannot duplicate particles")
	for serial in range(3,403):
		payload.serial=serial
		guest.network._receive_gore(payload)
	check(guest.network._gore_seen.size()<=128,"Event replay memory has a fixed128-entry bound")
	var old_count: int=guest.combat_gore.particles.size()
	payload.serial=2
	guest.network._receive_gore(payload)
	check(guest.combat_gore.particles.size()==old_count,"Aged-out serials cannot replay")
	check(await Cleanup.free_scene(guest,self),"Replicated defenses release all scene resources")
	print("PERIMETER STATE: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
