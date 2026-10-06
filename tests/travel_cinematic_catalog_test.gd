extends SceneTree
## Every scene/local identity selects its own verified existing speech. Fixed
## timing must fit the longest real DE/EN recording, including SAN fallback.
const Catalog := preload("res://scripts/travel_cinematic_catalog.gd")
const Dialogue := preload("res://scripts/story_dialogue_catalog.gd")
const OUTPUT := "res://artifacts/travel-cinematics-20261004/catalog/"
const EXPECTED_ROUTES := {
	"harbor":"signal","steelworks":"signal","radar_archive":"signal","power_station":"signal",
	"mountain_pass":"storm","canyon":"storm","dam_vault":"storm",
	"quarry":"supply","rail_yard":"supply","refinery_archive":"supply","buried_archive":"supply",
}
var checks := 0
var failures := 0
var durations: Dictionary = {}
var recordings: Dictionary = {}
var scenes: Dictionary = {}
var routes: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2);return
	var previous_locale:=LocaleText.current_locale()
	var titles: Dictionary = {}
	check(Catalog.MIN_SKIP_DELAY==.45 and Catalog.VOICE_AT==1.1 and Catalog.OUTRO_TIME>=.85 and Catalog.MAX_DURATION<=9.0,"Shared skip, voice lead-in and complete outro budgets stay bounded")
	check(Catalog.ROUTES==EXPECTED_ROUTES,"All eleven route scene choices match the authored signal/storm/supply assignment")
	for locale: String in LocaleText.SUPPORTED:
		LocaleText.set_locale(locale,false)
		var directory: String=Dialogue.VOICE_ROOT+("en/" if locale=="en" else "")
		var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"source.json"))
		var translations: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://locales/"+locale+".json"))
		check(metadata.model_license=="Apache-2.0" and FileAccess.get_file_as_string(Dialogue.VOICE_ROOT+"MODEL_LICENSE.txt").contains("Apache License"),locale+" retains the existing voice model license and source manifest")
		for key: String in ["Überspringen · Enter / Esc","Der Gastgeber kann die Szene überspringen."]:
			check(translations.has(key) and LocaleText.text(key)==translations[key] and (locale=="de" or translations[key]!=key),locale+" localizes the actual skip control/host-only hint")
		for site: Dictionary in CampaignCatalog.NODES:
			if site.id=="last_shift": continue
			var route:=str(site.id)
			var expected_scene:=str(EXPECTED_ROUTES[route])
			for character: Dictionary in CharacterCatalog.CHARACTERS:
				var identity:=str(character.id)
				var context:=Catalog.context(route,identity)
				var label:=locale+"/"+route+"/"+identity
				check(not context.is_empty() and context.id==expected_scene and context.destination==route and context.environment==site.environment,label+" selects the deterministic actual campaign route and environment")
				if context.is_empty(): continue
				var dialogue: Dictionary=context.dialogue
				var radio:=identity in ["oskar","rika"]
				var speaker: String="san" if radio else identity
				var line_id: String=str(Catalog.VIGNETTES[expected_scene].radio_line if radio else Catalog.VIGNETTES[expected_scene].crew_line)
				var expected:=Dialogue.line(line_id,speaker)
				check(context.character_id==identity and context.crew_ids==[identity] and dialogue.speaker_id==speaker and dialogue.portrait_id==speaker and dialogue.speaker_name==Dialogue.speaker_name(speaker),label+" retains the selected local identity or explicit SAN radio portrait")
				check(dialogue.id==line_id and dialogue.text==expected.text and dialogue.source_text==expected.source_text and dialogue.locale==locale and translations.get(dialogue.source_text)==dialogue.text,label+" displays the exact actually recorded script in its language")
				check(dialogue.accent==Dialogue.speaker_color(speaker) and context.title==translations[Catalog.VIGNETTES[expected_scene].title],label+" keeps the speaker accent and localized scene title")
				var path:=str(dialogue.voice_path)
				check(path==Dialogue.recording_path(line_id,speaker,locale) and ResourceLoader.exists(path),label+" selects its genuine existing locale-specific speech asset")
				check(context.duration<=Catalog.MAX_DURATION and context.duration>=Catalog.VOICE_AT+float(dialogue.minimum_duration)+Catalog.OUTRO_TIME,label+" fits the full recorded voice plus lead-in and outro")
				if not durations.has(expected_scene): durations[expected_scene]=context.duration
				check(durations[expected_scene]==context.duration,label+" shares exactly the same authoritative scene duration across route, language and worker")
				var title_key:=locale+"/"+expected_scene
				if not titles.has(title_key): titles[title_key]=context.title
				if not recordings.has(path):
					var stream:=load(path) as AudioStreamWAV
					var source: Dictionary=metadata.files.get(path.get_file(),{})
					check(stream!=null and stream.mix_rate==24000 and not stream.stereo and stream.loop_mode==AudioStreamWAV.LOOP_DISABLED,locale+"/"+speaker+"/"+line_id+" remains non-looping mono speech")
					check(stream!=null and stream.get_length()>1.5 and stream.get_length()==float(dialogue.minimum_duration),locale+"/"+speaker+"/"+line_id+" duration comes from the actual recording")
					check(source.get("speaker")==speaker and source.get("text")==dialogue.text and source.get("sha256")==FileAccess.get_sha256(path),locale+"/"+speaker+"/"+line_id+" matches exact source script, speaker and file checksum")
					recordings[path]={"scene":expected_scene,"speaker":speaker,"locale":locale,"length":float(dialogue.minimum_duration),"sha256":FileAccess.get_sha256(path)}
					var longest: float=float(scenes.get(expected_scene,{}).get("longest_voice",0))
					if float(dialogue.minimum_duration)>longest: scenes[expected_scene]={"duration":context.duration,"longest_voice":float(dialogue.minimum_duration),"longest_path":path}
			var ids: Array=["mara","branko","ivo","mara"]
			var host:=Catalog.context(route,"mara",ids)
			var peer:=Catalog.context(route,"ivo",ids)
			check(host.id==peer.id and host.duration==peer.duration and host.crew_ids==ids and peer.crew_ids==ids,locale+"/"+route+" keeps all four real identities, including duplicate worker choices, with identical client timing")
			if locale=="de": routes.append({"destination":route,"scene":expected_scene,"environment":site.environment,"duration":host.duration})
	for id: String in Catalog.ORDER:
		check(titles["de/"+id]!=titles["en/"+id],id+" scene titles actually change with language")
		check(float(scenes[id].duration)>=Catalog.VOICE_AT+float(scenes[id].longest_voice)+Catalog.OUTRO_TIME,id+" complete scene budget fits its independently measured longest genuine recording")
	check(recordings.size()==42 and routes.size()==11 and Catalog.ROUTES.size()==11,"All 42 existing scene recordings and all 11 travel destinations are covered")
	for route: String in ["","last_shift","bad_route","../harbor","HARBOR"]:
		check(Catalog.context(route,"mara").is_empty(),"Invalid/non-travel route cannot borrow another scene: "+route)
	for identity: String in ["","san","bad_worker","MARA","../mara"]:
		check(Catalog.context("harbor",identity).is_empty(),"Invalid selected identity cannot borrow a present worker's voice: "+identity)
	check(Catalog.context("harbor","mara",["ivo","branko"]).is_empty() and Catalog.context("harbor","mara",[null,12,{},"bad_worker"]).is_empty(),"A worker absent from the supplied real crew cannot speak or appear")
	var clean:=Catalog.context("harbor","mara",[null,"mara","bad_worker","ivo",false,"branko","mara","nora"])
	check(clean.crew_ids==["mara","ivo","branko","mara"],"Invalid crew entries are discarded and the real four-player budget retains duplicates")
	LocaleText.set_locale("de",false)
	var original:=Catalog.context("mountain_pass","branko",["branko","ivo"])
	original.dialogue.text="caller mutation"
	original.dialogue.speaker_id="mara"
	original.crew_ids.clear()
	var fresh:=Catalog.context("mountain_pass","branko",["branko","ivo"])
	check(fresh.dialogue.speaker_id=="branko" and fresh.dialogue.text==fresh.dialogue.source_text and fresh.crew_ids==["branko","ivo"],"Callers cannot mutate catalog dialogue or the next caller's crew")
	LocaleText.set_locale("en",false)
	var english:=Catalog.context("mountain_pass","branko",["branko","ivo"])
	check(english.duration==fresh.duration and english.character_id==fresh.character_id and english.dialogue.portrait_id==fresh.dialogue.portrait_id and english.dialogue.text!=fresh.dialogue.text and english.dialogue.voice_path!=fresh.dialogue.voice_path,"Live language changes replace only exact subtitle/recording/title while keeping scene timing and identity")
	LocaleText.set_locale(previous_locale,false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	FileAccess.open(OUTPUT+"test-result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"passed":checks-failures,"failures":failures,"routes":routes,"scenes":scenes,"recordings":recordings,"fixture":"Catalog-only real CampaignCatalog/CharacterCatalog/StoryDialogueCatalog and actual DE/EN imported WAVs plus source manifests/checksums/model license. No gameplay, audio playback, rendering, networking, microphone, saved player profiles or editor interactions."},"  "))
	print("TRAVEL CINEMATIC CATALOG: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
