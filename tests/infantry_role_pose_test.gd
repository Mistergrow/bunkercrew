extends "res://tests/ground_abilities_test.gd"
## Real infantry nodes exercise the same gun, anatomy and weather transforms as
## combat. The gallery separately checks role silhouettes at native scale.
const RoleArt := preload("res://scripts/infantry_role_art.gd")
const Gore := preload("res://scripts/combat_gore.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var units: Array[Node2D] = []

func verify(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func run() -> void:
	InputSetup.install()
	arena = Arena.new()
	root.add_child(arena)
	arena.core = CoreProbe.new()
	arena.core.position = Vector2(200,430)
	arena.add_child(arena.core)
	var gait_signatures: Array[String] = []
	for kind in RoleArt.ROLES:
		var unit=preload("res://scenes/ground_infantry.tscn").instantiate()
		unit.kind=kind
		unit.game=arena
		unit.position=Vector2(800,430)
		arena.add_child(unit)
		unit.set_physics_process(false)
		unit.infantry.set_process(false)
		units.append(unit)
		unit.target=arena.core
		var role:=RoleArt.spec(kind)
		verify(unit.kind==kind and unit.is_in_group("human_enemies"),"Every field kit is attached to its actual human combat class")
		verify(not unit.body_part.visible and not unit.legs_part.visible and unit.infantry.visible,"Mechanical anatomy stays hidden for all six roles")
		verify(unit.weapon_muzzle()==role.muzzle,"Combat muzzle uses the exact role-specific visible barrel endpoint")
		var signature:=""
		for facing in [-1.0,1.0]:
			unit.attack_direction=facing
			for stance in [0.0,1.0]:
				unit.stance=stance
				unit.moving=stance==0
				for frame in 8:
					unit.gait=frame*TAU/8.0
					unit.age=frame*.1
					unit.weapon_recoil=4.0 if frame==3 else 0.0
					arena.core.position=unit.position+Vector2(facing*320,-80+frame*20)
					unit._pose_parts()
					var art=unit.infantry
					var pose: Dictionary=art.pose
					var visible_muzzle: Vector2=art.to_global(art.gun*unit.weapon_muzzle())
					verify(visible_muzzle.distance_to(unit.weapon_part.to_global(unit.weapon_muzzle()))<.001,"Visible gun and projectile transform agree through aim, recoil, gait and mirroring")
					verify(pose.hands.size()==2 and pose.feet.size()==2,"Every role retains exactly two arms and two legs")
					for hand in 2:
						var shoulder: Vector2=Vector2(pose.shoulder)+Vector2(-3,1) if hand==0 else Vector2(pose.shoulder)+Vector2(3,2)
						verify(shoulder.distance_to(pose.hands[hand])<22.9,"Native arm renderer never clamps a role hand off its grip")
						var grip: Vector2=art.gun*Vector2(13,4) if hand==0 else art.gun*Vector2(-1,5)
						verify(Vector2(pose.hands[hand]).distance_to(grip)<.001,"Aiming gloves grip the actual stock and fore-end")
					var feet: Array[Vector2]=unit.weather_feet()
					verify(feet[0].distance_to(art.to_global(pose.feet[0]))<.001 and feet[1].distance_to(art.to_global(pose.feet[1]))<.001,"Rain and footsteps share the actual animated boots")
					var rig:=Gore._rig(unit)
					verify(Vector2(rig[1].tip).distance_to(art.to_global(pose.hands[0]))<.001 and Vector2(rig[8].tip).distance_to(feet[1])<.001,"Damage anatomy follows the same mirrored limbs")
					verify(unit.get_node("MachineHitbox").shape.size.y==float(role.standing_height if stance==0 else role.kneeling_height),"Collision silhouette follows the role's actual standing or lowered stance")
					verify(unit.weather_segments().all(func(segment):return Vector2(segment.from).is_finite() and Vector2(segment.to).is_finite()),"All kit weather contacts remain finite")
					if facing==1 and stance==0: signature+=str(pose.feet)
		verify(not gait_signatures.has(signature),"The role has its own stride, foot lift and load-bearing rhythm")
		gait_signatures.append(signature)
		unit.moving=false
		unit.stance=1
		unit.weapon_recoil=0
		unit.muzzle_flash=0
		unit.attack_count=0
		unit._pose_parts()
		var resting_hands: Array=unit.infantry.pose.hands.duplicate()
		unit.attack_count=int(role.magazine)
		var duration: float=unit.profile.cooldown
		var window:=minf(float(role.reload_time),duration*.72)
		unit.attack_clock=duration-.12-window*.5
		unit._pose_parts()
		verify(is_equal_approx(unit.infantry.reload_phase,.5),"Role reload gesture follows the actual post-burst cooldown")
		verify(unit.infantry.pose.hands!=resting_hands,"Reload visibly reaches the bolt, belt cover, magazine or cartridge pouch")
		unit.attack_clock=duration-.12-window-.02
		unit._pose_parts()
		verify(unit.infantry.reload_phase==0 and unit.infantry.pose.hands==resting_hands,"Completing the service gesture returns both hands to the gun")
		if kind=="combat_medic":
			unit.abilities.repair_flash=.35
			unit.abilities.repair_endpoint=unit.position+Vector2(55,-30)
			unit._pose_parts()
			verify(unit.infantry.treating and is_equal_approx(unit.infantry.gun.get_rotation(),.85),"Treatment lowers the light weapon and prepares a dressing")
			verify(unit.infantry.pose.hands[0]!=resting_hands[0],"Medic treatment has a separate hand-to-pack and dressing pose")
			unit.abilities.repair_flash=0
		for unused in 4: RoleArt.spec("unknown-role-"+str(unused))
	verify(RoleArt._specs.size()==6,"Visual profile cache stays bounded to the six authored roles")
	for unit in units:
		unit.die()
	var remains:=get_nodes_in_group("infantry_remains")
	verify(remains.size()==6,"Each defeated human produces exactly one bounded corpse")
	var fallen_kinds: Array[String]=[]
	for fallen in remains:
		fallen._process(.35)
		fallen_kinds.append(fallen.troop_kind)
		verify(fallen.corpse and fallen.pose.hands.size()==2 and fallen.gun.origin.is_finite(),"Role equipment and finite articulated collapse survive defeat")
	verify(fallen_kinds.size()==6 and fallen_kinds.all(func(kind):return RoleArt.ROLES.has(kind)),"All six corpses retain their original class kit")
	for fallen in remains: fallen._process(3.1)
	await process_frame
	verify(get_nodes_in_group("infantry_remains").is_empty(),"All six corpse roles expire without persistent scene clutter")
	await Cleanup.free_scene(arena,self)
	print("INFANTRY ROLE POSES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
