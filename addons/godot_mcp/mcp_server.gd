@tool
extends Node
class_name MCPServer

## MCP Server for Godot Engine
## Implements HTTP server with JSON-RPC 2.0 protocol for MCP communication

# Tool imports - Core
const SceneTools = preload("res://addons/godot_mcp/tools/scene_tools.gd")
const NodeTools = preload("res://addons/godot_mcp/tools/node_tools.gd")
const ResourceTools = preload("res://addons/godot_mcp/tools/resource_tools.gd")
const ProjectTools = preload("res://addons/godot_mcp/tools/project_tools.gd")
const ScriptTools = preload("res://addons/godot_mcp/tools/script_tools.gd")
const EditorTools = preload("res://addons/godot_mcp/tools/editor_tools.gd")
const DebugTools = preload("res://addons/godot_mcp/tools/debug_tools.gd")
const FileSystemTools = preload("res://addons/godot_mcp/tools/filesystem_tools.gd")
const AnimationTools = preload("res://addons/godot_mcp/tools/animation_tools.gd")

# Tool imports - Visual
const MaterialTools = preload("res://addons/godot_mcp/tools/material_tools.gd")
const ShaderTools = preload("res://addons/godot_mcp/tools/shader_tools.gd")
const LightingTools = preload("res://addons/godot_mcp/tools/lighting_tools.gd")
const ParticleTools = preload("res://addons/godot_mcp/tools/particle_tools.gd")

# Tool imports - 2D
const TilemapTools = preload("res://addons/godot_mcp/tools/tilemap_tools.gd")
const GeometryTools = preload("res://addons/godot_mcp/tools/geometry_tools.gd")

# Tool imports - Gameplay
const PhysicsTools = preload("res://addons/godot_mcp/tools/physics_tools.gd")
const NavigationTools = preload("res://addons/godot_mcp/tools/navigation_tools.gd")
const AudioTools = preload("res://addons/godot_mcp/tools/audio_tools.gd")

# Tool imports - Utilities
const UITools = preload("res://addons/godot_mcp/tools/ui_tools.gd")
const SignalTools = preload("res://addons/godot_mcp/tools/signal_tools.gd")
const GroupTools = preload("res://addons/godot_mcp/tools/group_tools.gd")

# Tool imports - Dev power-tools (screenshot + eval)
const DevTools = preload("res://addons/godot_mcp/tools/dev_tools.gd")

signal server_started
signal server_stopped
signal client_connected
signal client_disconnected
signal request_received(method: String, params: Dictionary)

var _tcp_server: TCPServer
var _port: int = 3000
var _host: String = "127.0.0.1"
var _running: bool = false
var _debug_mode: bool = false
var _clients: Array[StreamPeerTCP] = []
var _pending_data: Dictionary = {}  # client -> accumulated data

# Tool instances
var _tools: Dictionary = {}
var _tool_definitions: Array[Dictionary] = []
var _disabled_tools: Array = []  # List of disabled tool names

# MCP Protocol info
# Streamable HTTP transport. Version is negotiated per spec: echo the client's
# requested version when supported, otherwise offer the latest we speak.
const SUPPORTED_PROTOCOL_VERSIONS: Array[String] = ["2025-06-18", "2025-03-26", "2024-11-05"]
const LATEST_PROTOCOL_VERSION := "2025-06-18"
const SERVER_NAME = "godot-mcp-server"
const SERVER_VERSION = "1.0.0"

const HTTP_STATUS_TEXT := {
	200: "OK",
	202: "Accepted",
	204: "No Content",
	400: "Bad Request",
	404: "Not Found",
	405: "Method Not Allowed",
	406: "Not Acceptable",
	500: "Internal Server Error",
}


func _ready() -> void:
	if _tcp_server == null:
		_tcp_server = TCPServer.new()
	_register_tools()


