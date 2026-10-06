extends SceneTree
const World=preload("res://scripts/network_world.gd")
const Cleanup=preload("res://tests/scene_cleanup.gd")
class Impostor extends Node2D:
	var game: Node
	var player_id := 3
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("PERIMETER PARTY %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)
func scene() -> Node:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(4,{"environment":"sector07","build_type":"workshop","position":"center"})
	game.rounds.set_process(false)
	game.medic.set_physics_process(false)
	for player in game.players: player.set_physics_process(false)
	for site in game.perimeter.sites: site.set_physics_process(false)
	return game
func build(site: Node, player: Node) -> void:
	player.position=site.position-Vector2(35,0)
	player.inventory=site.next_spec().cost.duplicate()
	for index in 50: site.interact(player,.2)
func run() -> void:
	var host=scene()
	var third=host.players[2]
	var fourth=host.players[3]
	var fence=host.perimeter.sites.filter(func(site): return site.role=="fence" and site.side==1)[0]
	var gun=host.perimeter.sites.filter(func(site): return site.role=="ground" and site.side==1)[0]
	var empty=host.perimeter.sites.filter(func(site): return site.role=="ground" and site.side==-1)[0]
	check(host.players.size()==4 and fence.can_interact(third) and gun.can_interact(fourth),"Real P3 and P4 can interact with their own perimeter")
	var impostor:=Impostor.new()
	impostor.game=host
	host.add_child(impostor)
	check(not fence.can_interact(impostor),"Matching player ID alone cannot impersonate a crew entity")
	impostor.free()
	# Paid construction is exercised after the new round's starter mesh falls.
	fence.take_damage(10000)
	build(fence,third)
	check(fence.tier==1 and fence.builder_player_id==3 and third.carried_count()==0,"P3 pays exactly two steel and owns the completed fence")
	check(third.progression.xp==4,"P3 receives only the completed paid construction XP")
	host.rounds.wave=11
	host.upgrades.owned={"bunker_workshop":true,"bunker_armor":true,"perimeter_automation":true}
	build(gun,fourth)
	check(gun.tier==1 and gun.builder_player_id==4 and fourth.carried_count()==0,"P4 pays real steel/concrete and owns the completed sentry")
	check(fourth.progression.xp==4 and gun.ammo==0,"P4 construction earns XP and creates no free ammunition")
	fourth.inventory={"ammo":1}
	for index in 8: gun.interact(fourth,.2)
	check(gun.ammo==20 and fourth.carried_count()==0 and fourth.progression.xp==6,"P4 supply consumes one crate, grants two XP, and loads twenty rounds")
	fence.take_damage(1)
	third.inventory={"steel":1}
	third.position=fence.position
	for index in 8: fence.interact(third,.2)
	check(fence.hp==fence.max_hp and is_equal_approx(third.progression.xp,4.06),"P3 repair rewards only the actual missing HP")
	for player in [third,fourth]:
		player.position=empty.position
		player.inventory={"steel":1}
		empty.interact(player,.2)
	check(empty.transfer.has("3") and empty.transfer.has("4"),"Unfinished P3/P4 deposits retain independent transfer progress")
	var authority=World.new()
	authority.bind(host)
	var snapshot: Dictionary=authority.capture()
	check(authority._validate(snapshot),"Four-player perimeter snapshot validates: "+authority.last_error)
	check(await Cleanup.free_scene(host,self),"Host fixture closes")
	var guest=scene()
	var replica=World.new()
	replica.bind(guest)
	guest.network.world=replica
	check(replica.apply(snapshot),"Four-player guest applies paid structures and partial deposits: "+replica.last_error)
	if not replica.last_error.is_empty():
		await Cleanup.free_scene(guest,self)
		quit(1)
		return
	var remote=guest.perimeter.sites.filter(func(site): return site.role=="ground" and site.side==1)[0]
	check(remote.builder_player_id==4 and remote.ammo==20 and guest.players[3].progression.xp==6,"P4 ownership, finite ammo, and role XP reach the replica together")
	var remote_fence=guest.perimeter.sites.filter(func(site): return site.role=="fence" and site.side==1)[0]
	check(remote_fence.builder_player_id==3 and is_equal_approx(guest.players[2].progression.xp,4.06),"P3 construction and exact repair XP survive replication")
	var unfinished=guest.perimeter.sites.filter(func(site): return site.role=="ground" and site.side==-1)[0]
	check(unfinished.transfer.has("3") and unfinished.transfer.has("4"),"Replica preserves both new player transfer keys")
	var record: Dictionary=snapshot.entities.filter(func(item): return item.type=="perimeter_site" and item.state.role=="ground" and item.state.side==1)[0]
	for mutation in [{"builder_player_id":5},{"builder_player_id":4.0},{"transfer":{"5":.2}},{"transfer":{"0":.2}},{"transfer":{"03":.2}}]:
		var bad:=snapshot.duplicate(true)
		bad.entities.filter(func(item): return item.id==record.id)[0].state.merge(mutation,true)
		check(not replica.apply(bad) and remote.ammo==20,"Out-of-range or noncanonical player references reject atomically: "+str(mutation))
	check(replica.apply(snapshot),"A valid four-player snapshot still applies after hostile rejection")
	check(await Cleanup.free_scene(guest,self),"Guest fixture closes")
	print("PERIMETER PARTY: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
