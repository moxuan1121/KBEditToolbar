# KBEditToolbar — 键盘编辑工具条

在系统键盘底部加入一排按钮：**粘贴、光标向左、光标向右、收起键盘**。短按和长按均带轻触反馈。

## 操作

| 按钮 | 短按 | 长按 |
|---|---|---|
| 粘贴 | 粘贴剪贴板内容 | 全选当前输入框并复制 |
| 向左 | 光标向左移动一个字符 | 光标移动到文本最开头 |
| 向右 | 光标向右移动一个字符 | 光标移动到文本最末尾 |
| 收起键盘 | 收起键盘 | 清空当前输入框全部内容 |

长按识别时间为 0.5 秒；识别成长按后不会再触发该按钮的短按动作。

### 拼音等组合输入的一键清空

九宫格拼音、日文等输入法会把尚未确认的字符保存在 marked/composing text 中。旧版长按清空最终调用 `deleteFromInput`，因此可能只删除一个拼音键位。0.3.0 会按以下顺序处理：

1. 找到并清除 `markedTextRange`。
2. 调用 `unmarkText` 结束当前组合输入。
3. 重新获取完整 document range，通过 `replaceRange:withText:@""` 一次清空。
4. 仅在输入代理不支持范围替换时，才退回“全选后删除”的兼容路径。

## 设置内独立调整布局

安装 PreferenceLoader 后，打开系统 **设置 → 键盘编辑工具条**。四个按钮各有独立的 X、Y 滑块，共 8 项：

- 粘贴按钮：`KBETPasteX`、`KBETPasteY`
- 向左按钮：`KBETLeftX`、`KBETLeftY`
- 向右按钮：`KBETRightX`、`KBETRightY`
- 收起键盘按钮：`KBETDismissX`、`KBETDismissY`
- 每个按钮都有独立的 SF Symbol 名称和图标大小（默认 22.0 pt）

X 负值向左、正值向右；Y 负值向上、正值向下。图标大小和 X/Y 位置均改为数字输入，可自定义到小数点后一位，不再按滑块档位变化。每个值只作用于对应按钮，不会一起移动。设置页底部提供“恢复默认布局”。

0.4.0 会自动寻找系统地球键和麦克风键的实际中心，把四个工具按钮插入两者之间。默认顺序为：

`地球 → 粘贴 → 向左 → 向右 → 收起键盘 → 麦克风`

这六个中心点采用相同间距，能够适配 iPhone 13 Pro Max 等不同宽度的设备。若系统控件暂时无法识别，则退回等价的六列比例位置。工具条的透明容器只接收四个工具按钮自身的触摸，其他区域会把点击传递给下层，因此不会再遮挡地球键和语音输入键。

0.3.x 的 Y 偏移是从整个键盘中线计算的，与 0.4.0 的底栏坐标不兼容；首次运行 0.4.0 会自动清除旧偏移并切换到新的六等距默认布局。新的调节范围为 X `-500～500`、Y `-400～400`，足以覆盖 iPhone 13 Pro Max 的键盘区域。

## 0.5.0 更新

- 四个图标依次使用 `arrow.up.doc.on.clipboard`、`arrow.left.circle`、`arrow.right.circle`、`keyboard.chevron.compact.down`。
- 设置中可统一调整四个工具图标的显示大小，按钮触控区域保持不变。
- 布局偏移迁移到带 `KBET` 前缀的全局偏好键，修复设置 App 生效但微信、抖音仍保持默认高度的问题。
- 长按收起键盘会同时清除输入框内容、输入法内部拼音组合和候选缓存，避免下一次输入时旧内容重新出现。

## 0.6.0 更新

- 粘贴、向左、向右、收起键盘四个按钮都可分别输入自定义 SF Symbol 名称；名称无效时自动回退到该按钮的默认图标。
- 四个按钮的图标大小改为分别调节，互不影响，按钮触控区域保持不变。
- 长按触发时长可用毫秒值自定义，默认 `500 ms`。设置项不设输入上下限，负数运行时按 `0 ms` 处理。

## 粘贴修复

旧实现从键盘 Dock 调用 `sendAction:@selector(paste:) to:nil`，部分系统版本和 App 中无法通过响应链找到真正的输入对象。现在参考 [DockX](https://github.com/udevsharold/dockx) 的实现：

1. 从 `UIKeyboardImpl` 获取 `privateInputDelegate`，不可用时再取 `inputDelegate`。
2. 直接对输入代理调用 `paste:`。
3. 输入代理不支持 `paste:` 时，读取系统剪贴板并通过 `UIKeyboardImpl insertText:` 插入纯文本。

全选后复制、全选后删除会等待 0.05 秒再执行第二个动作，以兼容异步更新选区的远程输入代理。WebKit 输入框移动到首尾时使用 DockX 相同的 WebKit 编辑命令兼容分支。

## 云端构建

仓库的 GitHub Actions 只构建 **Dopamine RootHide** 使用的 roothide `.deb`：

1. 推送到 `main` 或 `master` 会自动开始构建。
2. 在 Actions 运行的 Artifacts 中下载 `KBEditToolbar-roothide-deb`。
3. 推送 `v*` 标签时，还会把 `.deb` 附加到对应 GitHub Release。

## 安装与验证

用 Sileo/Zebra 安装 `.deb`，或通过 `dpkg -i` 安装后重启 SpringBoard。打开备忘录或任意输入框，逐项验证短按和长按动作。

## 项目结构

- `Tweak.x`：独立按钮布局、输入代理解析、粘贴与长按动作。
- `KBEditToolbar.plist`：注入过滤器（`com.apple.UIKit`）。
- `Makefile` / `control`：roothide、arm64 + arm64e、软件包元数据。
- `kbedittoolbarprefs/`：系统设置内的 8 个独立 X/Y 滑块与重置按钮。
- `.github/workflows/build.yml`：macOS 云端构建并上传 roothide `.deb`。