func _process(_delta: float) -> void:
	if not _running:
		return

	# Accept new connections
	if _tcp_server.is_connection_available():
		var client = _tcp_server.take_connection()
		if client:
			_clients.append(client)
			_pending_data[client] = ""
			print("[MCP] Client connected (total: %d)" % _clients.size())
			client_connected.emit()

	# Process existing clients
	var clients_to_remove: Array[StreamPeerTCP] = []
	for client in _clients:
		client.poll()
		var status = client.get_status()

		if status == StreamPeerTCP.STATUS_CONNECTED:
			var available = client.get_available_bytes()
			if available > 0:
				var data = client.get_data(available)
				if data[0] == OK:
					var request_str = data[1].get_string_from_utf8()
					_pending_data[client] += request_str
					if _debug_mode:
						print("[MCP] Received %d bytes, total pending: %d" % [available, _pending_data[client].length()])
					_process_http_request(client)
				else:
					print("[MCP] Error receiving data: %s" % data[0])
		elif status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			clients_to_remove.append(client)
			print("[MCP] Client status changed: %s" % status)

	# Remove disconnected clients
	for client in clients_to_remove:
		_clients.erase(client)
		_pending_data.erase(client)
		if _debug_mode:
			print("[MCP] Client disconnected")
		client_disconnected.emit()


func initialize(port: int, host: String, debug: bool) -> void:
	_port = port
	_host = host
	_debug_mode = debug


func start() -> bool:
	if _running:
		return true

	# IMPORTANT: plugin.gd can call start() from _enter_tree() before this
	# node receives _ready(). In that case _tcp_server is still null.
	if _tcp_server == null:
		_tcp_server = TCPServer.new()

	var error = _tcp_server.listen(_port, _host)
	if error != OK:
		push_error("[MCP] Failed to start server on port %d: %s" % [_port, error_string(error)])
		return false

	_running = true
	print("[MCP] Server started on http://%s:%d/mcp" % [_host, _port])
	server_started.emit()
	return true


func stop() -> void:
	# Be defensive: Godot can call plugin _exit_tree() after a failed _enter_tree(),
	# so _tcp_server may still be null or the server may not be running.
	for client in _clients.duplicate():
		if client != null:
			client.disconnect_from_host()
	_clients.clear()
	_pending_data.clear()

	if _tcp_server != null:
		_tcp_server.stop()

	if _running:
		_running = false
		print("[MCP] Server stopped")
		server_stopped.emit()


func is_running() -> bool:
	return _running


func set_port(port: int) -> void:
	_port = port


func set_debug_mode(debug: bool) -> void:
	_debug_mode = debug


func get_connection_count() -> int:
	return _clients.size()


func set_disabled_tools(disabled: Array) -> void:
	_disabled_tools = disabled


func get_disabled_tools() -> Array:
	return _disabled_tools


func is_tool_enabled(tool_name: String) -> bool:
	return not (tool_name in _disabled_tools)


func get_tools_by_category() -> Dictionary:
	"""Returns tools organized by category for UI display"""
	var result: Dictionary = {}

	for category in _tools:
		var executor = _tools[category]
		var tools = executor.get_tools()
		result[category] = tools

	return result


func get_enabled_tools() -> Array[Dictionary]:
	"""Returns only enabled tool definitions"""
	var enabled: Array[Dictionary] = []

	for tool_def in _tool_definitions:
		if is_tool_enabled(tool_def["name"]):
			enabled.append(tool_def)

	return enabled


func _register_tools() -> void:
	# Register all tool executors - Core
	_tools["scene"] = SceneTools.new()
	_tools["node"] = NodeTools.new()
	_tools["resource"] = ResourceTools.new()
	_tools["project"] = ProjectTools.new()
	_tools["script"] = ScriptTools.new()
	_tools["editor"] = EditorTools.new()
	_tools["debug"] = DebugTools.new()
	_tools["filesystem"] = FileSystemTools.new()
	_tools["animation"] = AnimationTools.new()

	# Register all tool executors - Visual
	_tools["material"] = MaterialTools.new()
	_tools["shader"] = ShaderTools.new()
	_tools["lighting"] = LightingTools.new()
	_tools["particle"] = ParticleTools.new()

	# Register all tool executors - 2D
	_tools["tilemap"] = TilemapTools.new()
	_tools["geometry"] = GeometryTools.new()

	# Register all tool executors - Gameplay
	_tools["physics"] = PhysicsTools.new()
	_tools["navigation"] = NavigationTools.new()
	_tools["audio"] = AudioTools.new()

	# Register all tool executors - Utilities
	_tools["ui"] = UITools.new()
	_tools["signal"] = SignalTools.new()
	_tools["group"] = GroupTools.new()

	# Register dev power-tools
	_tools["dev"] = DevTools.new()

	# Collect all tool definitions
	_tool_definitions.clear()
	for category in _tools:
		var executor = _tools[category]
		var tools = executor.get_tools()
		for tool_def in tools:
			tool_def["name"] = "%s_%s" % [category, tool_def["name"]]
			_tool_definitions.append(tool_def)

	if _debug_mode:
		print("[MCP] Registered %d tools" % _tool_definitions.size())


