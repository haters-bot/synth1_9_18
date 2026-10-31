(() => {
 "use strict";
 const P=PerformanceProtocol,T=P.TYPES,$=id=>document.getElementById(id);
 const state={client:null,socket:null,song:null,status:null,working:false,selecting:false,saving:false,saveWait:null,writeWait:null,linkConnected:false,helloPayload:null,handshakePromise:null,handshakeAttempts:0,link:null};
 const native=window.PhoneNative;
 let helloNonce=(Date.now() ^ Math.floor(Math.random()*4294967296))>>>0;
 const log=message=>{$("log").textContent=String(message);};
 function linkTrace(event){
  const d=state.link;if(!d)return;
  const hex=bytes=>Array.from(bytes.slice(-48),b=>b.toString(16).padStart(2,"0").toUpperCase()).join(" ");
  if(event.kind==="tx"){d.txFrames++;d.txBytes+=event.bytes.length;d.tx=hex(event.bytes);}
  else {d.rxBytes+=event.bytes.length;d.validFrames+=event.validFrames;d.badFrames+=event.badFrames;d.rx=hex(event.bytes);}
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
 function controls(){
  const ready=calibrated(state.status),s=state.status;
  $("connectButton").textContent=state.linkConnected && !s?"重试板卡应答":"连接蓝牙";
  $("connectButton").disabled=state.working || !!state.handshakePromise;
  $("uploadButton").disabled=state.working || state.selecting || !ready || !state.song || state.song.noteMax-state.song.noteMin>=32;
  $("playButton").disabled=state.working || !ready || !s.loaded;
  $("pauseButton").disabled=state.working || !ready || !s.loaded;
  $("downloadButton").disabled=state.working || !s?.storedFrames || s.busy;
 }
 function refresh(s){
  const previous=state.status;
  state.status=s;$("recordButton").textContent=s.recording?"停止录音":"开始录音";
  $("downloadButton").disabled=state.working || !s.storedFrames || s.busy;
  $("baseNote").replaceChildren(new Option(calibrated(s)?`0x${s.baseNote.toString(16).toUpperCase()} / MIDI ${s.baseNote}–${s.baseNote+s.keyCount-1}`:"等待 UI 板校准最左键",s.baseNote));
  $("baseNote").disabled=true;
  badge("gatewayStatus",`板卡已应答 · ${s.fast?115200:9600} baud`);
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
  $("calibrationStatus").textContent="蓝牙断开；下次连接后请重新在 UI 板校准。";controls();
  badge("gatewayStatus","蓝牙／板卡未连接");$("downloadButton").disabled=true;log(message);
  if(state.saveWait){state.saveWait.reject(Error(message));state.saveWait=null;}
  if(state.writeWait){state.writeWait.reject(Error(message));state.writeWait=null;}
 }
 function handshake(manual=false){
  if(!state.linkConnected || !state.client)return Promise.resolve();
  if(state.handshakePromise)return state.handshakePromise;
  if(manual)state.handshakeAttempts=0;
  const c=state.client;state.handshakeAttempts++;
  badge("gatewayStatus",`蓝牙已连，等待板卡 HELLO（${state.handshakeAttempts}/3）…`);
  state.handshakePromise=(async()=>{
   try {
    // Reuse the connection nonce across retries: a lost ACK must not erase a
    // calibration/score that the FPGA has already accepted for this session.
    await c.request(T.HELLO,state.helloPayload);
    if(state.client!==c || !state.linkConnected)return;
    log("双向通信成功。请在 UI 板演奏页点击 CALIBRATE，再按实体键盘最左键。每次重连或调整八度后都须校准并重新传曲。");
   }catch(e){
    if(state.client!==c || !state.linkConnected)return;
    const rejected=c.lastStatus?.request===T.HELLO && c.lastStatus.code;
    badge("gatewayStatus",rejected?"板卡已应答／握手被拒绝":state.link.rxBytes?"蓝牙已连／返回数据未通过协议校验":"蓝牙已连／未收到板卡返回");
    log(`${e.message}。${state.handshakeAttempts<3?"将自动重试；也可点“重试板卡应答”。":"自动重试已暂停，可点“重试板卡应答”继续。"}${state.link.rxBytes?"已有返回字节，请查看下方收发诊断。":"RX=0：尚不能确定是接线、模块串口波特率还是板端接收问题。"}`);
   }finally{if(state.client===c){state.handshakePromise=null;controls();}}
  })();
  controls();return state.handshakePromise;
 }
 async function attach(send){
  state.client?.close();state.handshakePromise=null;state.status=null;
  state.linkConnected=true;state.handshakeAttempts=0;state.helloPayload=P.u32(++helloNonce);
  state.link={txFrames:0,txBytes:0,rxBytes:0,validFrames:0,badFrames:0,tx:"—",rx:"—"};
  const c=new P.Client(send,{onStatus:s=>{if(state.client===c && (s.request!==T.HELLO || !s.code))refresh(s);},onTrace:event=>{if(state.client===c)linkTrace(event);}});
  state.client=c;controls();return handshake();
 }
 window.onNativeConnected=()=>attach(bytes=>native.sendBase64(bytes64(bytes)));
 window.onNativeBytes=data=>state.client?.receive(decode64(data));
 window.onNativeDisconnected=message=>disconnected(message||"蓝牙连接已断开");
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
  if(native){if(state.linkConnected && !state.status)return handshake(true);native.chooseDevice();return;}
  if(location.protocol==="file:")throw Error("此离线网页可解析 MIDI；安卓请安装配套 APK 直连 HC-07");
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
  const controlIds=["chooseMidiButton","connectButton","uploadButton","playButton","pauseButton","stopButton","recordButton","downloadButton"];
  controlIds.forEach(id=>$(id).disabled=true);
  try {await action();} catch(e){const message=e.message||String(e);log(message);feedback(message,"error");}
  finally {state.working=false;controlIds.forEach(id=>$(id).disabled=false);$("chooseMidiButton").disabled=state.selecting;if(state.status)refresh(state.status);controls();}
 }
 function client(){if(!state.client || !state.status)throw Error("先连接模块并收到板卡应答");return state.client;}
 $("connectButton").onclick=()=>connect().catch(e=>log(e.message));
 function finishSelection(){state.selecting=false;$("chooseMidiButton").disabled=state.working;controls();}
 function selectionError(message){state.song=null;$("songTitle").textContent="尚未选择曲谱";$("songMeta").textContent=String(message);$("eventStats").textContent="0 events";finishSelection();feedback(message,"error");log(message);}
 function selectedMidi(name,data){
  try {
   const song=PerformanceMidi.parseMidi(data);if(!song.events.length)throw Error("曲谱没有 Note 事件，请选择含音符的标准 MIDI");
   song.name=name;state.song=song;$("adaptationStatus").textContent="上传前按板端本次校准音域整体移调，原文件不变；超过32键时拒绝传输。";
   let low=127,high=0;for(const event of song.events)if(event.on && event.velocity>0){if(event.note<low)low=event.note;if(event.note>high)high=event.note;}
   if(low>high)throw Error("曲谱没有 Note On 事件");
   song.noteMin=low;song.noteMax=high;
   $("songTitle").textContent=name;$("songMeta").textContent=`${(song.duration_us/1e6).toFixed(1)} 秒 · ${song.events.length} Note事件 · MIDI ${low}–${high}`;
   $("eventStats").textContent=`${song.events.length} events`;finishSelection();
   if(high-low+1>32){feedback(`曲谱音域含两端共${high-low+1}键，超过32键，禁止传输；请选择较小音域的编曲。`,"error");log("曲谱已解析，但音域过宽，未向板卡发送。");}
   else {feedback(`曲谱音域共${high-low+1}键；校准成功后将整体移调到当前32键范围。`,"info");log("MIDI 已解析，等待板端校准并确认音域后上传。");}
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
  const song=PerformanceMidi.adaptToRange(original,s.baseNote,s.keyCount);
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
  await c.request(s.recording?T.RECORD_STOP:T.RECORD_START);
  log(s.recording?"已请求停止；等待 DDR 写入排空后下载":"板卡确认开始采集音频板 I²S；没有使用手机麦克风");
 });
 function nativeWrite(bytes){return new Promise((resolve,reject)=>{state.writeWait={resolve,reject};native.appendAudio(bytes64(bytes));});}
 $("downloadButton").onclick=()=>work(async()=>{
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
 });
 setInterval(()=>{
  if(!state.client || !state.linkConnected || state.working || state.client.pending || state.handshakePromise)return;
  if(state.status)state.client.request(T.STATUS).catch(e=>log(e.message));
  else if(state.handshakeAttempts<3)return handshake();
 },2500);
 piano();controls();log(native?"先在安卓系统配对模块，再点连接，选择已配对的设备；连接后在 UI 板校准最左键。":"此网页可离线解析 MIDI；手机直连 HC-07 需要配套安卓 APK。");
})();
