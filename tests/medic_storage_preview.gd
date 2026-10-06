extends SceneTree
## Actual paid research installs five empty stores; all starting stocks remain.
const OUTPUT := "res://artifacts/san-logistics/"
const Storage := preload("res://scripts/medic_storage.gd")
var game: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func frames(count: int = 4) -> void:
	for tick in count: await process_frame

func _run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1440,900)
	LocaleText.set_locale("de",false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.combat_events.persistence_enabled = false
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"),true)
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.set_process(false)
	await frames()
	var baseline := {}
	for crate: Node2D in get_nodes_in_group("supplies"):
		if crate.get("game") != game: continue
		baseline[str(crate.kind)] = {"amount":crate.amount,"position":crate.global_position}
	check(baseline.size() == 5,"Actual scenario starts with its five original physical crates")
	game.upgrades.add_points(6)
	check(game.upgrades.purchase("bunker_workshop"),"Two actual technology points purchase Fertigungstechnik")
	check(game.upgrades.purchase("medic_collection"),"Four actual technology points purchase SAN-1 Bergung")
	check(game.upgrades.points == 0,"Research pays its complete shared-point cost")
	await frames(8)
	var rows: Array[Dictionary] = []
	var seen := {}
	var empty_count := 0
	for crate: Node2D in get_nodes_in_group("supplies"):
		if crate.get("game") != game or crate.is_queued_for_deletion(): continue
		seen[str(crate.kind)] = true
		var original: bool = baseline.has(str(crate.kind))
		if original:
			check(crate.amount == baseline[str(crate.kind)].amount and crate.global_position == baseline[str(crate.kind)].position,"Existing "+str(crate.kind)+" stock and location remain unchanged")
		else:
			check(crate.amount == 0,"New "+str(crate.kind)+" store is physically present and completely empty")
			empty_count += 1
			check(game.medic.navigation.support_at(crate.global_position) and game.medic.navigation.body_clear(crate.global_position),"New "+str(crate.kind)+" store has a real accessible floor")
			var ladder_clear := true
			for ladder: Rect2 in game.ladders:
				ladder_clear = ladder_clear and not ladder.grow(22).has_point(crate.global_position)
			check(ladder_clear,"New "+str(crate.kind)+" store keeps the actual ladder passage clear")
		rows.append({"kind":crate.kind,"amount":crate.amount,"new":not original,"position":[crate.global_position.x,crate.global_position.y]})
	check(rows.size() == 10 and seen.size() == 10 and empty_count == 5,"Ten material kinds comprise five original stocks plus five new empty stores")
	for material: String in Storage.MATERIALS:
		check(seen.has(material),"Runtime has a matching physical store for "+material)
	check(game.medic.is_physics_processing() and game.medic.logistics_cargo.is_empty(),"SAN-1 keeps real physics and no fabricated cargo")
	# The review camera frames the complete physical storage bay. It leaves all
	# actors at their actual simulated positions and no material is added.
	game.player_camera.set_process(false)
	game.camera.position = Vector2(470,315)
	game.camera.zoom = Vector2.ONE*1.25
	game.camera.force_update_scroll()
	await frames()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT+"storage-runtime.png") == OK,"Full actual runtime storage layout screenshot saves")
	var report := {"checks":checks,"failures":failures,"actual_main_scene":true,"actual_paid_research":true,"research_points_spent":6,"injected_materials":false,"injected_robot_motion":false,"original_stock":baseline,"storage":rows,"prepared_state":"Solo Aschewerk / Betonbastion / West; only enemy spawner held; 6 prepared tech points spent through actual research API; camera centered470,315 at1.25; normal SAN-1 physics and storage transactions remain active"}
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Storage preview releases native scene and audio cleanly")
	report.checks = checks
	report.failures = failures
	var file := FileAccess.open(OUTPUT+"storage-runtime-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("MEDIC STORAGE PREVIEW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
