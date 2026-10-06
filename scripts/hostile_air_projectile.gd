class_name HostileAirProjectile
extends Node2D
## Swept physical ordnance: the first roof, pane, wall or worker always stops it.
## Heavy shells have a visual blast, not damage leaking through nearby cover.

const MAX_ACTIVE := 42
const MAX_LIFETIME := 6.0
var game: Node
var velocity := Vector2.LEFT * 300.0
var gravity := 0.0
var damage := 9.0
var flavor := "dart"
var lifetime := MAX_LIFETIME
var age := 0.0
var trail: Array[Vector2] = []
var spent := false
var _scenery_hits: Dictionary = {}

func _ready() -> void:
	add_to_group("air_projectiles")
	z_index = 9
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rotation = velocity.angle()

func _physics_process(delta: float) -> void:
	if spent or not _authoritative() or not is_finite(delta) or delta<=0.0:
		return
	age += delta
	lifetime -= delta
	var displacement := velocity * delta + Vector2(0,gravity * delta * delta * 0.5)
	velocity.y += gravity * delta
	var destination := global_position + displacement
	var ray := PhysicsRayQueryParameters2D.create(global_position,destination,1|2|8)
	ray.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(ray)
	preload("res://scripts/scenery_damage.gd").projectile_path(game,global_position,hit.position if not hit.is_empty() else destination,damage,flavor,_scenery_hits,true)
	if not hit.is_empty():
		global_position = hit.position
		_impact(hit.collider,hit.position,hit.normal)
		return
	trail.push_front(global_position)
	if trail.size()>8:
		trail.pop_back()
	global_position = destination
	rotation = velocity.angle()
	var scenario := ScenarioCombat.for_game(game)
	var outside: bool = global_position.x < (scenario.arena_left-160.0 if scenario != null else -100.0) or global_position.x > (scenario.arena_right+160.0 if scenario != null else 2400.0)
	if lifetime <= 0 or global_position.y>1400 or outside:
		spent = true
		queue_free()
	queue_redraw()

func _impact(collider: Node, point: Vector2, normal: Vector2) -> void:
	if spent or not _authoritative():
		return
	spent = true
	ImpactBurst.contact(game,collider,point,normal,velocity.normalized(),clampf(damage/20.0,0.5,2.2),"arcgun" if flavor=="arc" else flavor)
	if is_instance_valid(collider) and collider.has_method("take_damage"):
		if collider.is_in_group("players"):
			collider.take_damage(damage,velocity.normalized())
		else:
			collider.take_damage(damage)
	if flavor in ["bomb","rocket","grenade"]:
		ImpactBurst.emit(game,point,"explosion",normal,0.8 if flavor=="bomb" else 1.2)
		preload("res://scripts/spatial_sound.gd").emit(game,"explosion",point)
	queue_free()

func _authoritative() -> bool:
	if not is_instance_valid(game): return true
	var session = game.get("network")
	return not is_instance_valid(session) or not bool(session.get("active")) or bool(session.get("is_host"))

func _draw() -> void:
	var tint := Color("ed9f53") if flavor!="arc" else Color("9cceeb")
	for index in range(1,trail.size()):
		var alpha := (1.0-float(index)/trail.size())*0.38
		draw_line(to_local(trail[index-1]),to_local(trail[index]),Color(tint,alpha),2.0 if flavor in ["bomb","rocket"] else 1.0)
	if flavor=="grenade":
		draw_rect(Rect2(-4,-3,9,6),Color("17201f"))
		draw_rect(Rect2(-3,-2,5,4),Color("929379"))
		draw_rect(Rect2(2,-2,2,4),Color("bc8250"))
	elif flavor in ["bomb","rocket"]:
		draw_rect(Rect2(-10,-5,20,10),Color("141e23"))
		draw_rect(Rect2(-8,-3,15,6),Color("697171"))
		draw_rect(Rect2(4,-3,4,6),Color("ed8c53"))
		draw_rect(Rect2(-8,-5,3,10),Color("8d8a70"))
		if flavor=="rocket":
			draw_colored_polygon(PackedVector2Array([Vector2(-10,-3),Vector2(-22-sin(age*50)*4,0),Vector2(-10,3)]),Color("ffd995"))
	else:
		draw_line(Vector2(-11,0),Vector2(5,0),Color(tint,0.3),5)
		draw_line(Vector2(-7,0),Vector2(4,0),tint,2)
		draw_rect(Rect2(2,-1,4,2),Color("fff2d4"))
