# UI / Android 统一版本验收记录（2026-10-31）

## 状态

源码检查点：`97d2b37a53364f9ee80e1712cfab2e5c7279fcd9`，integration/dual-138k-uart-phase1，本地保存，未推送。正常工程：`2_ui_touch_hub.gprj` / `ui_touch_hub_top`。

首轮构建：`E:/gaoyun_builds/R16A_build_20261031_211342`，21:37完成但**审计失败，未烧录**：15个setup端点，worst -1.302ns，pixel46.944/50MHz及DDR88.640/100MHz不通过；其他四类、124引脚及116输入一致。证据完整保留，正在按负路径局部修补并重跑相关回归。板上原版仍为173812 / 83ed585 / UserCode 0x3056。后续以CODEX_HANDOFF顶部和新构建目录的审计、部署记录为准。

## 本次统一包含

- WARP模式菜单与独立Amount：A CC38/39，B CC40/41。
- 五个效果器Distortion、Phaser、Chorus、Delay/Reverb、Compressor；第六PITCH页集中Vibrato和Portamento，CC82～86。
- WAVEBANK.WTB目录验证为10张，SD BANK 00～09；不杜撰表名、SD已就绪状态或真实波形预览。
- A/B/MASTER PAN协议不变，值64指针居中。
- Android原生选曲、完整PCM后导出WAV、下载逐包进度；APK0.2.4/code6。
- 手机每次连接后，在UI点CALIBRATE，出现LEFTKEY后按实体最左键；F15捕获安全起音0x29/35/41/4D。App收到26字节状态中的成功/epoch后才允许上传。
- 整曲音域含两端≤32可移调至校准窗口；原调可容纳则保留，否则先八度再半音。>32拒传，不折八度、不丢音、不改原文件。
- 跟弹、试听、演奏三模式与校准后的灯屏共用音高窗口，19白灯有效、末5灯熄灭。
- 保留LFO绑定/8档速率/重启/Commit、53固定目标及NC能力标记、ENV1 CC24～27 / ENV2 CC32～35、其他UART仲裁。

音频协议以origin/main `dbffe3768fa29405ad50845d4e915577d1c16557`的真实接收代码为基准，本轮未改音频RTL。该版本含C19 Note接收修复。源冻结、Git规范化一致性和所有证据索引见构建目录`functional_evidence.json`（116项清单）。

## 软件验证

- 23项RTL：`six_fix_20261031_210551_921708/result.json`，全部通过。
- 6项音频协议/画面/仲裁：`six_fix_20261031_210334_282530/result.json`，全部通过。
- 手机选曲/22663音域用例/校准gate/CRC/断连/录音导出：`phone_selection_20261031_210906_550676/result.json`，通过。
- normal/debug完整层次：`ui_elaboration_20261031_210552_318706/result.json`，通过；官方原语加DDR stub，不替代时序和实物DDR验证。
- APK：`E:/gaoyun_builds/phone_apk_20261031_205654_857065/FPGA-Performance.apk`，SHA256 `bc0c891f0c0505d644c45e24d50ea1254b19318ea1a048e9fdd03faf2d5c24fb`，原签名证书一致，v2/v3通过，6份网页资产逐字节与工作区一致。

## 上板后现场验收顺序

1. 独立安装APK0.2.4；连接HC-07，在UI进入演奏页校准，看到LEFTKEY后仅按实体最左键。App显示校准音域后再上传。
2. 用音域不超过32的MIDI验证原调保持或整曲移调；跨度33的曲目应拒传。换键盘八度后重校准、重传。
3. 依次验证试听发声、跟弹等待正确实体键、演奏按时走；19白灯与屏幕音高对应，末5灯不亮。
4. 由音频板I²S输出录制真实PCM，下载进度持续变化；取得大于44字节且可播放的WAV。该步骤不是手机麦克风录制。
5. WARP和五FX逐项听感核对；PITCH开关/拖动发出BF 52～56，PAN三路中心/两端核对。波表由音频SD实际载入。
6. UI TX抓取LFO1→Detune：F0 7D 4F 02 7F F7，Commit后解绑才归零；2/4Hz模式03/04，ENV1/2分别检查BF 18～1B / BF 20～23。

真实安卓/HC-07/实体键盘/灯带/SD/I²S整曲DDR/音频听感尚未由本轮软件测试证明。Gowin退出0和生成FS也不代表时序闭合；必须五类时序、七时钟、全部引脚和输入审计通过才部署。部署仅UI SRAM operation2，不写Flash、不操作音频板，SSH写入中断禁止自动重烧。
