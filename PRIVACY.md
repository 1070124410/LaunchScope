# Privacy

LaunchScope 采用本地优先设计：

- 不创建网络请求；
- 不使用 AI 或云端识别；
- 不采集遥测、崩溃报告或设备标识；
- 不读取浏览器历史、文档正文、剪贴板或键盘输入；
- 自定义规则仅保存在当前用户的 Application Support 目录。

应用会读取 `launchctl`、LaunchAgents/LaunchDaemons plist 和对应进程的资源占用，以展示后台任务的用途与状态。详情页可能显示包含用户名的本机路径。

Markdown 报告只包含名称、Label、状态、范围、来源和识别依据，不包含命令、参数、PID、日志、环境变量或网络内容。公开报告前仍应人工检查 Label 和来源字段。
