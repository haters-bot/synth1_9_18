# 新增采样提取钢琴预设

本轮只修改UI工程及交付波表文件，音频RTL、音频协议、53个LFO目标、其他UART功能保持原样。用户明确授权完成验证后构建并烧录UI SRAM，不写Flash。

## 音色和兼容边界

SYSTEM → PRESETS → ACOUSTIC中依次显示原SYNTH PIANO、新SAMPLED GRAND PIANO、SOLO BOWED STRINGS。新预设内部ID为12，原0～11号ID及完整参数保持不变。新项同样完整装载74个参数、清旧LFO路由并发送708字节，复用原有Note优先及最新待执行批次机制。

现有音频引擎是周期波表DDS，不是长采样播放器。新音色使用真实钢琴录音的同步谐波分析结果，A为主体、B为短促明亮起音，配合独立ADSR；没有加入多音区/多力度采样、非周期琴槌噪声、踏板或弦共鸣模型，因此不能把“真实录音提取”写成已达到多采样钢琴的听感。

录音来自University of Iowa Electronic Music Studios的Steinway & Sons Model B：

- 许可说明：https://theremin.music.uiowa.edu/MIS.html
- 原始文件：https://theremin.music.uiowa.edu/sound%20files/MIS/Piano_Other/piano/Piano.mf.C4.aiff
- 原始AIFF SHA256：`1a7d8ddea94a3639fa58d79ebcc0b09b170b9c324811d2b705f97e278fdefac2`

选择第一麦克风，按检测基频约262.613Hz做12周期Hann窗同步谐波分析，保留60谐波、移除DC并对齐各帧基频相位，最后以统一增益量化为有符号16位。256帧是音色/亮度轴，现有预设不会把该轴自动当作每个Note的时间轴推进。主体和亮音层分别使用不同时间窗口，短层ADSR形成快速衰减。

## SD交付文件

输出：`E:/gaoyun_builds/piano_sampled_release_20261102/sd_card/WAVEBANK.WTB`

- WTB1 v1，12表，每表256帧×256点、16bit、小端；总长1,572,896字节。
- SHA256：`ac2253f3eacc7397ace79c6d9f54f266409eac6f69383c45ad1d8da7f95437ee`
- 原D:/github/gaoyun/WAVEBANK.WTB未覆盖；原00～09载荷逐字节不变，只更新包头表数并追加10、11。
- 10号Sampled Piano Body，11号Sampled Piano Bright Attack。
- UI的同源本地预览ROM已扩为12表，不伪造音频板SD加载状态。
- 附带PianoBody.wav/PianoAttack.wav是每帧256点的波表容器，不是整段钢琴演奏录音。

音频参考固定到本轮fetch的origin/main `2b09db0bdf74c6c8cf8933674cb7e343e9f995b5`。其sd_wavetable_loader允许1～16表；详细格式和SD路径见该提交的docs/sd_ddr_wavetable_path.md。UI A/B选择分别发CC49=10、CC50=11，即`BF 31 0A`、`BF 32 0B`，不需要新增音频协议。

先备份SD上现有波表文件，再把新包按音频项目已有加载位置和文件选择规则复制到SD；应只保留要加载的那一个WTB包，避免目录顺序选错。插拔卡前断电，音频板重新上电加载后再选新音色。当前电脑没有识别到可写的音频SD卡，不能声称已替用户完成实体SD复制。

## 验证与部署

首轮正式构建`R16A_build_20261102_210645`保留为失败证据：21条setup违例、最差−0.729ns，其余四类为零，未烧录。关键路径集中于`static_cc_sync`的74路槽位读出、比较及扫描索引反馈。修复在读出与比较之间增加一拍，仍保存实际FIFO接收值并保留背压刷新；没有改变MIDI协议、时钟或时序约束。加速仿真启动测试的排空等待改为连续200拍空闲，避免新增扫描拍导致固定等待提前返回；参数值及发送字节断言保留。

12项旧预设的完整数据与9ee5dce逐项比较不变；13项预设的实际UART串行输出与固定Python发送方法一致，共12051个控制字节，包含重发、快切、启动立即应用、后续CC/LFO编辑及Note优先。

真实顶层触摸验证原声卡片顺序0/12/1及全部13项选择，512个七拍像素检查、六分类渲染通过。预览独立检查393476个采样，覆盖12表、128个WT位置、双OSC、越界钳位与缓存原子切换。normal/debug层次展开和4352项FX输入回归通过；17项原有RTL回归、最终Gowin审计和SRAM烧录状态见本轮acceptance与交接记录，不能由本文中的源码说明提前认定完成。

旧目录中间文件清理曾两次被自动审批以“blocked by policy”拒绝，未执行删除；随后用户手动腾出E盘空间。未改用C盘。
