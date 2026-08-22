# 焊死版本配置审计

本分支只提取用户提供的 `.GlobalPreferences.plist` 中 `KBET…` 键。未出现的键使用 0.7.1 的运行时默认值，并在代码中显式固定。

| 项目 | 固定值 | 来源 |
|---|---:|---|
| 粘贴 X | `0.0` | 文件未保存，默认值 |
| 粘贴 Y | `-6.0` | `KBETPasteY` |
| 粘贴 SF | `doc.on.clipboard` | `KBETPasteSymbol` |
| 粘贴大小 | `17.0` | `KBETPasteIconPointSize` |
| 向左 X | `0.0` | `KBETLeftX` |
| 向左 Y | `-6.0` | `KBETLeftY` |
| 向左 SF | `chevron.backward.circle` | `KBETLeftSymbol` |
| 向左大小 | `20.5` | `KBETLeftIconPointSize` |
| 向右 X | `0.0` | 文件未保存，默认值 |
| 向右 Y | `-6.0` | `KBETRightY` |
| 向右 SF | `chevron.right.circle` | `KBETRightSymbol` |
| 向右大小 | `20.5` | `KBETRightIconPointSize` |
| 收起 X | `0.0` | `KBETDismissX` |
| 收起 Y | `-6.0` | `KBETDismissY` |
| 收起 SF | `keyboard.chevron.compact.down` | 文件未保存，默认值 |
| 收起大小 | `18.0` | `KBETDismissIconPointSize` |
| 长按时长 | `300 ms` | `KBETLongPressDurationMS` |
| 图标颜色 | 跟随地球键 | 文件未保存，默认值 |
| 按压区域 | `60.0 × 44.0` | 文件未保存，默认值 |
| 阴影 | 关闭 | `KBETShowTouchShadow` |
| 辅助线 | 关闭 | `KBETShowLayoutGuides` |

源文件还包含旧的全局 `KBETIconPointSize = 17.0`。四个独立大小键优先，因此它不会覆盖 `17.0 / 20.5 / 20.5 / 18.0`。
