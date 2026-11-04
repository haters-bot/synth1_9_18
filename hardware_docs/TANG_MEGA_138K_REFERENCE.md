# Tang Mega 138K 硬件参考手册

> 来源：Sipeed 官方 Wiki (https://wiki.sipeed.com/hardware/zh/tang/tang-mega-138k/mega-138k.html)

---

## 1. 核心芯片参数

- **FPGA 芯片型号**：`GW5AST-LV138PG484AC1/I0`（高云 Arora V 系列）
- **IDE 封装选择**：`PBG484A`，`Device Version: B/C`
- **逻辑单元 (LUT4)**：138,240
- **触发器 (FF)**：138,240
- **分布式 SRAM (S-SRAM)**：1080 Kbits
- **块状 SRAM (B-SRAM)**：6120 Kbits（340个）
- **乘法器 (18x18 Multiplier)**：298个
- **锁相环 (PLLs)**：12个
- **全局时钟**：16个 / 高速时钟：24个
- **高速收发器 (Transceivers)**：4个，速率范围 270Mbps ~ 8.0Gbps
- **硬核 PCIe**：1个（支持 x1, x2, x4 PCIe 3.0）
- **硬核处理器**：RISC-V AE350_SOC (@800MHz)
- **硬核 ADC**：2个
- **DDR3 内存**：1GiB DDR3 (512MiB x 2), 800Mbps
- **外部 Flash**：128 / 64 Mbits SPI Flash

---

## 2. 底板关键外设资源

- **供电与电源开关**：
  - DC 12V 输入（DC5521 接口）或 Type-C 供电
  - 支持 3.7V 1S 锂电池（板载充放电管理）
  - 长按 **PWR 按钮**（HDMI 接口旁）2 秒开机/关机
- **调试接口**：
  - 板载 USB JTAG & UART（Type-C `DEBUG-USB2` 接口，FT2232 双通道）
- **PCIe 插槽**：
  - PCIe 3.0 x4 金手指
- **高速通信接口**：
  - USB 3.0 x 1 (5Gbps)
  - 千兆以太网 GbE (RJ45) x 1
  - DVI/HDMI TX/RX 接口（支持高清视频输入输出）
- **屏幕与摄像头接口**：
  - RGB 屏幕接口（RGB888，40P FPC，支持 800x480 / 1024x600 等）
  - DVP 摄像头接口（与上侧 40P 排针及 PMOD 复用）
  - 电容触摸接口（I2C，如 GT911 驱动）
- **扩展与交互**：
  - 2 组 PMOD 接口
  - 2 组 40P 双排针扩展
  - 3 个用户按键 + 1 个 Reconfig 按键
  - 1 颗板载 WS2812 RGB LED + 4 颗电量指示灯 + 8 颗 PMOD LED
  - MicroSD 卡槽（1-bit SDIO / SPI）
  - MS5351 可编程时钟发生器（为 SerDes 提供 RefClk）
  - 扬声器接口 (2x 3W) + 3.5mm 耳机接口 + 麦克风阵列接口

---

## 3. Gowin 编程与固化注意事项

1. **IDE 版本要求**：
   - 教育版 IDE：≥ V1.9.11.03
   - 商业版 IDE：≥ V1.9.9
2. **Flash 固化模式**：
   - 推荐使用模式：`exFlash Erase,Program thru GAO-Bridge 5A`（≥V1.9.11.03）或 `exFlash Erase,Program thru GAO-Bridge Arora V`（≥V1.9.12）
   - 推荐使用单独的 **1.9.12 SP1 Programmer**（云源编程器）
3. **IO 电压警告**：
   - GPIO 排针外部通信电平必须严格为 **3.3V**，严禁输入过高电压。

---

## 4. 本地下载资料结构指引 (`hardware_docs/`)

- `02_Schematic/`: 包含 SOM 核心板与 DOCK 底板各版本详细原理图 PDF。
- `03_Designator_drawing/`: 交互式 PCB BOM (`ibom.html`) 及元件装配图 PDF。
- `04_Mechanical_drawing/`: 结构与尺寸图（CAD DXF 及 PDF）。
- `05_3D_file/`: 核心板与底板 3D 结构文件（STEP 与 7z 压缩包）。
- `07_Datasheet/`: 高云 GW5AST-138 Pinout 管脚表、物理约束手册、ADC 用户手册、RISC-V AE350 系列手册。
- `08_Misc/`: 官方全引脚物理约束文件 (`tang_mega_138K_pins.cst`)。
