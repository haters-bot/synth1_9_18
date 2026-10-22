# FPGA 三路三点通用 LFO 与调制矩阵

## 1. 总体结构

LFO 已经与滤波器 Cutoff 解耦。FPGA 内部结构为：

```text
上位机：3组速率/曲线、8条共享路由
                    │ SysEx，仅配置变化时发送
                    ▼
highres_parameter_parser
                    ▼
曲线与路由影子寄存器 ── Commit ──► 活动配置
                    ▼
3×curve_lfo_core：各自生成三点曲线，输出双极性Q1.13
                    ▼
lfo_modulation_router：8槽时分复用调制矩阵
                    ▼
各参数基础值 + LFO偏移 ── 限幅 ──► 振荡器与滤波器
```

上位机不再周期发送 Warp Amount 或 Cutoff。LFO 每个样本的计算和参数路由全部在 FPGA 中完成。

## 2. 三个控制点

第一版固定为三个点：

- `P0` 时间固定为 0，电平范围为 -1～+1；
- `P1` 时间可在 0.125～0.875 周期内移动，电平范围为 -1～+1；
- `P2` 时间固定为 1，电平范围为 -1～+1；
- `C0` 控制 P0 到 P1 的曲率；
- `C1` 控制 P1 到 P2 的曲率。

每段以三次 Smoothstep 为基础，并加入端点值和端点斜率都为 0 的曲率项：

```text
smooth = t² × (3 - 2t)
bump   = 3 × t² × (1 - t)²
weight = smooth - curve × bump
value  = start + (end - start) × weight
```

Python 编辑器和 FPGA 使用相同公式。启用和关闭时，LFO 总幅度在 512 个 96 kHz 样本内渐变，约为 5.33 ms，避免路由目标突然跳变。

## 3. 相位与速率

三个 LFO 各有独立的 24 位局部相位累加器。上位机根据每个 LFO 的速率和 P1 时间计算两个 14 位步进：

```text
step0 = round(rate_hz × 2^24 / (96000 × middle_time))
step1 = round(rate_hz × 2^24 / (96000 × (1 - middle_time)))
```

P1 时间限制为 0.125～0.875，当前速率范围为 0.1～10 Hz。

## 4. 路由槽位

共有 8 条路由，每条包含：

```text
Enable
Source：LFO 1、LFO 2 或 LFO 3
Destination
Depth：-127～+127
```

每条路由独立选择三个 LFO 之一。同一个 LFO 可以同时控制多个目标；多个槽位也可以指向同一目标，此时偏移相加后统一限幅。路由槽总数仍为 8，因此增加 LFO 数量不会增加每个样本的路由处理拍数。

| Destination | 编号 | 范围 | 说明 |
|---|---:|---:|---|
| None | 0 | - | 不产生调制 |
| OSC A WT Position | 1 | 0～127 | 对 Acid 多帧波表有效 |
| OSC A Warp Amount | 2 | 0～127 | 对当前 Warp 模式生效 |
| OSC A Level | 3 | 0～127 | 进入现有增益平滑路径 |
| OSC B WT Position | 4 | 0～127 | 对 Acid 多帧波表有效 |
| OSC B Warp Amount | 5 | 0～127 | 对当前 Warp 模式生效 |
| OSC B Level | 6 | 0～127 | 进入现有增益平滑路径 |
| Pan | 7 | 0～127 | 路由已保留，当前单声道输出听不到变化 |
| Filter Cutoff | 8 | Q7.8 的 0～127 | 保留小数精度 |
| Filter Resonance | 9 | 0～127 | 进入现有平滑路径 |
| Filter Mix | 10 | 0～127 | 进入现有平滑路径 |

基础值仍由原 MIDI CC 控制。路由只在基础值上增加有符号偏移：

```text
result = saturate(base + lfo_q13 × depth_q13)
```

当目标为 Filter Cutoff 且当前模式为 Comb+ 或 Comb- 时，偏移继续乘以 `141/256`，使最大实际深度约为 70。

## 5. SysEx 配置协议

每个字段使用六字节非商业 SysEx 帧：

```text
F0 7D parameter_id value_msb value_lsb F7
```

### LFO 1 曲线字段

| ID | 字段 | 编码 |
|---:|---|---|
| 16 | Enable | 0 或 1 |
| 17 | Segment 0 phase step | 14 位整数 |
| 18 | Segment 1 phase step | 14 位整数 |
| 19 | 保留 | 当前忽略 |
| 20 | P0 level | 双极性 Q1.13 Offset Binary |
| 21 | P1 level | 双极性 Q1.13 Offset Binary |
| 22 | P2 level | 双极性 Q1.13 Offset Binary |
| 23 | C0 | 双极性 Q1.13 Offset Binary |
| 24 | C1 | 双极性 Q1.13 Offset Binary |
| 25 | Commit | 数值忽略 |

### LFO 2 与 LFO 3 曲线字段

| LFO | Enable | Step 0 | Step 1 | P0 | P1 | P2 | C0 | C1 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| LFO 2 | 31 | 32 | 33 | 34 | 35 | 36 | 37 | 38 |
| LFO 3 | 39 | 40 | 41 | 42 | 43 | 44 | 45 | 46 |

三个 LFO 共用 ID 25 作为 Commit。发送一次 Commit 后，三组曲线和全部路由在同一系统时钟沿切换到新配置。

### 路由字段

| ID | 字段 | 编码 |
|---:|---|---|
| 26 | Route Index | 0～7 |
| 27 | Route Enable | 0 或 1 |
| 28 | Destination | 0～10 |
| 29 | Route Depth | 双极性 Q1.13 Offset Binary |
| 30 | Route Source | 0=LFO 1，1=LFO 2，2=LFO 3 |

配置一条路由时，先写 ID 26 选择槽位，再写 ID 27～30。全部三组曲线和路由写完后发送一次 ID 25；曲线核心和路由矩阵在同一时钟沿提交活动配置。

双极性编码为：

```text
encoded = round((normalized + 1) × 8191.5)
```

上位机显示的 Depth `-127～+127` 会先归一化为 `-1～+1` 再使用该编码。

## 6. 时序预算

- 曲线计算使用 6 级 50 MHz 流水线，约 120 ns；
- 路由器使用 1 拍装载、8 拍处理、1 拍提交，共 10 拍，即约 200 ns；
- 一个 96 kHz 样本周期约有 521 个 50 MHz 时钟；
- 路由计算使用的时间不到周期预算的 2%；
- `route_overrun` 会记录新 LFO 样本在上一轮路由结束前到达的异常，正常配置下应始终为 0。

## 7. 当前边界

- Detune/Pitch 尚未接入。当前 Detune 只在 Note On 分配任务时参与相位步进计算；实时颤音需要单独的 phase-step 调制通路。
- Unison、Waveform、Warp Mode 和 Filter Mode 是离散或结构参数，不接受连续 LFO。
- Pan 路由已经生成控制值，但当前 I2S 链路仍复制单声道样本，因此尚无可听效果。
- 第一版提供 3 个独立 LFO 源和 8 条共享路由；三个 LFO 可设置不同速率、控制点和曲率。
- Detune 按本阶段约定暂不加入目标列表。
