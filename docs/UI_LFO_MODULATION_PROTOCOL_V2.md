# UI LFO 调制模型与传输协议 V2（以 UI 端模型为准）

Status: 协议草案 v2.0，2026-10-25 由 ZCode 按用户决策整理。音频端 Agent 按本文档改造 `curve_lfo_core` / `lfo_modulation_router` / SysEx 解析；UI 端发送器由 UI 侧后续实现。本文档取代 `docs/lfo_curve_control.md` 的三点/两段曲率模型；旧 ID 16–46 段在 V2 落地后由音频端决定是否保留兼容解析。

## 0. 架构原则（用户明确决策，不可违背）

**UI 板 = 展示端 + 控制端；音频板 = 合成端。两边严格分工：**

1. UI 板对 LFO 调制效果**只做视觉预览**（`modulation_preview.v`，53 目标轮询渲染，仅供屏幕显示）。
2. UI 板对外**永远发送静态值**：用户调好的基础参数照旧走 Phase 1 CC 表（CH16 `0xBF`），**绝不发送"已算好调制量的值"**。
3. LFO 界面的完整配置（曲线点、速率、模式、路由、深度）打包成 SysEx 发给音频板。
4. 音频板拿"CC 静态基础值 + LFO 配置"，**在音频引擎内自己完成调制计算**，算法与 UI 预览完全一致（第 3、4 节），保证"看到的 = 听到的"。
5. UI 端调制公式只作用于 0..127 的 CC 参数域，调制后再进入音频端现有的 CC→物理值映射与平滑路径。

## 1. UI 端数据模型（精确定义）

来源：`2_ui_touch_hub/rtl/ui_vector_engine/lfo_editor_state.v`、`lfo_binding_state.v`、`mod_targets.vh`。

### 1.1 LFO 源（3 个 bank）

每个 LFO bank 包含：

| 字段 | 位宽 | 含义 |
|---|---|---|
| `points[0..6]` | 7×7 bit | 7 个节点幅度，每个 0..127。**时间位置固定等距**：一个周期 384 相位档，节点 n 位于相位 n×64（n=0..6，节点 6 对应周期末端） |
| `rate` | 3 bit | 速率档位 r=0..7，频率 = **0.25 × 2^r Hz**，即 0.25 / 0.5 / 1 / 2 / 4 / 8 / 16 / 32 Hz |
| `once` | 1 bit | 单次模式：播完一个周期停在末端（phase 停在 383），不循环 |
| `stepped` | 1 bit | 阶梯模式：不做平滑插值，输出当前段的节点常数值 |

UI 内置预设（`preset_point`）：预设 0 = 三角状 `0,42,85,127,85,42,0`；预设 1 = 线性斜坡 `0,21,42,64,85,106,127`；预设 2 = 方波 `127,127,127,0,0,0,0`（同时置 stepped=1）；预设 3 = 用户自定义。

**相位重置规则**：UI 在该 bank 的任何编辑动作（改点、换预设、换速率、切 tab）时把该 bank 的 phase 清零并重新运行。协议第 2.4 节的"相位同步帧"把这一事件告知音频端，保证视听同步。

### 1.2 调制目标与路由（53 槽，UI 语义）

UI 侧每个可调旋钮都是一个潜在调制目标，共 **53 个**（`mod_targets.vh` 的 `mod_id` 数组）。每个目标独立存储：

| 字段 | 位宽 | 含义 |
|---|---|---|
| `source` | 2 bit | 0=无调制，1=LFO1，2=LFO2，3=LFO3 |
| `depth` | 8 bit **signed**（二补码） | −127..+127 |

**这是"每目标一路由"的语义**（不是音频端现行的 8 条共享路由槽）：一个 LFO 可同时调制多个目标；同一时刻每个目标只绑一个 LFO 源（UI 的 BIND 交互一次绑一个目标）。

53 个目标（idx = 路由槽号，UI_ID 见 `params.vh`）及其在音频端的映射：

