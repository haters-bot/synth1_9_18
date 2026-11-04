(() => {
 "use strict";
 const P=PerformanceProtocol,T=P.TYPES,$=id=>document.getElementById(id);
 const state={client:null,socket:null,song:null,status:null,working:false,selecting:false,saving:false,saveWait:null,writeWait:null,linkConnected:false,helloPayload:null,handshakePromise:null,handshakeAttempts:0,link:null,
  device:"",transport:"蓝牙",baud:null,recordInfo:null,recordCapabilities:false,downloads:[],downloading:false,pauseDownload:false,
  placement:0,compress:false,adaptationCache:null};
 const native=window.PhoneNative;
 const durable=!!native?.downloadAction,downloadRequests=new Map();let downloadRequest=0;
 function nativeAction(action,data={}){
  return new Promise((resolve,reject)=>{
   const id=++downloadRequest,dialog=["export","delete","confirmOverwrite","confirmDiscard"].includes(action);
   const timer=dialog?null:setTimeout(()=>{downloadRequests.delete(id);reject(Error("手机缓存操作超时，保留已有文件；可重新打开 App 检查进度"));},30000);
   downloadRequests.set(id,{resolve,reject,timer});
   try{native.downloadAction(id,action,JSON.stringify(data));}catch(e){clearTimeout(timer);downloadRequests.delete(id);reject(e);}
  });
 }
 window.onNativeDownloadReply=(id,ok,value)=>{
  const p=downloadRequests.get(id);if(!p)return;downloadRequests.delete(id);clearTimeout(p.timer);
  try{ok?p.resolve(JSON.parse(value)):p.reject(Error(value));}catch(e){p.reject(e);}
 };
 let helloNonce=(Date.now() ^ Math.floor(Math.random()*4294967296))>>>0;
 const log=message=>{$("log").textContent=String(message);};
 function linkTrace(event){
  const d=state.link;if(!d)return;
  const hex=bytes=>Array.from(bytes.slice(-48),b=>b.toString(16).padStart(2,"0").toUpperCase()).join(" ");
  if(event.kind==="tx"){d.txFrames++;d.txBytes+=event.bytes.length;d.tx=hex(event.bytes);}
  else {d.rxBytes+=event.bytes.length;d.validFrames+=event.validFrames;d.badFrames+=event.badFrames;d.rx=hex(event.bytes);}
  if(Date.now()-(d.drawn||0)<200)return;d.drawn=Date.now();
  const target=$("linkDiagnostic");
  if(target)target.textContent=`App TX ${d.txFrames}帧/${d.txBytes}B · RX ${d.rxBytes}B · 有效帧 ${d.validFrames} · 坏帧 ${d.badFrames}\n最近TX: ${d.tx}\n最近RX: ${d.rx}`;
 }
 function badge(id,text){$(id).textContent=text;}
 function feedback(message,kind=""){
  const target=$("actionStatus");target.textContent=String(message);target.dataset.state=kind;
 }
 function bytes64(bytes){let s="";for(const b of bytes)s+=String.fromCharCode(b);return btoa(s);}
 function decode64(value){return Uint8Array.from(atob(value),c=>c.charCodeAt(0));}
 function calibrated(s){return !!s?.calibrationSupported && s.calibrated;}
 function adaptationOptions(){return {position:state.placement/100,compress:state.compress};}
 function adaptationPreview(){
  const output=$("songPositionValue"),target=$("adaptationStatus"),s=state.status;
  if(output)output.textContent=`${state.placement===0?"靠左":state.placement===100?"靠右":state.placement+"%"} · 校准后显示起始键`;
  if(!state.song){target.textContent="默认最低音从最左键开始。超过32键可主动开启有损八度压缩；调整后需重新发送到板卡。";return null;}
  if(!calibrated(s)){target.textContent="请先在UI板校准最左键，再按本次音域预览。原MIDI不变；八度压缩默认关闭。";return null;}
  const key=`${s.baseNote}:${s.keyCount}:${state.placement}:${state.compress}`;
  if(state.adaptationCache?.song!==state.song || state.adaptationCache.key!==key){
   try{state.adaptationCache={song:state.song,key,result:PerformanceMidi.adaptToRange(state.song,s.baseNote,s.keyCount,adaptationOptions())};}
   catch(e){state.adaptationCache={song:state.song,key,error:e.message};}
  }
  const cache=state.adaptationCache;
  target.textContent=cache.error?cache.error:`适配预览：${cache.result.adaptation.summary}`;
  if(output && cache.result){const a=cache.result.adaptation;output.textContent=`最低音从第${a.startKey}键开始 · 可右移${a.availableShift}键${!a.availableShift?"（已占满音域）":""}`;}
  return cache;
 }
 function controls(){
  const ready=calibrated(state.status),s=state.status;
  const preview=adaptationPreview();
  $("connectButton").textContent=state.linkConnected && !s?"重试板卡应答":"连接设备";
  $("connectButton").disabled=state.working || !!state.handshakePromise;
  $("uploadButton").disabled=state.working || state.selecting || !ready || !state.song ||
   (state.song.noteMax-state.song.noteMin+1>(s?.keyCount || 32) && !state.compress) || !!preview?.error;
  if($("compressRange")){$("compressRange").checked=state.compress;$("compressRange").disabled=state.working;}
  if($("songPosition")){$("songPosition").value=String(state.placement);$("songPosition").disabled=state.working || !state.song || preview?.result?.adaptation.availableShift===0;}
  for(const id of ["positionLeft","positionCenter","positionRight"])if($(id))$(id).disabled=state.working || !state.song || preview?.result?.adaptation.availableShift===0;
  $("playButton").disabled=state.working || !ready || !s.loaded;
  $("pauseButton").disabled=state.working || !ready || !s.loaded;
  $("downloadButton").disabled=state.working || !s?.storedFrames || s.busy;
  if($("cancelDownloadButton"))$("cancelDownloadButton").disabled=!state.downloading || state.pauseDownload;
  if($("discardRecordingButton"))$("discardRecordingButton").disabled=state.working || !state.recordCapabilities || !s?.storedFrames || s.busy || s.recording;
  if($("refreshRecordingButton"))$("refreshRecordingButton").disabled=state.working || !state.status;
  $("exportChannels").disabled=state.working;
  renderDownloads();
 }
 function refresh(s){
  const previous=state.status;
  state.status=s;$("recordButton").textContent=s.recording?"停止录音":"开始录音";
  if(s.recordInfoSupported){state.recordInfo=s;state.recordCapabilities=true;state.baud=s.baud;}
  else if(state.recordInfo && (state.recordInfo.generation!==s.generation || state.recordInfo.storedFrames!==s.storedFrames))state.recordInfo=null;
  $("downloadButton").disabled=state.working || !s.storedFrames || s.busy;
  $("baseNote").replaceChildren(new Option(calibrated(s)?`0x${s.baseNote.toString(16).toUpperCase()} / MIDI ${s.baseNote}–${s.baseNote+s.keyCount-1}`:"等待 UI 板校准最左键",s.baseNote));
  $("baseNote").disabled=true;
  const baud=state.baud||s.baud|| (s.fast?115200:9600);
  // Legacy status has only one fast bit; it cannot distinguish the two fast
  // dividers. Keep the last INFO rate, never guess 115200 during a busy take.
  const rateLabel=durable && s.fast && !state.baud?"115200及以上（待查询）":baud;
  badge("gatewayStatus",`板卡已应答 · ${rateLabel} baud`);
  if($("recordingStatus"))$("recordingStatus").textContent=s.storedFrames?
   `板上当前录音：第 ${s.generation} 段 · ${(s.storedFrames/s.sampleRate).toFixed(2)} 秒 · 原始双声道PCM ${(s.storedFrames*4/1048576).toFixed(2)} MiB${s.busy?" · 写入中":""}。板卡仅保留一段，新录音覆盖旧录音；断电／重配会失效。`:
   "板上没有可下载录音。DDR是易失性单段缓冲，不是会不断堆积歌曲的文件系统。";
  if($("speedStatus"))$("speedStatus").textContent=baud===9600?
   "当前9600：8kHz单声道有效PCM理论上限约720B/s，32秒录音仅串口就至少约12分钟。115200约1分钟、230400约半分钟、1 Mbps约7秒；理论值未计处理和无线开销。":
   `当前${rateLabel}：保持8kHz/16bit导出。实际速度受协议、DDR、手机和无线链路影响；下方显示实测速度与剩余时间。`;
  badge("songStatus",s.loaded?`板卡已载入 ${s.events} 事件`:"板卡曲谱未就绪");
  const message=!s.calibrationSupported?"UI 固件不支持起音校准，请更新固件后上传；录音功能仍可使用。":
   s.calibrationState===2?`校准 OK：MIDI ${s.baseNote}–${s.baseNote+s.keyCount-1}（0x${s.baseNote.toString(16).toUpperCase()} 起，32键）。可以适配并发送曲谱。`:
   s.calibrationState===1?"请按实体键盘最左键一次。仅 F15 实体 Note On 可完成校准。":
   s.calibrationState===3?"此起音不在已确认的安全档位。请选择 0x29／0x35／0x41／0x4D，点击板端 CALIBRATE 重试。":
   s.calibrationState===4?"正在停止旧曲并释放音符，完成后请按最左键。":
   "已连接：请在 UI 演奏页点击 CALIBRATE，再按实体键盘最左键；校准成功后才能上传。";
  $("calibrationStatus").textContent=message;
  if(!previous || previous.baseNote!==s.baseNote || previous.calibrationEpoch!==s.calibrationEpoch || previous.calibrated!==s.calibrated){
   piano(s.baseNote);
   if(!state.working)feedback(message,calibrated(s)?"success":"info");
  }
  controls();
 }
 function piano(base=41){
  $("piano").replaceChildren();
  for(let i=0;i<32;i++) {
   const note=base+i,key=document.createElement("button");
   key.className="key"+([1,3,6,8,10].includes(note%12)?" black":"");key.textContent=note;key.dataset.note=note;
   const noteEvent=on=>{
    if((state.working && on) || !state.client || !calibrated(state.status))return;
    if(on)key.setPointerCapture?.(key._pointer);
    key.classList.toggle("active",on);
    state.client.request(T.NOTE,Uint8Array.of(note,on?100:0,on?1:0)).catch(e=>log(e.message));
   };
   key.onpointerdown=e=>{key._pointer=e.pointerId;noteEvent(true);};
   key.onpointerup=()=>noteEvent(false);key.onpointercancel=()=>noteEvent(false);
   $("piano").appendChild(key);
  }
 }
 function disconnected(message){
  state.linkConnected=false;state.client?.close();state.client=null;state.status=null;state.handshakePromise=null;state.helloPayload=null;
  $("calibrationStatus").textContent=`${state.transport}连接断开；下次连接后请重新在 UI 板校准。`;
  state.baud=null;state.recordInfo=null;state.recordCapabilities=false;
  badge("gatewayStatus","通信模块／板卡未连接");$("downloadButton").disabled=true;log(message);controls();
  if(state.saveWait){state.saveWait.reject(Error(message));state.saveWait=null;}
  if(state.writeWait){state.writeWait.reject(Error(message));state.writeWait=null;}
 }
 function handshake(manual=false){
  if(!state.linkConnected || !state.client)return Promise.resolve();
  if(state.handshakePromise)return state.handshakePromise;
  if(manual)state.handshakeAttempts=0;
  const c=state.client;state.handshakeAttempts++;
  badge("gatewayStatus",`${state.transport}已连，等待板卡 HELLO（${state.handshakeAttempts}/3）…`);
  state.handshakePromise=(async()=>{
   try {
    // Reuse the connection nonce across retries: a lost ACK must not erase a
    // calibration/score that the FPGA has already accepted for this session.
    await c.request(T.HELLO,state.helloPayload);
    if(state.client!==c || !state.linkConnected)return;
    log("双向通信成功。请在 UI 板演奏页点击 CALIBRATE，再按实体键盘最左键。每次重连或调整八度后都须校准并重新传曲。");
    if(durable && !state.status?.busy && !state.status?.recording){
     try{await recordingInfo(c);}catch(e){log(`板卡握手成功；录音信息查询失败：${e.message}，可点“刷新板上录音”重试。`);}
    }
   }catch(e){
    if(state.client!==c || !state.linkConnected)return;
    const rejected=c.lastStatus?.request===T.HELLO && c.lastStatus.code;
    badge("gatewayStatus",rejected?"板卡已应答／握手被拒绝":state.link.rxBytes?`${state.transport}已连／返回数据未通过协议校验`:`${state.transport}已连／未收到板卡返回`);
    log(`${e.message}。${state.handshakeAttempts<3?"将自动重试；也可点“重试板卡应答”。":"自动重试已暂停，可点“重试板卡应答”继续。"}${state.link.rxBytes?"已有返回字节，请查看下方收发诊断。":"RX=0：尚不能确定是接线、模块串口波特率还是板端接收问题。"}`);
   }finally{if(state.client===c){state.handshakePromise=null;controls();}}
  })();
  controls();return state.handshakePromise;
 }
 async function attach(send){
  state.client?.close();state.handshakePromise=null;state.status=null;
  state.linkConnected=true;state.handshakeAttempts=0;state.helloPayload=P.u32(++helloNonce);state.baud=null;state.recordInfo=null;state.recordCapabilities=false;
  state.link={txFrames:0,txBytes:0,rxBytes:0,validFrames:0,badFrames:0,tx:"—",rx:"—"};
  const c=new P.Client(send,{onStatus:s=>{if(state.client===c && (s.request!==T.HELLO || !s.code))refresh(s);},onTrace:event=>{if(state.client===c)linkTrace(event);}});
  state.client=c;controls();return handshake();
 }
 function nativeTransport(address){state.device=String(address||"");state.transport=state.device.startsWith("wifi://")?"Wi-Fi TCP":"蓝牙";}
 window.onNativeConnecting=address=>{nativeTransport(address);disconnected(`正在连接 ${state.device}`);badge("gatewayStatus",`${state.transport}连接中…`);};
 window.onNativeConnected=address=>{nativeTransport(address);return attach(bytes=>native.sendBase64(bytes64(bytes)));};
 window.onNativeBytes=data=>state.client?.receive(decode64(data));
 window.onNativeDisconnected=message=>disconnected(message||"通信连接已断开");
 window.onNativeError=message=>log(message);
 window.onNativeSaveReady=()=>{state.saveWait?.resolve();state.saveWait=null;};
 window.onNativeWrite=(ok,message)=>{const p=state.writeWait;state.writeWait=null;if(p)(ok?p.resolve():p.reject(Error(message)));};
 window.onNativeSaveError=message=>{
  if(state.saveWait){state.saveWait.reject(Error(message));state.saveWait=null;}
  if(state.writeWait){state.writeWait.reject(Error(message));state.writeWait=null;}
  log(message);
 };
 async function connect(){
  if(state.working)throw Error("请先等待当前操作结束");
  if(native){if(state.linkConnected && !state.status)return handshake(true);if(native.chooseConnection)native.chooseConnection();else native.chooseDevice();return;}
  if(location.protocol==="file:")throw Error("此离线网页可解析 MIDI；安卓请安装配套 APK 连接蓝牙或ESP-01S Wi-Fi桥");
  state.socket?.close();
  const socket=new WebSocket(`${location.protocol==="https:"?"wss":"ws"}://${location.host}/ws`);
  state.socket=socket;socket.binaryType="arraybuffer";
  socket.onopen=()=>attach(bytes=>{if(socket.readyState!==1)throw Error("网关连接中断");socket.send(bytes);});
  socket.onmessage=e=>{if(e.data instanceof ArrayBuffer)state.client?.receive(new Uint8Array(e.data));};
  socket.onclose=()=>{if(state.socket===socket)disconnected("网关连接已断开");};
  socket.onerror=()=>log("网关连接失败；手机直连请使用安卓 APK");
 }
 async function work(action){
  if(state.working)return;state.working=true;
  const controlIds=["chooseMidiButton","connectButton","uploadButton","playButton","pauseButton","stopButton","recordButton","downloadButton","refreshRecordingButton","discardRecordingButton","compressRange","songPosition","positionLeft","positionCenter","positionRight"];
  controlIds.forEach(id=>{if($(id))$(id).disabled=true;});
  try {await action();} catch(e){const message=e.message||String(e);log(message);feedback(message,"error");}
  finally {state.working=false;controlIds.forEach(id=>{if($(id))$(id).disabled=false;});$("chooseMidiButton").disabled=state.selecting;if(state.status)refresh(state.status);controls();}
 }
 function client(){if(!state.client || !state.status)throw Error("先连接模块并收到板卡应答");return state.client;}
 $("connectButton").onclick=()=>connect().catch(e=>log(e.message));
 function changedAdaptation(){
  state.adaptationCache=null;controls();
  if(state.song)feedback($("adaptationStatus").textContent,state.adaptationCache?.error?"error":"info");
 }
 if($("compressRange"))$("compressRange").onchange=()=>{if(state.working)return;state.compress=!!$("compressRange").checked;changedAdaptation();};
 if($("songPosition"))$("songPosition").oninput=()=>{if(state.working)return;state.placement=Math.max(0,Math.min(100,Number($("songPosition").value)||0));changedAdaptation();};
 for(const [id,position] of [["positionLeft",0],["positionCenter",50],["positionRight",100]])if($(id))$(id).onclick=()=>{if(state.working)return;state.placement=position;changedAdaptation();};
 function finishSelection(){state.selecting=false;$("chooseMidiButton").disabled=state.working;controls();}
 function selectionError(message){state.song=null;$("songTitle").textContent="尚未选择曲谱";$("songMeta").textContent=String(message);$("eventStats").textContent="0 events";finishSelection();feedback(message,"error");log(message);}
 function selectedMidi(name,data){
  try {
   const song=PerformanceMidi.parseMidi(data);if(!song.events.length)throw Error("曲谱没有 Note 事件，请选择含音符的标准 MIDI");
   song.name=name;state.song=song;state.adaptationCache=null;
   let low=127,high=0;for(const event of song.events)if(event.on && event.velocity>0){if(event.note<low)low=event.note;if(event.note>high)high=event.note;}
   if(low>high)throw Error("曲谱没有 Note On 事件");
   song.noteMin=low;song.noteMax=high;
   $("songTitle").textContent=name;$("songMeta").textContent=`${(song.duration_us/1e6).toFixed(1)} 秒 · ${song.events.length} Note事件 · MIDI ${low}–${high}`;
   $("eventStats").textContent=`${song.events.length} events`;finishSelection();
   if(high-low+1>(state.status?.keyCount || 32) && !state.compress){feedback(`曲谱音域含两端共${high-low+1}键，超过32键，暂时禁止传输；可主动勾选“允许八度压缩”后预览有损适配。`,"error");log("曲谱已解析，尚未发送；八度压缩可选，原MIDI不变。");}
   else {feedback(calibrated(state.status)?$("adaptationStatus").textContent:`曲谱音域共${high-low+1}键；校准后按所选位置适配。`,"info");log("MIDI已解析；琴键位置及压缩修改后，需点击发送才能在板卡生效。");}
  }catch(e){selectionError(e.message||String(e));}
 }
 window.onNativeMidiSelected=(name,encoded)=>{try{selectedMidi(name,decode64(encoded).buffer);}catch(e){selectionError(e.message);}};
 window.onNativeMidiError=selectionError;
 $("chooseMidiButton").onclick=()=>{
  if(state.working || state.selecting)return;
  state.selecting=true;state.song=null;$("uploadButton").disabled=true;$("chooseMidiButton").disabled=true;
  $("songTitle").textContent="正在选择 MIDI…";feedback("正在打开系统文件选择器…","info");log("请选择已下载的 .mid／.midi 文件");
  try{if(native && typeof native.chooseMidi==="function")native.chooseMidi();else {$("songFile").value="";$("songFile").click();}}
  catch(e){selectionError(e.message);}
 };
 $("songFile").oncancel=()=>selectionError("已取消选择 MIDI");
 $("songFile").onchange=async event=>{
  const file=event.target.files?.[0];if(!file){selectionError("未选取文件");return;}
  try {
   if(file.size>4*1024*1024)throw Error("MIDI 文件超过4 MiB");
   log("正在读取并解析 MIDI…");
   const data=typeof file.arrayBuffer==="function"?await file.arrayBuffer():await new Promise((resolve,reject)=>{
    const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=()=>reject(Error("无法读取所选文件"));reader.readAsArrayBuffer(file);
   });
   selectedMidi(file.name,data);
  }catch(e){selectionError(e.message);}
 };
 $("uploadButton").onclick=()=>work(async()=>{
  if(state.selecting)throw Error("请等待曲谱读取完成");
  feedback("正在检查板卡状态与曲谱音域…","info");
  const c=client(),s=await c.request(T.STATUS),original=state.song;
  if(!original?.events.length)throw Error("请选择含音符的 MIDI 曲谱");
  if(!s.calibrationSupported)throw Error("未发送：请更新支持起音校准的 UI 固件；仅更新 APK 不足以完成此流程。");
  if(!calibrated(s))throw Error("未发送：请先在 UI 板点击 CALIBRATE，按实体最左键，等待校准 OK。");
  const song=PerformanceMidi.adaptToRange(original,s.baseNote,s.keyCount,adaptationOptions());
  if(!song.events.length)throw Error("曲谱没有可演奏的 Note On 事件");
  if(song.events.length>s.maxEvents)throw Error(`适配后有 ${song.events.length} 事件，超过板卡 ${s.maxEvents} 容量；请分段导出 MIDI，不能截断上传`);
  $("adaptationStatus").textContent=song.adaptation.summary;
  await c.request(T.STOP);await c.request(T.CLEAR);
  $("progress").style.width="0%";$("progressLabel").textContent=`上传 0/${song.events.length} 事件`;feedback("正在准备上传…","info");
  await c.request(T.BEGIN,P.join(P.u32(Math.max(1,Math.ceil(song.duration_us/1000))),P.u16(song.events.length),P.u16(s.calibrationEpoch)));
  for(let at=0;at<song.events.length;at+=8){
   await c.request(T.EVENTS,P.eventsPayload(song.events.slice(at,at+8)));
   $("progress").style.width=`${Math.min(100,(at+8)/song.events.length*100)}%`;
   $("progressLabel").textContent=`上传 ${Math.min(at+8,song.events.length)}/${song.events.length} 事件`;
  }
  const result=await c.request(T.END);
  if(!result.loaded || result.events!==song.events.length)throw Error("板卡曲谱计数不匹配");
  feedback(`板卡已确认载入 ${result.events} 个事件。${song.adaptation.summary}`,"success");
  log(`板卡确认 ${result.events} 事件完整载入。按所选模式开始试听、跟弹或演奏指引。`);
 });
 $("modeSelect").onchange=()=>work(async()=>{await client().request(T.MODE,Uint8Array.of(Number($("modeSelect").value)));log("板卡已确认演奏模式");});
 for(const [id,type] of [["playButton",T.PLAY],["pauseButton",T.PAUSE],["stopButton",T.STOP]])
  $(id).onclick=()=>work(async()=>{await client().request(type);log("板卡已确认控制指令");});
 $("recordButton").onclick=()=>work(async()=>{
  const c=client(),s=await c.request(T.STATUS);
  if(!s.recording && s.storedFrames && durable && !(await nativeAction("confirmOverwrite")).confirmed)return;
  await c.request(s.recording?T.RECORD_STOP:T.RECORD_START);
  log(s.recording?"已请求停止；等待 DDR 写入排空后下载":"板卡确认开始采集音频板 I²S；没有使用手机麦克风");
 });
 function nativeWrite(bytes){return new Promise((resolve,reject)=>{state.writeWait={resolve,reject};native.appendAudio(bytes64(bytes));});}
 async function legacyDownload(){
  const c=client(),s=await c.request(T.STATUS),channels=Number($("exportChannels").value),frames=Math.floor(s.storedFrames/12);
  if(s.busy || !frames)throw Error("请先停止录音并等待 DDR 写入完成");
  if(s.recordStatus===6 || s.recordStatus===7)throw Error("本次录音存在音源／存储错误，请重新录音");
  if(s.sampleRate!==96000)throw Error("当前导出固件只支持 96k I²S 源");
  const name=`fpga_take_${s.generation}_8k_${channels}ch.wav`,parts=[];
  let saved=0;
  $("progress").style.width="0%";
  $("progressLabel").textContent=`准备读取 ${frames} 帧…`;
  try {
   if(native){
    state.saving=true;
    await new Promise((resolve,reject)=>{state.saveWait={resolve,reject};native.beginSave(name,frames,channels);});
   }else parts.push(P.wavHeader(frames,channels));
   const started=Date.now();
   for(let at=0;at<frames;at+=1024){
    const n=Math.min(1024,frames-at);
    const result=await c.request(T.READ,P.join(P.u32(at),P.u16(n),Uint8Array.of(channels)),{offset:at,count:n,channels,generation:s.generation,onProgress:received=>{
     const complete=at+received;
     $("progress").style.width=`${complete/frames*100}%`;
     $("progressLabel").textContent=`正在回传 ${complete}/${frames} 帧（${(complete/frames*100).toFixed(1)}%）`;
    }});
    if(result.pcm.length!==n*channels*2)throw Error(`板卡 PCM 长度错误：应为 ${n*channels*2}，实际 ${result.pcm.length}`);
    if(native)await nativeWrite(result.pcm);else parts.push(result.pcm);
    saved+=n;$("progress").style.width=`${saved/frames*100}%`;
    $("progressLabel").textContent=`已回传 ${saved}/${frames} 帧`;
    const remaining=Math.max(0,(Date.now()-started)/1000*(frames-saved)/saved);
    log(`下载 ${saved}/${frames} 帧 · 8kHz/${channels}声道 · 预计剩余 ${Math.ceil(remaining)} 秒。串口回传慢于原始演奏。`);
   }
   if(saved!==frames)throw Error(`录音回传未完成：${saved}/${frames} 帧`);
   if(native){$("progressLabel").textContent="声音数据已完整接收，请选择 WAV 保存位置…";await new Promise((resolve,reject)=>{state.writeWait={resolve,reject};native.finishSave();});}
   else {
    const url=URL.createObjectURL(new Blob(parts,{type:"audio/wav"})),link=document.createElement("a");link.href=url;link.download=name;link.click();setTimeout(()=>URL.revokeObjectURL(url),60000);
   }
   $("progressLabel").textContent=`完成 ${saved}/${frames} 帧`;
   log(`录音已保存：${name}。来源为板卡 DDR 中的 I²S PCM，127抽头低通后 96k→8k；末尾不足12帧舍弃。`);
  }catch(e){if(native)native.cancelSave();throw e;}
  finally {state.saving=false;}
 }
 function freshClaim(){
  const claim=new Uint8Array(16);
  if(!window.crypto?.getRandomValues)throw Error("手机随机数服务不可用，无法安全标识录音");
  window.crypto.getRandomValues(claim);if(claim.every(b=>b===0))claim[0]=1;return claim;
 }
 async function recordingInfo(c=client()){
  const status=await c.request(T.STATUS);
  if(status.busy || status.recording)return status;
  try{
   const s=await c.request(T.RECORD_INFO,freshClaim());
   if(!s.recordInfoSupported){state.recordCapabilities=false;state.recordInfo=null;return status;}
   state.recordCapabilities=true;state.recordInfo=s;return s;
  }catch(e){if(e.boardCode===1){state.recordCapabilities=false;state.recordInfo=null;return status;}throw e;}
 }
 async function loadDownloads(){
  if(!durable)return;
  const result=await nativeAction("list");state.downloads=result.entries;renderDownloads();
 }
 function renderDownloads(){
  if(!durable || !$("localRecordings"))return;
  const area=$("localRecordings");area.replaceChildren();
  if(!state.downloads.length){area.textContent="尚无本地录音缓存。开始下载后，每个完整块自动保存；断连或退出 App 后仍可恢复。";return;}
  for(const entry of state.downloads){
   const row=document.createElement("div"),label=document.createElement("span");row.className="download-entry";
   label.textContent=`${entry.name} · ${(entry.frames/8000).toFixed(1)}秒 · ${(entry.received/entry.frames*100).toFixed(1)}% · ${entry.complete?"已完整，可离线导出":"未完成，进度已保存在手机"}`;row.appendChild(label);
   for(const [title,disabled,action] of [
    [entry.complete?"导出 WAV":"继续下载",state.working || (!entry.complete && !state.status),()=>entry.complete?nativeAction("export",{key:entry.key}):downloadRecording(entry)],
    ["删除手机缓存",state.working,async()=>{await nativeAction("delete",{key:entry.key});await loadDownloads();}]
   ]){
    const button=document.createElement("button");button.textContent=title;button.disabled=disabled;button.onclick=()=>work(action);row.appendChild(button);
   }
   area.appendChild(row);
  }
 }
 function identityFor(s,channels){
  return JSON.stringify({device:state.device,token:s.recordingToken,generation:s.generation,storedFrames:s.storedFrames,channels,rate:8000,
   legacySession:s.recordInfoSupported?null:Array.from(state.helloPayload||[]).join("-")});
 }
 async function downloadRecording(resume=null){
  const c=client(),s=await recordingInfo(c),channels=resume?resume.channels:Number($("exportChannels").value),frames=Math.floor(s.storedFrames/12);
  if(s.busy || s.recording || !frames)throw Error("板上没有已完成录音；请先停止录音并等待DDR写入排空。断电或新录音可能使旧录音失效。");
  if(s.recordStatus===6 || s.recordStatus===7)throw Error("本次录音存在音源／存储错误，请重新录音");
  if(s.sampleRate!==96000)throw Error("当前固件导出只支持96k I²S源");
  if(s.recordInfoSupported && (!s.recordingToken || /^0+$/.test(s.recordingToken)))throw Error("板上录音身份未就绪，请刷新后重试");
  const identity=identityFor(s,channels),name=`fpga_take_${s.generation}_8k_${channels}ch.wav`;
  if(resume && resume.identity!==identity)throw Error("板上录音身份、音频长度或模块已改变；停止续传，保留旧缓存。若板卡仍是旧固件，跨连接续传需更新UI固件。");
  let saved=0,entry=null,finished=false;
  state.downloading=true;state.pauseDownload=false;controls();
  try{
   entry=await nativeAction("begin",{identity,name,frames,channels});saved=entry.received;
   const initial=saved,started=Date.now();
   function progress(received){
    const done=saved+received,percent=done/frames*100,elapsed=(Date.now()-started)/1000;
    const speed=elapsed>0?(done-initial)*channels*2/elapsed:0,eta=speed>0?(frames-done)*channels*2/speed:0;
    $("progress").style.width=`${percent}%`;
    $("progressLabel").textContent=`回传 ${percent.toFixed(1)}% · 手机已保存 ${saved}/${frames} 帧${received?` · 本块已收 ${received} 帧`:""}`;
    log(`${speed.toFixed(0)} B/s · ${speed>0?`预计剩余 ${Math.ceil(eta)} 秒`:"正在估算速度"} · 断连保留已保存进度，重连后手动“继续下载”。`);
   }
   progress(0);
   while(saved<frames && !state.pauseDownload){
    const at=saved,n=Math.min(1024,frames-at);
    const result=await c.request(T.READ,P.join(P.u32(at),P.u16(n),Uint8Array.of(channels)),
     {offset:at,count:n,channels,generation:s.generation,onProgress:progress});
    if(result.pcm.length!==n*channels*2)throw Error("板卡PCM长度不符，保留已有进度");
    const committed=await nativeAction("append",{key:entry.key,pcm:bytes64(result.pcm)});
    if(committed.received!==saved+n)throw Error("手机缓存偏移不一致，停止以保护文件");
    saved=committed.received;progress(0);
   }
   finished=saved===frames;
  }finally{
   await nativeAction("pause").catch(e=>log(e.message));state.downloading=false;controls();await loadDownloads().catch(e=>log(e.message));
   const retained=state.downloads.find(e=>e.key===entry?.key);if(retained)saved=retained.received;
   if(!finished)$("progressLabel").textContent=saved===frames?
    `完整录音已保留 ${saved}/${frames} 帧；可在手机缓存列表直接导出。`:
    `回传已暂停，手机进度已保留 ${saved}/${frames} 帧；重连后手动继续。`;
  }
  if(finished){
   $("progress").style.width="100%";$("progressLabel").textContent=`完整接收 ${saved}/${frames} 帧，手机缓存已保存；可随时导出。`;
   await nativeAction("export",{key:entry.key});log(`已导出 ${name}；完整缓存仍保留，可离线再次导出。`);
  }
 }
 $("downloadButton").onclick=()=>work(()=>durable?downloadRecording():legacyDownload());
 if($("cancelDownloadButton"))$("cancelDownloadButton").onclick=()=>{
  state.pauseDownload=true;controls();log("将在当前块收完并保存后暂停；不会丢弃此前进度。");
 };
 if($("refreshRecordingButton"))$("refreshRecordingButton").onclick=()=>work(async()=>{await recordingInfo();await loadDownloads();});
 if($("discardRecordingButton"))$("discardRecordingButton").onclick=()=>work(async()=>{
  const s=await recordingInfo();if(!s.recordInfoSupported)throw Error("此UI固件尚不支持板端丢弃；板卡只保留一段，新录音会覆盖，不会累积塞满。");
  if(!durable || !(await nativeAction("confirmDiscard")).confirmed)return;
  await client().request(T.RECORD_CLEAR);await recordingInfo();log("板上当前录音已逻辑丢弃，无法继续下载；手机缓存和已导出的WAV保持不变。无需逐字节擦除DDR。");
 });
 setInterval(()=>{
  if(!state.client || !state.linkConnected || state.working || state.client.pending || state.handshakePromise)return;
  if(state.status)state.client.request(T.STATUS).catch(e=>log(e.message));
  else if(state.handshakeAttempts<3)return handshake();
 },2500);
 piano();controls();log(native?"可选蓝牙串口或ESP-01S Wi-Fi TCP；连接后在 UI 板校准最左键。Wi-Fi方式需先连接ESP热点。":"此网页可离线解析 MIDI；蓝牙或ESP-01S直连需配套安卓 APK。");
 if(native?.appInfo){try{const info=JSON.parse(native.appInfo());if(info.version){$("appVersion").textContent=`FPGA PERFORMANCE · ${info.version}`;log(`App ${info.version} · Android API ${info.sdk} · ${info.manufacturer} ${info.model}`);}}catch(e){log("读取App版本信息失败："+e.message);}}
 if(durable)loadDownloads().catch(e=>log(e.message));
})();
