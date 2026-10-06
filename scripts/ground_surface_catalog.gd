extends RefCounted
## Cosmetic deposits only; collision, traction and movement remain unchanged.
const CELL_WIDTH := 76.0
const PROFILES := {
	"sector07": {"water": 0.18, "dust": Color("918779"), "grit": Color("aca08c")},
	"ash_foundry": {"water": 0.0, "dust": Color("766f66"), "grit": Color("988b78")},
	"abandoned_harbor": {"water": 0.30, "dust": Color("77817b"), "grit": Color("a0aaa0")},
	"basalt_quarry": {"water": 0.0, "dust": Color("807d8b"), "grit": Color("aba4b1")},
	"overgrown_steelworks": {"water": 0.08, "dust": Color("83806a"), "grit": Color("a5a184")},
	"frozen_rail_yard": {"water": 0.0, "ice": 0.48, "dust": Color("a0b6bb"), "grit": Color("d5e1dd")},
	"iron_canyon": {"water": 0.0, "dust": Color("a4816b"), "grit": Color("c0a18a")},
	"flooded_power_station": {"water": 0.36, "dust": Color("737f6e"), "grit": Color("a0ab90")},
	"mountain_pass": {"water": 0.22, "dust": Color("808290"), "grit": Color("acaaba")},
}

static func profile(environment: String) -> Dictionary:
	return PROFILES.get(environment, PROFILES.sector07)

static func seed_for(environment: String, cell: int) -> int:
	var result := 194613
	for character in environment.to_utf8_buffer():
		result = posmod(result * 31 + int(character), 104729)
	return posmod(result + cell * 7919 + cell * cell * 97, 104729)

static func deposit(environment: String, cell: int) -> Dictionary:
	var spec := profile(environment)
	var seed_value := seed_for(environment, cell)
	var chance := float(seed_value % 997) / 997.0
	var frozen := environment == "frozen_rail_yard"
	if chance >= float(spec.get("ice", 0.0) if frozen else spec.get("water", 0.0)):
		return {}
	return {"kind": "ice" if frozen else "water", "seed": seed_value,
		"x": (float(cell) + 0.30 + float(seed_value % 37) / 100.0) * CELL_WIDTH,
		"width": 14.0 + float(seed_value % 12)}
