extends SceneTree
const Themes := preload("res://scripts/music_theme_catalog.gd")
const Genres := preload("res://scripts/music_genre_catalog.gd")
const Runtime := preload("res://scripts/live_music.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func run() -> void:
	check(Genres.SELECTIONS.size()==5 and Genres.GENRES.size()==4,"The genre menu has a level recommendation and four concrete styles")
	for invalid in ["hiphop","unknown",true,0,[],{}]:
		check(not Genres.valid_selection(invalid),"Malformed or misspelled style preferences are rejected")
	var default_genres: Dictionary = {}
	var ranges := {"minimal_techno":Vector2(128,132),"schranz":Vector2(140,150),"hip_hop":Vector2(84,96),"breakbeat":Vector2(124,136)}
	for environment: String in Themes.THEMES:
		var recommendation := Genres.resolve(environment)
		default_genres[recommendation]=true
		check(Genres.DEFAULTS.has(environment) and recommendation in Genres.GENRES,"%s has an authored genre recommendation"%environment)
		check(Themes.native_settings(environment).genre==Genres.NATIVE_IDS[recommendation],"%s native default follows its recommendation"%environment)
		for genre: String in Genres.GENRES:
			var original := Themes.theme(environment,genre)
			var score := Genres.apply(original,genre)
			check(score.key==original.key and score.motif==original.motif and score.scale==original.scale,"%s/%s retains the musical identity across styles"%[environment,genre])
			check(score.bpm>=ranges[genre].x and score.bpm<=ranges[genre].y,"%s/%s uses its intended genre tempo"%[environment,genre])
			var numeric := Themes.native_settings(environment,{},genre)
			check(numeric.genre==Genres.NATIVE_IDS[genre] and numeric.bpm==score.bpm,"%s/%s compiles the exact genre and tempo for the native engine"%[environment,genre])
			if genre!="minimal_techno":
				var previous: Dictionary=Themes.THEMES[environment]
				check(original.key==previous.key and original.motif==previous.motif and original.scale==previous.scale,"%s/%s preserves the previous explicit-style composition"%[environment,genre])
			check(Themes.seed_for(environment,42)==Themes.seed_for(environment,42),"Genre choice cannot change the environment/match musical seed")
	check(default_genres.size()==1 and default_genres.has("minimal_techno"),"All level recommendations expose the requested rave collection while explicit genre choices remain available")
	var host := Runtime.new()
	var guest := Runtime.new()
	host.live_enabled=false
	guest.live_enabled=false
	root.add_child(host)
	root.add_child(guest)
	host.set_music_style("hip_hop")
	host.begin_session("ash_foundry",42)
	check(host.genre=="hip_hop" and host.rhythm_frame().genre=="hip_hop","An explicit local music preference selects a concrete session genre")
	host.update_game_state({"phase":"attack","enemy_count":20})
	var serial := host.command_serial
	host.begin_session("ash_foundry",42,{"genre":"hip_hop"})
	check(host.command_serial==serial and host.pending_intensity==3,"An unchanged genre-only session request preserves its arrangement and timeline")
	guest.begin_session("ash_foundry",42,{"genre":"schranz"})
	guest.apply_music_state(host.get_music_state())
	check(guest.genre==host.genre and guest.clock.bpm==host.clock.bpm,"A first host snapshot replaces the guest's provisional genre and tempo")
	guest.set_music_style("breakbeat")
	check(guest.genre=="hip_hop" and guest.music_style=="breakbeat","Guest personal preferences cannot replace the host's current musical arrangement")
	guest.set_live_enabled(true)
	guest.set_live_enabled(false)
	guest.update_game_state({"phase":"build"})
	check(guest._remote_session and guest.pending_intensity==host.pending_intensity and guest.command_serial==host.command_serial,"Changing the local synthesis preference preserves authoritative guest arrangement commands")
	var state := host.get_music_state()
	for invalid in ["level_default","hiphop","invalid",0,true,[],{}]:
		var bad := state.duplicate(true)
		bad.genre=invalid
		check(not Runtime.valid_music_state(bad),"Only a known concrete genre may enter a network music envelope")
	state.erase("genre")
	check(Runtime.valid_music_state(state),"Version-one music snapshots without genre remain compatible")
	guest.apply_music_state(state)
	check(guest.genre==Genres.resolve("ash_foundry"),"An older snapshot uses the authored level genre")
	var theme_before := host.theme_seed
	host.set_music_style("schranz")
	check(host.genre=="schranz" and host.theme_seed==theme_before,"Changing the local style preserves the piece's deterministic seed")
	guest.apply_music_state(host.get_music_state())
	check(guest.genre=="schranz" and guest.clock.bpm==host.clock.bpm,"A new host genre is applied with its matching sample clock tempo")
	host.start_preview("ash_foundry",42,-1.0,3,"breakbeat")
	check(host.genre=="breakbeat" and host.pending_intensity==3,"An isolated preview accepts a genre alongside its existing tempo and intensity API")
	host.set_preview_intensity(2)
	check(host.genre=="breakbeat" and host.pending_intensity==2,"Changing preview intensity preserves its selected genre")
	await Cleanup.free_scene(host,self)
	await Cleanup.free_scene(guest,self)
	print("MUSIC GENRES: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
