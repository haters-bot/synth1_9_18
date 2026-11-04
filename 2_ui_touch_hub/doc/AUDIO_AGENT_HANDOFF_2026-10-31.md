# 给音频板 Agent 的协议交接（2026-10-31）

> **21:05 最新音频基准已更新为dbffe3768fa29405ad50845d4e915577d1c16557。** fetch确认790d131已加入C19 UART Note解析，因此不再只是用户口述修复；UI自身仍未改音频RTL。dbffe37的midi_note_parser/synth_control_router/lfo_target_router_v2与原5224279一致。UI将CC82/83/84颤音开关/速率/深度、CC85/86滑音开关/时间集中到第五效果器后的第六PITCH页；开关0/127，参数保留原0～127。五FX/WARP/波表/PAN/校准会一起构建，53个LFO目标号不扩展，音频协议不变。下文旧基准及“C19待准确commit”属于此前历史；各功能边界和未适配功能列表仍保留供共同审阅。

> **起音/曲谱适配更新（覆盖此前固定起音/超宽折叠结论）：** UI新增每次蓝牙连接后的显式校准，在演奏页CALIBRATE后从F15真实Note On取最左键。只接受0x29/0x35/0x41/0x4D，对应32键41～72/53～84/65～96/77～108；0x59按用户实测排除。App整曲统一移调，含两端音域≤32才允许上传，>32警告并拒绝，不折八度、不丢音。换校准前UI停止旧曲，并按原绝对MIDI音高释放旧Note；实体跟弹、试听和灯屏共享runtime base。此为UI/手机协议扩展，不改音频Note/CC/LFO或53目标号；音频侧沿用既有按收到音高合成。新功能未EDA/烧录，不能当作已完成双板现场验收。具体实现/验证见 `MIDI_RANGE_ADAPTATION_2026-10-31.md` 和CODEX_HANDOFF顶部。

UI源码／仿真阶段已完成，尚未做本轮Gowin构建或部署。端到端仿真、静态74项启动序列和旧LFO/ENV/UART回归全部通过；细节与真实数据见同目录`PROTOCOL_ALIGNMENT_2026-10-31.md`。本交接列音频团队需要审阅或共同决定的差异，不是要求一次性全部实现。

## 基准与已完成项

UI分支 `integration/dual-138k-uart-phase1`，本轮基于 `1a8ced1`。可见音频 `origin/main=52242799c1bc8b0ee411a2de39600408472b3219`，已fetch核对。UI通过提取该版本真实`midi_note_parser.v`／`synth_control_router.v`进行串行端到端回归。仅修改UI，未改音频RTL、CC协议或53个调制槽的编号。

本轮补齐：WARP mode A38/B40（amount仍39/41）、SD index49/50且wave21/29=127、FX mode51与58～81全参数、Vibrato82～84、Portamento85/86。原A/B Phase/Rand87～90、三PAN10/91/92、ADSR24～27/32～35、Delay/Reverb52～57保留。启动74项静态CC后再原81帧LFO全同步；仲裁及已修LFO常量切片保持。

用户已告知C19 Note接收由队友修复，因此不再要求重复修。请后续提供对应新commit，双方共同冻结基准。下列差异按可见5224279而非推测中的新固件列出。

## A. UI已有操作，但音频没有相应静态控制协议

这些本地显示／状态已有，不代表声音已实现。当前UI发送器会过滤不支持ID，不擅造CC。

| UI功能 | 当前状态 | 音频侧需确认的事项 |
|---|---|---|
| OSC A/B OCT、SEMI、FINE | 本地值可调，未接音高CC | 是否加入每OSC transpose／fine偏移；需区分Detune（Unison散布）与整体调音，不能复用CC22/30冒充 |
| OSC A/B BLEND | 本地状态／图形，音频无该参数 | 需先定义Unison主声部与旁声部增益模型及协议 |
| Macro1～4 | UI有值，音频无映射矩阵／目标 | 确定矩阵和协议后再接；不能仅分配四个CC就声称Macro生效 |
| Filter Drive／Fat | UI有参数，原音频router无对应CC | 不将全局Distortion Drive(CC60)当作滤波器Drive，拓扑位置不同 |
| Filter Route A/B/N/S、Keytrack | 本地按钮，音频无对应路由／键跟踪协议 | 当前共享全局滤波器不是每OSC独立滤波，需双方先定DSP结构 |
| ENV1/ENV2 Hold | 本地AHDSR状态，音频ADSR无Hold | 目前刻意不发CC；是否添加阶段需音频核心与时长映射一起设计 |
| ENV3 | 本地包络，音频没有第3套振幅ADSR | 保留本地，不与OSC A/B包络混用 |

不要把“LFO目标NC”误解为静态参数也无效：Unison静态CC23/31、ENV1/ENV2静态ADSR都已接入。

## B. 53目标中29项仍未接入音频LFO

0起计的target索引；音频SysEx路由参数ID=73+target，value=(source<<8)|(depth&255)，7bit MSB/LSB，Commit126。以下保持固定槽位、灰色NC并禁止新绑定，原状态不压缩、不改号。

