extends RefCounted
## The fixed shot list of the visual-review instrument. Everything that can
## be enumerated is read from the game's own catalogs at list time:
## environments, enemy classes, characters and the option tabs.
const WIDE_SIZES := [Vector2i(960, 600), Vector2i(2560, 1440), Vector2i(3440, 1440)]

static var _measured: Dictionary = {}

## Mean luminance of the environment's real panorama (read from its source
## image, so it also works headless); the catalog sky colour only as fallback.
static func _luminance(entry: Dictionary) -> float:
	var key := str(entry.get("id", ""))
	if _measured.has(key): return _measured[key]
	var color := Color(str(entry.get("sky_color", "#808080")))
	var path := str(entry.get("path", ""))
	if not path.is_empty() and FileAccess.file_exists(path):
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null and not image.is_empty():
			if image.is_compressed(): image.decompress()
			image.convert(Image.FORMAT_RGB8)
			image.resize(1, 1, Image.INTERPOLATE_BILINEAR)
			color = image.get_pixel(0, 0)
	_measured[key] = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	return _measured[key]

static func _chunks(values: Array, limit: int) -> Array:
	var result: Array = []
	var parts := ceili(float(values.size()) / float(limit))
	var each := ceili(float(values.size()) / float(maxi(parts, 1)))
	for index in parts: result.append(values.slice(index * each, (index + 1) * each))
	return result

static func _earliest(kinds: Array, waves: Dictionary) -> String:
	var best := ""
	for kind: String in kinds:
		if best.is_empty() or int(waves.get(kind, 99)) < int(waves.get(best, 99)): best = kind
	return best

## Contrasting environments chosen from catalog data, never by id.
static func contrasts(environments: Array) -> Dictionary:
	var darkest: Dictionary = {}
	var brightest: Dictionary = {}
	var water: Dictionary = {}
	for entry: Dictionary in environments:
		if darkest.is_empty() or _luminance(entry) < _luminance(darkest): darkest = entry
	for entry: Dictionary in environments:
		# Snow first, otherwise simply the brightest sky.
		var snowy := str(entry.get("weather", "")) == "snow"
		var best_snowy := str(brightest.get("weather", "")) == "snow"
		if brightest.is_empty() or (snowy and not best_snowy) or (snowy == best_snowy and _luminance(entry) > _luminance(brightest)): brightest = entry
	for entry: Dictionary in environments:
		if (entry.get("water_regions", []) as Array).is_empty() or entry.id == darkest.get("id") or entry.id == brightest.get("id"): continue
		if water.is_empty() or float(entry.get("rain_strength", 0.0)) > float(water.get("rain_strength", 0.0)): water = entry
	return {"night": darkest, "bright": brightest, "water": water}

