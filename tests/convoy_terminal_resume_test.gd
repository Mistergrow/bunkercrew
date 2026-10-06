extends SceneTree
## Empty and partial completed-campaign warehouse ledgers must survive the
## real terminal restore and authoritative snapshot unchanged.
const World := preload("res://scripts/network_world.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("TERMINAL RESUME %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)

func run() -> void:
	if not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args(): quit(2);return
	var source_game=load("res://scenes/main.tscn").instantiate()
	root.add_child(source_game)
	source_game.start_scenario(1,{"environment":"ash_foundry","position":"left","build_type":"workshop"})
	source_game.rounds.running=false
	source_game.rounds.wave=20
	check(source_game.expedition.on_victory(),"A real defended-site snapshot seeds the completed campaign fixture")
	var completed: Dictionary=source_game.campaign.checkpoint()
	completed.completed.clear()
	completed.claimed_missions.clear()
	completed.unlocked_routes.clear()
	completed.blueprints.clear()
	completed.banked_salvage=0
	completed.total_salvage_earned=0
	for site: Dictionary in CampaignCatalog.NODES:
		completed.completed.append(site.id)
		completed.claimed_missions.append(completed.campaign_id+":"+site.id)
		if int(site.cost)>0:
			completed.unlocked_routes.append(site.id)
			completed.total_salvage_earned+=int(site.cost)
		if not str(site.blueprint).is_empty(): completed.blueprints.append(site.blueprint)
	completed.current_node=CampaignCatalog.NODES[-1].id
	completed.pending_node=completed.current_node
	completed.expedition.stage="preparation"
	completed.expedition.departure={}
	check(CampaignState.valid_checkpoint(completed),"Full claimed campaign and finite vehicle satisfy the real checkpoint validator")
	paused=false
	await Cleanup.free_scene(source_game,self)
	for expected: Dictionary in [{},{"steel":5,"ammo":2}]:
		var game=load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		var saved := completed.duplicate(true)
		saved.expedition.garage_stock=expected.duplicate()
		var options: Dictionary=saved.options.duplicate()
		options.environment=CampaignCatalog.node(saved.current_node).environment
		var payload: Dictionary={"checkpoint":saved,"mode":"preparation","options":options}
		check(game.expedition.restore(payload),"Actual terminal restore accepts stock "+str(expected))
		check(paused and game.hud.overlay=="campaign_victory" and not game.rounds.running,"Completed campaign stays terminal rather than starting a new siege")
		var physical: Dictionary=game.expedition._capture_stock()
		for kind: String in CampaignCatalog.CARGO_KINDS:
			check(int(physical.get(kind,0))==int(expected.get(kind,0)),"Terminal physical "+kind+" equals the saved finite stock")
		var authority:=World.new()
		authority.bind(game)
		var snapshot: Dictionary=authority.capture()
		check(snapshot.expedition.checkpoint.expedition.garage_stock==expected,"First authoritative terminal snapshot cannot replace the exact saved warehouse ledger")
		check(game.campaign.expedition.garage_stock==expected,"Snapshot capture cannot mutate completed campaign stock in memory")
		paused=false
		await Cleanup.free_scene(game,self)
	print("CONVOY TERMINAL RESUME CHECKS: %d passed, %d failed"%[checks-failures,failures])
	quit(1 if failures else 0)
