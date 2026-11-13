#!/usr/bin/env python3
"""Exercise the built MCP executable against the current user's workspace."""

import json
import select
import subprocess
import sys
import unittest


EXECUTABLE = sys.argv.pop(1) if len(sys.argv) > 1 else ".build/debug/peanut-service-manager"


class MCPInitializationTest(unittest.TestCase):
    def test_webcodex_protocol_version_and_shutdown(self):
        process = subprocess.Popen(
            [EXECUTABLE, "--mcp-server"], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        try:
            def send(message):
                process.stdin.write(json.dumps(message) + "\n")
                process.stdin.flush()

            def receive():
                self.assertTrue(select.select([process.stdout], [], [], 15)[0], "MCP response timed out")
                return json.loads(process.stdout.readline())

            send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
                "protocolVersion": "2025-06-18", "capabilities": {},
                "clientInfo": {"name": "webcodex-runner-mcp-gateway", "version": "test"},
            }})
            response = receive()
            self.assertEqual(response["id"], 1)
            self.assertEqual(response["result"]["protocolVersion"], "2025-06-18")
            self.assertIsInstance(response["result"]["capabilities"]["tools"], dict)
            self.assertTrue(response["result"]["serverInfo"]["name"])
            self.assertTrue(response["result"]["serverInfo"]["version"])
            send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
            send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
            response = receive()
            self.assertEqual(response["id"], 2)
            self.assertIn("workspace_list", [tool["name"] for tool in response["result"]["tools"]])
            process.stdin.close()
            self.assertEqual(process.wait(timeout=10), 0)
            self.assertEqual(process.stdout.read(), "")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()
            process.stderr.close()


if __name__ == "__main__":
    unittest.main()
