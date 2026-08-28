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

四个工具按钮从最左侧到最右侧组成一块固定的水平触摸板，按钮之间的空隙也可开始或继续滑动：向左滑删除光标左侧直到文本开头的全部内容；向右滑删除光标右侧直到文本末尾的全部内容。手势确认时触发一次轻触反馈；触摸板范围外继续穿透，不影响地球键和麦克风。本功能焊死在固定版中，不提供设置项。

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

这六个中心点采用相同间距，能够适配 iPhone 13 Pro Max 等不同宽度的设备。若系统控件暂时无法识别，则退回等价的六列比例位置。工具条的透明容器只在四个工具按钮的整体包围框内接收按钮与滑动触摸，包围框以外继续传递给下层，因此不会遮挡地球键和语音输入键。

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

## 0.7.0 更新

- 图标颜色默认实时跟随系统地球键；也可关闭跟随，通过系统取色器或十六进制色值自定义颜色。
- 按压区域宽度和高度可分别输入到小数点后一位，并可打开阴影查看真实触控范围，调节完成后手动关闭阴影。
- 可显示布局辅助线：一条横线标示统一高度，六条竖线标示地球、四个工具按钮和语音输入按钮的等距中心。

### 0.7.1 修复

- 修复开关型偏好值未识别 `CFBoolean`，导致布局辅助线和按压区域阴影始终保持关闭的问题，同时修复“跟随地球键颜色”开关无法关闭。

## 0.8.0 更新

- 配置迁移到 RootHide 独立文件 `/var/mobile/Library/Preferences/cn.example.kbedittoolbar.preferences.plist`，不再长期占用系统 `.GlobalPreferences.plist`。
- 首次升级自动复制旧 `KBET…` 设置；独立文件成功建立后，只删除全局偏好中的本插件键，不影响其他系统或插件配置。
- 配置改为启动时读取、Darwin 通知到达时刷新，布局阶段只访问内存缓存，避免每次布局反复读取磁盘。
- 启用 `-Os`、函数/数据分段和链接器死代码裁剪，降低动态库与 SpringBoard/键盘进程额外占用。

## 粘贴修复

旧实现从键盘 Dock 调用 `sendAction:@selector(paste:) to:nil`，部分系统版本和 App 中无法通过响应链找到真正的输入对象。现在参考 [DockX](https://github.com/udevsharold/dockx) 的实现：

1. 从 `UIKeyboardImpl` 获取 `privateInputDelegate`，不可用时再取 `inputDelegate`。
2. 直接对输入代理调用 `paste:`。
3. 输入代理不支持 `paste:` 时，读取系统剪贴板并通过 `UIKeyboardImpl insertText:` 插入纯文本。

全选后复制、全选后删除会等待选区更新后再执行第二个动作。WebKit 输入框通过其标准 `selectAll:`/`copy:` 动作处理全选复制，左右移动和移动到首尾使用 WebKit 编辑命令；粘贴通过当前键盘输入通道插入。网页全选清空会额外等待 0.12 秒，再直接调用 `WKContentView` 的 `deleteBackward` 提交网页选区删除；键盘层删除仅作为旧系统后备。删除完成后关闭 iOS 15 的 `UIMenuController`，避免全选编辑菜单残留。

## 云端构建

仓库的 GitHub Actions 只构建 **Dopamine RootHide** 使用的 roothide `.deb`：

- 焊死版直接安装到 ElleKit 的实际注入目录 `/usr/lib/TweakInject`，不经过 `/Library/MobileSubstrate/DynamicLibraries` 兼容符号链接，也不使用普通 rootless 的固定 `/var/jb` 前缀。
- 软件包没有 `preinst`、`postinst`、`prerm` 或 `postrm`；安装、升级和卸载只由 dpkg 管理本包自己的 `KBEditToolbar.dylib` 与 `KBEditToolbar.plist`。
- 本包不包含、创建、删除或修复 ElleKit、PreferenceLoader 及其他软件包的文件。

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
