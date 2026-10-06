extends RefCounted
## Crew can walk on the service plane through defensive hulls. A body falling
## inside one settles onto its nearest clear flank, using real horizontal
## movement on the same floor. This never bypasses earth, gaps or medical LOS.
const MAX_DISTANCE := 48.0
const SPEED := 90.0
var destination := Vector2.INF
var checked := false

func begin(worker: CharacterBody2D) -> void:
	destination=Vector2.INF
	checked=false
	_choose_when_grounded(worker)

func reset() -> void:
	destination=Vector2.INF
	checked=true

func velocity_x(worker: CharacterBody2D, delta: float, ordinary_knockback: float) -> float:
	_choose_when_grounded(worker)
	if destination==Vector2.INF: return ordinary_knockback
	var remaining:=destination.x-worker.global_position.x
	if absf(remaining)<.5 or absf(destination.y-worker.global_position.y)>4:
		destination=Vector2.INF
		return 0.0
	var next:=worker.global_position+Vector2(clampf(remaining,-SPEED*delta,SPEED*delta),0)
	if not _supported(worker,next) or not _terrain_clear(worker,worker.global_position,next):
		destination=Vector2.INF
		return 0.0
	return clampf(remaining/maxf(delta,.001),-SPEED,SPEED)

func _choose_when_grounded(worker: CharacterBody2D) -> void:
	if checked or not _supported(worker,worker.global_position): return
	checked=true
	if not _inside_defense(worker): return
	var origin:=worker.global_position
	for distance in range(2,int(MAX_DISTANCE)+1,2):
		for direction in [-1.0,1.0]:
			var point:=origin+Vector2(direction*distance,0)
			if _free_hull(worker,point) and _supported_path(worker,origin,point) and _terrain_clear(worker,origin,point):
				destination=point
				worker.knockback=0.0
				return

func _inside_defense(worker: CharacterBody2D) -> bool:
	var query:=PhysicsPointQueryParameters2D.new()
	query.position=worker.global_position-Vector2(0,18)
	query.collision_mask=2
	for hit in worker.get_world_2d().direct_space_state.intersect_point(query):
		var body=hit.collider
		if body.is_in_group("walls") or body.is_in_group("anti_air") or body.is_in_group("field_defenses") or body.is_in_group("dome_segments"):
			return true
	return false

func _shape_query(worker: CharacterBody2D,point: Vector2,mask: int) -> PhysicsShapeQueryParameters2D:
	var collider: CollisionShape2D=worker.get_node("CollisionShape2D")
	var query:=PhysicsShapeQueryParameters2D.new()
	query.shape=collider.shape
	query.transform=collider.global_transform
	query.transform.origin+=point-worker.global_position-Vector2(0,.8)
	query.collision_mask=mask
	query.exclude=[worker.get_rid()]
	return query

func _free_hull(worker: CharacterBody2D,point: Vector2) -> bool:
	return worker.get_world_2d().direct_space_state.intersect_shape(_shape_query(worker,point,2),1).is_empty()

func _terrain_clear(worker: CharacterBody2D,from: Vector2,to: Vector2) -> bool:
	var space:=worker.get_world_2d().direct_space_state
	var query:=_shape_query(worker,from,1)
	if not space.intersect_shape(query,1).is_empty(): return false
	query.motion=to-from
	var fractions:=space.cast_motion(query)
	return fractions.size()==2 and fractions[0]>=.9999

func _supported(worker: CharacterBody2D,point: Vector2) -> bool:
	for offset in [-8.0,0.0,8.0]:
		var ray:=PhysicsRayQueryParameters2D.create(point+Vector2(offset,-4),point+Vector2(offset,7),1)
		var hit:=worker.get_world_2d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y>-.5 or absf(hit.position.y-point.y)>3: return false
	return true

func _supported_path(worker: CharacterBody2D,from: Vector2,to: Vector2) -> bool:
	var count:=maxi(1,ceili(from.distance_to(to)/5.0))
	for i in count+1:
		if not _supported(worker,from.lerp(to,float(i)/count)): return false
	return true
