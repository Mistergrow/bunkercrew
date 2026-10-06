extends SceneTree
## Authentication, Unicode bounds, deterministic replay and asynchronous drafts.
const Chat := preload("res://scripts/network_chat.gd")
const Messages := preload("res://scripts/network_messages.gd")
const Protocol := preload("res://scripts/network_protocol.gd")
const PeerState := preload("res://scripts/network_peer_state.gd")
class SessionProbe extends "res://scripts/network_session.gd":
	var packets: Array[Dictionary]=[]
	var sending := true
	func _send(message: Dictionary,reliable := true,target_id: int=0) -> bool:
		packets.append({"message":message.duplicate(true),"reliable":reliable,"target":target_id})
		return sending
class HudProbe extends Node:
	var scenario_options := ScenarioCatalog.validate({})
	var story_selected := false
class GameProbe extends Node:
	var started := false
	var selected_characters := ["mara","ivo","branko","nora"]
	var hud: HudProbe
var checks := 0
var failures := 0
var completions: Array[Dictionary]=[]

func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func row(sequence: int,text: String="hello",preset: String="") -> Dictionary:
	return {"id":sequence,"player_id":2,"name":"Crew Guest","text":text,"preset":preset,"time":float(sequence)}
func deliver(session: SessionProbe,message: Dictionary) -> void:
	var encoded := Protocol.encode(message)
	check(not encoded.is_empty(),"Chat fixture uses the bounded compressed transport envelope")
	session._receive_packet_message(Protocol.decode(encoded),0)
func latest_ack(session: SessionProbe) -> Dictionary:
	for index in range(session.packets.size()-1,-1,-1):
		if session.packets[index].message.kind=="chat_ack": return session.packets[index].message
	return {}

