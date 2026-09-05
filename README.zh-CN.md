# LaunchScope

<p align="center">
  <img src="assets/LaunchScope.png" width="144" alt="LaunchScope 应用图标">
</p>

<p align="center">
  <strong>看懂 Mac 上每一个后台项。</strong><br>
  一款原生、本地优先的 macOS 后台任务识别与管理工具。
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/1070124410/LaunchScope/releases/latest"><img alt="最新版本" src="https://img.shields.io/github/v/release/1070124410/LaunchScope?display_name=tag&sort=semver"></a>
  <a href="https://github.com/1070124410/LaunchScope/actions/workflows/release.yml"><img alt="发布状态" src="https://github.com/1070124410/LaunchScope/actions/workflows/release.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
</p>

---

macOS 的后台服务能力很强，但 `LaunchAgent`、`LaunchDaemon`、plist 和 `launchctl` 状态对普通用户并不友好。LaunchScope 把这些信息整理成可理解、可核对、可管理的本机清单：它是什么、由谁安装、何时运行、关闭后可能影响什么，以及一次管理操作是否真正生效。

LaunchScope 使用原生 SwiftUI 构建。扫描和管理都在本机完成，不需要账户，不采集遥测，也不依赖云端服务。

## 核心功能

- **看懂后台项**：统一查看 `LaunchAgent`、`LaunchDaemon`、定时任务、已禁用、运行异常和应用动态注册的任务。
- **先给证据，再做决定**：明确区分精确规则、路径推断和用途未知，不把猜测包装成事实。
- **管理结果可验证**：启动、停止、启用或禁用后重新读取系统状态，不把命令正常退出直接当作成功。
- **隐私受限的变化历史**：保留最近 30 天的新增、移除、配置与状态变化，不保存命令参数、原始程序路径、PID 或资源指标。
- **可扩展 Rule Pack**：通过版本化、可审计的 JSON 补充私有或小众工具，安装前在 App 内查看差异。
- **通用本机 MCP**：让兼容 MCP 的 AI 读取隐私快照、校验规则和准备候选文件，但不能直接操作 launchd。
- **AI 一键接入**：检测 Codex、Claude Code、Cursor 和 Claude Desktop，显示目标配置并在确认后安全注册。
- **原生 macOS 体验**：SwiftUI 导航、材质、弹簧反馈、深浅色和辅助功能支持。

## 快速安装

### 安装最新 Release

```bash
curl -fsSL https://raw.githubusercontent.com/1070124410/LaunchScope/main/scripts/install.sh | bash
```

安装脚本会下载最新 GitHub Release、校验 SHA-256，并把 `LaunchScope.app` 安装到 `/Applications`。

> 当前 Release 使用 ad-hoc 签名。第一次打开若被 Gatekeeper 拦截，请在 Finder 中右键 LaunchScope 并选择“打开”。安装脚本不会移除 quarantine，也不会绕过 macOS 安全机制。

### 从源码构建

```bash
git clone https://github.com/1070124410/LaunchScope.git
cd LaunchScope
make install
```

环境要求：

- macOS 14 Sonoma 或更高版本
- Xcode 16，或兼容 Swift 6 的工具链

## 工作原理

```text
launchd plist + launchctl + 进程指标
                    │
                    ▼
             LaunchdScanner
                    │ 事实快照
                    ▼
             PurposeCatalog
          精确规则 / 路径推断 / 未知
                    │
          ┌─────────┴─────────┐
          ▼                   ▼
      SwiftUI App       隐私受限的历史
          │
          ▼ 仅限用户确认后的管理操作
     LaunchdManager ──► 系统状态回读
```

系统读取、用途解释、UI 编排和 launchd 写操作被明确分层。完整边界见[架构说明](docs/ARCHITECTURE.md)。

## AI 与 MCP

LaunchScope 内置零依赖的本机 stdio MCP Server，提供 7 个聚焦工具：集成状态、隐私后台项、近期变化、已安装规则、Rule Pack 校验、合并预演，以及经用户明确授权后的候选文件保存。

