import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SERVER_PATH = ROOT / "mcp/launchscope_mcp.py"
RULES_TOOL_PATH = ROOT / ".agents/skills/launchscope/scripts/rules_tool.py"


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MCP = load_module("launchscope_mcp_test", SERVER_PATH)
RULES = load_module("launchscope_rules_test", RULES_TOOL_PATH)


class LaunchScopeMCPTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.history = self.directory / "snapshot-history.json"
        self.rules = self.directory / "purpose-rules.json"
        self.candidates = self.directory / "Candidates"
        self.history.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "baselineDate": "2026-09-05T00:00:00Z",
                    "latest": {
                        "generatedAt": "2026-09-05T01:00:00Z",
                        "items": [
                            {
                                "id": "user:com.example.worker",
                                "name": "Example 后台服务",
                                "status": "running",
                                "runAtLoad": True,
                                "keepAlive": False,
                                "schedule": None,
                                "programFingerprint": "abc123",
                            }
                        ],
                    },
                    "changes": [
                        {
                            "id": "change-1",
                            "itemID": "user:com.example.worker",
                            "itemName": "Example 后台服务",
                            "kind": "status",
                            "summary": "已停止 → 运行中",
                            "detail": "observed",
                            "occurredAt": "2026-09-05T01:00:00Z",
                            "attentionLevel": "notice",
                        }
                    ],
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        self.server = MCP.LaunchScopeMCP(
            history_file=self.history,
            rules_file=self.rules,
            candidates_dir=self.candidates,
            rules_module=RULES,
        )

    def tearDown(self):
        self.temporary.cleanup()

    @property
    def candidate(self):
        return {
            "schemaVersion": 1,
            "rules": [
                {
                    "id": "com.example.worker",
                    "labels": ["com.example.worker"],
                    "name": "Example 后台服务",
                    "summary": "为 Example 提供后台同步。",
                    "vendor": "Example",
                    "category": "效率工具",
                    "evidence": "Example 官方帮助文档与本机 plist",
                    "disableImpact": "自动同步会停止。",
                }
            ],
        }

    def payload(self, result):
        return json.loads(result["content"][0]["text"])

    def test_discovery_and_tools_expose_safe_capabilities(self):
        discovery = self.server.handle("server/discover")
        self.assertIn("2026-07-28", discovery["supportedVersions"])
        tools = self.server.handle("tools/list")["tools"]
        self.assertEqual(len(tools), 7)
        save = next(tool for tool in tools if tool["name"].endswith("save_rule_pack_candidate"))
        self.assertFalse(save["annotations"]["destructiveHint"])
        self.assertFalse(save["annotations"]["readOnlyHint"])
        self.assertFalse(any("disable" in tool["name"] for tool in tools))

    def test_list_items_uses_privacy_limited_snapshot(self):
        result = self.payload(
            self.server.call_tool(
                "launchscope_list_background_items", {"status": "running", "limit": 10}
            )
        )
        self.assertTrue(result["ok"])
        self.assertEqual(result["totalMatched"], 1)
        self.assertNotIn("program", result["items"][0])
        self.assertNotIn("arguments", result["items"][0])
        self.assertTrue(result["privacy"]["rawProgramPathOmitted"])

    def test_validate_plan_and_save_candidate_without_installing(self):
        validation = self.payload(
            self.server.call_tool("launchscope_validate_rule_pack", {"rulePack": self.candidate})
        )
        self.assertTrue(validation["ok"])

        plan = self.payload(
            self.server.call_tool("launchscope_plan_rule_pack", {"rulePack": self.candidate})
        )
        self.assertTrue(plan["ok"])
        self.assertEqual(plan["addedIDs"], ["com.example.worker"])
        self.assertFalse(plan["writePerformed"])

        saved = self.payload(
            self.server.call_tool(
                "launchscope_save_rule_pack_candidate",
                {"rulePack": self.candidate, "name": "example-candidate"},
            )
        )
        candidate_path = Path(saved["path"])
        self.assertTrue(candidate_path.is_file())
        self.assertFalse(self.rules.exists())
        self.assertFalse(saved["installed"])
        self.assertFalse(saved["launchdChanged"])
        self.assertEqual(stat.S_IMODE(candidate_path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.candidates.stat().st_mode), 0o700)

        second = self.payload(
            self.server.call_tool(
                "launchscope_save_rule_pack_candidate",
                {"rulePack": self.candidate, "name": "example-candidate"},
            )
        )
        self.assertFalse(second["created"])

    def test_rejects_invalid_or_unexpected_arguments(self):
        missing = self.server.call_tool("launchscope_validate_rule_pack", {})
        self.assertTrue(missing["isError"])
        unexpected = self.server.call_tool("launchscope_get_status", {"apply": True})
        self.assertTrue(unexpected["isError"])
        bad_status = self.server.call_tool(
            "launchscope_list_background_items", {"status": "unknown"}
        )
        self.assertTrue(bad_status["isError"])
        empty = self.payload(
            self.server.call_tool(
                "launchscope_plan_rule_pack", {"rulePack": {"schemaVersion": 1, "rules": []}}
            )
        )
        self.assertFalse(empty["ok"])

    def test_stdio_is_newline_delimited_json_rpc_without_stdout_noise(self):
        environment = os.environ.copy()
        environment.update(
            {
                "LAUNCHSCOPE_HISTORY_PATH": str(self.history),
                "LAUNCHSCOPE_RULES_PATH": str(self.rules),
                "LAUNCHSCOPE_CANDIDATES_PATH": str(self.candidates),
            }
        )
        requests = "\n".join(
            [
                json.dumps(
                    {
                        "jsonrpc": "2.0",
                        "id": 1,
                        "method": "initialize",
                        "params": {"protocolVersion": "2025-11-25"},
                    }
                ),
                json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}),
                "",
            ]
        )
        process = subprocess.run(
            [sys.executable, str(SERVER_PATH)],
            input=requests,
            text=True,
            capture_output=True,
            env=environment,
            check=False,
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        responses = [json.loads(line) for line in process.stdout.splitlines()]
        self.assertEqual([response["id"] for response in responses], [1, 2])
        self.assertEqual(responses[0]["result"]["protocolVersion"], "2025-11-25")
        self.assertEqual(len(responses[1]["result"]["tools"]), 7)


if __name__ == "__main__":
    unittest.main()
