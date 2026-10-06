extends RefCounted
## A menu preview is a read-only view of a durable checkpoint. Merely opening
## the menu must never load a mission, migrate a file, or commit a route choice.
const DEFAULT_ENVIRONMENT := "ash_foundry"

static func read_saved(path: String = CampaignState.SAVE_PATH, enabled: bool = true) -> Dictionary:
	var result := {"environment":DEFAULT_ENVIRONMENT, "has_campaign":false, "recovered_backup":false}
	if not enabled: return result
	var checkpoint := _read_checkpoint(path)
	if checkpoint.is_empty():
		checkpoint = _read_checkpoint(path + ".bak")
		result.recovered_backup = not checkpoint.is_empty()
	if checkpoint.is_empty(): return result
	result.has_campaign = true
	result.environment = environment_for(checkpoint)
	return result

static func environment_for(checkpoint: Dictionary) -> String:
	if not CampaignState.valid_checkpoint(checkpoint): return DEFAULT_ENVIRONMENT
	var saved := CampaignState.migrate_checkpoint(checkpoint)
	# A destination is not the current place while it is only selected or being
	# driven toward. An occupied/defended site has actually been reached.
	var stage: String = saved.expedition.stage
	var site: String = saved.pending_node if stage in ["defense", "occupation"] else saved.current_node
	if site.is_empty() or site == CampaignCatalog.ENTRY:
		return str(saved.options.environment)
	return str(CampaignCatalog.node(site).environment)

static func _read_checkpoint(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > CampaignState.MAX_SAVE_BYTES: return {}
	var decoder := JSON.new()
	if decoder.parse(file.get_as_text()) != OK: return {}
	var value: Variant = decoder.data
	if not value is Dictionary or not CampaignState.valid_checkpoint(value): return {}
	return CampaignState.migrate_checkpoint(value)
