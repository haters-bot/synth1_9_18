# LFO V2与Phase/Rand接入说明

日期：2026-10-28。音频工程与桌面调试工具采用本说明；触屏端发送器需同步实现。
基线：29939e2，回退标签checkpoint/pre-lfo-v2-20261028。Blend继续预留。

## 1. 功能和数据路径

3个独立LFO，每个7个等距7位节点，位置为0、64、128、192、256、320、384。
节点自动生成C1单调Hermite曲线，内点切线用minmod，首尾切线为零；阶梯模式保持当前段节点值。
每个周期使用索引0..383，第384项仅表示曲线终点。循环时首尾值若不等会回跳，这是曲线定义，不能保证周期接缝连续。

```text
V14 USB调试口 / C19控制口 -> 各自UART和解析器 -> 完整控制事件队列
    -> V2配置影子寄存器 -> Commit快照 -> 后台双缓冲构表
    -> 96 kHz边界统一激活表/模式/53目标绑定
    -> 三路查表 -> 单乘法器扫描53目标 -> 整组输出 -> CC域限幅后的映射与平滑
E19键盘口 -> 原有独立演奏事件路径 -> 振荡器任务调度
```

768 kHz振荡器采样、96 kHz音频输出、音频效果顺序和物理串口引脚未改变。
7位调制公式严格采用触屏模型：clamp(base + ((signed_depth * wave) >>> 7), 0, 127)。
wave是Q7.6表值右移6位；source=0直接返回base。+127深度与wave127的乘积右移7位结果是126。
原双极性深度、8共享路由和Comb专用141/256缩放在活动V2路径中不再使用。
Cutoff改为调制完成后再进入现有512样本线性平滑器，仅目标变化时重启插值；其余沿用现有增益/效果器平滑。

## 2. 线协议：仍为14位、7位安全打包

```text
F0 7D id ((value>>7)&7F) (value&7F) F7
```

不能把value按普通16位大端拆成两个8位数据字节。ID与数据字节均小于80(hex)。
CC与SysEx的编号空间独立，例如CC87是Phase，而SysEx ID87是一个绑定槽，互不冲突。

| SysEx ID（十进制） | 值 |
|---|---|
|48..68|bank=(ID-48)/7，node=(ID-48)%7；value=0..127|
|69..71|bank=ID-69；value=rate档位 \| stepped<<3 \| once<<4|
|72|value=4 \| bank（0..2）；将对应bank的重启请求加入下一次Commit|
|73..125|idx=ID-73；value=(source<<8) \| (depth&FF)，source0无、1/2/3为LFO1/2/3|
|126|Commit，value忽略，推荐0|

深度为8位二补码-127..127，非法-128、高位溢出及非法节点/模式被拒绝并置config_error。
速率档0..7为0.25、0.5、1、2、4、8、16、32 Hz。32位归一化相位加法器自然回绕，索引为(phase*3)>>25，不会访问384..511。
32位步进按96000 Hz计算并舍入，最慢档频率误差约17 ppm。Once自然完成一周期后停在第383档，保持该档值；ID72+Commit重启。
无独立bank Enable位；解除绑定(source=0)即取消该目标的调制。

例：Cutoff（idx23）绑定LFO1、深度-64：

```text
F0 7D 60 03 40 F7
F0 7D 7E 00 00 F7
```

## 3. 原子提交与时序

Commit立即锁存完整配置快照，构表时继续运行完整旧配置，随后在96 kHz边界统一切换。
节点/模式编辑应发该bank的ID72重启；仅改变绑定不需重启。ID72不会在收到时立即中断旧曲线。
同一笔事务可发送三个ID72，分别重启三个bank。不能在两个串口同时修改同一套影子事务。
构表器每项6拍，385项约2310拍，三个bank并行，约46.2 us，随后等待下一个音频边界。
Commit完成前的新Commit被拒绝并置config_error；标准31250 baud相邻6字节帧相隔至少1.92 ms，不会因此拥塞。
若自行提高控制口波特率，需使Commit间隔至少100 us，并按config_busy/config_error调试。
路由器一次输出约57拍，约1.14 us，小于每96 kHz周期约521拍；同一批次锁存所有基础值、来源、深度与LFO值，输出统一提交。
表为6份512x13bit同步RAM（3个LFO各双缓冲），逻辑容量39936 bit，明确write-first，RAM内容不复位。实际BSRAM映射和时序必须看后续综合报告。

