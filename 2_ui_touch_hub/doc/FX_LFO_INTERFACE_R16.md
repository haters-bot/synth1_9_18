# R16 FX / LFO 逻辑接口（供三人接入讨论）

这是一份本项目实现的接口，不是三人已共同确认的线上协议。FX和LFO新增配置未发送到现有MIDI口，不声称已经改变声音。音频侧仍按实际协议单独接入；旧MIDI映射差异见 TEAM_INTEGRATION_2026-10-17.md。

## 操作

- ENV五旋钮中心X=64/130/196/262/328，Y=652；曲线时间长度缩为原来的一半，参数值域不变。FILTER与上排OSC坐标不变。
- 中央三栏依次DELAY、REVERB、EQ，参数拖动采用横向右增、纵向上增；首次按下不跳值。标题处开关每次接触只动作一次。
- LFO先选择1/2/3，再点BIND LFO，按住图内拖动整条曲线。缩略图跟随手指，目标显示白色候选外环。松手后提交，BIND自动退出；无效落点取消。若 HID 路径没有明确 UP，最后报文后静默500 ms按松手处理，保存最后有效目标；停顿超过500 ms同样结束手势。也可点BIND后直接点目标，按下即绑定并捕获该次接触，避免同时改变基础值。
- 上述 500 ms 仅适用于已开始的曲线分配拖动；普通接触、BIND/AMOUNT 按钮及点击绑定的残留接触按 50 ms 静默释放。BIND 后从按钮直接进入图内可开始拖动，不依赖按钮 UP；armed 模式可再次点 BIND 取消。修复与部署状态见 `R16_BIND_CONTACT_FIX_2026-10-19.md`。
- 每个目标目前绑定一个LFO，一组LFO可以绑定多个目标；再次绑定会替换该目标来源。持续彩色外环及L1/L2/L3标记表明已绑定，白色小指示表示动态值。
- 点一个已绑定目标，再用LFO底部AMOUNT的−/＋调整带符号深度，CLEAR解除。新绑定默认+64，范围−127..+127，步进8并在端点饱和。
- 参数基础值与调制预览值独立。预览公式：`clamp(base + floor(depth * waveform / 128), 0, 127)`，waveform=0..127。负深度向下调制。当前为单极性方案，未来如需双极性/多源叠加应扩展协议。
- FILTER CUTOFF/RES、OSC A/B WT POS、ENV A/H/D/S/R 曲线与旋钮共用有效预览值；它们都是 UI 示意，非实测音频。ENV 白点命中使用有效值，实际拖动保持按下时基础值的相对编辑，不把调制写回基础库。详见 `R16_SCOPE_MODULATION_FIX_2026-10-19.md`，其部署状态单独记录。
- 曲线首尾节点独立，未强制循环连续；不同首尾值会在回绕时跳变。不能把段内C1平滑等同于跨周期连续或无爆音。
- FREE/ONCE仍是手动本地预览模式，没有来自音频Note On的触发。本轮未接入音符事件，不伪装成按键同步。非当前页LFO的视觉预览独立循环；实际音频触发与同步交由音频适配层定义。

## 上游旋钮的逻辑入口

`ui_top_renderer.external_param_valid / external_param_id[7:0] / external_param_value[6:0]`：同像素时钟域，一拍valid，绝对参数值0..127。仅当状态机未捕获同一旋钮拖动时接收该参数；其他参数照常更新。外部按键使用绝对0/1，避免重复包引发重复翻转。

现有SPI仍是4位channel+12位ADC草案，16个通道没有自动扩成19个FX参数；顶层将其已解码事件接至逻辑入口，但FX新ID必须由队友新增已约定的协议适配器产生。异步物理接口须先通过同步器/FIFO，不可直接连valid跨时钟。

### 控制流水与仲裁（2026-10-19）

旧参数库 `param_merger` 的 SPI、相对触摸、曲线事务和按钮事件现在整体寄存一拍后仲裁，同一输入拍的各路优先级保持为按钮 > SPI > 触摸，曲线待处理事务保留原有逻辑。valid、ID、值和页签等元数据一起延迟，支持连续每拍事件；状态与 MIDI 请求比旧入口晚一拍。`midi_tx_busy` 保持为当前拍的实际背压，不能跟着事件延迟。`sim/tb_param_merger.v` 检查连续不同 ID/值配对、无重复和同拍仲裁；`tb_curve_touch_editor.v` 检查实际 UART 与曲线/外部输入合并。

FX在输入采样后增加一级报文/命中寄存，下一时钟沿提交状态；外部valid、ID和值也经过同一级，保持同一输入时钟沿与触摸的相对优先级。连续每拍有效的报文均可接收。按下捕获此前基础值，已经捕获的同一目标在松手报文提交当拍仍拒绝外部抢占；此后恢复外部更新。

LFO绑定采用两级译码：并行目标命中寄存，再编码目标并对齐报文标志，下一拍提交状态。LFO来源在曲线按下报文输入时锁存页签，不能被随后切页改写。BIND/工具按下尚在译码流水时也预先占用手势，避免紧随的曲线报文提前进入其他编辑器。`sim/tb_fx_lfo_routing.v` 覆盖无间隔BIND/松手/曲线/目标/松手、页签元数据变化、连续FX拖拽及同拍外部仲裁。

