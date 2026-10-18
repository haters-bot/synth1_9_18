# DDR3 400 MHz PLL IP 配置

## 用途

从板载 `V22` 的 `50 MHz` 时钟产生 DDR3 Memory Interface 所需的
`400 MHz memory_clk`。GW5AST-138K 的 `pll_stop` 必须直接连接 PLL 的
`enclk2`，因此不能复用当前只输出50 MHz的系统 PLL。

## IP Core Generator 设置

| 选项 | 设置值 |
| --- | --- |
| File/Module Name | `ddr3_pll_400m_ip` |
| IP | `PLL_ADV` |
| Mode | `General` |
| CLKIN | `50.000 MHz` |
| Initialization Clock | `50.000 MHz` |
| Feedback | `Internal` |
| CLKOUT0 | 开启，`400.000 MHz` |
| CLKOUT1 | 开启，`50.000 MHz` |
| CLKOUT2 | 开启，`400.000 MHz` |
| Clock Enable Ports | 开启 |
| PLL Reset | 开启 |
| Lock Output | 开启 |
| SSC | 关闭 |

生成结果必须至少包含：

```text
clkin, init_clk, reset, lock
enclk0, enclk1, enclk2
clkout0, clkout1, clkout2
```

本地封装只使用 `clkout2` 作为 `memory_clk`，并将 DDR IP 的低有效
`pll_stop` 直接接到 `enclk2`。这个连接方式来自 IPUG281-2.6 第 4.4.4 节
针对138K器件的连接图。

生成后若端口名不同，只修改 `src/ddr3_wavetable_wrapper.v`，不要修改厂商IP。
