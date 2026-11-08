# 安装 ishot 0.1.0

要求 macOS 14 或更新版本。Universal 安装包同时包含 Apple 芯片和 Intel 架构；仅在 Apple 芯片 Mac 上做过运行验证。

下载地址：https://github.com/sunholdshen/ishot/releases/tag/v0.1.0

1. 打开 DMG，把 ishot.app 拖到 Applications（应用程序）。
2. 从 Applications 打开 ishot。应用常驻屏幕顶部的取景框菜单栏图标。
3. 点击“开始截图”，允许系统请求的屏幕录制权限。若授权后仍无法截图，请退出并重新打开 ishot。
4. 选择区域后按 P 钉住；Enter 进入批注；C 复制；S 保存；Esc 取消。

本预览版使用 ad-hoc 本地签名，没有 Apple Developer ID 签名和公证。通过浏览器下载后，macOS 可能阻止首次启动。确认文件来自你信任的仓库且校验值匹配后，可按 Apple 官方说明，在“系统设置 → 隐私与安全性”中对该应用选择“仍要打开”。不要关闭系统全局安全检查。

Apple 官方说明：https://support.apple.com/en-gb/102445

也可以从源码自行构建：

    xcode-select --install
    ./scripts/build.sh universal

完成后将 dist/ishot.app 拖入 Applications。

默认快捷键：
- 区域截图：⌘⇧⌥3
- 当前显示器全屏截图：⌘⇧⌥4
- 显示 / 隐藏全部贴图：⌘⇧⌥P

如果组合已被其他软件占用，请进入 ishot → 设置 → 快捷键重新指定。

贴图操作：
- 按住图片拖动位置。
- 滚轮或双指缩放调整大小。
- Option + 滚轮调整透明度。
- 双击恢复原始尺寸（仍受屏幕安全尺寸限制）。
- 右键进行批注、复制、保存、锁定和关闭。
- 退出前请保存需要保留的图片；当前版本不会自动恢复贴图。

屏幕权限可在 ishot → 设置 → 通用中重新打开。无需辅助功能权限。

校验安装包：下载同名 .sha256 文件，与 DMG 放在同一目录，然后运行：

    shasum -a 256 -c ishot-0.1.0-universal.dmg.sha256

应显示 OK。校验和不等于 Apple 公证。
