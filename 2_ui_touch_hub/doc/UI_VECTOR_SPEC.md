# 纯硬件矢量图形光栅化渲染规范 (UI Vector Engine Specification)

> **画布分辨率**：1280 × 720 @ 50.5Hz / 60Hz 原生 CEA 720p 视频流  
> **设计思想**：**Procedural Vector Graphics (PVG)** —— 全流水线纯数学计算，零 ROM 位图依赖，0 内存带宽占用，0 帧延迟，彻底解决杂色、噪点与裁切缺陷。

---

## 一、 配色系统规范 (Palette Reference)

基于经典 Serum 合成器高级质感：深黑曜石/深岩灰工作台底色 + 电光荧光绿 / 亮钴青 / 琉璃宝蓝高对比度发光波形。

```verilog
// 基础底色与背板
localparam C_BG           = 24'h101318; // 全局深邃底色
localparam C_PANEL_BG     = 24'h181C24; // 面板凹陷底色
localparam C_PANEL_BORDER = 24'h2A3140; // 面板金属外框
localparam C_PANEL_HEADER = 24'h222834; // 模块标题栏底色
localparam C_PANEL_BEVEL  = 24'h384256; // 1px 倒角反光亮线

// 视窗网格与基线
localparam C_GRID_SUBTLE  = 24'h141D26; // 示波器暗淡参考网格
localparam C_GRID_AXIS    = 24'h223040; // 零电平参考中轴线

// OSC A 发光波形 (Neon Lime / Serum Signature)
localparam C_OSCA_LINE    = 24'h76EA12; // 荧光绿亮线条 (描边)
localparam C_OSCA_GLOW    = 24'h368406; // 边缘辉光半色
localparam C_OSCA_FILL    = 24'h142806; // 波形半透明渐变填充底色

// OSC B 发光波形 (Electric Cyan)
localparam C_OSCB_LINE    = 24'h2AD8EC; // 亮青色线条
localparam C_OSCB_GLOW    = 24'h157482; // 青色光晕
localparam C_OSCB_FILL    = 24'h082530; // 青色半透明填充

// Filter 频响曲线 (Cobalt Blue)
localparam C_FLT_LINE     = 24'h3884F8; // 钴蓝频响曲线
localparam C_FLT_FILL     = 24'h0E2448; // 通带区域填充
localparam C_FLT_NODE     = 24'hFFFFFF; // 截止频率高亮节点

// ENV ADSR 包络曲线 (Azure Aqua)
localparam C_ENV_LINE     = 24'h44C4F8; // 亮电光蓝曲线
localparam C_ENV_FILL     = 24'h102640; // 包络区域半透明填充
localparam C_ENV_NODE     = 24'hFFFFFF; // 关键拐点白圆环控制柄

// 旋钮与刻度
localparam C_KNOB_BEZEL   = 24'h323A4A; // 旋钮金属外圈
localparam C_KNOB_BODY    = 24'h1A1E26; // 旋钮内部暗色转盘
localparam C_KNOB_NEEDLE  = 24'hFFFFFF; // 旋钮指示指针 (纯白带青色核心)
localparam C_KNOB_ARC     = 24'h38E8FF; // 旋钮当前电平 270° 发光弧形进度条

// 虚拟琴键
localparam C_KEY_WHITE    = 24'hE6EAEE; // 象牙白白键
localparam C_KEY_W_BORDER = 24'h14161B; // 白键细微缝隙黑线
localparam C_KEY_BLACK    = 24'h181B22; // 墨黑黑键
localparam C_KEY_B_TOP    = 24'h2C313C; // 黑键顶部反光高亮
localparam C_KEY_PRESS_W  = 24'h4FACFE; // 白键按下高亮反馈 (天蓝发光)
localparam C_KEY_PRESS_B  = 24'h2563EB; // 黑键按下高亮反馈 (深钴蓝发光)
```

---

## 二、 关键图形的纯硬件实时数学解析算法

### 1. 2D 动态波表 (OSC A & OSC B)
- 视窗高度 $H = 154$，中心零点基线 $Y_0 = 153$。
- 根据 `wt_pos` 参数 (0 ~ 127) 实现多形态连续动态调制：
  - `wt_pos == 0`：纯正弦基波 $y(x) = Y_0 - A \sin(2\pi \cdot \frac{2x}{W})$；
  - `wt_pos > 0`：正弦波叠加入高次谐波与方波/锯齿畸变因子，表现丰富的双峰脉冲与锯齿波过渡；
  - 硬件实现：采用内置高精度正弦表 (`sine_table`)，通过双抽样线性插值生成任意相位点幅值。
- **填充判定**：
  像素落在 $Y_0$ 与 $y(x)$ 之间时输出发光填充色 `C_OSCA_FILL`；
  像素落在 $|y - y(x)| \le 1$ 时输出高亮描边色 `C_OSCA_LINE`。

### 2. 滤波器动态频响曲线 (FILTER)
- 根据截止频率 `cutoff` ($f_c \in [0, 127]$) 与共振峰 `resonance` ($Q \in [0, 127]$)：
  - 通带 ($x < x_c$)：低通保持平坦，$y = Y_{\text{pass}}$；
  - 共振峰拐点 ($x \approx x_c$)：在截止点上扬形成高度为 $Q \times \text{scale}$ 的共振凸起；
  - 阻带 ($x > x_c$)：以 12dB/oct 或 24dB/oct 对数斜率急剧滚降至基底。
- 流水线计算：使用预置分段多项式折线逼近，每个像素周期内仅需 1 次定点数加减与移位即可求出目标高度。

### 3. ADSR 动态包络曲线 (ENV)
- 视窗高度 $H = 108$，基底 $Y_{\text{base}} = 496$，顶峰 $Y_{\text{peak}} = 412$ (动态行程 84px)。
- 关键水平长度：
  - 起音长度：$L_A = 24 + (\text{attack} \times 120 / 128)$；
  - 衰减长度：$L_D = 24 + (\text{decay} \times 160 / 128)$；
  - 延音长度：$L_S = 180$；
  - 释音长度：$L_R = 24 + (\text{release} \times 160 / 128)$；
  - 延音电平：$Y_{\text{sus}} = Y_{\text{base}} - (\text{sustain} \times 84 / 128)$。
- 硬件使用预计算倒数表 (`reciprocal_lut`) 消除除法器，实现 1 拍定点乘法获取光滑的斜坡折线。

### 4. 旋转旋钮指针与 270° 发光弧线 (Knobs)
- 中心点 $(x_c, y_c)$，最大半径 $R = 14 \sim 16$。
- **圆形判定**：$dx = |x - x_c|, dy = |y - y_c|, r^2 = dx^2 + dy^2$：
  - $r^2 \le R^2$ 判定为旋钮内部；
  - $R^2 - 2 \le r^2 \le R^2$ 判定为金属外圈光晕；
- **270° 旋转指针**：
  将参数值 $v \in [0, 127]$ 划分为 16 个高精度角度方向向量 $(\cos \theta, \sin \theta)$。
  通过向量投影计算：
  $\text{proj} = dx \cdot \cos\theta + dy \cdot \sin\theta$
  $\text{perp} = |dx \cdot \sin\theta - dy \cdot \cos\theta|$
  当 $\text{proj} > 0$ 且 $\text{perp} \le 1.2$ 时，判定命中发光指针！
