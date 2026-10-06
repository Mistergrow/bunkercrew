#!/usr/bin/env python3
"""Retry existing relationships at capacity while rejecting new allocations."""
from __future__ import annotations
import secrets
import sys
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
