# Custom purpose rules

自定义规则文件位于：

```text
~/Library/Application Support/LaunchScope/purpose-rules.json
```

文件顶层是 JSON 数组。每条规则包含：

| 字段 | 类型 | 说明 |
|---|---|---|
| `match` | string[] | 在 Label、可执行路径和参数拼成的文本中做不区分大小写的包含匹配 |
| `name` | string | 页面显示名称 |
| `summary` | string | 用途和关闭影响 |
| `vendor` | string | 厂商、项目或团队 |
| `category` | string | 页面分组类别 |

```json
[
  {
    "match": ["com.example.worker", "/Applications/Example.app"],
    "name": "Example 后台服务",
    "summary": "为 Example 提供后台同步；禁用后自动同步会停止。",
    "vendor": "Example",
    "category": "效率工具"
  }
]
```

规则按文件顺序匹配，第一个命中的规则生效，并优先于应用内置目录。尽量使用稳定、唯一的 Label；宽泛的单词可能误识别其他任务。保存文件后返回应用刷新。