func _process_http_request(client: StreamPeerTCP) -> void:
	# Keep-alive clients (Claude Code reuses one TCP connection) can buffer
	# several complete HTTP requests before we get scheduled again, so drain
	# every complete request instead of waiting for the next data event.
	while _try_process_one_request(client):
		pass


func _try_process_one_request(client: StreamPeerTCP) -> bool:
	var data = _pending_data.get(client, "")
	if data.is_empty():
		return false

	# Check for complete HTTP request (headers end with \r\n\r\n)
	var header_end = data.find("\r\n\r\n")
	if header_end == -1:
		if _debug_mode and data.length() > 0:
			print("[MCP] Waiting for headers... current data length: %d" % data.length())
		return false

	# Parse HTTP headers
	var header_section = data.substr(0, header_end)
	var headers = _parse_http_headers(header_section)

	if headers.is_empty():
		_pending_data[client] = ""
		return false

	# Get content length - support chunked encoding
	var content_length = 0
	var is_chunked = false

	if headers.has("content-length"):
		content_length = int(headers["content-length"])
	elif headers.has("transfer-encoding") and headers["transfer-encoding"].to_lower().contains("chunked"):
		is_chunked = true

	# Check if we have complete body
	var body_start = header_end + 4
	var body = data.substr(body_start)

	# IMPORTANT: Content-Length is in bytes, not characters!
	# For UTF-8 strings with multi-byte chars (emojis, Chinese, etc.), we must compare byte sizes
	var body_bytes = body.to_utf8_buffer()
	var body_byte_size = body_bytes.size()

	if _debug_mode:
		print("[MCP] Request headers: method=%s, content_length=%d, body_bytes=%d, chunked=%s" % [headers.get("method", "?"), content_length, body_byte_size, is_chunked])

	# Handle chunked encoding
	if is_chunked:
		var decoded_body = _decode_chunked_body(body)
		if decoded_body == null:
			if _debug_mode:
				print("[MCP] Waiting for chunked body...")
			return false  # Wait for more data
		body = decoded_body
		content_length = body.to_utf8_buffer().size()
	elif body_byte_size < content_length:
		if _debug_mode:
			print("[MCP] Waiting for body... need %d bytes, have %d bytes" % [content_length, body_byte_size])
		return false  # Wait for more data

	# Extract the complete request body (by bytes, then convert back to string)
	var request_body: String
	if is_chunked:
		request_body = body
		_pending_data[client] = ""
	else:
		# Extract exactly content_length bytes and convert to string
		var request_bytes = body_bytes.slice(0, content_length)
		request_body = request_bytes.get_string_from_utf8()
		# Remove processed data (also by bytes)
		if body_byte_size > content_length:
			var remaining_bytes = body_bytes.slice(content_length)
			_pending_data[client] = remaining_bytes.get_string_from_utf8()
		else:
			_pending_data[client] = ""

	# Route request
	var method = headers.get("method", "GET")
	var path = headers.get("path", "/")
	var query_pos = path.find("?")
	if query_pos != -1:
		path = path.substr(0, query_pos)

	if _debug_mode:
		print("[MCP] Processing: %s %s (body length: %d)" % [method, path, request_body.length()])

	if path == "/mcp":
		match method:
			"POST":
				_handle_mcp_post(client, request_body)
			"OPTIONS":
				_send_empty_response(client, 204)
			"GET":
				# Streamable HTTP: the standalone GET stream for server-initiated
				# messages is optional; we do not offer one (spec allows 405).
				_send_empty_response(client, 405, {"Allow": "POST, OPTIONS"})
			"DELETE":
				# Stateless server: no Mcp-Session-Id is issued, so there is no
				# session to terminate (spec allows 405).
				_send_empty_response(client, 405, {"Allow": "POST, OPTIONS"})
			_:
				_send_empty_response(client, 405, {"Allow": "POST, OPTIONS"})
	elif method == "OPTIONS":
		_send_empty_response(client, 204)
	elif method == "GET" and path == "/health":
		_send_json_response(client, 200, _create_health_response())
	elif method == "GET" and path == "/api/tools":
		_send_json_response(client, 200, _create_tools_list_response())
	else:
		_send_json_response(client, 404, {"error": "Not found"})

	return true


