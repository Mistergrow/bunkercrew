class_name BetaAssetExportCheck
extends SceneTree
## Source or actual exported pack. No profile, save, social identity or game start.
const AudioCatalog := preload("res://scripts/audio_catalog.gd")
const Parallax := preload("res://scripts/parallax_catalog.gd")
const Surfaces := preload("res://scripts/background_surface_catalog.gd")
const Story := preload("res://scripts/story_dialogue_catalog.gd")
const Menu := preload("res://scripts/menu_music_catalog.gd")
const Rave := preload("res://scripts/rave_music_catalog.gd")
const Upgrade := preload("res://scripts/upgrade_audio.gd")
const Movement := preload("res://scripts/movement_audio.gd")
const EnemyAudio := preload("res://scripts/enemy_audio_catalog.gd")
const CinematicSound := preload("res://scripts/travel_cinematic_sound.gd")
const ConvoyAudio := preload("res://scripts/convoy_audio.gd")
const ConvoyArt := preload("res://scripts/convoy_vehicle_art.gd")
const Crafting := preload("res://scripts/crafting_catalog.gd")
const ReleaseNotes := preload("res://scripts/release_notes_catalog.gd")
const Content := preload("res://scripts/content_registry.gd")
const CRAFTING_SOURCE := "res://assets/ui/crafting/crafting_items_v1.source.json"
const RAW_METADATA := [
	"res://assets/releases/changelog.json",
	"res://assets/environments/catalog.json",
	"res://assets/environments/background_surface_regions.json",
	"res://assets/environments/surface_masks/catalog.json",
	"res://assets/environments/panorama_edges.json",
	"res://assets/environments/v3/landmarks.json",
	"res://assets/environments/props/tree_metadata.json",
	"res://assets/environments/life/vegetation_v1.source.json",
	"res://assets/environments/life/fauna_v1.source.json",
	"res://assets/cinematics/storm_charred_tree_v1.source.json",
	"res://assets/courtyard/modules_v1.source.json",
	"res://assets/enemies/machine_limbs_v1.source.json",
	"res://assets/workers/character_motion_frames.json",
	"res://assets/workers/worker_frames.json",
	"res://assets/workers/armor_anchors.json",
	"res://assets/workers/character_visuals.json",
	"res://assets/ui/social/source.json",
	CRAFTING_SOURCE,
	"res://locales/de.json", "res://locales/en.json",
]
const DIAGNOSTICS := [
	"res://tests/story_export_test.gd", "res://tests/tree_export_test.gd",
	"res://tests/living_ecology_export_test.gd", "res://tests/live_music_export_test.gd",
	"res://tests/network_gameplay_peer.gd", "res://tests/scene_cleanup.gd",
	"res://tests/campaign_revisit_test.gd", "res://tests/beta_asset_export_test.gd",
]
var checks := 0
var failures := 0
var resources: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _resource(path: String, kind: String) -> void:
	if resources.has(path): return
	var exists := ResourceLoader.exists(path)
	var loaded: Resource = load(path) if exists else null
	var valid := (loaded is Texture2D) if kind == "texture" else (loaded is AudioStream)
	resources[path] = {"kind":kind, "loaded":valid}
	_check(exists and valid, "Required %s loads: %s" % [kind,path])

func _raw(path: String) -> void:
	var exists := FileAccess.file_exists(path)
	var valid := exists and JSON.parse_string(FileAccess.get_file_as_string(path)) != null
	resources[path] = {"kind":"raw_json", "loaded":valid}
	_check(valid, "Raw metadata survives FileAccess: " + path)

