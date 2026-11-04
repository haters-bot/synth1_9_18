# 交给音频队友：接入已有 C19 Note 解析输出

2026-10-31实际fetch的origin/main=5224279，`src/top.v.v` 中 `u_control_cc_parser` 已解析 C19/31250 MIDI，但 note_event_valid/on/channel/note/velocity 全部未连接。现有发声Note只合并USB-UART与E19实体键，因此UI试听发来的Note被忽略。

用户已选：队友补齐C19 Note接收；本轮Codex只完成UI并烧UI SRAM，不修改音频工程。

请保留协议、E19键盘、CC/SysEx与当前双声道/ENV逻辑，只将上述已有Note输出接入有序事件合并队列，再进入现有 `midi_note_event_*` / note路由。多个来源同周期到达不得用简单优先mux静默丢失。当前8项双入口control_event_merge可以级联合并或按现有架构扩展；确保Note On/Off每源顺序，不能把Note导入CC队列。

UI发送：

```text
31250 baud / 8N1 / 3.3 V / 空闲高
90 1D 64   MIDI29 Note On，velocity100
80 1D 00   MIDI29 Note Off
```

试听模式会发送曲谱Note，并在Stop/Pause/重新播放/切模式时释放已发音符。FOLLOW与PERFORM不发送曲谱Note。键盘模块TX仍直接到音频E19，UI F15仅并联监听，不再转发实体Note。

建议验收：C19串行Note29/60 On/Off、velocity0、Running Status/realtime、Note与CC/14bit SysEx/Commit交错、E19和C19并发、停止无粘音、ENV1 CC24～27及ENV2 CC32～35、既有音色CC无回退。请按音频板自身构建/时序/部署流程处理；UI仿真不能代替这段接收链的验收。