| idx | UI_ID(hex) | 参数（UI 名称） | 音频 Destination | 对应 CC | V2 当前是否生效 |
|---:|---:|---|---|---:|---|
| 0–3 | 0x01–0x04 | Macro 1–4 | — | — | 暂无对应（宏路由未实现） |
| 4 | 0x05 | Master Volume | — | 48 | 可生效（音频 Master Level） |
| 5 | 0x13 | OSC A Unison | — | 23 | 暂不（离散量） |
| 6 | 0x14 | OSC A Detune | — | 22 | 暂不（需 phase-step 通路，见 §6） |
| 7 | 0x15 | OSC A Blend | — | — | 暂无对应 |
| 8 | 0x16 | OSC A Phase | — | — | 暂无对应 |
| 9 | 0x1B | OSC A Rand | — | — | 暂无对应 |
| 10 | 0x17 | OSC A WT Position | 1 | 20 | **生效** |
| 11 | 0x18 | OSC A Warp Amount | 2 | 21 | **生效** |
| 12 | 0x19 | OSC A Pan | 7 | — | 生效但单声道无听感 |
| 13 | 0x1A | OSC A Level | 3 | 46 | **生效** |
| 14 | 0x23 | OSC B Unison | — | 31 | 暂不（离散量） |
| 15 | 0x24 | OSC B Detune | — | 30 | 暂不（同上） |
| 16 | 0x25 | OSC B Blend | — | — | 暂无对应 |
| 17 | 0x26 | OSC B Phase | — | — | 暂无对应 |
| 18 | 0x2B | OSC B Rand | — | — | 暂无对应 |
| 19 | 0x27 | OSC B WT Position | 4 | 28 | **生效** |
| 20 | 0x28 | OSC B Warp Amount | 5 | 29 | **生效** |
| 21 | 0x29 | OSC B Pan | 7 | — | 生效但单声道无听感 |
| 22 | 0x2A | OSC B Level | 6 | 47 | **生效** |
| 23 | 0x30 | Filter Cutoff | 8 | 43 | **生效** |
| 24 | 0x31 | Filter Resonance | 9 | 44 | **生效** |
| 25 | 0x32 | Filter Pan | 7 | — | 生效但单声道无听感 |
| 26 | 0x33 | Filter Drive | — | — | 暂无对应 |
| 27 | 0x34 | Filter Fat | — | — | 暂无对应 |
| 28 | 0x35 | Filter Mix | 10 | 45 | **生效** |
| 29–33 | 0x40–0x44 | ENV1 A/H/D/S/R | — | 24–27(A/D/S/R) | 暂无对应（Hold 除外均无 CC 外发） |
| 34–52 | 0x60–0x72 | FX 面板旋钮（`fx_controls.vh` 动态 ID = 0x60+k：Delay/Reverb/Chorus 等三组 FX 参数矩阵） | — | 52–68 | 后续按音频 FX CC 表（CC52–68）逐步映射 |

（**换算说明**：`mod_targets.vh` 的 `mod_id` 输出是十进制编号，与 `params.vh` 十六进制 ID 的对应如上表；权威来源为 `mod_targets.vh` 的 `mod_id` 函数与 `fx_controls.vh` 的 `8'h60+k`。"音频 Destination"沿用 `docs/lfo_curve_control.md` §4 编号 1–10。）

**UI 全量下发 53 槽路由；音频端只应用自己有对应 Destination 的槽，其余忽略（保留语义，未来扩展不用改协议）。**

## 2. SysEx 传输协议（V2 帧与 ID 分配）

沿用音频端现有 6 字节帧格式（MIDI 通道外系统消息）：

```text
F0 7D <parameter_id> <value_msb> <value_lsb> F7
```

`parameter_id` 8bit；`value` 16bit 大端（msb 在前）。**新 ID 段 48–126，与旧段 16–46 无冲突。**

### 2.1 曲线点（ID 48–68）

```text
ID = 48 + bank×7 + n        bank=0..2, n=0..6
value = 节点幅度 0..127
```

### 2.2 bank 模式字（ID 69–71）

```text
ID = 69 + bank
value = rate(3bit) | stepped<<3 | once<<4      // value = 0..31
```

### 2.3 路由（ID 73–125）

```text
ID = 73 + idx                idx=0..52（对应 §1.2 表）
value = (source<<8) | (depth & 0xFF)
       source: 0..3；depth: 8bit 二补码
       source=0 表示该目标无调制（音频端清除该目标偏移）
```

### 2.4 相位同步帧（ID 72）

```text
ID = 72
value = bank(0..2) | (0x0004)      // bit2=1 表示重启请求
```

UI 在某 bank 发生编辑性相位重置时发送；音频端收到后将该 bank 相位累加器清零（once 模式重新从 0 播放）。若音频端实现自己的相位连续性策略，此帧至少用于 once 模式重触发。

### 2.5 原子提交（ID 126）