| target | 项目 |
|---|---|
| 0～3 | Macro1～4 |
| 5、7 | OSC A Unison、Blend |
| 14、16 | OSC B Unison、Blend |
| 25 | 旧 Filter Pan槽（静态内部ID已作为MASTER PAN/CC10） |
| 26、27 | Filter Drive、Fat |
| 29～33 | ENV Attack／Hold／Decay／Sustain／Release调制 |
| 36～38 | Delay Right Time、Filter Freq、Filter Q |
| 42～45 | Reverb Low／High／Spin／Depth |
| 47～52 | 旧EQ六参数 |

已接24项：4、6、8～13、15、17～24、28、34、35、39～41、46。A/B PAN为12/21已接，MASTER PAN旧25仍NC。当前UI不把旧EQ六槽重新解释成新Distortion，避免合法旧SysEx改变含义。

新Distortion／Phaser／Chorus／Compressor为静态可控，53槽中没有其调制入口。如需新增，建议另增版本能力查询／目标扩展，双方确认后实施，勿静默挪用旧目标ID。

音频 `docs/global_effects.md` 中“Delay/Reverb尚未加入LFO”是旧描述，与真实`lfo_target_router_v2.v`支持六项不一致，应更新文档；UI以RTL为准已保持六项可绑。

## C. SD波表目录／真实状态回传缺失

用户提供WTB：10表，256×256×16bit LE，1,310,752字节，SHA256：

`59a09d279c4a55883cb92085a890e405e0b3494d5b03048ffad6765c05ae2a90`

已对照音频打包工具验证。WTB1没有名字；UI编译时目录只用00～09，不冒充能读SD。CC49/50音频允许0～15／越界钳最后一张，UI按本包0～9循环。换SD包需同步UI目录。

后续可讨论回传：协议版本、WTB数量／哈希／表名索引、DDR calibrated、SD init／loader错误、cache ready、当前选表和WT Position。当前没有这条通用readback协议；不能声称UI看到SD就绪。音频加载器选根目录第0个普通文件，建议双方板测核验真实加载文件及hash，不仅核验文件名。

UI常规scope为示意，SD时明确无预览。若要显示真实WARP/WT波形，需要轻量波形缓存回传；不需要为了绘图把整份WTB复制到UI FPGA。

## D. Stereo/PAN DSP边界

三路协议已对齐：A91、B92、Global10；0/64/127=左/中/右。UI修复中心64的9°视觉右偏，显示C，不改发送数值。

音频现有中心不衰减线性平衡律与Serum/equal-power不是同一条law，中心左右各1.0。UI不擅自重映射为63或补偿声道。若用户仍听到偏声，请抓三CC实际值并旁路FX、只开一个OSC、用双声道I²S样本比较，避免把两个OSC的不同音色／相位误判为PAN编码错误。

实际拓扑是A/B分别PAN→Mid/Side；Mid走共享全局Filter/五FX，Side干声旁通→重构L/R→Master/GlobalPAN。结果：全局FX不是完整立体声，硬PAN时非线性或湿声可跨到对侧；特定反相信号Mid趋0时全局效果可能减弱。若需要声像与效果严格独立，要评估双声道FX或M/S一致处理的资源与时延，属于音频设计事项，本轮不改。

## E. 启动同步、掉电和ACK

UI复位会依照自身默认／状态值发74项CC，再发81帧LFO；音频reset默认与UI不同的参数（如wave/level/ADSR）最终由UI覆盖。已验证FIFO拥塞中身份稳定、最新状态收敛、Note优先、SysEx不中途拆帧。

这条MIDI参数链没有一般ACK或readback。如果音频单独复位而UI不复位，UI无法发现丢配置，不会自动凭空知道需要全量重发；若需要恢复，后续加共同约定的ready/version/reset通知或用户明确的重同步操作，勿与现有重启LFO命令混用。

同样，当前UI不知道队友实际烧的版本。后续至少提供构建commit／协议版本证据，再决定是否正式新增能力协商。

## F. 演奏／录音的职责

UI当前已具试听／实体跟弹／按时间演奏模式、19白键灯、手机MIDI上传与I²S录音回传。19:59用户已澄清最低音29为十六进制：默认MIDI41～72（0x29～0x48），最高八度档MIDI89～120（最左0x59）；UI源码默认起音已纠正为41但尚未重新上板。App0.2.3自动移调/超宽折八度，练习仍使用键盘默认档；详情见MIDI_RANGE_ADAPTATION_2026-10-31.md。音频不需要重做手机协议。试听由UI输出普通Note，需队友已修C19入口。实体键盘TX可并联两个RX监听，不能将两个TX短接。

录音采音频板I²S最终输出进UI DDR，回手机为低采样率WAV，不使用手机麦克风。UI协议ACK只证明UI手机链包接收／读回，不证明音频DSP参数已应用。

## 建议队友返回的最小信息

1. C19 Note修复对应commit／当前烧录版本，及未改变的31250baud、Note通道1、CC通道16。
2. 音频SD实际加载的WTB是否与上述SHA一致、10表均ready。
3. 对A/B Pitch／Blend／Filter路由／Hold等未定义功能的优先级；确定后再共同新增协议，当前不要求一轮全补。
4. 是否接受现有Mid-only FX边界，或计划真正的立体声FX；这决定PAN问题后续怎样验收。

本文件供用户转交，Codex未自动向其他聊天或他人发送消息。