在主侧边栏打开“AI 助手”，即可：

1. 确认安装包是否包含 MCP Server。
2. 查看本机已经安装哪些受支持的 AI 客户端。
3. 核对即将修改的准确配置位置。
4. 一次确认完成接入，或复制标准 MCP 配置手动安装。

MCP **不能**安装 Rule Pack，也不能启动、停止、启用或禁用后台任务。AI 识别、规则安装与 launchd 管理始终是三个独立动作。

仓库也提供以下自动发现入口：

- `.mcp.json` 与 `.cursor/mcp.json`
- `.agents/skills/launchscope/SKILL.md`
- `AGENTS.md`、`CLAUDE.md` 与 `llms.txt`
- [AI 接入说明](docs/AI_INTEGRATION.md)
- [Agent Protocol](docs/AGENT_PROTOCOL.md)

## 自定义识别规则

本地规则默认保存在：

```text
~/Library/Application Support/LaunchScope/purpose-rules.json
```

自定义规则优先于内置目录。通过 LaunchScope 导入 Rule Pack 时，可以在安装前核对新增、更新、未变化规则和安装后总数；已有配置会创建备份，预览后目标发生变化时会拒绝覆盖。

字段说明与示例见[自定义规则](docs/CUSTOM_RULES.md)、[Rule Pack Schema](docs/schema/purpose-rules-v1.schema.json)和[示例文件](examples/purpose-rules.example.json)。

## 隐私与安全

- 不需要账户，不接入遥测 SDK，不上传分析数据，也不调用云端识别。
- 不读取浏览器历史、文档正文、网络流量或键盘输入。
- MCP 只消费 LaunchScope 已持久化的隐私快照。
- 默认隐藏 `/System/Library` 下的 Apple 核心服务。
- 整台 Mac 范围的管理使用 macOS 标准管理员授权流程。
- 禁用后台项不会删除应用、plist、配置或用户数据。
- 导出的报告不包含命令、参数、日志、环境变量、PID 或资源指标。

分享诊断信息或管理陌生的系统级后台项前，请阅读[隐私说明](PRIVACY.md)和[安全策略](SECURITY.md)。

## 开发

```bash
swift test
./scripts/build-app.sh
open "dist/LaunchScope.app"
```

Release Workflow 会在 tag 推送后执行测试、打包、生成校验和并发布。行为变化应带聚焦测试；Rule Pack 示例还应通过项目内置校验工具。

## 项目结构

```text
Sources/BackgroundButler/
├── Views/                         SwiftUI 界面
├── LaunchdScanner.swift           系统读取与解析
├── PurposeCatalog.swift           可解释的用途识别
├── SnapshotHistoryStore.swift     隐私受限的本地历史
├── AIClientConfigurationManager.swift
│                                    有边界的 AI 客户端接入
├── AppStore.swift                 UI 状态与编排
└── LaunchdManager.swift           经确认的 launchd 状态修改

mcp/launchscope_mcp.py             通用本机 MCP Server
.agents/skills/launchscope/        Agent 工作流与 Rule Pack 工具
docs/                              协议、架构与 Schema
```

## 参与贡献

欢迎提交聚焦的通用识别规则、解析样例、辅助功能改进、多语言和测试。提交 Pull Request 前请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

进入内置目录的识别规则必须使用稳定、足够窄的选择器，并提供可复核证据和禁用影响。包含私人 Label 或组织内部服务的规则应保留在本地 Rule Pack 中。

## License

LaunchScope 使用 [MIT License](LICENSE) 开源。

## 感谢支持

如果 LaunchScope 帮你节省了时间，或让你更安心地理解 Mac 上的后台任务，欢迎请作者喝杯奶茶。每一份支持都会用于持续维护和新功能迭代，感谢你的打赏与鼓励。

<p align="center">
  <img src="assets/support-alipay.jpg" width="360" alt="通过支付宝支持 LaunchScope">
</p>

<p align="center"><strong>感谢打赏，感谢你支持 LaunchScope</strong></p>
