# 统一功能版时序修补（2026-10-31）

## 首轮证据

源码97d2b37；normal工程`2_ui_touch_hub.gprj`、顶层`ui_touch_hub_top`。构建`E:/gaoyun_builds/R16A_build_20261031_211342`，审计`audit_20261031_213750_461223.json`：15个setup端点，最差-1.302ns；pixel46.944/50MHz、DDR88.640/100MHz未达标。其余四类检查通过；124引脚、116项输入一致。该位流未部署，原目录和全部证据保留。

实际gowinsynthesis/place3/route1/timing/correct_hold1配置与前次成功工程一致。本轮失败不是默认EDA选项选错，也不能通过重复相同输入保证改善。

## 局部修改

1. `audio_controls_renderer.v`：页选→参数ID→参数读取→十进制字形原来同拍完成，15层组合逻辑。数字和条宽改用已有`cell_values`寄存输出，控制显示多一拍收敛时间，50MHz下20ns。文字范围检查`tx<192`移到已有`tx1`后的下一拍；没有新增像素流水拍数，仍保持五拍对齐。参数状态、UART协议和页面坐标不变。
2. `ddr3_user_port_adapter.v`：`accept_request`原来同时驱动317位地址/数据/mask寄存器和控制状态，STA显示约330扇出并拖慢上游FSM。宽payload改为adapter空闲时采样，接受请求的边沿仍采样当前有效payload，busy期间保持；`accept_request`只更新少量事务控制。命令和数据握手时刻、响应延迟均不变。无效空闲采样不会拉高命令使能。
3. `tb_ddr_adapter_payload.v`：生产adapter新增独立回归，请求接受后立即改变输入，并分别检验command-first、data-first、同拍握手、读返回/末拍错误、未校准/valid-low和中途复位；不得重复接收或提前返回。

未修改PCM store状态机；其即时响应、最终watchdog边沿响应优先、失校准、超时隔离和复位行为保留并重新验证。未修改音频RTL、LFO/ENV编码、目标编号、五FX/PITCH协议或引脚。

## 验证边界

最终33种bench全PASS且源码快照一致：`E:/gaoyun_builds/six_fix_20261031_214529_142128/result.json`（9项，含生产adapter/PCM store/录音全链与画面/音频协议）和`.../six_fix_20261031_214657_010510/result.json`（24项，含LFO/ENV/校准/三模式/手机/UART及PCM capture）。八张完整PPM画面与修补前21:03快照逐字节相同，证明所有831672个像素和原五拍流水对齐。PCM store额外7/13时钟比`pcm_clocks_20261031_214738_225263`通过。normal/debug展开`ui_elaboration_20261031_214633_754215`通过。手机软件回归17项源输入及APK0.2.4哈希重新核对一致，没有重新把旧代码的结果冒充新代码结果。

受影响像素/协议/DDR/录音完整链及原有LFO/ENV/手机/校准回归需匹配最终源码快照。normal/debug层次展开使用官方原语和DDR stub，仅用于接口检查。新normal隔离构建必须重新审计setup/hold/recovery/removal/pulse、七时钟、124引脚和输入哈希；通过前禁止部署。

后续构建、审计和唯一SRAM2部署结果以CODEX_HANDOFF顶部及`UNIFIED_RELEASE_2026-10-31.md`为准。烧录不等于安卓、灯带、整曲DDR和音频听感的现场验收。


## 第二轮失败与追加修补（22:20）

7bf3b60 / `R16A_build_20261031_215327` 已22:16退出0，审计271 setup，worst -3.105ns；DDR76.306/100MHz、pixel48.414/50MHz，其他四类/116输入/124引脚通过，未部署。STA实证：busy/Q扇出320，之后读完成门控扇出257，最差为busy反馈自身；前次仅把宽使能从accept挪到busy，没有根治扇出。另有x0→valid1的22层路径含4.219ns DSP和长文字有效优先链。

追加修补：317位请求payload分成每组最多32位，每组独立`idle`寄存器用syn_preserve/syn_keep保留；与主busy状态同周期更新，避免单点宽扇出。返回数据无条件寄存，只有rsp_valid时可见，消除读完成驱动256位使能；响应时刻不变。效果器标签和WARP菜单的列/行坐标由乘法改成等价常量选择，不增加像素拍数。相关回归及下一轮物理审计尚在进行，不得提前声称时序闭合。

22:26追加修补验证完成：9项`221913_674315`、24项`221939_307389`和normal/debug `221913_697287`均PASS，所有输入重新匹配工作区；八张画面与上一检查点逐字节相同。准备保存新源码检查点后启动唯一normal构建，尚未时序闭合或烧录。
