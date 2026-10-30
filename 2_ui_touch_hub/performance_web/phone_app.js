(() => {
 "use strict";
 const P=PerformanceProtocol,T=P.TYPES,$=id=>document.getElementById(id);
 const state={client:null,socket:null,song:null,status:null,working:false,saving:false,saveWait:null,writeWait:null};
 const native=window.PhoneNative;
 const log=message=>{$("log").textContent=String(message);};
 function badge(id,text){$(id).textContent=text;}
 function bytes64(bytes){let s="";for(const b of bytes)s+=String.fromCharCode(b);return btoa(s);}
 function decode64(value){return Uint8Array.from(atob(value),c=>c.charCodeAt(0));}
 function refresh(s){
  state.status=s;$("recordButton").textContent=s.recording?"停止录音":"开始录音";
  $("downloadButton").disabled=state.working || !s.storedFrames || s.busy;
  $("baseNote").replaceChildren(new Option(`板卡 MIDI ${s.baseNote} 起／${s.keyCount}键`,s.baseNote));
  $("baseNote").disabled=true;
  badge("gatewayStatus",`板卡已应答 · ${s.fast?115200:9600} baud`);
  badge("songStatus",s.loaded?`板卡已载入 ${s.events} 事件`:"板卡曲谱未就绪");
 }
 function piano(base=29){
  $("piano").replaceChildren();
  for(let i=0;i<32;i++) {
   const note=base+i,key=document.createElement("button");
   key.className="key"+([1,3,6,8,10].includes(note%12)?" black":"");key.textContent=note;key.dataset.note=note;
   const noteEvent=on=>{
    if((state.working && on) || !state.client)return;
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
  state.client?.close();state.client=null;state.status=null;
  badge("gatewayStatus","蓝牙／板卡未连接");$("downloadButton").disabled=true;log(message);
  if(state.saveWait){state.saveWait.reject(Error(message));state.saveWait=null;}
  if(state.writeWait){state.writeWait.reject(Error(message));state.writeWait=null;}
 }
 async function attach(send){
  state.client?.close();state.client=new P.Client(send,{onStatus:refresh});
  badge("gatewayStatus","蓝牙已连，等待板卡 HELLO…");
  try {const s=await state.client.request(T.HELLO);piano(s.baseNote);log(`双向通信成功。默认音域 ${s.baseNote}–${s.baseNote+s.keyCount-1}；实体最低音仍需按键核对。`);}
  catch(e){log(e.message);badge("gatewayStatus","蓝牙已连／板卡未应答");}
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
  if(native){native.chooseDevice();return;}
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
  const controls=["connectButton","uploadButton","playButton","pauseButton","stopButton","recordButton","downloadButton"];
  controls.forEach(id=>$(id).disabled=true);
  try {await action();} catch(e){log(e.message||String(e));}
  finally {state.working=false;controls.forEach(id=>$(id).disabled=false);if(state.status)refresh(state.status);else $("downloadButton").disabled=true;}
 }
 function client(){if(!state.client || !state.status)throw Error("先连接模块并收到板卡应答");return state.client;}
 $("connectButton").onclick=()=>connect().catch(e=>log(e.message));
 $("songFile").onchange=async event=>{
  const file=event.target.files?.[0];if(!file)return;
  try {
   const song=PerformanceMidi.parseMidi(await file.arrayBuffer());song.name=file.name;state.song=song;
   $("songTitle").textContent=file.name;$("songMeta").textContent=`${(song.duration_us/1e6).toFixed(1)} 秒 · ${song.events.length} Note事件`;
   $("eventStats").textContent=`${song.events.length} events`;log("MIDI 已在手机本地解析。只传时间与按键事件，板卡播放不自动发声。");
  }catch(e){state.song=null;log(e.message);}
 };
 $("uploadButton").onclick=()=>work(async()=>{
  const c=client(),s=await c.request(T.STATUS),song=state.song;
  if(!song?.events.length)throw Error("请选择含音符的 MIDI 曲谱");
  if(song.events.length>s.maxEvents)throw Error(`曲谱有 ${song.events.length} 事件，超过板卡 ${s.maxEvents} 容量；不能截断上传`);
  const bad=song.events.filter(e=>e.note<s.baseNote || e.note>=s.baseNote+s.keyCount);
  if(bad.length)throw Error(`${bad.length} 个事件超出板卡 MIDI ${s.baseNote}–${s.baseNote+s.keyCount-1} 音域；请先在 MIDI 编辑器移调／选轨，未发送`);
  await c.request(T.STOP);await c.request(T.CLEAR);
  await c.request(T.BEGIN,P.join(P.u32(Math.max(1,Math.ceil(song.duration_us/1000))),P.u16(song.events.length)));
  for(let at=0;at<song.events.length;at+=8){
   await c.request(T.EVENTS,P.eventsPayload(song.events.slice(at,at+8)));
   $("progress").style.width=`${Math.min(100,(at+8)/song.events.length*100)}%`;
  }
  const result=await c.request(T.END);
  if(!result.loaded || result.events!==song.events.length)throw Error("板卡曲谱计数不匹配");
  log(`板卡确认 ${result.events} 事件完整载入。点击播放开始灯带／屏幕指引，声音由实体琴键演奏。`);
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
  if(native){
   state.saving=true;
   await new Promise((resolve,reject)=>{state.saveWait={resolve,reject};native.beginSave(name,frames,channels);});
  }else parts.push(P.wavHeader(frames,channels));
  try {
   const started=Date.now();
   for(let at=0;at<frames;at+=1024){
    const n=Math.min(1024,frames-at);
    const result=await c.request(T.READ,P.join(P.u32(at),P.u16(n),Uint8Array.of(channels)),{offset:at,count:n,channels,generation:s.generation});
    if(result.pcm.length!==n*channels*2)throw Error(`板卡 PCM 长度错误：应为 ${n*channels*2}，实际 ${result.pcm.length}`);
    if(native)await nativeWrite(result.pcm);else parts.push(result.pcm);
    saved+=n;$("progress").style.width=`${saved/frames*100}%`;
    $("progressLabel").textContent=`已回传 ${saved}/${frames} 帧`;
    const remaining=Math.max(0,(Date.now()-started)/1000*(frames-saved)/saved);
    log(`下载 ${saved}/${frames} 帧 · 8kHz/${channels}声道 · 预计剩余 ${Math.ceil(remaining)} 秒。串口回传慢于原始演奏。`);
   }
   if(saved!==frames)throw Error(`录音回传未完成：${saved}/${frames} 帧`);
   if(native)await new Promise((resolve,reject)=>{state.writeWait={resolve,reject};native.finishSave();});
   else {
    const url=URL.createObjectURL(new Blob(parts,{type:"audio/wav"})),link=document.createElement("a");link.href=url;link.download=name;link.click();setTimeout(()=>URL.revokeObjectURL(url),60000);
   }
   $("progressLabel").textContent=`完成 ${saved}/${frames} 帧`;
   log(`录音已保存：${name}。来源为板卡 DDR 中的 I²S PCM，127抽头低通后 96k→8k；末尾不足12帧舍弃。`);
  }catch(e){if(native)native.cancelSave();throw e;}
  finally {state.saving=false;}
 });
 setInterval(()=>{
  if(state.client && state.status && !state.working && !state.client.pending)
   state.client.request(T.STATUS).catch(e=>log(e.message));
 },2500);
 piano();log(native?"先在安卓系统配对模块，再点连接，选择已配对的设备。":"此网页可离线解析 MIDI；手机直连 HC-07 需要配套安卓 APK。");
})();
