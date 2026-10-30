"use strict";
// Execute the real phone entry point and CRC client through its native bridge.
// The board peer is explicitly synthetic; no hardware acceptance is implied.
const fs=require("node:fs"),vm=require("node:vm"),assert=require("node:assert/strict");
const P=require("../performance_web/protocol.js"),T=P.TYPES;
async function scenario(disconnect=false){
 const elements=new Map(),progress=[];
 const el=id=>{
  if(!elements.has(id))elements.set(id,{value:id==="exportChannels"?"1":"",textContent:"",disabled:false,
   replaceChildren(){},appendChild(){},classList:{toggle(){}},dataset:{},style:new Proxy({}, {set(o,k,v){o[k]=v;if(id==="progress"&&k==="width")progress.push(parseFloat(v));return true;}})});
  return elements.get(id);
 };
 let ctx,cache=[],exported=null,cancels=0,readBlocks=0;
 const pcm=Buffer.alloc(1029*2);for(let i=0;i<1029;i++)pcm.writeInt16LE((i*733)%65536-32768,i*2);
 const status=kind=>P.join(Uint8Array.of(0,kind,20,4),P.u32(1029*12),P.u16(0),Uint8Array.of(29,32),P.u32(96000),P.u32(1),P.u16(16384));
 function incoming(type,seq,payload){const wire=P.frame(type,seq,payload);for(let at=0;at<wire.length;at+=9)ctx.onNativeBytes(Buffer.from(wire.slice(at,at+9)).toString("base64"));}
 const native={
  sendBase64(encoded){const p=new P.Decoder().feed(Buffer.from(encoded,"base64"))[0];
   setImmediate(()=>{
    if(p.type===T.READ){
     readBlocks++;const d=new DataView(p.payload.buffer),offset=d.getUint32(0,true),count=d.getUint16(4,true);
     for(let at=0;at<count;at+=27){
      if(disconnect && at>=27){ctx.onNativeDisconnected("synthetic interrupted transfer");return;}
      const n=Math.min(27,count-at);
      incoming(T.AUDIO,p.seq,P.join(P.u32(offset+at),Uint8Array.of(n,1),P.u32(1),pcm.subarray((offset+at)*2,(offset+at+n)*2)));
     }
    }
    incoming(T.ACK,p.seq,status(p.type));
   });
  },
  beginSave(name,frames,channels){cache=[Buffer.from(P.wavHeader(frames,channels))];setImmediate(()=>ctx.onNativeSaveReady());},
  appendAudio(encoded){cache.push(Buffer.from(encoded,"base64"));setImmediate(()=>ctx.onNativeWrite(true,""));},
  finishSave(){exported=Buffer.concat(cache);setImmediate(()=>ctx.onNativeWrite(true,""));},
  cancelSave(){cancels++;},chooseDevice(){}
 };
 ctx={PerformanceProtocol:P,PhoneNative:native,document:{getElementById:el,createElement:()=>el("created")},
  Option:function(text,value){return{text,value};},Uint8Array,DataView,Date,Number,Math,Promise,Error,console,
  atob:s=>Buffer.from(s,"base64").toString("binary"),btoa:s=>Buffer.from(s,"binary").toString("base64"),setInterval(){},setTimeout};
 ctx.window=ctx;vm.createContext(ctx);vm.runInContext(fs.readFileSync(require.resolve("../performance_web/phone_app.js"),"utf8"),ctx);
 await ctx.onNativeConnected();await el("downloadButton").onclick();
 if(disconnect){assert.equal(exported,null);assert.equal(cancels,1);assert.match(el("log").textContent,/蓝牙连接/);}
 else{
  assert.equal(readBlocks,2);assert.equal(exported.length,44+pcm.length);assert.deepEqual(exported.subarray(44),pcm);
  assert.ok(progress.some(p=>p>0&&p<10),"progress must advance on first AUDIO packet, before block ACK");
  assert.equal(progress.at(-1),100);assert.match(el("progressLabel").textContent,/1029\/1029/);
 }
}
(async()=>{await scenario();await scenario(true);console.log("PASS: real phone UI + CRC protocol + native bridge, two-block exact PCM, packet-level progress, interrupted download never exported");})().catch(e=>{console.error(e);process.exitCode=1;});