func _crafting_assets() -> void:
	var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(CRAFTING_SOURCE))
	var valid: bool = metadata is Dictionary and metadata.get("atlas_size") is Array and metadata.atlas_size.size()==2 and metadata.atlas_size.all(func(part): return (part is int or part is float) and is_finite(float(part))) and metadata.get("regions") is Dictionary
	_check(valid,"Packed crafting provenance contains the atlas dimensions and named recipe regions")
	if not valid: return
	var atlas_path := CRAFTING_SOURCE.get_base_dir().path_join(str(metadata.get("asset","")))
	_resource(atlas_path,"texture")
	var atlas: Texture2D = load(atlas_path)
	var size := Vector2(int(metadata.atlas_size[0]),int(metadata.atlas_size[1]))
	_check(atlas.get_size()==size and size.x>0 and size.y>0,"Crafting atlas loads with its documented dimensions")
	_check(not str(metadata.get("generator","")).is_empty() and not str(metadata.get("source_image","")).is_empty(),"Crafting runtime texture retains its adjacent source identity")
	_check(Crafting.recipes().size()>=Crafting.LEGACY_IDS.size(),"Every historic workbench recipe remains available")
	for recipe: Dictionary in Crafting.recipes():
		var kind := str(recipe.id)
		var art: Dictionary = recipe.art
		_resource(str(art.texture),"texture")
		var region := ItemCatalog.region(art.region)
		var source_texture: Texture2D = load(str(art.texture))
		_check(region.size.x>0 and region.size.y>0 and Rect2(Vector2.ZERO,source_texture.get_size()).encloses(region),"Registered crafting picture stays inside its actual texture: "+kind)
		if kind in Crafting.LEGACY_IDS:
			var value: Variant = metadata.regions.get(kind)
			var region_valid: bool = value is Array and value.size()==4 and value.all(func(part): return (part is int or part is float) and is_finite(float(part)))
			_check(region_valid,"Crafting source names the actual original recipe picture: "+kind)
			if region_valid: _check(str(art.texture)==atlas_path and ItemCatalog.region(value)==region,"Original crafting provenance and registered sampling agree: "+kind)
		var texture := AtlasTexture.new()
		texture.atlas = source_texture
		texture.region = region
		var image := texture.get_image()
		_check(texture.get_size()==region.size and image!=null and image.get_size()==Vector2i(region.size),"Native AtlasTexture loads the packed recipe cell: "+kind)

