extends SceneTree
const Ground=preload("res://scripts/ground_contact_effects.gd")
func _initialize():
	var checks:=0
	for width in [5.0,5.1,6.0,8.0,10.0,16.0,22.0]:
		for at in [Vector2.ZERO,Vector2(-240,430),Vector2(1680,430)]:
			var polygon:=Ground.field_polygon(at,width)
			if Geometry2D.triangulate_polygon(polygon).is_empty():
				push_error("Supported ground patch must triangulate at width%f"%width)
				quit(1)
				return
			checks+=1
	print("GROUND PATCH GEOMETRY: %d/%d checks passed"%[checks,checks])
	quit()
