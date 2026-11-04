"use strict";
// Run the production UI and CRC client. Native file durability is independently
// tested against the real Java store; this peer models board disconnect/reset.
const fs=require("node:fs"),vm=require("node:vm"),assert=require("node:assert/strict"),crypto=require("node:crypto");
const P=require("../performance_web/protocol.js"),T=P.TYPES;
const source=fs.readFileSync(require.resolve("../performance_web/phone_app.js"),"utf8");
const html=fs.readFileSync(require.resolve("../performance_web/index.html"),"utf8");
for(const id of ["cancelDownloadButton","discardRecordingButton","refreshRecordingButton","recordingStatus","speedStatus","localRecordings"])
 assert.ok(html.includes(`id="${id}"`),`missing real HTML element ${id}`);
let checks=0;
function create(options={}){
 const persistent=options.persistent||new Map(),board=options.board||{frames:2053,generation:7,token:"",legacy:false,baud:2};
 const pcm=Buffer.alloc(board.frames*2);for(let i=0;i<board.frames;i++)pcm.writeInt16LE((i*947)%65536-32768,i*2);
 const elements=new Map(),reads=[],exports=[],actions=[],progress=[];let ctx,active=null,cut=false,paused=false,cancelExport=false,confirm=true;
 const node=()=>({value:"",textContent:"",disabled:false,children:[],dataset:{},style:{},classList:{toggle(){}},
  replaceChildren(...kids){this.children=kids;},appendChild(kid){this.children.push(kid);}});
 const el=id=>{if(!elements.has(id)){const n=node();if(id==="exportChannels")n.value="1";
  if(id==="progress")n.style=new Proxy({}, {set(o,k,v){o[k]=v;progress.push(parseFloat(v));return true;}});elements.set(id,n);}return elements.get(id);};
 function reply(id,ok,value){setImmediate(()=>ctx.onNativeDownloadReply(id,ok,ok?JSON.stringify(value):value));}
 function incoming(type,seq,payload){const wire=P.frame(type,seq,payload);for(let i=0;i<wire.length;i+=13)ctx.onNativeBytes(Buffer.from(wire.slice(i,i+13)).toString("base64"));}
 function ack(kind,code=0){
  let result=P.join(Uint8Array.of(code,kind,156,4),P.u32(board.frames*12),P.u16(2),Uint8Array.of(41,32),P.u32(96000),P.u32(board.generation),P.u16(16384),Uint8Array.of(1,2),P.u16(6));
  if(kind===T.RECORD_INFO&&!board.legacy)result=P.join(result,Uint8Array.of(1,board.baud),Buffer.from(board.token.padEnd(32,"0"),"hex"));return result;
 }
 const native={chooseDevice(){},sendBase64(encoded){const p=new P.Decoder().feed(Buffer.from(encoded,"base64"))[0];
  setImmediate(()=>{
   if(p.type===T.RECORD_INFO){
    if(board.legacy){incoming(T.ACK,p.seq,ack(p.type,1));return;}
    if(!board.token&&board.frames)board.token=Buffer.from(p.payload).toString("hex");
   }
   if(p.type===T.RECORD_CLEAR){board.frames=0;board.generation++;board.token="";}
   if(p.type===T.READ){
    const d=new DataView(p.payload.buffer,p.payload.byteOffset,p.payload.byteLength),at=d.getUint32(0,true),count=d.getUint16(4,true);reads.push(at);
    for(let i=0;i<count;i+=27){
     if(cut && at===1024 && i>=27){cut=false;ctx.onNativeDisconnected("synthetic link loss");return;}
     const n=Math.min(27,count-i);incoming(T.AUDIO,p.seq,P.join(P.u32(at+i),Uint8Array.of(n,1),P.u32(board.generation),pcm.subarray((at+i)*2,(at+i+n)*2)));
     if(paused){paused=false;el("cancelDownloadButton").onclick();}
    }
   }
   incoming(T.ACK,p.seq,ack(p.type));
  });
 },downloadAction(id,action,encoded){
  const data=JSON.parse(encoded);actions.push(action);
  try{
   if(action==="list")reply(id,true,{entries:[...persistent.values()].map(e=>({...e,pcm:undefined})),directory:"synthetic-app-private/recordings"});
   else if(action==="begin"){
    const key=crypto.createHash("sha256").update(data.identity).digest("hex");
    if(!persistent.has(key))persistent.set(key,{...data,key,received:0,complete:false,pcm:[]});
    active=persistent.get(key);reply(id,true,{...active,pcm:undefined});
   }else if(action==="append"){
    assert.equal(data.key,active.key);active.pcm.push(Buffer.from(data.pcm,"base64"));active.received+=Buffer.from(data.pcm,"base64").length/2;
    active.complete=active.received===active.frames;reply(id,true,{received:active.received});
   }else if(action==="pause"){active=null;reply(id,true,{});}
   else if(action==="export"){
    const e=persistent.get(data.key);assert.ok(e.complete);
    if(cancelExport){cancelExport=false;reply(id,false,"已取消导出；完整缓存保留");}
    else {exports.push(Buffer.concat([Buffer.from(P.wavHeader(e.frames,e.channels)),...e.pcm]));reply(id,true,{});}
   }else if(action==="delete"){
    if(confirm)persistent.delete(data.key);reply(id,true,{cancelled:!confirm});
   }else if(action==="confirmDiscard"||action==="confirmOverwrite")reply(id,true,{confirmed:confirm});
   else throw Error("unknown action "+action);
  }catch(e){reply(id,false,e.message);}
 }};
 ctx={PerformanceProtocol:P,PhoneNative:native,document:{getElementById:el,createElement:node},
  crypto:crypto.webcrypto,Option:function(text,value){return{text,value};},Uint8Array,DataView,Date,Number,Math,Promise,Error,console,
  atob:s=>Buffer.from(s,"base64").toString("binary"),btoa:s=>Buffer.from(s,"binary").toString("base64"),setTimeout,clearTimeout,setInterval(){}};
 ctx.window=ctx;vm.createContext(ctx);vm.runInContext(source,ctx);
 const settle=()=>new Promise(resolve=>setImmediate(()=>setImmediate(resolve)));
 async function clickRow(title){await settle();const button=el("localRecordings").children.flatMap(n=>n.children).find(b=>b.textContent===title);assert.ok(button,`missing ${title}`);await button.onclick();}
 return{ctx,el,board,persistent,pcm,reads,exports,actions,progress,settle,clickRow,
  cutNext(){cut=true;},pauseNext(){paused=true;},cancelExport(){cancelExport=true;},confirm(value){confirm=value;},
  connect:async(address="00:11:22:33:44:55")=>{await ctx.onNativeConnected(address);await settle();},
  disconnect:()=>ctx.onNativeDisconnected("synthetic disconnect")};
}
async function main(){
 const a=create();await a.connect();assert.match(a.el("gatewayStatus").textContent,/230400/);checks++;
 a.cutNext();await a.el("downloadButton").onclick();
 const partial=[...a.persistent.values()][0];assert.equal(partial.received,1024);assert.equal(a.exports.length,0);
 assert.match(a.el("progressLabel").textContent,/保留 1024\/2053/);assert.deepEqual(a.reads,[0,1024]);checks++;
 // Recreate the complete JS app (as after process restart); keep native files and board token.
 const b=create({persistent:a.persistent,board:a.board});await b.connect();await b.clickRow("继续下载");
 assert.deepEqual(b.reads,[1024,2048]);assert.equal(b.exports.length,1);assert.deepEqual(b.exports[0].subarray(44),b.pcm);
 assert.equal(b.exports[0].length,44+b.pcm.length);assert.ok(b.progress.some(p=>p>49.8&&p<51));checks++;
 b.disconnect();const before=b.reads.length;await b.clickRow("导出 WAV");assert.equal(b.reads.length,before);assert.equal(b.exports.length,2);checks++;
 b.confirm(false);await b.clickRow("删除手机缓存");assert.equal(b.persistent.size,1);checks++;
 // This deletes only synthetic in-memory data, never user files.
 b.confirm(true);await b.clickRow("删除手机缓存");assert.equal(b.persistent.size,0);checks++;
 const c=create();await c.connect();c.pauseNext();await c.el("downloadButton").onclick();
 assert.equal([...c.persistent.values()][0].received,1024);assert.deepEqual(c.reads,[0]);checks++;
 const original=c.board.token;c.disconnect();c.board.token="ab".repeat(16);await c.connect();const count=c.reads.length;
 await c.clickRow("继续下载");assert.equal(c.reads.length,count);assert.match(c.el("log").textContent,/身份/);assert.equal(c.persistent.size,1);checks++;
 c.board.token=original;c.disconnect();await c.connect("66:77:88:99:AA:BB");await c.clickRow("继续下载");
 assert.equal(c.reads.length,count);assert.match(c.el("log").textContent,/身份/);checks++;
 c.disconnect();await c.connect();c.cancelExport();await c.clickRow("继续下载");
 assert.equal([...c.persistent.values()][0].complete,true);assert.equal(c.exports.length,0);assert.match(c.el("log").textContent,/取消导出/);
 c.disconnect();const completed=c.reads.length;await c.clickRow("导出 WAV");assert.equal(c.reads.length,completed);assert.deepEqual(c.exports[0].subarray(44),c.pcm);checks++;
 await c.connect();c.confirm(false);await c.el("discardRecordingButton").onclick();assert.equal(c.board.frames,2053);checks++;
 c.confirm(true);await c.el("discardRecordingButton").onclick();assert.equal(c.board.frames,0);assert.equal(c.persistent.size,1);
 assert.match(c.el("recordingStatus").textContent,/没有/);checks++;
 const old=create();old.board.legacy=true;await old.connect();old.pauseNext();await old.el("downloadButton").onclick();
 assert.equal([...old.persistent.values()][0].received,1024);old.disconnect();await old.connect();const oldCount=old.reads.length;
 await old.clickRow("继续下载");assert.equal(old.reads.length,oldCount);assert.match(old.el("log").textContent,/旧固件/);checks++;
 old.ctx.onNativeDownloadReply(999999,true,"{\"received\":999999}");assert.equal([...old.persistent.values()][0].received,1024);checks++;
 const old2=create();old2.board.legacy=true;await old2.connect();await old2.el("downloadButton").onclick();assert.deepEqual(old2.exports[0].subarray(44),old2.pcm);checks++;
 console.log(`PASS: ${checks} durable phone scenarios: real CRC/UI + manual resume after disconnect/restart, exact PCM, identity/MAC guards, pause, offline/repeated export, cancelled export, confirmed discard/delete, old-firmware fallback, stale callback ignored`);
}
main().catch(e=>{console.error(e);process.exitCode=1;});
