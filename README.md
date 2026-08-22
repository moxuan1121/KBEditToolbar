# KBEditToolbar — 键盘工具条（粘贴 / 向左 / 向右 / 收起）

在系统键盘底部加一排按钮：**粘贴、光标向左、光标向右、收起键盘**，点按带轻触感。
本地无需 WSL/Theos —— 用 GitHub Actions 的 macOS runner 打包出 rootless `.deb`。

## 功能与按钮
| 按钮 | SF Symbol | 实现 |
|---|---|---|
| 粘贴 | `doc.on.clipboard` | 响应链 `sendAction:@selector(paste:) to:nil` |
| 向左 | `chevron.left` | 找当前 `UITextInput`，`selectedTextRange` 左移一位 |
| 向右 | `chevron.right` | 同上，右移一位 |
| 收起 | `keyboard.chevron.compact.down` | `[[UIKeyboardImpl activeInstance] dismissKeyboard]` |

## 不用 WSL 怎么构建（三步）
1. 在 GitHub 新建一个仓库，把本文件夹所有内容（含 `.github/`）push 上去，默认分支 `main`。
   ```bash
   git init && git add -A && git commit -m "init KBEditToolbar"
   git branch -M main
   git remote add origin https://github.com/<你的账号>/<仓库名>.git
   git push -u origin main
   ```
2. push 后进仓库 **Actions** 标签，工作流 `Build rootless deb` 会自动跑（也可点 `Run workflow` 手动触发）。
3. 跑完点进那次运行，在 **Artifacts** 下载 `KBEditToolbar-rootless-deb`，解压得到 `.deb`。
   - 打 tag（如 `v0.1.0`）push 会额外把 `.deb` 挂到 Release。

## 安装 / 验证
- 用 Sileo/Zebra 安装 `.deb`（rootless 越狱如 Dopamine），或 `dpkg -i` 后 `killall -9 SpringBoard`。
- 打开备忘录/任意输入框弹出键盘 → 底部应出现 4 个按钮 → 逐个验证：粘贴插入剪贴板内容、左右移动光标、收起关闭键盘。

## 结构
- `Tweak.x`：`%hook UIKeyboardDockView -layoutSubviews` 注入按钮栏；`%new` 方法实现 4 个动作 + 光标移动辅助函数。
- `KBEditToolbar.plist`：注入过滤器（`com.apple.UIKit`）。
- `Makefile` / `control`：rootless、arm64+arm64e。
- `.github/workflows/build.yml`：macOS runner 打包。

## 关键坑（已在代码里规避）
- **`layoutSubviews` 反复调用** → 先 `viewWithTag:` 查重，避免按钮越堆越多。
- **光标移动没有系统 selector** → 必须先拿到 firstResponder 里的 `UITextInput`，改 `selectedTextRange`；越界时 `positionFromPosition:offset:` 返回 nil，代码里已 clamp。
- **rootless** → 不硬编码 `/var/jb`；`THEOS_PACKAGE_SCHEME=rootless`。

## 想扩展
加「全选/撤销/重做」= 再加按钮走 `sendAction:@selector(selectAll:/undo:/redo:)`；
加设置开关 = 配 PreferenceBundle。
