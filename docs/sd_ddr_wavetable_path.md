# SD 卡到 DDR3 的真实波表路径

## 数据流

```text
FAT16/FAT32 SD卡根目录第0个文件
        │ 逐字节
        ▼
sd_file_list_reader
        │ WTB1文件流，50 MHz
        ▼
sd_wavetable_loader
        │ 32字节打包 + 8深度异步FIFO
        ▼
DDR3用户接口，100 MHz，256 bit/事务
        │ OSC A/B独立预取
        ▼
双bank、每bank两帧的本地BRAM缓存
        │ 当前帧/下一帧同时读取并插值
        ▼
原有768 kHz TDM振荡器与音频链路
```

DDR校准完成之前，SD控制器保持复位。SD文件完整写入DDR后，两组缓存分别读取所选
波表和WT Position对应的相邻两帧。缓存切换使用toggle握手，只有两帧全部写完后才
原子切换活动bank。装载或换帧期间，振荡器继续使用上一组缓存；首次缓存准备好以前
使用原来的Acid ROM作为安全回退。

## WTB1文件格式

文件头固定32字节：

| 偏移 | 内容 |
|---:|---|
| 0～3 | ASCII `WTB1` |
| 4 | 版本，当前为1 |
| 5 | 波表数量，1～16 |
| 6～7 | 每张波表帧数，小端16位，固定256 |
| 8～9 | 每帧采样数，小端16位，固定256 |
| 10 | 采样位数，固定16 |
| 11 | 小端标志，固定1 |
| 12～31 | 保留，填0 |

负载区按波表编号、帧编号、相位采样依次排列，采样为有符号16位小端数。一张波表
固定占用`256 × 256 × 2 = 131072`字节。DDR中的负载从地址0开始，不保存32字节文件头。

使用打包工具：

```powershell
python tools/pack_wavetable_bank.py `
  C:\wave\table0.wav C:\wave\table1.wav `
  --source-frame-size 2048 `
  -o E:\SDCARD\WAVEBANK.WTB
```

当前SD控制器按根目录文件编号读取第0个普通文件。板测时建议使用空的FAT32卡，只复制
一个`WAVEBANK.WTB`文件，避免目录顺序与文件名显示顺序不同。

## 参数控制

| 参数 | MIDI控制 |
|---|---|
| OSC A波表编号 | 通道16，CC49，低4位，范围0～15 |
| OSC B波表编号 | 通道16，CC50，低4位，范围0～15 |
| OSC A WT Position | 通道16，CC20，范围0～127 |
| OSC B WT Position | 通道16，CC28，范围0～127 |
| 选择SD/DDR波表 | CC21或CC29发送127 |

编号超过文件中实际波表数量时会钳位到最后一张。WT Position映射到256帧，并在当前帧
与下一帧之间执行8位线性插值。

## 时钟与带宽

- SD和音频控制域：50 MHz；
- DDR PHY：400 MHz；
- DDR用户接口：100 MHz、256 bit；
- 振荡器内部采样：768 kHz；
- 每次缓存换帧读取32个DDR事务，共1024字节；
- DDR事务由OSC A缓存、OSC B缓存和SD装载器三方轮询仲裁。

## 当前验证

`sim/run_sd_ddr_wavetable_path_test.do`覆盖：

1. WTB1头解析；
2. 131072字节负载跨异步FIFO写入4096个DDR块；
3. DDR地址步进和数据字节序；
4. 双帧缓存预取；
5. WT Position换帧和帧间插值；
6. 原音频TDM、ADSR、MIDI和双振荡器回归。

目前只有RTL事务级验证。板级SD初始化、DDR校准、引脚与时序需要在有开发板时检查。