渲染器入口为背景及九个图层分别寄存局部光栅坐标，避免跨面板高扇出。总像素/HSYNC/VSYNC/DEN 延迟为七拍，HUD 选中 ID 在入口单独寄存；控制事件延迟与视频流水延迟是两种独立接口，不应混用。50 MHz 时七拍约 140 ns；实际刷新兼容性仍必须单独在屏幕核验。

## FX参数表

值暂为归一化0..127；页面直接显示该整数，不捏造Hz、秒、dB。音频队友确认映射后再统一显示单位。`BPM/FREE`目前切换保存状态，未经约定不能把LEFT/RIGHT整数当作实际毫秒或拍值。LINK开启时立即令RIGHT跟随LEFT，此后任意一侧的触屏/外部输入都会同时更新左右参数。

| 内部ID | 参数 | 坐标中心 |
|---|---|---|
| 0x60..0x65 | Delay Feedback / Left / Right / Filter Freq / Q / Mix | X448+56*n，Y416 |
| 0x66..0x6C | Reverb Size / Decay / Low Cut / High Cut / Spin / Spin Depth / Mix | X444+48*n，Y524 |
| 0x6D..0x72 | EQ Low Freq / Q / Gain / High Freq / Q / Gain | X448+56*n，Y632 |
| 0x80..0x82 | Delay / Reverb / EQ Enable | 各标题右侧 |
| 0x83..0x85 | Delay BPM / Link / Ping-pong | Delay标题 |
| 0x86 | Reverb Hall=1 / Plate=0 | Reverb标题 |
| 0x87..0x88 | EQ Low / High类型：Bell=0、Shelf=1、Cut=2 | EQ标题 |

这是紧凑触屏版：本轮实现三种EQ类型选择和Delay左右LINK联动，没有完整复刻Delay滤波响应编辑图和Tap Delay功能。BPM、EQ类型先作为独立音效配置状态保存，实际拍速/滤波响应由音频配置适配器实现；已实现的UI联动不等同于音频左右通道已经联动。

## 下游逻辑接口与完整快照

FX事件：`fx_event_valid / fx_event_id / fx_event_value`。绑定事件：`route_event_valid / route_event_target / route_event_source / route_event_depth`。source=0解除、1/2/3分别LFO1/2/3，depth为8位有符号数。

完整输出快照：

- `fx_parameter_snapshot[132:0]`，19×7 bit，最低7 bit是0x60；`fx_switch_snapshot[10:0]`：bit0..6对应0x80..0x86；bit7/9分别为EQ Low Shelf/Cut，bit8/10分别为High Shelf/Cut，两者全零为Bell。
- `lfo_node_snapshot[146:0]`：LFO1/2/3顺序，各49 bit，节点0..6各7 bit，从低位排列；固定横坐标等间距，节点电平0..127。
- `lfo_rate_snapshot[8:0]`：各3 bit，0..5对应0.25/0.5/1/2/4/8 Hz。
- `lfo_step_snapshot[2:0]`、`lfo_once_snapshot[2:0]`分别对应阶梯及单次模式。编辑节点转为平滑自定义曲线。
- `route_source_snapshot[105:0]`：53×2 bit；`route_depth_snapshot[423:0]`：53×8 bit，有符号。
- 53个目标的索引、参数ID和坐标唯一来源为`mod_targets.vh`，由`tools/generate_mod_targets.py`生成。内部ID与音频MIDI CC是两种编号，不能混用。

快照在时钟域内为当前权威状态。事件是变更提示，当前没有ready/ack；不同FX外部更新与触摸更新恰好同拍时，事件提示可合并为后一项，但两个参数状态都保存。正式串行适配器应对照快照形成dirty位图/待发队列，在传输忙时合并最新值，且按版本号/commit原子提交曲线配置，不把一拍事件直连慢串口。不同快照字段需由适配器在同一时钟沿锁存，再跨域。

ENV目标目前按当前显示的ENV参数ID绑定，没有细分三个ENV页签的目标ID。Unison等离散目标的合法量化必须由音频适配层处理，UI归一化预览不等同于音频合法值。

## 平滑算法与来源

2026-10-18阅读Xfer官网首页进入[Serum 2产品页](https://xferrecords.com/products/serum-2)。官方当前页面介绍产品与调制界面，旧`/products/serum`返回404；没有获得可以证明Serum内部插值公式的资料，不声称复刻其专有算法。

阅读[SciPy PchipInterpolator官方文档](https://docs.scipy.org/doc/scipy/reference/generated/scipy.interpolate.PchipInterpolator.html)，确认PCHIP是C1保形分段三次Hermite，使用调和平均切线、保持单调且不出现过冲。本实现借鉴保形Hermite思路，但采用更适合定点硬件的minmod切线，不等同于SciPy PCHIP：内部节点相邻斜率同号时取绝对值较小者，否则取0；两端切线置0。每段为三次Hermite，端点精确通过，段内单调、无过冲，内部连接一阶连续。

定点Horner计算保留中间精度，末尾统一截断为Q7.6，控制域后台刷新385点表，像素域查表。初版中途截断曾造成端点附近极小反向台阶，已通过末端截断修正，专项回归检查单调性/端点/幅值。拖拽缩略图为七点线性简图，主曲线与调制值共用平滑表。

已核对GitHub团队main `838b134`的`docs/lfo_curve_control.md`：其三点两曲率公式为smoothstep加bump，且音频为96 kHz。七点模型与其不能直接无损映射；需音频队友选择扩展配置、查表采样曲线或明确的有损适配。本轮不自动改队友实现。
