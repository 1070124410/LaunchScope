# LaunchScope

<p align="center">
  <img src="assets/LaunchScope.png" width="144" alt="LaunchScope app icon">
</p>

<p align="center">
  <strong>Understand what runs in the background on your Mac.</strong><br>
  A native, local-first macOS control center for launch agents, daemons, and app-managed background tasks.
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/1070124410/LaunchScope/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/1070124410/LaunchScope?display_name=tag&sort=semver"></a>
  <a href="https://github.com/1070124410/LaunchScope/actions/workflows/release.yml"><img alt="Release workflow" src="https://github.com/1070124410/LaunchScope/actions/workflows/release.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
</p>

---

macOS background services are powerful, but their labels, plist files, and `launchctl` state are difficult to interpret. LaunchScope turns them into a clear, evidence-backed inventory: what each item is, who installed it, when it runs, what may break if it is disabled, and whether a management action actually took effect.

LaunchScope is built with native SwiftUI. Scanning and management happen locally, with no account, telemetry, or cloud service.

## Highlights

- **Readable background inventory** — understand `LaunchAgent`, `LaunchDaemon`, scheduled, disabled, failed, and dynamically registered items.
- **Evidence before action** — exact recognition rules, path-based inference, and unknown purposes remain visibly distinct.
- **Verified management** — start, stop, enable, or disable an item, then read system state back instead of trusting a successful command exit.
- **Private change history** — track additions, removals, configuration changes, and status changes for 30 days without storing commands, raw executable paths, PIDs, or resource metrics.
- **Extensible Rule Packs** — add private or niche recognition rules with a versioned, auditable JSON format and an in-app diff before installation.
- **Universal local MCP** — let MCP-compatible AI clients inspect privacy-limited snapshots, validate Rule Packs, and prepare candidates without direct launchd access.
- **One-click AI setup** — detect Codex, Claude Code, Cursor, and Claude Desktop, then register LaunchScope after showing the exact target and preserving existing configuration.
- **Native macOS experience** — responsive SwiftUI navigation, materials, spring feedback, accessibility support, and light/dark appearance.

## Quick start

### Install the latest release

```bash
curl -fsSL https://raw.githubusercontent.com/1070124410/LaunchScope/main/scripts/install.sh | bash
```

The installer downloads the latest GitHub Release, verifies its SHA-256 checksum, and installs `LaunchScope.app` into `/Applications`.

> Releases currently use ad-hoc signing. If Gatekeeper blocks the first launch, right-click LaunchScope in Finder and choose **Open**. The installer does not remove quarantine attributes or bypass macOS security controls.

### Build from source

```bash
git clone https://github.com/1070124410/LaunchScope.git
cd LaunchScope
make install
```

Requirements:

- macOS 14 Sonoma or later
- Xcode 16, or a compatible Swift 6 toolchain

## How it works

```text
launchd plist + launchctl + process metrics
                    │
                    ▼
             LaunchdScanner
                    │ factual snapshot
                    ▼
             PurposeCatalog
        exact rule / inference / unknown
                    │
          ┌─────────┴─────────┐
          ▼                   ▼
      SwiftUI app       private history
          │
          ▼ confirmed management only
     LaunchdManager ──► state readback
```

System reads, explanations, UI orchestration, and launchd mutation are deliberately separated. See [Architecture](docs/ARCHITECTURE.md) for the full boundary model.

## AI and MCP integration

LaunchScope includes a zero-dependency local stdio MCP server. It exposes seven focused tools for status, privacy-limited background items, recent changes, installed rules, Rule Pack validation, merge previews, and explicitly authorized candidate saves.

Open **AI Assistant** in the main sidebar to:

1. Confirm that the bundled MCP server is available.
2. See which supported AI clients are installed.
3. Review the exact configuration target.
4. Apply the integration with one confirmation, or copy the standard MCP configuration manually.

The MCP server **cannot** install a Rule Pack or start, stop, enable, or disable background tasks. AI-assisted recognition, rule installation, and launchd management remain separate actions.

Repository-aware agents can also discover the checked-in integrations:

- `.mcp.json` and `.cursor/mcp.json`
- `.agents/skills/launchscope/SKILL.md`
- `AGENTS.md`, `CLAUDE.md`, and `llms.txt`
- [AI integration guide](docs/AI_INTEGRATION.md)
- [Agent Protocol](docs/AGENT_PROTOCOL.md)

## Custom recognition rules

Local rules live at:

```text
~/Library/Application Support/LaunchScope/purpose-rules.json
```

Custom rules take precedence over the built-in catalog. Import a Rule Pack from LaunchScope to review added, updated, and unchanged rules before installation; an existing configuration is backed up and a stale preview is rejected.

See [Custom Rules](docs/CUSTOM_RULES.md), the [Rule Pack schema](docs/schema/purpose-rules-v1.schema.json), and the [example pack](examples/purpose-rules.example.json).

## Privacy and safety

- No account, telemetry SDK, analytics upload, or cloud recognition.
- No browser history, document contents, network traffic, or keyboard input is read.
- The MCP server consumes only the privacy-limited snapshot persisted by LaunchScope.
- Apple core services under `/System/Library` are hidden by default.
- System-wide management uses the standard macOS administrator authorization flow.
- Disabling an item never deletes its application, plist, configuration, or user data.
- Exported reports omit commands, arguments, logs, environment variables, PIDs, and resource metrics.

Read [Privacy](PRIVACY.md) and [Security](SECURITY.md) before sharing diagnostics or managing unfamiliar system-wide items.

## Development

```bash
swift test
./scripts/build-app.sh
open "dist/LaunchScope.app"
```

The release workflow tests, packages, checksums, and publishes tagged builds. Behavioral changes should include focused tests; Rule Pack examples should also pass the bundled validation tool.

## Project layout

```text
Sources/BackgroundButler/
├── Views/                         SwiftUI interface
├── LaunchdScanner.swift           system reads and parsing
├── PurposeCatalog.swift           explainable recognition
├── SnapshotHistoryStore.swift     privacy-limited local history
├── AIClientConfigurationManager.swift
│                                    bounded AI-client setup
├── AppStore.swift                 UI state and orchestration
└── LaunchdManager.swift           confirmed launchd mutations

mcp/launchscope_mcp.py             universal local MCP server
.agents/skills/launchscope/        agent workflow and Rule Pack tools
docs/                              protocol, architecture, and schemas
```

## Contributing

Contributions are welcome, especially focused recognition rules, parser fixtures, accessibility improvements, localization, and tests. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

For a recognition rule to enter the built-in catalog, it must use a stable, narrow selector and include reviewable evidence and disable impact. Private labels and organization-specific services belong in a local Rule Pack.

## License

LaunchScope is released under the [MIT License](LICENSE).

## Support the project

If LaunchScope saved you time or helped you understand your Mac, a small tip is sincerely appreciated. Thank you for supporting continued maintenance and new features.

<p align="center">
  <img src="assets/support-alipay.jpg" width="360" alt="Support LaunchScope via Alipay">
</p>

<p align="center"><strong>Thank you for your support · 感谢打赏与支持</strong></p>
