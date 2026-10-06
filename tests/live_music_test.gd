extends SceneTree
const Runtime := preload("res://scripts/live_music.gd")
const Themes := preload("res://scripts/music_theme_catalog.gd")
const Rave := preload("res://scripts/rave_music_catalog.gd")
var checks := 0
var failures := 0
var fallbacks := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)

func run() -> void:
	check(Themes.THEMES.size()==13 and Rave.ENVIRONMENT_TRACKS.size()==13,"All thirteen environments have an assigned live composition")
	var identities: Dictionary = {}
	for id: String in Themes.THEMES:
		var theme := Themes.theme(id)
		var assigned: Dictionary = Rave.track(str(Rave.ENVIRONMENT_TRACKS[id]))
		check(float(theme.bpm)>=128.0 and float(theme.bpm)<=132.0 and theme.bpm==assigned.bpm,"%s uses its authored rave tempo for the live sample clock"%id)
		check(theme.motif.size()==8 and int(theme.phrase_bars) in [8,16],"%s has a recurring motif and musical phrase length"%id)
		check(float(theme.master_gain)==1.0,"%s preserves native loudness normalization before the Music bus"%id)
		var identity := JSON.stringify([theme.bpm,theme.key,theme.motif,theme.personality])
		check(theme.key==assigned.theme.key and theme.motif==assigned.theme.motif,"%s uses the assigned composition's tonic and recurring motif"%id)
		identities[identity]=true
		check(Themes.seed_for(id,91273)==Themes.seed_for(id,91273),"%s seed is deterministic"%id)
		check(Themes.seed_for(id,91273)!=Themes.seed_for(id,91274),"%s varies coherently between matches"%id)
		var compiled := Themes.native_settings(id)
		check(compiled.scale is int and compiled.personality is int and compiled.effects is float,"%s compiles descriptive music settings to native parameter types"%id)
		check(int(compiled.scale)==({"minor":0,"major":1,"dorian":2,"phrygian":3}[theme.scale]),"%s retains its intended mode in the native composer"%id)
		check(int(compiled.motif[0])==0 and int(compiled.motif.max())<=7,"%s compiles semitone motifs without accidental octave jumps"%id)
		theme.motif[0]=99
		check(Themes.theme(id).motif[0]!=99,"%s configuration is isolated from mutable runtime data"%id)
	check(identities.size()==9,"Nine distinct level compositions are distributed across all thirteen environments")
	check(Themes.intensity_for({"phase":"build","wave":1})==1,"Early construction schedules a restrained groove after its cinematic opening")
	check(Themes.intensity_for({"phase":"warning"})==2,"Warning prepares combat tension")
	check(Themes.intensity_for({"phase":"attack","enemy_count":20})==3,"A crowded attack reaches the fourth intensity")
	check(Themes.intensity_for({"phase":"attack","enemy_count":0,"boss":true})==3,"Boss presence raises musical tension")
	check(Themes.intensity_for({"phase":"salvage","wave":20})==0,"Salvage restores a conscious quiet section")
	check(Themes.intensity_for({"phase":"attack","core_ratio":0.1})==3,"A critical core raises tension independently of enemy count")
	check(Themes.section_for({"phase":"attack"},3)=="breath","Arrangement includes breath phrases during long combat")
	var host := Runtime.new()
	var guest := Runtime.new()
	host.live_enabled=false # This test proves the optional extension fallback itself.
	guest.live_enabled=false
	host.fallback_requested.connect(func(_id: String) -> void: fallbacks+=1)
	root.add_child(host)
	root.add_child(guest)
	check(not host.begin_session("ash_foundry",1234),"A disabled or missing native extension enters OGG fallback")
	check(fallbacks==1 and host.session_active and not host.native_active,"Fallback is explicit and keeps the logical music session alive")
	check(not host.rhythm_frame().active,"A fallback score cannot drive an inaccurate native rhythm clock")
	host.update_game_state({"phase":"attack","enemy_count":20,"wave":12})
	var state := host.get_music_state()
	guest.apply_music_state(state)
	check(guest.theme_seed==host.theme_seed and guest.environment_id==host.environment_id,"Host and guest derive the same piece from the replicated match seed")
	check(guest.pending_intensity==3 and guest.pending_bar==host.pending_bar,"Guest receives the host's exact phrase-boundary arrangement command")
	var serial := guest.command_serial
	guest.apply_music_state(state)
	guest.update_game_state({"phase":"build","enemy_count":0})
	check(guest.command_serial==serial and guest.pending_intensity==3,"Repeated snapshots and local guest state cannot overwrite the authoritative musical command")
	var old_command := state.duplicate(true)
	old_command.command_serial=maxi(serial-1,0)
	old_command.intensity=0
	guest.apply_music_state(old_command)
	check(guest.command_serial==serial and guest.pending_intensity==3,"An older replicated command cannot undo the current musical arrangement")
	var original_seed := host.theme_seed
	host.update_game_state({"phase":"salvage","wave":12})
	check(host.theme_seed==original_seed and host.pending_intensity==0,"Wave transitions preserve the theme and motif while changing instrumentation")
	host.set_calibration_seconds(0.22)
	check(is_equal_approx(host.clock.calibration_seconds,0.22),"Calibration reaches the audible presentation clock")
	host.set_calibration_seconds(INF)
	check(is_equal_approx(host.calibration_seconds,0.22),"Invalid persisted calibration cannot corrupt runtime timing")
	host.set_rhythm_motion_reduced(true)
	check(host.rhythm_frame().reduced_motion and float(host.rhythm_frame().motion_gain)<0.25,"Reduced rhythm motion is exposed uniformly to all cosmetic consumers")
	host.request_interlude("boss")
	check(host.interlude_kind=="boss" and host.interlude_sample>0,"Boss punctuation is scheduled on the next sample-aligned beat")
	host.request_interlude("invalid")
	check(host.interlude_kind=="boss","Unknown punctuation requests are ignored")
	host.set_music_enabled(false)
	check(not host.rhythm_frame().active and host.rhythm_frame().beat_pulse==0.0,"Turning music off immediately disables visual motion")
	host.end_session()
	guest.apply_music_state(host.get_music_state())
	check(not host.session_active and not guest.session_active,"Ending the authoritative session also ends the guest presentation session")
	var valid_state := host.get_music_state()
	check(Runtime.valid_music_state(valid_state),"Even an inactive session exports a complete valid music envelope")
	for bad in [NAN,INF,"bad",true,[],{}]:
		var invalid := valid_state.duplicate(true)
		invalid.intensity=bad
		check(not Runtime.valid_music_state(invalid),"Malformed musical intensity is rejected before native calls")
	var corrupted := valid_state.duplicate(true)
	corrupted.seed=int(corrupted.seed)+1
	check(not Runtime.valid_music_state(corrupted),"An envelope seed must match its environment and replicated match identity")
	corrupted=valid_state.duplicate(true)
	corrupted.extra={"nested":"unexpected"}
	check(not Runtime.valid_music_state(corrupted),"Unexpected or nested network music fields are rejected")
	var state_before := guest.get_music_state()
	guest.apply_music_state(corrupted)
	check(guest.get_music_state()==state_before,"Rejected envelopes cannot mutate the current guest session")
	host.set_dance_configuration(9.0,{"mechanic":{"style":"hand_tap","intensity":8.0},"scout":{"style":"bad","intensity":NAN}})
	check(host.rhythm_frame().dance_intensity==1.5 and host.rhythm_frame().dance_profiles.mechanic.intensity==1.5,"Dance amplitudes are bounded across global and per-character preferences")
	check(host.rhythm_frame().dance_profiles.scout.style=="character_default" and host.rhythm_frame().dance_profiles.scout.intensity==1.0,"Invalid dance preferences recover to a valid character default")
	var retained_profiles := host.dance_profiles.duplicate(true)
	host.set_dance_configuration(0.73,host.dance_profiles)
	check(host.dance_profiles==retained_profiles and is_equal_approx(host.dance_intensity,0.73),"Changing global gain with the current runtime profiles preserves individual preferences")
	host.set_dance_configuration(0.64,host.rhythm_frame().dance_profiles)
	check(host.dance_profiles==retained_profiles and is_equal_approx(host.dance_intensity,0.64),"A rhythm-frame profile reference can be reapplied without clearing the source dictionary")
	for id: String in Themes.THEMES:
		host.begin_session(id,1234)
		host.update_game_state({"phase":"build","wave":1,"running":true})
		var opening := host.get_music_state()
		check(opening.current_intensity==0 and opening.intensity==1 and opening.target_bar==int(Themes.theme(id).phrase_bars),"%s preserves stage-zero cinematic opening, then schedules its first stage-one groove at the first complete phrase"%id)
		var legacy := opening.duplicate(true)
		legacy.erase("current_intensity")
		check(Runtime.valid_music_state(legacy),"%s keeps version-one snapshots without current bank compatible"%id)
	# A local OGG preference must not rewind the shared host arrangement or
	# emit synthesized beat events from a recording with a different rhythm.
	host.begin_session("ash_foundry",9821)
	host.tick(70.0,true)
	var fallback_state := host.get_music_state()
	check(fallback_state.mixed_samples==70*fallback_state.mix_rate and not host.rhythm_frame().active,"A recording fallback advances only its logical arrangement timeline, without fabricated kick motion")
	host.set_paused(true)
	host.tick(8.0,true)
	check(host.get_music_state().mixed_samples==fallback_state.mixed_samples,"Pause freezes the logical timeline while native synthesis is disabled")
	host.set_paused(false)
	host.update_game_state({"phase":"attack","wave":15,"running":true})
	fallback_state=host.get_music_state()
	check(fallback_state.target_bar>host._mixed_bar() and fallback_state.target_bar%8==0,"A host using recorded music schedules its next arrangement after the current phrase, rather than at bar zero")
	host.tick(30.0,true)
	check(host.get_music_state().current_intensity==3 and not host.rhythm_frame().active,"The fallback host exports its resolved current bank once the shared phrase boundary passes")
	host.request_interlude("boss")
	check(host.interlude_sample>host.get_music_state().mixed_samples,"Fallback punctuation uses the next shared musical sample after the current timeline")
	await preload("res://tests/scene_cleanup.gd").free_scene(host,self)
	await preload("res://tests/scene_cleanup.gd").free_scene(guest,self)
	print("LIVE MUSIC: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
