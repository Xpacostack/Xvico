# 本地配置与热重载 / Local configuration and hot reload

Xvico 的按键映射、应用场景、快捷指令和遥控器输入参数保存在同一份文件中：

```text
~/Library/Application Support/Xvico/config.json
```

在 **设备设置 → 功能映射 → 配置文件** 展开后，可以查看状态并打开文件夹。界面编辑和外部文件编辑使用同一份行为配置。保存有效 JSON 后，应用约在 0.75 秒内检测变化；正在按键、触控、拖动或等待双击判定时，等这次操作结束才应用。不需要重启或重新连接遥控器。

The GUI and external editor share this behavior file. A valid JSON edit is normally detected within about 0.75 seconds. Applying it waits for held buttons, touch gestures, dragging and pending double-click decisions to finish. No reconnect or relaunch is required. Find the folder under **Device Settings → Function Mapping → Configuration file**.

## 格式 / Format

这是 **JSON，不是 JSONC**，不接受注释或尾随逗号。顶层的 `format` 与 `schemaVersion` 必须保持不变。应用生成的文件包含所有当前配置；建议从当前文件复制后只修改所需字段。例子见 [config.example.json](config.example.json)。示例是全量替换时的演示，不要直接覆盖自己的配置，否则示例的空场景列表会移除现有场景。

This is **JSON, not JSONC**: comments and trailing commas are not supported. Keep `format` and `schemaVersion` unchanged. Prefer editing a copy of the generated configuration. [config.example.json](config.example.json) demonstrates the schema; replacing your configuration with it replaces your scenes with its empty list.

| 字段 / Field | 内容 / Contents |
| --- | --- |
| `format` | `Xvico.Configuration` |
| `schemaVersion` | 当前为 `1` / Currently `1` |
| `settings` | 全局映射、输入参数、界面语言和后台显示设置 / Global bindings, input tuning, language and background appearance |
| `scenes` | 有序应用场景；绑定按现有规则继承全局设置 / Ordered app scenes; bindings inherit global values using the existing rules |
| `shortcuts` | 已保存的快捷指令 / Saved phrase actions |
| `learnedUsages` | 自定义 HID 用法到遥控器按键的对应表 / Learned HID usages mapped to remote keys |

动作和按键标识沿用现有导入/导出格式，部分标识为中文。场景 UUID 必须唯一，名称不能为空。场景顺序保留不变；同一个应用绑定多个启用场景时，仍按列表顺序匹配第一个。`settings` 中未提供的已有可选参数采用默认值，场景中未覆盖的按键继承全局映射。外部修改应用级绑定后，实际输出与界面读取同一个解析器。

Action and key identifiers retain the existing import/export format, including some Chinese identifiers. Scene UUIDs must be unique and names nonempty. Scene order is preserved; when multiple enabled scenes match an app, the first wins. Missing optional settings use defaults; missing app bindings inherit globals. Runtime output and the editor share the binding resolver.

## 保存、冲突与恢复 / Saving, conflicts and recovery

- 写入使用权限为 `0600` 的临时文件，完整写入后原子替换；配合文件锁防止多个 Xvico 实例同时写入。参数范围、枚举、UUID、格式版本和文件大小（最多 8 MiB）均在应用前检查。
- 文件错误时，当前有效配置继续运行，不会用空映射覆盖。修正文件后自动重新读取。
- 发现界面和外部文件都被修改时，不自动选择一方。在配置入口点“使用文件配置”，或“保存当前配置”。后者会先备份当前外部内容，再替换文件。
- 未保存的界面版本会尽力写入 `config.unsaved.json`；目录不可写时也无法保存此副本。它不会自动覆盖当前配置。在配置文件入口点击“恢复未保存配置”可明确恢复；应用会先备份当前外部文件，再验证、保存并应用此副本。
- `config.last-good.json` 是最近有效副本。启动时主文件损坏，可在内存中恢复此副本，保留损坏原文件供修复。主文件被移走时不会偷偷重建，需明确保存当前配置。
- `config.external-backup.json` 保留最近一次明确选择“保存当前配置”时覆盖的外部版本；它不是完整的版本历史。
- 第一次迁移前的原始偏好数据保存在 `legacy-pre-migration.plist`。旧 UserDefaults 仍作为回退旧应用的兼容镜像；新版启动后以 JSON 为准，不再合并外部对旧偏好键的修改。

Writes use private `0600` temporary files and atomic replacement, plus an advisory lock between Xvico instances. External-editor conflicts are detected by checking the previously accepted bytes before saving; this is optimistic detection, not a transaction guarantee for editors that do not participate in the lock. Invalid edits keep the last valid runtime configuration. GUI/file conflicts require an explicit choice. The recovery files above are local only; `config.unsaved.json` is best-effort and never automatically applied. Use **Recover unsaved configuration** to restore it explicitly, retaining a backup of the external version first. The external backup is a single recovery copy, not version history. Legacy preferences remain rollback mirrors; after migration, editing those old keys does not override the JSON.

## 授权与隐私边界 / Authorization and privacy

麦克风来源、输入法模式与触发键仍由语音设置独立保存；本轮配置文件不包含这些语音偏好。系统隐私权限、管理员批准、已保存后台授权、签名材料、Apple 运行时路径、凭据和音频不写入此文件，修改 JSON 也不能批准这些权限或自动启动采音。主题、边栏和当前编辑场景属于独立界面偏好。

Voice-source, input-method and trigger-key preferences remain in their existing voice settings. This document contains no system privacy grants, administrator approvals, saved backend authorization, signing material, Apple runtime locations, credentials or audio. Editing JSON cannot grant permissions or start audio capture. Theme, sidebar visibility and the selected editing scene remain separate UI preferences.

映射内可能含私人文本或应用信息，不应未经检查就上传配置和恢复副本。本地开发记录及个人配置不加入 Git。

Mappings can contain private text and app information. Inspect configurations and recovery copies before sharing them. Personal configurations and local development evidence are not committed to Git.