func _decode_chunked_body(data: String):
	# Decode chunked transfer encoding
	# Returns null if more data is needed, or the decoded body string
	var result = ""
	var pos = 0

	while pos < data.length():
		# Find chunk size line end
		var line_end = data.find("\r\n", pos)
		if line_end == -1:
			return null  # Need more data

		# Parse chunk size (hex)
		var size_str = data.substr(pos, line_end - pos).strip_edges()
		# Remove any chunk extensions
		var semicolon = size_str.find(";")
		if semicolon != -1:
			size_str = size_str.substr(0, semicolon)

		var chunk_size = size_str.hex_to_int()

		if chunk_size == 0:
			# Last chunk - check for trailer and final CRLF
			return result

		# Check if we have the full chunk
		var chunk_start = line_end + 2
		var chunk_end = chunk_start + chunk_size

		if chunk_end + 2 > data.length():
			return null  # Need more data

		# Extract chunk data
		result += data.substr(chunk_start, chunk_size)
		pos = chunk_end + 2  # Skip chunk data and trailing CRLF

	return null  # Need more data


func _close_client(client: StreamPeerTCP) -> void:
	if client in _clients:
		client.disconnect_from_host()
		_clients.erase(client)
		_pending_data.erase(client)
		if _debug_mode:
			print("[MCP] Client connection closed")


func _parse_http_headers(header_section: String) -> Dictionary:
	var result: Dictionary = {}
	var lines = header_section.split("\r\n")

	if lines.size() == 0:
		return result

	# Parse request line
	var request_line = lines[0].split(" ")
	if request_line.size() >= 2:
		result["method"] = request_line[0]
		result["path"] = request_line[1]

	# Parse headers
	for i in range(1, lines.size()):
		var line = lines[i]
		var colon_pos = line.find(":")
		if colon_pos > 0:
			var key = line.substr(0, colon_pos).strip_edges().to_lower()
			var value = line.substr(colon_pos + 1).strip_edges()
			result[key] = value

	return result


func _handle_mcp_post(client: StreamPeerTCP, body: String) -> void:
	if _debug_mode:
		print("[MCP] Parsing request body (%d bytes)..." % body.length())
		if body.length() < 500:
			print("[MCP] Body: %s" % body)

	var json = JSON.new()
	var error = json.parse(body)

	if error != OK:
		push_error("[MCP] JSON parse error: %s" % json.get_error_message())
		_send_json_response(client, 400, _create_json_rpc_error(-32700, "Parse error: %s" % json.get_error_message(), null))
		return

	var data = json.get_data()

	# JSON-RPC batch (allowed in protocol 2025-03-26, removed in 2025-06-18).
	# Accepted for compatibility with older clients.
	if data is Array:
		var responses: Array = []
		for message in data:
			var response = _dispatch_message(message)
			if response != null:
				responses.append(response)
		if responses.is_empty():
			# Only notifications/responses: acknowledge without a body.
			_send_empty_response(client, 202)
		else:
			_send_json_response(client, 200, responses)
		return

	var response = _dispatch_message(data)
	if response == null:
		# Notification or client response: Streamable HTTP requires
		# 202 Accepted with no body.
		_send_empty_response(client, 202)
	else:
		_send_json_response(client, 200, response)


