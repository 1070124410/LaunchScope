#!/usr/bin/env python3
"""Zero-dependency local MCP server for LaunchScope."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

SERVER_NAME = "launchscope"
SERVER_VERSION = "1.0.0"
MODERN_VERSION = "2026-07-28"
LEGACY_VERSIONS = ("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
SUPPORTED_VERSIONS = (MODERN_VERSION, *LEGACY_VERSIONS)
APP_SUPPORT = Path.home() / "Library/Application Support/LaunchScope"


def _find_asset(relative_repo_path: str, bundled_name: str) -> Path:
    script_dir = Path(__file__).resolve().parent
    bundled = script_dir / bundled_name
    if bundled.exists():
        return bundled
    return script_dir.parent / relative_repo_path


def _load_rules_module():
    path = _find_asset(
        ".agents/skills/launchscope/scripts/rules_tool.py",
        "rules_tool.py",
    )
    spec = importlib.util.spec_from_file_location("launchscope_rules_tool", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load Rule Pack engine at {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _canonical_json(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def _digest(value: Any) -> str:
    return hashlib.sha256(_canonical_json(value)).hexdigest()


def _text_result(payload: Any, *, is_error: bool = False) -> dict[str, Any]:
    text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)
    return {
        "content": [{"type": "text", "text": text}],
        "isError": is_error,
    }


class LaunchScopeMCP:
    """Small MCP interface over LaunchScope's local protocol and state files."""

    def __init__(
        self,
        *,
        history_file: Path | None = None,
        rules_file: Path | None = None,
        candidates_dir: Path | None = None,
        protocol_file: Path | None = None,
        schema_file: Path | None = None,
        rules_module: Any | None = None,
    ) -> None:
        self.history_file = history_file or Path(
            os.environ.get("LAUNCHSCOPE_HISTORY_PATH", APP_SUPPORT / "snapshot-history.json")
        )
        self.rules_file = rules_file or Path(
            os.environ.get("LAUNCHSCOPE_RULES_PATH", APP_SUPPORT / "purpose-rules.json")
        )
        self.candidates_dir = candidates_dir or Path(
            os.environ.get("LAUNCHSCOPE_CANDIDATES_PATH", APP_SUPPORT / "Candidates")
        )
        self.protocol_file = protocol_file or _find_asset(
            "docs/AGENT_PROTOCOL.md",
            "AGENT_PROTOCOL.md",
        )
        self.schema_file = schema_file or _find_asset(
            "docs/schema/purpose-rules-v1.schema.json",
            "purpose-rules-v1.schema.json",
        )
        self.rules = rules_module or _load_rules_module()

    @property
    def capabilities(self) -> dict[str, Any]:
        return {
            "tools": {"listChanged": False},
            "resources": {"subscribe": False, "listChanged": False},
            "prompts": {"listChanged": False},
        }

    @property
    def instructions(self) -> str:
        return (
            "LaunchScope exposes privacy-limited local background-item state and Purpose Rule Pack tools. "
            "Recognition and launchd management are separate: never infer that a rule authorizes starting, "
            "stopping, enabling, or disabling an item. Validate and preview every candidate. Save candidates "
            "only after the user asks, then direct the user to review and install them in the LaunchScope app."
        )

    def handle(self, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        params = params or {}
        if method == "server/discover":
            return {
                "resultType": "complete",
                "supportedVersions": list(SUPPORTED_VERSIONS),
                "capabilities": self.capabilities,
                "_meta": {
                    "io.modelcontextprotocol/serverInfo": {
                        "name": SERVER_NAME,
                        "version": SERVER_VERSION,
                    }
                },
                "instructions": self.instructions,
                "ttlMs": 3_600_000,
                "cacheScope": "private",
            }
        if method == "initialize":
            requested = params.get("protocolVersion")
            selected = requested if requested in SUPPORTED_VERSIONS else LEGACY_VERSIONS[0]
            return {
                "protocolVersion": selected,
                "capabilities": self.capabilities,
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
                "instructions": self.instructions,
            }
        if method == "ping":
            return {}
        if method == "tools/list":
            return {"tools": self.tool_definitions()}
        if method == "tools/call":
            return self.call_tool(params.get("name", ""), params.get("arguments") or {})
        if method == "resources/list":
            return {"resources": self.resource_definitions()}
        if method == "resources/read":
            return self.read_resource(params.get("uri", ""))
        if method == "prompts/list":
            return {"prompts": self.prompt_definitions()}
        if method == "prompts/get":
            return self.get_prompt(params.get("name", ""), params.get("arguments") or {})
        raise KeyError(f"Unknown method: {method}")

    def tool_definitions(self) -> list[dict[str, Any]]:
        read_only = {
            "readOnlyHint": True,
            "destructiveHint": False,
            "idempotentHint": True,
            "openWorldHint": False,
        }
        return [
            {
                "name": "launchscope_get_status",
                "description": (
                    "Read LaunchScope's local integration status, snapshot/rule counts, paths, and safety "
                    "boundary. Use first when asked to inspect or customize Mac background items."
                ),
                "inputSchema": {"type": "object", "additionalProperties": False},
                "annotations": {**read_only, "title": "Get LaunchScope status"},
            },
            {
                "name": "launchscope_list_background_items",
                "description": (
                    "List privacy-limited items from LaunchScope's latest local snapshot. Omits command "
                    "arguments, raw program paths, PIDs, resource metrics, and environment variables."
                ),
                "inputSchema": {
                    "type": "object",
                    "additionalProperties": False,
                    "properties": {
                        "status": {
                            "type": "string",
                            "enum": ["running", "stopped", "scheduled", "disabled", "failed"],
                        },
                        "query": {"type": "string", "maxLength": 200},
                        "limit": {"type": "integer", "minimum": 1, "maximum": 200, "default": 50},
                    },
                },
                "annotations": {**read_only, "title": "List background items"},
            },
            {
                "name": "launchscope_list_recent_changes",
                "description": (
                    "Read recent added, removed, configuration, and status changes. Results are observational "
                    "evidence and do not imply LaunchScope performed the change."
                ),
                "inputSchema": {
                    "type": "object",
                    "additionalProperties": False,
                    "properties": {
                        "limit": {"type": "integer", "minimum": 1, "maximum": 200, "default": 50}
                    },
                },
                "annotations": {**read_only, "title": "List recent changes"},
            },
            {
                "name": "launchscope_get_installed_rules",
                "description": (
                    "Read and validate the installed Purpose Rule Pack. A recognition rule explains an item "
                    "and never authorizes launchd management."
                ),
                "inputSchema": {"type": "object", "additionalProperties": False},
                "annotations": {**read_only, "title": "Get installed rules"},
            },
            {
                "name": "launchscope_validate_rule_pack",
                "description": (
                    "Validate a Purpose Rule Pack v1 candidate without writing. Prefer exact labels and "
                    "sourced evidence; leave an item unknown when evidence is insufficient."
                ),
                "inputSchema": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": ["rulePack"],
                    "properties": {"rulePack": {"type": "object"}},
                },
                "annotations": {**read_only, "title": "Validate Rule Pack"},
            },
            {
                "name": "launchscope_plan_rule_pack",
                "description": (
                    "Validate and compare a Purpose Rule Pack v1 candidate with installed rules. Returns "
                    "added, updated, unchanged IDs and resulting count without writing."
                ),
                "inputSchema": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": ["rulePack"],
                    "properties": {"rulePack": {"type": "object"}},
                },
                "annotations": {**read_only, "title": "Preview Rule Pack"},
            },
            {
                "name": "launchscope_save_rule_pack_candidate",
                "description": (
                    "Save a valid Rule Pack into LaunchScope's Candidates directory. Use only after the user "
                    "explicitly asks to save it. This does not install rules or change launchd state; the user "
                    "must review the diff and install it in the app."
                ),
                "inputSchema": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": ["rulePack"],
                    "properties": {
                        "rulePack": {"type": "object"},
                        "name": {
                            "type": "string",
                            "pattern": "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$",
                            "description": "Optional safe filename stem.",
                        },
                    },
                },
                "annotations": {
                    "title": "Save Rule Pack candidate",
                    "readOnlyHint": False,
                    "destructiveHint": False,
                    "idempotentHint": True,
                    "openWorldHint": False,
                },
            },
        ]

    def call_tool(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        try:
            if not isinstance(arguments, dict):
                raise TypeError("arguments must be an object")
            self._validate_tool_arguments(name, arguments)
            if name == "launchscope_get_status":
                return _text_result(self.status())
            if name == "launchscope_list_background_items":
                return _text_result(self.list_items(arguments))
            if name == "launchscope_list_recent_changes":
                return _text_result(self.list_changes(arguments))
            if name == "launchscope_get_installed_rules":
                return _text_result(self.installed_rules())
            if name == "launchscope_validate_rule_pack":
                return _text_result(self.validate_pack(arguments.get("rulePack")))
            if name == "launchscope_plan_rule_pack":
                return _text_result(self.plan_pack(arguments.get("rulePack")))
            if name == "launchscope_save_rule_pack_candidate":
                return _text_result(self.save_candidate(arguments.get("rulePack"), arguments.get("name")))
            return _text_result({"ok": False, "error": f"Unknown tool: {name}"}, is_error=True)
        except (OSError, ValueError, TypeError, json.JSONDecodeError) as error:
            return _text_result({"ok": False, "error": str(error)}, is_error=True)

    def status(self) -> dict[str, Any]:
        snapshot = self._load_history()
        try:
            installed, warnings = self.rules.load_target(self.rules_file)
        except (OSError, ValueError, json.JSONDecodeError) as error:
            installed = []
            warnings = [f"Installed Rule Pack could not be read: {error}"]
        return {
            "ok": True,
            "serverVersion": SERVER_VERSION,
            "snapshotAvailable": snapshot is not None,
            "snapshotGeneratedAt": snapshot.get("latest", {}).get("generatedAt") if snapshot else None,
            "backgroundItemCount": len(snapshot.get("latest", {}).get("items", [])) if snapshot else 0,
            "recentChangeCount": len(snapshot.get("changes", [])) if snapshot else 0,
            "installedRuleCount": len(installed),
            "warnings": warnings,
            "paths": {
                "history": str(self.history_file),
                "rules": str(self.rules_file),
                "candidates": str(self.candidates_dir),
            },
            "managementBoundary": (
                "MCP cannot start, stop, enable, disable, or install a rule. Review candidate diffs and "
                "manage launchd items in the LaunchScope app."
            ),
        }

    def list_items(self, arguments: dict[str, Any]) -> dict[str, Any]:
        history = self._require_history()
        items = history.get("latest", {}).get("items", [])
        status = arguments.get("status")
        query = str(arguments.get("query", "")).strip().casefold()
        limit = self._limit(arguments.get("limit", 50))
        if status:
            items = [item for item in items if item.get("status") == status]
        if query:
            items = [
                item
                for item in items
                if query in f"{item.get('id', '')} {item.get('name', '')}".casefold()
            ]
        return {
            "ok": True,
            "generatedAt": history.get("latest", {}).get("generatedAt"),
            "totalMatched": len(items),
            "items": items[:limit],
            "privacy": {
                "argumentsOmitted": True,
                "rawProgramPathOmitted": True,
                "runtimeIdentifiersOmitted": True,
                "resourceMetricsOmitted": True,
            },
        }

    def list_changes(self, arguments: dict[str, Any]) -> dict[str, Any]:
        history = self._require_history()
        changes = history.get("changes", [])
        limit = self._limit(arguments.get("limit", 50))
        return {
            "ok": True,
            "baselineDate": history.get("baselineDate"),
            "total": len(changes),
            "changes": changes[:limit],
        }

    def installed_rules(self) -> dict[str, Any]:
        rules, warnings = self.rules.load_target(self.rules_file)
        return {
            "ok": True,
            "target": str(self.rules_file),
            "ruleCount": len(rules),
            "rules": rules,
            "warnings": warnings,
            "managementAuthorized": False,
        }

    def validate_pack(self, pack: Any) -> dict[str, Any]:
        accepted, errors, warnings = self.rules.validate_pack(pack)
        return {
            "ok": not errors,
            "acceptedCount": len(accepted),
            "errors": errors,
            "warnings": warnings,
            "candidateHash": _digest(pack) if isinstance(pack, dict) else None,
        }

    def plan_pack(self, pack: Any) -> dict[str, Any]:
        candidate, errors, warnings = self.rules.validate_pack(pack)
        if not errors and not candidate:
            errors = ["rules must contain at least one rule"]
        if errors:
            return {
                "ok": False,
                "errors": errors,
                "warnings": warnings,
                "writePerformed": False,
            }
        existing, target_warnings = self.rules.load_target(self.rules_file)
        existing_by_id = {rule["id"]: rule for rule in existing}
        added = [rule["id"] for rule in candidate if rule["id"] not in existing_by_id]
        updated = [
            rule["id"]
            for rule in candidate
            if rule["id"] in existing_by_id and rule != existing_by_id[rule["id"]]
        ]
        unchanged = [
            rule["id"]
            for rule in candidate
            if rule["id"] in existing_by_id and rule == existing_by_id[rule["id"]]
        ]
        merged, _, _ = self.rules.merge_rules(existing, candidate)
        return {
            "ok": True,
            "candidateHash": _digest(pack),
            "candidateCount": len(candidate),
            "installedCount": len(existing),
            "resultCount": len(merged),
            "addedIDs": added,
            "updatedIDs": updated,
            "unchangedIDs": unchanged,
            "warnings": [*target_warnings, *warnings],
            "writePerformed": False,
            "nextStep": (
                "If the user approves saving, call launchscope_save_rule_pack_candidate. Then import the "
                "file in LaunchScope → More → Custom Recognition Rules."
            ),
        }

    def save_candidate(self, pack: Any, requested_name: Any) -> dict[str, Any]:
        candidate, errors, warnings = self.rules.validate_pack(pack)
        if not errors and not candidate:
            errors = ["rules must contain at least one rule"]
        if errors:
            raise ValueError("Invalid Rule Pack: " + "; ".join(errors))
        digest = _digest(pack)
        if requested_name is None:
            stem = f"purpose-rules-{digest[:12]}"
        else:
            stem = str(requested_name)
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", stem):
                raise ValueError("name must match ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
        path = self.candidates_dir / f"{stem}.json"
        self.candidates_dir.mkdir(parents=True, exist_ok=True)
        os.chmod(self.candidates_dir, 0o700)
        data = json.dumps(
            {"schemaVersion": 1, "rules": candidate},
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        ).encode("utf-8") + b"\n"
        if path.exists():
            if path.read_bytes() != data:
                raise ValueError(f"Candidate already exists with different content: {path}")
            created = False
        else:
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            created = True
        return {
            "ok": True,
            "path": str(path),
            "created": created,
            "candidateHash": digest,
            "ruleCount": len(candidate),
            "warnings": warnings,
            "installed": False,
            "launchdChanged": False,
            "nextStep": "Open LaunchScope and import this candidate to review its diff before installation.",
        }

    def resource_definitions(self) -> list[dict[str, Any]]:
        return [
            {
                "uri": "launchscope://protocol",
                "name": "LaunchScope Agent Protocol",
                "description": "Authoritative workflow and safety boundaries for AI integrations.",
                "mimeType": "text/markdown",
            },
            {
                "uri": "launchscope://schema/purpose-rules-v1",
                "name": "Purpose Rule Pack v1 Schema",
                "description": "Machine-readable JSON Schema for recognition rules.",
                "mimeType": "application/schema+json",
            },
            {
                "uri": "launchscope://snapshot/current",
                "name": "Current privacy-limited snapshot",
                "description": "Latest locally persisted LaunchScope snapshot.",
                "mimeType": "application/json",
            },
        ]

    def read_resource(self, uri: str) -> dict[str, Any]:
        if uri == "launchscope://protocol":
            text = self.protocol_file.read_text(encoding="utf-8")
            mime_type = "text/markdown"
        elif uri == "launchscope://schema/purpose-rules-v1":
            text = self.schema_file.read_text(encoding="utf-8")
            mime_type = "application/schema+json"
        elif uri == "launchscope://snapshot/current":
            history = self._require_history()
            text = json.dumps(history, ensure_ascii=False, indent=2, sort_keys=True)
            mime_type = "application/json"
        else:
            raise ValueError(f"Unknown resource: {uri}")
        return {"contents": [{"uri": uri, "mimeType": mime_type, "text": text}]}

    def prompt_definitions(self) -> list[dict[str, Any]]:
        return [
            {
                "name": "identify-background-item",
                "description": (
                    "Inspect a privacy-limited LaunchScope item and prepare a sourced Rule Pack candidate."
                ),
                "arguments": [
                    {
                        "name": "item",
                        "description": "LaunchScope item ID, label, or name.",
                        "required": True,
                    }
                ],
            }
        ]

    def get_prompt(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        if name != "identify-background-item":
            raise ValueError(f"Unknown prompt: {name}")
        item = str(arguments.get("item", "")).strip()
        if not item:
            raise ValueError("item is required")
        return {
            "description": "Prepare a reviewable LaunchScope recognition candidate.",
            "messages": [
                {
                    "role": "user",
                    "content": {
                        "type": "text",
                        "text": (
                            f"Inspect LaunchScope item {item!r}. Read launchscope://protocol, call "
                            "launchscope_list_background_items, and distinguish exact evidence from inference. "
                            "If evidence supports a stable purpose, produce Purpose Rule Pack v1, validate it, "
                            "and preview the merge. Save only if I explicitly ask. Do not manage launchd state."
                        ),
                    },
                }
            ],
        }

    def _load_history(self) -> dict[str, Any] | None:
        if not self.history_file.exists():
            return None
        value = json.loads(self.history_file.read_text(encoding="utf-8"))
        if not isinstance(value, dict):
            raise ValueError("Snapshot history must be a JSON object")
        return value

    def _require_history(self) -> dict[str, Any]:
        history = self._load_history()
        if history is None:
            raise ValueError("No LaunchScope snapshot is available. Open LaunchScope and refresh once.")
        return history

    @staticmethod
    def _limit(value: Any) -> int:
        if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= 200:
            raise ValueError("limit must be an integer from 1 to 200")
        return value

    @staticmethod
    def _validate_tool_arguments(name: str, arguments: dict[str, Any]) -> None:
        allowed_by_tool = {
            "launchscope_get_status": set(),
            "launchscope_list_background_items": {"status", "query", "limit"},
            "launchscope_list_recent_changes": {"limit"},
            "launchscope_get_installed_rules": set(),
            "launchscope_validate_rule_pack": {"rulePack"},
            "launchscope_plan_rule_pack": {"rulePack"},
            "launchscope_save_rule_pack_candidate": {"rulePack", "name"},
        }
        if name not in allowed_by_tool:
            return
        unexpected = set(arguments) - allowed_by_tool[name]
        if unexpected:
            raise ValueError(f"unexpected arguments: {', '.join(sorted(unexpected))}")
        if name in {
            "launchscope_validate_rule_pack",
            "launchscope_plan_rule_pack",
            "launchscope_save_rule_pack_candidate",
        }:
            if "rulePack" not in arguments or not isinstance(arguments["rulePack"], dict):
                raise ValueError("rulePack is required and must be an object")
        if "limit" in arguments:
            LaunchScopeMCP._limit(arguments["limit"])
        if "status" in arguments:
            status = arguments["status"]
            valid_statuses = {"running", "stopped", "scheduled", "disabled", "failed"}
            if not isinstance(status, str) or status not in valid_statuses:
                raise ValueError("status must be running, stopped, scheduled, disabled, or failed")
        if "query" in arguments:
            query = arguments["query"]
            if not isinstance(query, str) or len(query) > 200:
                raise ValueError("query must be a string no longer than 200 characters")
        if "name" in arguments and arguments["name"] is not None:
            candidate_name = arguments["name"]
            if not isinstance(candidate_name, str) or not re.fullmatch(
                r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", candidate_name
            ):
                raise ValueError("name must match ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


def _response(request_id: Any, *, result: Any = None, error: Any = None) -> dict[str, Any]:
    payload: dict[str, Any] = {"jsonrpc": "2.0", "id": request_id}
    if error is not None:
        payload["error"] = error
    else:
        payload["result"] = result
    return payload


def serve(server: LaunchScopeMCP | None = None) -> int:
    server = server or LaunchScopeMCP()
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        request_id: Any = None
        try:
            request = json.loads(line)
            if not isinstance(request, dict) or request.get("jsonrpc") != "2.0":
                raise ValueError("Expected a JSON-RPC 2.0 object")
            request_id = request.get("id")
            method = request.get("method")
            if not isinstance(method, str):
                raise ValueError("method must be a string")
            if request_id is None:
                continue
            result = server.handle(method, request.get("params"))
            response = _response(request_id, result=result)
        except KeyError as error:
            response = _response(request_id, error={"code": -32601, "message": str(error)})
        except (ValueError, TypeError, json.JSONDecodeError) as error:
            response = _response(request_id, error={"code": -32602, "message": str(error)})
        except Exception as error:
            print(f"LaunchScope MCP internal error: {error}", file=sys.stderr)
            response = _response(
                request_id,
                error={"code": -32603, "message": "Internal server error"},
            )
        sys.stdout.write(json.dumps(response, ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(serve())