func _release_notes() -> void:
	var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(ReleaseNotes.PATH))
	var valid: bool = metadata is Dictionary and metadata.get("schema")==1 and metadata.get("releases") is Array and not metadata.releases.is_empty()
	_check(valid,"Packed changelog has the versioned release schema")
	if not valid: return
	var entries := ReleaseNotes.entries()
	_check(entries.size()==metadata.releases.size(),"Runtime release-note reader accepts every shipped bilingual entry")
	_check(not entries.is_empty() and str(entries[0].version)==str(ProjectSettings.get_setting("application/config/version","")),"First shipped release-note entry matches this exact game version")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--no-profile-save" not in args:
		push_error("Asset diagnostics require --no-profile-save")
		quit(1)
		return
	for path: String in RAW_METADATA: _raw(path)
	_check(Content.diagnostics().is_empty(),"Packed content registry validates every enabled pack")
	for path: String in Content.enumerated_resources():
		if path.ends_with(".json"): _raw(path)
		elif path.get_extension() in ["png","webp","svg"]: _resource(path,"texture")
	_resource(str(ProjectSettings.get_setting("application/config/icon","")),"texture")
	_crafting_assets()
	_release_notes()
	_resource("res://assets/cinematics/storm_charred_tree_v1.png","texture")
	_resource("res://assets/courtyard/modules_v1.png","texture")
	_resource(ConvoyArt.HULL.resource_path, "texture")
	_resource(ConvoyArt.SERVICE_ATLAS.resource_path, "texture")
	for kind: String in ConvoyAudio.LOOP_KINDS: _resource(ConvoyAudio.recording_path(kind), "audio")
	for kind: String in ConvoyAudio.EFFECTS: _resource(ConvoyAudio.recording_path(kind), "audio")
	for definition: Dictionary in CinematicSound.SCENES.values():
		var bed: String=CinematicSound.BANK+str(definition.bed)+".wav"
		_resource(bed,"audio")
		_raw(bed.get_basename()+".source.json")
		for cue: Dictionary in definition.cues:
			_resource(str(cue.path),"audio")
			if str(cue.path).begins_with(CinematicSound.BANK): _raw(str(cue.path).get_basename()+".source.json")
	var environments := ScenarioCatalog.environments(true)
	_check(environments.size() >= 13 and Content.ENVIRONMENT_PROFILES.all(func(id):return Content.contains("environments",id)), "All thirteen existing locations retain runtime definitions alongside optional additions")
	for entry: Dictionary in environments:
		var id := str(entry.id)
		_resource(str(entry.path), "texture")
		_check(Parallax.available(id), id + ": all authored depth layers remain available")
		for path: String in Parallax.paths(id): _resource(path, "texture")
		if id in Content.ENVIRONMENT_PROFILES or not str(entry.get("surface_profile","")).is_empty():
			_check(Surfaces.available(id), id + ": authored surface metadata and current mask agree")
			_resource(Surfaces.mask_path(id), "texture")
		var sky_mask: String = Parallax.sky_mask_path(id)
		if not sky_mask.is_empty(): _resource(sky_mask,"texture")
	for build: Dictionary in ScenarioCatalog.BUILD_TYPES:
		_resource(str(build.wall), "texture")
	for score: String in AudioCatalog.MUSIC_SETS:
		for arrangement: String in AudioCatalog.MUSIC_SETS[score]:
			_resource("res://assets/audio/" + str(AudioCatalog.MUSIC_SETS[score][arrangement]), "audio")
	_resource(Menu.STREAM_PATH, "audio")
	for id: String in Rave.TRACKS:
		var track := Rave.track(id)
		_resource("res://assets/audio/" + str(track.asset), "audio")
	for kind: String in AudioCatalog.VARIANT_COUNTS:
		for index: int in int(AudioCatalog.VARIANT_COUNTS[kind]):
			_resource("res://assets/audio/%s_%02d.wav" % [kind,index+1], "audio")
	for kind: String in Upgrade.KINDS:
		for index: int in Upgrade.VARIANTS:
			_resource("res://assets/audio/%s_%02d.wav" % [kind,index+1], "audio")
	for kind: String in Movement.KINDS:
		for index: int in Movement.VARIANTS:
			_resource("res://assets/audio/step_%s_%02d.wav" % [kind,index+1], "audio")
	for family: String in EnemyAudio.FAMILIES:
		for surface: String in EnemyAudio.SURFACES:
			for index: int in EnemyAudio.VARIANTS:
				_resource("res://assets/audio/enemy_step_%s_%s_%02d.wav" % [family,surface,index+1], "audio")
	var voice_counts := {"de":0, "en":0}
	for locale: String in ["de", "en"]:
		for id: String in Story.LINES:
			for speaker: String in Story.SPEAKERS:
				var path := Story.recording_path(id,speaker,locale)
				if path.is_empty(): continue
				_resource(path,"audio")
				if speaker=="san" or speaker in Content.CHARACTER_PROFILES: voice_counts[locale] += 1
	_check(int(voice_counts.de) == 85 and int(voice_counts.en) == 85, "All 170 original DE/EN story recordings remain reachable alongside optional voice-profile aliases")
	for path: String in DIAGNOSTICS:
		_check(ResourceLoader.exists(path), "Embedded beta diagnostic retained: " + path)
	# The historic skyline preview deliberately still uses v2. Keep its images
	# while excluding the earlier unused environment-root panoramas.
	_resource("res://assets/environments/v2/ash_foundry.png", "texture")
	if "--expect-packed" in args:
		_check(not FileAccess.file_exists("res://native/bunkercrew_audio/api/extension_api.json"), "Native author/build API stays outside the pack")
		_check(not ResourceLoader.exists("res://assets/environments/ash_foundry.png"), "Unreferenced earliest panorama stays outside the pack")
		_check(not ResourceLoader.exists("res://assets/audio/story_voices/san_story_open.wav"), "Legacy voice recording stays outside the pack")
	for arg: String in args:
		if not arg.begins_with("--asset-report="): continue
		var target := arg.trim_prefix("--asset-report=")
		var report := FileAccess.open(target,FileAccess.WRITE)
		if report == null:
			_check(false,"Cannot write explicit report path")
		else:
			report.store_string(JSON.stringify({"success":failures==0,"checks":checks,"passed":checks-failures,"resources":resources,"voices":voice_counts,"scope":"Catalogue loading and raw metadata checks only; no player profiles or gameplay were changed."},"\t"))
			report.close()
	print("BETA ASSETS %s: %d/%d checks passed" % ["PASSED" if failures==0 else "FAILED",checks-failures,checks])
	quit(1 if failures else 0)
