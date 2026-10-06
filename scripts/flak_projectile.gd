class_name FlakProjectile
extends Node2D
## Swept first-contact flak shell. Glass, concrete and earth remain opaque;
## ammunition never damages friendly bunker components.
var game: Node
var direction := Vector2.RIGHT
var speed := 1450.0
var damage := 46.0
var life := 1.6
var credit_worker: Node
var source: Node
var retired := false
var _scenery_hits: Dictionary = {}

var distance_travelled := 0.0

func _physics_process(delta: float) -> void:
	if retired:
		return
	var destination := global_position+direction*speed*delta
	var query := PhysicsRayQueryParameters2D.create(global_position,destination,1|2|4)
	query.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	preload("res://scripts/scenery_damage.gd").projectile_path(game,global_position,hit.position if not hit.is_empty() else destination,damage,"flak",_scenery_hits,true)
	if not hit.is_empty():
		global_position = hit.position
		impact(hit.collider,hit.position,hit.normal)
		return
	distance_travelled += global_position.distance_to(destination)
	global_position = destination
	life -= delta
	if life <= 0.0:
		retired = true
		queue_free()
	queue_redraw()

func impact(collider: Object,at: Vector2,normal: Vector2) -> void:
	if retired:
		return
	retired = true
	ImpactBurst.contact(game,collider,at,normal,direction,1.1,"flak")
	if collider is Node and collider.is_in_group("enemies") and collider.has_method("take_damage"):
		var applied := damage*(1.0 if collider.is_in_group("air_enemies") else 0.45)
		if is_instance_valid(game) and game.has_method("combat_hit"):
			game.combat_hit(collider,applied,credit_worker)
		else:
			collider.take_damage(applied)
	queue_free()

func _draw() -> void:
	WeaponEffectArt.tracer(self,direction,minf(distance_travelled,37.0),WeaponEffectArt.reduced(game),true)
