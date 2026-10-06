extends SceneTree
## Furnace snapshots preserve scrap identity and reject impossible batches.
const Schema := preload("res://scripts/network_replication_schema.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	for entity_kind: String in ["station", "deep_station", "glass_furnace"]:
		check("input_scrap" in Schema.fields(entity_kind) and "working_scrap" in Schema.fields(entity_kind), "Every production station transmits scrap provenance")
		var furnace := {"kind":"furnace", "input_amount":2, "input_scrap":1, "working_scrap":0, "working":false}
		check(Schema.valid_state(entity_kind, furnace), "Mixed queued furnace inputs retain exactly one scrap unit")
		furnace.input_amount = 0
		furnace.input_scrap = 0
		furnace.working_scrap = 1
		furnace.working = true
		check(Schema.valid_state(entity_kind, furnace), "A paid mixed running batch retains scrap after queued inputs were consumed")
		for changes: Dictionary in [{"input_scrap":1}, {"working_scrap":3}, {"working":false}, {"working":1}, {"working_scrap":-1}, {"working_scrap":1.0}, {"input_scrap":-1}, {"input_scrap":0.0}, {"input_amount":10001}]:
			check(not Schema.valid_state(entity_kind, furnace.merged(changes, true)), "Malformed or inconsistent furnace provenance is rejected: " + str(changes))
		var missing := furnace.duplicate()
		missing.erase("working_scrap")
		check(not Schema.valid_state(entity_kind, missing), "Current snapshots cannot omit the running batch provenance")
		for recipe_kind: String in ["mixer", "glass", "alloy", "ammo_press"]:
			var recipe := {"kind":recipe_kind, "input_amount":1, "input_scrap":0, "working_scrap":0, "working":false}
			check(Schema.valid_state(entity_kind, recipe), "Other recipes retain their valid zero-scrap state")
			recipe.input_scrap = 1
			check(not Schema.valid_state(entity_kind, recipe), "Scrap cannot be forged into another recipe")
	print("STATION INPUT SCHEMA: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
