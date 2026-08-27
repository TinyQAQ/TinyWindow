# TinyWindow

> Drop windows onto layout pads — an open-source revival of [Window Tidy](https://www.lightpillar.com/window-tidy.html) for macOS 26+.

[English](#english) · [中文](#中文)

![CI](https://github.com/TinyQAQ/TinyWindow/actions/workflows/ci.yml/badge.svg)

---

## English

### Why

Window Tidy (Light Pillar, retired 2017) had one idea nothing else replicated well: while you drag a window, **explicit layout pads** pop up — drop the window on a pad and it snaps to that layout's position and size. Because the drop targets are pads, not screen edges, it behaves sanely on multi-monitor setups: dragging left moves to the left display instead of accidentally tiling.

The original is Intel-only and dies with Rosetta 2 (macOS 27 is its last stop). TinyWindow is a native Apple Silicon replacement with 1:1 interaction, and it imports your existing Window Tidy layouts.

### Features

- Drag any app's window → a strip of layout pads fades in on the screen under your cursor, and **follows you across displays**
- Hover a pad → it highlights and the target region is previewed on the destination screen; release → the window snaps there
- Layouts are per-layout grids (e.g. 6×6) with a drag-selected cell range; fixed-size layouts supported for import fidelity
- Option-key modes: always show / hold ⌥ to show / hold ⌥ to hide
- Pad strip position (bottom/top/left/right), pad titles, minimum drag distance, per-app blacklist
- Menu bar: apply any layout to the frontmost window, recover a window to the cursor's screen, launch at login
- **One-click import** of Window Tidy's `Layouts.data` (layouts + Option/titles preferences)
- ~0% idle CPU (the event tap receives nothing until you actually drag)

### Install

1. Download `TinyWindow-x.y.z.zip` from [Releases](https://github.com/TinyQAQ/TinyWindow/releases), unzip, move to `/Applications`.
2. Gatekeeper will block the unsigned build: System Settings → Privacy & Security → scroll to "TinyWindow was blocked" → **Open Anyway** (or `xattr -d com.apple.quarantine /Applications/TinyWindow.app`).
3. Grant **Accessibility** permission when prompted (required to move other apps' windows). Note: each release update resets this grant — a known limitation of unsigned builds.
4. Recommended: System Settings → Desktop & Dock → turn **off** "Drag windows to screen edges to tile", so the OS tiling preview doesn't fight the pads.

### Build from source (no Xcode needed)

Command Line Tools with the macOS 26 SDK are enough:

```bash
git clone https://github.com/TinyQAQ/TinyWindow.git && cd TinyWindow
make run     # swift build + assemble dist/TinyWindow.app + launch
make test    # run the check suite
```

**Stable dev signing (do this once):** ad-hoc signatures change every build, which silently kills the Accessibility grant on each rebuild. Run `scripts/dev-cert.sh` — it creates a self-signed code-signing certificate named `TinyWindow Dev`, imports it, and verifies with a real signing test (it prints exact manual-trust steps if macOS refuses scripted trust). GUI alternative: Keychain Access (hidden on macOS 26 — it lives at `/System/Library/CoreServices/Applications/Keychain Access.app`, not the new Passwords app) → **menu bar** → Certificate Assistant → Create a Certificate… → name `TinyWindow Dev`, Self-Signed Root, **Code Signing**. `make app` picks the identity up automatically and the grant then survives rebuilds.

### Uninstall

Quit TinyWindow, delete the app, then:

```bash
rm -rf ~/Library/Application\ Support/TinyWindow
defaults delete com.tinyqaq.TinyWindow
tccutil reset Accessibility com.tinyqaq.TinyWindow
```

---

## 中文

### 为什么做这个

Window Tidy（Light Pillar，2017 年停止开发）有一个至今没有被好好复刻的交互：拖动窗口时浮出**显式的布局 pad**，把窗口拖到 pad 上松手即应用该布局的位置和尺寸。因为投放目标是 pad 而不是屏幕边缘，多屏下体验极佳——往左拖就是去左边屏幕，不会被误触发贴边平铺。

原版是纯 Intel 应用，Rosetta 2 退役后（macOS 27 之后）就彻底跑不了了。TinyWindow 是 Apple Silicon 原生替代品，操作方式 1:1，并能一键导入你现有的 Window Tidy 布局。

### 功能

- 拖动任意 App 的窗口 → pad 条淡入在光标所在屏幕，并**跟随光标跨屏移动**
- 悬停 pad → 高亮 + 目标屏幕上预览落点区域；松手 → 窗口精确就位
- 布局 = 独立网格（如 6×6）+ 拖选格子范围；同时支持固定尺寸布局（导入保真）
- Option 键三种模式：始终显示 / 按住 ⌥ 才显示 / 按住 ⌥ 隐藏
- pad 位置（上/下/左/右）、标题开关、触发距离、按 App 黑名单
- 菜单栏：直接把布局应用到前台窗口、把窗口找回到鼠标所在屏、登录启动
- **一键导入** Window Tidy 的 `Layouts.data`（布局 + Option/标题偏好一并迁移）
- 空闲 CPU ≈ 0%（不拖动时事件 tap 收不到任何事件）

### 安装

1. 从 [Releases](https://github.com/TinyQAQ/TinyWindow/releases) 下载 zip，解压后移到「应用程序」。
2. Gatekeeper 会拦截未签名构建：系统设置 → 隐私与安全性 → 找到"已阻止 TinyWindow" → **仍要打开**（或执行 `xattr -d com.apple.quarantine /Applications/TinyWindow.app`）。
3. 按提示授予**辅助功能**权限（移动其他 App 窗口所必需）。注意：每次更新版本都需重新授权，这是未签名构建的已知限制。
4. 建议：系统设置 → 桌面与程序坞 → 关闭"将窗口拖到屏幕边缘时平铺"，避免系统平铺预览和 pad 打架。

### 源码构建（无需 Xcode）

只需 Command Line Tools（含 macOS 26 SDK）：

```bash
git clone https://github.com/TinyQAQ/TinyWindow.git && cd TinyWindow
make run     # 构建 + 打包 dist/TinyWindow.app + 启动
make test    # 跑检查套件
```

**稳定开发签名（一次性）**：ad-hoc 签名每次构建都变，辅助功能授权会随之失效。运行 `scripts/dev-cert.sh` 即可——它会创建名为 `TinyWindow Dev` 的自签代码签名证书、导入钥匙串并实际验签（若系统拒绝脚本设置信任，会打印精确的手动步骤）。图形界面备选：钥匙串访问在 macOS 26 里被隐藏（位于 `/System/Library/CoreServices/Applications/Keychain Access.app`，不是新的「密码」App）→ 打开后在**顶部菜单栏** → 证书助理 → 创建证书…（名称 `TinyWindow Dev`、自签名根证书、**代码签名**）。之后 `make app` 自动使用该证书，授权在重编译后保持有效。

### 卸载

退出 TinyWindow、删除 App，然后：

```bash
rm -rf ~/Library/Application\ Support/TinyWindow
defaults delete com.tinyqaq.TinyWindow
tccutil reset Accessibility com.tinyqaq.TinyWindow
```

### License

MIT © 2026 TinyQAQ
