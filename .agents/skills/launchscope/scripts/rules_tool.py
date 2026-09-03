#!/usr/bin/env python3
"""Validate and transactionally merge LaunchScope Purpose Rule Packs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
DEFAULT_TARGET = Path.home() / "Library/Application Support/LaunchScope/purpose-rules.json"
RULE_KEYS = {
    "id",
    "labels",
    "programPrefixes",
    "match",
    "name",
    "summary",
    "vendor",
    "category",
    "evidence",
    "disableImpact",
}
ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def non_empty_strings(value: Any) -> bool:
    return isinstance(value, list) and bool(value) and all(isinstance(item, str) and item.strip() for item in value)


def validate_pack(pack: Any) -> tuple[list[dict[str, Any]], list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    if not isinstance(pack, dict):
        return [], ["top level must be an object"], warnings
    unknown_top = set(pack) - {"schemaVersion", "rules"}
    if unknown_top:
        errors.append(f"unknown top-level fields: {', '.join(sorted(unknown_top))}")
    if pack.get("schemaVersion") != SCHEMA_VERSION:
        errors.append(f"schemaVersion must be {SCHEMA_VERSION}")
    raw_rules = pack.get("rules")
    if not isinstance(raw_rules, list):
        errors.append("rules must be an array")
        return [], errors, warnings

    accepted: list[dict[str, Any]] = []
    seen: set[str] = set()
    for index, raw_rule in enumerate(raw_rules, 1):
        prefix = f"rule #{index}"
        if not isinstance(raw_rule, dict):
            errors.append(f"{prefix}: must be an object")
            continue
        rule_id = raw_rule.get("id")
        if isinstance(rule_id, str) and rule_id.strip():
            prefix = f"rule {rule_id}"
        rule_errors: list[str] = []
        unknown = set(raw_rule) - RULE_KEYS
        if unknown:
            rule_errors.append(f"unknown fields: {', '.join(sorted(unknown))}")
        if not isinstance(rule_id, str) or not ID_PATTERN.fullmatch(rule_id):
            rule_errors.append("id must match ^[A-Za-z0-9][A-Za-z0-9._-]*$")
        elif rule_id in seen:
            rule_errors.append("id is duplicated")
        else:
            seen.add(rule_id)

        selector_names = [name for name in ("labels", "programPrefixes", "match") if name in raw_rule]
        if not selector_names:
            rule_errors.append("at least one selector is required: labels, programPrefixes, or match")
        for name in selector_names:
            if not non_empty_strings(raw_rule[name]):
                rule_errors.append(f"{name} must be a non-empty array of non-empty strings")
        if non_empty_strings(raw_rule.get("programPrefixes")) and any(not value.startswith("/") for value in raw_rule["programPrefixes"]):
            rule_errors.append("programPrefixes values must be absolute path prefixes")

        for name in ("name", "summary", "vendor", "category"):
            if not isinstance(raw_rule.get(name), str) or not raw_rule[name].strip():
                rule_errors.append(f"{name} must be a non-empty string")
        for name in ("evidence", "disableImpact"):
            if name in raw_rule and (not isinstance(raw_rule[name], str) or not raw_rule[name].strip()):
                rule_errors.append(f"{name} must be a non-empty string when present")

        if rule_errors:
            errors.extend(f"{prefix}: {message}" for message in rule_errors)
            continue
        accepted.append(raw_rule)
        if raw_rule.get("match"):
            warnings.append(f"{prefix}: broad match selector is compatible but exact labels are preferred")
        if not raw_rule.get("evidence"):
            warnings.append(f"{prefix}: evidence is omitted")
        if not raw_rule.get("disableImpact"):
            warnings.append(f"{prefix}: disableImpact is omitted")
    return accepted, errors, warnings


def legacy_id(rule: dict[str, Any]) -> str:
    canonical = json.dumps(rule, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:12]
    return f"legacy.{digest}"


def load_target(path: Path) -> tuple[list[dict[str, Any]], list[str]]:
    if not path.exists():
        return [], []
    data = read_json(path)
    if isinstance(data, list):
        migrated = [{**rule, "id": rule.get("id") or legacy_id(rule)} for rule in data if isinstance(rule, dict)]
        accepted, errors, warnings = validate_pack({"schemaVersion": SCHEMA_VERSION, "rules": migrated})
        if errors:
            raise ValueError("existing legacy target is invalid: " + "; ".join(errors))
        return accepted, ["existing legacy array will be migrated to Rule Pack v1", *warnings]
    accepted, errors, warnings = validate_pack(data)
    if errors:
        raise ValueError("existing target is invalid: " + "; ".join(errors))
    return accepted, warnings


def merge_rules(existing: list[dict[str, Any]], candidate: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[str], list[str]]:
    candidate_by_id = {rule["id"]: rule for rule in candidate}
    replaced = [rule["id"] for rule in existing if rule["id"] in candidate_by_id]
    merged = [candidate_by_id.pop(rule["id"], rule) for rule in existing]
    added = [rule["id"] for rule in candidate if rule["id"] in candidate_by_id]
    merged.extend(candidate_by_id[rule_id] for rule_id in added)
    return merged, replaced, added


def atomic_write(path: Path, pack: dict[str, Any]) -> str | None:
    path.parent.mkdir(parents=True, exist_ok=True)
    backup: Path | None = None
    if path.exists():
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        backup = path.with_name(f"{path.name}.backup-{stamp}")
        shutil.copy2(path, backup)

    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, prefix=f".{path.name}.", delete=False) as handle:
            temporary_name = handle.name
            json.dump(pack, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary_name, 0o600)
        os.replace(temporary_name, path)
    except Exception:
        if temporary_name:
            Path(temporary_name).unlink(missing_ok=True)
        raise
    return str(backup) if backup else None


def output(payload: dict[str, Any], exit_code: int = 0) -> int:
    json.dump(payload, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    return exit_code


def validate_command(candidate_path: Path) -> int:
    try:
        pack = read_json(candidate_path)
    except (OSError, json.JSONDecodeError) as error:
        return output({"ok": False, "command": "validate", "errors": [str(error)], "warnings": []}, 1)
    rules, errors, warnings = validate_pack(pack)
    return output(
        {"ok": not errors, "command": "validate", "candidate": str(candidate_path), "acceptedCount": len(rules), "errors": errors, "warnings": warnings},
        1 if errors else 0,
    )


def merge_command(candidate_path: Path, target_path: Path, apply: bool) -> int:
    try:
        candidate_pack = read_json(candidate_path)
        candidate, errors, warnings = validate_pack(candidate_pack)
        if errors:
            return output({"ok": False, "command": "merge", "errors": errors, "warnings": warnings}, 1)
        existing, target_warnings = load_target(target_path)
        merged, replaced, added = merge_rules(existing, candidate)
        backup = atomic_write(target_path, {"schemaVersion": SCHEMA_VERSION, "rules": merged}) if apply else None
    except (OSError, json.JSONDecodeError, ValueError) as error:
        return output({"ok": False, "command": "merge", "errors": [str(error)], "warnings": []}, 1)

    return output({
        "ok": True,
        "command": "merge",
        "mode": "applied" if apply else "plan",
        "target": str(target_path),
        "candidateCount": len(candidate),
        "resultCount": len(merged),
        "replacedIDs": replaced,
        "addedIDs": added,
        "backup": backup,
        "warnings": [*target_warnings, *warnings],
    })


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate = subparsers.add_parser("validate", help="validate a Rule Pack v1 candidate")
    validate.add_argument("candidate", type=Path)
    merge = subparsers.add_parser("merge", help="plan or apply an ID-based merge")
    merge.add_argument("candidate", type=Path)
    merge.add_argument("--target", type=Path, default=DEFAULT_TARGET)
    merge.add_argument("--apply", action="store_true", help="write the merged pack atomically; default is a read-only plan")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.command == "validate":
        return validate_command(args.candidate.expanduser())
    return merge_command(args.candidate.expanduser(), args.target.expanduser(), args.apply)


if __name__ == "__main__":
    raise SystemExit(main())
