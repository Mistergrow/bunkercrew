class_name BunkerProjectile
extends Node2D

var game: Node
var direction := Vector2.RIGHT
var speed := 1350.0
var damage := float(Balance.SHOT_DAMAGE)
var life := 1.7
var trail_length := 29.0
var credit_worker: Node
var source: Node
var _scenery_hits: Dictionary = {}

var distance_travelled := 0.0

func _physics_process(delta: float) -> void:
	var destination := global_position + direction * speed * delta
	var query := PhysicsRayQueryParameters2D.create(global_position, destination, 1 | 2 | 4)
	# Vehicle mounts own a physical hull. Their rounds leave that chassis while
	# still respecting every other wall, terrain surface and enemy along the ray.
	if is_instance_valid(source) and source is CollisionObject2D:
		query.exclude = [source.get_rid()]
	query.hit_from_inside = true
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	preload("res://scripts/scenery_damage.gd").projectile_path(game,global_position,result.position if not result.is_empty() else destination,damage,"turret",_scenery_hits,true)
	if not result.is_empty():
		global_position = result.position
		var collider: Object = result.collider
		ImpactBurst.contact(game, collider, global_position, result.normal, direction, clampf(damage / 32.0, 0.5, 1.5), "turret")
		if collider is Node and collider.is_in_group("enemies") and collider.has_method("take_damage"):
			if is_instance_valid(game) and game.has_method("combat_hit"):
				game.combat_hit(collider,damage,credit_worker)
			else:
				collider.take_damage(damage)
		queue_free()
		return
	distance_travelled += global_position.distance_to(destination)
	global_position = destination
	life -= delta
	if life <= 0:
		queue_free()
	queue_redraw()

func _draw() -> void:
	WeaponEffectArt.tracer(self,direction,minf(distance_travelled,trail_length),WeaponEffectArt.reduced(game),true)
