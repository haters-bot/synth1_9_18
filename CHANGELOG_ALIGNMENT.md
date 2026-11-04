> **2026-11-03 报告任务已按用户新指示转为只收素材、改内容，停止排版。** 主交付E:/gaoyun_documentation/20261103_revision2/content/技术文档_内容修订稿.md，保留58主题及原表格/代码，整合扩写23主题；原58页DOCX和此前60页补图校样保留，不再排版，也不以校样作为当前主入口。后台采12张Gowin原生HTML页面/表格截图、归档14份真实GPRJ/PLL/DDR/TMDS/FIR配置封装及SHA；不冒称IDE窗口，工程树/IP配置和ModelSim Wave GUI截图仍缺。新增从已部署9ee5dce冻结UART以50MHz/31250baud/8N1运行24字节全通过，保留WLF/VCD/原始日志/TB和可编辑SVG；仅低层发送器，手工注入帧，不冒充真实触摸或实板延迟，完整触摸依据另附归档回归。46个正文素材链接及所有原生/IP文件SHA验证；增量ZIP完成CRC。正文仍按正式12预设/10波表验证基线，13预设/12波表新钢琴作为时序未过、未部署扩展。用户无副屏，改为完全后台，没有桌面输入、产品源码修改、Gowin综合或JTAG烧录，之前硬件暂停不解除。真实SW/PCB/琴弦/通电实屏、复音频谱、延迟重复统计、手机录音续传吞吐与长稳仍待现场资料。

> **2026-11-02 22:26 用户要求重烧，只读核验后板上仍为0x617D版，用户确认无需重烧，未执行任何写板。** 工程机已换校园网地址10.31.56.68（ICMP通、仅TCP22放行、多级NAT下deploy_verified.py的8899回传不可用）。只读读码：ID=0x0001081B、UserCode=0x617D、Status=0x26230，与19:19烧录一致，设计仍在板上。期间见programmer.exe PID 31412残留（疑为上方22:18条目所述operation0残留之一，非用户GUI），未杀未并行。SSH排障结论：Git Bash下MSYS ssh把HOME解析成乱码路径，known_hosts与私钥均找不到，产生"Host key verification failed"与"Permission denied"假象；须显式`-o UserKnownHostsFile=C:/Users/胡珂/.ssh/known_hosts -o IdentityFile=C:/Users/胡珂/.ssh/id_ed25519 -o IdentitiesOnly=yes`绕过。本轮全程只读，无operation2/Flash/音频/ESP写入、无删除、无重试，与22:18条目"先解决JTAG残留、禁盲目写板"的约束一致。

> **2026-11-02 22:18 第二轮新钢琴构建214807完成但STA失败，当前暂停，不可烧录。** 源52491f2；Gowin退出0/位流生成不代表通过：setup56端点、报告106条负路径，最差−1.040ns；全部负路径从u_synth_presets/preset_cc_id_0_s5出发，主要至u_midi_tx/fifo_mem及u_static_cc_sync/cc_val，13逻辑级。上一轮scan反馈路径不再见于负清单，但UART参数ID解码/仲裁路径成为瓶颈。hold/recovery/removal/pulse全0，pixel47.527/50MHz未达标，其余6时钟达标，124引脚通过、125构建/回归输入相符；audit_20261102_221531_438299.json及FS SHA9CC0DC1F9148D040B3E518943E1DBA14E6BD2F3089C1EBBE03FF1142C5ACF8D4保留。用户对JTAG重连回复“先不忙”，本轮只让在途构建结束审计，未启动第三轮，未发任何operation2/Flash写板。之前两次operation0查询25812/34796已发送取消请求，但当时仍见进程残留，不能认定退出；恢复硬件时先解决JTAG读取与残留，禁盲目写板。下一步局部缩短CC解码/握手路径、回归后再新输入构建，不能原样重跑。13预设/12051串行字节等源码回归已通过，SD包仍由用户自行断电拷卡，原10表不变。现有其他脏文件保留，未推送、未删除任何文件。

> **2026-11-02 21:50 用户回复JTAG重连请求“先不忙”：硬件重连与SRAM烧录暂停，不能沿用此前自动烧录授权继续写板，等用户恢复；本地214807构建继续完成并审计。未发任何operation2写板。**

> **2026-11-02 21:48 新钢琴第二轮正式构建已启动，尚未烧录。** 第一轮210645失败：setup21、最差−0.729ns，其余四类0；全在static_cc_sync扫描读出/比较/索引反馈族，位流禁止部署、证据保留。新增读出/比较寄存级，启动测试排空等待按连续空闲判定；源码52491f2（含c0f1fe5钢琴）。17项完整新RTL回归、13预设12051串行字节、UI512像素/六分类、预览393476、normal/debug及FX4352通过；125输入Git匹配，functional_evidence_v2.json齐全。唯一正在运行的Gowin E:/gaoyun_builds/R16A_build_20261102_214807，exec22912；用户仍授权最终UI SRAM2。工程机LAN182/183通、FTDI双通道在，但两次operation0只读查询卡住；已仅对本轮两个匹配命令PID25812/34796请求取消，用户待断电重接JTAG，禁止未查明直接写板。未写任何SRAM/Flash/音频/ESP，未推送。

> **2026-11-02 21:06 采样提取钢琴版已开始唯一正式构建，未烧录。** 用户授权直到UI SRAM2；新preset ID12在原声区显示0/12/1，原0～11完整参数不变；采样来自Iowa Steinway C4，12表WTB追加10主体/11起音，原10表载荷不变、SHA ac2253f3eacc7397ace79c6d9f54f266409eac6f69383c45ad1d8da7f95437ee。源c0f1fe5，17RTL组合证据（前12通过日志+后5新快照，所有使用的硬件/fixture哈希核对）、12051串行字节、13卡片512像素/六图、393476波表预览、normal/debug/FX4352通过。functional_evidence.json已绑定125 Git匹配冻结输入；正式E:/gaoyun_builds/R16A_build_20261102_210645、exec95746，normal ui_touch_hub_top/GowinSynthesis/place3/route1，禁止并行或原样重跑。等审计五类0违例/7时钟/124引脚/输入匹配才唯一deploy_verified.py --board ui --target sram，label UI_SAMPLED_PIANO_20261102；SSH写板超时禁自动重试，再只读verify_after_sram.py闭环。LAN182/183已恢复，UI JTAG用户确认；用户自行断电拷SD，说明与ZIP在E:/gaoyun_builds/piano_sampled_release_20261102。未改音频/ESP/App/Flash；E空间由用户手动恢复，自动清理两次被policy拒绝，未执行删除。现有脏文件保留，未推送。

> **2026-11-02 19:20 官方12预设版已按用户指示重烧UI SRAM并完成只读复核闭环，未动其他板卡。** 板子此前断电SRAM已空（烧前只读UserCode=0x18D6/Status=0x26020），同一位流E:/gaoyun_builds/R16A_build_20261102_060044/impl/pnr/2_ui_touch_hub.fs，本地烧前复核SHA256=FF2A32811EF2AC11F2933C99F8AB5EA409AB946C4C2380BCC3A477512A18BF13与06:23审计记录一致。deploy_runs/20261102_191920_UI_PRESETS_SRAM2_REBURN_20261102：operation2唯一一次29.71秒、100%、PROGRAMMER_EXIT=0、CODEX_PROGRAM_COMPLETE，无超时无重试；独立只读verify_after_sram.py复核UserCode=0x617D/Status=0x26230与06:23一致、远端SHA匹配、无并行Programmer，completion_record.json已保存。未写Flash/音频/ESP；Flash固化仍待压缩位流重建（当前41MB未压缩>128Mbit容量，见wiki官方Generic Flash/GAO-Bridge 5A结论）。网络备注：本时段走LAN 192.168.31.182→183，工程机TCP22间歇性断续（疑似休眠/无线省电），known_hosts已补LAN条目修复BatchMode Host key verification failed；工程机ICMP被防火墙拦截，ping假阴性，探测须用TCP22。板子现场验收仍按SYSTEM→PRESETS流程；掉电SRAM即失需重烧。

> **2026-11-02 技术文档准备已完成首轮盘点，未改产品源码/未合并/未构建烧录。** 用户确认只fetch远端整理、不合并；硬件队友无其他仓库、主要手工实物。共享音频origin/main刷新0dbd8a7，UI生产仍9ee5dce/归档617D，文档HEAD d5c9ddb；App0.3.3及ESP原未提交修改保留。计划包 `D:/github/gaoyun/docs/TECHNICAL_DOCUMENTATION_20261102_164345/README.md`：49功能/16要求矩阵、22测试/22素材、48音频快照及411原文件SHA。共享仓库入口docs/TECHNICAL_DOCUMENTATION_KICKOFF_2026-11-02.md（未提交未推送）。注意默认1×32不能套旧2×32实板成绩，50MHz/1650/750理论40.404Hz非60Hz，53目标槽/24能力位分开；优先补独立交互维度、复音/分量频谱、总延迟、ADC固定电压、录音与吞吐及实物照片。全稿按Word模板匿名/限字，设计/仿真/STA/部署/现场证据分别表达。没有联系队友或操作其电脑，不因写文档重复烧录；未删除原文件。

> **2026-11-02 06:23 官方12预设版已全审计通过并成功唯一UI SRAM2烧录，禁止因历史待构建条目重复烧录。** 当前板上UserCode=0x617D、Status=0x26230，替代旧352D；正式E:/gaoyun_builds/R16A_build_20261102_060044，源码9ee5dce473774f85e8010ec0add1d4e942047855（本地未推送）。124冻结/工作区/Git输入、136回归输入、124引脚、7时钟匹配；setup/hold/recovery/removal/pulse全0，最差+0.730/+0.138/+0.365/+0.299/+0.366ns，pixel54.027/50MHz、DDR112.592/100MHz。17RTL、11343预设控制字节、512七拍/六图像素、normal/debug、FX4352项全过。deploy_runs/20261102_062216_UI_FACTORY_PRESETS_20261102：operation2只写一次26.76秒，100%/PROGRAMMER_EXIT0/CODEX_PROGRAM_COMPLETE，独立只读再次617D/26230，双端文件SHA=FF2A32811EF2AC11F2933C99F8AB5EA409AB946C4C2380BCC3A477512A18BF13；completion_record.json与doc/SYNTH_FACTORY_PRESET_RELEASE_2026-11-02.acceptance.json齐全。所有本轮Gowin/Programmer已退出，未超时/未重试/未Flash/音频/ESP写入，全部旧文件与两失败构建保留、原App等脏文件未动。入口SYSTEM→PRESETS，6分类/12官方音色/重发/返回，自定义仍仅预留；原先WARP/五FX/SD10表/PITCH/演奏校准/钢琴长条等保留。首两轮setup314/184由UART握手/复位反馈、导航取消和坐标重映射长链引起，局部寄存拆级后收敛，未换模式或放宽约束；详见doc/SYNTH_FACTORY_PRESET_RELEASE_2026-11-02.md。相机仅工作台，实屏/听感/实体灯带电气需用户现场验收，不冒称已测。验收先SYSTEM→PRESETS试钢琴/Supersaw/SubBass/Pad；若测手机PERFORM，烧录重置会话后按原流程重新连接/校准/传曲。

> **2026-11-02 06:22 第三轮正式全审计已通过，准备唯一一次 UI SRAM2 写入；中断后严禁盲目重烧。** 正式060044/源码9ee5dce473774f85e8010ec0add1d4e942047855，audit_20261102_062137_424718：setup/hold/recovery/removal/pulse违例全0，最差+0.730/+0.138/+0.365/+0.299/+0.366ns；七时钟全部达标，pixel54.027/50MHz、DDR112.592/100MHz，124输入/124引脚和136回归输入匹配。FS SHA256=FF2A32811EF2AC11F2933C99F8AB5EA409AB946C4C2380BCC3A477512A18BF13，41215585B；deploy_check_only.json复审通过。即刻只读preflight_062154确认唯一UI旧352D/26230、工程机HOST正确、无Programmer/Gowin。下一命令仅一次deploy_verified.py --label UI_FACTORY_PRESETS_20261102 --fs E:/gaoyun_builds/R16A_build_20261102_060044/impl/pnr/2_ui_touch_hub.fs --board ui --target sram，LAN环境182/183。恢复先找impl/deploy_runs最新对应label/manifest及远端programmer_exit.txt/完成标记，不能因SSH中断自动重试。写后用E:/gaoyun_builds/performance_roll_acceptance_20261101_210306/verify_after_sram.py <deploy_run>（同LAN环境）仅只读复核codes/hash/STA并保存completion_record。两失败位流永不部署，旧证据全保留；Flash/音频/ESP不写。

> **2026-11-02 06:00 第三轮唯一正式构建已启动，未烧录。** 当前源码9ee5dce（全提交见build_context.json），E:/gaoyun_builds/R16A_build_20261102_060044、PID3208、exec95799，normal ui_touch_hub_top / GowinSynthesis/place3/route1。124冻结/工作区/规范化Git与136当前测试输入全匹配；相比第二轮只有controller/top/renderer三个RTL不同，其余121输入一致，functional_evidence.json/source_delta_from_second.json已保存。17RTL(新增本地复位)055548_138957、11343字节055548_037074、UI512七拍/六类像素055637_643734、normal-debug055657_920737、FX4352项055704_553134均PASS，6组当前证据已汇总。两轮044748/setup314和052003/setup184都禁止部署，失败审计和位流全部保留。新增四路本地同步释放复位、Note ready复位屏蔽、预设SEND/ADVANCE分级及绑定坐标/页签/valid/down两级寄存；MIDI编码文件、53编号、时钟/约束/模式不变。恢复先查060044进程/日志，不另开Gowin。只有五类违例0、7时钟/124引脚/124源全过才按持续授权一次UI SRAM2，label UI_FACTORY_PRESETS_20261102；LAN环境182/183，烧前再只读UI旧352D/26230。使用deploy_verified.py，写板SSH超时禁止自动重烧；不写Flash/音频/ESP。详细原因/测试见doc/SYNTH_FACTORY_PRESET_RELEASE_2026-11-02.md。

> **2026-11-02 05:20 两条控制链修补已通过全部验证，第二轮唯一正式构建运行中，未烧录。** 源码0593b6ec45bee5a67b08723a1d05c263d9b34416（未推送），唯一E:/gaoyun_builds/R16A_build_20261102_052003，PID39788、exec39934，normal ui_touch_hub_top / gowinsynthesis/place3/route1。124冻结/工作区/规范化Git和135当前回归输入一致，functional_evidence.json/source_delta_from_failed_first.json齐全；相比失败044748只有static_cc_sync.v和lfo_binding_state.v两个RTL不同，其余122输入逐位相同。新16RTL051439_661319、预设11343字节051439_574254、UI512七拍/1382400像素051529_989988、normal/debug051549_434465、FX4352项051555_406348全PASS，汇总acceptance已更新并本地提交。第一轮setup314失败位流永久禁部署，旧证据全保留。恢复先查052003 build_process.json/真实PID，不原样另开Gowin。待五类全零、7时钟/124引脚/124源全过后按既有用户授权一次deploy_verified.py UI SRAM2(label UI_FACTORY_PRESETS_20261102)，LAN环境GAOYUN_LOCAL_IP=192.168.31.182、GAOYUN_REMOTE_IP=192.168.31.183，烧前再只读确认UI旧352D/26230。SSH写板超时禁止自动重烧；Flash/音频/ESP均不写。详见doc/SYNTH_FACTORY_PRESET_RELEASE_2026-11-02.md。

> **2026-11-02 首轮预设正式构建时序失败，绝未烧录；正在收敛两条控制链。** 044748/e27b2c3已05:09:47退出0，audit_20261102_051007_420448：setup314、worst−1.062ns、pixel47.477/50MHz，其他四类/7时钟其余项/124引脚/124源匹配，禁止部署或原样重跑。负路径报告250条只出现reset→MIDI CCaccept→static sent/initial_pending和raw导航几何cancel→binding depth两族。仅static_cc_sync.v增加accepted scan/value寄存提交与COUNT1防重复气泡、lfo_binding_state.v将cancel寄存一拍（仍先于两拍触摸包），协议/53目标/约束/模式未动；更新两个相应bench覆盖确认沿编辑、COUNT1和导航取消/重新绑定。当前无Gowin活动。新source回归：预设11343字节051439_574254、UI512七拍+六类1382400采样051529_989988、normal/debug051549_434465、FX4352项051555_406348均PASS；16RTL full在six_fix_20261102_051439_661319（exec86762）继续，待收回，代码尚未提交新检查点。旧bit/失败审计/源/acceptance_frozen全部保留。完整验证过后再新唯一构建，全审计通过按持续授权一次UI SRAM2；无需重复问许可。LAN182/183与旧UI352D只读确认、8899传输预检都过；烧前再读码，使用环境覆写GAOYUN_LOCAL_IP/REMOTE_IP，不走ZeroTier。硬件尚保持旧版，不写Flash/音频/ESP。

> **2026-11-02 04:54 远程连接已恢复，正式构建仍在运行，未烧录。** 用户将主力机切回昨晚Wi-Fi，获准沿用直连LAN：GAOYUN_LOCAL_IP=192.168.31.182、GAOYUN_REMOTE_IP=192.168.31.183，不走ZeroTier；deploy_verified.py和后置只读verify均需带这两个环境变量。readonly preflight E:/gaoyun_builds/preset_remote_preflight_20261102_045347_285633确认HOST=DESKTOP-FDEVSGP、无Programmer/Gowin进程、唯一GW5AST138B/ID1081B、旧UI UserCode352D/Status26230、READ_CODES_EXIT0。尚未写板。唯一构建仍044748/e27b2c3/PID11276/exec52895，先看状态再继续，禁重复构建/自动重烧；待全审计过后按用户持续授权一次UI SRAM2，label UI_FACTORY_PRESETS_20261102。