func _run() -> void:
	check(Chat.valid_text("ä🎵".repeat(120)),"240 Unicode codepoints including four-byte emoji are accepted")
	check(not Chat.valid_text("a".repeat(241)),"Messages above 240 codepoints are rejected")
	check(Chat.valid_text("👩‍🔧 [b]Danke[/b]"),"Emoji and literal formatting brackets remain plain text")
	for invalid in [""," ","\nhello","hello\tworld","a"+String.chr(127),"a"+String.chr(0x202E),"a"+String.chr(0x2066),"a"+String.chr(0x200B),"a"+String.chr(0x061C),"a"+String.chr(0x200F),"a"+String.chr(0x2060),"a"+String.chr(0xFEFF),42,null,{}]:
		check(not Chat.valid_text(invalid),"Empty, control, bidi and incorrectly typed content is rejected")
	check(Chat.valid_name("ä".repeat(24)) and not Chat.valid_name("a".repeat(25)),"Author names have their independent 24-codepoint bound")
	check(Chat.valid_name("",true) and not Chat.valid_name(""),"Optional local names retain a validated fallback")
	check(not Chat.valid_name(String.chr(0x200D)) and not Chat.valid_name(String.chr(0x200C)),"Invisible join controls cannot impersonate a blank participant name")
	for preset: String in Chat.PRESETS:
		check(Chat.valid_content("",preset),"Canonical preset "+preset+" travels without localized text")
	check(not Chat.valid_content("translated","ready") and not Chat.valid_content("","forged"),"Preset text and unknown preset IDs cannot override the canonical message")
	check(Messages.valid({"kind":"chat_send","request":1,"text":"test","preset":""},true),"Only a text or preset request is accepted from guests")
	check(not Messages.valid({"kind":"chat_send","request":1,"text":"test","preset":"","player_id":1},true),"A guest cannot append a forged author field")
	check(not Messages.valid({"kind":"chat_message","message":row(1)},true),"Guests cannot publish authoritative messages")
	for field in ["id","player_id","name","text","preset","time"]:
		var malformed := row(1)
		malformed.erase(field)
		check(not Chat.valid_row(malformed),"Missing message field "+field+" is rejected")
	for timestamp in [INF,NAN,-1.0,"now",null]:
		var malformed := row(1)
		malformed.time=timestamp
		check(not Chat.valid_row(malformed),"Non-finite and incorrectly typed timestamps are rejected")
	check(not Chat.valid_history([row(2),row(1)]) and not Chat.valid_history([row(1),row(1)]),"History must have strictly increasing unique IDs")
	var store := Chat.new()
	for sequence in 100: check(store.append_authoritative(row(sequence+1)),"Authoritative sequence %d is accepted"%(sequence+1))
	check(store.history.size()==80 and store.history[0].id==21 and store.highest_id==100,"History retains exactly the latest 80 authoritative rows")
	check(not store.append_authoritative(row(100)) and not store.append_authoritative(row(20)),"Duplicated and old replay cannot insert or evict rows")
	var forged_history := store.history.duplicate(true)
	forged_history.append(row(101))
	check(not Chat.valid_history(forged_history),"An oversized history envelope is rejected before application")
	check(store.allow_sender("slot:2",0.0) and store.allow_sender("slot:2",0.0) and store.allow_sender("slot:2",0.0) and not store.allow_sender("slot:2",0.0),"Each author has a three-message burst")
	check(store.allow_sender("slot:3",0.0) and not store.allow_sender("slot:2",0.99) and store.allow_sender("slot:2",1.0),"Authors have independent one-message-per-second sustained budgets")
	var game := GameProbe.new()
	game.hud=HudProbe.new()
	game.add_child(game.hud)
	root.add_child(game)
	var host := SessionProbe.new()
	game.add_child(host)
	host.set_process(false)
	host.set_physics_process(false)
	host.game=game
	host.active=true
	host.is_host=true
	host.state="lobby"
	host._invite_secret="a".repeat(16)
	host.set_display_name("Crew Host")
	check(not host.set_display_name("\nSpoof") and not host.set_display_name("x".repeat(25)),"The local name setter rejects controls and overlong names")
	check(host.chat_available() and host.send_chat("  Welcome 🎵  "),"An open host lobby accepts trimmed Unicode text before guests arrive")
	check(host.chat_history[0].player_id==1 and host.chat_history[0].name=="Crew Host" and host.chat_history[0].text=="Welcome 🎵","Host text is stamped with its actual author and normalized edges")
	var peer := PeerState.create(0.0)
	peer.wire=37
	host._peers[37]=peer
	host._enter_peer(37)
	deliver(host,{"kind":"chat_send","request":1,"text":"unauthenticated","preset":""})
	check(host.chat_history.size()==1,"A connected peer cannot chat before game authentication")
	deliver(host,{"kind":"hello","version":Protocol.VERSION,"build":Protocol.BUILD,"world_revision":Protocol.WORLD_REVISION, "content_fingerprint":preload("res://scripts/content_registry.gd").fingerprint(),"resume":"","invite":host._invite_secret,"name":"Crew Guest"})
	check(host._peers[37]._authenticated and host._peers[37].slot==2,"The actual hello validator authenticates the named guest")
	check(host.packets.any(func(packet):return packet.message.kind=="chat_history" and packet.message.messages.size()==1 and packet.reliable),"Welcome is followed by reliable recent history for an authenticated join")
	check(host.chat_names=={"1":"Crew Host","2":"Crew Guest"},"Lobby names are derived from actual authenticated participants")
	deliver(host,{"kind":"chat_send","request":1,"text":"[b]plain[/b] 🎵","preset":""})
	check(host.chat_history.size()==2 and host.chat_history[-1].player_id==2 and host.chat_history[-1].name=="Crew Guest","The host assigns the actual guest author and keeps text literal")
	check(latest_ack(host).accepted and host.packets.filter(func(packet):return packet.message.kind=="chat_message").all(func(packet):return packet.reliable and packet.target==-1),"Messages use reliable authenticated broadcast and author receives an ACK")
	deliver(host,{"kind":"chat_send","request":1,"text":"[b]plain[/b] 🎵","preset":""})
	check(host.chat_history.size()==2 and latest_ack(host).accepted,"An identical request repeats its receipt without appending a duplicate")
	deliver(host,{"kind":"chat_send","request":1,"text":"edited old request","preset":""})
	check(host.chat_history.size()==2 and latest_ack(host).error_code=="stale","An edited request cannot reuse an accepted ID")
	deliver(host,{"kind":"chat_send","request":2,"text":"","preset":"help"})
	deliver(host,{"kind":"chat_send","request":3,"text":"last allowed","preset":""})
	check(host.chat_history[-2].preset=="help" and host.chat_history[-2].text.is_empty(),"The host broadcasts the canonical preset ID")
	var count := host.chat_history.size()
	deliver(host,{"kind":"chat_send","request":4,"text":"rate rejected","preset":""})
	check(host.chat_history.size()==count and latest_ack(host).error_code=="rate","Excess valid requests receive a bounded rate rejection")
	for index in 30: deliver(host,{"kind":"chat_send","request":5+index,"text":"spam","preset":""})
	check(host.chat_history.size()==count and host._allow_message("input"),"Chat flood cannot append unbounded history or consume the input budget")
	host._leave_peer()
	var token: String=host._slots[2]._guest_token
	var receipt_id: int=host._slots[2].chat_receipt.request
	host._slots[2].connected=false
	host._peers.erase(37)
	var resumed := PeerState.create(0.0)
	resumed.wire=38
	host._peers[38]=resumed
	host._enter_peer(38)
	deliver(host,{"kind":"hello","version":Protocol.VERSION,"build":Protocol.BUILD,"world_revision":Protocol.WORLD_REVISION, "content_fingerprint":preload("res://scripts/content_registry.gd").fingerprint(),"resume":token,"invite":host._invite_secret,"name":"Returning Guest"})
	check(host._peers[38].slot==2 and host._peers[38].chat_receipt.request==receipt_id,"A reconnect retains the last receipt under the authenticated slot")
	check(latest_ack(host).request==receipt_id and latest_ack(host).error_code=="rate","Reconnect replays the last request result alongside authoritative history")
	deliver(host,{"kind":"chat_send","request":receipt_id+1,"text":"reconnect spam","preset":""})
	check(host.chat_history.size()==count and latest_ack(host).error_code=="rate","Reconnection cannot reset the host's per-slot spam budget")
	host._leave_peer()
	var guest := SessionProbe.new()
	game.add_child(guest)
	guest.set_process(false)
	guest.set_physics_process(false)
	guest.game=game
	guest.active=true
	guest.state="lobby"
	guest.peer_connected=true
	guest._authenticated=true
	guest.chat_send_completed.connect(func(text: String,accepted: bool):completions.append({"text":text,"accepted":accepted,"pending_text":guest.chat_pending_text,"pending_draft":guest.chat_pending_draft}))
	guest.chat_draft="My pending draft"
	check(guest.send_chat(guest.chat_draft) and guest.chat_pending and completions.is_empty(),"Guest sending remains pending until the authoritative ACK")
	check(not guest.send_chat("second") and guest.chat_pending,"Only one pending draft may be submitted")
	deliver(guest,{"kind":"chat_ack","request":999,"accepted":true,"error_code":""})
	check(guest.chat_pending,"An unrelated ACK cannot erase the current draft")
	deliver(guest,{"kind":"chat_ack","request":1,"accepted":false,"error_code":"rate"})
	check(not guest.chat_pending and guest.chat_draft=="My pending draft" and not completions[-1].accepted and not guest.chat_error.is_empty(),"Rejected async sends retain their draft and report local feedback")
	guest._clock=5.0
	check(guest.send_chat("accepted"),"A later draft can be sent after rejection")
	deliver(guest,{"kind":"chat_message","message":row(2,"accepted")})
	deliver(guest,{"kind":"chat_ack","request":2,"accepted":true,"error_code":""})
	check(not guest.chat_pending and completions[-1].accepted and guest.chat_error.is_empty(),"An accepted ACK completes the actual text without an error")
	deliver(guest,{"kind":"chat_history","messages":[row(1),row(2,"accepted"),row(3)]})
	check(guest.chat_history.size()==2 and guest.chat_history[0].id==2 and guest.chat_history[1].id==3,"An overlapping replay preserves current messages and deduplicates accepted IDs")
	guest.game=null
	deliver(guest,{"kind":"chat_message","message":row(4,"Between scenes")})
	check(guest.chat_history[-1].text=="Between scenes","Authenticated room chat is retained while the mission node is absent")
	guest.game=game
	host.game=null
	host._enter_peer(38)
	deliver(host,{"kind":"chat_name","name":"Name during reload"})
	for index in 35: host._receive_packet_message({"kind":"chat_name","name":"Name during reload"},0)
	check(host._deferred_room_packets.size()==32,"Reliable world-dependent controls have a bounded queue during a scene replacement")
	host._receive_input({"kind":"input","generation":1,"seq":1,"input":{}})
	host.game=game
	host._flush_room_packets()
	check(host._deferred_room_packets.is_empty() and host._slots[2].chat_name=="Name during reload","The new scene safely applies queued room controls with their original authenticated peer context")
	host._clock=5.0
	host._enter_peer(38)
	var lobby_packets_before: int=host.packets.filter(func(packet):return packet.message.kind=="lobby").size()
	for value in ["First name","Second name","Third name","Latest name"]:
		deliver(host,{"kind":"chat_name","name":value})
	check(host._slots[2].chat_name=="Second name" and host._slots[2].chat_pending_name=="Latest name","Names beyond the two-update burst retain only the latest validated desired value")
	check(is_equal_approx(host._slots[2].chat_pending_name_at,7.0),"Repeated excess renames do not extend the pending reconciliation deadline")
	host._leave_peer()
	host._clock=6.9
	host._flush_chat_names()
	check(host._slots[2].chat_name=="Second name","Coalesced names wait for their normal sustained-rate budget")
	host._clock=7.1
	host._flush_chat_names()
	var lobby_packets_after: int=host.packets.filter(func(packet):return packet.message.kind=="lobby").size()
	check(host._slots[2].chat_name=="Latest name" and host._slots[2].chat_pending_name==null and lobby_packets_after-lobby_packets_before==3,"Host reconciliation eventually applies the final name with exactly one additional bounded lobby broadcast")
	host._enter_peer(38)
	deliver(host,{"kind":"chat_name","name":"Canceled pending name"})
	deliver(host,{"kind":"chat_name","name":"Latest name"})
	check(host._slots[2].chat_pending_name==null,"Reverting to the actual authoritative name cancels an obsolete pending rename")
	host._leave_peer()
	host._clock=10.0
	host._flush_chat_names()
	host._enter_peer(38)
	deliver(host,{"kind":"chat_name","name":"Latest name"})
	check(host.packets.filter(func(packet):return packet.message.kind=="lobby").size()==lobby_packets_after,"Repeating an already applied name cannot generate lobby broadcasts")
	host._leave_peer()
	guest.sending=false
	check(not guest.send_chat("transport fail") and not guest.chat_pending and guest.chat_draft=="My pending draft","An immediate transport failure retains the draft and does not leave a pending send")
	guest.sending=true
	guest._clock=10.0
	check(guest.send_chat("timed out"),"Timeout fixture first queues a real valid request")
	guest.game=null
	guest._clock += 8.1
	guest._process(0.0)
	check(not guest.chat_pending and not completions[-1].accepted and completions[-1].text=="timed out" and guest.chat_draft=="My pending draft","A missing ACK times out with the original draft and a failed completion")
	guest.game=game
	guest._clock+=5.0
	check(guest.send_chat("  closing  ") and guest.chat_pending_text=="closing" and guest.chat_pending_draft=="  closing  ","Pending send exposes normalized text and original draft across UI reconstruction")
	guest.leave()
	check(not guest.chat_pending and not completions[-1].accepted and guest.chat_history.is_empty(),"Leaving ends a pending send and clears this room's history")
	check(completions[-1].pending_text=="closing" and completions[-1].pending_draft=="  closing  " and guest.chat_pending_text.is_empty() and guest.chat_pending_draft.is_empty(),"Completion observers see original pending text before the session clears it")
	var chain := SessionProbe.new()
	game.add_child(chain)
	chain.set_process(false)
	chain.set_physics_process(false)
	chain.game=game
	chain.active=true
	chain.state="lobby"
	chain.peer_connected=true
	chain._authenticated=true
	chain.chat_send_completed.connect(func(text: String,accepted: bool):
		if accepted and text=="first": chain.send_chat("  next  "))
	check(chain.send_chat("first"),"A completion listener starts with a submitted draft")
	deliver(chain,{"kind":"chat_ack","request":1,"accepted":true,"error_code":""})
	check(chain.chat_pending and chain.chat_pending_text=="next" and chain.chat_pending_draft=="  next  " and chain._chat_waiting.request==2,"A synchronous completion listener cannot have its next draft metadata cleared by the old completion")
	deliver(chain,{"kind":"chat_ack","request":2,"accepted":true,"error_code":""})
	check(not chain.chat_pending and chain.chat_pending_text.is_empty(),"The reentrant next draft still completes normally")
	var gap := SessionProbe.new()
	game.add_child(gap)
	gap.set_process(false)
	gap.set_physics_process(false)
	gap.game=game
	gap.active=true
	gap.state="playing"
	gap.peer_connected=true
	gap._authenticated=true
	gap.chat_draft="  Confirmation in the scene gap  "
	check(gap.send_chat(gap.chat_draft),"A raw spaced draft is submitted before its UI is absent")
	gap.game=null
	deliver(gap,{"kind":"chat_message","message":row(1,"Confirmation in the scene gap")})
	deliver(gap,{"kind":"chat_ack","request":1,"accepted":true,"error_code":""})
	check(not gap.chat_pending and gap.chat_draft.is_empty() and gap.chat_history[0].text=="Confirmation in the scene gap","Accepted ACK without any UI clears the exact raw draft while keeping the normalized authoritative message")
	gap.chat_draft="  Earlier draft  "
	check(gap.send_chat(gap.chat_draft),"An edited-draft fixture submits its original spaced text")
	gap.chat_draft="A newer unsent draft Ω"
	deliver(gap,{"kind":"chat_ack","request":2,"accepted":true,"error_code":""})
	check(gap.chat_draft=="A newer unsent draft Ω","An ACK received without UI never clears text edited after submission")
	check(gap.send_chat_preset("thanks"),"A canonical preset can be sent while a free-text draft is stored")
	deliver(gap,{"kind":"chat_ack","request":3,"accepted":true,"error_code":""})
	check(gap.chat_draft=="A newer unsent draft Ω","Preset acceptance without UI leaves the free-text draft untouched")
	gap.game=game
	check(host.chat_history.size()==count,"Another peer leaving cannot mutate the host history")
	host.chat_draft="  Host confirmation  "
	check(host.send_chat(host.chat_draft) and host.chat_draft.is_empty(),"Synchronous host acceptance also owns clearing its unchanged raw persisted draft")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Session and fixture nodes release cleanly")
	print("NETWORK CHAT: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
