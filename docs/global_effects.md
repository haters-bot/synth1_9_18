# 全局效果链

## 1. 数据流位置

效果器位于降采样和全局滤波器之后、Master Level之前：

```text
768 kHz振荡器混音
        ↓
8倍FIR降采样
        ↓ 96 kHz
全局滤波器
        ↓
global_effects
  → Distortion
  → Phaser
  → Chorus
  → Delay/Reverb兼容核心
  → Compressor/Limiter
        ↓
Master Level → I2S
```

它是全局单声道效果链，只实例化一次，不随32复音、Unison或两个振荡器复制。
Delay和Reverb在旁路或未选中时仍接收样本，因此切换模式时内部历史不会被清空。
新增四级分别具有独立Enable和Dry/Wet，因此可与Delay/Reverb同时使用。CC51原有含义
保持不变，旧上位机仍能控制原来的Delay/Reverb组合。

## 2. 模式

| CC51 | 模式 | 输出 |
|---:|---|---|
| 0 | Bypass | 原始滤波器输出 |
| 1 | Delay | Delay的Dry/Wet结果 |
| 2 | Reverb | Reverb的Dry/Wet结果 |
| 3 | Delay + Reverb | 两路Dry/Wet结果等权并联 |

模式3不是串联结构。它把Delay和Reverb的输出各乘0.5后相加，避免两路满幅直接叠加。

## 3. Delay

Delay使用`32768 × 16 bit`循环缓冲，时间映射为：

```text
delay_samples = 480 + 250 × CC52
delay_ms      = delay_samples / 96
```

因此范围约为`5.0～335.7 ms`。CC53控制反馈，最大反馈约为：

```text
127 / 128 × 7 / 8 ≈ 0.868
```

CC54控制Dry/Wet，0为全干，127为全湿。反馈写入和输出混合都在16位输出前饱和，
不会发生二进制回绕。

## 4. Reverb

Reverb采用Schroeder结构：

```text
输入 ─┬─ 低通反馈Comb 1 ─┐
      ├─ 低通反馈Comb 2 ─┤
      ├─ 低通反馈Comb 3 ─┼─ 求平均 ─ Allpass 347点 ─ Allpass 113点
      └─ 低通反馈Comb 4 ─┘
```

CC55同时缩放四条梳状线长度：

| 线路 | CC55=0 | CC55=127 |
|---|---:|---:|
| Comb 1 | 1277点，13.3 ms | 约2541点，26.5 ms |
| Comb 2 | 1499点，15.6 ms | 约2987点，31.1 ms |
| Comb 3 | 1741点，18.1 ms | 约3467点，36.1 ms |
| Comb 4 | 1999点，20.8 ms | 约3973点，41.4 ms |

CC56控制反馈衰减，最大同样约0.868。反馈环内固定加入四分之一速度的一阶低通，
使高频尾音比低频更快衰减。CC57控制Reverb的Dry/Wet。

四条Comb共享一条时分复用乘法路径。每个输入样本的全部Reverb运算约14个50 MHz时钟，
远小于96 kHz下约521个系统时钟的样本间隔。

## 5. RAM与上电处理

Delay、Reverb和Chorus合计使用约864256个有效存储位，约105.5 KiB：

- Delay：32768 × 16 bit；
- 4条Comb：4 × 4096 × 16 bit；
- 2条Allpass：512 × 16 bit和256 × 16 bit。
- Chorus：4096 × 16 bit。

数组带有高云块RAM推断属性。RTL不在复位时遍历清零RAM，而是为每条延迟线记录已写入
样本数；地址尚未形成有效历史时强制读作0。实际映射到多少BSRAM必须以后续综合报告为准。

## 6. 第一版限制

- 当前音频链仍为单声道；Reverb没有左右声道扩散。
- Delay Time和Reverb Size直接改变读指针/环长。演奏中快速修改可能产生轻微跳变，后续可加入交叉淡化双读头。
- Delay和Reverb参数尚未加入通用LFO目标表。
- 模式3是并联混合，没有实现Delay进入Reverb的串联发送量。

## 7. Distortion

Distortion提供Soft Clip、Hard Clip和Foldback三种波形整形。Drive把输入增益从1倍映射到
约8倍；Tone是一阶低通，Mix进行Dry/Wet插值。Soft Clip使用分段线性曲线，避免在RTL中
实现除法或非线性函数。当前失真位于96 kHz路径，极高Drive仍可能产生48 kHz以上的谐波；
第一版通过软削波和Tone低通控制这部分能量。

## 8. Phaser

Phaser使用4级一阶全通滤波器：

```text
y[n] = -a*x[n] + x[n-1] + a*y[n-1]
```

四级共享一条乘法数据路径，每个样本约使用4个50 MHz时钟。内部三角LFO控制系数，
Center、Depth和Mix以每个96 kHz样本一级的速度平滑。Feedback最大约为0.5，避免全通链
进入不稳定状态。

## 9. Chorus

Chorus使用`4096 × 16 bit`循环缓冲。基础延迟约2～23 ms，LFO深度最大约5.25 ms。
每个样本分三拍读取相邻两个延迟点，并使用8位小数线性插值，避免整数读指针造成明显的
阶梯音高。Depth、Delay和Mix按每个采样一级平滑。反馈最大约0.5。

新增的Chorus缓冲增加65536 bit，约8 KiB有效存储；实际BSRAM数量以综合报告为准。

## 10. Compressor与最终限制

Compressor使用峰值包络检测，Attack控制增益下降速度，Release控制增益恢复速度。
Threshold从约-30 dB幅度映射到接近满幅，Ratio控制超过阈值后的线性增益衰减，Makeup
提供最高约1.5倍补偿。输出在16位边界进行饱和，因此不会发生二进制回绕。该限制器是
零前视结构，只能钳制当前样本，不能完全替代带look-ahead的母带限制器。

## 11. 控制编号

| CC | 参数 |
|---:|---|
| 58～62 | Distortion Enable、Type、Drive、Tone、Mix |
| 63～68 | Chorus Enable、Rate、Depth、Delay、Feedback、Mix |
| 69～74 | Phaser Enable、Rate、Depth、Center、Feedback、Mix |
| 75～81 | Compressor Enable、Threshold、Ratio、Attack、Release、Makeup、Mix |

Enable为0时旁路，非0时开启。Type使用0～2，其余参数均使用0～127。

