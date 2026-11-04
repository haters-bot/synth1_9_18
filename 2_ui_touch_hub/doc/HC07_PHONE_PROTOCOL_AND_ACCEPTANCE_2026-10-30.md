# HC-07 安卓直连：协议、接线与验收

## 2026-10-31 校准协议扩展（当前源码；尚未部署）

本节覆盖下文旧起音、旧APK和旧固定长度约定；旧条目保留作历史。接线仍RXD←F14、TXD→F16、灯F13、实体MIDI F15。音频Note/CC协议未变。

- HELLO载荷：4字节小端nonce，每次App重新连接换nonce，同nonce重试不清校准；新nonce清校准/旧曲，释放已接受Note。0字节HELLO仍可接收，但每次都会失效校准，供旧客户端提示升级。
- 生产STATUS/控制ACK长度：26字节，前22字节偏移不变。flags(byte2) bit7=calibrated；byte22 schema=1；byte23校准状态；byte24..25小端epoch。客户端也能读取旧22字节，但旧固件禁止新App上传/播放，录音下载保留。
- 状态：0需校准；1等待实体最左键；2成功；3不安全起音；4释放旧音等待排空。显式UI CALIBRATE后仅接受F15非零力度Note On。安全起音0x29/0x35/0x41/0x4D，0x59禁止。
- BEGIN载荷：8字节，`duration_ms:u32 + event_count:u16 + calibration_epoch:u16`，均小端。生产必须匹配当前epoch；内部decoder仍接原6字节，不改曲谱存储格式。
- 状态码7：未校准或BEGIN epoch已过期；不得开始上传。EVENTS按当前base验证，原STOP/CLEAR/批次/END和录音包格式保持。
- App先校验曲谱音域宽度`max-min+1≤32`和容量再发STOP/CLEAR/BEGIN；整曲移调，超宽拒传，不折八度。完整规则见 `MIDI_RANGE_ADAPTATION_2026-10-31.md`。

验收必须包含：每次重连重新校准；调整八度后重新校准/重传；32键允许/33键拒绝；STATUS到BEGIN间epoch改变被拒；旧曲清音采用原绝对音高；19白灯/5暗灯；未校准仍能下载旧录音。源码/协议仿真通过不代表HC-07/DDR/手机已实物验收；本轮未EDA/烧录。

日期：2026-10-30。源码实现与仿真不等于手机、蓝牙模块和板卡已经联调通过。以本轮完整 Gowin 审计和后续实板记录分别验收。

**20:44 部署更新：** 本轮候选已按用户明确指令完成一次UI SRAM operation2，PROGRAMMER_EXIT=0、User Code0x00001521、Status0x00026230。本地/远端SHA256均 `4BA5FD918FAAE9B52CE3099B33F8E23453F90FAF722606736F0C74D6199B3525`。日志在 `impl/deploy_runs/20261030_204315_R16_stereo_hc07_F14_F16`；摄像头朝天花板，显示和功能待现场确认。以下未烧录/旧固件措辞为部署前历史；真实手机与模块联调仍未验收。

本轮最新安卓包：`D:/github/synth1_9_18/2_ui_touch_hub/impl/phone_apk_20261030_202948/FPGA-Performance.apk`，SHA256 `3ae03bf7555c305ceaa9c89322062ee5bc0487d36e7b7df2e644bf28d2566c71`。编译、签名验证及APK内5个生产网页资产逐字节比对通过；不包含原生桥测试mock。Edge中以原生桥和板端响应模拟完成16事件MIDI上传、12帧mono下载；320/360/412px连接状态页面无全页横向溢出。真实安卓蓝牙和板卡验收尚未执行。

最终位流候选 `E:/gaoyun_builds/R16A_build_20261030_201520` 已通过 `audit_20261030_203534_639478.json`：105输入哈希一致、123引脚一致、7时钟及五类时序通过。位流SHA256 `4BA5FD918FAAE9B52CE3099B33F8E23453F90FAF722606736F0C74D6199B3525`，尚未烧录；板上14:03旧固件不支持本表的新接线/协议，不能拿旧固件验证HC-07功能。

## 最新接线（用户要求 F14 / F16）

