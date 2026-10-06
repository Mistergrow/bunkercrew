extends ActorWetness
## Reuse rain, tire splashes and terrain dust without synthetic walking sounds.
func _install_materials() -> void:
	_apply_material(actor.visual,true,-10000.0,false,.5)
	_apply_material(actor.weapon_visual,true)

func feet() -> Array[Vector2]:
	var result: Array[Vector2]=[]
	for wheel_x in [-65.0,-15.0,56.0]:
		result.append(actor.to_global(Vector2(wheel_x*actor.facing,-3)))
	return result
