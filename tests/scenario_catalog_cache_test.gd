extends SceneTree
const Content := preload("res://scripts/content_registry.gd")
const Catalog := preload("res://scripts/scenario_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	check(Content.diagnostics().is_empty(),"Installed registry validates before catalog lookup")
	var raw := Content.entries("environments")
	var initial := Catalog.environments(true)
	var reads := Content.read_count()
	check(initial.size()==raw.size() and initial.size()>=13,"Every registered environment is enumerated without dropping campaign entries")
	for entry: Dictionary in raw:
		check(Catalog.environment(str(entry.id)).id==entry.id,"Indexed lookup returns the selected stable ID: "+str(entry.id))
		check(Catalog.environments().any(func(value): return value.id==entry.id)==(not bool(entry.get("campaign_only",false))),"Free-shift filter preserves authored campaign visibility: "+str(entry.id))
	for index in 100:
		var entry := Catalog.environment("ash_foundry")
		entry.title = "changed"
		entry.palette[0] = "#000000"
		var listing := Catalog.environments(true)
		listing[0].path = "res://invalid.png"
	check(Content.read_count()==reads,"Repeated list and single-entry lookups do not perform disk JSON reads")
	check(Catalog.environment("ash_foundry").title!="changed" and Catalog.environment("ash_foundry").palette[0]==Content.data("environments","ash_foundry").palette[0],"Returned localized dictionaries cannot mutate the raw cached catalog")
	check(Catalog.environments(true)[0].path==raw[0].path,"Nested caller mutation cannot change later list results")
	LocaleText.set_locale("de",false)
	var german := Catalog.environment("ash_foundry")
	LocaleText.set_locale("en",false)
	var english := Catalog.environment("ash_foundry")
	check(german.title!=english.title,"Locale switch resolves a fresh presentation title after catalog caching")
	check(german.id==english.id and german.path==english.path and german.palette==english.palette,"Language changes do not translate stable IDs, resource paths or palette values")
	LocaleText.set_locale("de",false)
	check(Catalog.environment("ash_foundry").title==german.title,"Switching back restores the original localized title")
	check(Catalog.validate({"environment":"unknown","position":"unknown","build_type":"unknown"})=={"environment":"sector07","position":"left","build_type":"bastion"},"Legacy invalid setup fallback remains playable")
	print("SCENARIO CATALOG CACHE: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
