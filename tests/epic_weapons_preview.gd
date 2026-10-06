extends SceneTree
## Actual WorkerWeapon drawing, arranged at4x; this sheet is a visual fixture.
const OUTPUT := "res://artifacts/expedition/research/"
const L = preload("res://scripts/locale_text.gd")
class Armory extends Node2D:
	var campaign: CampaignState
	var upgrades: UpgradeSystem
	func _draw() -> void:
		draw_rect(Rect2(0,0,1600,900), Color("131e20"))
		UiArt.text(self, Vector2(46,54), "WAFFENDEPOT / FELDAUSRÜSTUNG", 27)
		UiArt.text(self, Vector2(46,83), "DIENSTWAFFEN / GEBORGENE SONDERAUSFÜHRUNGEN", 13, UiArt.MUTED)
		var kinds := ["rifle", "shotgun", "arcgun", "veteran_rifle", "breacher_shotgun", "storm_arcgun"]
		for index in 6:
			var origin := Vector2(30+(index%3)*525, 112+floori(float(index)/3.0)*378)
			draw_rect(Rect2(origin, Vector2(505,351)), Color("26342f"))
			UiArt.text(self, origin+Vector2(24,40), WorkerWeapon.WEAPONS[kinds[index]].title, 20)
			UiArt.text(self, origin+Vector2(24,312), "%d / %d" % [WorkerWeapon.WEAPONS[kinds[index]].capacity, WorkerWeapon.WEAPONS[kinds[index]].cost], 15, UiArt.MUTED)
			UiArt.text(self, origin+Vector2(145,312), "Magazin / Munition je Schuss", 12, UiArt.MUTED)
			draw_line(origin+Vector2(24,276), origin+Vector2(481,276), Color("5b675a"),1)
class Holder extends Node2D:
	var game
	var facing := 1.0
	var player_id := 1
	var climbing := false
	var mining := false
	var mounted_turret
	@warning_ignore("unused_private_class_variable")
	var _interacting := false
	func can_act() -> bool: return true
	func carried_count() -> int: return 0
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var view := SubViewport.new()
	view.size = Vector2i(2560,1440)
	view.size_2d_override = Vector2i(1600,900)
	view.size_2d_override_stretch = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var armory := Armory.new()
	armory.campaign = CampaignState.new("user://unused-weapon-sheet.json", false)
	armory.campaign.active = true
	armory.campaign.expedition.epic_weapons = WorkerWeapon.EPIC_WEAPONS.duplicate()
	armory.upgrades = UpgradeSystem.new()
	armory.upgrades.owned = {"shotgun":true, "arcgun":true}
	armory.add_child(armory.upgrades)
	view.add_child(armory)
	var kinds := ["rifle", "shotgun", "arcgun", "veteran_rifle", "breacher_shotgun", "storm_arcgun"]
	for index in 6:
		var holder := Holder.new()
		holder.game = armory
		holder.position = Vector2(30+(index%3)*525+220, 112+floori(float(index)/3.0)*378+172)
		armory.add_child(holder)
		var weapon := WorkerWeapon.new()
		holder.add_child(weapon)
		weapon.set_physics_process(false)
		weapon.position = Vector2.ZERO
		weapon.scale = Vector2.ONE * 4.0
		weapon.weapon_kind = kinds[index]
		weapon.aiming = true
		weapon.aim_direction = Vector2.RIGHT
		weapon.queue_redraw()
	for locale in ["de", "en"]:
		L.set_locale(locale, false)
		armory.queue_redraw()
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		var picture := view.get_texture().get_image()
		if picture.save_png(OUTPUT+"epic-weapons-"+locale+".png") != OK: quit(1); return
	await preload("res://tests/scene_cleanup.gd").free_scene(armory,self)
	view.queue_free()
	await process_frame
	print("EPIC VISUAL: two nativeQHD comparisons saved")
	quit(0)
