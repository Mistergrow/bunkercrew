class_name FieldDefense
extends StaticBody2D
## Small field devices share real arena collision checks and credited damage.
## Sentry kits construct the existing, manually occupied gun with an empty magazine.

class GroundGun extends RoofTurret:
	func display_name(uppercase: bool=false) -> String:
		return LocaleText.text("FELDGESCHÜTZ" if uppercase else "Feldgeschütz")

const SPECS := {
	"jaw_trap":{"damage":70.0, "radius":31.0, "charges":3, "rearm":2.1, "slow":1.8},
	"blast_trap":{"damage":240.0, "radius":92.0, "charges":1, "rearm":0.0, "slow":0.0},
}
var game: Node
var builder: Node2D
var kind := "jaw_trap"
var hp := 180.0
var max_hp := 180.0
var charges := 0
var arming := 1.0
var cooldown := 0.0
var animation := 0.0
var age := 0.0
var spent := false
var victims: Dictionary = {}
var turret: RoofTurret

func _ready() -> void:
	add_to_group("field_defenses")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 5
	collision_layer = 0
	collision_mask = 0
	if kind == "sentry_kit":
		add_to_group("walls")
		collision_layer = 2
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(54,17)
		shape.shape = box
		shape.position.y = -8.5
		add_child(shape)
		turret = GroundGun.new()
		turret.game = game
		turret.ammo = 0
		turret.reserve = 0
		turret.aim_angle = -0.08
		add_child(turret)
	else:
		charges = int(SPECS.get(kind,SPECS.jaw_trap).charges)
	queue_redraw()

func footprint_width() -> float:
	return 90.0 if kind == "sentry_kit" else 46.0

func is_blocking() -> bool:
	return kind == "sentry_kit" and hp > 0.0 and not spent

func attack_point() -> Vector2:
	return global_position-Vector2(0,9)

func take_damage(amount: float) -> void:
	if kind != "sentry_kit" or spent or not is_finite(amount) or amount <= 0:
		return
	hp = maxf(0.0,hp-amount)
	animation = 0.25
	if is_instance_valid(game) and game.has_method("impact") and int(get_meta("impact_contact_frame",-1))!=Engine.get_physics_frames():
		game.impact(global_position-Vector2(0,14),"metal",Vector2.LEFT,0.8)
	if hp <= 0:
		spent = true
		collision_layer = 0
		remove_from_group("walls")
		if is_instance_valid(turret):
			turret.exit()
			turret.queue_free()
		if is_instance_valid(game) and game.has_method("impact"):
			game.impact(global_position-Vector2(0,21),"explosion",Vector2.UP,1.0)
		queue_free()
	queue_redraw()

func _physics_process(delta: float) -> void:
	age += delta
	animation = maxf(0.0,animation-delta)
	arming = maxf(0.0,arming-delta)
	cooldown = maxf(0.0,cooldown-delta)
	if kind == "sentry_kit":
		queue_redraw()
		return
	if spent:
		if animation <= 0.0:
			queue_free()
		queue_redraw()
		return
	if arming <= 0.0 and cooldown <= 0.0:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if _can_trigger(enemy):
				trigger(enemy)
				break
	queue_redraw()

func _can_trigger(enemy: Node2D) -> bool:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or ("dead" in enemy and enemy.dead):
		return false
	if victims.has(enemy.get_instance_id()):
		return false
	if absf(enemy.global_position.y-global_position.y)>32 or absf(enemy.global_position.x-global_position.x)>float(SPECS[kind].radius if kind=="jaw_trap" else 27.0):
		return false
	return _visible_enemy(enemy)

func _visible_enemy(enemy: Node2D) -> bool:
	var destination := enemy.global_position-Vector2(0,18)
	var query := PhysicsRayQueryParameters2D.create(global_position-Vector2(0,12),destination,1|2)
	query.hit_from_inside = true
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func _damage(enemy: Node2D, amount: float) -> void:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
		return
	if is_instance_valid(game) and game.has_method("combat_hit"):
		game.combat_hit(enemy,amount,builder)
	else:
		enemy.take_damage(amount)

