extends "res://tests/ui_audit_gallery.gd"
## Current options/report modal at small and normal native outputs, DE/EN.

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if capture_enabled and DisplayServer.get_name() == "headless": quit(2); return
	output_directory = "res://artifacts/p1-beta-readiness-20261004/onboarding-ui/support-gallery/"
	phase = "current"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory + phase))
	AudioServer.set_bus_mute(0, true)
	view = SubViewport.new()
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.gui_embed_subwindows = true
	root.add_child(view)
	for resolution: Vector2i in [Vector2i(960,600), Vector2i(1440,900)]:
		for locale: String in ["de", "en"]:
			view.size = resolution
			L.set_locale(locale, false)
			game = load("res://scenes/main.tscn").instantiate()
			view.add_child(game)
			await frames(6)
			actual_network = game.network
			game.audio.persistence_enabled = false
			game.combat_events.persistence_enabled = false
			game.campaign.persistence_enabled = false
			game.hud._layout_viewport()
			await overlay("audio")
			game.hud.options_panel.support_button.grab_focus()
			await capture("options-report-entry")
			game.hud.options_panel._open_support_report()
			await frames()
			var panel: Control = game.hud.options_panel.support_panel
			check(is_instance_valid(panel) and panel.back_button.has_focus(), "Report owns initial focus at " + str(resolution) + " " + locale)
			check(panel.preview.get_global_rect().end.x <= game.hud.screen_rect().end.x * game.hud.canvas.scale.x + game.hud.canvas.position.x, "Complete report preview fits its native viewport")
			await capture("report-modal")
			panel.preview.grab_focus()
			panel.preview.set_v_scroll(panel.preview.get_v_scroll_bar().max_value)
			await capture("report-preview-end")
			check(not game.audio.persistence_enabled and not game.combat_events.persistence_enabled and not game.campaign.persistence_enabled, "Native report captures preserve all player profiles")
			paused = false
			check(await Cleanup.free_scene(game, self), "Native report capture releases scene and audio handles")
			game = null
	var report := {"checks":checks,"failures":failures,"rendered":capture_enabled,"screens":entries,"findings":findings,"fixture":"Actual native Compatibility rendering with unchanged art/UI skin; current options entry and report modal at 960x600 and 1440x900 in German and English. Report generated from actual empty-menu game state; no game/session inputs replaced. Master muted, persistence disabled, no sockets, no physical microphone. Screens are layout evidence, not a frame-rate benchmark."}
	FileAccess.open(output_directory + phase + "/report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	if capture_enabled: write_index()
	view.queue_free()
	await process_frame
	print("P1 SUPPORT GALLERY: %d/%d checks passed; %d captures; %d overflows" % [checks-failures, checks, entries.size(), findings.size()])
	quit(1 if failures or not findings.is_empty() else 0)
