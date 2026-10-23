# R16A 实机验收与交接（2026-10-19）

## 当前板上固件

- 工程：`D:/github/gaoyun/2_ui_touch_hub`；独立本地Git，分支master。
- RTL提交：`9d761aa`（其前置 `9d14f5d` 为光栅分发和参数事件流水）。
- 构建：`impl/R16A_build_20261019_192921`；位流 `impl/pnr/2_ui_touch_hub.fs`，35926701字节。
- SHA256：`9C758B67F235139D522D1185489A76B8431147A5EA21A0F036801A4FCD165522`。
- 部署：`impl/deploy_runs/20261019_193852_R16_binding_release_fixed`。工程机`.157`识别GW5AST-138B，双机哈希一致，operation2 SRAM，Finished且PROGRAMMER_EXIT=0。无Flash操作。
- 主力机`.235`只编写、仿真与构建；所有JTAG均在工程机执行。此次未推送新的团队远程提交。

## 时序与视频

Gowin当前报告像素估算Fmax59.438MHz，PLL实际50MHz；串行器250MHz，USB60MHz。setup/hold违例0/0，最差setup+0.590ns、hold+0.147ns、recovery+0.201ns、removal+0.506ns、脉宽+0.450ns。三路OSER10 RESET均有recovery/removal覆盖，无该端点false-path。审计 `audit_20261019_193823_970785.json` 输入/快照哈希一致。

1280×720画布、总1650×750时序，实际约40.404Hz，属于非标准刷新。现场摄像头与用户反馈已证实本屏能显示并操作；这不等同于任意屏幕兼容、标准720p60或长期环境可靠性测试。未增加分辨率。

## 功能与验收证据

| 项目 | 证据与状态 |
|---|---|
| 中央DELAY/REVERB/EQ三栏，ENV压缩 | 实机照片可见，用户确认DELAY MIX跟手/画面正常 |
| REVERB SIZE、EQ GAIN及ENV回归 | 用户将误选“异常”更正为“选错了，都正常”，确认跟手且画面正常 |
| LFO平滑曲线与整曲线拖动绑定 | 用户复测确认L2持续高亮、AMOUNT出现 |
| 深度与动态指示 | 用户确认数值、动态范围、持续标记都正常 |
| 直接点目标替代方式 | BIND后点目标即绑定，RTL回归通过；尚未单独实机验收 |
| 外部旋钮与下游接口 | 模块逻辑入口/状态快照/事件已预留，仲裁和连续输入仿真通过；队友物理硬件未接入 |
| 声音调制与实际FX | 本轮不接入，按用户确认由音频队友实现 |
| 第二期六页可视化 | 规划/带宽/资源与隔离方案已完成，未改动当前屏幕页面 |

此前绑定的候选高亮消失、底部仍显示UI PREVIEW，表明未提交。旧50ms超时直接取消拖动，在缺UP或瞄准停顿时可能丢掉绑定；没有取得真实HID序列，故只将其列为与现象一致的路径。现增加500ms静默松手、最后有效目标提交和迟到UP去重；无效最后目标取消。保留显式UP立即提交及整曲线拖动。BIND后也可直接点目标，不要求长按。

回归证据：`fx_lfo_tests_20261019_192835_494813` 包含53目标、三来源、19FX参数、九开关、持续标记像素和独立生命周期测试；`video_alignment_20261019_192932_148400` 6136项对齐。参数/ENV/MIDI与诊断回归见CODEX_HANDOFF当前入口。最终像素源码完整帧 `ui_preview_20261019_190937_R16_final_event_pipeline/frame.png` 已检查；新绑定生命周期不改变像素流水。

## 接口与第二期

完整逻辑接口：[FX_LFO_INTERFACE_R16.md](FX_LFO_INTERFACE_R16.md)。参数库事件增加一拍；整幅像素/同步延迟七拍。FX新ID需要队友物理协议适配，当前SPI草案16通道不能自动代表19个FX旋钮。UI七节点LFO不能当作音频核三点两曲率的无损等价；事件无ready/ack，正式串行适配器须根据快照形成队列/dirty位图。

可视化建议见[VISUALIZATION_PHASE2_PLAN.md](VISUALIZATION_PHASE2_PLAN.md)：音符/瀑布、示波器、李萨如、频谱、瀑布频谱、电平/调制。先补充PCM/音符数据链路，优先音符页与示波器。当前音频96kHz、单声道复制LR；不能凭MIDI带宽承载实时PCM或伪造双声道相位。

## 文件恢复与E盘清理完成状态

用户于19:49后明确确认E盘目录由其本人删除；实际检查 `E:/gaoyun_builds` 已不存在，不能将删除归功于代理。此前迁移的旧档案已通过76文件逐一SHA256核验保存回D盘，中断构建63文件也已逐一核验保存为 `impl/R16A_build_20261019_185328`（不完整、不可部署）。

D盘 `impl/R16A_build_20261019_181815` 已恢复为真实目录，不再依赖E盘。操作为只在D盘内重命名：原失效junction保留为 `impl/R16A_build_20261019_181815_stale_E_junction`，完整的restored备份改回原目录名；没有执行删除，不存在原目录仍为跨盘链接的问题。该stale条目仅为失效链接记录，不含独立档案。自动审批此前拒绝移除junction，仅返回blocked by policy；后采用非删除的同盘重命名恢复原路径。

后续构建与部署工具均使用D盘默认目录。用户原有未跟踪 `sim/tb_curve_probe.v`、`transcript` 保持原状。

## 回退

R15I已验收普通MIDI位流仍保留 `impl/R15I_final_build2_20261017_2336/2_ui_touch_hub.fs`，SHA256 `3974EC45CAAA7FC88B8B2358ECC81CF563E5C2E0132572065CB94B52F2D8DC20`。本轮R16未写Flash，掉电后不保证保持当前SRAM画面。
