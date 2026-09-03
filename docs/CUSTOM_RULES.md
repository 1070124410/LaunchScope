# Custom purpose rules

自定义规则文件位于：

```text
~/Library/Application Support/LaunchScope/purpose-rules.json
```

推荐使用带版本号的 Rule Pack。完整机器可读约束见 [Purpose Rule Pack v1 Schema](schema/purpose-rules-v1.schema.json)，AI 协作流程见 [Agent Protocol](AGENT_PROTOCOL.md)。

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | 规则的稳定身份，同一用途更新时保持不变 |
| `labels` | string[] | 对 Label 做不区分大小写的完整匹配，推荐使用 |
| `programPrefixes` | string[] | 对可执行文件绝对路径做前缀匹配 |
| `match` | string[] | 兼容旧版的宽泛包含匹配，谨慎使用 |
| `name` | string | 页面显示名称 |
| `summary` | string | 可核验的用途说明 |
| `vendor` | string | 厂商、项目或团队 |
| `category` | string | 页面分组类别 |
| `evidence` | string | 可复核的来源类别或文档名，可选 |
| `disableImpact` | string | 禁用后受影响的能力，可选 |

```json
{
  "schemaVersion": 1,
  "rules": [
    {
      "id": "com.example.worker",
      "labels": ["com.example.worker"],
      "name": "Example 后台服务",
      "summary": "为 Example 提供后台同步。",
      "vendor": "Example",
      "category": "效率工具",
      "evidence": "Example 官方帮助文档与已安装 plist",
      "disableImpact": "自动同步会停止。"
    }
  ]
}
```

同一规则内任一选择器命中即视为匹配。规则按文件顺序匹配，第一个命中的规则生效，并优先于应用内置目录。尽量使用稳定、唯一的 Label；宽泛的单词可能误识别其他任务。保存文件后返回应用刷新。

旧版顶层 JSON 数组仍可读取，但应用会显示迁移提示。可使用项目 skill 中的工具校验候选文件，并在明确确认后原子合并到本机规则路径：

```bash
python3 .agents/skills/launchscope/scripts/rules_tool.py validate candidate.json
python3 .agents/skills/launchscope/scripts/rules_tool.py merge candidate.json
python3 .agents/skills/launchscope/scripts/rules_tool.py merge candidate.json --apply
```

也可以在应用的“更多 → 自定义识别规则 → 导入 Rule Pack”中选择候选文件，核对差异预览后安装。预览不会写入；安装会保留原文件备份并刷新后台项识别结果。