```text
ID = 126
value 忽略（发 0）
```

与音频端现有 ID25 Commit 同一机制：影子寄存器整组写入，Commit 后在同一时钟沿切换活动配置，防止半更新被听到。**UI 发送顺序：先全部变化字段，最后一条 Commit。**

### 2.6 发送时机与带宽

- 仅在配置变化时发送（松手/预设切换/绑定提交时一次），运行期零流量；不占用 31250 baud 链路带宽。
- 全量同步（上电或首次连接）：21+3+1+53+1 = 79 帧 × 约 2.2 ms ≈ 175 ms，一次性可接受。
- UI 侧使用 dirty 队列：同一 ID 只保留最新值；Note On/Off 与普通 CC 优先于 SysEx。
- 每帧完整 6 字节，不依赖 Running Status。

## 3. 曲线生成算法（音频端必须逐位复刻）

来源：`2_ui_touch_hub/rtl/ui_vector_engine/lfo_smooth_table.v`（C1 单调三次 Hermite 插值 + minmod 切线，非 Serum 专有数学）。UI 端把 7 节点展开成 384 档查找表（Q7.6，13bit，0..8128）；**音频端建议同样实现 384×13bit×3 的 BRAM 表，节点变化时重建（385 拍），每音频样本仅查表**。

### 3.1 数学定义

相位 p ∈ [0,384)，段 s = floor(p/64) ∈ [0,5]，段内归一化坐标 t = (p − 64s)/64 ∈ [0,1)。节点 y[s]（s=0..6，y 值 0..127）。割线斜率：

```text
dm = y[s+1] − y[s]                    （本段）
dl = y[s]   − y[s−1]                  （左段；s=0 时切线置 0）
dr = y[s+2] − y[s+1]                  （右段；s=5 时切线置 0）
```

minmod 切线（防止过冲振荡，保证单调段不过冲）：

```text
minmod(a,b) = 0                         若 a=0 或 b=0 或 sign(a)≠sign(b)
            = sign(a)·min(|a|,|b|)       否则

m0 = (s=0) ? 0 : minmod(dl, dm)         左端点切线
m1 = (s=5) ? 0 : minmod(dm, dr)         右端点切线
```

三次 Hermite（t∈[0,1]）：

```text
c1 = m0
c2 = 3·dm − 2·m0 − m1
c3 = −2·dm + m0 + m1
y(p) = y[s] + c1·t + c2·t² + c3·t³
```

输出钳位到 [0,127]（定点表为 Q6：`round(y×64)` 钳位 [0,8128]）。

`stepped=1` 时跳过插值：`y(p) = y[s]`（阶梯保持）。

### 3.2 定点实现参考（UI RTL 的位宽约定，建议直接照抄）

- 切线/割线：8bit signed（范围 −127..127）。
- 系数：c1 8bit；c2、c3 11bit signed（`c2 = 3·dm − 2·m0 − m1`，`c3 = −2·dm + m0 + m1`）。
- Horner 三级流水（t 用 6bit 定点 0..64，`t6 = p mod 64`）：
  - `h1 = c3·t6 + (c2 << 6)`
  - `h2 = h1·t6 + (c1 << 12)`
  - `h3 = (h2·t6 + (y[s] << 18)) >>> 12` → Q7.6
- 中间量保留精度，仅最终结果截断并钳位 [0, 8128]。
- 特例：p=384（表末项）取 `y[6]<<6`。

### 3.3 Python golden model（一致性验证用）

```python
def ui_lfo_value(points, phase, stepped=False):
    # points: 7 ints 0..127; phase: int 0..383
    s = min(phase // 64, 5)
    y = points[s]
    if stepped:
        return y
    def minmod(a, b):
        if a == 0 or b == 0 or (a < 0) != (b < 0):
            return 0
        return a if abs(a) < abs(b) else b
    dm = points[s+1] - points[s]
    dl = points[s] - points[s-1] if s > 0 else None
    dr = points[s+2] - points[s+1] if s < 5 else None
    m0 = 0 if s == 0 else minmod(dl, dm)
    m1 = 0 if s == 5 else minmod(dm, dr)
    t = (phase - 64 * s) / 64.0
    c1, c2, c3 = m0, 3*dm - 2*m0 - m1, -2*dm + m0 + m1
    v = y + c1*t + c2*t*t + c3*t*t*t
    return max(0, min(127, round(v)))
```

