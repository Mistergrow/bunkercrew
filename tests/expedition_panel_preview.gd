extends SceneTree
## Prepared route/garage states. Buttons and source state are real, while the
## controller records requests so the preview cannot launch combat or save data.
const PANEL := preload("res://scripts/expedition_panel.gd")
var checks := 0
var failures := 0
class ControllerProbe extends Node:
	var state := CampaignState.new("user://expedition_visual_never_save.json",false)
	var calls: Array = []
	func can_manage() -> bool: return state.expedition.stage in ["preparation","map"]
	func can_retry_journey() -> bool: return state.expedition.stage=="failed"
	func outpost_pending() -> bool: return false
	func authoritative() -> bool: return true
	func status_text() -> String: return LocaleText.text("Ladung unterstützt die nächste Basis.")
	func request(action: String, args: Dictionary={}) -> void:
		calls.append({"action":action,"args":args.duplicate()})
		if action=="route": state.select_destination(str(args.id))
		if action=="stop": state.select_stop(str(args.id))
class GameProbe extends Node:
	var expedition: ControllerProbe
	var network: Node
class CrewProbe extends Node:
	var player_id := 1
	var character_id := "mara"
	var progression := PlayerProgression.new()
	func _init() -> void: add_child(progression)

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(description)

func run() -> void:
	LocaleText.initialize()
	var translations: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/expedition/locale-routes.json"))
	for code: String in translations:
		LocaleText._tables[code].merge(translations[code],true)
	var game := GameProbe.new()
	var controller := ControllerProbe.new()
	game.expedition = controller
	game.add_child(controller)
	root.add_child(game)
	var crew := CrewProbe.new()
	var state := controller.state
	state.begin_new({"environment":"ash_foundry","build_type":"concrete","position":"left"},["mara","branko"],1)
	var mission := state.mission_start()
	state.complete_mission(mission.id,20,[crew],null,{"steel":12,"ammo":6,"concrete":18,"scrap":8})
	state.select_destination("harbor")
	state.expedition.vehicle.cargo={"steel":4,"ammo":3,"concrete":6}
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2560,1440)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas := Control.new()
	canvas.scale = Vector2(2560.0/1440.0,1440.0/900.0)
	viewport.add_child(canvas)
	var panel := PANEL.new()
	panel.game = game
	canvas.add_child(panel)
	panel._choose_route("harbor")
	panel._choose_stop(2)
	check(controller.calls.size()==2 and controller.calls[0].action=="route" and controller.calls[1].args.id=="harbor:salvage","Route buttons dispatch real authoritative intents")
	check(not panel.depart_button.disabled,"Fueled selected route is actionable")
	panel._choose_route("quarry")
	check(panel.depart_button.disabled,"Unavailable destination cannot depart")
	panel._choose_route("harbor")
	panel._choose_stop(2)
	state.expedition.vehicle.fuel=0.0
	panel._refresh()
	check(panel.depart_button.disabled,"Empty tank disables departure")
	state.expedition.vehicle.fuel=12.0
	panel._refresh()
	check(panel.cargo_selector.item_count==CampaignCatalog.CARGO_KINDS.size(),"Cargo picker exposes all transportable materials")
	check(panel.route_buttons.size()==CampaignCatalog.NODES.size() and panel.stop_buttons.size()==4,"Map exposes each site and three optional encounters")
	if "--capture" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/expedition"))
		for language: String in ["de","en"]:
			LocaleText.set_locale(language,false)
			panel.refresh_locale()
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png("res://artifacts/expedition/map-"+language+"-2560.png")
	crew.free()
	viewport.queue_free()
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Preview fixtures tear down cleanly")
	await process_frame
	print("EXPEDITION MAP: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
