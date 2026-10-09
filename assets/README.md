# 用户资产

演示启动动画在 `../media/startup.mp4`，媒体说明在 `../media/MEDIA_NOTICE.md`。公开仓库不附带独立官方图标。

可通过 `scripts/Import-Animation.ps1` 换成自己的 MP4。自定义图标可在构建时通过 `-IconPath` 传入。除随附的这一个演示视频外，其他视频与个人图标被 `.gitignore` 排除。

## Mac 应用图标

`mac-app-icon.png` 是通过内置 imagegen 生成的原创紫色白龙图标，作为本项目应用图标随 MIT 代码一同分发，不使用 OpenAI 官方标志。`scripts/build-mac-icon.sh` 用系统工具生成完整的标准和 Retina 尺寸 ICNS。

生成描述：深紫色圆角底板、白色幼龙头部、淡紫色角和双翼、透明外边距，无文字或第三方标志。