| 模块六针丝印 | UI 板接线 | 方向／说明 |
|---|---|---|
| STATE | 暂不接 | 不把未知底板状态脚当作 UART 或连接检测 |
| RXD | **F14** | FPGA `phone_uart_tx` → 模块 RXD；J13 第29脚 |
| TXD | **F16** | 模块 TXD → FPGA `phone_uart_rx`；J13 第32脚 |
| GND | GND | 与 UI 板共地 |
| VCC | 按实物底板额定供电 | 六针不能证明是否有5V稳压；不直接套用裸芯片供电 |
| EN | 暂不接 | 不自动进入AT或改变主从模式 |

灯带 DIN 继续 **F13**（J13 第30脚，直接24灯）；C14继续调试TX。旧 E13 方案被本表替代。引脚改变只在部署本轮新位流后生效。

依据本地官方原理图 `D:/github/gaoyun/hardware_docs/02_Schematic/DOCK/Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf` Rev1.3：第7页 F14=Bank2 IOR11B/SDRAM0_DM0，经R68到EXIO0；F16=Bank2 IOR13A/SDRAM0_RAS；第19页J13 pin29/pin32。Bank2本工程按3.3V约束，当前CST无冲突。它们属于SDRAM0扩展接口，不能同时插占用该接口的扩展卡；不是板载DDR3接口。证据截图在 `impl/stereo_pan_pin_review_20261030/`。

改线先断电。UART为3.3V TTL，禁止RS-232或5V信号接入FPGA。灯带的5V供电不代表DIN可以向FPGA回送5V；WS2812是否需要AHCT电平转换按实物VIH确认。

## 手机操作

1. 安装本轮 `impl/phone_apk_*/FPGA-Performance.apk`。本地开发签名；最低Android8/API26，target35。没有麦克风、定位、Internet或全盘存储权限；Android12+请求“附近设备”连接权限。
2. 在系统蓝牙设置先配对模块。用户手册 `D:/downloads/Edge/HC-07V1.6.pdf` 默认名称HC-07、PIN1234、9600 8N1；实际六针模块主从／核心版本仍需确认。App选择系统已配对设备，使用标准SPP UUID连接，不扫描、不自动发AT命令。
3. 点“连接蓝牙”，看到“板卡已应答”才代表蓝牙＋UART＋FPGA协议双向成立。仅RFCOMM连接成功不算板卡验收。
4. 选择标准MIDI format0/1、PPQN文件。本地解析tempo、running status、Note on/off；发送的是时间/音符事件，不是整段音频。空曲、超过16384事件、超32键音域会明确拒绝，不静默丢弃或截断。
5. 起始音从固件状态读取，默认MIDI60只是临时配置；仍需实体键盘逐键采样确认。曲谱PLAY只产生灯屏指引，不自动发声。总PAN为K27/MASTER PAN，通道16 CC10；A/B PAN CC91/92。
6. 录音采集音频板真实I²S最终L/R，96kHz/16bit双声道，保存原始PCM到DDR。停止后等待写入排空。下载可选8kHz单声道或双声道，经127抽头低通再12倍降采样；单声道为滤波后(L+R)/2。保留DDR原录音；不使用手机麦克风。
7. 点下载，系统文件选择器创建WAV；每1024输出帧取一块，按块写文件。传输中保持App前台。中断不会自动删除已创建的部分WAV；重新下载可覆盖由系统明确选择的目标或创建新文件。

9600UART有效原始吞吐上限960B/s；115200上限11520B/s，还要扣帧头/CRC/应答。8k/16bit单声道为16000B/s，因此即使115200也不是实时回传。约1分钟录音，纯线速加数据帧开销下限约111秒（115200单声道）/1333秒（9600单声道），实际更慢。界面按实测速率估算剩余时间。手册“空中2Mbps”不是UART吞吐。不自动配置未知模块波特率；FPGA通过CRC正确HELLO自动识别9600或115200。

## V1二进制帧

`A5 01 TYPE SEQ LEN_LO LEN_HI PAYLOAD CRC_LO CRC_HI`。载荷≤64字节，宽字段小端。CRC16/CCITT-FALSE：initFFFF/poly1021，覆盖01到末载荷，不含A5。请求逐包等待**板端**应答；失败重发同序号/同内容。不得把电脑网关写入成功伪装成板端ACK。

