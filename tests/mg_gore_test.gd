extends SceneTree
## Actual RoofTurret.fire -> emitted BunkerProjectile -> swept physics contact
## -> accepted damage -> local cosmetics. No manual contact or damage calls.
const Cleanup=preload("res://tests/scene_cleanup.gd")
var game
var checks:=0
var failures:=0

func _initialize(): run.call_deferred()

func check(value: bool,label: String):
	checks+=1
	print("MG GORE ","PASS " if value else "FAIL ",label)
	if not value:
		failures+=1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func frames(count: int):
	for index in count: await physics_frame

func projectiles() -> Array:
	return game.get_children().filter(func(node):return node is BunkerProjectile and not node.is_queued_for_deletion())

func shoot(gun: RoofTurret) -> bool:
	# Cases run with other scene systems frozen; elapsed cooldown is prepared.
	gun.cooldown=0.0
	var ammo_before:=gun.ammo
	var ok:=gun.fire()
	check(ok and gun.ammo==ammo_before-1,"Real gun action spends exactly one round")
	var shots:=projectiles()
	check(shots.size()==1,"Muzzle is clear and gun creates one actual BunkerProjectile")
	if shots.is_empty(): return false
	var shot=shots[0]
	check(shot.source==gun and shot.credit_worker==gun.occupant and shot.is_physics_processing(),"Live projectile carries weapon source and real operator attribution")
	for index in 60:
		await physics_frame
		if not is_instance_valid(shot) or shot.is_queued_for_deletion(): return true
	check(false,"Projectile resolves its physical path within one second")
	return false

func run():
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(1,{"environment":"sector07","position":"left","build_type":"workshop"})
	game.dialogue.reset()
	freeze(game)
	game.combat_gore.set_level(2)
	var gun: RoofTurret=game.turret
	var worker: Worker=game.players[0]
	gun.global_position=Vector2(840,430)
	gun.aim_angle=0.0
	gun.pose_barrel()
	gun.enter(worker)
	var soldier=preload("res://scenes/ground_infantry.tscn").instantiate()
	soldier.kind="rifle_guard"
	soldier.wave=1
	soldier.position=Vector2(1120,430)
	soldier.game=game
	game.add_child(soldier)
	freeze(soldier)
	soldier._pose_parts()
	var cover=preload("res://scenes/wall.tscn").instantiate()
	cover.game=game
	cover.initial_state=4
	cover.position=Vector2(1000,430)
	game.add_child(cover)
	freeze(cover)
	game.camera.position=Vector2(1010,380)
	game.camera.zoom=Vector2.ONE
	game.camera.force_update_scroll()
	await frames(3)
	var hp_before: float=soldier.hp
	var cover_before: float=cover.hp
	var serial_before: int=game._gore_serial
	await shoot(gun)
	check(soldier.hp==hp_before and soldier.gore_mask==0,"Intervening real concrete protects the human target")
	check(cover.hp<cover_before,"Swept projectile contacts and damages the first concrete collider")
	check(game._gore_serial==serial_before and game.combat_gore.particles.is_empty() and game.combat_gore.parts.is_empty(),"Blocked MG shot creates no false human blood or dismemberment event")
	cover.queue_free()
	await frames(2)
	var kills_before: int=worker.progression.kills
	var xp_before: float=worker.progression.xp
	await shoot(gun)
	check(is_instance_valid(soldier) and soldier.hp>0 and soldier.hp<hp_before,"Uncovered real projectile removes actual human HP without killing on the first round")
	check(not game.combat_gore.particles.is_empty() and game.combat_gore.particles.all(func(bit):return bit.material=="flesh"),"Accepted physical MG hit produces the human blood family")
	check(game.combat_gore.parts.is_empty() and soldier.gore_mask==0,"Surviving target retains all limbs")
	await shoot(gun)
	check(not is_instance_valid(soldier) or soldier.is_queued_for_deletion(),"Second ordinary projectile causes an actual human defeat")
	check(game.combat_gore.parts.size()==1,"Fatal physical MG contact produces one detached native part")
	var remains:=get_nodes_in_group("infantry_remains").filter(func(body):return body.get_parent()==game)
	check(remains.size()==1 and remains[0].gore_mask>0 and remains[0].gore_mask==game.combat_gore.parts[0].part,"Actual corpse hides precisely the part emitted by the projectile contact")
	check(worker.progression.kills==kills_before+1 and worker.progression.xp>xp_before,"Damage and kill XP remain attributed once to the real mounted operator")
	check(game._gore_serial==serial_before+2,"Only the two accepted human hits enter the network cosmetic event sequence")
	check(await Cleanup.free_scene(game,self),"Full main scene and created projectile/effect nodes release cleanly")
	print("MG GORE: ",checks-failures," passed / ",failures," failed")
	quit(1 if failures else 0)
