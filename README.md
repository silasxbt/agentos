# Binance Voice Agent (Hackathon)

SwiftUI 原生 iOS App:**Action Button → 语音听写 → Agent 结构化解析 → 灵动岛/锁屏卡片确认 → 下单 → 原生通知**。全程不需要打开 App。

| 灵动岛卡片(待确认) | 灵动岛卡片(已成交 + 通知) | 「修改」跳回 App | App 内确认页 |
|---|---|---|---|
| ![](docs/island_pending.png) | ![](docs/island_filled.png) | ![](docs/island_edit.png) | ![](docs/confirm.png) |

## 两条流程

### A. 全局触发(任意界面,不跳 App)
1. 在任何 App(Coinglass / TradingView…)按下 **Action Button** → 系统「听写文本」开始录音。
2. 听写结果传给 `VoiceTradeIntent`(`openAppWhenRun = false`),后台解析并弹出 **Live Activity**(灵动岛 + 锁屏卡片)。
3. 卡片显示 **币种 / 方向 / 杠杆 / 全仓逐仓 / 保证金 / 止盈止损 / 置信度**,底部三个按钮:
   - **取消**:`CancelFromIslandIntent`,原地结束。
   - **修改**:深链 `binancevoice://edit`,跳进 App,整份配置带入 `ConfirmView` 快捷编辑。
   - **下单**:`SubmitFromIslandIntent`(`LiveActivityIntent`,后台执行,不弹窗)→ 卡片变为「已成交 @ 价格 #订单号」→ 原生通知。
4. 开启 Face ID 开关时,「下单」改为深链 `binancevoice://submit`,进 App 先过 Face ID 再提交。

### B. App 内流程
Action Button 绑定「语音下单」(`StartVoiceTradeIntent`)→ 打开 App 听写 → `ConfirmView` 确认/编辑 → (可选 Face ID)→ 成交页 + 通知。

## 真机设置(全局触发)

**最简方式**:设置 → 操作按钮 → 快捷指令 → 选择「Binance Voice → 语音下单」。按下即打开 App 开始听写。

**不跳 App 的灵动岛方式**:直接绑定「灵动岛下单」时,按键后系统会弹出输入请求(可点麦克风说话),说完即出灵动岛卡片。
若想省掉这个弹框,用系统的「听写文本」动作串联(iOS 不允许后台 App 自行打开麦克风):
1. 打开「快捷指令」→ 新建。
2. 添加动作 **听写文本**(语言:中文,停止聆听:暂停后)。
3. 添加动作 **Binance Voice → 语音下单(灵动岛)**,把「听写文本」的输出拖到「交易指令」参数。
4. 命名(如「语音下单」)→ 设置 → 操作按钮 → 快捷指令 → 选择它。

按下 Action Button 后会短暂出现系统听写浮层,不会跳 App;说完即出现灵动岛卡片。

## Face ID 开关
首页右上角齿轮 → 「Face ID 二次确认」。默认关闭:手机处于解锁状态即视为已授权,「下单」在卡片上直接后台成交。开启后每次下单都需 Face ID。

## 解析器
`CommandParser` 把自然语言解析为 `TradeOrder`:币种(支持大饼/以太坊等别名)、方向、杠杆、全仓/逐仓、保证金(中文数字、万/千、U/USDT/美元)、止盈止损(价格或百分比),并给出置信度与说明。

## 语音转写:Qwen ASR(不使用苹果语音识别)
App 内听写不走 `SFSpeechRecognizer`,而是:`AVAudioEngine` 录音 → 16kHz 单声道 WAV(说话后静音 1.6s 自动结束,最长 30s)→ 阿里云百炼 DashScope **`qwen-audio-3.0-asr-flash-filetrans`** 录音文件转写 → 文本交给 `CommandParser`。

实现见 `Services/DashScopeASR.swift`:`GET /uploads?action=getPolicy` 获取临时凭证 → multipart 上传到 OSS → `POST /services/audio/asr/transcription`(`X-DashScope-Async` + `X-DashScope-OssResourceResolve`)→ 轮询 `/tasks/{id}` → 拉取 `transcription_url` JSON 的 `transcripts[].text`。

**API Key 配置(不入库)**:
```bash
cp BinanceVoiceAgent/Config/Secrets.example.swift.template BinanceVoiceAgent/Config/Secrets.swift
# 编辑 Secrets.swift 填入 sk-…;该文件已在 .gitignore 中
```
也可在 App「设置 → 语音转写模型」里临时覆盖 Key(存 UserDefaults)。

调试:`-demoAudio /path/to.wav` 启动参数会跳过录音、直接把该文件送云端转写,用于模拟器验证整条链路。

## 工程结构
- `BinanceVoiceAgent/` App target:`AppState` 状态机、`Services/`(Speech(录音)/ DashScopeASR / Parser / Biometric / Notification / Order / IslandFlow)、`Intents/`、`Views/`、`Config/Secrets.swift`(gitignored)。
- `BinanceVoiceAgent/Shared/` App 与 Widget 共用:`TradeActivityAttributes`、`IslandIntents`、`Theme`。
- `BinanceVoiceWidget/` WidgetKit 扩展:`TradeLiveActivity`(锁屏卡片 + 灵动岛 expanded/compact/minimal)。
- `OrderService` 目前为模拟成交(接口顺序对齐 `/fapi/v1/leverage → /marginType → /order`,可直接替换真实调用)。

## 运行
```bash
brew install xcodegen
xcodegen generate
open BinanceVoiceAgent.xcodeproj   # 选真机运行(麦克风与灵动岛在真机上最完整;需先配置 Secrets.swift)
```

模拟器演示(无需真实录音):
```bash
# 云端 ASR 链路:用一段 wav 代替麦克风(say -v Tingting 生成 + afconvert 转 16k 单声道)
xcrun simctl launch booted com.hackathon.BinanceVoiceAgent -demoAudio /tmp/bnv_demo.wav
# 灵动岛流程:启动后回到桌面/锁屏即可看到卡片
xcrun simctl launch booted com.hackathon.BinanceVoiceAgent -demoTranscript "做空 SOL 5倍 逐仓 300U 止损 4%" -island
# 「修改」深链
xcrun simctl openurl booted binancevoice://edit
# App 内流程 + Face ID
xcrun simctl spawn booted notifyutil -s com.apple.BiometricKit.enrollmentChanged 1 -p com.apple.BiometricKit.enrollmentChanged
xcrun simctl launch booted com.hackathon.BinanceVoiceAgent -demoTranscript "做多比特币 十倍 全仓 200U 止盈7万 止损6.5万" -autoSubmit
xcrun simctl spawn booted notifyutil -p com.apple.BiometricKit_Sim.pearl.match
```
注:模拟器截图不包含灵动岛图层,锁屏可看到同一 Live Activity 卡片。

## 示例指令
- 做多比特币 十倍 全仓 200U 止盈7万 止损6.5万
- 做空以太坊 20倍 逐仓 500U 止盈5% 止损3%
- short DOGE 50x isolated 300 usdt tp 0.2 sl 0.14
