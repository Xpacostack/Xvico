# Xvico 科技竖屏更新短片

本项目是独立的 9:16、1080×1920、30fps、32 秒宣传视频。保留原 `promo/dist` 横屏成片。以深蓝光场、冷色网格、信号粒子与更快的电子节奏呈现当前应用的更新。全片只有一个持续绘制的 3D 遥控器层，位置、大小、俯仰、偏航与翻滚由一组连续曲线控制，包括片尾。

## 叙事与素材

- 0–3s：Xvico 与遥控器开场。
- 3–7s：真实新版玻璃侧栏与连接状态。
- 7–12s：Siri / 音量映射面板与模型聚焦姿态。
- 12–16s：真实 Codex 多任务预设。
- 16–21s：Siri Remote → 输入法的语音场景。
- 21–29s：Codex 风格输入框、构建与迭代的脚本化示例。
- 29–32s：Xvico 品牌收束，遥控器继续运动。

真实 UI 取自 `../assets/` 的 2026-10-16 本地窗口截图；使用 `../prepare-app-assets.py` 已说明的派生图层，再按竖屏进行裁切。映射面板与应用选项未重新绘制或编造。`prepare.py` 只额外裁出侧栏。遥控器来自应用资源 `Sources/XvicoApp/Resources/SiriRemote.usdz`，以 1200×1680 离屏分辨率和 4× MSAA 渲染，没有覆盖按钮热区圈。

语音转写与 Coding 内容是经过编排的功能场景演示，未调用真实识别、麦克风或编程服务；不是速度基准，也不表示 OpenAI 背书。片内保留场景演示说明。配乐与音效由本地正弦合成和种子噪声原创生成，没有使用第三方歌曲或录音。

## 本地重建

需要 macOS、Swift / Xcode SDK、Python 3，以及 NumPy 与 Pillow。无需网络与第三方视频服务。

```sh
./promo/douyin/build.sh
```

如果系统 Python 没有依赖，可以指定已安装依赖的解释器：

```sh
XVICO_VIDEO_PYTHON=/path/to/python3 ./promo/douyin/build.sh
```

- `storyboard.json`：时长、镜头文案、验证时刻和遥控器运动关键帧。关键帧的 `x/y` 表示可见模型中心，`width` 在本竖屏项目中表示可见模型高度；程序将其换算为完整图层矩形再插值。
- `render.swift`：可编辑的竖屏构图与动效源码；原生 SceneKit / AppKit / AVFoundation。
- `soundtrack.py`：124 BPM 配乐、转场音与点击音。
- `finish.swift`：音画合成和最终编码帧提取。
- `validate.swift`：全片视频解码、时间戳、音频时长/峰值检查、编码后分镜图。
- `deliver.py`：字幕、发布文案、素材与成片哈希。

`dist/Xvico-update-douyin-9x16.mp4` 是最终成片；`preview.html` 为本地播放器。字幕已经以镜头标题形式出现在画面中，SRT 供后续编辑使用，不必再重复烧录。

主标题和关键内容为竖屏重新排版，右侧和下方留出余量。这是本片设计选择，未宣称适用于所有抖音版本或用户界面的官方安全区模板。本项目不执行发布、Git 提交或上传，也不修改应用配置。