func _dispatch_message(message) -> Variant:
	# Returns a JSON-RPC response Dictionary for requests, or null for
	# notifications and client responses (which must not be answered).
	if not message is Dictionary:
		return _create_json_rpc_error(-32600, "Invalid Request", null)

	var has_id = message.has("id")
	var id = _normalize_id(message.get("id")) if has_id else null
	var method = str(message.get("method", ""))

	# Messages without a method are client responses to server requests;
	# we never issue server requests, so just accept them silently.
	if method.is_empty():
		if message.has("result") or message.has("error"):
			return null
		return _create_json_rpc_error(-32600, "Invalid Request", id)

	var params = message.get("params")
	if not params is Dictionary:
		params = {}

	request_received.emit(method, params)

	# Notifications (no id) never get a JSON-RPC response. This covers
	# notifications/initialized, notifications/cancelled, etc.
	if not has_id:
		if _debug_mode:
			print("[MCP] Notification: %s" % method)
		return null

	if _debug_mode:
		print("[MCP] Method: %s, ID: %s" % [method, id])

	match method:
		"initialize":
			return _handle_initialize(params, id)
		"ping":
			return _create_json_rpc_response({}, id)
		"tools/list":
			return _handle_tools_list(params, id)
		"tools/call":
			return _handle_tools_call(params, id)
		_:
			return _create_json_rpc_error(-32601, "Method not found: %s" % method, id)


func _normalize_id(id):
	# Godot's JSON parser turns every number into a float, and stringify would
	# echo the id back as e.g. 0.0. JSON-RPC ids must round-trip unchanged
	# (Claude Code sends integers), so restore integral floats to int.
	if id is float and id == floor(id):
		return int(id)
	return id


func _handle_initialize(params: Dictionary, id) -> Dictionary:
	var requested_version = str(params.get("protocolVersion", ""))
	var negotiated_version = requested_version if requested_version in SUPPORTED_PROTOCOL_VERSIONS else LATEST_PROTOCOL_VERSION

	var result = {
		"protocolVersion": negotiated_version,
		"capabilities": {
			"tools": {
				"listChanged": false
			}
		},
		"serverInfo": {
			"name": SERVER_NAME,
			"title": "Godot MCP Server",
			"version": SERVER_VERSION
		}
	}
	return _create_json_rpc_response(result, id)


func _handle_tools_list(_params: Dictionary, id) -> Dictionary:
	var tools_list: Array[Dictionary] = []

	for tool_def in _tool_definitions:
		# Only include enabled tools
		if is_tool_enabled(tool_def["name"]):
			tools_list.append({
				"name": tool_def["name"],
				"description": tool_def.get("description", ""),
				"inputSchema": tool_def.get("inputSchema", {
					"type": "object",
					"properties": {}
				})
			})

	return _create_json_rpc_response({"tools": tools_list}, id)


func _handle_tools_call(params: Dictionary, id) -> Dictionary:
	var tool_name = params.get("name", "")
	var arguments = params.get("arguments", {})

	print("[MCP] Tool call: %s" % tool_name)

	if tool_name.is_empty():
		return _create_tool_response({"success": false, "error": "Missing tool name"}, id)

	# Check if tool is enabled
	if not is_tool_enabled(tool_name):
		return _create_tool_response({"success": false, "error": "Tool '%s' is disabled" % tool_name}, id)

	# Parse tool name: category_toolname
	var parts = tool_name.split("_", true, 1)
	if parts.size() < 2:
		return _create_tool_response({"success": false, "error": "Invalid tool name format: %s" % tool_name}, id)

	var category = parts[0]
	var actual_tool_name = parts[1]

	if _debug_mode:
		print("[MCP] Category: %s, Tool: %s" % [category, actual_tool_name])

	if not _tools.has(category):
		return _create_tool_response({"success": false, "error": "Unknown tool category: %s" % category}, id)

	var executor = _tools[category]
	var result: Dictionary

	# Execute with error handling
	result = executor.execute(actual_tool_name, arguments)

	if _debug_mode:
		print("[MCP] Tool result: success=%s" % result.get("success", false))

	return _create_tool_response(result, id)


func _create_tool_response(result: Dictionary, id) -> Dictionary:
	# Tool failures keep a valid JSON-RPC envelope and advertise their failure
	# to MCP clients instead of disguising errors as successful executions.
	var sanitized_result = _sanitize_for_json(result)
	var result_text = JSON.stringify(sanitized_result)

	if _debug_mode:
		print("[MCP] Tool response text length: %d" % result_text.length())

	return _create_json_rpc_response({
		"content": [{
			"type": "text",
			"text": result_text
		}],
		"isError": result.get("success", false) != true
	}, id)


