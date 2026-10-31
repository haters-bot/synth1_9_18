# LFO八档速率：根因、最小修复与协议验证

## 结果与边界

源码修复及RTL/官方网表功能仿真完成。仅UI侧3份生产RTL有小改动，没有重构主体架构、修改音频协议或其他参数编码。用户随后明确授权“构建并烧录”，正式构建及一次SRAM2部署已完成，当前板上UserCode为8E85。隔离探针自动引脚、5Mbaud及缩短计时，仅供仿真，禁止部署。

## 16:15 正式构建与部署证据

- 生产源码提交138943f90bc63f4cf7180182cd7b39aa2c941c99，实际工程2_ui_touch_hub.gprj/顶层ui_touch_hub_top；独立构建 `E:/gaoyun_builds/R16A_build_20261031_155419`，实际place3/route1/timing/correct_hold1，没有原样重跑或更换策略赌结果。
- functional_evidence.json确认五份关键源Git/工作区/快照一致，八档网表、renderer绑定/曲线/仲裁、八档标签回归与构建输入匹配；相比此前部署仅editor/panel/sender三份输入变更。
- audit_20261031_161231_494437.json：109输入、124引脚、7时钟全部通过；setup/hold/recovery/removal/pulse五类零违例，最差余量+0.001/+0.189/+0.324/+0.299/+0.451ns。pixel50.001/50MHz、DDR105.561/100MHz。setup只有1ps余量，已明确告知用户，不能称余量充裕或承诺下次必过。
- Logic63543/138240（46%）、Register34541/139095（25%）、BSRAM99/340；位流39834625B，SHA256 **1F35EB3ADC2D5D5AC690518061C169C27ECF0DF76FABD99F18A4A464E3F6A3DF**。
- 写前check-only再审及JTAG只读确认唯一UI板旧9C50；随后唯一一次 `deploy_verified.py --board ui --target sram`，部署 `impl/deploy_runs/20261031_161339_UI_LFO_RATE8_20261031`，双端SHA一致、PROGRAMMER_EXIT=0、CODEX_PROGRAM_COMPLETE、manifest=sram_programmed。写后只读UserCode **0x00008E85**、Status **0x00026230**，completion_record.json保存证据；Flash和音频未操作，无自动重试。
- 摄像头仅拍到工作台/键盘，没有可读UI屏幕，不能据此验收显示及速率功能。2/4Hz的新版实板UI TX仍需用户现场抓包；下文UART字节属于已通过的仿真证据，不伪称新版实物测量。

## 根因

1. 当前界面状态本来就保存协议编号，2Hz为3、4Hz为4，没有Hz转整数或软件发送回调。真实触摸RTL的2/4Hz帧正确；原版综合网表却发零速率。`E:/gaoyun_builds/lfo_route_gate_test_20261031_153830_580367/baseline_gate_sim.log`明确显示all_rates/q_rates/sh_rates均092（三bank各编号2），发送45/46为0000，47为0008（Stepped正确、低三位丢失）。故障定位至`sh_rates[mode_bank[1:0]*3 +: 3]`在本版本Gowin中的综合不等价；不是状态更新失败或读取旧快照。baseline_gate_result.json记录失败，不能将模拟器退出0当PASS。
2. 界面速率按钮在编号5就回到0，导致编号6/7不可达；标签也把其余编号统一显示成8Hz。原版真实触摸回归已在无法到达编号6处失败，证据同目录rtl_sim.log/result.json。

## 最小生产修改

- rtl/midi_uart_tx/lfo_sysex_tx.v，模式组帧处约151行：以三个常量切片分支读取bank0/1/2，保持`{once,stepped,rate_index}`的五位布局及原ID、重启和Commit机制。
- rtl/ui_vector_engine/lfo_editor_state.v，约167行：按钮在7回0，完整遍历八档；不修改预览分频函数或默认编号2。
- rtl/ui_vector_engine/lfo_panel_renderer.v，约159行：明确编号5=8Hz、6=16Hz、7=32Hz的标签，不改页面结构。