首次同步为21节点+3模式+53绑定+3重启+1Commit=81帧，31250 baud、8N1纯线速约155.52 ms。
运行期无需持续发送LFO值。Note/CC可在SysEx消息之间优先，不能把普通CC插入一条未完成的SysEx中间。
当前桌面发送器按ID合并变化字段，绑定变化不重启；重连/全量同步会重发所有字段。

## 4. 53目标与当前支持范围

全部53槽都可接收并保存绑定；下面列出的CC说明该目标已经连接到音频参数。
无对应目标继续预留，不得映射到含义不同的旋钮。Unison、ENV等虽然有静态CC，也不代表本版允许实时LFO调制。
Delay Left Time映射当前单声道Delay Time；Right独立时间、Delay滤波、Reverb Spin/Depth和EQ暂未实现。
触屏源码FX实际为Delay/Reverb/EQ，并不是任意的19个连续音频CC。

|idx|触屏目标|当前音频CC／状态|
|---:|---|---|
|0|Macro 1|预留，不应用到音频|
|1|Macro 2|预留，不应用到音频|
|2|Macro 3|预留，不应用到音频|
|3|Macro 4|预留，不应用到音频|
|4|Master Level|CC48|
|5|OSC A Unison|预留，不应用到音频|
|6|OSC A Detune|CC22|
|7|OSC A Blend|预留，不应用到音频|
|8|OSC A Phase|CC87|
|9|OSC A Rand|CC88|
|10|OSC A WT Position|CC20|
|11|OSC A Warp Amount|CC39|
|12|OSC A Pan|预留，不应用到音频|
|13|OSC A Level|CC46|
|14|OSC B Unison|预留，不应用到音频|
|15|OSC B Detune|CC30|
|16|OSC B Blend|预留，不应用到音频|
|17|OSC B Phase|CC89|
|18|OSC B Rand|CC90|
|19|OSC B WT Position|CC28|
|20|OSC B Warp Amount|CC41|
|21|OSC B Pan|预留，不应用到音频|
|22|OSC B Level|CC47|
|23|Filter Cutoff|CC43|
|24|Filter Resonance|CC44|
|25|Filter Pan|预留，不应用到音频|
|26|Filter Drive|预留，不应用到音频|
|27|Filter Fat|预留，不应用到音频|
|28|Filter Mix|CC45|
|29|ENV1 Attack|预留，不应用到音频|
|30|ENV1 Hold|预留，不应用到音频|
|31|ENV1 Decay|预留，不应用到音频|
|32|ENV1 Sustain|预留，不应用到音频|
|33|ENV1 Release|预留，不应用到音频|
|34|Delay Feedback|CC53|
|35|Delay Left Time|CC52|
|36|Delay Right Time|预留，不应用到音频|
|37|Delay Filter Freq|预留，不应用到音频|
|38|Delay Filter Q|预留，不应用到音频|
|39|Delay Mix|CC54|
|40|Reverb Size|CC55|
|41|Reverb Decay|CC56|
|42|Reverb Low Cut|预留，不应用到音频|
|43|Reverb High Cut|预留，不应用到音频|
|44|Reverb Spin|预留，不应用到音频|
|45|Reverb Depth|预留，不应用到音频|
|46|Reverb Mix|CC57|
|47|EQ Low Freq|预留，不应用到音频|
|48|EQ Low Q|预留，不应用到音频|
|49|EQ Low Gain|预留，不应用到音频|
|50|EQ High Freq|预留，不应用到音频|
|51|EQ High Q|预留，不应用到音频|
|52|EQ High Gain|预留，不应用到音频|

