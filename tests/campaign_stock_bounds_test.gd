extends SceneTree
## Aggregate garage stock survives the real atomic writer and JSON reader.
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var stock: Dictionary = {}
	for kind: String in CampaignCatalog.CARGO_KINDS:
		stock[kind] = CampaignState.MAX_STOCK_PER_KIND
	check(CampaignState.valid_stock(stock), "All material types support multiple full physical stores")
	check(CampaignState.valid_stock({"steel":20000}), "Two legal steel crates are a legal aggregate")
	for invalid: Variant in [null, [], {"unknown":1}, {"steel":-1}, {"steel":1.5}, {"steel":"20000"}, {"steel":true}, {"steel":INF}, {"steel":NAN}, {"steel":CampaignState.MAX_STOCK_PER_KIND + 1}]:
		check(not CampaignState.valid_stock(invalid), "Malformed or oversized aggregate is rejected: " + str(invalid))
	var path := "user://campaign-stock-bounds-%d.json" % OS.get_process_id()
	var state := CampaignState.new(path, false)
	# Explicitly allow only this disposable test filename, never the real profile.
	state.persistence_enabled = true
	check(state.begin_new({"environment":"ash_foundry", "position":"left", "build_type":"bastion"}, ["mara"], 1), "Disposable campaign creates a real valid checkpoint")
	state.expedition.garage_stock = stock.duplicate()
	check(state.save_checkpoint(), "Maximum legal aggregate passes the atomic writer")
	var reloaded := CampaignState.new(path, false)
	reloaded.persistence_enabled = true
	check(reloaded.load_checkpoint(), "The JSON reader accepts the saved integer aggregate")
	var amounts_match: bool = reloaded.expedition.garage_stock.size() == stock.size()
	for kind: String in stock:
		amounts_match = amounts_match and int(reloaded.expedition.garage_stock.get(kind, -1)) == int(stock[kind])
	check(amounts_match, "Reload preserves every resource amount")
	check(CampaignState.valid_checkpoint(reloaded.checkpoint()), "Reloaded state remains a valid campaign checkpoint")
	var stable := FileAccess.get_file_as_string(path)
	state.expedition.garage_stock.steel = CampaignState.MAX_STOCK_PER_KIND + 1
	check(not state.save_checkpoint(), "Oversized state cannot overwrite a valid save")
	check(FileAccess.get_file_as_string(path) == stable, "Failed validation preserves the durable inventory")
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("CAMPAIGN STOCK BOUNDS: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