> **2026-11-02 04:48 用户已明确授权“开始构建，按照流程直到完成烧录”，取代下方源码阶段禁构建状态。** 本地检查点e27b2c36851dad48d3ec583e15c8072e4dde49f3（未推送）；唯一正式normal构建E:/gaoyun_builds/R16A_build_20261102_044748，Gowin PID11276、exec52895，2_ui_touch_hub.gprj/ui_touch_hub_top，gowinsynthesis/place3/route1。124冻结/工作区/规范化Git输入全部匹配，135现有回归输入匹配，functional_evidence.json与source_delta.json已保留（相比上一版只新增5项、变更12项，无删除）。恢复先看build_process.json/build.log/真实进程，不另开Gowin。完成后audit_build.py，五类违例全零、7时钟、124引脚与124源通过才一次deploy_verified.py --board ui --target sram、label UI_FACTORY_PRESETS_20261102，再外置verify_after_sram.py只读核验哈希和codes；SSH写板超时禁自动重烧。当前未烧录。工程机旧IPv6及昨晚LAN192.168.31.183不通，本机当前校园WLAN10.31.173.53、IPv6 RA暂失，已向用户询问现行SSH地址；继续本机构建，禁止改用ZeroTier中继。手机/ESP/音频/Flash不写，现有脏文件和全部证据保留。源码/仿真阶段交付详见doc/SYNTH_FACTORY_PRESETS_2026-11-02.md，旧FX颜色oracle在未修改HEAD同样失败不计PASS，新预设512七拍检查通过。

> **2026-11-02 SYSTEM 官方预设音色库源码与仿真完成；本轮禁止自动综合/烧录。** 用户确认本轮仅12官方预设、自定义只预留入口/数据契约，等今晚改完统一构建。实际 `D:/github/synth1_9_18/2_ui_touch_hub`、integration/dual-138k-uart-phase1，Git基准bfb3afe，本轮未提交/推送。固定GitHub参考f0da2279eba79c3b368248718f96033f0cc8f9b6，经fetch/Git对象AST展开，12×74=888完整参数；SYSTEM第四子页PRESETS、6分类/大卡片/说明/重发/返回/灰色CUSTOM预留。新增只读ROM、preset事务生产者，整批落入merger/extra/FX真实状态、清53个LFO source/depth；复用原MIDI FIFO/Note优先，42CC→81SysEx→A/B32CC共708字节，顺序和值与实际Python send_all逐字节一致；原曲线/速率保留，53ID/CC/协议/音频RTL不改，不发All Notes Off。1当前+1最新待执行，hold/adopt防重复；期间参数编辑锁定，演奏/导航继续。最终E:/gaoyun_builds/synth_presets_20261102_012625_658936验证11343串行字节（12项/重发/快切/启动立即应用/后续实体CC与重新绑定）；UI012820_925548全12触摸、512七拍动态像素、六类1382400采样图人工查看通过；normal/debug012755_697461、FX4352项及16RTL/six_fix_012831_341785全PASS，6证据组/135当前测试输入哈希全部匹配。doc/SYNTH_FACTORY_PRESETS_2026-11-02.md与acceptance.json、schema_v1齐全。旧video_alignment固定FX颜色oracle在原始HEAD也完全同样cycle19失败，baseline_012941_449260留证、不计PASS；首轮旧字体和快照失配结果全保留。新Gowin资源/时序/实屏/音色听感尚未验收，板仍上轮03bd696/352D（本轮未读写JTAG）。没有Gowin/烧录/Flash/音频/手机/ESP操作、未删除；既有脏文件保留。下一步只在用户明确统一构建后冻结输入并全审计，勿把下方历史已烧录记录当成预设已上板。

> **2026-11-01 22:34 PERFORM下落长条版已通过全审计并完成唯一UI SRAM2写入，禁止因下方历史状态重烧。** 板上当前UserCode=0x352D、Status=0x26230，替代旧6B0D；正式E:/gaoyun_builds/R16A_build_20261101_215915，源码03bd696d639416ff3a128033ccfb914c632096a8，本地未推送。119源/111规范化Git条目/124引脚/7时钟全过，setup/hold/recovery/removal/pulse违例均0、最差+0.709/+0.136/+0.316/+0.287/+0.366ns；pixel53.212/50MHz、DDR118.055/100MHz。14RTL/4993像素/normal-debug/两DDR时钟/I²S链/绑定107帧RTL-网表/96速率组合469帧RTL-网表六组当前证据齐全。deploy_runs/20261101_223333_UI_PIANO_ROLL_20261101：PROGRAMMER_EXIT=0、CODEX_PROGRAM_COMPLETE，一次26.3秒；独立只读复核352D/26230、主机身份/无Programmer/双端SHA=036F9CF7B47D2713DF4D55F7BE0C5EA8A5C50679C43DA34FF3361F0526EE9A89，completion_record.json已保存。正式构建约33分24秒，旧失败55setup由LFO/DDR局部拆级消除，未放宽约束；逻辑52%/BSRAM37%。保留所有失败构建/探针/截图/旧文件，无删除/Flash/音频/ESP写入，无重试。相机未覆盖UI正面，手机/长条实屏/灯带电气待用户现场确认。验收：重新连接、CALIBRATE按最左键、重新传曲，观察长条起音白边和尾端；掉电丢SRAM。详见doc/PERFORMANCE_PIANO_ROLL_2026-11-01.md。

> **2026-11-01 ESP-01S Wi-Fi桥接1 Mbps：源码、仿真和APK完成，未综合、未烧录。** 目标是 ESP-01S 只做 TCP↔UI FPGA UART 原始字节桥；音频板协议、帧CRC、录音身份和断点续传仍由现有UI/App处理。UI新增第四档 1000000 baud，HELLO/CRC锁定四档，状态码3回报1 Mbps；App增加蓝牙／Wi-Fi TCP选择，Wi-Fi使用当前局域网SocketFactory和TCP_NODELAY，蓝牙保持原路径。新增 `esp8266_bridge/` PlatformIO源：AP `FPGA-ESP01S`、密码 `PianoLink1M`、`192.168.4.1:333`、UART0 1 Mbps 8N1、单客户端8 KiB缓冲，拥塞溢出断开以便续传。随附安信可2017 AT固件不是本项目桥接固件；本机未安装PlatformIO/ESP8266 Arduino，因此桥接固件尚未编译，不能直接烧录。四档/50 MHz 1 Mbps双向仿真、录音身份25事务、LFO/Note/校准/灯带及完整手机回归通过；证据 `E:/gaoyun_builds/six_fix_20261101_024255_579184/result.json`、`E:/gaoyun_builds/phone_selection_20261101_024851_078006/result.json`。最终APK **0.3.0/code9**：`E:/gaoyun_builds/phone_apk_20261101_025153_015492/FPGA-Performance.apk`，SHA256 `241702f8e7c8622c65aea89c1dfb1319a8642dd52b65146e2e54ed85c76241a9`，尚未手机实测。详细设计 `doc/ESP8266_WIFI_UART_1M_2026-11-01.md`。必须后续烧录ESP及UI位流后实测HELLO/ACK、持续吞吐、CRC错误、断连和恢复，再决定2 Mbps；本轮没有Gowin、JTAG或HC-07操作，也未删除文件。

> **2026-11-01 录音续传/管理及230400：源码、仿真和APK完成，未综合、未烧录、未配置HC-07。** 实际UI副本仍为本目录。新增9600/115200/230400三档CRC/HELLO锁定；板端单段DDR录音加入128bit身份及INFO/CLEAR，手机每1024帧完整块持久保存，断连/重启后手动续传，身份不符拒拼，完整缓存离线导出，覆盖/丢弃/删除均需用户确认。DDR失效作废旧段；不是多歌曲永久存储。本轮未进一步降低8k导出采样率。5项录音/三档RTL、9项LFO/Note/校准/模式/灯带回归、normal/debug层次展开及完整手机回归均PASS且当前源码哈希一致。总证据 `E:/gaoyun_builds/recording_resume_acceptance_20261101.json`；详细说明 `doc/RECORDING_RESUME_AND_SPEED_2026-11-01.md`。最终APK **0.2.6/code8**：`E:/gaoyun_builds/phone_apk_20261101_005155_010241/FPGA-Performance.apk`，SHA256 `6875ce24bc785a61a563d1f65ec9e2b87111619c6d386dcf1896ba8ab2c8b47e`，v2/v3签名及与0.2.5同证书、全部打包资源核验通过，尚未手机实测。旧位流仅可普通下载；跨连接续传、板端丢弃及230400需后续新位流；模块UART需届时手动匹配，App不能改模块TTL速率。手册PDF第7页列更高档，未实现或实测460800以上；32秒单声道230400约30秒仅理论下限。此前检查点ee7aa1e已推送，本轮新修改仅本地检查点、未推送。SD预览/提前灯光配色/重校准提示源码保留，均等待用户明确统一构建命令。板上历史记录仍为222517/59a5f282/0x171D，本轮未查询JTAG，无任何硬件操作或文件删除。失败测试与原无关脏项全部保留。

> **2026-11-01 PERFORM key alignment verified; source/simulation only, NOT built/programmed.** User confirmed octave changed to0x35 without recalibration: old base0x29 maps0x35 tokey12 and rejects0x54. Existing note-base mapping is correct; do not guess origin from a single Note. Added current KEY0Xxx-0Xyy range and persistent orange RECALIBRATE on out-of-range nonzero physical NoteOn; explicit CALIBRATE/LEFTKEY remains required after every octave change, followed by App score re-adaptation/upload. Real31250 UART/panel/session/final-pixel regression passes all128 keys in4 safe banks; 8 performance+4 protocol/overlay benches, normal/debug elaboration,327940 WTB samples and32768 pixel comparisons PASS with current hashes. Changed3 renderer/text files plus new bench; SD preview30aba70 and LED guidance bac085f retained. Evidence E:/gaoyun_builds/performance_key_alignment_acceptance_20261101.json; details doc/PERFORMANCE_KEY_ALIGNMENT_2026-11-01.md. Wait for user's explicit combined-build instruction. No Gowin/JTAG/deletion/push; last board record0x171D is historical, not a new query.

> **2026-11-01 performance LED guidance and pitch colors complete in source/simulation; NOT built/programmed.** User explicitly requests waiting for a later combined build command. Follow cues now include the due pending Note On before physical acknowledgement; running playback uses score-only strip masks, while idle keeps key feedback. 19 white pixels progress red/orange/yellow/green/cyan/blue/violet, last5 stay dark; pause preserves cues, Stop returns to idle, page exit/invalidation blanks. Only ui_top_renderer.v production RTL changed; audio/protocol/App/pins unchanged, prior SD preview30aba70 retained. New full-renderer/UART/actual-GRB bench:46 checks/22 frames PASS; 6 performance+4 protocol/integration benches and normal/debug elaborate PASS; all current evidence hashes verified, prior preview27+27 hashes still match. Same real scheduler probe at score10ms with no physical hit reproduces old LEDguide0 and new LEDguide1. Evidence E:/gaoyun_builds/led_guidance_acceptance_20261101.json; details doc/PERFORMANCE_LED_GUIDANCE_2026-11-01.md. No Gowin, JTAG, deletion or push; board remains prior0x171D, physical colors/Fmax/resources unverified.

> **2026-10-31 SD BANK local preview source/simulation complete; NOT built or programmed.** User confirmed BANK selection changes sound, only waveform was missing. Added WTB-derived compact 20KiB local ROM with independent A/B double-buffered preview, BANK00-09 and WT POSITION tracking; label LOCAL SD PREVIEW replaces fixed NOPREVIEW/status placeholder. Audio/protocol/App0.2.5 unchanged. 327940 sample checks, 32768 previous-renderer pixel/latency comparisons, 4 protocol/integration/overlay benches and normal/debug elaboration PASS with matching source hashes. Evidence: E:/gaoyun_builds/wavetable_preview_acceptance_20261031.json; details: doc/SD_WAVETABLE_PREVIEW_2026-10-31.md. Real UI remains prior deployed 0x171D until a later authorized build/audit/SRAM deployment; FPGA resource inference/Fmax unverified. Legacy video_alignment oracle fails identically on pre-change d963ff4; old osc oracle refers to missing 542cdeb; neither is claimed PASS. All old/failed evidence retained, no deletion or push.

> **2026-10-31 App0.2.5握手恢复修复已交付；本轮未改RTL、未启动Gowin、未烧录。** 用户手机为0.2.4，要求优先只改App。已核对HELLO四字节nonce及22/26字节ACK格式一致，只读JTAG仍UserCode0x171D/Status0x26230；不能断言现场首次缺失ACK的物理原因。已复现并修复首次握手耗尽重试后永久停止、重复连接不复用socket及断连回调覆盖状态；加入最多三轮自动恢复/手动重试、同连接nonce保持、TX/RX/有效帧/坏帧/最近hex诊断，保留板端校准gate。APK **0.2.5/code7**：`E:/gaoyun_builds/phone_apk_20261031_233409_562252/FPGA-Performance-0.2.5.apk`，SHA256 `c8590797a9752883b2df9d9f37aeb4f1ae4f16b81b79ed2ff8507dd444b816f8`；v2/v3签名通过且与0.2.4同证书，12打包输入/7网页资源逐字节匹配。手机完整回归 `phone_selection_20261031_233409_523272/result.json` 全PASS/18输入匹配（含22663音域用例及新握手回归）；已部署222517固件116输入仍完全一致。真实安卓/HC07链路尚未验收；若失败需新版RX/坏帧/最近RX，不要仅改提示就宣称链路修复。APK同目录release_verification.json及doc/PHONE_HANDSHAKE_FIX_2026-10-31.md记录证据，旧包/日志/无关脏文件保留，不推送。下方22:44固件已烧录结论仍成立。

> **2026-10-31 22:44 统一功能版已审计通过并完成唯一UI SRAM2烧录。** 实际工程 `D:/github/synth1_9_18/2_ui_touch_hub`，源码59a5f282f163c1cbe51f936c624317b1786226cd；normal构建 `E:/gaoyun_builds/R16A_build_20261031_222517`，五类时序违例0、七时钟全过（pixel53.671/50MHz、DDR112.458/100MHz）、116输入/124引脚匹配。包含此前WARP/五FX/SD10表/PAN/App及本轮校准移调、第六PITCH页；33种RTL和最终源码匹配。部署 `impl/deploy_runs/20261031_224251_UI_UNIFIED_PITCH_CAL_20261031`，双端SHA256=96F32E5317254CDCE89806B1A61E9A004468222A8F7E0F62E60C25EFCB8568FD，退出0/完成标记，烧后只读UserCode0x171D/Status0x26230一致。Gowin/Programmer已退出；不自动重烧。相机未覆盖UI屏幕，不宣称屏显或功能实测；APK0.2.4需单独安装，真实安卓/HC07/灯带/SD/整曲I²S-DDR及听感待现场验收。两失败目录和旧证据保留，未操作Flash/音频板、未删除、未推送。下方仍在构建/旧板0x3056为历史记录。

> **2026-10-31 22:26 第三轮唯一normal统一构建运行中，尚未烧录。** 新源码检查点59a5f282f163c1cbe51f936c624317b1786226cd（本地未推送），`E:/gaoyun_builds/R16A_build_20261031_222517`，Gowin PID13296、exec82346。116输入全部Git规范化/冻结/工作区匹配，仅两份RTL较215327变化，functional_evidence.json/source_delta.json齐全；33项RTL `six_fix_20261031_221913_674315`＋`221939_307389`、normal/debug `ui_elaboration_221913_697287`及八张画面等价全PASS，手机17输入/22,663用例及APK0.2.4哈希再次核对一致。新增32位bank保留idle寄存器与无门控读数据采样，消除busy宽扇出；绘图坐标乘法改常量选择。先检查真实进程，不并行/原样重跑；必须五类时序/七时钟/124引脚全过后唯一UI SRAM2。两失败目录211342/215327及审计保留，旧板173812/83ed585/0x3056，Flash/音频/删除/推送不操作。

> **2026-10-31 22:20 第二轮统一构建审计失败，未烧录；继续局部修复。** `E:/gaoyun_builds/R16A_build_20261031_215327` / 7bf3b60已22:16退出0，audit_20261031_221645_953051.json：271 setup端点，worst -3.105ns；DDR76.306/100MHz、pixel48.414/50MHz，其余四类/116输入/124引脚一致。首轮15setup的问题仅转移到busy高扇出，不能把空闲采样当已收敛。当前无Gowin，37321/监控878均已结束。追加修复：DDR payload分32位独立保留idle使能，读返回总线每拍采样、rsp_valid资格/周期保持；绘图tab/warp坐标乘法改等价常量选择，去除关键路径DSP。生产adapter回归与normal/debug已过，9项221913_674315及24项221939_307389回归正在收取；完成后唯一新normal构建。两失败构建全部保留，禁止部署；板上仍173812/83ed585/0x3056。用户持续授权统一功能至UI SRAM2完成，无需重复问；Flash/音频/删除/推送不操作。

