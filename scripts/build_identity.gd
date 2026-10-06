extends RefCounted
## The project version is authoritative; desktop exports add their frozen
## source fingerprint through the builder's existing BUILD_INFO.json sidecar.
const Protocol := preload("res://scripts/network_protocol.gd")
const L := preload("res://scripts/locale_text.gd")
const Content := preload("res://scripts/content_registry.gd")
const MAX_INFO_BYTES := 16384
static var _identity: Dictionary = {}

static func version() -> String:
	var value := str(ProjectSettings.get_setting("application/config/version","unknown"))
	var release := RegEx.new()
	release.compile("^[0-9]+\\.[0-9]+\\.[0-9]+(?:-[A-Za-z0-9.-]+)?$")
	return value if value.length()<=64 and release.search(value)!=null else "unknown"

static func validated_info(value: Variant, expected_version: String, platform: String) -> Dictionary:
	if not value is Dictionary: return {}
	if not value.get("version") is String or not value.get("network_protocol") is String or not value.get("platform") is String: return {}
	var revision: Variant=value.get("world_revision")
	if not revision is int and not revision is float: return {}
	if value.get("version")!=expected_version or value.get("network_protocol")!=Protocol.BUILD or value.get("world_revision")!=Protocol.WORLD_REVISION: return {}
	if value.get("platform")!=platform: return {}
	var fingerprint: Variant=value.get("source_sha256")
	if not fingerprint is String or fingerprint.length()!=64: return {}
	var hex := RegEx.new()
	hex.compile("^[0-9a-f]{64}$")
	if hex.search(fingerprint)==null: return {}
	if value.has("content_sha256") and value.content_sha256 != Content.fingerprint(): return {}
	return {"source_sha256":fingerprint,"build":fingerprint.left(12),"exported":true,"content_sha256":Content.fingerprint()}

static func read_info(path: String, expected_version: String, platform: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>MAX_INFO_BYTES: return {}
	return validated_info(JSON.parse_string(file.get_as_text()),expected_version,platform)

static func current() -> Dictionary:
	if not _identity.is_empty(): return _identity.duplicate()
	var release := version()
	_identity={"version":release,"build":"dev","source_sha256":"","exported":false,"network_build":Protocol.BUILD,"world_revision":Protocol.WORLD_REVISION,"content_sha256":Content.fingerprint()}
	# Source/editor runs cannot accidentally identify themselves as an old
	# export next to the installed Godot executable.
	if not OS.has_feature("editor"):
		var platform := "ubuntu-x86_64" if OS.get_name()=="Linux" else "windows-x86_64" if OS.get_name()=="Windows" else ""
		if not platform.is_empty():
			var sidecar:=OS.get_executable_path().get_base_dir().path_join("BUILD_INFO.json")
			_identity.merge(read_info(sidecar,release,platform),true)
	return _identity.duplicate()

static func display_text() -> String:
	var identity := current()
	return L.format("Version %s · Build %s",[identity.version,identity.build])
