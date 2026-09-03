---
name: launchscope
description: Inspect LaunchScope recognition requests and create, validate, or install local Purpose Rule Packs. Use for unknown macOS background items shown by LaunchScope or edits to purpose-rules.json; do not use for generic launchd development.
---

# LaunchScope rules

Treat identification and background-service management as separate actions. A recognition rule explains an item; it never authorizes starting, stopping, enabling, or disabling it.

## Rule workflow

1. Read [`../../../docs/AGENT_PROTOCOL.md`](../../../docs/AGENT_PROTOCOL.md) before creating or changing a rule. Finish when the request version, selector semantics, evidence boundary, and write boundary are accounted for.
2. Use the supplied Recognition Request as the evidence baseline. Prefer an exact `labels` selector. State when purpose or disable impact remains an inference; if the available evidence does not support a stable purpose, leave the item unknown and report what would verify it.
3. Write a Purpose Rule Pack v1 candidate outside the installed Application Support path. Include only sourced, non-secret evidence and run:

   ```bash
   python3 .agents/skills/launchscope/scripts/rules_tool.py validate <candidate.json>
   ```

   Finish when validation returns `ok: true` and every warning is either removed or explicitly explained.
4. Installing or merging a candidate is a separate local write. For interactive use, direct the user to “更多 → 自定义识别规则 → 导入 Rule Pack” so they can inspect the in-app diff and confirm installation. For automation, act only when the user explicitly asks to apply or install: first show the read-only plan with `merge <candidate.json>`, then run the same command with `--apply`. Report the target, accepted count, replaced IDs, and backup path.

For requests to change actual launchd state, route the user through LaunchScope's confirmation UI. Do not use the rules tool or raw `launchctl` as a substitute for the application's authorization and readback checks.