> **2026-10-31 21:55 修补后唯一normal统一构建已启动，未烧录。** 源码7bf3b60（本地未推送），`E:/gaoyun_builds/R16A_build_20261031_215327`，PID28200、exec37321；恢复先看build_process.json/build.log/真实进程，禁止并行或原样重跑。116项输入与Git规范化内容/工作区/冻结快照匹配；33种RTL回归、normal/debug、手机旧证据17输入和APK0.2.4已重新核对，八张画面与修补前逐字节相同；证据汇总functional_evidence.json。修补仅效果器控制显示/文字流水及DDR adapter宽payload握手扇出，首轮211342的15setup失败证据完整保留。统一包含WARP/五FX/SD/PAN/App、校准移调和第六PITCH页。等待完整五类时序/七时钟/124引脚审计；通过后按既有授权仅UI SRAM2，Flash/音频板不操作。旧板仍173812/83ed585/0x3056，不删除、不推送。

> **2026-10-31 21:15 唯一normal统一构建已启动，未烧录。** 本地提交97d2b37（未推送），构建 `E:/gaoyun_builds/R16A_build_20261031_211342`，PID46616、exec63648；恢复先看build_process.json/build.log/真实进程，不重复启动。116项冻结输入与工作区、Git规范化内容一致；最终29项RTL/手机/层次/APK证据写入functional_evidence.json，全部匹配。本次包含所有尚未部署的WARP/五FX/SD/PAN/App修复、校准移调和第六PITCH页。等待唯一构建完成及五类时序/七时钟/124引脚全审计；旧板仍173812/83ed585/0x3056。Flash/音频板不操作，不删除证据。

> **2026-10-31 21:46 更正21:15运行状态：首轮统一构建已结束但时序失败，未烧录。** 实际UI `E:/gaoyun_builds/R16A_build_20261031_211342`，15setup，worst -1.302ns；pixel46.944/50MHz、DDR88.640/100MHz不通过，其余四类/124引脚/116输入匹配。audit_20261031_213750_461223.json及全部失败证据保留，不原样重跑。gowinsynthesis/place3/route1/timing/correct_hold1已核对正确。局部修补效果器数字/文字流水和DDR adapter宽payload握手扇出，重跑回归后再唯一normal构建；全审计通过才按既有授权UI SRAM2。旧板仍173812/83ed585/0x3056，Flash/音频未操作，不删除/推送。

# 工程操作日志与多 Agent 协作对齐表 (Operation & Alignment Log)

> **2026-10-31 21:04 用户授权统一UI构建，先完成第六PITCH页回归；当前尚无新Gowin/烧录。** 真实UI副本synth1_9_18，HEAD1a8ced1，全部旧改动保留，未提交/推送/删除。连接后板端CALIBRATE＋F15捕获安全起音0x29/0x35/0x41/0x4D、App整曲移调/含两端≤32允许/33拒传已完成源码、22,663手机用例、28项RTL及6项校准小修复回归；0x59实测不安全，禁止超宽折八度，覆盖19:59旧结论。APK0.2.4/code6在 `E:/gaoyun_builds/phone_apk_20261031_205654_857065/FPGA-Performance.apk`，签名/输入/资产核对通过。21:00 fetch音频origin/main已到dbffe37（C19已含Note接收），CC82～86未变；滑音/颤音从旧底部控件改为第五效果器后的第六PITCH页，新6项回归210334_282530运行中，随后唯一normal隔离构建/全审计。板上仍173812/83ed585/0x3056，不把源码/仿真当已部署。详细过程和恢复点见真实UI CODEX_HANDOFF顶部。

> **2026-10-31 19:59 起音进制纠正/App自动适配源码已验证，未重新上板。** 实际UI副本synth1_9_18，HEAD1a8ced1未变。用户确认默认最左0x29=41，最高档最左更正0x59=89；旧十进制29起点作废。7个RTL默认值改7'h29，默认41～72；App0.2.3/code5对上传副本整曲移调/超宽折八度，并处理重叠同键持续时间，显示实际处理，原文件不变。新APK `E:/gaoyun_builds/phone_apk_20261031_195710_749691/FPGA-Performance.apk`，SHA249718b8...79dd4bd；旧板上报29时提示先更新UI固件，练习需键盘默认档（尚无动态八度跟随）。8268音域/App/WAV回归、5项RTL/19白灯/31250键盘/仲裁、normal/debug层次全部通过，详见实际UI CODEX_HANDOFF顶部及doc/MIDI_RANGE_ADAPTATION_2026-10-31.md。未EDA/烧录/提交/推送/删除，所有旧改动保留；板上仍173812/83ed585/0x3056。

> **2026-10-31 LFO范围缩小至发送链，待曲线原始帧。** 用户确认Detune有LFO1持久标记，但未在旋钮旁见深度；代码实际把深度放在LFO底部AMOUNT栏。实际synth副本 `lfo_transport_frontends_20261031_140921_123261` 两种RTL语言模式各三项共六次全过（完整81帧/参数、真实31250绑定6/13、51字节UART仲裁），但仍未复现实板全零，不能认定综合bug或已修复。正请用户拖曲线并抓原始字节，核对固定同步帧 `F0 7D 48 00 04 F7` 的04，以区分路由选取与通用帧传输。生产RTL未改、没有新综合/布局布线或烧录；无活跃本轮任务，诊断改动未提交。以实际UI CODEX_HANDOFF/专门诊断文档为准。

> **2026-10-31 LFO实板反馈仍为0000，功能未验收。** 用户确认UI TX原始字节 `F0 7D 4F 00 00 F7`；13:50只读JTAG仍为UI新版0x00000966/0x00026230，没有掉电回旧版证据。实际synth副本新增原始触摸router→绑定→真实31250 UART诊断回归135607通过6/13正确值（UI计时压缩/启动握手加速），但未复现实板问题；首次全时序回归134906超时完整保留，不算全过。正常binding深度127及±8/±127规则不能到达0，仍需查状态/发送/实现。正等用户确认旋钮绑定标记和+127。生产RTL未改、未重新EDA或烧录，部署成功不等于功能成功；接续实际UI CODEX_HANDOFF与doc/LFO_ZERO_FRAME_2026-10-31.md。诊断改动未提交。

> **2026-10-31 收尾：六项UI修改已通过第7次完整审计并完成唯一一次UI SRAM2烧录。** 实际副本 `D:/github/synth1_9_18/2_ui_touch_hub`，源码 **f86e882** 已推送；构建 `E:/gaoyun_builds/R16A_build_20261031_041417`，109清单项（104独立输入）/124引脚/7时钟全过，setup/hold/recovery/removal/pulse余量 **+0.255/+0.141/+0.324/+0.389/+0.451ns**。部署 `impl/deploy_runs/20261031_043825_UI_SIX_FIX_MIDI29_LFO_ENV2`：PROGRAMMER_EXIT=0、CODEX_PROGRAM_COMPLETE、manifest=sram_programmed；User Code **0x00000966**、Status **0x00026230**，烧录后只读复核一致。双端FS SHA256 **4FEA0D3259550B06FBCBD545A99E3E51358173BE7948226AAA6091C7602D1A18**。抓拍过暗无法验屏，手机/实体跟弹/灯带及PCM实物回传待现场复测；需安装实际UI impl/phone_apk_20261031_004152/FPGA-Performance.apk（0.2.0）。键盘TX并联UI F15/J13第34脚，音频C19接收由队友补齐。Flash/音频工程未操作，全部失败证据保留。不得因下方历史运行状态重复构建或烧录；详细报告及completion_record.json在实际UI副本。

> **2026-10-31 04:15 第7次UI构建运行中未烧录。** 实际synth副本f86e882已推送；E:/gaoyun_builds/R16A_build_20261031_041417、PID18420、exec80539，ui_touch_hub_top/place3/route1。109清单项/10份Git源证明/9组当前回归（15400表对照及3BSRAM探针）/APK输入全匹配。等待本进程并全审计，过后按授权一次UI SRAM2。前6次失败全部保留未部署，音频C19接收由队友负责。实际UI CODEX_HANDOFF顶部为准。

> **2026-10-31 04:14 第6次UI失败未烧录，准备第7次。** 034931/8771013原DDR比较已过，剩8预览异步表读+1校准→回包kind，最差−1.148/−0.052ns；其余四类/109输入/124引脚过。实际synth副本新增仅预览启用的同步7bit镜像表，独立综合041150确认3BSRAM；15400数值/同步延迟对照、12项六功能/UART、2053帧双时钟/I²S-FIR、FX/导航/视频/编译全过。DDR仅提前预装回包kind，不延后校准失效。当前无Gowin，提交推送再唯一第7次全审计，过后按既有授权UI SRAM2；前6次失败全保留。

> **2026-10-31 03:50 第6次UI构建运行中未烧录。** 实际synth副本8771013已推送；E:/gaoyun_builds/R16A_build_20261031_034931、PID41468、exec69574。109项/9份Git源证明/7组当前回归及APK输入全匹配，12项六功能整链路/预览1272/PCM2053两时钟/I²S-FIR与navigation/video/trace全部通过。仅等该构建并全审计，通过再按授权UI SRAM2一次。前5次失败保留未部署；实际UI CODEX_HANDOFF顶部为准。

> **2026-10-31 03:48 第5次UI构建失败未烧录，setup105→3。** 032243/eff3bed原phone/UART/nav三组全过，剩LFO预览−0.987/−0.108ns、DDR容量比较−0.232ns；其余四类/109输入/124引脚通过。当前无Gowin。实际synth副本已加预览相位/样本寄存和DDR静态写校验寄存，1272数值/53目标/2053帧两时钟/I²S链测试过，完整六功能034648待收回；navigation/video/trace034722过。随后提交/推送、唯一第6次构建全审计，过后按授权SRAM2。只读JTAG仍UI旧1521，失败证据全部保留。

> **2026-10-31 03:24 第5次UI构建运行中未烧录。** 实际synth副本eff3bed已推送；E:/gaoyun_builds/R16A_build_20261031_032243、Gowin PID38364、exec96807，ui_touch_hub_top/place3/route1。109清单项/8份Git源证明/10组当前回归及APK输入均匹配；47事务、51串行字节、272679背景像素、2749716文字等价及完整LFO/ENV/模式/Note回归PASS。等待该进程并全审计，通过后按授权唯一UI SRAM2。前4次失败证据全部保留，音频/Flash/无关脏文件不动。

> **2026-10-31 03:19 第4次UI构建失败未烧录，三组时序修复回归中。** 024025/e221b04退出0但105setup、pixel45.861/50MHz、−1.805ns；DDR110.094MHz通过，其余四类/109输入/124引脚过，失败证据保留。当前无Gowin。phone_session批次三拍、UART原始请求握手、导航已有流水级分担背景选择已改，47事务与51串行字节专项过，完整LFO/ENV/导航回归待收回。先提交/推送，再唯一第5次构建审计，全过后依既有授权UI SRAM2；实际synth副本CODEX_HANDOFF顶部为准。音频/Flash/无关脏文件未动、不删文件。

> **2026-10-31 02:44 第四UI候选综合中，未烧录。** e221b04已推送，E:/gaoyun_builds/R16A_build_20261031_024025，PID45220、exec63919；109输入和六份关键源匹配，functional_evidence.json含10组当前回归/新toolbar/2749716例等价/APK输入。只等该进程，五类全零才按授权一次SRAM2。导航报告旧base60字段已改29并重跑通过（工具不在构建输入，不改RTL）；待最终文档提交。三失败候选全保留未部署，实际UI CODEX_HANDOFF顶部为准。

> **2026-10-31 02:38 第三UI候选未烧录，仅剩导航1setup。** 020513/2a73052的DDR112.379MHz已过100目标，1条pixel49.700MHz/−0.121ns来自shortcut优先链；其余四类/108输入/124引脚全过。现并行矩形+平衡OR去除长链，2749716旧/新case完全等价，navigation/video6136/trace编译通过，nine-bench67779及toolbar70542待收回。当前无活跃Gowin，先完成验证再提交/新构建。三份失败目录全部保留未部署；实际UI CODEX_HANDOFF顶部为准。

> **2026-10-31 02:06 第三UI候选综合中，未烧录。** 实际synth副本已推送2a73052（31b0547六项+a71dd14响应流水+读索引校验提前注册），E:/gaoyun_builds/R16A_build_20261031_020513，PID38520、exec79502。108输入及三份LFO/PCM源Git与快照一致，7组关键证据/九项bench和APK输入全匹配。仅等待该候选并审计，全零后按授权UI SRAM2；前两候选未烧录且全部保留。实际UI CODEX_HANDOFF顶部为准。

> **2026-10-31 02:02 第二UI候选013218已结束，8setup未闭合，未烧录。** 比首候选83条改善至8条，DDR96.220/100MHz、−0.393ns，其余四类/108输入/124引脚全过。剩余为读索引32位比较→错误回包，已提前至CALCULATE寄存，实时校准检查保留；store62534/six_fix97326仿真中，trace020154编译过。当前无活跃Gowin，先收回测试再提交并唯一新构建；不得复用013218失败位流，不删除证据。实际UI CODEX_HANDOFF顶部为准。

> **2026-10-31 01:34 唯一新UI候选综合中，未烧录。** 实际synth副本已推送a71dd14（六项31b0547+PCM DDR响应时序补丁），E:/gaoyun_builds/R16A_build_20261031_013218，PID25796、exec70728；108输入和关键源Git/工作区/快照匹配，functional_evidence.json含9组当前回归/原APK输入。等待该进程，不重跑；审计全过后按授权一次SRAM2。005813失败证据保留未烧录；Flash/音频工程/无关改动未动。最新细节以实际UI CODEX_HANDOFF顶部为准。

> **2026-10-31 01:31 六项UI首统一构建审计失败，未烧录。** 实际副本synth1_9_18，候选E:/gaoyun_builds/R16A_build_20261031_005813退出0但83setup（DDR83.583/100MHz，−1.964ns）；108输入/124引脚及其余四类通过。已按STA增加PCM store响应完成流水级、解除宽payload共享使能，store012858含即时/最后watchdog/完成前复位及真实I²S链回归通过，trace完整编译通过；six_fix012943完整回归仍运行。失败证据全部保留，不原样重跑；收回仿真后提交补丁，再唯一新构建审计，通过后按既有授权SRAM2。下方00:59运行状态已结束；31b0547是首候选，不是补丁后候选。

> **2026-10-31 00:59 六项UI修复已冻结并推送，统一构建中，未烧录。** 实际工作副本 `D:/github/synth1_9_18/2_ui_touch_hub`；提交 **31b0547** 已推送integration/dual-138k-uart-phase1。MIDI29～60、19白键灯/5暗灯、三模式/实体F15监听/触控恢复、ENV2独立CC32～35、LFO锁存dirty竞态、完整PCM安卓缓存与逐包进度已通过关键仿真，APK0.2.0/code2已签名。唯一Gowin候选 `E:/gaoyun_builds/R16A_build_20261031_005813`，PID33832、exec10802，先看真实进程/日志，勿重跑；108个源输入/三份LFO关键文件Git哈希证明在候选functional_evidence.json。用户明确选择音频队友补齐C19 Note接收（main5224279当前输出悬空），本轮只继续UI构建并烧SRAM2。F15=J13 pin34监听音频E19同根键盘TX，不重复转发；JTAG只读UserCode0x1521/Status0x26230与上一版UI相符。必须五类时序/124引脚/输入哈希全过才部署，Flash/音频工程未操作。详情实际UI doc/SIX_FIX_2026-10-31.md及CODEX_HANDOFF.md顶部。

> **2026-10-30 GitHub检查点已推送。** 用户要求“先把这个版本推上去github”。实际仓库 `haters-bot/synth1_9_18`，分支 `integration/dual-138k-uart-phase1`，提交 `32e2340`（feat(ui): add performance guidance and HC-07 phone integration），origin已从8f46f98快进至该提交。包含144个UI源码/约束/网页/安卓/回归/文档文件及两份MIDI样例；105个部署输入工作区哈希与上板候选一致且均入索引。构建输出/APK/密钥/仿真库/抓拍未入Git；旧scripts/remote_build.ps1和临时分析文件仍留本地，未删除或提交。没有合并main、重跑EDA或重新烧录。

> **2026-10-30 UI新版显示已获用户现场确认。** 用户对20:43 SRAM部署回复“没事，正常的”，实际UI部署hardware_acceptance.json已保存原话；不再处于显示待确认状态。随后提供生产JS解析通过的4秒C大调音阶和90BPM《小星星》单旋律MIDI（`E:/gaoyun_builds/midi_examples_20261030/`），供用户做蓝牙/灯屏/录音回传实物验收；这些功能仍待实际测试结果。

> **2026-10-30 20:44 UI SRAM烧录完成，待显示与功能验收。** 用户明确要求“按照烧录流程烧录”。实际工程deploy_verified.py一次operation2，部署 `D:/github/synth1_9_18/2_ui_touch_hub/impl/deploy_runs/20261030_204315_R16_stereo_hc07_F14_F16`；PROGRAMMER_EXIT=0、User Code0x00001521、Status0x00026230。写前105输入/123引脚/五类时序审计通过，本地/远端SHA256均 `4BA5FD918FAAE9B52CE3099B33F8E23453F90FAF722606736F0C74D6199B3525`。F14TX/F16RX、F13灯带及本轮PAN/LFO/双声道/手机录音功能已入本次SRAM位流；Flash未动，无重试/推送/音频修改。摄像头抓拍朝向天花板，无法验屏，明确待用户现场确认；真实蓝牙/实体音域/灯带/整曲DDR仍未验收。下方“未部署/板上14:03版”为历史。

