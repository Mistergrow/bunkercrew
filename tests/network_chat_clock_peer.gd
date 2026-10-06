extends "res://tests/network_chat_peer.gd"
## Observe the actual chat/reconnect fixture without changing its timeouts.
var _probe_last_usec := 0
var _probe_last_report_usec := 0
var _probe_engine_elapsed := 0.0
var _probe_previous_state := ""
var _probe_max_wall := 0.0
var _probe_max_delta := 0.0
var _probe_stalled := false

func _process(delta: float) -> bool:
	var now := Time.get_ticks_usec()
	var wall_delta := float(now - _probe_last_usec) / 1000000.0 if _probe_last_usec > 0 else 0.0
	_probe_last_usec = now
	_probe_engine_elapsed += delta
	_probe_max_wall = maxf(_probe_max_wall, wall_delta)
	_probe_max_delta = maxf(_probe_max_delta, delta)
	if not is_instance_valid(game) or not is_instance_valid(game.network): return false
	var session = game.network
	var current_state := str(session.state)
	if now - _probe_last_report_usec >= 250000 or current_state != _probe_previous_state or wall_delta > 0.25 or delta > 0.25:
		_probe_last_report_usec = now
		_probe_previous_state = current_state
		var socket_state: int = -1 if session._websocket == null else session._websocket.get_ready_state()
		print("NETWORK_CLOCK ", JSON.stringify({"role":role, "wall_seconds":float(now) / 1000000.0, "wall_delta":wall_delta, "engine_delta":delta, "engine_elapsed":_probe_engine_elapsed, "network_clock":session._clock, "state":current_state, "paused":paused, "socket":socket_state, "relay_action":session._relay_action, "authenticated":session._authenticated, "hello_sent":session._hello_sent, "reconnect_deadline":session._reconnect_deadline, "retry_at":session._retry_at, "max_wall_delta":_probe_max_wall, "max_engine_delta":_probe_max_delta}))
	var stall_ms := OS.get_environment("BUNKERCREW_CLOCK_STALL_MS").to_int()
	if slot == 2 and current_state == "reconnecting" and not _probe_stalled and stall_ms > 0:
		_probe_stalled = true
		OS.delay_msec(mini(stall_ms, 4000))
	return false
