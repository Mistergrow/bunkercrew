extends RefCounted
## Canonical listening A/B baseline, isolated from a live editor's bus edits.
## Install before creating any audio owner; never save ProjectSettings.
static func install(path: String) -> bool:
	var text := """[gd_resource type="AudioBusLayout" load_steps=2 format=3]

[sub_resource type="AudioEffectHardLimiter" id="Output"]
resource_name = "BunkercrewOutputCeiling"
pre_gain_db = 6.0199986
ceiling_db = -1.0

[resource]
bus/0/name = &"Master"
bus/0/volume_db = 0.0
bus/0/effect/0/effect = SubResource("Output")
bus/0/effect/0/enabled = true
bus/1/name = &"Music"
bus/1/volume_db = -9.11034656
bus/1/send = &"Master"
bus/2/name = &"SFX"
bus/2/volume_db = -6.02059991
bus/2/send = &"Master"
bus/3/name = &"Voice"
bus/3/volume_db = -14.89455
bus/3/send = &"Master"
"""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(text)
	file.close()
	var layout := ResourceLoader.load(path, "AudioBusLayout", ResourceLoader.CACHE_MODE_IGNORE) as AudioBusLayout
	if layout == null: return false
	AudioServer.set_bus_layout(layout)
	ProjectSettings.set_setting("audio/buses/default_bus_layout", path)
	return true
