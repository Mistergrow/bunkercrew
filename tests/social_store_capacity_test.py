#!/usr/bin/env python3
"""Retry existing relationships at capacity while rejecting new allocations."""
from __future__ import annotations
import secrets
import sqlite3
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "server"))
from social import MAX_BLOCKS, MAX_REQUESTS, SocialError, Store


class StoreCapacity(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.store = Store(":memory:")
        await self.store.open()

    async def asyncTearDown(self):
        await self.store.close()

    async def profiles(self, count):
        return [await self.store.call("profile", secrets.token_hex(32), f"Crew {index}")
                for index in range(count)]

    async def assert_limit(self, owner, operation, target, code):
        with self.assertRaises(SocialError) as caught:
            await self.store.call("mutate", owner["id"], operation, target["code"])
        self.assertEqual(caught.exception.code, code)

    async def test_retry_existing_block_with_full_block_list(self):
        owner, *targets = await self.profiles(MAX_BLOCKS + 2)
        for target in targets[:MAX_BLOCKS]:
            await self.store.call("mutate", owner["id"], "block_friend", target["code"])
        await self.assert_limit(owner, "block_friend", targets[-1], "friend_limit")
        self.assertEqual(await self.store.call("mutate", owner["id"], "block_friend", targets[0]["code"]), targets[0]["id"])
        state = await self.store.call("view", owner["id"])
        self.assertEqual(len(state["blocked"]), MAX_BLOCKS)
        self.assertEqual(state["friends"], [])

    async def test_retry_existing_request_with_full_outgoing_list(self):
        owner, *targets = await self.profiles(MAX_REQUESTS + 2)
        for target in targets[:MAX_REQUESTS]:
            await self.store.call("mutate", owner["id"], "add_friend", target["code"])
        await self.assert_limit(owner, "add_friend", targets[-1], "request_limit")
        self.assertEqual(await self.store.call("mutate", owner["id"], "add_friend", targets[0]["code"]), targets[0]["id"])
        state = await self.store.call("view", owner["id"])
        self.assertEqual(len(state["outgoing_requests"]), MAX_REQUESTS)
        self.assertEqual(state["friends"], [])

    async def test_retry_existing_request_with_full_incoming_list(self):
        target, *senders = await self.profiles(MAX_REQUESTS + 2)
        for sender in senders[:MAX_REQUESTS]:
            await self.store.call("mutate", sender["id"], "add_friend", target["code"])
        await self.assert_limit(senders[-1], "add_friend", target, "request_limit")
        self.assertEqual(await self.store.call("mutate", senders[0]["id"], "add_friend", target["code"]), target["id"])
        state = await self.store.call("view", target["id"])
        self.assertEqual(len(state["requests"]), MAX_REQUESTS)
        self.assertEqual(state["friends"], [])


class ProfileRetention(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="bunkercrew-retention-test-")
        self.path = str(Path(self.directory.name) / "social.sqlite3")
        self.stores = []

    async def asyncTearDown(self):
        for store in self.stores:
            await store.close()
        self.directory.cleanup()

    async def store(self, **options):
        store = Store(self.path, **options)
        await store.open()
        self.stores.append(store)
        return store

    @staticmethod
    def age(store, profile, days):
        store.connection.execute("UPDATE profiles SET seen=? WHERE id=?", (int(time.time() - days * 86400), profile["id"]))
        store.connection.commit()

    @staticmethod
    def codes(store):
        return {row[0] for row in store.connection.execute("SELECT code FROM profiles")}

    async def create(self, store, name="Crew"):
        return await store.call("profile", secrets.token_hex(32), name)

    async def test_existing_database_gains_last_seen_without_losing_anything(self):
        # The exact schema shipped before last-login tracking.
        old = sqlite3.connect(self.path)
        old.executescript("""
            CREATE TABLE profiles(id INTEGER PRIMARY KEY, secret_hash TEXT NOT NULL UNIQUE,
                code TEXT NOT NULL UNIQUE, name TEXT NOT NULL, created INTEGER NOT NULL);
            CREATE TABLE friends(a INTEGER NOT NULL REFERENCES profiles(id), b INTEGER NOT NULL REFERENCES profiles(id),
                PRIMARY KEY(a,b), CHECK(a<b));
            CREATE TABLE requests(sender INTEGER NOT NULL REFERENCES profiles(id), target INTEGER NOT NULL REFERENCES profiles(id),
                PRIMARY KEY(sender,target), CHECK(sender<>target));
            CREATE TABLE blocks(owner INTEGER NOT NULL REFERENCES profiles(id), target INTEGER NOT NULL REFERENCES profiles(id),
                PRIMARY KEY(owner,target), CHECK(owner<>target));
        """)
        secrets_ = [secrets.token_hex(32) for _ in range(3)]
        for index, secret in enumerate(secrets_):
            old.execute("INSERT INTO profiles(secret_hash,code,name,created) VALUES(?,?,?,?)",
                        (secret, "ABCDEFGHJKL" + "234"[index], f"Alt {index}", 1_600_000_000))
        old.execute("INSERT INTO friends VALUES(1,2)")
        old.commit()
        old.close()
        before = time.time()
        store = await self.store(unused_seconds=86400)
        seen = [row[0] for row in store.connection.execute("SELECT seen FROM profiles ORDER BY id")]
        self.assertEqual(len(seen), 3)
        self.assertTrue(all(before - 1 <= value <= time.time() + 1 for value in seen), seen)
        # Created in 2020, but nothing is known about their use: none is pruned.
        self.assertEqual(await store.call("prune"), 0)
        self.assertEqual(await store.call("profile", secrets_[0], "Alt 0"),
                         {"id": 1, "code": "ABCDEFGHJKL2", "name": "Alt 0"})
        self.assertEqual(len((await store.call("view", 1))["friends"]), 1)
        await store.close()
        # A second start, and a row written by a rolled-back older server.
        old = sqlite3.connect(self.path)
        old.execute("INSERT INTO profiles(secret_hash,code,name,created) VALUES(?,?,?,?)",
                    (secrets.token_hex(32), "ABCDEFGHJKL5", "Rollback", 1_600_000_000))
        old.commit()
        old.close()
        store = await self.store(unused_seconds=86400)
        self.assertEqual(await store.call("prune"), 0)
        self.assertEqual(len(self.codes(store)), 4)

    async def test_login_refreshes_last_seen(self):
        store = await self.store()
        secret = secrets.token_hex(32)
        profile = await store.call("profile", secret, "Mara")
        self.assertIsNone(await store.call("profile", secrets.token_hex(32), "Ivo", False))
        self.assertEqual(len(self.codes(store)), 1)
        self.age(store, profile, 20)
        self.assertEqual((await store.call("profile", secret, "Mara", False))["code"], profile["code"])
        seen = store.connection.execute("SELECT seen FROM profiles").fetchone()[0]
        self.assertLess(time.time() - seen, 5)

    async def test_only_stale_profiles_without_relationships_are_pruned(self):
        store = await self.store(unused_seconds=30 * 86400)
        fresh, stale, connected, friend_a, friend_b, sender, target, blocker, blocked = [
            await self.create(store) for _ in range(9)]
        await store.call("mutate", friend_a["id"], "add_friend", friend_b["code"])
        await store.call("mutate", friend_b["id"], "accept_friend", friend_a["code"])
        await store.call("mutate", sender["id"], "add_friend", target["code"])
        await store.call("mutate", blocker["id"], "block_friend", blocked["code"])
        for profile in (stale, connected, friend_a, friend_b, sender, target, blocker, blocked):
            self.age(store, profile, 31)
        self.age(store, fresh, 29)
        self.assertEqual(await store.call("prune", (connected["id"],)), 2)
        # Being blocked by somebody is no relationship worth keeping.
        self.assertEqual(self.codes(store), {item["code"] for item in (
            fresh, connected, friend_a, friend_b, sender, target, blocker)})
        self.assertEqual((await store.call("view", blocker["id"]))["blocked"], [])
        self.assertEqual(len((await store.call("view", friend_a["id"]))["friends"]), 1)
        # Its only block pointed at a removed profile, so the equally stale
        # blocker has nothing left either and follows in the next pass.
        self.assertEqual(await store.call("prune"), 1)
        self.assertNotIn(blocker["code"], self.codes(store))
        self.assertEqual(await store.call("prune"), 0)
        self.assertEqual(len(self.codes(store)), 6)
        self.assertEqual(store.connection.execute("PRAGMA foreign_key_check").fetchall(), [])

    async def test_full_table_evicts_least_recently_seen_and_protects_active_players(self):
        store = await self.store(max_profiles=6, unused_seconds=30 * 86400, active_seconds=180 * 86400)
        lonely_new, lonely_old, lonely_older, friend_a, friend_b, veteran = [
            await self.create(store) for _ in range(6)]
        await store.call("mutate", friend_a["id"], "add_friend", friend_b["code"])
        await store.call("mutate", friend_b["id"], "accept_friend", friend_a["code"])
        await store.call("mutate", veteran["id"], "add_friend", friend_a["code"])
        with self.assertRaises(SocialError) as caught:
            await self.create(store)
        self.assertEqual(caught.exception.code, "service_unavailable")
        # The scan is not repeated for every refused login.
        self.age(store, lonely_old, 3)
        with self.assertRaises(SocialError):
            await self.create(store)
        store.pressure_checked = float("-inf")
        self.age(store, lonely_older, 5)
        self.age(store, friend_a, 100)
        self.age(store, friend_b, 100)
        first = await self.create(store)
        # One place was needed: only the least recently seen unused profile went.
        self.assertEqual(self.codes(store), {item["code"] for item in (
            lonely_new, lonely_old, friend_a, friend_b, veteran, first)})
        store.pressure_checked = float("-inf")
        second = await self.create(store)
        self.assertNotIn(lonely_old["code"], self.codes(store))
        # Now only profiles with friends remain as candidates, and none has
        # been away for 180 days: the service refuses rather than deletes.
        store.pressure_checked = float("-inf")
        with self.assertRaises(SocialError):
            await self.create(store)
        self.assertEqual(len((await store.call("view", friend_a["id"]))["friends"]), 1)
        self.age(store, veteran, 200)
        self.age(store, friend_b, 300)
        store.pressure_checked = float("-inf")
        # A connected profile is exempt however old its row is.
        third = await store.call("profile", secrets.token_hex(32), "Neu", True, (friend_b["id"],))
        self.assertEqual(self.codes(store), {item["code"] for item in (
            lonely_new, friend_a, friend_b, first, second, third)})
        self.assertEqual((await store.call("view", friend_a["id"]))["requests"], [])
        self.assertEqual(store.connection.execute("PRAGMA foreign_key_check").fetchall(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
