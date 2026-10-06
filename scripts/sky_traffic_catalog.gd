extends RefCounted
## Bounded cosmetic flight population and weather colors for the thirteen sites.
const PROFILES := {
	"sector07":{"count":2,"cloud":"747282","opacity":.46,"light":"e4bb84"},
	"ash_foundry":{"count":3,"cloud":"576d86","opacity":.58,"light":"d8d6ae"},
	"abandoned_harbor":{"count":2,"cloud":"637e91","opacity":.57,"light":"c6d9d9"},
	"basalt_quarry":{"count":1,"cloud":"b0a1b7","opacity":.38,"light":"e3c597"},
	"overgrown_steelworks":{"count":1,"cloud":"9fae9c","opacity":.34,"light":"e3d5a2"},
	"frozen_rail_yard":{"count":2,"cloud":"aac1cf","opacity":.46,"light":"d9e2cf"},
	"iron_canyon":{"count":1,"cloud":"bd9d94","opacity":.35,"light":"eed4a2"},
	"flooded_power_station":{"count":2,"cloud":"8eaaa9","opacity":.50,"light":"d9e3bc"},
	"mountain_pass":{"count":2,"cloud":"747b9d","opacity":.64,"light":"c6d4db"},
	"storm_dam":{"count":2,"cloud":"8196a5","opacity":.66,"light":"cbd8cf"},
	"sulfur_refinery":{"count":1,"cloud":"aa9875","opacity":.42,"light":"e7cd90"},
	"radar_highlands":{"count":2,"cloud":"8a88a6","opacity":.59,"light":"d9d1d2"},
	"buried_megafactory":{"count":1,"cloud":"a58982","opacity":.38,"light":"e9c290"},
}

static func definition(id: String) -> Dictionary:
	return PROFILES.get(id,PROFILES.sector07)
