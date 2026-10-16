# Xvico · 用声音，开启 Vibe Coding

4:3，1440×1080，30fps，45 秒。中文主文案，保留 Xvico / Xpaco / Codex 英文名称。以 Siri Remote 语音输入为主线，使用中性黑背景、蓝色交互与绿色语音波形、持续在场的高清 3D 遥控器与连续镜头运动。原创电子 BGM + 交互音效，无配音。

## 成品

- `dist/Xvico-promo-4x3-zh.mp4`：H.264 + AAC 立体声。
- `dist/Xvico-cover.png`：1440×1080 封面。
- `dist/Xvico-storyboard.png`：从最终成片解码抽取的八个关键镜头。
- `dist/Xvico-promo-zh.srt`：独立字幕；画面已有文案，无需重复叠加。
- `preview.html`：本地播放器及下载入口。
- `dist/verification.json`：实际成片的轨道、抽帧及完整解码检查。
- `dist/delivery.json`：交付范围和验证记录。
- `dist/motion-verification.json`：逐帧位置、缩放、转角连续性检查。

`dist/` 与 `.build/` 被 Git 忽略；生成源码、分镜及播放器可纳入版本管理。宣传视频不参与主应用 Swift Package 编译。

## 分镜与动效

| 时间 | 能力 | 表达 |
| --- | --- | --- |
| 00–03 | 品牌开场 | Xvico · 用声音，开启创造 |
| 03–10 | 进入真实应用 | 实际功能映射主界面，点击模型 Siri 侧键，实际映射框展开；模型从窗口中连续放大移出 |
| 10–14 | 自定义映射 | 最新 Siri 与音量键设置卡连续切换；Fn、修饰键和分段模式均来自应用截图 |
| 14–19 | 应用预设 | 展示实际预设场景页，再推进 Codex 多任务预设卡片 |
| 19–24 | 外圈与指针 | 触控盘外圈轨迹驱动滚动，再展示指针移动与点击 |
| 24–34 | 语音 Coding | 展示实际语音页和 Siri Remote 麦克风选项；按住侧键产生波形，再转入模拟 Codex 输入框 |
| 34–40 | 持续迭代 | 生成页面，再以第二句语音修改主题并加入任务列表 |
| 40–45 | 品牌收尾 | Xvico 图标与简短行动文案 |


遥控器使用独立于章节的单一渲染层，在 0–40 秒品牌和功能演示中持续在场。位置、统一缩放、俯仰、侧转和侧倾由 `storyboard.json` 的 `remoteMotion` 轨迹控制，使用五次缓动平滑衔接；周围内容先收起再展开。映射聚焦沿用当前应用的姿态；不显示按键热区圈。外圈运动轨迹跟随当前 3D 投影。品牌收尾时才淡出遥控器。

以产品动作为主线，每个镜头只保留一句标题。应用画面和设置控件来自真实截图；光标操作、模型移位、波形和编程过程为品宣动画。单击、双击、按住的映射仍由用户自定义；视频不写入实际配置。

## 构建

需要 macOS、兼容的 Swift/Xcode 工具链、Python 3 + NumPy + Pillow。使用 AppKit/CoreGraphics、SceneKit、AVFoundation；无 Node、Remotion、FFmpeg 或外部生成 API 依赖。

```sh
# Python 依赖未安装时，建议在独立虚拟环境中安装：
# python3 -m pip install -r promo/requirements.txt
./promo/build.sh
```

默认离线构建。已有项目素材：

- `Sources/XvicoApp/Resources/SiriRemote.usdz`
- `Assets/Xvico-v2.png`
- `promo/assets/app-mapping-main.png`、`app-siri-mapping.png`、`app-volume-mapping.png`、`app-scenes.png`、`app-voice.png`、`app-device.png`：本机实际应用窗口截图，采集说明见 `promo/assets/README.md`。

可编辑入口：

- `storyboard.json`：文案、段落时间、抽帧时间、转场与点击音效落点。
- `prepare-app-assets.py`：保留原图，制作单模型合成用底板与真实控件特写。
- `render.swift`：真实应用合成、模型注册与连续镜头、光标点击、波形形变、模拟 Codex、逐字输入、代码与页面动画。
- `soundtrack.py`：110 BPM 原创电子配乐；正弦合成器、琶音、低频鼓、噪声打击及转场声。固定随机种子，无第三方采样；独立输出 BGM、SFX、混音 WAV 到 `.build/`。
- `finish.swift`：音视频合成、按分镜抽取最终编码画面。
- `validate.swift`：完整解码、帧数、时间戳、音频峰值检查及分镜总览。
- `write-captions.py`：SRT 字幕。

快速检查关键画面：

```sh
mkdir -p promo/.build
python3 promo/prepare-app-assets.py
swiftc -O promo/render.swift -o promo/.build/render
promo/.build/render "$PWD" --preview
```

排版针对 1440×1080 / 4:3 设计。更改画幅或段落结构后，必须同步调整镜头和排版，重新检查画面。

## 描述与素材边界

真实素材是本机 Xvico 窗口截图、实际设置控件、项目图标和 USDZ 模型。截图中的原有静态模型及阴影被相邻背景插值替换；派生底板同时移除系统共享指示和停放的采集指针，用同一个 USDZ 动画层对齐后连续放大移出；原图完整保留。导航、控件、文字和配置状态来自 2026-10-16 的实际截图。旧版额外标题栏已移除；视频外围展示卡改为中性玻璃层次。光标点击、波形、识别文字、Codex 对话、代码和生成的页面是编排演示，功能段底部标注“交互与编程场景演示”。不表示真实识别准确率或生成速度；没有调用 Codex API、启动遥控器采集、修改用户配置或应用功能。

配乐与音效为本片原创程序合成，不引用商业歌曲。图标、模型和界面沿用项目既有来源及权利边界；见根目录 LICENSE、THIRD_PARTY_NOTICES.md。本片不会扩大原素材的分发授权。

未写死尚未确认的 GitHub 地址，未声称生产签名、公证或全型号验证已完成。
