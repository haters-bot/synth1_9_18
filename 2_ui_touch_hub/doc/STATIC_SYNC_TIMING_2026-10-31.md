# 2026-10-31 静态同步正式构建时序修补

实际工程：D:/github/synth1_9_18/2_ui_touch_hub。用户授权综合布线及UI SRAM2。Flash/音频/推送不操作，所有失败产物保留。

## 首构建失败证据

- 提交31a20f4d862220c6d5bfb4aeb8e054613f56c527；normal工程2_ui_touch_hub.gprj，顶层ui_touch_hub_top。
- E:/gaoyun_builds/R16A_build_20261031_164831，17:16:48退出0；并未烧录。
- audit_20261031_171712_800915.json：112输入匹配、124引脚匹配，197setup端点违例、hold0。最差setup−1.897ns，pixel45.667/50MHz；DDR101.294/100MHz；其他四类检查通过。
- 主路径static_cc_sync.scan经40项live值/ID选择、MIDI解码进入UART FIFO和SysEx仲裁。旧旋钮步进优先链−1.195ns，导航文字列号全局归约−1.120ns亦暴露。
- 实际pnr/cmd.do确认place3/route1/timing/correct_hold1，与成功配置一致，不能归因为默认选错。timing_closed=false；位流不得部署或原样重跑。

## 小修补与不变量

1. static_cc_sync：输出请求、ID、值寄存；scan在请求待接收期间不动。堵塞时刷新待发值；cc_accept边沿记录旧寄存值，即UART实际取走的数据。恰好该边沿发生的较新UI编辑仍与sent不同，下轮扫描补发。40项顺序、启动排空后释放LFO、Note优先、原SysEx原子入队均保留。读数据/已发送值使用常量切片和并行归约，规避已证实的动态切片综合问题。
2. knob_ui_control：32个唯一物理ID并行掩码归约替换优先链，不加事件延迟，不改focus/增量方向或设置表。
3. ui_navigation_renderer：127个文字矩形的列号分为8组，在既有stage0分别寄存，原stage1的同步ROM前归约。页结构、文字内容、总像素延迟不变；其余颜色/valid/字形元数据仍跟同一像素。

## 验证证据

- E:/gaoyun_builds/six_fix_20261031_172722_196852：当前堵塞槽刷新、接收同拍编辑竞态通过；40启动CC/81完整LFO、串行拥塞/Note/实时更新通过；133120组步进等价及32ID唯一性通过。导航达到240秒wall-clock时限，失败/超时日志保留，不记为通过。
- E:/gaoyun_builds/navigation_timing_20261031_173332_683142：使用上述冻结源码和测试，以900秒单阶段时限重跑导航及UART，全部通过；result.json同时核验前三项已有PASS日志与源码哈希，共6项passed=true、workspace_matches_snapshot=true。导航272679个变化像素的列号/ROM/背景/valid与原流水一致，没有改变检查范围或减少用例。串行仲裁51实际字节、普通Note/CC映射通过。
- E:/gaoyun_builds/six_fix_20261031_172926_376641：其余14项LFO/ENV/能力/预览/字节回归全部通过，workspace_matches_snapshot=true。包含96完整renderer速率组合/469帧、783360个预览值对原音频RTL、24支持/29NC绑定及实际灰色像素。
- LFO真实31250 baud已观察target6 f07d4f027ff7、target13 f07d56027ff7；两个Commit均f07d7e0000f7。ENV1/2实际CC保持18..1B/20..23，Hold/ENV3不发送。

## 部署门禁

完成回归后保存本地源码检查点，唯一隔离正式构建。重新审计全部输入、7时钟、124引脚及setup/hold/recovery/removal/pulse五类；全部通过才使用deploy_verified.py --board ui --target sram一次。SSH写板超时后只核验远端记录，禁止自动重烧。生成位流、RTL通过、成功写SRAM和用户现场功能验收是不同结论。