七节点曲线和53目标路由编码不改；此前路由常量切片修复保留。

| Hz | rate_index | Smooth/Loop | Stepped | Once | Stepped+Once |
|---:|---:|---:|---:|---:|---:|
| 0.25 | 0 | 00 | 08 | 10 | 18 |
| 0.5 | 1 | 01 | 09 | 11 | 19 |
| 1 | 2 | 02 | 0A | 12 | 1A |
| 2 | 3 | 03 | 0B | 13 | 1B |
| 4 | 4 | 04 | 0C | 14 | 1C |
| 8 | 5 | 05 | 0D | 15 | 1D |
| 16 | 6 | 06 | 0E | 16 | 1E |
| 32 | 7 | 07 | 0F | 17 | 1F |

后四列为mode_value十六进制；每项在LFO1/2/3均验证，总96种。

## 实际仿真UART证据

修复版官方网表：`E:/gaoyun_builds/lfo_route_gate_test_20261031_154256_958600`；加强批次顺序后重用同一网表（没有重跑Gowin）验证：`E:/gaoyun_builds/lfo_route_gate_test_20261031_154639_309116/result.json`。两边RTL/.vo均PASS、源码哈希匹配。真实原始触摸→router→editor→快照→sender→FIFO→UART逐位接收，96组合/469帧；每个测试批次严格检查末尾模式→对应重启→Commit。最终原始网表串口帧保存在后者gate_uart_frames.hex（共469行），已逐段验证以下连续三帧确实存在：

```text
2Hz smooth/loop:
F0 7D 45 00 03 F7
F0 7D 48 00 04 F7
F0 7D 7E 00 00 F7

4Hz smooth/loop:
F0 7D 45 00 04 F7
F0 7D 48 00 04 F7
F0 7D 7E 00 00 F7
```

4Hz Stepped/Once/同时启用的模式帧分别为`F0 7D 45 00 0C F7`、`F0 7D 45 00 14 F7`、`F0 7D 45 00 1C F7`，均有相同重启和Commit。LFO2使用46/重启5，LFO3使用47/重启6，全部组合通过。这些是网表仿真UART实收，不是本轮实板抓包。

补充回归：

- impl/six_fix_20261031_154256_981239：编辑器、完整renderer绑定/解绑/重绑/LFO2/3/超时、快照同拍竞态、51字节Note/CC/SysEx满队列仲裁均PASS。
- impl/midi_lfo_protocol_20261031_154256_909498：53目标不同值、七节点/模式/重启/Commit及普通CC协议全PASS。
- impl/six_fix_20261031_154500_871578：8档界面标签64字符全部PASS；此前154409首次标签测试因测试台缺params.vh而编译失败，已补include，失败目录保留。
- tools/test_lfo_serial_monitor.py：96解码组合、旧全零帧与界面不一致提示、混合CC/实时字节/重启/Commit，共3项测试通过。

## 串口调试打印

新增tools/lfo_serial_monitor.py，在主机读取现有31250-baud MIDI输出并打印诊断文本，不向音频MIDI链路混入ASCII，不占新引脚或改变其他UART。示例：

```powershell
python tools/lfo_serial_monitor.py --hex "F0 7D 45 00 03 F7" --ui-hz 2
python tools/lfo_serial_monitor.py --port COM7 --ui-hz 4
```

COM7只是示例，使用实际采集UI TX的串口；实时串口需pyserial。`--ui-hz`由操作者按当前屏幕填写，不能从MIDI中独立读取屏幕状态。输出UI_Hz、expected_rate_index、实际rate_index/encoded_Hz、stepped/once、mode_value、UI_match及完整字节。测试台则直接读取真实editor状态打印UI速率，避免把推算值当独立测量。

复现命令：`python tools/test_lfo_route_gate.py --build --rates`。此命令只构建隔离仿真探针，不可用于烧录。
