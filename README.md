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

- 粘贴按钮：`pasteX`、`pasteY`
- 向左按钮：`leftX`、`leftY`
- 向右按钮：`rightX`、`rightY`
- 收起键盘按钮：`dismissX`、`dismissY`

X 负值向左、正值向右；Y 负值向上、正值向下。每个值只作用于对应按钮，不会一起移动。默认状态下四个按钮会均匀铺开在底栏宽度的 1/8、3/8、5/8、7/8 位置。设置页底部提供“恢复默认布局”。

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
