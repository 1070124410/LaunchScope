# Architecture

LaunchScope 把“读取事实”“解释事实”和“改变状态”分成三层。

## 数据流

1. `LaunchdScanner` 读取 plist、`launchctl` 和进程指标，生成 `LaunchItem`。
2. `PurposeCatalog` 用本地规则解释用途；不能确认时只做路径推断或标记未知。
3. `SystemBackgroundServiceRepository` 为 UI 提供单一快照接口，并把管理动作交给 `LaunchdManager`。
4. `AppStore` 负责筛选、排序、确认流程和操作后的重新扫描。
5. `SnapshotHistoryStore` 接收已完成的快照，计算本地差异并持久化隐私裁剪后的基线与最近变化。
6. SwiftUI 视图只消费状态，不直接执行 shell 命令。

## 关键边界

- `BackgroundServiceRepository` 是系统实现和测试替身之间的边界。
- `PurposeRule` 是识别能力的扩展边界；Rule Pack v1 提供版本、稳定 ID、精确选择器和证据字段，本地规则优先于内置规则。
- `LaunchdManager` 是唯一允许改变 launchd 状态的模块。
- `ReportExporter` 定义可公开诊断信息的最小集合。
- `AgentContextExporter` 定义交给外部 AI 的隐私最小集合；它省略参数、运行时标识和环境变量。
- `SnapshotHistoryStore` 是可降级的本地辅助能力；写入失败不能让实时扫描失败。历史文件不保存参数、原始程序路径、PID 或资源指标。
- 本机 MCP 是协议适配层：只读取 `SnapshotHistoryStore` 的隐私快照和 Purpose Rule Pack，并复用 `rules_tool.py` 校验/合并语义；它不直接访问 `LaunchdScanner` 或 `LaunchdManager`。
- `AIClientConfigurationManager` 只扫描已知客户端位置。Codex/Claude Code 通过已发现的官方 CLI 注册；JSON 客户端仅合并 `mcpServers.launchscope`，写前备份且不覆盖无关配置。

## 操作语义

“停止”只卸载当前任务，应用或守护逻辑以后可能重新加载它。“禁用”记录长期禁用状态并尝试停止当前实例。“启用”解除禁用，但不会承诺任务立刻运行。所有操作都应在执行后重新读取真实状态。

## 后续扩展

新的数据来源应先转换成 `LaunchItem`，不要把来源细节渗透到视图。新的识别器应保留置信度并提供可审计依据，不应直接用不可解释的模型输出覆盖系统事实。

AI 扩展遵循“隐私快照/上下文导出 → 候选 Rule Pack → 校验与预演 → 明确确认后安装 → 应用重新读取”的协议。MCP、仓库 skill 和离线 CLI 共用同一 Rule Pack source of truth。AI 不在应用进程内运行，Rule Pack 也不能表达管理动作；实际状态变更仍只能经过 `LaunchdManager`。
