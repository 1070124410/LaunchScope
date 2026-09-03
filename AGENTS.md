# LaunchScope agent guide

- For changes to background-item recognition or `purpose-rules.json`, use the project skill at [`.agents/skills/launchscope/SKILL.md`](.agents/skills/launchscope/SKILL.md) and follow [`docs/AGENT_PROTOCOL.md`](docs/AGENT_PROTOCOL.md).
- Keep system reads in `LaunchdScanner`, explanations in `PurposeCatalog`, UI orchestration in `AppStore`, and all launchd mutations in `LaunchdManager`.
- Preserve the evidence boundary: exact rule, path inference, and unknown are distinct states. A generated rule needs a stable selector and a reviewable source.
- Treat rule installation and launchd management as separate writes. Management succeeds only after system-state readback, not when a command merely exits successfully.
- Run `swift test` after behavior changes. Also validate changed Rule Pack examples with the project skill's `rules_tool.py`.
