# UI 演奏功能：EDA 配置与曲谱存储自查（2026-10-29）

## 结论与边界

已经确认曲谱调度器的 RAM 推断失败，不能继续通过缩小事件容量解决。
另发现实际使用的是偏速度的布线算法 2，已将后续构建明确设为算法 1。
尚无同一份网表分别使用两种布线算法的对照结果，因此不能断言算法 2
是此前失败的根因，也不能把 RAM 修复的收益归功于布线模式。

本次只处理 UI 工程；音频工程没有修改、推送或烧录。所有原始文件、
失败构建和诊断日志保留。没有进行硬件操作。

## 实际配置核对

比较对象：

- 成功 UI 基线：`impl/R16A_build_20261028_032336`。
- 失败演奏候选：`impl/R16A_build_20261029_090153`。

两者实际 `impl/pnr/cmd.do` 均为：

| 配置 | 实际值 |
| --- | --- |
| 器件/封装/速度等级 | GW5AST-138B / PBGA484A / 1 |
| 料号 | GW5AST-LV138PG484AC1/I0 |
| 布局算法 | `-place_option 3` |
| 布线算法 | `-route_option 2` |
| 时序驱动 | `-timing` |
| Hold 修复 | `-correct_hold 1` |
| Route Maxfan | 23 |

综合日志均实际执行 GowinSynthesis，综合 `.prj` 中除输出路径外的选项一致。
没有发现切错器件、误用另一综合工具、禁用时序驱动的证据。
`global_freq=100` 也同时存在于成功基线；不能仅凭该默认值认定实际像素
时钟为 100 MHz，最终须核对 SDC、PLL 和 STA。

`build.tcl` 与 `build_debug.tcl` 现显式指定：

```tcl
set_option -synthesis_tool gowinsynthesis
set_option -place_option 3
set_option -route_option 1
set_option -timing_driven 1
```

本机 V1.9.11.03 Education 的工具名参数接受小写 `gowinsynthesis`；
手册示例的 `GowinSynthesis` 在本机被拒绝为 `unknown synthesis tool`。
该大小写差异已在只综合的诊断工程中实际验证，错误日志也保留。
后续必须读取实际生成的 `.prj`/`cmd.do`，不能只检查脚本文本。

## 失败证据

`090153` 的进程已退出，返回码 1。它完成布局后在布线失败：
`PR0004: 19825 unrouted nets`。没有合格位流或完整 STA 可供部署。

| 最终 PnR 资源 | 成功基线 | 失败候选 |
| --- | ---: | ---: |
| Logic | 56,417（41%） | 85,541（62%） |
| Register | 29,375（22%） | 79,218（57%） |
| CLS | 44,024（64%） | 67,470（98%） |
| BSRAM | 19 | 19 |

失败候选的综合层次报告显示 `u_performance_scheduler` 占 48,262 个寄存器、
26,676 个 LUT，未使用 BSRAM。逻辑总量百分比掩盖了 CLS 的实际饱和。

## RAM 修复与对照实验

旧写法把内存读写混入带异步复位的控制过程，并从不同地址表达式读取，
未匹配本机工具的 BSRAM 推断模板。仅添加 `syn_ramstyle` 属性没有奏效。

修正为单写端口、单同步读端口的独立无复位过程；控制状态单独复位。
预取等待保证地址更新后的同步读延迟，计数器复位使旧 RAM 数据无效。
清空优先于同拍写入，满容量计数使用扩展宽度，避免回绕丢失最后事件。

对照目录：`impl/performance_eda_probe_20261029_105142`。
两个独立工程均使用 1024 容量、同一器件和同一 EDA 参数，仅调度器写法不同。

| 独立综合结果 | 修正前 | 修正后 |
| --- | ---: | ---: |
| 寄存器 | 48,266 | 131 |
| LUT | 27,235 | 178 |
| BSRAM | 0 | 3 |

证据在 `resource_comparison.json`、两侧综合 XML、网表和 `build.log`。
独立综合与完整工程的优化上下文不同，其资源数字不可直接当作完整 UI 数字。
初版接口仍限制 1024 个事件；提高容量需同步浏览器/网关并另行验证完整工程。

## 验证与当前候选

- ModelSim 在容量 5、8、1024、4096 下均通过：时间戳、同刻顺序、暂停、
  重播、满容量及溢出拒绝、运行时拒绝装载/清空、停止、清空优先级、复位失效。
  证据：`impl/performance_scheduler_tests_20261029_104938_064254`。
- Python MIDI 与协议 CRC/分片/恢复/批次回归通过。
- 正常/诊断版完整 RTL 编译与串口波形/日志回归通过，含 FIFO 溢出报告、
  分片和重新同步；证据：`impl/trace_tests_20261029_105716_858285`。
- 新完整候选的 80 个输入哈希与工作区一致；`git diff --check` 通过。
- 新完整候选：`impl/R16A_build_20261029_105439`，含源码哈希清单。
  启动 PID 28528，exec 会话 35235。恢复时以真实进程和日志为准。
  完整综合已通过：31,084 个寄存器、52,920 个 LUT、22 块 BSRAM；
  其中调度器为 127 个寄存器、169 个 LUT、3 块 BSRAM，修复在完整工程中生效。
  实际 `cmd.do` 确认为 `place_option 3`、`route_option 1`、`-timing`。
  本段记录时正在布局，尚未完成布局布线，不能宣称时序通过。
  配置及综合证据另存该候选的 `eda_configuration_audit.json`。

新候选必须完整布线成功，再运行 `tools/audit_build.py`，确认输入哈希、
位流完整性和 setup/hold/recovery/removal/pulse 五类时序全部通过。
本次没有烧录授权，不自动部署。

## 官方资料来源（本机安装包，未使用网页搜索）

- `D:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/doc/EN/SUG100-4.4.2E_Gowin Software User Guide.pdf`：
  PDF 第 46–47 页说明布局/布线配置；算法 1 牺牲速度尝试更好的布线，
  算法 2 提高布线速度。PDF 第 112、122–124 页列出 Tcl 参数。
- 同目录 `SUG550-2.0.1E_GowinSynthesis User Guide.pdf` §5.15：
  `syn_ramstyle=block_ram` 及对 SUG949 推断模板的引用。
- 同目录 `SUG949-1.9E_Gowin HDL Coding User Guide.pdf` 第 4 章：BSRAM 编码指南。

结论依据为官方文档与本机实际执行产物；不把“模式 1 一定成功”当作厂商保证。