音频端 RTL 落地后，用同一 `points`/`phase` 与本函数逐点对比（384 点全扫），最大误差 ≤ 1 LSB（Q6 截断差异）即视为一致。

## 4. 调制公式（音频端每样本执行）

对每个**音频端已实现的目标**（§1.2 表）：

```text
wave = lfo_wave[source]            # 0..127（查表值 >>6，单极性）
base = 该目标当前 CC 基础值         # 0..127，来自 CC 链路（静态）
modulated = clamp( base + ((depth_signed × wave) >> 7), 0, 127 )
```

- `depth_signed` 为 −127..+127；`>>7` 为**算术右移**（保留符号）。
- 调制结果钳位后**进入音频端现有的 CC→物理值映射与平滑路径**（如 Cutoff 的 Q7.8 与 5.33 ms 平滑、Mix 模式切换保护等），后处理链一律不动。
- **废弃旧模型的差异项**：双极性 Q1.13 偏移加法（`base + lfo_q13×depth_q13`）与 Comb 模式 141/256 深度缩放不再使用；V2 统一为上式（与 UI 预览 `modulation_preview.v` 第 58–60 行逐位一致）。
- `source=0` 的目标直接输出 base（无偏移）。
- 路由计算预算：音频端现有路由器 10 拍（8 槽）；V2 最多 53 槽 ≈ 55 拍，仍在每样本 521 个 50 MHz 拍的预算内（<11%），可继续时分复用单乘法器。

## 5. 相位与速率模型（音频端 96 kHz 域）

UI 预览在 50 MHz 用整数相位步进（`PREVIEW_BASE_TICKS=50e6/(384×0.25)`）；音频端改用**连续相位累加器**，周期仍是 384 档：

```text
rate_hz = 0.25 × 2^r                r = 0..7（UI 下发 r，不下发 Hz）
phase_inc = rate_hz × 384 / 96000   每样本累加（建议 24bit 定点累加器，
                                    index = acc[23:15] 即高 9bit 对 384 取档）
once：index 到 383 后停（累加器冻结），等待 ID72 重启帧
```

相位档进入 §3.1 的 384 档表查值。两板相位不必逐样本对齐（视觉预览与音频在毫秒级同步即可，人耳/眼无感）；ID72 重启帧用于编辑时避免突变。

## 6. 音频端改造清单（按依赖顺序）

1. **SysEx 解析扩展**：`highres_parameter_parser` 增加 ID 48–126 段解码与影子寄存器（含 53 槽路由数组），ID126 Commit 整组切换；旧 ID16–46 是否保留由音频端定（建议保留一个开关，方便回退）。
2. **替换曲线核**：3×`curve_lfo_core`（三点/smoothstep/bump）→ 3×"7 点 Hermite+minmod 384 档表"（§3.2，可整体移植 `lfo_smooth_table.v` 的展开逻辑，节点变化时 385 拍重建 BRAM 表）。
3. **速率/相位**：24bit 累加器 + `0.25×2^r`（§5），once 模式冻结。
4. **路由器扩槽**：8 槽 → 53 槽（每槽 source 2bit + depth 8bit signed，时分复用），输出公式换 §4；旧 Destination 编号 1–10 语义不变。
5. **目标应用点**：调制钳位发生在 CC 域 0..127，再走现有映射/平滑（Comb 缩放等旧偏移路径删除）。
6. **验证**：§3.3 golden model 384 点全扫对比；板上听感：三角 LFO 全深度调制 Cutoff，应与 UI 预览曲线同步起伏。
7. **暂不实现项**（协议已预留，UI 会照发但音频端忽略）：Detune 实时调制（需独立 phase-step 调制通路）、离散量目标（Unison/Waveform/Filter Mode）、ENV/FX 目标扩展。

## 7. UI 端待实现清单（UI 侧后续工作，不属于本文档接收方）

1. `midi_uart_tx`/`param_merger` 增加 SysEx 6 字节帧发送与 dirty 队列（Note/CC 优先）。
2. 绑定提交、预设切换、速率/once/stepped 变化处触发对应 ID 帧 + Commit；编辑性重置处发 ID72。
3. 上电全量同步（79 帧）。
4. UI 本地预览逻辑不变（`modulation_preview.v` 已按 §4 公式渲染）。

## 8. 变更记录

- 2026-10-25 v2.0：ZCode 依用户决策（展示端/合成端分离、静态值+配置传输、调制在音频板完成）从 UI RTL 提炼成文，替代三点/两段曲率模型。
