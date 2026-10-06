#!/usr/bin/env python3
"""Read-only checks against the enabled local Godot editor MCP plugin.

Requires the editor's existing listener on 127.0.0.1:3000. Never reloads scenes,
changes settings, starts/stops gameplay, or performs real undo/redo actions.
"""
import json
import pathlib
import unittest
import urllib.request


class EditorAccess(unittest.TestCase):
    def test_readonly_editor_access_preserves_open_scene(self):
        records = []

        def request(method, params):
            body = {"jsonrpc": "2.0", "id": 8200 + len(records), "method": method, "params": params}
            query = urllib.request.Request(
                "http://127.0.0.1:3000/mcp", data=json.dumps(body).encode(),
                headers={"Content-Type": "application/json", "Accept": "application/json, text/event-stream"})
            with urllib.request.urlopen(query, timeout=15) as response:
                result = json.loads(response.read())
                records.append({"request": body, "http_status": response.status, "response": result})
                self.assertEqual(response.status, 200)
            self.assertEqual(result["id"], body["id"])
            self.assertNotIn("error", result)
            return result["result"]

        def call(name, arguments, success=True):
            result = request("tools/call", {"name": name, "arguments": arguments})
            payload = json.loads(result["content"][0]["text"])
            self.assertEqual(payload.get("success"), success, payload)
            self.assertEqual(result["isError"], not success, result)
            return payload

        def state():
            code = (
                'var scene = EditorInterface.get_edited_scene_root()\n'
                'return {"scene_id":scene.get_instance_id() if scene else 0,'
                '"path":scene.scene_file_path if scene else "",'
                '"playing":EditorInterface.is_playing_scene()}'
            )
            result = call("dev_eval", {"action": "eval", "code": code})
            return json.loads(result["data"]["result"])

        try:
            self.assertEqual(request("ping", {}), {})
            listed = request("tools/list", {})
            names = {tool["name"] for tool in listed["tools"]}
            self.assertTrue({"editor_status", "editor_undo_redo", "editor_inspector", "dev_eval"} <= names)
            before = state()
            info = call("editor_status", {"action": "get_info"})
            self.assertIn("godot_version", info["data"])
            call("editor_status", {"action": "get_distraction_free"})
            call("editor_inspector", {"action": "get_edited"})
            call("editor_filesystem", {"action": "get_current_path"})
            plugin = call("editor_plugin", {"action": "is_enabled", "plugin": "godot_mcp"})
            self.assertTrue(plugin["data"]["enabled"])
            for context in ("local", "global"):
                history = call("editor_undo_redo", {"action": "get_info", "context": context})
                self.assertEqual(history["data"]["context"], context)
                self.assertIsInstance(history["data"]["has_undo"], bool)
                self.assertIsInstance(history["data"]["has_redo"], bool)
            call("project_info", {"action": "get_info"})
            call("debug_performance", {"action": "get_fps"})
            call("dev_scene_tree", {"action": "scene_tree", "depth": 1})
            # An unknown action has no side effect and must be a real MCP tool error.
            call("editor_status", {"action": "audit_invalid_readonly_action"}, success=False)
            self.assertEqual(state(), before, "Read-only checks must preserve the scene instance and running state")
        finally:
            output = pathlib.Path(__file__).resolve().parents[1] / "artifacts/project-audit"
            output.mkdir(parents=True, exist_ok=True)
            (output / "mcp-readonly-final.json").write_text(json.dumps(records, indent=2) + "\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