func trigger(enemy: Node2D) -> bool:
	if spent or kind == "sentry_kit" or arming > 0.0 or cooldown > 0.0 or charges <= 0 or not _can_trigger(enemy):
		return false
	charges -= 1
	cooldown = SPECS[kind].rearm
	animation = 0.72
	if kind == "blast_trap":
		for target in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(target) or target.is_queued_for_deletion() or ("dead" in target and target.dead):
				continue
			if target.global_position.distance_to(global_position) <= float(SPECS[kind].radius) and _visible_enemy(target):
				_damage(target,float(SPECS[kind].damage))
		if is_instance_valid(game):
			game.impact(global_position-Vector2(0,10),"explosion",Vector2.UP,1.6)
			preload("res://scripts/spatial_sound.gd").emit(game,"explosion",global_position)
	else:
		victims[enemy.get_instance_id()] = true
		_damage(enemy,float(SPECS[kind].damage))
		if is_instance_valid(enemy) and "stagger" in enemy:
			enemy.stagger = maxf(enemy.stagger,float(SPECS[kind].slow))
		if is_instance_valid(game):
			game.impact(global_position-Vector2(0,10),"metal",Vector2.UP,1.0)
			preload("res://scripts/spatial_sound.gd").emit(game,"impact_metal",global_position)
	spent = charges <= 0
	queue_redraw()
	return true

func _draw() -> void:
	if kind == "sentry_kit":
		draw_rect(Rect2(-39,-7,78,8),Color("272f2d"))
		for i in 6:
			draw_line(Vector2(-35+i*13,-6),Vector2(-29+i*13,-1),Color("8d835b"),3)
		if hp < max_hp:
			UiArt.bar(self,Rect2(-30,-87,60,4),hp/max_hp,UiArt.AMBER)
		return
	draw_rect(Rect2(-27,-1,54,4),Color(0,0,0,0.4))
	if kind == "jaw_trap":
		_draw_jaw()
	else:
		_draw_mine()
	if not spent:
		var lamp := Color("bd5445") if arming > 0 else Color("b6c487")
		if cooldown>0:
			lamp = Color("d3a05d")
		draw_rect(Rect2(-2,-9,4,3),lamp)
		for i in charges:
			draw_rect(Rect2(-8+i*6,-4,3,2),Color("d4b878"))
		if arming>0:
			UiArt.bar(self,Rect2(-20,-34,40,3),1.0-arming,UiArt.AMBER)

func _draw_jaw() -> void:
	draw_rect(Rect2(-24,-6,48,6),Color("222f31"))
	draw_rect(Rect2(-21,-6,42,2),Color("92988b"))
	var shut := clampf(animation/0.4,0.0,1.0)
	for side in [-1.0,1.0]:
		var hinge := Vector2(side*19,-5)
		var tip := Vector2(side*(21.0-shut*16.0),-14.0-shut*15.0)
		draw_line(hinge,tip,Color("182526"),7)
		draw_line(hinge,tip,Color("a8ada0") if not spent else Color("626d67"),4)
		for i in 3:
			var point := hinge.lerp(tip,float(i+1)/4.0)
			draw_line(point,point+Vector2(-side*5,-2),Color("c6cab9"),2)
		draw_rect(Rect2(hinge-Vector2(3,2),Vector2(6,4)),Color("776f51"))
	if spent:
		draw_line(Vector2(-15,-3),Vector2(15,-15),Color("3c4540"),2)

func _draw_mine() -> void:
	if spent:
		draw_rect(Rect2(-20,-2,40,2),Color("1c2628"))
		return
	draw_rect(Rect2(-22,-11,44,11),Color("152024"))
	draw_rect(Rect2(-19,-10,38,8),Color("535a43"))
	draw_rect(Rect2(-15,-14,30,4),Color("7c8265"))
	draw_rect(Rect2(-11,-14,22,2),Color("a3a68a"))
	for x in [-16,13]:
		draw_rect(Rect2(x,-8,3,4),Color("c29b59"))
	draw_line(Vector2(5,-14),Vector2(13,-21),Color("566867"),2)
	draw_rect(Rect2(11,-24,4,4),Color("b25543"))
