extends StaticBody2D
## Receiver damage uses the existing hostile-target layer. The chassis below it
## remains ordinary solid cover for both sides; the receiver is not a new wall.
var site: Node2D
func _ready() -> void:
	collision_mask=0
	collision_layer=0
	var collider:=CollisionShape2D.new()
	var shape:=RectangleShape2D.new()
	shape.size=Vector2(27,20)
	collider.shape=shape
	collider.position=Vector2(2,-9)
	add_child(collider)
func take_damage(amount: float) -> void:
	if is_instance_valid(site): site.take_damage(amount)
func impact_material() -> String:
	return "metal"
func impact_sound() -> String:
	return "impact_metal"