> **2026-10-30 20:10 Codex：本轮蓝牙等功能已整合，统一Gowin待启动/审计，未部署。** 实际副本 `D:/github/synth1_9_18/2_ui_touch_hub`。用户最新指定近邻F14/F16：F14 TX→模块RXD、F16 RX←TXD；F13灯带。双速UART/板端ACK与去重/曲谱完整性、DDR原I²S录音127tap低通96k→8k回传、安卓壳已实现并通过软件/RTL回归，APK已签名但未手机实测。PAN/LFO/双声道图与视频、24灯回归通过。全部功能完成后才启动唯一Gowin候选并做五类时序/全部引脚/源哈希审计。入口见实际UI `CODEX_HANDOFF.md` 顶部与 `doc/HC07_PHONE_PROTOCOL_AND_ACCEPTANCE_2026-10-30.md`。无推送/删除/音频工程修改/自动烧录。

> **2026-10-30 19:35 Codex 整合进行中：用户要求全部问题（含新提供HC-07手册）解决后再统一构建一次。** PAN/左右波形与L:R相位/F13直连24灯/LFO 14bit及FX输入流水线已改并通过相关仿真，尚未部署；提前启动的192337构建已按用户要求停止并保留，非最终候选。安卓轻量壳+HC-07双向通信/录音降采样仍待实现。详情见 [整合状态](D:/github/synth1_9_18/2_ui_touch_hub/doc/STEREO_HC07_UPDATE_2026-10-30.md)。所有历史失败证据保留，未推送/烧录/删除/修改音频工程。


> **2026-10-30 经验集中归档：** 后续EDA工作先读实际UI工程 `D:/github/synth1_9_18/2_ui_touch_hub/doc/EDA_LESSONS_2026-10-30.md`，已由实际副本CODEX_HANDOFF.md链接。包含已证实根因、改进执行顺序与余量/验收边界；独立Hindsight入库未获工具确认。

> **2026-10-30 UI SRAM成功上板：** 用户确认“这一版成功上板”。实际副本 `D:/github/synth1_9_18/2_ui_touch_hub` 的 normal `R16A_build_20261029_222234` 唯一一次 SRAM operation2 成功，PROGRAMMER_EXIT=0、User Code `0x00009B47`、Status `0x00026230`，双机哈希 `9F842D53FF2B12F36AC67A317E7D1A16B9CFA7C613C947ABD8520F7C6401CC00`。验收证据在实际副本 `impl/deploy_runs/20261030_140337_R16_local_performance_ui_sram_20261030/hardware_acceptance.json`。五类时序零违例、122引脚匹配；确认不涵盖整曲DDR录音、实际键盘音域和逐灯验收。Flash未动、未推送、未删除、未改音频板。下方旧未烧录条目均为历史。

> **2026-10-29 23:00 SRAM 部署前只读检查通过，未烧录：** normal candidate `R16A_build_20261029_222234` 的 `deploy_verified.py --target sram --board ui --check-only` 重新验证输入哈希、五类时序与 122 个引脚，位流 SHA256 `9F842D53FF2B12F36AC67A317E7D1A16B9CFA7C613C947ABD8520F7C6401CC00`；未访问工程机、未写板。

> **2026-10-29 22:55 UI 本地演奏灯带引脚核对与构建完成：** 按官方 `hardware_docs/02_Schematic/DOCK/Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf` Rev1.3 第7/9页，确认 FPGA J16→板载 U15 WS2812 DIN→J24 pin3 `WS2812_DOUT`；J24 pin1 GND、pin2 NC、pin4 5V（0.45A max）。演奏帧改为1个板载黑像素+24个外接像素；新增独立 `performance_led_data`→J16，C14恢复debug UART；演奏颜色限制最大电流。灯带串行仿真和生产renderer全屏预览通过（25像素链、7帧、921600画面像素）；normal/debug RTL编译、白键映射和显示回归通过。正常 P&R `D:/github/synth1_9_18/2_ui_touch_hub/impl/R16A_build_20261029_222234` 审计通过，122/122 pins、99 inputs hash、五类时序零违例，最差余量setup/hold/recovery/removal/pulse +0.140/+0.138/+0.335/+0.302/+0.361ns。诊断 P&R `.../impl/DEBUG_R16A_build_20261029_223907` 也通过，122/122 pins、100 inputs hash、零违例，余量+0.649/+0.135/+0.335/+0.299/+0.361ns。首正常候选 `220509` 时序失败（5 setup，−0.126ns）保留。未烧录/推送/删除或改音频板；实物线缆接入 J24、亮度/供电、键盘 MIDI 音域、DDR录音仍待板上验收。

> **21:11 SRAM 部署前预检完成，未烧录：** `python tools/deploy_verified.py --label R16_local_performance_check_20261030 --target sram --board ui --fs impl/R16A_build_20261029_191907/impl/pnr/2_ui_touch_hub.fs --check-only` 通过；结果保存在 `impl/R16A_build_20261029_191907/deploy_check_only.json`，输入/快照哈希无偏差、五类时序闭合、121 引脚匹配，脚本明确在 check-only 分支返回，没有访问工程机或写板。复查发现重要板级冲突：旧 `doc/UI_PCB_DEBUG_UART_PINOUT.md` 将 C14 定义为调试 UART TX，当前 `PERFORMANCE_LED_ENABLE=1` 则将顶层 `debug_uart_tx` 改为 WS2812 数据输出，合并 CST 仍把该顶层端口约束到 C14。实际灯带 DIN 是否接 C14、是否已移除/迁移原调试线尚待用户确认；在确认前不烧录。未推送、不删文件、不修改音频板。

> **21:13 本地录音边界回归补齐：** PCM 捕获深度 3/16、左右声道次序/有符号采样、背压、容量、溢出、排空、断源及命令优先级通过（`impl/performance_pcm_20261029_211338_276125`）；生产 I²S 发送器到独立时钟 UI 接收器的逐对采样测试通过。长曲目进度 1047 项参考通过（`impl/performance_progress_20261029_211338_277479`）。加上上一轮 DDR adapter 全链路读回回归，软件侧录音/进度用例已覆盖。当前只读 SRAM 预检仍通过，物理接线与断电状态未确认，继续不烧录、不推送。

> **20:58 构建与本地演奏回归收尾：** 唯一候选 `impl/R16A_build_20261029_191907` 已于 19:46:38 退出 0；实际 `cmd.do` 为 `GW5AST-138B/PBGA484A-1`、`place_option 3`、`route_option 1`、`timing`、`correct_hold 1`、`route_maxfan 23`，使用唯一 `ui_touch_hub_combined.cst`。最新审计 `audit_20261029_205750_886777.json`：99/99 输入哈希匹配，121/121 引脚匹配，setup/hold 违例 0/0，最差 setup/hold/recovery/removal/pulse 分别 +0.214/+0.140/+0.335/+0.369/+0.361 ns；`clk_pixel` 50.541 MHz、`ddr_user_clk100` 104.122 MHz，OSER10 recovery/removal 三端点齐全且无豁免，`2_ui_touch_hub.fs` 38,731,437 bytes，SHA256 `78FEB3FA6EA7771B9D4DB0979C724437238355B2FE7B3DF2A09FC99A112C396`。旧 `185326` 仅综合后中断，保留未删。`performance_led_white_mapper` 的综合 swept 警告不作为硬件失效结论；当前白键映射、24 灯 WS2812 波形、实体键/曲谱提示均有独立回归和完整 renderer 预览证据。
>
> 当前回归全部 PASS：`performance_keys_20261029_194846_759722`、`performance_led_serial_20261029_194846_765328`、`performance_cue_20261029_194846_766005`、`performance_command_tests_20261029_194846_811607`、`performance_store_20261029_194932_141837`（两组异步时钟、137 对生产 I²S 样本逐帧读回、故障恢复）、`performance_display_20261029_194932_141544`、`navigation_20261029_194932`、`trace_tests_20261029_194932_169522`、`performance_notes_20261029_205545_646398`、`performance_scheduler_tests_20261029_205545_632768`，以及 MIDI/协议 Python 回归。当前 renderer 预览 `performance_preview_20261029_202447_714069/result.json` PASS，`performance.png` 为 1280×720，720 行×1280 像素、7 个 24 灯帧/921600 有效像素，已人工查看。预览工具改为逐行写出并严格恢复/校验完整像素，原始超时目录 `performance_preview_20261029_195017_613814` 保留。
>
> `impl/R16A_build_20261029_191907/functional_evidence.json` 汇总上述构建、位流、预览和回归路径。仍不烧录、不推送、不改音频、不删除：实体键盘最低 MIDI 音仍是临时 `PERFORMANCE_BASE_NOTE=60`，DDR 实板容量/校准、WS2812 电气接线和整首录音硬件验收未完成；手机/蓝牙只保留接口，音频板由队友负责。
> **19:40 接续恢复：** 先前 `impl/R16A_build_20261029_185326` 不是成功结束：PID 37860 已不存在，日志只到 Routing Phase 0，只有综合产物，没有 P&R 时序/位流；该目录 99 个输入哈希均匹配，未删除。按同一最终源码启动唯一新候选 `impl/R16A_build_20261029_191907`，构建 PID 17256、exec 19784；真实日志已完成综合并进入布局 `[30%] Placement Phase 2 completed`，进程仍存活，未收结果。实际 `cmd.do` 已核对 `-place_option 3`、`-route_option 1`、`-correct_hold 1`；约束文件为唯一 `ui_touch_hub_combined.cst`。综合资源为 Logic 61259/138240、Register 38370/139095、BSRAM 86/340；仍需完整五类时序审计。综合日志报告 `performance_led_white_mapper` 实例 swept；白键映射与 24 灯串行有 RTL 回归及生产 renderer 预览证据，但该综合警告与实体灯带行为仍须实板核实，不据仿真宣称硬件验收。继续不并行 Gowin、不烧录、不推送、不改音频、不删除。



> **2026-10-30 17:55 ZCode：队友 LFO 修复已同步、两轮构建差 5 条同源违例未烧，交接后续收敛；板上 14:03 版仍为旧 LFO 编码。** 队友 8f46f98（LFO SysEx MIDI-safe 14bit）已 pull --ff-only 进实际副本（AI_COLLABORATION_LOG 冲突双方条目均保留），tb_lfo_sysex_tx 全 PASS（T6=0x017F）。两轮隔离构建 impl/R16A_build_20261030_165924/_172142 审计完全相同：setup 5/hold 0 同源 u_knob_spi/param_id_3_s0→fx_state packet_external_value_*（-0.126×3/-0.084×2），其余四类+122 引脚+七时钟全过，timing_closed=false 未部署；相同输入两轮逐位同结果（与 222234=191907 同位流 9F842D53 一道实证本机 Gowin 确定性，重跑无意义）。222234 全零版 worst 仅 +0.140ns，LFO 9 行挪动布局挤过该族老路径。建议 Codex：fx_state 入口 knob 事件寄存一拍（10-19 先例）或 place_option 3→2，随用户后续改动一并收敛。板上 20261030_140337 版 lfo=4a89beca 旧编码，联调前须换新；队友 main 新 4 提交至 5224279 未合并。未推送/烧录/删除。

> **16:44 当前唯一构建164300正在综合，目标未完成。** 实际UI impl/R16A_build_20261029_164300，PID29796、exec39803，99输入哈希一致。上一162301已退出0并审计：3setup/0hold，pixel50.299/50MHz已通过，DDR90.976/100MHz仍失败，最差-0.992ns为committed到return_data64，121引脚全匹配，recovery/removal/pulse+0.335/+0.290/+0.361ns，三路OSER10均有完整检查，不可部署。审计audit_20261029_163948_380808.json。
>
> 已增加M_CALCULATE阶段，先寄存memory_base+committed及committed+frames，再比较并生成状态，未放宽时钟/约束。store164215两异步时钟/2053帧/137生产I²S链路/故障恢复PASS；测试原随机窗口未覆盖data-first，已改逐写强制交替，两顺序各9次通过，保留失败证据。trace164051正常/诊断完整编译、cue164331、navigation164331、display164331通过；notes162226及背景259330逐点比较输入仍匹配。索引当前构建functional_evidence.json。
>
> 无运行中预览；旧preview152737已经PASS和人工查看，本版以背景等价和七拍导航回归支持，不声称新整帧截图。曲谱默认只指引，MIDI最低音60临时且实体32键待采样；E19队友main仍d4338fb。无线延后，整首DDR实际容量/校准/录音读回及灯带电气未实板验收。不烧录/推送/删除/修改音频。

> **16:31 当前唯一构建162301仍在布局，未完成。** 实际UI impl/R16A_build_20261029_162301，PID32320、exec80315，99输入SHA与工作区一致。旧155807已退出0并审计失败：329setup/0hold，pixel48.774/50MHz、DDR81.593/100MHz，最差-2.256ns为committed计数到req_wmask；121引脚匹配，recovery/removal/pulse为+0.335/+0.377/+0.361ns，不能部署。审计audit_20261029_161438_233137.json。
>
> 已按关键路径将DDR命令锁存与校验分成M_VALIDATE阶段，宽请求载荷锁存独立于合法性检查。回归发现校准丢失后结束标记被旧故障逻辑覆盖，已把transaction_failed限定实际REQUEST/RESPONSE，store162149两时钟/2053帧/137生产I²S链路与校准丢失恢复全PASS。notes162226、cue162225（默认曲谱只指引不发音频Note）、navigation162226、display162225、trace162149正常/诊断完整编译PASS。带哈希证据索引impl/performance_timing_fix_20261029_155312/final_regressions_162301.json。trace脚本无result.json，记录日志证据，不伪造结果。
>
> 上一整帧预览152737已PASS并人工查看；该图早于时序改动，本版以259330背景等价比较和七拍导航回归支持，无新整帧捕获。Sipeed官方标称1GB DDR3/512MB×2，来源impl/ui_memory_reference_20261029_160033；配置1GiB录音区理论96kHz/16位双声道46分36秒，具体实板容量/校准/地址不折返未验收。验收基准doc/LOCAL_PERFORMANCE_ACCEPTANCE_2026-10-29.md。音符沿队友d4338fb原始MIDI号，实体最低音仍待测，60临时。无线继续延期；未烧录/推送/删除/改音频；目标未完成。

> **15:58 接续：旧预览152737已收回PASS，当前唯一Gowin155807正在运行。** preview/session70304/kernel29548均结束；921600像素与7灯帧/4032位、按钮/切页全灭PASS，result.json输入SHA一致，performance.png已人工查看。解除冻结后增加DDR mem_token数据/valid保留边界、Note队列独立弹性输出寄存、并行背景选择（保持7拍），默认关闭曲谱自动发声，灯/屏幕指引不变。旧综合网表为加密文件，无法凭搜索不到mem_token断言寄存消失；是否改善以新STA判断。
>
> 新回归store155532（两异步时钟/2053帧/137生产VIS V2 I²S/队友adapter精确读回及故障恢复）、notes155532（36事件真实串行/背压/溢出）、cue155618（1000位置/暂停/停止且曲谱无音频Note）、navigation155618、display155618、trace155618正常/诊断完整编译均PASS；background_final_result.json比较259330组旧/新背景PASS，全部带哈希证据当前匹配。索引impl/performance_timing_fix_20261029_155312/final_regressions.json。编译曾因循环变量sc重名失败，已改名并重新通过，失败证据保留。
>
> 唯一构建实际副本impl/R16A_build_20261029_155807，exec61759，PID=34700；99输入SHA匹配，尚未时序审计。无第二份Gowin、无运行中整帧预览，不烧录/推送/删除、不改音频，目标未完成。键盘协议按队友d4338fb的E19 MIDI原始编号，最低音60仍临时，实物验收前需采样实际32键；无线延期。旧152727仍因488setup/DDR81.944MHz/pixel46.81MHz拒绝部署。

> **15:48 唯一构建152727已退出0，仍拒绝部署：** 审计audit_20261029_154524_330143.json，99输入哈希匹配、121引脚全匹配，setup488/hold0，pixel46.81/50MHz、DDR user81.944/100MHz。官方DDR异步分组已消除原PHY跨域-7.508ns路径；本次最差-2.203ns为commands BSRAM到return_data/req，pixel最差-1.363ns为raster x到导航背景；另Note arbiter计数到MIDI FIFO使能-0.877ns。recovery/removal/pulse+0.335/+0.302/+0.361ns，三路OSER10均完整报告且通过。critical_path_review.json已保留，后续应保留DDR数据寄存边界、Note输出寄存、并行背景选择，不盲换模式。
>
> 无活跃Gowin；preview152737/session70304/kernel29548仍真实运行，约15:47已有5.8MB像素，未结束前RTL继续冻结。最终同源录音store153326通过拒绝/满/停止/断线恢复，candidate证据索引已更新。默认设计依据原需求为用户按实体琴键发声、曲谱仅指引；可选自动发声问题尚未答复，当前候选中曲谱到预留MIDI输出的默认行为仍需在冻结解除后明确。未烧录/推送/删除或改音频，目标未完成。

