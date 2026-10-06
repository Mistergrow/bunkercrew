class_name WorkerShot
extends Node2D
## Handheld rounds stop on world geometry and only damage enemy machines.

var game
var credit_worker: Node
var direction := Vector2.RIGHT
var damage := 16.0
var speed := 1100.0
var life := 0.75
var flavor := "rifle"
var remaining_hits := 1
var stagger_duration := 0.0
var age := 0.0
var excluded: Array[RID] = []
var _scenery_hits: Dictionary = {}

var distance_travelled := 0.0

func _physics_process(delta: float) -> void:
	age += delta
	var destination := global_position+direction*speed*minf(delta,life)
	var start := global_position
	for crossing in 4:
		var query := PhysicsRayQueryParameters2D.create(start,destination,1|2|4)
		query.exclude = excluded
		query.hit_from_inside = true
		var hit := get_world_2d().direct_space_state.intersect_ray(query)
		preload("res://scripts/scenery_damage.gd").projectile_path(game,start,hit.position if not hit.is_empty() else destination,damage,flavor,_scenery_hits,true)
		if hit.is_empty():
			distance_travelled += global_position.distance_to(destination)
			global_position = destination
			break
		global_position = hit.position
		var collider: Object = hit.collider
		ImpactBurst.contact(game, collider, hit.position, hit.normal, direction, 0.65 if flavor == "shotgun" else 0.9, flavor)
		var machine: bool = collider is Node and collider.is_in_group("enemies") and collider.has_method("take_damage")
		if machine:
			if is_instance_valid(game) and game.has_method("combat_hit"):
				game.combat_hit(collider,damage,credit_worker)
			else:
				collider.take_damage(damage)
			if "stagger" in collider:
				collider.stagger = maxf(collider.stagger, maxf(stagger_duration, 0.60 if flavor == "arcgun" else 0.0))
			if collider is CollisionObject2D:
				excluded.append(collider.get_rid())
			remaining_hits -= 1
		if not machine or remaining_hits <= 0:
			queue_free()
			return
		start = hit.position+direction*2
		if start.distance_to(destination) <= 2:
			break
	life -= delta
	if life <= 0:
		queue_free()
	queue_redraw()

func arc_paths(quiet: bool = false) -> Array[PackedVector2Array]:
	var paths: Array[PackedVector2Array] = []
	var length := minf(31.0,distance_travelled)
	if length < .5: return paths
	var forward := direction.normalized() if direction.length_squared() > .001 else Vector2.RIGHT
	var side := forward.orthogonal()
	var tail := -forward*length
	var tick := floori(age*12.0)
	var width := minf(1.0,length/15.0)
	var main := PackedVector2Array([tail.round()])
	# The sampled clock follows projectile age, so pausing also freezes the
	# electrical shape. Integer corners match the furnace electrode arcs.
	for segment in range(1,5):
		var hash_value := posmod(tick*137+segment*71,997)
		var point := tail.lerp(Vector2.ZERO,segment/5.0)+side*float(hash_value%7-3)*width
		main.append(point.round())
	main.append(Vector2.ZERO)
	paths.append(main)
	if not quiet and length >= 12.0:
		var sign_side := -1.0 if tick%2 == 0 else 1.0
		var start := main[2]
		var bend := start+forward*3.0+side*sign_side*3.0
		var end := start+forward*6.0+side*sign_side*5.0
		paths.append(PackedVector2Array([start,bend.round(),end.round()]))
	return paths

func _draw() -> void:
	if flavor == "arcgun":
		if distance_travelled < .5: return
		var quiet := WeaponEffectArt.reduced(game)
		for path in arc_paths(quiet):
			if not quiet:
				draw_polyline(path,Color(.49,.65,.67,.12),5,false)
			draw_polyline(path,Color("304c4e"),3,false)
			draw_polyline(path,Color("e5f2d7"),1,false)
		draw_rect(Rect2(-1,-1,2,2),Color("f6f3d6"))
	else:
		var length := 14.0 if flavor == "shotgun" else 23.0
		WeaponEffectArt.tracer(self,direction,minf(distance_travelled,length),WeaponEffectArt.reduced(game))
