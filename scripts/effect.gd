extends "res://scripts/impact_burst.gd"
## Compatibility adapter for quiet pickup/build/mining puffs through game.fx().
var color: Color = Art.AMBER
var count := 8

func _ready() -> void:
	surface_material = "utility"
	tint_override = color
	count_override = clampi(count, 0, 16)
	direction = Vector2.UP
	super._ready()
