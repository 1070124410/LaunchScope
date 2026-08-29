# Architecture

LaunchScope 把“读取事实”“解释事实”和“改变状态”分成三层。

## 数据流

1. `LaunchdScanner` 读取 plist、`launchctl` 和进程指标，生成 `LaunchItem`。
2. `PurposeCatalog` 用本地规则解释用途；不能确认时只做路径推断或标记未知。
3. `SystemBackgroundServiceRepository` 为 UI 提供单一快照接口，并把管理动作交给 `LaunchdManager`。
4. `AppStore` 负责筛选、排序、确认流程和操作后的重新扫描。
5. SwiftUI 视图只消费状态，不直接执行 shell 命令。

## 关键边界

- `BackgroundServiceRepository` 是系统实现和测试替身之间的边界。
- `PurposeRule` 是识别能力的扩展边界；本地规则优先于内置规则。
- `LaunchdManager` 是唯一允许改变 launchd 状态的模块。
- `ReportExporter` 定义可公开诊断信息的最小集合。

## 操作语义

“停止”只卸载当前任务，应用或守护逻辑以后可能重新加载它。“禁用”记录长期禁用状态并尝试停止当前实例。“启用”解除禁用，但不会承诺任务立刻运行。所有操作都应在执行后重新读取真实状态。

## 后续扩展

新的数据来源应先转换成 `LaunchItem`，不要把来源细节渗透到视图。新的识别器应保留置信度并提供可审计依据，不应直接用不可解释的模型输出覆盖系统事实。