现有Distortion/Chorus/Phaser静态CC继续有效；触屏53槽里没有对应目标，本版V2不为它们伪造槽号。
原src/filter_curve_lfo.v只保留用于历史单元回归，当前top不例化V1模块，旧ID16..46不会驱动当前LFO。

## 5. Phase与Rand

|静态参数|通道16 CC|范围与默认值|
|---|---:|---|
|OSC A Phase|87|0..127，默认0|
|OSC A Rand|88|0..127，默认0|
|OSC B Phase|89|0..127，默认0|
|OSC B Rand|90|0..127，默认0|

Phase对应phase_control/128周期：0=0度，32=90度，64=180度，127约357.19度。
Rand=0固定起音；1..126按rand/128缩放随机偏移；127使用全周期随机偏移。
公式为initial_phase=(Phase<<25)+floor(PRNG32*rand_scale/128)，按32位回绕。
两个调度器使用不同的固定非零xorshift32种子，Unison成员每次计算时推进随机状态。
这是可复现的伪随机起始相位，不是给每个采样增加随机相位。

新Note On时锁存Phase/Rand，分配给同一Note的所有成员使用一致参数、各自随机偏移；重复Note On重新起音。
修改这些参数（包括LFO调制）只影响后续触发，不重置正在发声的相位或包络；Note Off保持原相位继续Release。
调度器在原有Detune离线计算阶段并行计算起始相位，未增加振荡器数量或音频TDM流水拍数。
旧独立实例INITIAL_PHASE_ENABLE默认0保持旧行为，主top显式启用。

## 6. 触屏端需要同步的修改

1. 按本说明的14位打包增加6字节SysEx发送器、dirty字段队列与消息级仲裁；现有压缩包发送器仅发3字节CC。
2. 7节点、模式、每目标绑定写入后发ID126，曲线/模式编辑附对应ID72。
3. 新增静态Phase/Rand到CC87..90的映射；Warp Amount正确CC为39/41，而非21/29。
4. 统一三bank的预览相位、Once与速率界面（当前UI速率按钮只到档5）；保留目标的未实现提示。
5. 本机音频控制口为C19，不采用旧协作包的AB21或输入线逻辑合并方式。

触屏工程压缩包未在本次直接修改，以上是发送端联调契约。

## 7. 验证与剩余限制

- Python独立Fraction基函数参考与整数模型一致；协议符号位、全量字段和7位打包通过。
- ModelSim：64组曲线含阶梯，共24640个Q6值逐位通过；后台构表不污染前台。
- 53目标来源/深度/限幅、运行中base快照、未Commit不生效、全绑定、Once/Restart、非法-128通过。
- 完整MIDI顶层与双引擎容量回归通过，检查Phase固定起音、核心状态写入、Rand成员去相关及原有MIDI路径。
- 完整SD/DDR/音频层次检查通过，厂商IP用接口桩，仅证明连接和语法，不代表DDR或FIR真实功能已验证。
- 桌面GUI构建、七点编辑器、53目标分页、81帧首次同步与后续增量发送检查通过。
- 未运行综合布线，未烧录；BSRAM实际映射、资源、时序和听感仍需板级验证。平滑造成的声音相位滞后是现有控制路径的一部分。

复现实验命令（工程根目录）：

```powershell
python tools/test_lfo_curve.py
python tools/generate_lfo_v2_vectors.py
vsim -c -do "do sim/run_lfo_v2_test.do; quit -f"
python tools/test_lfo_v2_sender.py
vsim -c -do "do sim/run_top_midi_test.do; quit -f"
vsim -c -do "do sim/run_top_dual_unison8_test.do; quit -f"
vsim -c -do "do sim/run_full_top_elaboration.do"
```

参考向量只生成到tmp，不纳入版本控制；GUI发送测试使用假串口，不发送到板卡。
