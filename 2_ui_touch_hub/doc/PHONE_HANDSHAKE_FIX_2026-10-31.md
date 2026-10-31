# App 0.2.5：蓝牙已连但板卡未应答的恢复与诊断

## 范围和结论

用户安装版本为 0.2.4，要求优先修改 App。本轮没有修改 RTL、串口协议或引脚，没有启动 Gowin 综合布线，也没有烧录 SRAM/Flash。

源码核对：App 发出的 HELLO 为 type=1、四字节会话 nonce；当前固件接受该格式并返回 26 字节状态，App 同时支持 22/26 字节状态。因此没有证据表明新固件删除了握手或与 App 的 HELLO 格式不兼容。

只读 JTAG 证据 `E:/gaoyun_builds/phone_link_readonly_20261031_232901_183752.log` 显示 UserCode=0x0000171D、Status=0x00026230，与已部署统一功能版一致。本轮仅执行 Read Device Codes，没有写板。

**尚未确定用户现场首次丢失 ACK 的物理原因。** 模拟板端测试证明的是 App 恢复逻辑缺陷及修复；不能据此宣布真实手机、HC-07 或板卡串口链路已经验收。

## 已复现的软件问题

1. 首次 HELLO 超过原有重传次数后结束，周期轮询又要求已经取得状态；首次握手失败会永久停止请求。
2. 蓝牙 socket 已连时再次点击连接，会重新打开设备选择器，无法直接重试板卡握手。
3. 握手等待期间断开，旧请求的失败回调可能覆盖断连状态。
4. 原提示无法区分完全没有 RX、已有损坏/不兼容返回、明确拒绝握手。

修复前生产入口测试失败证据：`E:/gaoyun_builds/phone_handshake_fix_20261031_233231_602153/before_failure.log`，断言为 `retry must reuse the connected socket, not open device picker`（1 !== 0）。该目录同时保存修复前源码哈希。

## 修改

- `performance_web/phone_app.js`：增加最多三轮握手恢复和“重试板卡应答”，复用现有连接；每轮沿用 Client 的三次发送、3500ms 超时。每次真实连接生成新 nonce，同一连接所有握手重试复用 nonce，避免丢 ACK 后重试又重置板端校准和曲目。隔离过期回调，保留校准后才能上传的限制。
- `performance_web/protocol.js`：增加可选 trace 回调，统计 TX/RX 字节、有效/坏帧和最近十六进制；不改变命令、编码、CRC 和帧格式。
- `performance_web/index.html`、`style.css`：增加可换行的链路诊断区，显示版本 0.2.5，资源 URL 带版本号。
- `phone_android/AndroidManifest.xml`：versionName=0.2.5，versionCode=7。
- `phone_android/src/cn/gaoyun/performance/MainActivity.java`：WebView 使用 LOAD_NO_CACHE，避免升级后使用旧网页资源。
- `tools/test_phone_handshake.js`：真实生产入口与协议 Client，模拟板端；覆盖超时恢复、有限重试、同连接 nonce 保持/重连更新、断连竞态、22/26 字节 ACK、拒绝/静默/异常长度和校准限制。
- `tools/test_phone_midi_selection.py`：纳入上述握手回归。

## 验证与交付

- 手机软件完整回归：`E:/gaoyun_builds/phone_selection_20261031_233409_523272/result.json`，全部 PASS，18 项输入哈希与工作区一致。含 22,663 个音域用例、原生文件选择、上传 ACK/进度、逐包录音导出、断连和新握手回归。
- APK：`E:/gaoyun_builds/phone_apk_20261031_233409_562252/FPGA-Performance-0.2.5.apk`。
- SHA256：`c8590797a9752883b2df9d9f37aeb4f1ae4f16b81b79ed2ff8507dd444b816f8`。
- APK v2/v3 验签通过，与 0.2.4 签名证书相同；12 项打包输入及包内 7 项网页资源逐字节匹配。
- 已部署固件 `E:/gaoyun_builds/R16A_build_20261031_222517/source_manifest.json` 的 116 项输入仍全部匹配工作区，证实本轮没有改变 FPGA 构建输入。
- 交付检查：APK 同目录 `release_verification.json`；保留全部旧 APK、构建和失败证据，不删除、不推送。

## 手机验收方法

覆盖安装 0.2.5，关闭旧 App 后打开新版，确认页眉显示 0.2.5，再连接已配对的 HC-07。等待 HELLO，首次超时会自动恢复，也可使用“重试板卡应答”。成功后仍必须在 UI 板点击 CALIBRATE 并按最左实体键，然后才能上传曲目。

若仍失败，记录诊断区 RX 字节数、有效帧、坏帧和最近 RX。RX=0 只说明 App 没收到串口返回，不能仅凭该现象断言板卡程序有错；已有 RX 则利用完整返回字节继续排查。真实手机与模块验收仍待用户反馈。
