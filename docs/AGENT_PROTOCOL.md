# LaunchScope Agent Protocol

LaunchScope 的 AI 集成是一个本地、可审计的文件协议，不是应用内模型调用。应用负责提供最小上下文和读取有效规则；AI 负责生成候选规则；校验工具负责在写入前拒绝不完整或过宽的配置。

## 协议对象

### Recognition Request v1

在用途未知的详情页点击“复制给 AI 识别”，应用会生成：

```json
{
  "protocol": "launchscope.recognition-request",
  "protocolVersion": 1,
  "task": "identify-purpose-rule",
  "service": {
    "label": "com.example.worker",
    "domain": "user",
    "program": "/Applications/Example.app/Contents/MacOS/worker",
    "source": "$HOME/Library/LaunchAgents/com.example.worker.plist"
  },
  "requestedOutput": {
    "protocol": "launchscope.purpose-rules",
    "schemaVersion": 1,
    "preferredSelector": "labels"
  },
  "privacy": {
    "argumentsOmitted": true,
    "environmentOmitted": true,
    "runtimeIdentifiersOmitted": true
  }
}
```

这里不会包含启动参数、环境变量、PID、退出码或资源数据。`$HOME` 会替换当前用户名。

### Purpose Rule Pack v1

候选输出必须符合 [JSON Schema](schema/purpose-rules-v1.schema.json)：

```json
{
  "schemaVersion": 1,
  "rules": [
    {
      "id": "com.example.worker",
      "labels": ["com.example.worker"],
      "name": "Example 后台同步",
      "summary": "为 Example 提供后台同步。",
      "vendor": "Example",
      "category": "效率工具",
      "evidence": "Example 官方帮助文档与本机 plist",
      "disableImpact": "自动同步会停止，手动打开应用仍可使用。"
    }
  ]
}
```

选择器的语义如下：

- `labels`：对 launchd Label 做不区分大小写的完整匹配，优先使用。
- `programPrefixes`：对可执行文件绝对路径做不区分大小写的前缀匹配。
- `match`：在 Label、程序路径和参数的拼接文本中做包含匹配，仅用于兼容旧规则。
- 同一条规则中的选择器是“任一命中”；规则按数组顺序匹配，第一个命中的规则生效。
- 自定义规则始终优先于应用内置目录。

`id` 是稳定的配置身份，不是显示名称。修改同一项时保留 `id`；不同用途使用不同 `id`。`evidence` 应写可复核的来源类别或文档名，不放访问令牌、Cookie、完整私有 URL 或个人路径。证据不足时保留“用途未知”，不要生成规则。

## 校验与安装

项目 skill 自带离线工具：

```bash
python3 .agents/skills/launchscope/scripts/rules_tool.py validate candidate.json
python3 .agents/skills/launchscope/scripts/rules_tool.py merge candidate.json
python3 .agents/skills/launchscope/scripts/rules_tool.py merge candidate.json --apply
```

`validate` 和默认的 `merge` 都是只读；后者输出合并计划。`merge --apply` 才会写入 `~/Library/Application Support/LaunchScope/purpose-rules.json`，写入采用同目录原子替换，并在已有文件旁生成带 UTC 时间戳的备份。候选规则按 `id` 替换同 ID 规则，其余规则保持原顺序，新 ID 追加到末尾。

LaunchScope 自身也提供“导入 Rule Pack”入口。选择文件后必须先查看新增、更新、未变化和安装后总数；只有点击预览页的“安装规则”才会写入。如果目标文件在预览后发生变化，应用会拒绝覆盖并要求重新预览。

应用仍兼容旧版顶层数组，但会显示迁移警告。工具在合并时会给旧规则生成内容派生的稳定 `legacy.<hash>` ID，并将目标升级为 v1。

## 权限边界

生成、校验规则不会改变 launchd 状态。安装 Rule Pack 只改变 LaunchScope 的本地识别结果。启动、停止、启用和禁用仍必须在应用内单独确认，并由 `LaunchdManager` 执行和回读验证；识别规则不能表达或触发这些动作。
