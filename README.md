# Dragon Codex Boot — Mac

给 macOS 版 Codex 播放随附龙娘启动动画，再淡出到真实客户端。Fork 自 [yushua0808-cpu/dragon-codex-boot](https://github.com/yushua0808-cpu/dragon-codex-boot)，原 Windows 实现完整保留，见 [Windows 使用说明](docs/windows-readme.md)。独立社区项目，与 OpenAI 无隶属关系。

## Mac 上怎么用

要求 macOS 13+、已安装 Codex。通用应用包含 Apple Silicon / Intel 两种架构；运行时不需要 Python、Node、API key，也不需要屏幕录制或辅助功能权限。

### 从源码构建

先安装 Apple 的 Xcode Command Line Tools（已安装 Xcode 可跳过）：

```bash
xcode-select --install
```

```bash
git clone https://github.com/swtxbling/dragon-codex-boot-mac.git
cd dragon-codex-boot-mac
bash scripts/test-mac.sh
open "build/Dragon Codex Boot.app"
```

把 `build/Dragon Codex Boot.app` 复制到 `~/Applications` 或 `/Applications`，双击启动，也可以拖到 Dock。应用内部包含视频和配置，移动应用后依然可以使用。打开这个入口才播放动画；直接打开官方 Codex 仍使用官方启动方式。

构建脚本只写仓库的 `build/`，不会替换官方应用、已有 Dock 图标或系统入口。卸载时退出并删除这个独立应用，再移除对应 Dock 图标即可。

### 下载构建包

[GitHub Actions](https://github.com/swtxbling/dragon-codex-boot-mac/actions/workflows/macos.yml) 的成功运行会附带 `DragonCodexBoot-mac-universal`，包含应用 ZIP 和 SHA-256 文件。下载 Actions 附件需要登录 GitHub。

本项目目前使用本地 ad-hoc 签名，没有 Apple Developer ID 签名或公证。联网下载的包可能被 Gatekeeper 拦截；核实来源后按 macOS「系统设置 → 隐私与安全性 → 仍要打开」流程操作，或自行从源码构建。不要关闭系统安全保护。

## 播放与交接

- 在当前屏幕中央播放动画，按可用屏幕区域缩小，保留视频比例。
- 同时通过 macOS 原生应用启动接口打开 Codex；已运行时复用现有应用。
- 默认在 11.3 秒等待启动完成，然后继续；12.7 秒开始淡出并激活 Codex。
- Esc 立即隐藏并静音动画，启动完成后激活 Codex。最迟 60 秒退出等待并显示错误。
- 缺失或无法解码视频时继续交接到 Codex；找不到应用、启动失败、无响应超时会显示错误。

Mac 版使用淡出交接，**尚未实现 Windows DWM 那种将实时客户端画面嵌入动画屏幕的过渡**，不移动或缩放客户端窗口。启动完成来自操作系统信号，不保证聊天视图或全部后台任务加载完成。

## 配置与自定义视频

右键应用 → 显示包内容，编辑 `Contents/Resources/launcher.json`。构建时默认来自 [Mac 配置](config/launcher.macos.json)，重复构建保留已有配置。

| 字段 | 含义 |
| --- | --- |
| `video` | 相对 `Contents/Resources` 的视频路径，或绝对路径；默认 `media/startup.mp4` |
| `appBundleIdentifier` | 默认 `com.openai.codex`，按标识查找，不依赖 `.app` 名称 |
| `appPath` | 可选，指定客户端的完整 `.app` 路径，优先于应用标识；支持 `~/` |
| `holdAt` | 客户端尚未启动完成时暂停的秒数 |
| `transitionStart` | 淡出交接的秒数，必须 ≥ `holdAt` |
| `fadeDuration` | 淡出时长，0–10 秒之间，不含 0 |
| `maxWaitSeconds` | 从启动器开始的总等待上限，1–300 秒 |
| `volume` | 音量，0–1 |
| `playerWidth` / `playerHeight` | 窗口尺寸，单位为 Mac 逻辑点，默认 1280×720 |

可用自己的 H.264/AAC MP4 替换应用内部的 `media/startup.mp4`。短视频会在播放结束后交接；长视频在设定的交接时刻提前结束。使用其他视频时要调整时间字段。修改应用内容后，原签名会失效，本机可重新签名：

```bash
codesign --force --sign - "/path/to/Dragon Codex Boot.app"
```

## 验证与打包

```bash
bash scripts/test-mac.sh
bash scripts/package-mac.sh
```

测试覆盖配置校验、延迟启动等待、恢复播放、短视频、超时和带空格路径，并构建和验证通用应用签名。`dist/` 输出带默认媒体的通用 ZIP；打包使用公开默认配置，不带本机的 `appPath` 或自定义视频。

```bash
# 只检查配置、文件和 Codex 查找，不启动客户端
"build/Dragon Codex Boot.app/Contents/MacOS/DragonCodexBoot" --check
# 播放预览，不启动客户端
"build/Dragon Codex Boot.app/Contents/MacOS/DragonCodexBoot" --preview
```

桌面验收步骤和已知边界见 [Mac 验收说明](docs/macos-testing.md)。Windows 测试需要 Windows 环境，本机 Mac 测试不代表 Windows 回归测试。

## 目录与许可

- `src/macos/`：AppKit + AVFoundation 原生启动器。
- `scripts/*-mac.sh`：测试、通用构建与打包。
- `.github/workflows/macos.yml`：Mac 自动构建。
- `src/DragonCodexBoot.cs` 等：保留的 Windows 实现。

代码沿用 [MIT 许可证](LICENSE)。随附动画保留上游 [媒体说明](media/MEDIA_NOTICE.md)，软件 MIT 许可不授予媒体素材的额外用途。第三方名称说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。无网络遥测，不保存聊天内容或屏幕画面。
