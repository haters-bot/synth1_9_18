# 时分复用 ADSR 包络

当前实现为 32 个逻辑声部保存独立状态，但共享一套包络更新和乘法数据路径。

## 默认参数

- 内部音频采样率：约 `768 kHz`
- 包络更新分频：`16`
- 包络控制率：约 `48 kHz`
- 包络格式：16 位无符号 `Q0.16`
- Attack 步长：`137`，约 `10 ms`
- Decay 步长：`4`，从满幅到 70% 约 `102 ms`
- Sustain：`45875 / 65535`，约 `70%`
- Release：指数曲线，每次更新减去当前电平的 `1/4096`
- Release 结束阈值：`1024 / 65535`，约 `-36 dB`
- 从 Sustain 电平衰减到结束阈值：约 `315 ms`

指数 Release 的实际时间取决于 Note Off 时的当前电平；如果在 Attack
早期松键，Release 会相应缩短。指数曲线在听感上比线性幅度下降更均匀，
结束阈值用于避免低电平整数长尾。

## 每声部状态

每个槽位保存：

- `phase_state`
- `note_state`
- `enable_state`
- `gate_state`
- `envelope_stage`
- `envelope_level`

`envelope_stage` 编码：

- `0`：IDLE
- `1`：ATTACK
- `2`：DECAY
- `3`：SUSTAIN
- `4`：RELEASE

Note On 会启用振荡器、将包络清零并进入 Attack。Note Off 只关闭 Gate 并进入
Release，不会立即停用振荡器。Release 归零后，振荡器核心通过
`voice_idle_mask` 通知 MIDI 声部分配器释放对应槽位。

## 定点数据路径

每个槽位的波形样本先乘以当前包络：

```text
signed PCM16（符号扩展为17位）× unsigned Q0.16（扩展为正17位）
→ signed 34 bit → >>> 16 → PCM16
```

包络乘积在右移前增加半个 Q0.16 LSB；Bank 在 `/32` 右移前同样增加半个
输出 LSB。这两处舍入用于避免直接算术截断造成负半波偏置和低电平谐波。
舍入加法均先扩展位宽，以免边界值在加常数时溢出。之后数据进入声部累加和
Bank 输出缩放，乘法器由所有声部时分复用。

## 当前限制

- MIDI velocity 已被解析，但尚未参与声部增益。
- 同音重触发和偷音会从零重新开始 Attack，可能产生轻微不连续。
- 修改包络乘法路径后必须重新检查综合资源映射和 `50 MHz` 时序；源码检查
  不等同于布局布线时序验证。