func _create_json_rpc_response(result, id) -> Dictionary:
	return {
		"jsonrpc": "2.0",
		"result": result,
		"id": id
	}


func _create_json_rpc_error(code: int, message: String, id) -> Dictionary:
	return {
		"jsonrpc": "2.0",
		"error": {
			"code": code,
			"message": message
		},
		"id": id
	}


func _create_health_response() -> Dictionary:
	return {
		"status": "ok",
		"server": SERVER_NAME,
		"version": SERVER_VERSION,
		"running": _running,
		"connections": _clients.size()
	}


func _create_tools_list_response() -> Dictionary:
	return {
		"tools": _tool_definitions
	}


func _cors_headers() -> String:
	var headers = "Access-Control-Allow-Origin: *\r\n"
	headers += "Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\n"
	headers += "Access-Control-Allow-Headers: Content-Type, Accept, Authorization, X-Requested-With, Mcp-Session-Id, MCP-Protocol-Version, Last-Event-ID\r\n"
	headers += "Access-Control-Expose-Headers: Mcp-Session-Id, MCP-Protocol-Version\r\n"
	headers += "Access-Control-Max-Age: 86400\r\n"
	return headers


func _send_json_response(client: StreamPeerTCP, status_code: int, payload) -> void:
	# Sanitize data before JSON serialization
	var sanitized = _sanitize_for_json(payload)
	var body = JSON.stringify(sanitized)
	var body_bytes = body.to_utf8_buffer()

	var headers = "HTTP/1.1 %d %s\r\n" % [status_code, HTTP_STATUS_TEXT.get(status_code, "OK")]
	headers += "Content-Type: application/json\r\n"
	headers += "Content-Length: %d\r\n" % body_bytes.size()
	headers += _cors_headers()
	headers += "Connection: keep-alive\r\n"
	headers += "\r\n"

	var err1 = client.put_data(headers.to_utf8_buffer())
	var err2 = client.put_data(body_bytes)

	if _debug_mode:
		print("[MCP] Response sent: status=%d, size=%d bytes, errors=(h:%s, b:%s)" % [status_code, body_bytes.size(), err1, err2])


func _send_empty_response(client: StreamPeerTCP, status_code: int, extra_headers: Dictionary = {}) -> void:
	var headers = "HTTP/1.1 %d %s\r\n" % [status_code, HTTP_STATUS_TEXT.get(status_code, "OK")]
	for key in extra_headers:
		headers += "%s: %s\r\n" % [key, extra_headers[key]]
	# 204 must not carry a Content-Length header (RFC 9110); every other
	# bodyless status needs an explicit 0 so keep-alive clients can frame it.
	if status_code != 204:
		headers += "Content-Length: 0\r\n"
	headers += _cors_headers()
	headers += "Connection: keep-alive\r\n"
	headers += "\r\n"

	var err = client.put_data(headers.to_utf8_buffer())

	if _debug_mode:
		print("[MCP] Empty response sent: status=%d, error=%s" % [status_code, err])


func _sanitize_for_json(value):
	"""Recursively sanitize values to ensure valid JSON serialization"""
	match typeof(value):
		TYPE_DICTIONARY:
			var result = {}
			for key in value:
				# Ensure key is a string
				var str_key = str(key)
				result[str_key] = _sanitize_for_json(value[key])
			return result
		TYPE_ARRAY:
			var result = []
			for item in value:
				result.append(_sanitize_for_json(item))
			return result
		TYPE_FLOAT:
			# Handle NaN and Infinity which are not valid JSON
			if is_nan(value):
				return 0.0
			if is_inf(value):
				return 999999999.0 if value > 0 else -999999999.0
			return value
		TYPE_STRING:
			# Ensure string is valid
			return value
		TYPE_STRING_NAME:
			return str(value)
		TYPE_NODE_PATH:
			return str(value)
		TYPE_OBJECT:
			# Convert objects to string representation
			if value == null:
				return null
			return str(value)
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4:
			return str(value)
		TYPE_COLOR:
			return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}
		TYPE_NIL:
			return null
		_:
			return value
