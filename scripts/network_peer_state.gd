extends RefCounted
## Independent authenticated link state. NetworkSession enters one link only
## while processing its packet/timer, then publishes its input by player slot.
const FIELDS := ["ping_ms","_guest_token","_authenticated","_last_input_at","_last_packet_at","_remote_seq","_snapshot_seq","_snapshot_ack","_pending_remote","_input_edges","_pressed","_released","_ready_for_snapshots","_command_window","_command_count","_handshake_deadline","_rejecting","_voice_highest","_voice_seen","_packet_budgets","_invalid_packets","_pong_at","remote_input"]

static func create(now: float) -> Dictionary:
	return {"ping_ms":0,"slot":0,"wire":0,"connected":true,"chat_name":"","chat_pending_name":null,"chat_pending_name_at":0.0,"chat_receipt":{},"_guest_token":Crypto.new().generate_random_bytes(24).hex_encode(),"_authenticated":false,"_last_input_at":-100.0,"_last_packet_at":now,"_remote_seq":-1,"_snapshot_seq":0,"_snapshot_ack":0,"_pending_remote":{},"_input_edges":[],"_pressed":[],"_released":[],"_ready_for_snapshots":false,"_command_window":now,"_command_count":0,"_handshake_deadline":now+5.0,"_rejecting":false,"_voice_highest":-1,"_voice_seen":{},"_packet_budgets":{},"_invalid_packets":0,"_pong_at":-1.0,"remote_input":{}}
