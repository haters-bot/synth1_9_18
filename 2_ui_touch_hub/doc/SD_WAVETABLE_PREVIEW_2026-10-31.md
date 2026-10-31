# SD 波表本地预览：源码与验证记录

## 现场事实与缺项

用户确认“能切换音色，只是看不到波形”。已部署版本的 SD BANK 选择可以改变音色，但 UI 的 `SD/DDR NO PREVIEW`、`BANK STATUS UNAVAILABLE` 是固定占位文字，并非音频板发来的加载故障。之前实现了 CC49/50 的表选择，没有实现显示预览。

本轮补齐现有 OSC A/B 波形框的本地预览，不改音频板、MIDI/CC/SysEx 协议、BANK 编号和页面布局。不把本地预览当作 SD 就绪证明。**本轮没有运行 Gowin 综合布线，也没有烧录；当前实板仍是上一次部署版本。**

## 数据与渲染

- 只读输入 `D:/github/gaoyun/WAVEBANK.WTB`，10张表，SHA256 `59a09d279c4a55883cb92085a890e405e0b3494d5b03048ffad6765c05ae2a90`。
- `tools/import_wavetable_catalog.py` 在原有目录验证之外，生成 `wavetable_preview_data.vh` 与 `wavetable_preview_map.vh`，以及目录 JSON 的 preview 元数据。
- 每表取源帧 0、17、…、255 共16个锚点，每帧取相位0、2、…、254共128点，保留有符号8位采样。10表原始预览 ROM 共20,480字节；没有把整份1,310,752字节声音负载复制进 UI。
- MIDI WT POSITION 0～127 映射到锚点及插值系数，随后在相邻锚点之间插值。因此这是降采样后的源波表形状预览，不能当作精确的256帧音频重建、WARP/FX后波形或I²S实时示波图。
- `osc_panel_renderer.v` 中增加 `ui_wavetable_preview`：一个同步读源 ROM 在控制路径生成 A/B 两组小型双缓冲显示缓存，完成一整条128点曲线后才切换缓存；轮流服务A/B，避免持续变化的一路饿死另一路。ROM和缓存不作逐项复位，复位只清有效位。
- 像素路径只读显示缓存，沿用原有栅格延迟。独立 BANK 和 WT POSITION 都能改变对应 OSC 的曲线；关闭振荡器保留原有静音显示。
- `ui_top_renderer.v` 将已有 A/B BANK 状态接入预览；WT POSITION 仍取原来的显示参数，不改变控制发送。
- `audio_controls_renderer.v` 移除遮住整个曲线区的占位层，改在顶部显示 `LOCAL SD PREVIEW`，原 WARP 菜单和底部 BANK 控件优先级保留。

## 检查命令

```powershell
python tools/import_wavetable_catalog.py D:/github/gaoyun/WAVEBANK.WTB
python tools/test_wavetable_preview.py D:/github/gaoyun/WAVEBANK.WTB
python tools/test_wavetable_preview_pixels.py
python tools/test_six_fix.py tb_audio_protocol_alignment tb_audio_controls_renderer_integration tb_lfo_sysex_tx tb_audio_controls_pixels
python tools/test_ui_elaboration.py
```

所有新测试产物放到 E:/gaoyun_builds；不修改或删除源 WTB，不触碰硬件。测试覆盖从真实 WTB 独立计算的327,940个采样检查（10张×128档×128相位×双OSC，加缓存/边界场景），有符号插值、端点、越界钳位、更新中再次修改、双缓存原子切换、A/B公平性及复位。像素测试以改动前提交 `d963ff4e32d309182050ed018dfc3974355b6f5d` 的 OSC 渲染器为基准，检查四种原波形，并生成三组生产OSC/文字层合成截图。

### 已完成证据

- `E:/gaoyun_builds/wavetable_preview_20261031_235537_097951/result.json`：327,940采样检查PASS，目录可重现生成，工作区哈希匹配。
- `E:/gaoyun_builds/wavetable_pixels_20261031_235537_145894/result.json`：32,768组原OSC hit/RGB/延迟与前置提交逐拍一致，三组实际RTL截图均生成且逐张检查。图为仿真，不是实板照片。
- `E:/gaoyun_builds/six_fix_20261031_234755_756265/result.json`：音频协议对齐、生产renderer触摸/绑定/UART集成、LFO SysEx和覆盖层像素四项PASS；含74项启动CC、WARP/BANK/FX/PITCH/PAN/Note及831,672个覆盖层像素。
- `E:/gaoyun_builds/ui_elaboration_20261031_234755_757642/result.json`：normal/debug完整顶层与官方原语/DDR仿真桩展开PASS；这不是DDR实机或时序验收。
- `sd_00_09_position_000.png`、`sd_00_09_position_127.png`、`sd_05_03_position_064.png` 位于上述像素目录，显示A/B不同表与不同位置的曲线，菜单和编号区域保留。

## 旧测试与限制

- `test_osc_pixels.py` 原先引用的历史对象 `542cdeb` 在本地不可用，不能宣称它通过。新像素测试使用可验证的本轮前置提交。
- `test_video_alignment.py` 的旧固定边框颜色断言在 cycle19 失败。已在改动前 `d963ff4` 的隔离副本复现完全相同的 actual=181c24 / expected=384256，证据 `E:/gaoyun_builds/wavetable_baseline_alignment_20261031/result.json`；不是本轮新增预览导致。没有为通过测试而更改生产边框。
- 首次双完整 UI 实例的额外像素比较无进展，已停止本轮两个专属仿真进程，保留 `wavetable_pixels_20261031_235201_938869`。改用对应 OSC 和真实文字覆盖层的隔离比较；正常/调试完整顶层另做层次展开，真实触摸/UART链路另用生产集成回归。
- 源码中的20KiB指预览数据量，不是对最终BSRAM/LUT占用或Fmax的承诺。具体资源推断和时序仍需后续明确授权的Gowin构建与完整审计。
- UI没有音频板BANK加载状态或文件哈希回传。更换SD文件后需重新导入同一WTB生成预览，避免显示数据与声音包不一致。
- 本轮不修改安卓 App；0.2.5 的蓝牙握手修复仍保留。
