# 全局 Delay 与 Reverb

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
  ├─ global_delay
  └─ global_reverb
        ↓
Master Level → I2S
```

它是全局单声道效果链，只实例化一次，不随32复音、Unison或两个振荡器复制。
Delay和Reverb在旁路或未选中时仍接收样本，因此切换模式时内部历史不会被清空。

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

效果器使用约798720个有效存储位，约97.5 KiB：

- Delay：32768 × 16 bit；
- 4条Comb：4 × 4096 × 16 bit；
- 2条Allpass：512 × 16 bit和256 × 16 bit。

数组带有高云块RAM推断属性。RTL不在复位时遍历清零RAM，而是为每条延迟线记录已写入
样本数；地址尚未形成有效历史时强制读作0。实际映射到多少BSRAM必须以后续综合报告为准。

## 6. 第一版限制

- 当前音频链仍为单声道；Reverb没有左右声道扩散。
- Delay Time和Reverb Size直接改变读指针/环长。演奏中快速修改可能产生轻微跳变，后续可加入交叉淡化双读头。
- Delay和Reverb参数尚未加入通用LFO目标表。
- 模式3是并联混合，没有实现Delay进入Reverb的串联发送量。

