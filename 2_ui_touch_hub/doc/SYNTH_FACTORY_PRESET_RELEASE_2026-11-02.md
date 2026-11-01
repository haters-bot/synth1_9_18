# 官方音色库正式构建、时序收敛和 SRAM 部署记录

用户于 2026-11-02 明确授权：开始构建，按照流程直到完成烧录。仅 UI SRAM operation 2；不写 Flash、音频板或 ESP。

## 第一轮正式构建：禁止部署

- 源码检查点：`e27b2c36851dad48d3ec583e15c8072e4dde49f3`。
- 工程：`2_ui_touch_hub.gprj` / `ui_touch_hub_top`；Gowin Synthesis、place3、route1、timing driven，配置显式指定。
- 隔离目录：`E:/gaoyun_builds/R16A_build_20261102_044748`。
- 04:47:51 启动、05:09:47 退出 0；位流生成成功，但时序失败。
- 审计：`audit_20261102_051007_420448.json`，124 冻结/工作区输入和 124 引脚匹配；setup 314、hold 0，最差 setup −1.062 ns，像素时钟 47.477/50 MHz；其他六个时钟及 recovery/removal/pulse 通过。
- 该位流绝未烧录。整个失败目录、审计、网表、位流和 `source_acceptance_frozen.json` 保留。

### STA 报告中暴露的两条长组合链

已报告的 250 条负路径由两类起点组成，不能把报告条数当作完整违例端点数：

1. `u_rst_sync/reset_cnt_1_s0` → MIDI/FIFO 的 CC 接收组合译码 → `u_static_cc_sync/sent[]`、`initial_pending[]`。最差到 `sent[44]_2_s1` 的 CE 为 −1.062 ns。UART 接收确认同拍直接驱动大量参数影子寄存器的写使能，跨越长译码和高扇出布线。
2. `u_touch_router/s0_tx_7_s0` → 导航头栏几何/capture → `u_render/u_binding/depth[]`。最差约 −1.007 ns。原始导航取消信号没有寄存，穿过导航逻辑后直接进入绑定库。

这次问题不是未设置 EDA 默认模式，也不是逻辑容量满。第一轮实际使用的配置正确，最终资源为逻辑 56%、寄存器 29%、BSRAM 55%；需要缩短真实组合路径。

## 最小 RTL 修补

仅修改两个生产文件，没有修改协议、53 个目标、串口编码、引脚、时钟或约束：

- `static_cc_sync.v`：用本地寄存器保存 UART 已接受的 scan/value/valid，下一拍写入影子库；请求仍在真实 FIFO 接受沿撤销。增加一拍提交间隔，避免 COUNT=1 时在影子尚未提交前重复发送。接受沿发生的新编辑仍在后续重发，不能误记成已发送。
- `lfo_binding_state.v`：导航取消先寄存一拍，再作用于绑定库；原有触摸数据包有两拍译码，取消仍在对应头栏触摸包之前生效。保持已保存路由，取消活动拖动，返回后可重新绑定。

没有添加 false path、multicycle、降低像素/DDR 时钟或调整综合布线策略来绕开违例。

## 修补后源码验证

全部使用当前源哈希重新运行并通过：

- 16 项原有 RTL 回归：`E:/gaoyun_builds/six_fix_20261102_051439_661319/result.json`。
- 完整预设状态库/UART：`E:/gaoyun_builds/synth_presets_20261102_051439_574254/result.json`，11,343 字节与固定 Python 参考一致；包括同音色重发、快切、启动立即应用、Note 优先及后续 CC/重新绑定。
- 实际 renderer：`E:/gaoyun_builds/synth_preset_ui_20261102_051529_989988/result.json`，12 卡片、512 次七拍对齐、六分类共 1,382,400 个像素采样。
- normal/debug 层次：`E:/gaoyun_builds/ui_elaboration_20261102_051549_434465/result.json`。
- FX 实体输入 4,352 项：`impl/fx_input_pipeline_20261102_051555_406348/result.json`。
- 新增/扩展的针对性检查：接受沿修改的旧/新值所有权、COUNT=1 无重复、导航取消和重新绑定。
- 6 组证据、135 个当前测试输入哈希一致，汇总为 `SYNTH_FACTORY_PRESETS_2026-11-02.acceptance.json`。

旧 FX 固定颜色 oracle 在原始未修改 HEAD 也失败，保持单独失败记录，不计作通过；本次不改原显示像素来迎合陈旧期望。

## 工程机和部署前置条件

用户将主力机切回昨晚成功的 Wi-Fi。使用直接 LAN：本机 `192.168.31.182`、工程机 `192.168.31.183`，通过 `GAOYUN_LOCAL_IP`、`GAOYUN_REMOTE_IP` 环境变量覆盖；没有使用 ZeroTier 中继，也没有改全局 SSH 配置。

- `preset_remote_preflight_20261102_045347_285633`：只读确认主机 DESKTOP-FDEVSGP、无其他下载进程、唯一预期 UI 板旧 UserCode `0x352D` / Status `0x26230`。
- `preset_transfer_preflight_20261102_050021_730553`：工程机可从本机 8899 端口读取传输测试内容。没有烧录操作。

后续正式构建、五类审计和唯一一次 SRAM 写入结果完成后追加于本记录；第一轮失败位流始终禁止部署。