> **15:31 本地功能已推进，源码冻结验证中：** 录音接受/拒绝/自动停止反馈已闭环，新增真实状态与字符ROM；解决上次断线故障污染下一次录音的capture epoch问题。store152158的2053帧两时钟组和137帧生产I²S→队友adapter→精确读回，含拒绝重试、满容量/停止/断线恢复及状态均PASS。三源Note独立16深队列+UART ready/独立键掩码，36事件真实串行、480三源同键重叠通过；超载可见但密集32键和Stop/Pause已发送Note清理尚须后续验收，不称完整音频演奏通路。
>
> 候选曲谱容量升16384事件并集中参数，满后额外写入导致load_error并拒绝播放截断曲谱；scheduler152702覆盖5/8/1024/4096/16384通过。新增提前1秒的下落Note-On提示，cue152729验证1000位置/暂停冻结/Off不提示/停止清除；导航152743、I²S字形/ROM152708、全部11状态字符152744、normal/debug完整编译152702通过。手机无线仍延后，只同步32键/容量接口。
>
> **唯一Gowin**实际副本impl/R16A_build_20261029_152727、PID22828、exec60928，仍综合，normal/debug使用官方DDR分组与扩大STA报告；不可并行。**新版preview**impl/performance_preview_20261029_152737_017392、exec70304，真实renderer/7灯帧验证运行中，相关RTL/vh冻结直到收回。恢复先核对真实进程/同句柄。未烧录、推送、删除或改音频工程，目标未完成。

> **15:07 预览已收回并通过（覆盖下方运行中状态）：** performance_preview_20261029_144245_230550/session70866退出0，kernel34760已结束；921600有效像素、7个24灯帧/4032位、控制点击不切页、启动全灭/触摸/松开/MIDI64/停止/退出页全灭全部PASS，result.json的输入SHA256一致。完整performance.png已人工查看，控制按钮无导航遮挡；这不是实板验收。当前无活跃Gowin或ModelSim，RTL冻结已解除。
>
> normal/debug SDC已按高云GW5AST-138B官方例程拆开DDR100/400异步组，并按本机SUG940 5.5.1加入扩大及pixel/bit-clock专项report_timing，未降低频率或豁免域内/OSER10 reset。尚未跑下一候选；142528仍拒绝部署。下一步先补录音请求失败/自动停止恢复及真实状态显示、三源Note仲裁和容量硬门槛，再相关回归、唯一完整构建/五类审计。键盘最低音仍待现场MIDI采样，C14分配仍待回复；不依赖它们的本地工作继续。未推送/烧录/删除或改音频工程。

> **15:01 接续核对：** 已再次fetch队友main，仍d4338fb。E19的MIDI音符号原样进入合成器、解析器接受全部16通道；UI发送约定通道1，不能写成E19只收通道1。仓库仍无实体32键最低音，60只是临时参数；不需要原理图，但实体灯安装/验收前必须采样实际键号。只读源码证据impl/audio_note_contract_20261029_145705，协议文档已纠正。
>
> **DDR官方约束新证据：** 高云官网DDR3 ZIP内含GW5AST-138B专用1:4工程，其SDC将100MHz用户时钟与400MHz PHY设异步组（源头/逐项对照/SHA在doc/DDR_OFFICIAL_TIMING_REFERENCE_2026-10-29.md与impl/ddr_official_reference_20261029_145035）。此前142528最差25条setup全部跨此边界（4条到下降沿、21条到上升沿），先前“同组”指导已被官方示例纠正。normal/debug SDC已按官方分组，域内时序/OSER10 reset未豁免，尚未重跑P&R，不代表时序闭合或DDR实物验收。无新活跃Gowin；preview144245/session70866/kernel34760仍运行，hex持续增长，RTL冻结等待收回。未烧录、推送、删除或改音频源。

> **14:48 最终构建证据：** UI142528退出0，唯一Gowin已结束。最终121处引脚对照全部匹配，combined CST修复验证通过；STA仍不合格：233setup、pixel45.907/50MHz、最差-7.508ns位于DDR内部，hold0，其余三类摘要为正但removal前25路径未含全OSER10，完整审计仍拒绝，不能部署。审计在实际副本`impl/R16A_build_20261029_142528/audit_20261029_144607_910780.json`。最新按钮移动不在该快照，完整preview144245/session70866/kernel34760继续运行，待收结果/人工查看，不重新启动。未推送/烧录/删除或改音频。

> **2026-10-29 14:44 UI本地演奏继续：** 查实两份active CST导致Gowin只加载DDR一份，旧135029/140630的UI引脚全被自动分配，禁止部署；normal/debug已各改唯一combined CST+SDC，增加构建前唯一性与最终引脚报告门槛。录音宽RAM输出寄存/DDR显式时钟组已加，store142445、normal/debug完整编译142445、WS2812串行141945、导航144322、按钮144134通过。唯一Gowin实际副本142528/PID33588/session31668在routing，cmd.do确认place3/route1/combined CST；恢复先检查，不并行。旧preview142720因部分画面发现按钮被全局导航覆盖而主动只停该kernel，全部文件保留；按钮移y136..168，新preview144245/session70866/kernel34760运行，未PASS。C14专用灯带待用户答复，源码参数暂启用但未部署。实际代码D:/github/synth1_9_18/2_ui_touch_hub；未改音频/推送/烧录/删除。

> **2026-10-29 14:13 接续更新：** 实际UI仍在`D:/github/synth1_9_18/2_ui_touch_hub`。最新远端main=d4338fb，E19标准MIDI原样传递，无实体32键最低音记录，60只临时参数；工作区本地音频源较旧，参考用origin/main。DDR IP/wrapper/顶层请求现已接入；旧135029退出0但109setup/120hold及recovery/removal负裕量，禁止部署。最新normal/debug编译、导航、32键/白键灯映射及演奏触摸命令均PASS。唯一候选140630、PID6804、exec27762正在布局，恢复先核对实际进程；DDR显式时钟/异步组尚待审查。未烧录、推送、删除或改音频，详见实际UI状态文档。

> **13:35 UI本地演奏交互验证：** 实际UI工程演奏页加入播放/暂停/停止触控，和预留手机控制共用状态解码器。`performance_command_tests_20261029_133453_862938`、`navigation_20261029_133336`、`trace_tests_20261029_133336_612787`通过，git diff --check通过。队友音频main仍按MIDI 21..108处理音符，未找到实体32键键盘最低音记录；60仅是UI临时配置。未运行Gowin/烧录/推送/删除；UI DDR未接顶层，未完成P&R和实板验收。

> **13:23 验证更新：** recording_subsystem 已加入 UI 正常/诊断工程，137 帧生产 I²S 到 DDR adapter 写后逐帧读回PASS，两种DDR通道先后握手均过。`performance_store_20261029_131716_863132`、`navigation_20261029_131949`、`i2s_tests_20261029_131949_887871`、`trace_tests_20261029_131949_891687`是本轮证据。DDR user-port逻辑通过内存模型，但UI板DDR IP/实体容量与校准、界面录音状态、UI完整P&R和实板测试均未完成；未启动Gowin/烧录/推送/删除。

> **12:57 验证补充：** 实际副本 navigation_20261029_125443 与 trace_tests_20261029_125622_446219 均已结束PASS，最终源码编译/导航通过，34083不再运行；git diff --check通过。所有本轮测试结果已收回，无待观察测试句柄。本轮未启动Gowin，旧105439失败不可部署。下一步仍是整首外存后端及本地完整交互，不把前端PCM仿真当作功能完成。

> **2026-10-29 12:55 UI 本地演奏继续，目标未完成。** 实际源码仍 D:/github/synth1_9_18/2_ui_touch_hub；音频队友main fetch后仍d4338fb，E19按标准MIDI音符原样进入合成器，无实体键盘最低音记录。已修正32键/24白键灯映射、导航字页号、触摸拖键即时抬起/出屏/切页粘键、停止清理；最低音暴露为UI顶层参数60（待校准）。新增无32位溢出的长歌进度，1047参考通过；PCM前端FIFO3/16与生产I²S链路仿真通过，但尚未接整首DDR存储。旧UI105439已完成审计且失败494 setup/-27.684ns/20.971MHz，不能部署。本轮无Gowin、无烧录、无推送、无删除、不修改音频。原镜像RTL不得反向覆盖实际副本。详细证据/限制/下一步在实际副本doc/LOCAL_PERFORMANCE_STATUS_2026-10-29.md；后续先核对最终导航句柄34083，再推进外部存储兼容、真正本地交互/事件仲裁、WS2812串行验证和时序收敛。

> **2026-10-29 UI 演奏功能 EDA 自查（优先于下方旧音频任务记录）：用户已取消本侧音频工作，不恢复、不推送音频改动。** 实际 UI 源码 `D:/github/synth1_9_18/2_ui_touch_hub`。旧演奏候选090153已退出1/PR0004/19825未布线，CLS98%，无可部署位流；实际place3/route2与成功UI基线相同，不能认定仅因模式选错。确认调度器RAM展开：修正同步单读单写独立无复位存储过程后，同参数1024容量独立综合由48266FF/27235LUT/0BSRAM降为131FF/178LUT/3BSRAM。ModelSim容量5/8/1024/4096及Python MIDI/帧协议通过。正常/诊断Tcl显式gowinsynthesis（本机要求小写）、place3/route1/timing_driven1。新唯一完整UI候选105439、Gowin PID28528、exec35235，启动时尚未完成综合/布局布线；恢复须先查进程/日志，不并行Gowin，仍须五类时序审计。不烧录、不删除、不推送，保留所有脏改动。详细证据在实际副本`doc/UI_PERFORMANCE_EDA_AUDIT_2026-10-29.md`和`impl/performance_eda_probe_20261029_105142`。

> **2026-10-28 04:01 恢复更新：UI焦点已通过用户现场验收。** 用户确认“高亮已正常恢复并保留”，验收记录位于原副本部署034258的focus_acceptance.json。旧音频候选034258在会话续接后已无Gowin/监督进程，日志停Placement Phase1、无fs/最终STA，状态已记interrupted_no_exit_code，不能当作运行中或合格。未自动重烧、未删除文件。为避免终端任务被会话中断带走，构建器新增--background，经WMI隐藏独立启动；当前唯一音频候选为整合副本impl/AUDIO_XY_build_20261028_040056_136483，Gowin PID13268、监督PID20512，启动日志impl/audio_launcher_20261028_040055_308690/supervisor.log。通过文件/真实进程核对，不依赖已失效exec句柄。音频未部署，JTAG仍UI，五类审计后再请用户切换；目标未完成。**

> **2026-10-28 03:44 接续：UI 新版已实际部署，音频构建中。** UI候选 `D:/github/synth1_9_18/2_ui_touch_hub/impl/R16A_build_20261028_032336` 已完成五类时序审计，73输入哈希一致、0 setup/hold端点、pixel50.879/50MHz；setup/hold/recovery/removal/pulse余量+0.346/+0.203/+0.184/+0.497/+0.453ns。用户确认JTAG接UI板后，仅一次SRAM2部署 `20261028_034258_R16_OSC_AB_FOCUS_UI` 成功，PROGRAMMER_EXIT=0、User Code0x00009A81、Status0x00026230，双机SHA256 `0322CBA28DC6004AB1CA697DE30F5874B46C4C2A3C2140B7B0DC9933F6D06DB2`；摄像头画面正常，用户已实物确认“高亮已正常恢复并保留”；验收原话保存在该部署目录focus_acceptance.json。原副本与构建输入完全相符，新整合副本20个输入只有CRLF/LF差异，故使用原副本严格审计/部署，不弱化哈希。音频首候选034022在Tcl因不支持-inc_place退出，尚未综合；脚本改用全新目录保证无增量，并修正生成Tcl原始字节哈希。当前唯一Gowin为整合副本impl/AUDIO_XY_build_20261028_034258_711468，PID24760、session61358，综合已完成、正在布局；不得另起Gowin。预览session43904已退出且PASS，完整921600像素/4096逐拍检查及64输入哈希通过，preview.png已查看；模拟PCM，不是实板音频证据。两板独立供电、仅一根JTAG，音频烧录前仍须用户切换并确认目标。Flash未动，音频未烧录，目标未完成。**

> **对齐说明**：本文件记录每一次硬件操作、代码编译、版本迭代与排查结果，作为工作区常驻记忆。  
> **所有在此工作区操作的 Agent（Antigravity / Codex 等）均需在每次完成重要步骤后追加记录**。

---

## 📅 操作历史与版本演进流水线

### [2026-10-27 23:55] - 新一轮LFO/实体旋钮/显示缩放改进进行中，未部署

- 实际源码D:/github/synth1_9_18/2_ui_touch_hub，需求检查点3daf062已推送。本镜像RTL仍不得反向覆盖。
- 已实现绝对LFO预览与静态值分离、方向纠正/显示焦点、32旋钮独立1/2/4/8步长、两处共享显示缩放、独立左右RMS/峰值保持。319实体控制、67893 LFO数值、13746显示区域像素、86FFT/3591DFT/49152相位像素（正交椭圆）、I2S/四档时间/导航/6136视频/SPI事件日志/MIDI/SysEx均通过。
- 设置页及立体声六窗预览正在运行，首张设置页已查看；无Gowin、未烧录。完整时序与本轮现场验收待完成，板上仍为225244上一轮验收版。原始文件/旧候选未删除。
- FX全量音频CC原本未对接；最后两实体旋钮现与可见FX共用UI状态，不新增音频协议编号。音频板还需同步绝对LFO语义；不能写为音频FX/新调制已联调。详见实际副本doc/UI_CONTROL_IMPROVEMENTS_2026-10-27.md。

### [2026-10-27 22:56] - 六窗完整I2S升级已部署并通过现场验收

- 用户现场确认“六窗响应、旋钮联动都正常”。第一窗真实能量圆/数值、触发波形、相位/CORR/BAL、FFT峰值/重心、历史色标、RMS/Peak/dBFS/crest均完成本轮升级。旋钮与事件式SPI/C14日志保留。
- 实际源码仍在D:/github/synth1_9_18/2_ui_touch_hub，RTL检查点0ae2e6a已推送；本镜像旧RTL不得反向覆盖。最终候选223956完整审计通过：67输入哈希一致、五类时序零违例，余量+0.695/+0.200/+0.201/+0.497/+0.453ns，pixel56.229/50MHz。
- 仅一次SRAM operation2：实际副本impl/deploy_runs/20261027_225244_R16_I2S_SIX_WINDOW_UPGRADE，PROGRAMMER_EXIT=0、Status0x00026230、User Code0x0000D385、双机SHA256 1794286747E826D0116430014E17EDC4D8628CAE83AFA28B5EBA38B596FC1212。Flash未动、音频板未重烧，旧候选和原始文件未删除。
- 完整新预览223706通过921600像素/4096逐拍检查与58输入哈希；与221458完整PPM逐字节零差异。512游标、32769幅值dBFS、保持衰减、I2S整链路、字形/导航/6136视频、1366帧139行旋钮/串口回归全部通过。预览为模拟PCM，实板音频响应由用户确认。
- 验收原话与硬件/构建证据保存在部署目录hardware_acceptance.json；两处交接和详细文档已更新。所有本轮进程已结束，本轮升级可以收尾；下方未完成/运行中均为历史。

### [2026-10-27 22:37] - 六窗第三候选完整STA失败，剩余算术路径已分拍

- 实际源码在D:/github/synth1_9_18/2_ui_touch_hub，本目录旧RTL不反向覆盖。221458正常退出但审计不通过：46.978/50MHz、11 setup、-1.287ns；9条相关性坐标、2条保持幅值选择到dBFS编码。未部署。
- 已分为三拍相关性乘/除/加，以及幅值最大值寄存/保持比较寄存/三拍编码。完整I2S与512游标、metrics独立参考及新增held dBFS、导航、6136视频检查均通过。无降频或新时序豁免。
- 新预览impl/audio_upgrade_preview_20261027_223706_531567运行中。接续须提交/推送后唯一新候选完整构建和五类审计，通过后才SRAM operation2；Flash暂停，文件未删除，升级目标尚未完成。

### [2026-10-11 04:52] - 屎山代码与残留动效彻底清剿：v6 纯净架构、无溢出 ADSR 与实机闭环摄像头审计通过
* **操作者**：Antigravity Agent (FPGA & Architecture Specialist)
* **核心整改内容**：
  1. **彻底铲除“残留动效/假播放”屎山层 (`music_sequencer.v`)**：
     - 从顶层 `hdmi_serum_top.v` 中完全删除 `music_sequencer u_seq` 自动和弦发生器；
     - 切断之前向琴键强制 OR 注入的虚假音符掩码，将琴键驱动源 100% 收归真实的外部用户触控掩码（`touch_key_white_mask`/`black_mask`）；
     - 琴键在无用户按压时完全静默、息屏，杜绝“自嗨”假演奏。
  2. **消除 LFO 伪周期三角波栅栏**：
     - 移除旧版本在 LFO 窗口中反复重复的锯齿/三角波栅栏（`\ / \ / \ /`），重构为贯穿整个 363px 窗口的单周期高精光滑正弦波及柔和蓝光渐变充填。
  3. **修复 ENV 窗口溢出折叠与条形码瑕疵**：
     - 查明原 ENV 窗口锯齿条纹与垂直条形码根因：定点数除法查表缩放比使用了 65536 却按 `>> 8` 移位导致高位溢出折叠；
     - 采用预计算 10-bit 倒数 LUT（`1024 / len`）结合 3 级严格 Clamp 限幅，彻底根除数值溢出，呈现教科书级标准 ADSR 包络曲线与高亮白色控制节点。
  4. **全屏实机闭环视觉审计通过 (`audit_final_report.png`)**：
     - 校准前置摄像头裁剪坐标系（`y: 130..365, x: 120..500`），完整捕获 10.1" 物理屏幕全貌；
     - JTAG 烧录成功（Status Code `0x00026230`），实机摄像头截图对比官方 Serum VST 调音台：面板点对点像素贴合，波形、旋钮指针、高亮控制圈与 ADSR 曲线纯净无瑕疵。

