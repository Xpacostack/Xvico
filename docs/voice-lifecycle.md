# 语音启停与连接恢复 / Voice lifecycle and recovery

本文描述 beta.7 的语音与连接行为；beta.5 仍有单次一小时上限，升级主程序后还需更新后台组件，以下取消时限的行为才会生效。
This document describes beta.7. Beta.5 retains its one-hour limit; after upgrading the app, install the updated backend payload for sessions without a fixed deadline.

## 正常使用 / Normal use

- 后台安装授权与采集会话分开保存。重新打开应用不需要重复安装同一份后台，但不会自动开始采集。
- 在语音设置点击“启动系统语音后端”，通道就绪后再使用已配置的遥控器映射。
- 输入法模式按实际配置的触发键切换遥控器收音。单击、双击和长按仍由功能映射决定；没有把 Siri 固定成某一种操作。
- 点击“停止聆听”或退出应用，会关闭遥控器麦克风并停止当前采集。若硬件停止命令失败，界面会保留错误，清理或下一次触发可重试，不把失败当成已关闭。
- 手动启动的后端不设固定时长上限；主动停止、退出、睡眠或连接中断时结束。没有改变诊断设置范围或增加自动采集；后台待命不代表遥控器麦克风持续收音。

Backend installation approval and capture sessions are separate. Relaunching the app keeps the saved approval for the same payload but does not start capture. Start the system voice backend in Voice Settings before using remote voice mappings. In input method mode, the configured trigger toggles microphone capture; single press, double press and hold remain user mappings. Stop Listening or quitting closes the microphone and capture session. A failed hardware stop remains visible and retryable. Manually started sessions have no fixed time limit and end on stop, quit, sleep or connection loss. Diagnostic scope is unchanged, and backend availability does not keep the remote microphone open. Updated backend binaries require a one-time administrator-approved update; existing input/privacy permissions do not need resetting.

## 中断与恢复 / Interruption and recovery

| 情况 / Event | 行为 / Behavior |
| --- | --- |
| 麦克风开启或停止命令失败 / Microphone command fails | 下次触发重试同一方向，避免启停状态错位。The next trigger retries the failed direction. |
| 语音后台结束或读取器退出 / Backend or reader ends | 清理当前通道并显示错误，不继续显示就绪。The channel stops and reports an error. |
| 遥控器输入连接丢失 / Remote input is lost | 取消识别，关闭语音通道，释放应用持有的按键和鼠标状态。Recognition and voice stop; owned key and mouse outputs are released. |
| 系统睡眠 / System sleeps | 停止当前语音、释放输入、关闭遥控器输入监听。The current voice session and input monitoring stop. |
| 系统唤醒 / System wakes | 若控制原本启用，恢复按键和触控接口监听；不自动恢复采集。HID monitoring resumes only if control was enabled; capture does not restart automatically. |
| 在睡眠期间停止控制 / Control disabled during sleep | 唤醒后保持停止。Control stays stopped after wake. |

连接恢复后，先确认侧边栏显示已连接；需要语音时，重新点击“启动系统语音后端”。同一签名与后台文件未改变时沿用已保存授权。应用无法替代 macOS 的蓝牙配对或系统隐私批准。

After reconnecting, confirm the sidebar shows the remote connected, then explicitly restart the voice backend if needed. Saved approval is reused when the signing identity and backend payload still match. The app cannot replace macOS pairing or privacy approval.

触控 HID 身份出现后，多点触控通道可能尚未准备好。beta.5会在约12秒内有限重试绑定，成功后停止重试，不因闲置而重启。若仍未恢复，可在设备设置点击“重新识别遥控器触控板”并反馈；当前测试设备已确认无需手动重新识别即可恢复点击、滑动和滚动；其他设备仍需验证。

The multitouch channel may become available after the HID identity is discovered. Beta.5 retries binding within a bounded window of about 12 seconds, then stops retrying once connected. It does not restart a healthy idle device. If recovery still fails, use Reidentify Remote Touchpad in Device Settings and report the result. The tested remote recovered clicks, swipes and scrolling without manual reidentification; other setups still need acceptance.

## 硬件验收 / Hardware acceptance

自动测试使用隔离偏好、模拟输入接口和已知合成 Opus 音频，不会打开真实麦克风或启动蓝牙诊断。以下验收仍需真实 Mac、Siri Remote 和已配置的输入法。

Automated tests use isolated preferences, simulated interfaces and synthetic Opus audio. They do not open a microphone or start Bluetooth diagnostics. Real hardware acceptance still requires the following steps:

1. 启动后端，在同一普通输入框连续输入三段，每段按原映射开始和停止，确认每次都能落字。Start the backend and dictate three separate utterances using the existing mappings.
2. 停止聆听，再启动一次并输入，确认同一后台无需重新安装或管理员批准。Stop, restart and dictate again; unchanged backend approval should be reused.
3. 保存其他工作，将 Mac 睡眠并唤醒，确认遥控器点击、触控和原场景映射恢复，语音没有自行采集；手动启动后再输入一段。Save other work, sleep and wake the Mac, verify HID recovery and no automatic recording, then explicitly restart voice.
4. 只断开该遥控器，再重新连接，确认没有残留拖动或按住键；恢复连接后点击和滚动正常，语音可手动恢复。Disconnect only the remote and reconnect it; verify no stuck output and successful manual voice recovery.

请分别记录通过或失败及错误文字。一次普通输入成功不代表睡眠唤醒、意外断连或所有输入法均已验收。
Record each result separately. One successful dictation does not establish sleep/wake, unexpected-disconnect or all-input-method compatibility.

## 已完成的验收 / Completed acceptance

维护者当前设备已通过连续三轮语音、停止后重启语音及断连重连后点击/滑动/外圈滚动自动恢复。系统睡眠被测试电脑全局设置禁用，真实睡眠唤醒仍未验收；已有软件测试不替代该项硬件结论。

The maintainer confirmed three consecutive utterances, voice stop/restart and automatic click/swipe/ring recovery after reconnecting. Real sleep/wake acceptance remains pending because the test Mac had system sleep disabled; software tests do not replace that hardware check.