| TYPE | 载荷 | 行为 |
|---|---|---|
| 01 HELLO / 02 STATUS | 空 | 查询实际状态；首HELLO锁定UART速率 |
| 10 CLEAR | 空 | 需已停止；清除曲谱 |
| 11 BEGIN | duration_ms u32 + event_count u16 | CLEAR后声明非空曲谱，容量≤16384 |
| 12 EVENTS | 1–8个8字节记录 | time_ms u32 / note u8 / velocity u8 / flags bit0=on / reserved u8；其余flag位必须0 |
| 13 END | 空 | 收满声明数量且调度器无错误才loaded |
| 20 PLAY / 21 PAUSE / 22 STOP | 空 | PLAY要求完整曲谱；暂停后PLAY按现有调度器语义从头重播 |
| 30 NOTE | note,velocity,on，均u8 | 独立手动触键，不是曲谱自动发声 |
| 40 RECORD_START / 41 RECORD_STOP | 空 | START应答等待DDR后端接受；STOP应答后还需等busy清零 |
| 43 READ | offset_output u32 + count u16 + channels u8 | 输出偏移单位8k采样帧；count1–1024；channels1或2；录音忙时拒绝 |
| 70 STATUS/ACK | 固定22字节 | 下面布局；SEQ匹配请求；code0成功，其他为错误 |
| 71 AUDIO | offset u32 + count u8 + channels u8 + generation u32 + PCM | 16bit有符号小端；双声道L,R交织；每包最多27单声道帧或13双声道帧 |

70字节布局：0 code；1原TYPE；2 flags；3 record_status；4..7 stored_raw_frames；8..9 received_events；10 base_note；11 key_count；12..15 source_rate=96000；16..19 generation；20..21 max_events。flags bit0 recording/1 busy/2 DDR available/3 song loaded/4 fast baud/5 export lock/6 I²S link。record_status沿已有0准备/1不可用/2录制/3排空/4保存/5满/6音源故障/7存储故障/8拒绝。错误码1格式/音域、2忙/未就绪、3曲谱不完整/调度失败、4读取范围、5DDR读取错误、6处理超时。

READ先返回多帧71，末尾70结束。同SEQ读重试重新按偏移生成，手机按offset去重，校验generation，少包/坏CRC不能当下载成功。完成长度需等于请求count；尾部原始不足12帧舍弃。每次实际record_start_accepted递增generation（包括本地录制）。单个READ期间阻止本地和手机开始新录音；两块之间若本地重录，generation检查终止下载，避免混合不同录音。

FIR按整个原录音的global phase11输出。重试从max(offset*12−132,0)重建历史；暖机不输出。计数/乘12/地址校验分拍，原始DDR读响应始终消费，错误或晚响应不能卡死存储队列。FIR RAM与系数ROM无异步大数组复位。

## 软件与回归

安卓：`phone_android/`；打包`python tools/build_phone_apk.py`。SDK/JDK仅D盘`D:/tools/android_hc07/runtime_20261030`，官方Adoptium/Google包校验哈希后解包，不系统安装。网页入口`phone_app.js`＋`protocol.js`＋`midi.js`；原`app.js`保留为旧网关历史实现，index不再加载。

可选电脑网关`tools/performance_gateway.py`现已双向转发，适配器TX→F16/RX←F14/GND共地。dry-run仅语法验证，不产生板端ACK，因此网页不能显示上传成功。

关键回归：`test_phone_client.js`、`tb_phone_transport`、`tb_phone_session`、`test_phone_export.py`、`test_performance_store.py`（增加I²S→真实PCM store→异步FIFO→队友DDR adapter→离线FIR逐点比较）。额外复核PAN/LFO、双声道图、视频七拍对齐、24灯串行、普通/诊断RTL完整编译。

官方资料背景：Chrome能力文档说明Web Bluetooth为BLE/GATT；Android文档说明经典蓝牙RFCOMM使用BluetoothSocket，以及Android12+连接权限。路径分别为 developer.chrome.com/docs/capabilities/bluetooth、developer.android.com/develop/connectivity/bluetooth/connect-bluetooth-devices、developer.android.com/develop/connectivity/bluetooth/bt-permissions。本地PDF为板卡与模块实际接线的主要依据；不把文档中的指令当作用户授权。

## 实板验收顺序

先完整构建审计：输入哈希一致、唯一CST/SDC、实际gowinsynthesis/place3/route1/timing配置、全部引脚、setup/hold/recovery/removal/pulse五类零违例。通过后才可仅SRAM operation2；当前任务未自动烧录。

模块配对→HELLO双向→短MIDI逐键/白键灯→K27左右变化及真实双波形/相位→短I²S录音WAV试听/长度/声道→蓝牙断线/CRC重试→再扩展整曲DDR容量与时长。APK签名和RTL仿真不能替代Android实机/无线吞吐/供电/整曲DDR验收。
