"use strict";
// Exercise the production entry point and protocol. The peer is synthetic.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const P=require('../performance_web/protocol.js'),T=P.TYPES;
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function harness({reply=true,length=26,code=0}={}){
 const elements=new Map(),frames=[];let poll,ctx,choices=0,enabled=reply;
 const el=id=>{if(!elements.has(id))elements.set(id,{value:'',textContent:'',disabled:false,dataset:{},style:{},replaceChildren(){},appendChild(){},classList:{toggle(){}}});return elements.get(id);};
 const status=kind=>P.join(Uint8Array.of(code,kind,28,4),P.u32(0),P.u16(0),Uint8Array.of(41,32),P.u32(96000),P.u32(1),P.u16(16384),length===26?Uint8Array.of(1,0,1,0):new Uint8Array(length-22));
 const native={chooseDevice(){choices++;},sendBase64(encoded){
  const packet=new P.Decoder().feed(Buffer.from(encoded,'base64'))[0];frames.push(packet);
  if(enabled)setImmediate(()=>ctx.onNativeBytes(Buffer.from(P.frame(T.ACK,packet.seq,status(packet.type))).toString('base64')));
 }};
 const protocol={...P,Client:class extends P.Client{constructor(send,options){super(send,{...options,timeout:10,retries:2});}}};
 ctx={PerformanceProtocol:protocol,PhoneNative:native,document:{getElementById:el,createElement:()=>el('key')},Option:function(){},Uint8Array,ArrayBuffer,DataView,Promise,Error,console,setTimeout,clearTimeout,setInterval(fn){poll=fn;},atob:s=>Buffer.from(s,'base64').toString('binary'),btoa:s=>Buffer.from(s,'binary').toString('base64')};
 ctx.window=ctx;vm.createContext(ctx);vm.runInContext(fs.readFileSync(require.resolve('../performance_web/phone_app.js'),'utf8'),ctx);
 return {ctx,el,frames,get choices(){return choices;},ready(value){enabled=value;},poll:()=>poll()};
}
async function waitUntil(predicate){for(let n=0;n<120;n++){if(predicate())return;await sleep(5);}throw Error('Expected production handshake recovery did not occur');}
async function main(){
 // Real failure: after the initial retry budget is exhausted, recover without
 // another RFCOMM connection and without invalidating the nonce/calibration again.
 const h=harness({reply:false});await h.ctx.onNativeConnected();
 assert.equal(h.frames.length,2);assert.ok(h.el('uploadButton').disabled);
 const nonce=Buffer.from(h.frames[0].payload).toString('hex');
 h.ready(true);await h.el('connectButton').onclick();
 assert.equal(h.choices,0,'retry must reuse the connected socket, not open device picker');
 assert.match(h.el('gatewayStatus').textContent,/板卡已应答/);
 assert.ok(h.el('uploadButton').disabled,'HELLO cannot bypass physical keyboard calibration');
 for(const packet of h.frames)assert.equal(Buffer.from(packet.payload).toString('hex'),nonce);
 assert.ok(h.frames.every(packet=>packet.type===T.HELLO && packet.payload.length===4));
 assert.match(h.el('linkDiagnostic').textContent,/TX|发送/);assert.match(h.el('linkDiagnostic').textContent,/RX|接收/);

 const auto=harness({reply:false});await auto.ctx.onNativeConnected();auto.ready(true);auto.poll();
 await waitUntil(()=>/板卡已应答/.test(auto.el('gatewayStatus').textContent));
 assert.equal(new Set(auto.frames.map(p=>Buffer.from(p.payload).toString('hex'))).size,1);
 assert.equal(auto.choices,0);

 const dropped=harness({reply:false});const pending=dropped.ctx.onNativeConnected();
 await sleep(1);dropped.ctx.onNativeDisconnected('test disconnected during HELLO');await pending;
 assert.match(dropped.el('gatewayStatus').textContent,/未连接/,'stale handshake rejection cannot overwrite disconnect');
 const before=dropped.frames.length;dropped.poll();await sleep(25);assert.equal(dropped.frames.length,before);

 for(const length of [22,26]){const compatible=harness({length});await compatible.ctx.onNativeConnected();assert.match(compatible.el('gatewayStatus').textContent,/板卡已应答/);assert.ok(compatible.el('uploadButton').disabled);}
 const rejected=harness({code:1});await rejected.ctx.onNativeConnected();
 assert.match(rejected.el('gatewayStatus').textContent,/已应答.*拒绝/);
 assert.ok(rejected.el('uploadButton').disabled);
 const malformed=harness({length:24});await malformed.ctx.onNativeConnected();
 assert.doesNotMatch(malformed.el('gatewayStatus').textContent,/板卡已应答/);
 assert.match(malformed.el('log').textContent,/状态帧长度/);

 const bounded=harness({reply:false});await bounded.ctx.onNativeConnected();
 for(let i=0;i<5;i++){bounded.poll();await sleep(35);}
 assert.equal(bounded.frames.length,6,'automatic recovery has three bounded rounds');
 const sent=bounded.frames.length;bounded.poll();await sleep(35);assert.equal(bounded.frames.length,sent);
 bounded.ready(true);await bounded.el('connectButton').onclick();assert.match(bounded.el('gatewayStatus').textContent,/板卡已应答/);
 const oldNonce=Buffer.from(bounded.frames.at(-1).payload).toString('hex');
 bounded.ctx.onNativeDisconnected('reconnect');await bounded.ctx.onNativeConnected();
 assert.notEqual(Buffer.from(bounded.frames.at(-1).payload).toString('hex'),oldNonce);
 console.log('PASS: production handshake timeout/manual retry/automatic recovery, bounded retries, stable per-session nonce, new reconnect nonce, disconnect race, 22/26-byte ACK, rejection vs silence, malformed ACK, calibration gate and TX/RX diagnostics');
}
main().catch(error=>{console.error(error);process.exitCode=1;});
