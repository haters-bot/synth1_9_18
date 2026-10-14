# 双振荡器时序收敛记录

## 修改前基线

- 系统时钟：50 MHz，周期20 ns
- 布局耗时：3分38秒
- 布线耗时：19分38秒
- 总耗时：23分31秒
- 实际最高频率：42.789 MHz
- 最差建立时间余量：-3.370 ns
- 建立时间违例端点：4102
- TNS：-5863.293 ns

主要关键路径分为三类：

1. 32槽位活动状态统计经过归一化增益和乘法后到达顶层混音；
2. `pending_note`经过频率查表和Detune运算后直接写入槽位相位步进；
3. ADSR控制值经过参数映射和包络运算后直接写入每槽包络状态。

## 本轮RTL修改

1. 调度器使用事件增量维护活动任务数，移除每拍对32个`slot_active`的组合计数；
2. 频率查表结果先锁存，下一拍再参与Detune和槽位写入；
3. Bank在每个768 kHz批次开始时锁存活动任务数；
4. TDM核心在每批开始时锁存ADSR参数；
5. 顶层先寄存两路振荡器增益乘法结果，下一拍再求和、饱和并送入FIR。

模块端口、MIDI协议、32槽位数量、768 kHz内部采样率和96 kHz输出采样率均未改变。
顶层混音到FIR输入增加一个50 MHz时钟周期，即20 ns延迟。

## RTL回归结果

以下ModelSim测试全部通过，编译为0错误、0警告：

- `run_task_scheduler_test.do`
- `run_tdm_test.do`
- `run_adsr_control_test.do`
- `run_top_midi_test.do`
- `run_i2s_tx_test.do`
- `run_acid_wavetable_test.do`

## 下一次高云EDA验证

第一次验证本轮修改时执行完整综合和布局布线，并确认两个GAO配置保持禁用，避免旧调试核进入正式时序结果。记录以下数据：

- Total Placement
- Total Routing
- Actual Fmax
- WNS和TNS
- Setup/Hold违例端点数
- `PR1014`时钟通用布线警告是否仍存在

验收条件：

- 50 MHz建立和保持时间违例均为0；
- Actual Fmax高于50 MHz，建议至少保留10%的余量；
- 768 kHz调度无`oscillator_schedule_overrun`；
- FIR无`fir_input_overrun`。

在一次完整布局布线通过后，日常小改动可启用Incremental Place & Route缩短迭代时间；改变时钟、振荡器数量、RAM结构或大范围数据通路后重新执行完整布局布线。

