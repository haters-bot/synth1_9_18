# 32槽位振荡器TDM验证

## 配置

- `ENGINE_COUNT = 1`
- `SLOTS_PER_ENGINE = 32`
- `sys_clk = 50 MHz`
- `start_tick = 768 kHz`
- 调度回归槽位音符：MIDI 48～79
- 实际顶层槽位音符：由USB-UART MIDI输入动态配置

## 模块职责

`oscillator_tdm_core` 负责调度器，以及32个逻辑振荡器槽位各自独立的音符、
使能和相位状态。
该模块仅包含一个 `freq_lut`、一个相位加法器和一个 `sine_lut`。

`oscillator_tdm_bank` 同时启动所有核心，将各核心的部分和相加并对结果进行归一化，
然后把 `sample_out` 和 `sample_valid` 送入FIR封装模块。

## 调度器时序

| 上升沿 | 操作 | 上升沿后的可观察结果 |
|---|---|---|
| N | 接受 `start_tick` | `busy=1` |
| N+1 | 提交槽位0 | `debug_slot_commit=1`，`debug_slot=0` |
| N+2 | 提交槽位1 | `debug_slot_commit=1`，`debug_slot=1` |
| N+3～N+31 | 依次提交槽位2～30 | `debug_slot` 依次为2～30 |
| N+32 | 提交槽位31并锁存核心求和结果 | `partial_valid=1`，`busy=0` |
| N+33 | 引擎组锁存核心求和结果并进行缩放 | `sample_valid=1` |
| N+34 | FIR封装模块读取寄存后的采样值 | `in_valid=1` 在该上升沿前已经稳定 |

从启动到 `sample_valid`，完整调度需要33个时钟周期。在50 MHz时钟下对应660 ns。
相邻两个768 kHz时序脉冲之间约为1.302 us，因此当前验证配置仍有约642 ns的空闲时间。

## 单槽位状态更新接口

外部控制器每拍最多更新一个逻辑振荡器槽位：

```verilog
voice_update_valid
voice_update_slot[7:0]
voice_update_note[6:0]
voice_update_enable
voice_update_phase_reset
```

当 `voice_update_valid=1` 时，Bank根据全局槽位编号选择对应的物理引擎，
Core在该时钟沿更新指定槽位的音符和使能状态。若
`voice_update_phase_reset=1`，该槽位的相位同时清零。

当前顶层复位后保持全部槽位关闭。`midi_voice_allocator`收到Note On后，
通过该接口启用一个槽位；收到Note Off后关闭保存对应音符的槽位：

```verilog
Note On  -> voice_update_enable=1, voice_update_phase_reset=1
Note Off -> voice_update_enable=0, voice_update_phase_reset=0
```

768 kHz调度始终保持运行；没有启用槽位时混音结果为零。MIDI更新与调度发生在同一个
50 MHz时钟域，不需要CDC结构。若更新与当前槽位提交发生在同一拍，配置写入优先，
最迟在下一个内部采样周期体现完整状态变化。

## 相位状态

每个槽位都有自己的 `note_state[slot]`、`enable_state[slot]` 和
`phase_state[slot]`。提交一个槽位时执行：

```text
sample             = sine_lut(phase_state[slot][31:24])
phase_state[slot]  = phase_state[slot] + phase_step(note[slot])
mix_accumulator   += sample
```

改变 `slot_index` 会选择另一个保存的相位状态，32个音符并不会共用同一个相位累加器。

## 错误状态显示

`schedule_overrun` 是粘滞标志。如果核心仍处于忙碌状态时又收到新的 `start_tick`，
该标志就会置为1，并一直保持到复位。这样可以直接观察到新的内部音频采样请求被丢弃，
避免错误无声发生。

## 运行仿真

从工程根目录打开ModelSim并执行：

```tcl
do sim/run_tdm_test.do
```

该脚本只编译TDM振荡器的测试边界，把调度器信号添加到波形窗口，
然后运行带自检功能的测试平台。检查内容包括：

- 禁用的槽位产生零值采样；
- 单槽位接口能够正确写入32个音符和使能状态；
- 槽位提交顺序始终为0～31；
- 32个相位状态均能递增，且相邻槽位的相位状态互不相同；
- 32个逻辑振荡器最终产生非零的混合采样；
- 每个被接受的 `start_tick` 对应产生一次 `sample_valid`；
- 以约65个50 MHz时钟为周期发起请求时不会产生意外的调度超时；
- 相互重叠的 `start_tick` 脉冲会置位粘滞溢出标志。

USB-UART、MIDI解析、槽位分配和顶层连接使用另一组自检：

```tcl
do sim/run_top_midi_test.do
```

该测试发送真实的8N1串行波形，覆盖Note On、Note Off、Running Status、
插入式MIDI Clock、`Note On velocity=0`以及88键范围过滤。

## 当前验证范围与限制

- 为方便观察，相位状态目前保存在寄存器中，尚未映射到BSRAM。
- 音符与使能状态目前也保存在Core内部寄存器数组中。
- 全局槽位编号当前为8位，因此最多表示256个逻辑槽位。
- 振荡器使用最近邻波表查找，尚未进行插值。
- 当前测试包含32个槽位，因此增益归一化采用固定右移五位。
- 该测试直接观察Core内部的 `phase_state` 数组，只用于验证，不会进入综合工程。
- 当前导出了引擎0的调试信号。增加 `ENGINE_COUNT` 后，还需要加入多引擎调试信号的汇总逻辑。

## 验证记录

已于2026-09-27使用ModelSim SE-64 10.6d完成验证：

- 调度器RTL和测试平台编译结果：0个错误，0个警告。
- 自检仿真结果：`PASS: 32-slot updates, scheduler, phase state, and timing`。
- 上板逻辑分析确认槽位顺序为0～31，且相邻内部采样周期的同一槽位满足
  `新相位 = 旧相位 + phase_step`，未检测到调度超时。
- 使用仅供仿真的FIR端口桩模块完成顶层RTL编译和展开：0个错误，0个警告。
- 当前ModelSim版本无法解密高云Advanced FIR生成的加密源文件。FIR算法验证仍由生成的
  高云IP流程完成；该桩模块只用于检查FIR外围端口连接。
