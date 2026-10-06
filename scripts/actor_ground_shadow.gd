extends Node2D
## One small contact shadow per active worker, projected onto its actual physics
## world. Three downward rays per physics tick; draw never queries or simulates.
const MAX_DROP:=320.0
const MAX_HEIGHT:=180.0
const BASE_WIDTH:=34.0
const COLLISION_MASK:=1
var worker: CharacterBody2D
var has_support:=false
var ground_point:=Vector2.ZERO
var surface_normal:=Vector2.UP
var height:=0.0
var opacity:=0.0
var left_extent:=0.0
var right_extent:=0.0
var rays_last_tick:=0
var query_ticks:=0
var _last_frame:=-1

func _ready() -> void:
	set_as_top_level(true)
	z_as_relative=false
	process_mode=Node.PROCESS_MODE_PAUSABLE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	hide()

func _eligible() -> bool:
	if not is_instance_valid(worker) or worker.is_queued_for_deletion() or not worker.is_inside_tree() or not worker.is_visible_in_tree(): return false
	var parent:=get_parent() as CanvasItem
	if parent!=null and not parent.is_visible_in_tree(): return false
	if not "game" in worker or not is_instance_valid(worker.game): return false
	var world: Node=worker.game
	if world.is_queued_for_deletion() or not "started" in world or not bool(world.started) or not "players" in world or worker not in world.players: return false
	if is_instance_valid(worker.get("mounted_turret")): return false
	return get_world_2d()==worker.get_world_2d() and worker.global_position.is_finite()

func _clear() -> void:
	has_support=false
	opacity=0.0
	left_extent=0.0
	right_extent=0.0
	hide()

func _physics_process(_delta: float) -> void:
	# The child stays cosmetic on replicas even when actor simulation is frozen.
	# Inspector/redraw/extra render frames cannot multiply physics queries.
	if get_tree().paused: return
	var frame:=Engine.get_physics_frames()
	if _last_frame==frame: return
	_last_frame=frame
	rays_last_tick=0
	if not _eligible():
		_clear()
		return
	query_ticks+=1
	var feet:=worker.global_position
	var center:=_trace(feet)
	if center.is_empty():
		_clear()
		return
	var normal: Vector2=center.normal
	var drop:=maxf(0,float(center.position.y)-feet.y)
	if drop>MAX_HEIGHT or normal.dot(Vector2.UP)<cos(worker.floor_max_angle)-.025:
		_clear()
		return
	ground_point=center.position
	surface_normal=normal
	height=drop
	var half:=lerpf(BASE_WIDTH*.5,10.0,clampf(drop/120.0,0,1))
	var tangent:=Vector2(-normal.y,normal.x).normalized()
	var side_left:=_trace(feet-Vector2(half,0))
	var side_right:=_trace(feet+Vector2(half,0))
	var same_left:=_same_plane(side_left,center)
	var same_right:=_same_plane(side_right,center)
	var span:=_face_span(center,tangent)
	left_extent=-half if same_left else maxf(-half,span.x)
	right_extent=half if same_right else minf(half,span.y)
	if right_extent-left_extent<=.5:
		_clear()
		return
	opacity=lerpf(.24,.06,clampf(drop/MAX_HEIGHT,0,1))
	global_position=ground_point
	global_rotation=tangent.angle()
	global_scale=Vector2.ONE
	z_index=_worker_z()-1
	has_support=true
	show()
	queue_redraw()

func _trace(feet: Vector2) -> Dictionary:
	rays_last_tick+=1
	var query:=PhysicsRayQueryParameters2D.create(feet-Vector2(0,4),feet+Vector2(0,MAX_DROP),COLLISION_MASK,[worker.get_rid()])
	query.collide_with_areas=false
	query.collide_with_bodies=true
	return worker.get_world_2d().direct_space_state.intersect_ray(query)

func _same_plane(hit: Dictionary,center: Dictionary) -> bool:
	if hit.is_empty(): return false
	var normal: Vector2=center.normal
	var other_normal: Vector2=hit.normal
	var point: Vector2=hit.position
	return other_normal.dot(normal)>.98 and absf((point-Vector2(center.position)).dot(normal))<1.0

func _face_span(hit: Dictionary,tangent: Vector2) -> Vector2:
	# Exact shape edges prevent a shadow from hanging over a roof/shaft edge.
	# Adjacent coplanar tiles may extend the span through their verified rays.
	var body:=hit.collider as CollisionObject2D
	if not is_instance_valid(body): return Vector2.ZERO
	var owner_id:=body.shape_find_owner(int(hit.shape))
	var shape_node:=body.shape_owner_get_owner(owner_id) as Node2D
	if not is_instance_valid(shape_node): return Vector2.ZERO
	var vertices:=PackedVector2Array()
	var paired:=false
	if shape_node is CollisionShape2D:
		var shape: Shape2D=shape_node.shape
		if shape is RectangleShape2D:
			var half: Vector2=shape.size*.5
			vertices=PackedVector2Array([Vector2(-half.x,-half.y),Vector2(half.x,-half.y),Vector2(half.x,half.y),Vector2(-half.x,half.y)])
		elif shape is ConvexPolygonShape2D:
			vertices=shape.points
		elif shape is ConcavePolygonShape2D:
			vertices=shape.segments
			paired=true
		elif shape is SegmentShape2D:
			vertices=PackedVector2Array([shape.a,shape.b])
			paired=true
	elif shape_node is CollisionPolygon2D:
		vertices=shape_node.polygon
	# Curved/custom surfaces still use the three bounded actual support rays;
	# unknown edges stop at the center instead of inventing a terrain plane.
	var point: Vector2=hit.position
	var normal: Vector2=hit.normal
	for index in vertices.size():
		if paired and index%2!=0: continue
		var next:=index+1 if paired else (index+1)%vertices.size()
		if next>=vertices.size(): continue
		var a: Vector2=shape_node.global_transform*vertices[index]
		var b: Vector2=shape_node.global_transform*vertices[next]
		if a.distance_squared_to(b)<.01: continue
		var edge_normal: Vector2=(b-a).normalized().orthogonal()
		if absf(edge_normal.dot(normal))<.98: continue
		if Geometry2D.get_closest_point_to_segment(point,a,b).distance_to(point)>.75: continue
		return Vector2(minf((a-point).dot(tangent),(b-point).dot(tangent)),maxf((a-point).dot(tangent),(b-point).dot(tangent)))
	return Vector2.ZERO

func _worker_z() -> int:
	var result:=0
	var item:=worker as CanvasItem
	while is_instance_valid(item):
		result+=item.z_index
		if not item.z_as_relative: break
		item=item.get_parent() as CanvasItem
	return clampi(result,-4095,4096)

func _draw() -> void:
	if has_support:
		draw_rect(Rect2(left_extent,-1,right_extent-left_extent,3),Color(0,0,0,opacity))
