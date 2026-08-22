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

- `Tweak.x`：工具条、输入代理解析、粘贴与长按动作。
- `KBEditToolbar.plist`：注入过滤器（`com.apple.UIKit`）。
- `Makefile` / `control`：roothide、arm64 + arm64e、软件包元数据。
- `.github/workflows/build.yml`：macOS 云端构建并上传 roothide `.deb`。
