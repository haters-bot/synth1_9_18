# 系统 50 MHz PLL 配置清单

## 目的

将板载 `V22` 引脚输入的 `50 MHz` 时钟送入 Gowin PLL，再用 PLL 的
`50 MHz` 输出驱动全部系统逻辑。该实验用于验证 PLL 输出能否通过专用全局
时钟网络分发，并检查 `PR1014` 普通布线时钟警告是否消失或缩小影响范围。

这个实验不改变系统工作频率，因此 UART、768 kHz 内部采样时序、96 kHz
音频输出和现有音高参数都不需要重新计算。

## 已确认环境

- FPGA：`GW5AST-LV138PG484AC1/I0`
- Gowin EDA：`V1.9.12.03 (64-bit)`
- 外部参考时钟：`50.000 MHz`
- 外部时钟引脚：`V22`
- 官方依据：`UG306-1.0.9 Arora V 时钟资源用户指南` 第 5.1 节

## IP Core Generator 设置

在当前工程中打开：

`Tools -> IP Core Generator -> Soft IP Core -> Clocking -> PLL_ADV`

不同版本的分类文字可能略有区别，以 IP 名称 `PLL_ADV` 为准。

| 选项 | 设置值 |
| --- | --- |
| File Name | `sys_pll_50m_ip` |
| Module Name | `sys_pll_50m_ip` |
| Language | `Verilog` |
| Mode | `General` |
| CLKIN Clock Frequency | `50.000 MHz` |
| CLKFB Source | `Internal` |
| Initialization Clock Frequency | `50.000 MHz` |
| CLKOUT0 | 开启 |
| CLKOUT0 Expected Frequency | `50.000 MHz` |
| CLKOUT0 Phase | `0 degree` |
| CLKOUT1～CLKOUT6 | 关闭 |
| PLL Reset | 开启 |
| Lock | 开启 |
| PLL Power Down | 关闭 |
| CLKIN Divider Reset | 关闭 |
| CLKOUT Divider Reset | 关闭 |
| SSC | 关闭 |
| Dynamic divider/phase/duty ports | 全部关闭 |
| mDRP dynamic control | 关闭，使用固定频率配置 |

点击 `Calculate` 后必须确认：

1. 配置计算成功；
2. `CLKOUT0 Actual Frequency` 为 `50.000 MHz`；
3. 界面显示的 VCO 频率位于当前器件允许范围内；
4. 生成模块至少具有 `clkin`、`clkout0`、`reset` 和 `lock` 四个端口。

若生成器改变了端口大小写或名称，保留生成结果，不要手工修改 IP 文件；本地
wrapper 将按实际模板文件适配。

## 生成目录

建议在工程中生成到：

`src/sys_pll_50m/`

完整保留以下文件：

- `sys_pll_50m_ip.v`
- `sys_pll_50m_ip_tmp.v`
- `sys_pll_50m_ip.ipc`
- IP 生成器同时产生的其他配置、初始化和仿真文件

当前生成记录：

- 生成目录：`src/gowin_pll/`
- 配置文件：`sys_pll_50m_ip.ipc`
- IP 版本：`1.0`
- Gowin EDA：`V1.9.12.03 (64-bit)`
- 生成时间：`2026-10-14 22:39:34`
- 实际接口：`clkin`、`init_clk`、`clkout0`、`lock`、`reset`
- 本地封装：`src/sys_clock_manager.v`

## 后续顶层接入

生成 IP 后再完成以下改动：

```text
V22/sys_clk -> sys_pll_50m_ip -> clk_sys -> 全部现有同步逻辑
                      |
                      +-> pll_locked

rst_n 与 pll_locked -> 异步置位、同步释放 -> rst_n_sys
```

`src/timing.sdc` 中的外部 `sys_clk` 仍保持 `20 ns` 输入时钟约束。PLL 输出的
派生时钟优先由 Gowin PLL 和时序分析器自动识别；布局布线后必须在时钟报告中
确认它确实被识别为 `50 MHz`，不能通过删除时钟约束隐藏问题。

## 验收标准

1. PLL 成功锁定，`lock` 在上电后稳定为高；
2. 所有业务逻辑只使用 PLL 输出的 `clk_sys`；
3. PLL 未锁定或外部复位有效时，`rst_n_sys` 保持为低；
4. 现有 RTL 回归测试全部通过；
5. 布局布线后 `clk_sys` 使用 `PRIMARY/GCLK` 资源；
6. 检查 `PR1014` 是否消失；如果仍指向 V22 到 PLL 输入，则记录为参考时钟入口
   的普通布线，不把它误判成 PLL 输出时钟树仍使用普通布线；
7. Setup/Hold 均无违例，并重新记录 WNS、TNS 和时钟偏斜。

## 已知限制

PLL 可以改善内部时钟分发，但不能保证 V22 到 PLL 输入端存在专用连接。最终
是否能消除 `PR1014` 必须由本器件、本封装的实际布局布线报告确认。