static func build(driver, options: Dictionary) -> Array:
	var size := Vector2i(1920, 1080)
	var requested := str(options.get("size", "")).split("x")
	if requested.size() == 2 and int(requested[0]) >= 320 and int(requested[1]) >= 200: size = Vector2i(int(requested[0]), int(requested[1]))
	var locale := str(options.get("locale", "de"))
	if locale not in ["de", "en"]: locale = "de"
	var other := "en" if locale == "de" else "de"
	var shots: Array = []
	var add := func(id: String, group: String, title: String, stage: String, method: String, args: Dictionary = {}, frames: int = 1, extra: Dictionary = {}) -> void:
		var entry := {"id": id, "group": group, "title": title, "stage": stage, "method": method, "args": args, "frames": frames,
			"kind": "sequence" if frames > 1 else "still", "size": [size.x, size.y], "locale": locale, "seed": 7001 + absi(id.hash()) % 100000}
		entry.merge(extra, true)
		shots.append(entry)

	# ---- UI stills ----------------------------------------------------
	driver.spec = {"seed": 1}
	await driver.menu()
	var hud = driver.game.hud
	hud.audio_return_overlay = "menu"
	hud.overlay = "audio"
	await driver.frames(4)
	var tabs: int = hud.options_panel.tab_buttons.size() if is_instance_valid(hud.options_panel) else 0
	var tab_names: Array = []
	for index in tabs: tab_names.append(str(hud.options_panel.tab_buttons[index].text))
	hud.overlay = "menu"
	await driver.frames(3)
	var ui := [
		["ui.main_menu", "Main menu", "main_menu", {}],
		["ui.scenario_select", "New game: scenario selection", "scenario_select", {}],
		["ui.character_select", "Character selection (four local players)", "character_select", {}],
		["ui.help", "Help manual", "overlay_menu", {"action": "help", "overlay": "help"}],
		["ui.changelog", "Changelog (release notes) opened from the main menu", "changelog", {}],
		["ui.expedition", "Campaign / convoy map after a won mission", "expedition", {}],
		["ui.crafting", "Workbench crafting panel", "crafting", {}],
		["ui.research", "Research / upgrade tree (Technik) with points to spend", "overlay_match", {"action": "upgrades", "overlay": "upgrades"}],
		["ui.personnel", "Personnel panel in a four-player match", "overlay_match", {"action": "personnel", "overlay": "personal"}],
		["ui.pause", "Pause menu", "overlay_match", {"action": "pause", "overlay": "pause"}],
		["ui.victory", "Victory report", "result", {"won": true}],
		["ui.defeat", "Defeat report", "result", {"won": false}],
		["ui.tutorial_prompt", "Solo tutorial prompt over gameplay", "tutorial", {}],
		["ui.hud_solo_idle", "HUD, solo, build phase, nothing happening", "hud_idle", {"players": 1}],
		["ui.hud_combat", "HUD during a running wave (solo)", "hud_combat", {}],
		["ui.hud_coop4", "HUD with four local players carrying material", "hud_idle", {"players": 4}],
	]
	for row: Array in ui: add.call(row[0], "ui", row[1], "ui", row[2], row[3])
	for index in tabs:
		add.call("ui.options.tab%d" % index, "ui", "Options, tab %d (%s)" % [index + 1, tab_names[index]], "ui", "options", {"tab": index})
	add.call("ui.lobby_host", "ui", "Online lobby as host with one guest connected (real local connection)", "ui", "lobby", {"role": "host"}, 1, {"pair": "lobby", "wall_seconds": 80})
	add.call("ui.lobby_guest", "ui", "Online lobby as connected guest (real local connection)", "ui", "lobby", {"role": "guest"}, 1, {"pair": "lobby", "wall_seconds": 80})
	# Second language for the five screens with the most running text.
	var wordy := [["ui.help", "overlay_menu", {"action": "help", "overlay": "help"}, "Help manual"], ["ui.changelog", "changelog", {}, "Changelog"],
		["ui.research", "overlay_match", {"action": "upgrades", "overlay": "upgrades"}, "Research tree"], ["ui.expedition", "expedition", {}, "Convoy map"]]
	if tabs > 0: wordy.append(["ui.options.tab0", "options", {"tab": 0}, "Options, first tab"])
	for row: Array in wordy:
		add.call("%s.%s" % [row[0], other], "ui-locale", "%s in %s" % [row[3], other.to_upper()], "ui", row[1], row[2], 1, {"locale": other})
	for wide: Vector2i in WIDE_SIZES:
		var suffix := "%dx%d" % [wide.x, wide.y]
		var at := {"size": [wide.x, wide.y]}
		add.call("ui.main_menu.%s" % suffix, "ui-resolution", "Main menu at %s" % suffix, "ui", "main_menu", {}, 1, at)
		add.call("ui.hud_solo_idle.%s" % suffix, "ui-resolution", "Solo HUD at %s" % suffix, "ui", "hud_idle", {"players": 1}, 1, at)
		if tabs > 0: add.call("ui.options.tab0.%s" % suffix, "ui-resolution", "Options, first tab at %s" % suffix, "ui", "options", {"tab": 0}, 1, at)
	add.call("ui.seq.menu_focus", "ui-motion", "Main menu: focus moving down and back up across the items (one step every 6 frames)", "ui", "seq_menu_focus", {}, 14, {"ui_motion": true})
	add.call("ui.seq.panel_open_close", "ui-motion", "Research panel opening at frame 2 and closing at frame 8 over gameplay", "ui", "seq_panel", {}, 14, {"ui_motion": true})
	add.call("ui.seq.tab_change", "ui-motion", "Options: switching through the tabs (change every 3 captured frames)", "ui", "seq_tabs", {}, 12, {"ui_motion": true})
	add.call("ui.seq.wave_start", "ui-motion", "Wave start: warning announcement, then the attack begins (10 simulated frames apart)", "ui", "seq_wave_start", {}, 16, {"ui_motion": true})
	add.call("ui.seq.victory_reveal", "ui-motion", "Victory report appearing after the last wave (victory at frame 2)", "ui", "seq_victory", {}, 14, {"ui_motion": true})

	# ---- world --------------------------------------------------------
	var environments: Array = ScenarioCatalog.environments(true)
	for entry: Dictionary in environments:
		add.call("world.%s.wide" % entry.id, "world", "%s: standard overview framing with the bunker, HUD hidden" % entry.title, "world", "wide", {"environment": entry.id})
	var chosen := contrasts(environments)
	for role: String in chosen:
		var entry: Dictionary = chosen[role]
		if entry.is_empty(): continue
		var label := "%s (%s)" % [entry.title, role]
		add.call("world.%s.interior" % entry.id, "world-detail", label + ": close-up of the bunker interior", "world", "interior", {"environment": entry.id})
		add.call("world.%s.underground" % entry.id, "world-detail", label + ": deepest view stage with every underground room built", "world", "underground", {"environment": entry.id})
		if not str(entry.get("weather", "")).is_empty() and str(entry.get("weather", "")) != "clear":
			add.call("world.%s.weather" % entry.id, "world-detail", "%s: catalog weather '%s' after 8 simulated seconds, sky and ground" % [label, entry.weather], "world", "weather", {"environment": entry.id})
	for entry: Dictionary in environments:
		if bool(entry.get("lightning", false)):
			add.call("world.%s.storm" % entry.id, "world-detail", "%s: thunderstorm, lightning strike released at frame 2" % entry.title, "world", "storm", {"environment": entry.id}, 14)

	# ---- actors -------------------------------------------------------
	var night := str(chosen.night.get("id", environments[0].id))
	var bright := str(chosen.bright.get("id", environments[0].id))
	add.call("actors.workers", "actors", "All playable workers side by side, close-up", "action", "workers", {"environment": bright})
	var humans: Array = Array(EnemyCatalog.HUMAN_CLASSES)
	var vehicles: Array = Array(EnemyCatalog.VEHICLE_CLASSES)
	var mechs: Array = []
	for kind: String in EnemyCatalog.GROUND_CLASSES:
		if kind not in humans and kind not in vehicles: mechs.append(kind)
	var aircraft: Array = Array(AirEnemyCatalog.CLASS_ORDER)
	var rows := {"infantry": _chunks(humans, 6), "mechs": _chunks(mechs, 6), "vehicles": _chunks(vehicles, 4), "aircraft": _chunks(aircraft, 4)}
	for family: String in rows:
		var parts: Array = rows[family]
		for index in parts.size():
			var id := "actors.enemies.%s" % family + ("" if parts.size() == 1 else ".%d" % (index + 1))
			add.call(id, "actors", "Enemy close-up, %s: %s" % [family, ", ".join(PackedStringArray(parts[index]))], "action", "enemy_row", {"environment": bright, "kinds": parts[index], "air": family == "aircraft"})
	add.call("actors.stations.production", "actors", "Production floor close-up: mixer, core, furnace, medic", "action", "stations", {"environment": bright, "area": "production"})
	add.call("actors.stations.defense", "actors", "Roof close-up: gun emplacement, supply crates, built flak tower", "action", "stations", {"environment": bright, "area": "defense"})
	add.call("actors.stations.workshop", "actors", "First basement close-up: workbench and built room machine", "action", "stations", {"environment": bright, "area": "workshop"})

	# ---- worker motion ------------------------------------------------
	var worker := [
		["idle", "idle stance, 6 frames apart", 14], ["walk", "walking right, 3 frames apart", 14], ["run", "full-speed run with jump, 3 frames apart", 14],
		["carry", "walking with a full load, 3 frames apart", 14], ["mine", "digging earth below the bunker, 4 frames apart", 14], ["ladder", "climbing the shaft ladder, 4 frames apart", 14],
		["shoot", "aim, automatic fire, then reload, 8 frames apart", 16], ["hit", "taking a hit at frame 2, 2 frames apart", 12],
		["revive", "collapse at frame 1, a second worker revives", 16], ["dance", "idle dance to the live music (audio mixed by the movie writer), 4 frames apart", 14]]
	for row: Array in worker:
		add.call("motion.worker.%s" % row[0], "motion-worker", "Worker: " + row[1], "action", "worker_" + row[0], {"environment": bright}, row[2], {"movie": true, "wall_seconds": 300} if row[0] == "dance" else {})
	var cast := {"infantry": _earliest(humans, EnemyCatalog.INTRO_WAVES), "mech": _earliest(mechs, EnemyCatalog.INTRO_WAVES),
		"vehicle": _earliest(vehicles, EnemyCatalog.INTRO_WAVES), "aircraft": _earliest(aircraft, AirEnemyCatalog.INTRO_WAVES)}
	for family: String in cast:
		for act: String in ["move", "attack", "damage", "die"]:
			add.call("motion.%s.%s" % [family, act], "motion-enemy", "%s (%s): %s" % [family.capitalize(), cast[family], act], "action", "enemy_" + act, {"environment": bright, "kind": cast[family], "air": family == "aircraft"}, 14)
	add.call("motion.station.working", "motion-enemy", "Production machine working after a worker loads it, 5 frames apart", "action", "station_working", {"environment": bright}, 14)

	# ---- combat -------------------------------------------------------
	add.call("combat.rifle_single", "combat", "Single rifle shots at a machine: every frame around the first shot", "action", "rifle_single", {"environment": bright}, 14)
	add.call("combat.mg_sustained", "combat", "Sustained automatic fire from the worker's gun, 3 frames apart", "action", "mg_sustained", {"environment": bright}, 14)
	add.call("combat.turret_fire", "combat", "Manned roof gun firing at approaching machines, 2 frames apart", "action", "turret_fire", {"environment": bright}, 14)
	add.call("combat.flak_fire", "combat", "Unattended flak tower engaging two aircraft, seen by the gunner on the roof gun through the game's follow camera; from the first aircraft on screen, 10 frames apart", "action", "flak_fire", {"environment": bright}, 16)
	for surface: Array in [["metal", "metal"], ["stone", "earth"], ["concrete", "concrete"]]:
		add.call("combat.impact_%s" % surface[0], "combat", "Projectile impacts on %s (game impact material '%s'), hit at frame 1" % [surface[0], surface[1]], "action", "impact", {"environment": bright, "material": surface[1]}, 12)
	add.call("combat.explosion", "combat", "Large explosion on open ground, released at frame 1", "action", "explosion", {"environment": bright}, 16)
	for pair: Array in [["night", night], ["bright", bright]]:
		var args := {"environment": pair[1]}
		var crew := "four local players at their posts (roof gun, roof rifle, outer gate, fence line), flak built, game camera (couch co-op fit) and HUD as the players see them"
		add.call("combat.wave_%s" % pair[0], "combat", "Mixed late wave in %s: %s; still once three machines are engaged on screen" % [pair[1], crew], "action", "wave_still", args, 1, {"wall_seconds": 480})
		add.call("combat.wave_%s.seq" % pair[0], "combat", "Mixed late wave in %s: %s; from three engaged machines on screen, 8 frames apart" % [pair[1], crew], "action", "wave_sequence", args, 16, {"wall_seconds": 480})
		for renderer: String in ["gpu", "software"]:
			add.call("perf.wave_%s.%s" % [pair[0], renderer], "performance", "Frame time over 10 simulated seconds of the %s wave at 1920x1080, %s" % [pair[0], renderer], "action", "wave_probe", args, 1,
				{"size": [1920, 1080], "renderer": renderer, "wall_seconds": 900, "locale": "de"})
			add.call("perf.kills_%s.%s" % [pair[0], renderer], "performance", "Kill cost in the %s world at 1920x1080, %s: infantry, walker, vehicle and aircraft defeated in turn, three rounds, 40 frames apart" % [pair[0], renderer], "action", "kill_probe", args, 1,
				{"size": [1920, 1080], "renderer": renderer, "wall_seconds": 600, "locale": "de"})

	# ---- golden reference scenes (docs/art/BUNKERCREW_VISUAL_STYLE_BIBLE.md §8)
	var pair_crew := "two players (roof gun and roof rifle), game camera and HUD as they see them"
	add.call("golden.combat", "golden", "Combat reference, %s with its weather: %s, once two machines are engaged" % [bright, pair_crew], "action", "golden_combat", {"environment": bright}, 1, {"wall_seconds": 480})
	add.call("golden.combat.seq", "golden", "Combat reference, %s: %s; from two engaged machines, 6 frames apart" % [bright, pair_crew], "action", "golden_combat", {"environment": bright}, 12, {"wall_seconds": 480})
	add.call("golden.interior", "golden", "Interior reference, %s: first basement with workbench and room machine, two workers, a carried load, HUD" % bright, "action", "golden_interior", {"environment": bright})
	add.call("golden.dark", "golden", "Dark bunker reference, %s at night: %s, flak tower built, once two machines are engaged" % [night, pair_crew], "action", "golden_dark", {"environment": night}, 1, {"wall_seconds": 480})
	add.call("golden.dark.seq", "golden", "Dark bunker reference, %s at night: %s, flak built; 4 frames apart" % [night, pair_crew], "action", "golden_dark", {"environment": night}, 12, {"wall_seconds": 480})
	return shots