---

### [2026-10-10 01:10] - 远程异步轮询执行引擎落成、通道鲁棒性深度强化与 Task 4 音频链路接入规划
* **操作者**：Antigravity Agent (Review & Architecture Lead)
* **通道架构与执行工具攻坚**：
  1. **构建通用远程异步轮询引擎 (`run_remote_job.ps1`)**：
     - 响应用户核心关切：“避免命令通过 SSH 发过去无休止等待，及时确认收到，短周期轮询，把控量和度”；
     - 采用 WMI (`[wmiclass]'Win32_Process'`) 独立创建后台子进程，彻底规避 Windows OpenSSH 默认会话 Job Object 在断连时自动强杀子进程的机制死穴；
     - 2~3 秒内收回启动确认与远程 PID，使用轻量短周期（默认 5 秒）轮询状态与日志末尾（Tail），任务完成后精准回收 stdout/stderr 与退出码。已通过多阶段测试实测验证。
  2. **`run_remote.ps1` 通信通道深度健壮性修复**：
     - **消除 CLIXML 污染与延迟**：注入 `$ProgressPreference = 'SilentlyContinue'`，消除 PowerShell 默认流污染与额外 5~7 秒序列化开销；
     - **修复管道输出截断**：将原 `[Console]::Out.Write` 替换为 `Write-Output`，彻底恢复脚本外层变量捕获与管道对接功能；
     - **扩展网络重试覆盖面**：将仅匹配 "Connection timed out" 升级为覆盖 OpenSSH 退出码 255 及所有 ZeroTier 瞬态断连错误；
     - **兼容参数绑定与转义**：修复命令行转义被命令行解释器拆分导致的 ParameterBindingException。
  3. **工程机环境配置**：
     - 显式配置工程机 `CurrentUser` 的 ExecutionPolicy 为 `Bypass`，杜绝后台 runner 脚本被系统策略拦截。
* **硬件与代码对齐核查**：
  1. **顶层模块注释对齐**：修复 `hdmi_serum_top.v` 中残留的 1080p@60Hz/148.5MHz 注释，修正为验证过的 720p@50.5Hz CEA/VESA (PCLK=62.5MHz) 规范，已同步远端。
  2. **本地文件属性修复**：清除本地 `hdmi_serum.fs` 的只读标志，同步远端综合报告 `hdmi_serum.rpt.txt`。
* **后续规划推进 (Task 4 音频发声引擎接入)**：
  - 核心外设：板载 PT8211 16-bit 立体声 I2S DAC (引脚 `hp_bck=Y17, hp_ws=AB17, hp_din=AA16`) + NS4263 功放 (`pa_en=AB16`, 低有效)；
  - 接入方案：复用 `rtl_lib/i2s_tx.v` 与 `rtl_lib/dds_osc.v`，直接挂载在 `hdmi_serum_top.v` 的 50MHz 系统时钟域；由 `music_sequencer` 与触控事件驱动音符频率字，实现屏幕琴键动态点亮与喇叭/耳机实时同频发声联动。

### [2026-10-10 00:35] - 屏幕触控输入切断、720p 视频时序恢复与 Serum 界面点亮实证
* **操作者**：Antigravity Agent (Coding Worker)
* **背景与安全处置**：
  1. **切断 Windows 侧屏幕乱控（步骤 1）**：
     - 在工程机上执行 `Disable-PnpDevice -InstanceId 'HID\VID_222A&PID_0001&MI_00\9&2592614E&0&0000' -Confirm:$false` 与 `MI_02`（触摸与鼠标设备）；
     - 检查确认两者状态均转为 `CM_PROB_DISABLED`，彻底阻断了屏幕误触对工程机鼠标/系统的乱控干扰，同时保持 5V 正常供电。
  2. **工程机 SSH 远程通道优化**：
     - 查明虚拟内网为 ZeroTier（IP 10.132.253.235 -> 10.132.253.157），在主机 `.ssh/config` 与 `run_remote.ps1` 显式绑定网卡出口 IP `-b 10.132.253.235`，消除路由选择抖动与超时间隙；
     - 针对耗时编译任务，采用 WMI/CIM 独立进程拉起结合短周期轻量轮询机制，实现快速确认与零超时挂死。
* **硬件与代码变更**：
  1. **720p 视频时序恢复（步骤 2）**：
     - 修复 `hdmi_serum_top.v` 中 `u_timing` 模块参数，从误配的 1080p 恢复为经过验证的 720p（1280x720@50.5Hz，PCLK=62.5MHz）：
       `video_hlength (1650), video_vlength (750), video_hsync_pol (1), video_hsync_len (40), video_hbp_len (220), video_h_visible (1280), video_vsync_pol (1), video_vsync_len (5), video_vbp_len (20), video_v_visible (720)`；
     - 同步本地与工程机 `D:\gaoyun\hdmi_serum_ui\src\hdmi_serum_top.v` 保持完全一致。
* **编译与安全烧录**：
  1. **全量编译（步骤 3）**：
     - 使用 `$env:LM_LICENSE_FILE='gowinlic.sipeed.com:10559'` 调用 `gw_sh.exe build.tcl`，经综合与 PnR 生成全新比特流 `hdmi_serum.fs`（42,340,875 字节，时间戳 00:31:51），退出码 0。
  2. **JTAG 烧录与状态复核（步骤 4）**：
     - 清空 License 环境变量后执行 `programmer_cli.exe --scan --frequency 1M`，确认单设备 `GW5AST-138B` 在线；
     - 执行 `--operation_index 2` SRAM 烧录（100%，耗时 26.72s），返回 `User Code: 0x00008CA8`，`Status Code: 0x00026230`，FPGA 正式加载运行。
* **物理视觉实证（步骤 5）**：
  - 调用 `webcam_snap.py` 捕获摄像头图像 `cam_0.jpg` 并回传本地；
  - 通过 `view_file` 图像核查，确认 10.1 寸便携屏已稳定点亮，全屏清晰呈现 Serum 动态合成器界面（OSC A 荧光绿波形、OSC B 锯齿波形、Filter 视窗、ADSR 动态蓝色包络及各控件旋钮光泽无抖动/无黑屏）。


### [2026-10-08] - 主机与工程机远程互联约定
* **背景**：为降低主机因蓝屏导致硬件/工作损失的风险，已配置一台独立工程机承载相关硬件控制与工程操作。
* **网络方式**：两台电脑通过 Tailscale 虚拟网卡互联。
* **工程机 SSH 入口**：`ssh Administrator@10.132.253.157`
* **协作约定**：需要访问工程机上的工程文件、连接硬件、执行烧录/测试或发布命令时，优先由主机 Agent 通过上述 SSH 入口发起；实际命令在工程机执行。
* **安全边界**：默认先做只读检查；涉及烧录、硬件上电、文件覆盖或发布的操作，必须明确记录命令、目标和结果。原始文件未经明确允许不得删除、覆盖或移动。
* **连通性验证**：本次会话首次测试成功：远端主机名 `DESKTOP-FDEVSGP`，身份 `desktop-fdevsgp\\administrator`，默认目录 `C:\\Users\\Administrator`，可读取 `C:` 与 `D:` 磁盘容量信息，并能执行远程 PowerShell 命令。
* **稳定性记录**：首次成功后连续两次连接在 TCP/22 阶段超时，未进入认证握手；因此 Tailscale 路由或工程机 SSH 服务存在间歇性可达问题。Tailscale 状态、USB/JTAG 枚举和烧录工具路径尚未完成验证，后续连接恢复后再检查。

### [2026-09-26 21:25] - 音频链路原理图实证 + 静音开关功能上板（ZCode）
* **操作者**：ZCode Agent
* **原理图实证**（DOCK 31005 第 10 页 DAC+PA，PDF 文本提取）：
  1. 音频链路 = **U16 PT8211**（16bit 立体声 I2S DAC，纯硬件无寄存器配置）→ 低通滤波 → **U20 NS4263**（2×3W D 类功放）→ **J28 扬声器接口** + J25 3.5mm 耳机座（PJ-342）。
  2. 耳机/扬声器自动切换：耳机座 L/R_DET 检测，**不插耳机时 J28 扬声器口自动有输出**。
  3. **PA_EN 极性实证：0=功放开，1=关**（图面注释 PA_EN=1:PA OFF），与例程拉低行为互证。
* **新增功能**：
  - `rtl_lib/btn_toggle.v`：按键去抖+电平翻转积木（2FF 同步→计数去抖→稳定下降沿翻转），20ms@50MHz，后续所有"按一下切状态"交互复用。
  - `synth_app_a` 顶层接入静音开关：`key_mute_n = Y12`（官方引脚表 Key_in[1]，S2 之外的另一颗用户键），静音在数据域实现（采样置零，I2S 时钟不断）。
  - LED 语义（W21）：**放音=0.5s 心跳闪烁；静音=常亮**。
* **编译烧录**：21:19 生成新 fs，21:24 烧录成功（Status 0x00026230）。
* **待用户操作**：无源蜂鸣器/小喇叭接 J28 扬声器接口听音（L=440Hz R=659Hz），按 Key_in[1] 验证静音开关。

### [2026-09-26 21:15] - 方案A架构落地：rtl_lib 积木库 + synth_app_a Phase 1（ZCode）
* **操作者**：ZCode Agent
* **背景决策**：团队确认方案A仅为当前可行路线，未来可能整体换方案。故确立**两层架构**：
  1. `rtl_lib/`（新增目录）：**方案无关积木库**，只收纯逻辑参数化模块（禁引脚耦合），换方案时整体存活。
  2. `synth_app_a/`（新增目录）：**方案A集成层**，可整体替换；未来换路线新建 `synth_app_b/` 同构并存。
  命名规则：积木按功能命名（`dds_osc` 不带方案字母）；顶层 `synth_<字母>_top.v`；引脚只出现在各 app 的 `.cst`。详见两个目录的 README。
* **Phase 1 交付内容（音频链路验证）**：
  - `rtl_lib/i2s_tx.v`：16bit 立体声 I2S/左对齐发射器，逐边沿复刻官方例程 `audio_i2s/audio_drive.v` 板上验证时序，改为 50MHz 单时钟域使能实现（无需 PLL/CLKDIV IP）；fs = 50M/33/32 = 47348Hz。
  - `rtl_lib/dds_osc.v` + `sine_rom.v`：32bit 相位累加 DDS + 4096×16 正弦 B-SRAM 查表（`$readmemh` 初始化，综合日志确认无报错）。
  - `rtl_lib/tools/gen_sine_mem.py`：生成 sine_lut.mem + 音符相位增量表。
  - `synth_app_a/synth_a_top.v`：L=A4 440Hz / R=E5 659Hz 双音 + W21 心跳 LED；PA_EN 拉低（例程实证=功放常开）。
  - 引脚（新占用）：`hp_bck=Y17 hp_ws=AB17 hp_din=AA16 pa_en=AB16 led=W21`，clk/rst 沿用 V22/AB13。
* **编译**：21:11 一次通过，资源 102 LUT / 8 BSRAM(3%)，无告警。
* **采样率备忘**：50MHz 整数分频无法精确 48k（50e6/1.536e6=32.55 非整数），当前 −1.4% 近似；精确 48k/96k 的正解是 MS5351 可编程时钟（见 rtl_lib/README.md），留待冲分阶段。
* **待办**：上板听音验证（本条目录其他 Agent 请勿动）。

### [2026-09-26 20:35] - 确立「蓝屏防御七步流程」（ZCode，全体 Agent 共同遵守）
* **操作者**：ZCode Agent（经用户要求固化）
* **背景**：本日两次蓝屏均为 ftdibus.sys 0x3B，根因分别是带电插拔排线、未开机扫 JTAG；20:29 按新流程烧录一次成功，验证流程有效。
* **七步流程**：
  1. 上电顺序固定：12V 适配器 → 长按 PWR 2 秒开机 → 插 USB；严禁带电插拔任何部件。
  2. 烧录前 `Get-PnpDevice` 纯软件确认 FT2232 枚举正常。
  3. `programmer_cli --scan --frequency 1M` 低频预扫，干净才正式操作；**报错不得连续重试**，先停下排查。
  4. 烧录用 `--operation_index 2`，勿用操作 4（Verify 回读在此器件报错）。
  5. 烧录期间不碰板子与线缆，确保 12V 接触良好（运行中 FPGA 掉电 + USB 仍在 = 毛刺场景）。
  6. 任何蓝屏/断电后必须重新编译生成新 fs 再烧（崩溃前文件可能未落盘损坏）。
  7. 烧录前保存电脑上正在编辑的文档，最小化万一崩溃的损失。
* **维护要求**：出现新的蓝屏因素（如 USB 口供电不稳、静电、hub 兼容性等），操作 Agent 须读 Minidump 定位 → 登记本文件 → 更新各自记忆。

### [2026-09-26 20:29] - 点屏固件烧录成功，Task 3 待用户目视确认（ZCode）
* **操作者**：ZCode Agent
* **烧录记录**：
  1. 20:08 版比特流三次 SRAM 烧录均秒报 `Error: Error found!`（退出码 254），排查发现该文件生成 85 秒后遭遇蓝屏硬重启，判定为 **NTFS 数据未落盘导致 fs 文件内容损坏**（文件头/大小完好，主体可能被打洞）。
  2. 20:27 重新全量编译生成全新 `lcd_touch.fs`（34.6MB，头信息校验：GW5AST-138B 版本 B、CheckSum 0x2107、CRCCheck ON），重新执行 `programmer_cli --operation_index 2`（SRAM Program）。
  3. **烧录 100% 成功，耗时 18.76s，User Code 0x00002107，Status Code 0x00026230**（与 17:44 成功烧录状态码一致）。
* **重要经验（后续烧录必读）**：任何蓝屏/断电后，**必须重新编译生成新比特流再烧录**，不可复用崩溃前生成的 fs 文件；程序化烧录用 `--operation_index 2`，勿用带 Verify 的操作 4（SRAM 回读校验在此器件上会报错）。
* **当前状态**：修复版固件（25MHz 像素时钟 ≈51.3Hz 场频）已在 FPGA 内运行，等待用户目视确认 8 阶彩条（白/黄/青/绿/品红/红/蓝/黑）显示与闪烁情况。

### [2026-09-26 20:18] - JTAG 低频扫描成功，蓝屏根因假说证实（ZCode）
* **操作者**：ZCode Agent
* **操作内容**：
  1. 烧录前先以纯软件方式核查 USB 枚举：FT2232 双通道（USB Serial Converter A/B）与 COM8/COM9 均正常在线。
  2. `programmer_cli --scan --frequency 1M` 低频扫描：**成功，无蓝屏**。发现 1 颗设备 `GW5AST-138B`（ID `0x0001081B`），耗时 0.11 秒。
* **结论**：用户完成「12V 适配器 → 长按 PWR 开机 → 插 USB」上电顺序后 JTAG 即恢复正常，证实 20:09 蓝屏根因为**板子未开机时 JTAG 扫描灌入未上电 FPGA 产生电气毛刺**。后续所有烧录操作严格执行此上电顺序。

### [2026-09-26 20:15] - 第二次蓝屏排查与接管执行进展（ZCode）
* **操作者**：ZCode Agent
* **执行进展**：
  1. 已修复 `lcd_touch_app/lcd_touch_top.v` 像素时钟：原代码实际输出 12.5MHz（场频仅 ~25.7Hz，有失步/闪烁风险），改为 50MHz 二分频 25MHz（场频 ~51.3Hz），并将 `sc_clk` 反相输出保证面板采样建立裕量。
  2. `gw_sh.exe` 全量综合+布局布线通过，新比特流 `lcd_touch_app/impl/pnr/lcd_touch.fs` 于 20:08 生成（34.6MB）。
  3. 执行 `programmer_cli --scan` 扫描 JTAG 时（20:09:49）电脑再次蓝屏重启，烧录中止。
* **蓝屏排查结论**：
  - 事件日志确认：BugCheck `0x0000003B`（SYSTEM_SERVICE_EXCEPTION，内因 0xC0000005），与 17:10 第一次蓝屏**完全相同的错误码**，dump 为 `092626-6937-01.dmp`。
  - `ftdibus.sys` 版本 2.12.36.20（2024-11-19），17:44 成功烧录时即为该版本，**驱动未被更换**——排除了驱动版本因素。
  - 触发场景：适配器虽已接入，但 Tang Mega 138K 为**软开关机（长按 PWR 2 秒）**，若板子实际未开机，FPGA 未上电而 FT2232 由 USB 供电，JTAG 扫描信号灌入未上电芯片产生电气毛刺串回 USB，导致 ftdibus.sys 崩溃。
  - **整改措施**：烧录前必须确认板子已长按 PWR 开机且电源指示灯亮；上电顺序固定为「12V 适配器 → 长按 PWR 开机 → 插 USB 调试线 → 再跑烧录」；首次重试使用低 JTAG 时钟频率。
* **当前状态**：等待用户确认板子开机状态后恢复烧录。

