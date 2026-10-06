extends "res://tests/combat_gore_test.gd"
## Real gate and wall colliders remain alive while their support disappears.
func deposit(effects,body,point: Vector2) -> void:
	var hit: Dictionary=effects._trace(point+Vector2(0,-14),point+Vector2(0,14))
	check(not hit.is_empty() and hit.collider==body,"Deposit probe finds the actual intended collider")
	if not hit.is_empty(): effects._add_stain(hit,{"material":"flesh","tint":Color("963d35"),"size":2})

func falling_part(effects,point: Vector2) -> void:
	var event:={"material":"flesh","point":point,"direction":Vector2.DOWN,"strength":1.0,"part":2,"joint":point+Vector2(-6,-7),"tip":point+Vector2(8,7),"character":"infantry","front":true,"facing":1.0,"player_id":0}
	effects.present(event)
	effects.particles.clear()
	var part: Dictionary=effects.parts[-1]
	part.velocity=Vector2(0,40)
	part.spin=0.0
	part.bounces=1
	for index in 75:
		effects._physics_process(1.0/60.0)
		if part.stopped: break
	check(part.stopped,"Native part settles through a real swept collision")

func run():
	arena=GoreArena.new()
	root.add_child(arena)
	arena.combat_gore=Gore.new()
	arena.combat_gore.game=arena
	arena.add_child(arena.combat_gore)
	var effects=arena.combat_gore
	effects.set_physics_process(false)
	var floor_body=blocker(Rect2(0,430,1400,35))
	var gate=preload("res://scripts/perimeter_site.gd").new()
	gate.game=arena
	gate.role="fence"
	gate.tier=1
	gate.hp=100
	gate.max_hp=100
	gate.position=Vector2(500,430)
	arena.add_child(gate)
	gate.set_physics_process(false)
	var wall=preload("res://scenes/wall.tscn").instantiate()
	wall.game=arena
	wall.initial_state=4
	wall.position=Vector2(700,430)
	arena.add_child(wall)
	wall.set_physics_process(false)
	await frames(3)
	deposit(effects,gate,Vector2(500,366))
	deposit(effects,floor_body,Vector2(300,430))
	check(effects.stains.size()==2,"Closed gate and static floor both retain supported stains")
	falling_part(effects,Vector2(500,310))
	var gate_part: Dictionary=effects.parts[-1]
	var gate_height: float=gate_part.point.y
	gate.gate_amount=.2
	effects._physics_process(.016)
	check(is_instance_valid(gate) and gate.is_blocking() and effects.stains.size()==1,"First sliding-panel motion removes its stain even before collider opens")
	gate.gate_amount=1.0
	gate.sync_replica()
	await frames(2)
	effects._physics_process(.1)
	check(not gate_part.stopped and float(gate_part.point.y)>gate_height,"Part resumes gravity when the live gate opens beneath it")
	check(effects.stains[0].support.get_ref()==floor_body,"Unchanged static floor retains its stain without extra raycasts")
	effects.clear()
	var top: float=wall.global_position.y-72
	var wall_hit: Dictionary=effects._trace(Vector2(700,300),Vector2(700,425))
	check(not wall_hit.is_empty() and wall_hit.collider==wall,"Destroyed-wall fixture has a real supporting top surface")
	if not wall_hit.is_empty(): top=wall_hit.position.y
	deposit(effects,wall,Vector2(700,top))
	falling_part(effects,Vector2(700,top-55))
	var wall_part: Dictionary=effects.parts[-1]
	var wall_height: float=wall_part.point.y
	wall.take_damage(9999)
	await frames(2)
	effects._physics_process(.1)
	check(is_instance_valid(wall) and not wall.is_blocking() and effects.stains.is_empty(),"Destroyed but persistent wall no longer supports a floating stain")
	check(not wall_part.stopped and float(wall_part.point.y)>wall_height,"Part falls from a destroyed wall while its build-site node stays alive")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(arena,self),"Support regression cleans up all retained weak references")
	print("GORE SUPPORT: ",checks-failures," passed / ",failures," failed")
	quit(1 if failures else 0)
