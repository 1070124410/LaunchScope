# Security Policy

## Supported version

安全修复以最新源码和最新发布版本为准。

## Reporting a vulnerability

请不要在公开 Issue 中发布提权路径、敏感启动参数或能识别个人设备的信息。通过代码托管平台的私密安全报告功能联系维护者，并提供最小复现、影响范围和系统版本。

## Privileged operations

用户级任务直接通过当前用户的 `launchctl` 域管理。系统级任务由 macOS 标准授权流程执行；应用不会保存管理员密码。禁用操作修改 launchd 的 disabled 状态，但不会删除应用、plist 或用户数据。
