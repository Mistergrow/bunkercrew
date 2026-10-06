extends SceneTree
## Real scenario fixtures: cosmetic geology cannot add physical mining cells,
## disappear at the widest camera view, or lose the selected world's palette.

const STRATA := preload("res://scripts/terrain_strata.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	print("TERRAIN %s: %s" % ["PASS" if value else "FAIL", label])
	if not value:
		failures += 1
		push_error(label)

func run() -> void:
	var palettes := {}
	for entry: Dictionary in ScenarioCatalog.environments():
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game.start_scenario(1, {"environment": entry.id, "build_type": "bastion", "position": "center"})
		game.rounds.set_process(false)
		await process_frame
		var bunker: ScenarioBunker = game.scenario_bunker
		var strata := bunker.get_node_or_null("TerrainStrata") as Node2D
		check(is_instance_valid(strata), "%s contains geological backing" % entry.id)
		if is_instance_valid(strata):
			check(strata.show_behind_parent and strata.get_child_count() == 0 and strata.get_groups().is_empty(), "%s backing stays behind rooms and adds no collision or resource nodes" % entry.id)
			check(strata.environment_id == entry.id and strata.material is ShaderMaterial, "%s uses the selected biome" % entry.id)
			palettes[strata.material.get_shader_parameter("rock_tint")] = true
		check(bunker.fields.size() == 1 and bunker.fields[0].remaining_count() == 30 and bunker.excavated_rects().size() == 2, "%s keeps the real excavation boundaries and thirty starter cells" % entry.id)
		var widest := Rect2(Vector2(720, 430) - Vector2(2560, 1440) / 0.25 * 0.5, Vector2(2560, 1440) / 0.25)
		var underground := Rect2(widest.position.x, 430, widest.size.x, widest.end.y - 430)
		check(STRATA.FIELD.encloses(underground), "%s covers QHD at the widest 0.25 overview" % entry.id)
		check(await preload("res://tests/scene_cleanup.gd").free_scene(game, self), "%s cleans up" % entry.id)
	check(palettes.size() == ScenarioCatalog.environments().size(), "Each environment has its own rock palette")
	print("TERRAIN RESULT: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)
