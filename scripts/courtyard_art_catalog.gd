extends RefCounted
## The generated atlas is kept unchanged. These measured alpha bounds preserve
## each source module's pixel spacing and flat contact baseline.
const ATLAS = preload("res://assets/courtyard/modules_v1.png")
const SERVICE_ATLAS = preload("res://assets/perimeter/components_v3.png")
const SERVICE_CASE = Rect2(1232,195,282,198)
const FENCE = Rect2(20,129,590,281)
const DAMAGED_FENCE = Rect2(648,129,590,281)
const FENCE_FIELD = Rect2(98,159,446,238)
const FENCE_POST = Rect2(543,129,67,281)
const PAVING = Rect2(35,592,570,93)
const RUBBLE = Rect2(639,546,591,140)
const LAMP = Rect2(240,754,151,424)
const BOLLARDS = Rect2(648,958,558,220)
const FENCE_HEIGHT := 62.0
const PAVING_HEIGHT := 9.0
const LAMP_HEIGHT := 82.0
const BOLLARD_HEIGHT := 17.0

static func habitat_tint(environment_id: String) -> Color:
	match environment_id:
		"frozen_rail_yard": return Color("c6d0d2")
		"mountain_pass", "storm_dam": return Color("afbcca")
		"overgrown_steelworks", "flooded_power_station": return Color("bbc0a3")
		"iron_canyon", "basalt_quarry": return Color("cbbb9f")
	return Color("c1c3b5")

static func module_size(region: Rect2, height: float) -> Vector2:
	return Vector2(region.size.x / region.size.y * height,height)
