#!/usr/bin/env python3
"""Real sockets and durable databases: consent, privacy, lifecycle and abuse."""
from __future__ import annotations
import asyncio
import contextlib
import dataclasses
import hashlib
import hmac
import json
from pathlib import Path
import secrets
import sqlite3
import sys
import tempfile
import time
import unittest

from aiohttp import ClientSession, WSMsgType, WSServerHandshakeError
from aiohttp.test_utils import TestServer

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"server"))
from relay import Settings, create_app, GAME_BUILD, RELAY_KEY
from social import SOCIAL_KEY, MAX_FRIENDS, MAX_INVITES, SocialError, Store, safe_name, safe_relay_url, safe_room_code


class SocialIntegration(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="bunkercrew-social-test-")
        self.database = str(Path(self.directory.name)/"social.sqlite3")
        self.clients = ClientSession()
        self.servers = []
        self.sockets = []
        self.server = await self.start_server()

    async def asyncTearDown(self):
        for socket in self.sockets:
            await socket.close()
        await self.clients.close()
        for server in self.servers:
            await server.close()
        self.directory.cleanup()

    async def start_server(self,**changes):
        server = TestServer(create_app(dataclasses.replace(Settings(social_db=self.database),**changes)))
        await server.start_server()
        self.servers.append(server)
        return server

    async def receive(self,socket,operation=None,predicate=None,timeout=3):
        deadline = time.monotonic()+timeout
        while time.monotonic()<deadline:
            message = await asyncio.wait_for(socket.receive(),deadline-time.monotonic())
            self.assertEqual(message.type,WSMsgType.TEXT,message)
            value = json.loads(message.data)
            if (operation is None or value["op"]==operation) and (predicate is None or predicate(value)):
                return value
        self.fail("Expected social response did not arrive")

    async def connect(self,name="Mara",secret=None,server=None):
        socket = await self.clients.ws_connect((server or self.server).make_url("/social"))
        self.sockets.append(socket)
        credential = secret or secrets.token_hex(32)
        await socket.send_json({"op":"auth","version":1,"build":GAME_BUILD,"secret":credential,"name":name})
        ready = await self.receive(socket,"ready")
        return socket,ready,credential

    async def command(self,socket,operation,**values):
        await socket.send_json({"op":operation,**values})

    async def mutual(self):
        first,a,secret_a = await self.connect("Mara")
        second,b,secret_b = await self.connect("Ivo")
        await self.command(first,"add_friend",code=b["code"])
        request = await self.receive(second,"state",lambda value:len(value["requests"])==1)
        self.assertEqual(request["friends"],[])
        self.assertEqual(set(request["requests"][0]),{"code","name"})
        await self.command(second,"accept_friend",code=a["code"])
        await self.receive(first,"state",lambda value:len(value["friends"])==1)
        await self.receive(second,"state",lambda value:len(value["friends"])==1)
        return first,a,secret_a,second,b,secret_b

    async def room(self):
        host = await self.clients.ws_connect(self.server.make_url("/ws"))
        self.sockets.append(host)
        await host.send_json({"op":"host","version":1,"build":GAME_BUILD,"name":"Mara"})
        hosted = await self.receive(host,"hosted")
        self.assertEqual(len(hosted["code"]),6)
        return host,hosted

    async def lobby(self,socket,hosted):
        await self.command(socket,"presence",data={"status":"lobby","environment":"ash_foundry","joinable":True,
            "room_code":hosted["code"],"relay_url":str(self.server.make_url("/ws")).replace("http://","ws://"),"room_token":hosted["resume_token"]})

    async def test_crossed_requests_require_explicit_acceptance(self):
        first,a,_ = await self.connect("Mara")
        second,b,_ = await self.connect("Ivo")
        await self.command(first,"add_friend",code=b["code"])
        await self.receive(second,"state",lambda value:bool(value["requests"]))
        await self.command(second,"add_friend",code=a["code"])
        a_pending = await self.receive(first,"state",lambda value:bool(value["requests"]))
        b_pending = await self.receive(second,"state",lambda value:bool(value["requests"]))
        self.assertEqual(a_pending["friends"],[])
        self.assertEqual(b_pending["friends"],[])
        await self.command(second,"accept_friend",code=a["code"])
        confirmed = await self.receive(first,"state",lambda value:bool(value["friends"]))
        self.assertEqual(confirmed["requests"],[])
        self.assertEqual(confirmed["friends"][0]["code"],b["code"])

    async def test_link_scoped_crew_attestation_cannot_be_forged_or_replayed_after_logout(self):
        owner,a,secret = await self.connect("Mara")
        verifier,b,_ = await self.connect("Ivo")
        self.assertEqual(len(a["peer_key"]),64)
        self.assertNotIn("peer_key",a["friends"])
        context = secrets.token_hex(24)
        proof = hmac.new(bytes.fromhex(a["peer_key"]),("bunkercrew-crew1:"+GAME_BUILD+":"+context+":"+a["code"]).encode(),hashlib.sha256).hexdigest()
        await self.command(verifier,"verify_crew",request="real:1",code=a["code"],context=context,proof=proof)
        actual = await self.receive(verifier,"crew_verified")
        self.assertEqual(actual,{"op":"crew_verified","request":"real:1","code":a["code"],"name":"Mara","valid":True})
        for request,values in [("forge:2",dict(proof="0"*64)),("wronglink:3",dict(context=secrets.token_hex(24))),("wrongcode:4",dict(code=b["code"]))]:
            await self.command(verifier,"verify_crew",request=request,**(dict(code=a["code"],context=context,proof=proof)|values))
            self.assertFalse((await self.receive(verifier,"crew_verified"))["valid"])
        await owner.close()
        await asyncio.sleep(.15)
        await self.command(verifier,"verify_crew",request="expired:5",code=a["code"],context=context,proof=proof)
        self.assertFalse((await self.receive(verifier,"crew_verified"))["valid"])
        _,renewed,_ = await self.connect("Mara",secret)
        self.assertEqual(renewed["code"],a["code"])
        self.assertNotEqual(renewed["peer_key"],a["peer_key"])
        await self.command(verifier,"verify_crew",request="expired:6",code=a["code"],context=context,proof=proof)
        self.assertFalse((await self.receive(verifier,"crew_verified"))["valid"])

    async def test_outgoing_requests_are_confirmed_persisted_and_revoked(self):
        first,a,credential = await self.connect("Mara")
        second,b,_ = await self.connect("Ivo")
        await self.command(first,"add_friend",code=b["code"])
        confirmed = await self.receive(first,"state",lambda value:bool(value["outgoing_requests"]))
        self.assertEqual(confirmed["outgoing_requests"],[{"code":b["code"],"name":"Ivo"}])
        await self.receive(second,"state",lambda value:bool(value["requests"]))
        await first.close()
        await asyncio.sleep(.15)
        renewed,ready,_ = await self.connect("Mara",credential)
        self.assertEqual(ready["outgoing_requests"],confirmed["outgoing_requests"])
        await self.command(second,"decline_friend",code=a["code"])
        removed = await self.receive(renewed,"state",lambda value:not value["outgoing_requests"])
        self.assertEqual(removed["friends"],[])
        await self.command(renewed,"add_friend",code=b["code"])
        await self.receive(renewed,"state",lambda value:bool(value["outgoing_requests"]))
        await self.command(renewed,"remove_friend",code=b["code"])
        await self.receive(renewed,"state",lambda value:not value["outgoing_requests"])
        await self.command(renewed,"add_friend",code=b["code"])
        await self.receive(renewed,"state",lambda value:bool(value["outgoing_requests"]))
        await self.command(second,"block_friend",code=a["code"])
        await self.receive(renewed,"state",lambda value:not value["outgoing_requests"])

    @staticmethod
    def direct_invite(address="127.0.0.1"):
        octets=[int(part) for part in address.split(".")]
        checksum=0xA7
        for octet in octets:
            checksum ^= octet
            for _ in range(8): checksum=((checksum<<1)^0x07)&255 if checksum&128 else (checksum<<1)&255
        value=(int.from_bytes(bytes(octets),"big")<<8)|checksum
        alphabet="23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
        return "".join(alphabet[(value>>shift)&31] for shift in range(35,-1,-5))+"23456789ABCDEFGH"

    async def advertise_direct(self,socket,code=None):
        direct=code or self.direct_invite()
        self.assertTrue(safe_room_code(direct,""))
        await self.command(socket,"presence",data={"status":"lobby","environment":"ash_foundry","joinable":True,"room_code":direct,"relay_url":""})
        state=await self.receive(socket,"state",lambda value:bool(value["room_alias"]))
        return state["room_alias"],direct

    async def resolve(self,socket,code):
        request=secrets.token_hex(16)
        await self.command(socket,"resolve_room",request=request,code=code)
        return await self.receive(socket,"room_resolved",lambda value:value["request"]==request)

    async def test_short_direct_alias_has_no_directory_and_rejects_stale_blocked_routes(self):
        host,a,_=await self.connect("Host")
        guest,b,_=await self.connect("Guest")
        alias,direct=await self.advertise_direct(host)
        self.assertEqual(len(alias),6)
        self.assertEqual(a["observed_address"],"")
        self.assertNotIn("room_code",b)
        route=await self.resolve(guest,alias)
        self.assertEqual((route["room_code"],route["relay_url"],route["error_code"]),(direct,"",""))
        self.assertGreater(route["expires"],time.time())
        await self.command(host,"presence",data={"status":"lobby","environment":"mountain_pass","joinable":True,"room_code":direct,"relay_url":""})
        stable=await self.receive(host,"state",lambda value:value["room_alias"]==alias)
        self.assertNotIn(direct,json.dumps(stable))
        await self.command(guest,"block_friend",code=a["code"])
        await self.receive(guest,"state",lambda value:bool(value["blocked"]))
        denied=await self.resolve(guest,alias)
        self.assertEqual((denied["room_code"],denied["error_code"]),("","room_unavailable"))
        await self.command(host,"presence",data={"status":"playing","environment":"ash_foundry","joinable":False,"room_code":"","relay_url":""})
        await self.receive(host,"state",lambda value:not value["room_alias"])
        self.assertEqual((await self.resolve(guest,alias))["room_code"],"")

    async def test_short_alias_expires_on_full_leave_and_deadline(self):
        host,_,_=await self.connect("Host")
        guest,_,_=await self.connect("Guest")
        alias,_=await self.advertise_direct(host)
        await self.command(host,"presence",data={"status":"lobby","environment":"ash_foundry","joinable":False,"room_code":"","relay_url":""})
        await self.receive(host,"state",lambda value:not value["room_alias"])
        self.assertEqual((await self.resolve(guest,alias))["error_code"],"room_unavailable")
        new_alias,_=await self.advertise_direct(host)
        self.server.app[SOCIAL_KEY].room_aliases[new_alias]["expires"]=time.time()-1
        self.assertEqual((await self.resolve(guest,new_alias))["error_code"],"room_unavailable")
        await self.command(host,"ping")
        await self.receive(host,"pong")
        await host.close()
        await asyncio.sleep(.15)
        self.assertEqual((await self.resolve(guest,new_alias))["error_code"],"room_unavailable")
        self.assertFalse(self.server.app[SOCIAL_KEY].room_aliases)

    async def test_short_alias_rate_and_payloads_remain_bounded(self):
        host,_,_=await self.connect("Host")
        guest,_,_=await self.connect("Guest")
        alias,_=await self.advertise_direct(host)
        results=[await self.resolve(guest,alias) for _ in range(8)]
        self.assertTrue(any(value["error_code"]=="rate_limited" for value in results))
        self.assertTrue(all(not value["room_code"] for value in results if value["error_code"]))
        await self.command(guest,"resolve_room",request=secrets.token_hex(16),code="TOOLONG")
        self.assertEqual((await self.receive(guest,"error"))["code"],"invalid_request")
        await self.command(host,"ping")
        self.assertEqual(await self.receive(host,"pong"),{"op":"pong"})

    async def test_expired_alias_state_and_renewal_reach_the_host(self):
        host,_,_=await self.connect("Host")
        guest,_,_=await self.connect("Guest")
        alias,direct=await self.advertise_direct(host)
        service=self.server.app[SOCIAL_KEY]
        # A healthy heartbeat preserves the alias and sends no redundant state.
        await self.command(host,"ping")
        await self.receive(host,"pong")
        with self.assertRaises(asyncio.TimeoutError):
            await asyncio.wait_for(host.receive(),.15)
        self.assertEqual(service.profile_aliases[next(iter(service.profile_aliases))],alias)
        service.room_aliases[alias]["expires"]=time.time()-1
        await self.receive(host,"state",lambda value:not value["room_alias"],timeout=2)
        self.assertEqual((await self.resolve(guest,alias))["error_code"],"room_unavailable")
        await self.command(host,"ping")
        await self.receive(host,"pong")
        renewed=await self.receive(host,"state",lambda value:bool(value["room_alias"]))
        fresh=renewed["room_alias"]
        self.assertNotEqual(fresh,alias)
        self.assertEqual((await self.resolve(guest,fresh))["room_code"],direct)
        # Expiry before the sweeper's next iteration also creates and announces
        # a new alias, rather than silently reviving an already invalid code.
        service.room_aliases[fresh]["expires"]=time.time()-1
        await self.command(host,"ping")
        await self.receive(host,"pong")
        immediate=await self.receive(host,"state",lambda value:bool(value["room_alias"]))
        self.assertNotEqual(immediate["room_alias"],fresh)
        self.assertEqual((await self.resolve(guest,immediate["room_alias"]))["room_code"],direct)

    async def test_consent_privacy_and_no_global_directory(self):
        first,a,_ = await self.connect()
        second,b,_ = await self.connect("Ivo")
        stranger,c,_ = await self.connect("Nora")
        await self.command(first,"presence",data={"status":"playing","environment":"mountain_pass","joinable":False,"room_code":"","relay_url":""})
        await self.command(first,"add_friend",code=b["code"])
        request = await self.receive(second,"state",lambda value:bool(value["requests"]))
        self.assertEqual(request["friends"],[])
        self.assertNotIn("room_code",request["requests"][0])
        await self.command(stranger,"list")
        self.assertEqual((await self.receive(stranger,"error"))["code"],"invalid_request")
        await self.command(stranger,"invite",code=a["code"])
        self.assertEqual((await self.receive(stranger,"error"))["code"],"not_friends")
        await self.command(second,"accept_friend",code=a["code"])
        state = await self.receive(second,"state",lambda value:bool(value["friends"]))
        self.assertEqual(state["friends"][0]["status"],"playing")
        self.assertEqual(set(state["friends"][0]),{"code","name","status","environment","joinable"})

    async def test_real_relay_invitation_and_fast_latest_presence(self):
        first,a,_,second,b,_ = await self.mutual()
        host,hosted = await self.room()
        await self.command(first,"presence",data={"status":"menu","environment":"","joinable":False,"room_code":"","relay_url":""})
        await self.lobby(first,hosted)  # Deliberately within the 200 ms window.
        await self.command(first,"invite",code=b["code"])
        state = await self.receive(second,"state",lambda value:bool(value["invitations"]))
        invite = state["invitations"][0]
        self.assertEqual(invite["room_code"],hosted["code"])
        self.assertEqual(invite["from_code"],a["code"])
        self.assertNotIn("room_token",invite)
        self.assertNotIn(hosted["resume_token"],json.dumps(state))
        self.assertTrue(state["friends"][0]["joinable"])
        await self.command(second,"take_invite",id=invite["id"])
        await self.receive(second,"state",lambda value:not value["invitations"])

    async def test_quick_lobby_change_replaces_old_invitation_route(self):
        first,a,_,second,b,_ = await self.mutual()
        old_host,old_room = await self.room()
        await self.lobby(first,old_room)
        await self.command(first,"invite",code=b["code"])
        old_state = await self.receive(second,"state",lambda value:bool(value["invitations"]))
        old_invite = old_state["invitations"][0]
        new_host,new_room = await self.room()
        self.assertNotEqual(old_room["code"],new_room["code"])
        await self.lobby(first,new_room)  # No intermediate menu/offline status.
        await self.command(first,"invite",code=b["code"])
        new_state = await self.receive(second,"state",lambda value:bool(value["invitations"]) and value["invitations"][0]["room_code"]==new_room["code"])
        self.assertEqual(len(new_state["invitations"]),1)
        self.assertNotEqual(new_state["invitations"][0]["id"],old_invite["id"])
        await self.command(second,"take_invite",id=old_invite["id"])
        self.assertEqual((await self.receive(second,"error"))["code"],"invite_expired")

    async def test_host_room_ownership_capacity_and_started_guards(self):
        first,a,_,second,b,_ = await self.mutual()
        host,hosted = await self.room()
        forged = dict(hosted,resume_token=secrets.token_urlsafe(24))
        await self.lobby(first,forged)
        await self.command(first,"invite",code=b["code"])
        self.assertEqual((await self.receive(first,"error"))["code"],"not_joinable")
        await self.lobby(first,hosted)
        await host.send_json({"op":"status","started":True})
        await self.receive(host,"status")
        await self.command(first,"invite",code=b["code"])
        self.assertEqual((await self.receive(first,"error"))["code"],"not_joinable")
        await host.send_json({"op":"status","started":False})
        await self.receive(host,"status")
        for index in range(3):
            guest = await self.clients.ws_connect(self.server.make_url("/ws"))
            self.sockets.append(guest)
            await guest.send_json({"op":"join","version":1,"build":GAME_BUILD,"name":"Guest","code":hosted["code"]})
            await self.receive(guest,"joined")
        await self.command(first,"invite",code=b["code"])
        self.assertEqual((await self.receive(first,"error"))["code"],"not_joinable")

    async def test_block_revokes_both_sides_requests_and_invites(self):
        first,a,_,second,b,_ = await self.mutual()
        host,hosted = await self.room()
        await self.lobby(first,hosted)
        await self.command(first,"invite",code=b["code"])
        await self.receive(second,"state",lambda value:bool(value["invitations"]))
        await self.command(second,"block_friend",code=a["code"])
        blocked = await self.receive(second,"state",lambda value:bool(value["blocked"]))
        self.assertEqual(blocked["friends"],[])
        self.assertEqual(blocked["invitations"],[])
        await self.receive(first,"state",lambda value:not value["friends"])
        await self.command(first,"add_friend",code=b["code"])
        self.assertEqual((await self.receive(first,"error"))["code"],"not_found")
        await self.command(second,"unblock_friend",code=a["code"])
        state = await self.receive(second,"state",lambda value:not value["blocked"])
        self.assertEqual(state["friends"],[])  # Explicit fresh consent is required.

    async def test_pending_request_can_be_declined_removed_and_blocked(self):
        first,a,_ = await self.connect()
        second,b,_ = await self.connect("Ivo")
        await self.command(first,"add_friend",code=b["code"])
        await self.receive(second,"state",lambda value:bool(value["requests"]))
        await self.command(second,"decline_friend",code=a["code"])
        await self.receive(second,"state",lambda value:not value["requests"])
        await self.command(first,"add_friend",code=b["code"])
        await self.receive(second,"state",lambda value:bool(value["requests"]))
        await self.command(second,"block_friend",code=a["code"])
        state = await self.receive(second,"state",lambda value:bool(value["blocked"]))
        self.assertEqual(state["requests"],[])

    async def test_stable_credentials_durable_relationships_and_database_restart(self):
        first,a,secret_a,second,b,secret_b = await self.mutual()
        third,c,secret_c = await self.connect("Nora")
        await self.command(first,"add_friend",code=c["code"])
        await self.receive(third,"state",lambda value:bool(value["requests"]))
        await self.command(second,"block_friend",code=c["code"])
        await self.receive(second,"state",lambda value:bool(value["blocked"]))
        await self.server.close()
        reopened = await self.start_server()
        new_a,ready_a,_ = await self.connect("Ignored input name",secret_a,reopened)
        new_b,ready_b,_ = await self.connect("Ivo",secret_b,reopened)
        new_c,ready_c,_ = await self.connect("Nora",secret_c,reopened)
        self.assertEqual(ready_a["code"],a["code"])
        self.assertEqual(ready_a["name"],"Mara")
        self.assertEqual(ready_a["friends"][0]["code"],b["code"])
        self.assertEqual(ready_b["blocked"][0]["code"],c["code"])
        self.assertEqual(ready_c["requests"][0]["code"],a["code"])
        def inspect():
            with contextlib.closing(sqlite3.connect(self.database)) as database:
                return database.execute("SELECT secret_hash FROM profiles").fetchall()
        hashes = await asyncio.to_thread(inspect)
        self.assertIn((hashlib.sha256(bytes.fromhex(secret_a)).hexdigest(),),hashes)
        self.assertNotIn(secret_a,repr(hashes))

    async def test_second_login_cannot_take_over_and_reconnect_clears_old_presence(self):
        first,a,secret_a,second,b,_ = await self.mutual()
        duplicate = await self.clients.ws_connect(self.server.make_url("/social"))
        self.sockets.append(duplicate)
        await duplicate.send_json({"op":"auth","version":1,"build":GAME_BUILD,"secret":secret_a,"name":"Hijack"})
        self.assertEqual((await self.receive(duplicate,"error"))["code"],"session_replaced")
        await self.command(first,"ping")
        await self.receive(first,"pong")
        await first.close()
        offline = await self.receive(second,"state",lambda value:value["friends"][0]["status"]=="offline")
        self.assertFalse(offline["friends"][0]["joinable"])
        replacement,ready,_ = await self.connect("Mara",secret_a)
        self.assertEqual(ready["code"],a["code"])
        self.assertEqual(ready["friends"][0]["status"],"menu")

    async def test_invites_expire_and_room_changes_revoke_old_codes(self):
        first,a,_,second,b,_ = await self.mutual()
        host,hosted = await self.room()
        await self.lobby(first,hosted)
        await self.command(first,"invite",code=b["code"])
        state = await self.receive(second,"state",lambda value:bool(value["invitations"]))
        identity = state["invitations"][0]["id"]
        self.server.app[SOCIAL_KEY].invites[identity]["expires"] = time.time()-1
        await self.receive(second,"state",lambda value:not value["invitations"])
        await self.command(second,"take_invite",id=identity)
        self.assertEqual((await self.receive(second,"error"))["code"],"invite_expired")
        await self.command(first,"invite",code=b["code"])
        state = await self.receive(second,"state",lambda value:bool(value["invitations"]))
        identity = state["invitations"][0]["id"]
        await self.command(first,"presence",data={"status":"playing","environment":"ash_foundry","joinable":False,"room_code":"","relay_url":""})
        await self.receive(second,"state",lambda value:not value["invitations"])
        await self.command(second,"take_invite",id=identity)
        self.assertEqual((await self.receive(second,"error"))["code"],"invite_expired")

    async def test_invalid_json_auth_and_sender_spoofing(self):
        socket = await self.clients.ws_connect(self.server.make_url("/social"))
        self.sockets.append(socket)
        await socket.send_str('{"op":"auth","op":"ping"}')
        self.assertEqual((await self.receive(socket,"error"))["code"],"invalid_request")
        await socket.send_json({"op":"auth","version":1,"build":"old-build","secret":secrets.token_hex(32),"name":"Mara"})
        self.assertEqual((await self.receive(socket,"error"))["code"],"version_mismatch")
        first,a,_,second,b,_ = await self.mutual()
        await self.command(first,"invite",code=b["code"],from_code=b["code"])
        self.assertEqual((await self.receive(first,"error"))["code"],"invalid_request")
        await self.command(first,"name",name="Mara\u202ename")
        self.assertEqual((await self.receive(first,"error"))["code"],"invalid_name")
        await first.send_str('{"op":"presence","data":{"status":"menu","environment":"","joinable":NaN}}')
        self.assertEqual((await self.receive(first,"error"))["code"],"invalid_request")

    async def test_spam_cannot_block_healthy_social_or_game_socket(self):
        spam,a,_ = await self.connect()
        healthy,b,_ = await self.connect("Ivo")
        host,hosted = await self.room()
        for _ in range(48):
            await spam.send_json({"op":"ping"})
        await self.command(healthy,"ping")
        await self.receive(healthy,"pong")
        await host.send_json({"op":"ping"})
        await self.receive(host,"pong")
        async def closed():
            while not spam.closed:
                message = await spam.receive()
                if message.type in (WSMsgType.CLOSE,WSMsgType.CLOSED,WSMsgType.ERROR):
                    return
        await asyncio.wait_for(closed(),3)
        self.assertLessEqual(len(self.server.app[SOCIAL_KEY].invites),MAX_INVITES)

    async def test_threaded_storage_does_not_stall_game_heartbeats(self):
        social,a,_ = await self.connect()
        host,hosted = await self.room()
        store = self.server.app[SOCIAL_KEY].store
        original = store._name
        def slow_name(*values):
            time.sleep(0.35)
            return original(*values)
        store._name = slow_name
        await self.command(social,"name",name="Mara II")
        await asyncio.sleep(0.02)
        before = time.monotonic()
        await host.send_json({"op":"ping"})
        await self.receive(host,"pong")
        self.assertLess(time.monotonic()-before,0.2)

    async def test_storage_pressure_retries_presence_expiry_and_disconnect(self):
        first,a,_,second,b,_ = await self.mutual()
        host,hosted = await self.room()
        await self.lobby(first,hosted)
        await self.command(first,"invite",code=b["code"])
        state = await self.receive(second,"state",lambda value:bool(value["invitations"]))
        service = self.server.app[SOCIAL_KEY]
        store_call = service.store.call
        injected = {"remaining":2}
        async def pressure(operation,*arguments):
            if operation=="view" and injected["remaining"]:
                injected["remaining"] -= 1
                if injected["remaining"]==1:
                    raise SocialError("service_unavailable")
                raise sqlite3.OperationalError("database is locked")
            return await store_call(operation,*arguments)
        service.store.call = pressure
        session = next(row for row in service.sessions if row.profile and row.profile["code"]==a["code"])
        session.presence["status"] = "playing"
        session.presence["joinable"] = False
        session.presence_dirty = True
        service.invites[state["invitations"][0]["id"]]["expires"] = time.time()-1
        recovered = await self.receive(second,"state",lambda value:not value["invitations"] and value["friends"][0]["status"]=="playing",timeout=5)
        self.assertFalse(recovered["friends"][0]["joinable"])
        self.assertFalse(service.sweeper.done())
        self.assertEqual(injected["remaining"],0)
        injected["remaining"] = 2
        await first.close()
        await self.receive(second,"state",lambda value:value["friends"][0]["status"]=="offline",timeout=5)
        self.assertFalse(service.sweeper.done())

    async def test_corrupt_database_still_fails_startup_and_closes_handle(self):
        corrupt = Path(self.directory.name)/"corrupt.sqlite3"
        corrupt.write_bytes(b"invalid sqlite database")
        store = Store(str(corrupt))
        with self.assertRaises(sqlite3.DatabaseError):
            await store.open()
        self.assertIsNone(store.connection)

    async def test_origin_tls_and_plaintext_profile_protection(self):
        with self.assertRaises(WSServerHandshakeError):
            await self.clients.ws_connect(self.server.make_url("/social"),headers={"Origin":"https://untrusted.example"})
        proxy = await self.start_server(trusted_proxies=("127.0.0.1/32",))
        with self.assertRaises(WSServerHandshakeError) as denied:
            await self.clients.ws_connect(proxy.make_url("/social"),headers={"X-Forwarded-For":"8.8.8.8","X-Forwarded-Proto":"http"})
        self.assertEqual(denied.exception.status,403)
        accepted = await self.clients.ws_connect(proxy.make_url("/social"),headers={"X-Forwarded-For":"8.8.8.8","X-Forwarded-Proto":"https"})
        self.sockets.append(accepted)
        await accepted.send_json({"op":"auth","version":1,"build":GAME_BUILD,"secret":secrets.token_hex(32),"name":"Mara"})
        await self.receive(accepted,"ready")
        loopback = await self.clients.ws_connect(proxy.make_url("/social"),headers={"X-Forwarded-For":"::1"})
        self.sockets.append(loopback)
        await loopback.send_json({"op":"auth","version":1,"build":GAME_BUILD,"secret":secrets.token_hex(32),"name":"Ivo"})
        await self.receive(loopback,"ready")
        self.assertIn("::1",proxy.app[RELAY_KEY].addresses)


class SocialValidation(unittest.TestCase):
    def test_names_and_urls(self):
        self.assertEqual(safe_name("Ma\u0308ra"),"Mära")
        for name in ("", "x"*25,"Mara\n","Mara\u202e","Mara\u061c"):
            self.assertIsNone(safe_name(name))
        for url in ("wss://play.example.com/ws","ws://127.0.0.1:8765/ws",""):
            self.assertTrue(safe_relay_url(url))
        for url in ("ws://play.example.com/ws","ws://192.168.1.2/ws","wss://secret@play.example/ws","wss://play.example/ws?token=x","wss://play.example:99999/ws"):
            self.assertFalse(safe_relay_url(url))
        self.assertTrue(safe_room_code("ABCDEF","wss://play.example/ws"))
        self.assertFalse(safe_room_code("ABCDEFGH","wss://play.example/ws"))
        self.assertFalse(safe_room_code("ABCDEF",""))


if __name__ == "__main__":
    unittest.main(verbosity=2)
