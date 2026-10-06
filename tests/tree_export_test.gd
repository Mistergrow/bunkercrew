extends SceneTree
## Run against --main-pack from an empty --path to detect missing raw metadata
## or textures that would otherwise be supplied by the source checkout.
const Catalog := preload("res://scripts/scenario_prop_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	_check(FileAccess.file_exists("res://assets/environments/props/tree_metadata.json"), "Tree metadata is available in the exported resources")
	for kind: String in Catalog.TREE_PATHS:
		var texture := load(str(Catalog.TREE_PATHS[kind])) as Texture2D
		_check(texture != null and texture.get_width() > 0, kind + ": exported texture loads")
		_check(Catalog.canopy_points(kind).size() == 192, kind + ": exported canopy metadata loads")
		_check(not Catalog.tree_metadata(kind).is_empty(), kind + ": species metadata loads")
	var props := preload("res://scripts/scenario_props.gd").new()
	props.environment_id = "overgrown_steelworks"
	root.add_child(props)
	_check(props.tree_nodes.size() >= 3, "The exported forest builds mixed tree meshes")
	for tree: MeshInstance2D in props.tree_nodes:
		_check(tree.mesh != null and tree.texture != null, "Exported tree has its mesh and texture")
	await preload("res://tests/scene_cleanup.gd").free_scene(props, self)
	print("TREE EXPORT: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