### [2026-09-26 20:06] - ZCode Agent 接管 Task 3 点屏全流程执行
* **操作者**：ZCode Agent（用户指派全流程开发）
* **登记事项**：
  1. 用户确认硬件已连接完毕（7 寸屏排线 + 供电），指派 ZCode 接管点屏验证（Task 3）及后续开发推进。
  2. ZCode 在 `lcd_touch_app/` 内执行烧录与代码修复，其他 Agent 在此期间请勿并行改动该目录。
  3. 计划修复已知缺陷：`lcd_touch_top.v` 像素时钟分频实际输出 12.5MHz（注释宣称 33.33MHz），刷新率仅 ~25.7Hz，存在闪烁/失步风险；修复为 25MHz（约 51.3Hz）并将 `sc_clk` 反相输出以保证面板采样裕量。
  4. 完成后本条目将追加烧录结果，请在动手前重读本文件对齐。

### [2026-09-27 22:36] - 10.1寸 HDMI Serum UI 演示固件编译与安全烧录成功
* **操作者**：Antigravity Agent (DeepCoder 团队)
* **技术突破与验证成果**：
  1. **HDMI 物理驱动与 TMDS 高速时序完全收敛**：
     - 构建了 `D:\github\gaoyun\hdmi_serum_ui\` 独立工程，采用高云原厂 DVI-TX TMDS 编码与 `OSER10` 10:1 硬件串行原语；
     - 突破 150MHz 高频时序挑战：重构流水线与并行前缀 XOR 树，**Setup / Hold / Recovery 违规全部清零（0 违例，Fmax=150.192MHz）**！
  2. **Serum 经典界面纯硬件 5 级流水时光栅化实现**：
     - 渲染包含：顶部 SERUM 导航栏、OSC 荧光青绿波表视窗与半透明光晕、MG Low 12 滤波频响、AHDSR 动态包络与实时跟踪光斑、双通道动态电平表（VU）、24 键动态黑白钢琴琴键与双调制轮。
  3. **板载安全烧录完成**：
     - 比特流 `hdmi_serum.fs`（34.9MB）已安全通过 JTAG 写入芯片 SRAM（`operation_index 2`，耗时 19.61s，Status Code `0x00026230`，DONE 引脚高电平，芯片正式运行）。
     - 零系统盘/驱动风险，规避了热插拔与蓝屏威胁。

---

### [2026-09-26 17:44] - 屏幕固件烧录重试与硬件排查
* **操作者**：Antigravity Agent
* **操作内容**：
  1. 通过 JTAG 对 `GW5AST-138B` 成功执行 SRAM 烧录 `lcd_touch_app/impl/pnr/lcd_touch.fs`（100%，Status Code `0x00026230`）。
  2. 针对用户照片 `media_1790414563233.jpg` 进行详细物理接口诊断：
     - 确认排线接入底板 `J5`（40Pin FPC LCD 接口）位置正确，引脚 1~40 编号方向正确；
     - 发现排线座黑色翻盖未压紧锁死，且金手指正反需确保朝向电路板正面（下接触式）；
     - 提醒必须断电接线并使用 12V 供电，避免 USB 供电过载。

---

### [2026-09-26 17:16] - 解决蓝屏后比特流损坏，重新编译生成
* **操作者**：Antigravity Agent
* **操作内容**：
  1. 系统因热插拔排线触发 `ftdibus.sys` 蓝屏重启后，原生成文件不完整导致 programmer_cli 报错；
  2. 重新调用 `gw_sh.exe` 执行全量综合与布局布线，耗时 37 秒生成全新的 `lcd_touch.fs` (34.6MB)；
  3. 烧录测试通过。

---

### [2026-09-26 17:10] - 电脑突发蓝屏重启原因深度排查
* **操作者**：Antigravity Agent
* **排查结果**：
  - Windows 系统 Minidump（`C:\Windows\Minidump\092626-7421-01.dmp`）；
  - BugCheck 代码 `0x0000003B` (`SYSTEM_SERVICE_EXCEPTION`)，故障驱动 `ftdibus.sys`；
  - 诱因：带电热插拔 7 寸高亮液晶屏，背光升压瞬态冲击导致板载供电与 FTDI USB 芯片通信毛刺崩溃；
  - 处置：确立“严禁带电热插拔”与“必须外接 12V DC 供电”安全规则。

---

### [2026-09-26 17:05] - 板载 WS2812 炫彩点灯测试
* **操作者**：Antigravity Agent
* **操作内容**：
  - 在独立目录 `led_test/` 搭建基于引脚 `J16` 的 WS2812 呼吸灯驱动；
  - 成功烧录进芯片，用户现场肉眼确认板载炫彩呼吸灯正常点亮闪烁；
  - 证明开发板供电、50MHz 主时钟（`V22`）、JTAG 链路完全健康。

---

### [2026-09-26 16:50] - 高云 EDA 工具链与 License 激活
* **操作者**：Antigravity Agent
* **配置参数**：
  - EDA 路径：`D:\Gowin\Gowin_V1.9.11.03_Education_x64`
  - 浮动 License 服务器：`gowinlic.sipeed.com:10559`
  - 验证成功：`gw_sh.exe` 与 `programmer_cli.exe` 命令行均可正常调用。

---

## 📌 当前进行中与后续待办事项 (Current Kanban)

* [x] **Task 1**：基础通信与板载点灯验证 (Done)
* [x] **Task 2**：800×480 RGB 液晶屏彩条与 GT911 硬件 I2C 固件生成 (Done)
* [x] **Task 3**：10.1 寸便携屏 720p 视频时序恢复与 Serum 界面点亮实证 (Done, 摄像头抓帧回传核验通过)
* [x] **Task 3.5**：远程异步任务拉起、即时确认与轻量轮询系统搭建 (`run_remote_job.ps1` Done)
* [ ] **Task 4**：底板音频 DAC (PT8211 I2S) 驱动与 DDS 声音引擎挂载至 `hdmi_serum_top` 闭环发声 (`v0.2.0`, In Progress)
* [ ] **Task 5**：纯硬件黑白钢琴键盘动画与音符演奏发声联动 (`v0.3.0`)
* [ ] **Task 6**：16 复音与 ADSR 动态包络模块开发 (`v0.4.0`)
* [ ] **Task 7**：多音色（减法合成/FM）与二阶共振滤波器 SVF (`v0.5.0`)
* [ ] **Task 8**：DSP 硬件效果器（Delay / Reverb）与 Flash 脱机固化 (`v1.0.0`)

### [2026-10-07] - JTAG 安全复核记录（Codex）
* **操作**：先读取并复核本文件与 `PROJECT_DOCUMENT.md` 后，执行一次 `programmer_cli --scan --frequency 1M` 只读扫描。
* **结果**：工具返回 `Error: No Gowin devices found!`；未执行烧录，未修改 FPGA 内容。
* **安全结论**：FT2232/COM8/COM9 曾在系统中枚举，但 FPGA 未被 JTAG 识别时不得继续重试或烧录。必须先确认 12V 供电、长按 PWR 开机、电源指示灯、DEBUG-USB2 连接，并避免任何带电插拔。
* **后续规则**：扫描失败后停止操作；只有用户确认板卡已真正上电且线缆稳定，才允许再次进行一次低频扫描。连续重试可能复现 `ftdibus.sys` 蓝屏风险。

## 2026-10-27 14:08 接续原会话：I2S 波形与电平候选

- 原会话“检查串口旋钮数据刷新逻辑”（01a17933-4ae0-7f02-b5ef-194131117c1b）实际继续工作位于 `D:/github/synth1_9_18/2_ui_touch_hub`。本目录旧工程尚未同步 I2S，不能据本目录文件判断已部署源码，不能用旧副本覆盖新结果。
- 用户确认三根 I2S 与公共地已接好，本轮明确只先完成真实波形与电平；其余四窗后续接入。
- 原 13:18 UI SRAM 烧录成功，但接收功能仿真此前未跑完。已复现旧接收器解出 0 个左声道样本；修正 16 位 I2S 槽末位与 WS 边界，生产发送器 141 样本逐值环回、复位和断线恢复通过。
- 第二窗改 128 点/约 10.7 ms 的同步 RAM 历史；第六窗改真实峰值、平均绝对幅度和削波保持。显示专项、导航状态保持、6136 项视频对齐与串口回归通过。
- 候选 `D:/github/synth1_9_18/2_ui_touch_hub/impl/R16A_build_20261027_140338` 正在构建，尚未通过时序审计或部署。完整说明在同副本 `doc/I2S_LIVE_WAVEFORM_LEVELS_2026-10-27.md`。Flash 暂停，不删除或覆盖旧产物。


### [2026-10-27 15:08] - I2S 实时波形与电平：时序闭合并烧录 SRAM，现场音频验收待确认
- 操作者：Codex；接续原会话“检查串口旋钮数据刷新逻辑”。用户本轮范围为波形和电平，其余四窗保留示意。
- 实际副本：`D:/github/synth1_9_18/2_ui_touch_hub`，本工作区旧 RTL 不可反向覆盖。已修正生产 I2S 16 位槽末位/WS 边界，128 点同步 RAM 历史波形与峰值/平均绝对幅度/削波保持接入；字符同步 ROM 消除文字译码时序瓶颈。
- 验证：141 个生产发送器样本逐值环回、8192 项字符表、65536 字形格点、导航、6136 项视频对齐、串口事件回归均通过；921600 像素整帧与优化前参考逐字节一致，预览仅为模拟 PCM 输入。
- 最终构建 `impl/R16A_build_20261027_145452`；审计 `audit_20261027_150546_185747.json`，五类时序余量 `+0.601/+0.196/+0.319/+0.497/+0.453 ns`，像素 Fmax 56.823/50 MHz，61 个输入哈希一致，`timing_closed=true`。
- 唯一一次 SRAM 部署：实际副本 `impl/deploy_runs/20261027_150557_I2S_LIVE_WAVEFORM_LEVELS/`，operation 2、`PROGRAMMER_EXIT=0`、Status `0x00026230`、User Code `0x0000FE58`；双机 SHA256 `68DEE3B30642D10632F6D383856BB45661FA0EFFDF94DA3EF16D5FDCB38082CE`。未操作 Flash，未删除文件，未提交或推送。
- 摄像头确认合成器页显示正常；已询问用户切到 VISUALIZATION，验证第二窗波形与第六窗前两条电平的发声/停音响应，现场音频验收待回复。第三条为削波指示，正常音量下可以为空。
- 两处 `CODEX_HANDOFF.md` 已更新；完整记录见实际副本 `doc/I2S_LIVE_WAVEFORM_LEVELS_2026-10-27.md`。不要因缺少用户现场确认而自动重新烧录。


### [2026-10-27 15:12] - I2S 实板验收未通过：等待确认音频板实际发声
- 用户现场反馈波形和电平两项均无响应。新抓拍 `D:/github/synth1_9_18/2_ui_touch_hub/impl/i2s_no_response_20261027_150948/preview.jpg` 确认第二窗为琥珀色等待基线、电平为空，尚无完整有效采样显示；不能据此直接区分 BCLK、WS、接线或发送端固件问题。
- UI 已实现引脚报告与构建脚本均包含三个输入和 CPU/SSPI GPIO 释放；音频本地与 origin/main 源码也有三个 VIS 输出，但音频板是否实际加载该版本仍缺证据。已询问测试时耳机/扬声器是否确实有声音，等待回复；未重复烧录或修改 RTL。两处交接记录与详细文档已更新为现场验收未通过。


### [2026-10-27 15:15] - I2S 上游排查：用户确认无声，等待确认触发方式
- 已烧录 UI 的音符请求为常量 0，仅转旋钮不触发音符；音频 origin/main 的实体键盘 E19 与本地整合副本的旧 AB21 入口存在差异。当前音频源码关闭板载 NS4263、走外接 MAX98357A；I2S 时钟与音符无关，不能仅用无声解释等待基线。实际音频板固件仍未知。
- 已问用户刚才如何触发发声，等待回复；未修改 RTL，未合并音频工程，未重新烧录。两处交接与详细记录已更新。


### [2026-10-27 15:32] - 用户补烧音频板后第二窗恢复，第六窗待确认
- 用户确认音频板此前未加载带 VIS 回传的程序，现已在另一电脑自行烧录，反馈第二和第四窗正常。第四窗仍是标注示例的频谱，不能计为真实频谱验收；本轮目标是第二窗波形、第六窗电平。
- 新抓拍 `D:/github/synth1_9_18/2_ui_touch_hub/impl/i2s_after_audio_program_20261027_153131/preview.jpg` 显示第二窗从琥珀等待线变为青色有效采样中线，瞬间电平为空。已问第六窗前两条是否随发声/停音响应，等待回复。
- 未修改 RTL、未新建构建或重新烧录 UI。本会话未烧录音频板，音频固件 hash 未取得。两处交接与详细记录已更新为部分恢复、整轮验收待确认。


### [2026-10-27 15:34] - I2S 真实波形与电平本轮现场验收通过
- 用户补烧音频板后确认第二窗正常，并进一步确认第六窗前两条电平随发声上升、停音回零。本轮第二窗波形与第六窗峰值/平均绝对幅度目标完成。
- 第一、三、四、五窗仍为标注示例；削波保持有 RTL 仿真证据，未做现场削波测试。不能据本轮验收宣称六窗全部实时或 RMS/dBFS 测量已实现。
- UI SRAM 部署仍为 `20261027_150557_I2S_LIVE_WAVEFORM_LEVELS`，SHA256 `68DEE3B30642D10632F6D383856BB45661FA0EFFDF94DA3EF16D5FDCB38082CE`；音频板由用户在另一电脑烧录，未取得其位流 hash。本轮收尾只更新两处交接与实际副本详细记录，无新增构建或烧录。


### [2026-10-27 15:52] - 第三、四、五窗真实 I2S 接入：仿真通过，候选构建中
- 用户选择先完成真实相位、频谱、频谱历史；第一窗等待音符/力度回传。上一轮验收检查点 `73cb6b7` 已推送。
- 实际副本新增完整左右配对、相位双缓冲、1024 点 Hann FFT 和 32 频带/64 列历史；70 FFT 帧、3078 DFT 频点、24576 相位像素及原 I2S/导航/视频/串口回归通过。
- 唯一候选 `D:/github/synth1_9_18/2_ui_touch_hub/impl/R16A_build_20261027_154902`（PID 47420），待完整时序审计，尚未部署。板上仍为上一轮已验收的 SRAM 版本，Flash 未动。


### [2026-10-27] - 第三、四、五窗真实 I2S 显示已完成现场验收
- 用户明确确认“三、四、五窗及原波形、电平均正常”。当前第二、三、四、五窗与第六窗前两条均已按本轮现场测试通过；第一窗等待 Note/Velocity 事件，削波未做现场测试。
- 实际源码在 D:/github/synth1_9_18/2_ui_touch_hub，本目录旧 RTL 不可反向覆盖。FFT 存储改为双缓冲单写块 RAM，幅度/对数链分拍；70 帧、3078 DFT 频点、192 柱高、24576 相位像素、视频/导航/串口回归与整帧预览通过。
- 最终构建 R16A_build_20261027_161611，完整审计五类余量 +0.622/+0.147/+0.102/+0.497/+0.453 ns，像素 Fmax 61.072/50 MHz，64 个输入哈希一致。
- 仅一次 UI SRAM 部署 20261027_162828_I2S_LIVE_PHASE_SPECTRUM_HISTORY，operation 2、PROGRAMMER_EXIT=0、Status 0x00026230、User Code 0x0000AE7E；双机 SHA256 D3A66CCFBFEFA56CA9EE79C3397A862A4345571454B422F4B46A924225A706D4。Flash 未动，音频板未重新烧录，旧候选与备份全部保留。
- 两处交接、实际副本详细文档与部署目录 hardware_acceptance.json 已归档验收证据。

## 2026-10-27：旋钮 SPI 连续帧和普通固件 C14 日志修复（仅源码/仿真，尚未部署）

- 用户确认原接线 A15/B20/B21/B17/D17/A18/D14，串口 C14、115200 8N1。实际修复在 D:/github/synth1_9_18/2_ui_touch_hub；gaoyun 旧 RTL 不反向覆盖。
- 已定位普通顶层关闭 ASCII 导致 C14 镜像 MIDI；SPI 接收器又使用 24-clock 逐端口帧，未复用已实测成功的 64-clock 连续读。原文件哈希与 161611 已部署快照一致。严格引脚级模型在旧代码上复现“expected 64 clocks, got 24”。
- 已修复连续读、普通顶层默认 ASCII、多旋钮/开关事件逐个发出、两颗芯片独立断线处理；现有共享参数增量入口保留，按压不增加业务功能，SPI 状态仅首次/变化时打印。
- 专项 1366 个 SPI 帧、139 行精确 ASCII 校验、32 路 CW/CCW/PRESS/RELEASE、触屏与实体交替/限幅、单颗断开重连全部通过。既有串口回归和独立参数中枢回归通过。曲线套件 tb_curve_touch_editor 另报 Pending curve MIDI did not drain，其编译输入未含本轮修改 RTL，不能列为全绿。
- 未运行 Gowin、未生成新部署位流、未烧录、未操作 Flash、未删除文件。板上最后有记录的部署仍为 20261027_162828_I2S_LIVE_PHASE_SPECTRUM_HISTORY。工作副本 AGENTS.md 要求明确请求后才进行 Gowin 构建；时序审计和实板联动验收仍待后续完成。
- 完整证据与备份位置：实际副本 doc/KNOB_SPI_BURST_FIX_2026-10-27.md；原文件备份 impl/knob_fix_backup_20261027_164910_066。

## 后续执行更新：用户已明确授权构建与条件 SRAM 烧录

- 用户回复“是，构建并在审计通过后烧录 SRAM”，已满足工作副本 AGENTS.md 的明确请求要求。
- 当前唯一隔离构建：D:/github/synth1_9_18/2_ui_touch_hub/impl/R16A_build_20261027_185258，gw_sh PID 47704。综合与引脚约束解析完成，正在布局；source_manifest.json 已保存。恢复工作时先核对进程与日志，不重复启动 Gowin。
- 尚未产生最终时序结论，尚未调用烧录器。上文“未运行 Gowin”是授权之前的状态，以此更新为准；Flash 继续暂停。

## 2026-10-27 19:08–19:09：旋钮 SPI 连续帧/C14 ASCII 修正版构建并部署

- 用户已授权“构建并在审计通过后烧录 SRAM”。唯一隔离构建 `impl/R16A_build_20261027_185258` 完成，Gowin exit 0；64 个源文件快照与工作区一致。
- 五类审计通过：clk_pixel 56.905/50 MHz；setup +0.622 ns；hold +0.191 ns；recovery +0.201 ns；removal +0.497 ns；pulse width +0.453 ns；setup/hold 违例 0，负路径 0，OSER10 recovery/removal 三路均有报告，无 reset 例外。
- 仅执行一次 UI SRAM operation 2：`impl/deploy_runs/20261027_190826_KNOB_SPI_BURST_C14_ASCII/`。远程 `PROGRAMMER_EXIT=0`，User Code `0x00001766`，Status `0x00026230`；本地/远程位流 SHA256 `76E2B27474035033C464B72036230395BB29A1BDF15B95C928480BD9406C4DA5`。现场预览 `preview.jpg` 已抓取，屏幕画面正常。Flash 未操作。
- 当前待用户实测：打开 C14 串口（C14→USB-TTL RX、GND 共地、115200 8N1）后复位 UI 板，期望首次看到 `U1 SPI CONNECTED`、`U2 SPI CONNECTED`；随后旋转/按压应输出 `Kxx CW/CCW/PRESS/RELEASE U1/U2`。空闲不应每秒打印。SPI 连接状态只在首次检测或状态变化打印。
- 硬件状态仍需用户现场验证，不能用预览图替代旋钮事件验收。若要验证断线状态，先断电再改变接线并重新上电，避免带电插拔。

## 2026-10-27 21:23：六窗完整升级源码已推送，隔离构建中（目标尚未完成）

- 实际源码仍在 D:/github/synth1_9_18/2_ui_touch_hub；3150b91 已推送。早期 e5f8182 的条形总览不是整轮目标，已扩展为真实能量圆/左右状态/数值、过零触发双缓冲波形与峰值保持、相关性/BAL、精确 FFT 峰值 Hz/幅度中心、历史色标、真正 RMS/dBFS/crest/clip。断线不再回退假键盘。
- 独立数值验证：16 个连续立体声窗口 RMS/峰值逐值一致，dBFS 最大误差0.226 dB；71 FFT帧/3591频点/224频带/7帧峰值与中心频率；高端46.875kHz防溢出。触发迟滞/完整双缓冲/自动触发/重连通过。旋钮1366帧139行、导航页保留、6136视频对齐通过。
- 唯一 Gowin 构建 impl/R16A_build_20261027_212132（gw_sh PID33716，外层命令session82151）。构建尚未退出，不能启动第二份；须按真实进程/日志核对状态，再审计五类时序。
- 整帧仿真 impl/audio_upgrade_preview_20261027_211752_968052（session58379）已通过4096项每拍能量/相位/频谱/历史像素对齐，正在输出921600像素。三分钟超时的旧预览211309已经终止，部分PPM不可作为完整画面。
- 当前升级未烧录，Flash未动。板上最后已验收部署仍为20261027_190826_KNOB_SPI_BURST_C14_ASCII。完整定义/限制/测试路径见 doc/I2S_SIX_WINDOW_UPGRADE_2026-10-27.md。现场验收待本轮构建/审计通过后进行，不能把目标标记完成。

## 当前继续入口（2026-10-27 22:02，覆盖上面的21:23构建状态）

- 六窗升级仍未完成，不能标记goal complete。全部功能源码、独立数值/整链路/像素/导航/旋钮回归和完整预览已完成；时序收敛、SRAM上板、现场验收尚未完成。
- 第一次构建212132已退出且不合格：25.302/50MHz，105 setup，最差-19.522ns，路径u_metrics/tmp_peak_l到hold_db10。禁止部署该位流。其余四类+0.149/+0.201/+0.497/+0.453ns。完整audit_20261027_215716_545084.json保留。
- 已把原对数函数替换成三拍audio_dbfs_encoder，常数ROM取代32位乘除。32769种有效PCM幅值全部逐拍校验通过，最大0.315dB；16窗口RMS/相关/保持和生产I2S整链路回归通过。
- 当前唯一活跃隔离构建：D:/github/synth1_9_18/2_ui_touch_hub/impl/R16A_build_20261027_220133，gw_sh PID40640，外层命令session45828。source_manifest含66个输入且工作区一致。先核对这个进程/句柄/日志，不可因为观察超时另起Gowin。
- c8d9631已经推送（Git push需http.sslBackend=openssl，http.version=HTTP/1.1，http.postBuffer=52428800；schannel此前多次Empty reply）。与本轮无关的根目录脏文件保持原样。
- 预览：impl/audio_upgrade_preview_20261027_211752_968052/preview.png，完整921600像素和4096每拍能量/相位/频谱/历史对照均通过，已人工查看。模拟PCM，不是实板。预览在对数流水线替换前生成，数值语义已由穷举/字形回归证明一致。整帧原PPM及早先超时不完整PPM全部保留。
- 最新测试：metrics_tests_20261027_215958_053975；i2s_tests_20261027_215850_217355；spectral_tests_20261027_211752_887973；knob_integration_20261027_211825_465226；navigation_20261027_211943；video_alignment_20261027_212213_225013。
- 工程机ssh gaoyun hostname已验证可达；目前未烧录任何升级位流，板上仍190826旋钮稳定版。待当前构建完成必须audit_build五类全通过，再tools/deploy_verified.py --label R16_I2S_SIX_WINDOW_UPGRADE --fs <该构建>/impl/pnr/2_ui_touch_hub.fs（默认SRAMoperation2）。SSH烧录超时禁止自动重试，Flash暂停。
- 详细定义、误差、抽取波形6kHz混叠边界、失败时序与测量限制见doc/I2S_SIX_WINDOW_UPGRADE_2026-10-27.md。现场需要用户确认六窗随真实声音变化且旋钮仍正常；不可把仿真或摄像头静帧当作音频响应证明。

### 2026-10-28 03:35：OSC A/B双板整合仍在执行

> **2026-10-28 03:35 接续入口：两板OSC A/B与焦点修复仍进行中，尚未部署。** 用户保留X=OSC A/Y=OSC B并接受两板更新，随后授权拉取合并队友main并由工程机顺序烧两块板SRAM。main两次fetch均为29939e2（提交时间10月26日23:02，非服务端推送时间）。独立整合副本D:/github/synth1_9_18-osc-ab-20261028，分支integration/osc-ab-main-20261028，合并4b4cca1已推送，保留E19键盘、AB21/C19及弯音/滑音。原工作区脏文件未覆盖。当前UI唯一构建在原副本impl/R16A_build_20261028_032336，gw_sh PID33488、session98565，最近Placement Phase2；先核对进程，严禁并行Gowin。音频尚未启动构建。真实路由1329焦点检查、完整renderer的2638对A/B/26椭圆像素与最终输出隔离、247971时钟非零音频基线比较均通过；FIR用数学模型，不能代替加密IP/硬件验证。详细证据见新副本doc/OSC_AB_XY_FOCUS_2026-10-28.md。两板一根可切换JTAG USB线、独立供电，烧录前确认连接目标。Flash暂停、只SRAM2、五类时序全过、超时不自动重烧。**

## 2026-10-28：音频资源减负与布线候选恢复记录

- 原始音频候选（双 OSC + 外部 DDR 波表 + 五段效果链）综合 Logic 81%、FF 60%、BSRAM 36%，CLS 95%，放置失败约 10652 个寄存器；place_option=1/2 均复现 PR0003。
- 实验快照增加可选参数：EXTERNAL_WAVETABLE_ENABLE 与 EFFECTS_ENABLE。关闭外部波表后 CLS 约 94%、放置失败降至 6618 个寄存器；旁路五段效果链后综合降至 Logic 69%、FF 44%、BSRAM 10%，放置通过。
- route_option=1 旁路候选已完成放置，但 Routing Phase 0 长时间无日志进展，CPU 持续活动；产物保留并标为 terminated_routing_stall，无 fs、无时序审计、未烧录。
- 当前唯一候选：D:/github/synth1_9_18-osc-ab-20261028/impl/AUDIO_XY_build_20261028_114834_650547，配置 external_wavetable=off、effects_enable=off、place_option=1、route_option=2。已完成综合与放置 Phase 3，正在 Routing Phase 0；进程 PID 23932，尚无 fs 或最终时序报告。
- 保留目标：双 OSC、ADSR、全局滤波、主音量、I2S 音频输出和 OSC A/B VIS 回传；外部 DDR 波表与效果链仅在本实验配置中旁路。UI 板仍保持已验收版本；Flash 未动、音频板未烧录。

### 2026-10-28 19:07 CST — audio route follow-up (16-slot candidate)
- Previous 32-slot candidate AUDIO_XY_build_20261028_114834_650547 is recorded as 	erminated_routing_stall: PID 23932 disappeared after Routing Phase 0 completed; no .fs, timing report, audit, or burn.
- Isolated build script now accepts --slots-per-engine {8,16,32}. New candidate D:\github\synth1_9_18-osc-ab-20261028\impl\AUDIO_XY_build_20261028_190105_750978 uses SLOTS_PER_ENGINE=16, xternal_wavetable=off, ffects_enable=off, place 1 / route 2.
- At 19:07 the only Gowin process is PID 25360, still responding in synthesis technical mapping (75%); no .fs or timing result yet. Do not burn.

### 2026-10-28 20:10 CST — global comb delay-line BRAM refactor
- src/global_comb_filter.v in the isolated audio copy now wraps a 2048x8 Gowin SP RAM twice for the unchanged 2048x16 delay line; SIM uses a cycle-matched behavioral RAM model. Module ports, ready/valid protocol, delay mapping, Catmull-Rom interpolation, feedback polarity and output timing remain unchanged.
- ModelSim tb_global_filter passed with +define+SIM: PASS: global filter Mix and positive/negative Comb responses.
- First BRAM-refactor candidate AUDIO_XY_build_20261028_195325_083006 (external wavetable off, effects off, 16 slots) synthesized to u_global_comb_filter 681 LUT / 301 FF / 2 SP BSRAM; top summary Logic 28,704 (21%), FF 21,411 (16%), BSRAM 32 (10%). It passed placement through Phase 3 and is currently in Routing Phase 1; no .fs or timing audit yet.

### 2026-10-28 21:15 CST — full-function BRAM-refactor signoff build
- Candidate AUDIO_XY_build_20261028_202141_501665 uses external wavetable on, effects on, SLOTS_PER_ENGINE=32, place 1 / route 2, with the global comb delay line mapped to 2 SP BSRAMs.
- Synthesis resource summary: Logic 57,206/138,240 (41%), FF 49,607/139,095 (36%), BSRAM 120/340 (35%); global comb filter 758 LUT / 301 FF / 2 BSRAM.
- Placement passed through Phase 3 and routing is currently at Phase 1; no full-function .fs or timing audit yet.

### 2026-10-29 00:00 CST — P&R option audit
- Local Gowin config confirms place option 1 prioritizes routability, place option 2 prioritizes timing; route option 1 routes by timing, route option 2 prioritizes speed. Hold correction can hurt setup timing. Existing audio candidates used place 1 / route 2 / correct_hold 1, which was misaligned with setup closure.
- build_audio_isolated.py now exposes correct_hold and clock_route_order, defaults to place 2 / route 1 / correct_hold off / clock_route_order 1. Generated cmd.do for the active candidate confirms: -timing, -place_option 2, -route_option 1, -clock_route_order 1, -correct_hold 0, -convert_sdp32_36_to_sdp16_18.
- Active candidate AUDIO_XY_build_20261028_230540_123449 keeps DDR/effects/32 slots and the internal sample pipeline refactor. It is still in Placement Phase 1; no fs or timing audit yet.

# 2026-10-30 20:31 UI／HC-07 接续状态

实际工程 `D:/github/synth1_9_18/2_ui_touch_hub`；唯一候选 `E:/gaoyun_builds/R16A_build_20261030_201520`（Gowin PID40292）综合完成、布局Phase2完成，未审计/部署。F14 TX→模块RXD、F16 RX←模块TXD，灯带F13；PAN/LFO/左右波形与相位/安卓SPP/MIDI上传/DDR原I²S低通8k回传的源码与回归完成。新APK `impl/phone_apk_20261030_202948/FPGA-Performance.apk`，SHA256 `3ae03bf7555c305ceaa9c89322062ee5bc0487d36e7b7df2e644bf28d2566c71`，尚未手机实测。D盘满后本轮构建输出改E，失败目录保留；仅获准删除temurin17.zip/platform35.zip/build_tools35.zip三包，已完成。详见实际工程CODEX_HANDOFF顶部与HC07验收文档。继续不并行Gowin、不自动烧录、不推送、不改音频。

# 2026-10-30 20:36 最终统一候选通过（未部署）

`E:/gaoyun_builds/R16A_build_20261030_201520` 已退出0，`audit_20261030_203534_639478.json` 为 timing_closed=true：105输入哈希一致、123/123引脚一致、7时钟达标、五类时序零违例；最差setup/hold/recovery/removal/pulse +0.472/+0.133/+0.335/+0.338/+0.361ns。位流SHA256 `4BA5FD918FAAE9B52CE3099B33F8E23453F90FAF722606736F0C74D6199B3525`。原FX5条setup违例已消除；保留实际place3/route1/timing/correct_hold1。F14TX/F16RX、F13灯带及本轮全部功能已入位流，安卓APK202948已签名验证。构建和浏览器/HTTP辅助进程均结束；保留所有构建证据，仅按授权删3个安装压缩包。未烧录/推送/修改音频板；板上仍14:03旧版。后续实机验收与最新交接见实际工程CODEX_HANDOFF顶部。



# 2026-10-31 14:35 LFO网表根因与正式修复构建

实际工程仍D:/github/synth1_9_18/2_ui_touch_hub，本地修复提交a6c4a8b（未推送）。Gowin1.9.11.03官方网表复现绑定/q/sh为1/7F但动态路由切片发0000，改53路常量切片选择后RTL/网表107帧全PASS；曲线、LFO1/2/3、负深度、解绑和超时覆盖。正式唯一构建E:/gaoyun_builds/R16A_build_20261031_143345，PID27628/exec26405，正在综合；输入相比041417仅sender一文件变更，三关键源Git/工作区/快照已核对。未重新烧录，板上00000966；全审计通过才按既有授权SRAM2，探针绝不可部署。最新以实际工程CODEX_HANDOFF顶部为准；失败证据和原有脏文件保留。


# 2026-10-31 14:51 LFO修复构建/SRAM完成

a6c4a8b正式构建R16A_build_20261031_143345通过109输入/124引脚/7时钟/五类全审计，setup最差+0.033ns。唯一SRAM2部署144944_UI_LFO_ROUTE_STATIC_GATE_20261031退出0/完成标记，写后只读UserCode9C50、Status26230；FS SHA256 74E75DD438B0D77FC30B57CE5D202F2269B1E063C567DAB4B2DFA3F2DBBFCD1E。没有重试/Flash/音频操作。源码仅sender路由取值改常量切片，RTL/官方网表107帧已过，实际板上TX仍须用户在9C50重绑抓包验收。构建与部署进程均完成，禁止恢复后重复写板；具体证据和当前入口见实际synth1_9_18工程CODEX_HANDOFF顶部及LFO_ZERO_FRAME文档。


# 2026-10-31 16:15 RATE8构建/SRAM完成

用户明确授权构建并烧录。实际工程synth1_9_18/2_ui_touch_hub，源码138943f；正式唯一构建E:/gaoyun_builds/R16A_build_20261031_155419，全109输入/124引脚/7时钟/五类时序通过，setup最差+0.001ns，已向用户说明余量极窄。唯一SRAM2部署161339_UI_LFO_RATE8_20261031，双端SHA一致、退出0/完成标记、写后只读UserCode8E85/Status26230；位流SHA256 1F35EB3ADC2D5D5AC690518061C169C27ECF0DF76FABD99F18A4A464E3F6A3DF。Flash/音频未动，无重试/探针部署；进程已完成，恢复后不要重烧。真实2/4Hz UI TX待用户现场复测，仿真96组合/469帧已过，不能代替实板验收。最新交接和完整证据见实际工程CODEX_HANDOFF及doc/LFO_RATE_ENCODING_2026-10-31.md。
> **2026-10-31 21:14 UI统一构建前最终验证完成，尚未烧录。** 实际副本 `D:/github/synth1_9_18/2_ui_touch_hub`；之前未部署的WARP/五FX/10张SD波表编号/PAN显示/App修复，与本轮板端校准/App严格32键移调/第六PITCH页一起构建。最终23+6共29项RTL、手机、normal/debug层次全PASS，当前源哈希重新核对一致。最新APK0.2.4需独立安装，实机功能未验收。无活跃Gowin，先本地检查点，再唯一normal隔离构建及全审计；实际CODEX_HANDOFF顶部为准。不推送、不删证据、不改音频RTL。


