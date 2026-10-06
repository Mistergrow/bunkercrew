extends SceneTree
## Safe garage writes must preserve actual ammunition conversions and crew
## progression together with physical warehouse stock, across a real JSON read.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game: Node
var checks := 0
var failures := 0
var fixture_root := ""

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(detail)

func same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left))==JSON.parse_string(JSON.stringify(right))

func _freeze() -> void:
	paused = true
	game.rounds.running = false
	game.set_process(false)
	game.rounds.set_process(false)
	game.solo_story.set_process(false)
	game.network.set_process(false)
	game.social_bridge.set_process(false)
	for node: Node in game.find_children("*", "Node", true, false):
		node.set_physics_process(false)
		if node is ProductionStation: node.set_process(false)

func _disk(path: String) -> Dictionary:
	var saved := CampaignState.new(path, false)
	saved.persistence_enabled = true
	return saved.checkpoint() if saved.load_checkpoint() else {}

func _case(action: String) -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.campaign.save_path = fixture_root.path_join(action+".json")
	game.campaign.persistence_enabled = true
	game.start_scenario(1, {"environment":"ash_foundry", "build_type":"bastion", "position":"left"})
	_freeze()
	game.upgrades.add_points(12)
	check(game.upgrades.purchase("weapon_handling") and game.upgrades.purchase("bunker_dance"), action+": prepared mixed crew and medic research uses the real purchase path")
	game.rounds.wave = Balance.TOTAL_WAVES
	check(game.expedition.on_victory(), action+": actual victory establishes a durable safe garage")
	if action=="stop":
		check(game.expedition.handle_command("route", {"id":"harbor"}, 1), "Stop fixture uses the actual route selector")
	var worker: Worker = game.players[0]
	var weapon: WorkerWeapon = worker.get_node("WorkerWeapon")
	var ammo_supply: Supply
	for supply: Node in get_nodes_in_group("supplies"):
		if supply.game==game and supply.kind=="ammo" and not supply.is_queued_for_deletion():
			ammo_supply = supply
			break
	check(is_instance_valid(ammo_supply), action+": finite garage has a real ammunition supply")
	worker.position = ammo_supply.position
	for unused in 3: await physics_frame
	var original_stock: Dictionary = game.expedition._capture_stock()
	check(weapon.refill_from_supply(ammo_supply)==30, action+": actual refill converts finite boxes into reserve and an open package")
	worker.progression.award_team(7.0, "repair")
	var actual_stock: Dictionary = game.expedition._capture_stock()
	var actual_crew := CampaignBonus.snapshot_player(worker)
	check(int(actual_stock.ammo)<int(original_stock.ammo) and actual_crew.ammunition.open_pack==10, action+": fixture includes a real material-to-ammunition ownership change")
	match action:
		"research": check(game.upgrades.purchase("boots"), "Actual portable research purchase commits in the garage")
		"load": check(game.expedition.handle_command("load", {"kind":"steel", "amount":1}, 1), "Actual finite garage loading commits")
		"route": check(game.expedition.handle_command("route", {"id":"harbor"}, 1), "Actual destination selection commits")
		"stop": check(game.expedition.handle_command("stop", {"id":"harbor:fuel"}, 1), "Actual roadside stop selection commits")
	var saved := _disk(game.campaign.save_path)
	check(not saved.is_empty(), action+": a fresh state accepts the committed real JSON file")
	check(saved.snapshots["1"]==JSON.parse_string(JSON.stringify(actual_crew)), action+": saved personal ammunition and safe progression equal the actual crew")
	check(saved.expedition.garage_stock==JSON.parse_string(JSON.stringify(game.expedition._capture_stock())), action+": saved warehouse equals remaining physical ownership")
	var path: String = game.campaign.save_path
	var saved_hash := FileAccess.get_sha256(path)
	paused = false
	await Cleanup.free_scene(game, self)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.campaign.save_path = path
	game.campaign.persistence_enabled = true
	var payload := {"checkpoint":saved, "mode":"preparation", "options":saved.options.duplicate()}
	check(game.expedition.restore(payload), action+": genuine continuation builds a fresh safe garage")
	_freeze()
	check(same(CampaignBonus.snapshot_player(game.players[0]),actual_crew), action+": continuation retains exact finite rounds, open package and progression")
	check(same(game.expedition._capture_stock(),saved.expedition.garage_stock), action+": continuation materializes precisely the committed warehouse")
	check(FileAccess.get_sha256(path)==saved_hash, action+": restoring mixed research does not overwrite crew before its restoration")
	if action=="research":
		var before: Dictionary = game.campaign.checkpoint()
		var points: int = game.upgrades.points
		var research: Dictionary = game.upgrades.owned.duplicate()
		var actual: Dictionary = CampaignBonus.snapshot_player(game.players[0])
		game.campaign.save_path = fixture_root.path_join("missing-parent/campaign.json")
		check(not game.upgrades.purchase("convoy_armor"), "Rejected safe research cannot apply effects or debit finite points")
		check(same(game.campaign.checkpoint(),before) and game.upgrades.points==points and game.upgrades.owned==research and same(CampaignBonus.snapshot_player(game.players[0]),actual), "Rejected safe research restores the complete prior checkpoint and actual crew")
		check(FileAccess.get_sha256(path)==saved_hash, "Rejected safe research leaves the durable checkpoint intact")
	paused = false
	await Cleanup.free_scene(game, self)
	game = null

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	fixture_root = ProjectSettings.globalize_path("res://artifacts/final-hardening-20261004/persistence/preparation-%d" % OS.get_process_id())
	check(DirAccess.make_dir_recursive_absolute(fixture_root)==OK, "All persistence fixtures use a dedicated artifact directory")
	for action: String in ["research", "load", "route", "stop"]: await _case(action)
	for filename: String in DirAccess.get_files_at(fixture_root): DirAccess.remove_absolute(fixture_root.path_join(filename))
	DirAccess.remove_absolute(fixture_root)
	print("PREPARATION CHECKPOINT: %d/%d passed" % [checks-failures, checks])
	quit(1 if failures else 0)
