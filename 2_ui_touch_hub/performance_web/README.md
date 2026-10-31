# 手机演奏页（2026-10-30 安卓直连版）

> **2026-10-31当前规则（覆盖下文临时默认起音/旧协议说明）：** App0.2.4/code6每次连接先HELLO nonce；在UI演奏页点击CALIBRATE、待LEFTKEY后按实体最左键，F15捕获0x29/0x35/0x41/0x4D。板端回报校准OK、32键范围和epoch后才能上传。App保留原MIDI，对上传副本整体移调：原调可用则保留，否则优先八度再整体半音；最高−最低＋1≤32允许，>32警告且拒传，不折八度/丢音/截断。新生产协议STATUS26、BEGIN8携带epoch，必须配套新UI固件；旧板不能仅靠安装APK启用校准。音频Note/CC/LFO协议和接线不变。19颗白键灯亮、最后5灯灭；改八度后重新校准/传曲。详见 `doc/MIDI_RANGE_ADAPTATION_2026-10-31.md`、`CODEX_HANDOFF.md` 顶部。此轮源码/仿真/APK不等于已经综合或上板。

**当前入口**：`index.html`加载`protocol.js`、`midi.js`、`phone_app.js`；Android本地壳通过RFCOMM连接已配对HC-07，使用板卡真实ACK、MIDI完整性校验和I²S录音8k WAV分块下载。模块RXD接F14、TXD接F16、共地。灯带DIN为F13，C14仅调试；不是旧C14灯带方案。

完整协议／供电边界／上板验收：`doc/HC07_PHONE_PROTOCOL_AND_ACCEPTANCE_2026-10-30.md`。APK构建：`python tools/build_phone_apk.py`，输出唯一`impl/phone_apk_*/FPGA-Performance.apk`。MIDI容量16384，32键音域从板卡状态获取；默认最低音60临时，需实体确认。不静默裁剪曲谱。

电脑网关仍可作为可选工具，现转发双向原始二进制；**dry-run不产生板端ACK**。适配器TX→F16/RX←F14/GND共地。网页自身不能把HC-07当作BLE设备连接；安卓请用APK。`app.js`保留历史，已不被入口引用。

## 以下为旧网关阶段历史（不作为当前接线／容量／ACK依据）

`index.html` 是手机浏览器使用的控制页。它在浏览器本地解析 MIDI，按
`tools/performance_protocol.py` 定义的 V1 二进制帧通过 WebSocket 发送给网关。

网关运行在与手机同一局域网的电脑、树莓派或无线串口模块上。它把帧原样
转发到 UI 板的 `debug_uart_rx`（E13），速率为 115200、8N1。UI 板的 E13
不能接音频板 E19；E19 仍然只给实体钢琴键盘转换模块使用。

## 本机 dry-run

```powershell
python tools/performance_gateway.py --dry-run --host 0.0.0.0 --web-port 8080
```

手机访问网关机器的 `http://<网关IP>:8080/`，选择 MIDI 后连接网关。网页
会显示每个二进制帧的确认消息，但不会打开串口。

## 接 UI 板

网关机器安装 `pyserial` 后，将串口适配器 TX 接 UI E13，适配器 GND 与 UI
板 GND 相连，再运行：

```powershell
python tools/performance_gateway.py --serial COMx --baud 115200 --host 0.0.0.0 --web-port 8080
```

电平必须是 3.3 V TTL；不要把 RS-232 电平直接接 FPGA，也不要把 TX 线并
接到音频板 E19。C14 是 UI 板演奏页的 WS2812 数据输出，需要外部
3.3 V→5 V 电平转换和独立的 LED 供电。

当前 UI 位流的片内调度器容量是 1024 个 Note 事件；网页会在发送前拒绝
更大的事件列表，不会静默截断。要支持更长或更密的曲目，需要后续显式
BSRAM/DDR 流式后端。
