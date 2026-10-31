"use strict";
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const P=require('../performance_web/protocol.js'),M=require('../performance_web/midi.js');
const track=Buffer.from([0,0x90,41,100,0x83,0x60,41,0,0,0xff,0x2f,0]);
const midi=Buffer.concat([Buffer.from('4d546864000000060000000101e04d54726b','hex'),Buffer.from([0,0,0,track.length]),track]);
const elements=new Map(),frames=[];let ctx,choices=0,boardBase=41,maxEvents=16384,calState=0,epoch=1,legacy=false,helloNonce;
const el=id=>{if(!elements.has(id))elements.set(id,{value:'',textContent:'',disabled:false,style:{},dataset:{},classList:{toggle(){}},replaceChildren(){},appendChild(){},click(){this.clicked=true;}});return elements.get(id);};
const status=kind=>P.join(Uint8Array.of(0,kind,28+(calState===2?128:0),4),P.u32(0),P.u16(2),Uint8Array.of(boardBase,32),P.u32(96000),P.u32(1),P.u16(maxEvents),legacy?new Uint8Array():P.join(Uint8Array.of(1,calState),P.u16(epoch)));
ctx={PerformanceProtocol:P,PerformanceMidi:M,document:{getElementById:el,createElement:()=>el('key')},
 Option:function(){},Uint8Array,ArrayBuffer,DataView,Promise,Error,console,setTimeout,setInterval(){},
 atob:s=>Buffer.from(s,'base64').toString('binary'),btoa:s=>Buffer.from(s,'binary').toString('base64'),
 PhoneNative:{chooseMidi(){choices++;},sendBase64(s){const p=new P.Decoder().feed(Buffer.from(s,'base64'))[0];frames.push(p);
  if(p.type===P.TYPES.HELLO){assert.equal(p.payload.length,4);const n=Buffer.from(p.payload).readUInt32LE();assert.notEqual(n,helloNonce);helloNonce=n;calState=0;epoch++;}
  if(p.type===P.TYPES.BEGIN){assert.equal(p.payload.length,8);assert.equal(Buffer.from(p.payload).readUInt16LE(6),epoch);}
  setImmediate(()=>ctx.onNativeBytes(Buffer.from(P.frame(P.TYPES.ACK,p.seq,status(p.type))).toString('base64')));}},
 FileReader:class {readAsArrayBuffer(file){this.result=file.testBytes;this.onload();}}};
ctx.window=ctx;vm.createContext(ctx);vm.runInContext(fs.readFileSync(require.resolve('../performance_web/phone_app.js'),'utf8'),ctx);
async function main(){
 await ctx.onNativeConnected();el('chooseMidiButton').onclick();assert.equal(choices,1);assert.ok(el('uploadButton').disabled);
 ctx.onNativeMidiSelected('中文曲谱.mid',midi.toString('base64'));assert.equal(el('songTitle').textContent,'中文曲谱.mid');assert.match(el('songMeta').textContent,/2 Note/);
 assert.ok(el('uploadButton').disabled);assert.ok(el('playButton').disabled);
 await el('uploadButton').onclick();assert.match(el('actionStatus').textContent,/先在 UI 板.*最左键/);assert.ok(!frames.some(p=>p.type===P.TYPES.CLEAR));
 assert.ok(el('uploadButton').disabled,'finally cannot bypass calibration');
 calState=2;epoch++;
 await el('uploadButton').onclick();assert.ok(frames.some(p=>p.type===P.TYPES.EVENTS));assert.equal(el('progress').style.width,'100%');assert.match(el('progressLabel').textContent,/2\/2/);
 const outside=Buffer.from(midi);outside[24]=90;outside[28]=90;
 el('chooseMidiButton').onclick();ctx.onNativeMidiSelected('超出音域.mid',outside.toString('base64'));
 assert.match(el('songMeta').textContent,/MIDI 90–90/);
 await el('uploadButton').onclick();assert.match(el('actionStatus').textContent,/确认载入.*降24个半音/);
 const uploaded=frames.filter(p=>p.type===P.TYPES.EVENTS).at(-1).payload;
 assert.equal(uploaded[4],66);assert.equal(uploaded[12],66);
 // Repeating upload must transform the original notes, not transpose twice.
 await el('uploadButton').onclick();assert.equal(frames.filter(p=>p.type===P.TYPES.EVENTS).at(-1).payload[4],66);
 let sent=frames.filter(p=>p.type===P.TYPES.EVENTS).length;
 const destructive=()=>frames.filter(p=>[P.TYPES.STOP,P.TYPES.CLEAR,P.TYPES.BEGIN].includes(p.type)).length;
 let before=destructive();legacy=true;
 await el('uploadButton').onclick();assert.match(el('actionStatus').textContent,/更新.*UI 固件/);
 assert.equal(destructive(),before);assert.equal(frames.filter(p=>p.type===P.TYPES.EVENTS).length,sent);
 legacy=false;maxEvents=1;await el('uploadButton').onclick();assert.match(el('actionStatus').textContent,/超过板卡 1 容量/);assert.equal(destructive(),before);maxEvents=16384;
 const wideTrack=Buffer.from([0,0x90,40,100,0,72,100,20,40,0,0,72,0,0,0xff,0x2f,0]);
 const wide=Buffer.concat([midi.subarray(0,18),Buffer.from([0,0,0,wideTrack.length]),wideTrack]);
 ctx.onNativeMidiSelected('33keys.mid',wide.toString('base64'));assert.ok(el('uploadButton').disabled);assert.match(el('actionStatus').textContent,/33键.*禁止传输/);
 await el('uploadButton').onclick();assert.equal(destructive(),before);assert.match(el('actionStatus').textContent,/禁止传输/);
 for(boardBase of [41,53,65,77]){
  epoch++;ctx.onNativeMidiSelected('one_note.mid',midi.toString('base64'));await el('uploadButton').onclick();
  const b=frames.filter(p=>p.type===P.TYPES.EVENTS).at(-1).payload;
  assert.ok(b[4]>=boardBase && b[4]<boardBase+32);assert.match(el('calibrationStatus').textContent,/校准 OK/);
 }
 before=destructive();sent=frames.filter(p=>p.type===P.TYPES.EVENTS).length;
 ctx.onNativeDisconnected('test disconnect');assert.ok(el('uploadButton').disabled);
 await ctx.onNativeConnected();assert.ok(el('uploadButton').disabled);await el('uploadButton').onclick();assert.equal(destructive(),before);
 calState=2;epoch++;
 el('chooseMidiButton').onclick();ctx.onNativeMidiError('已取消选择 MIDI');await el('uploadButton').onclick();assert.equal(frames.filter(p=>p.type===P.TYPES.EVENTS).length,sent);
 el('chooseMidiButton').onclick();ctx.onNativeMidiSelected('invalid.mid','AAECAw==');assert.match(el('log').textContent,/MIDI|越界|文件头/);assert.equal(el('songTitle').textContent,'尚未选择曲谱');
 await el('songFile').onchange({target:{files:[{name:'fallback.mid',size:midi.length,testBytes:midi.buffer.slice(midi.byteOffset,midi.byteOffset+midi.length)}]}});assert.equal(el('songTitle').textContent,'fallback.mid');
 await el('songFile').onchange({target:{files:[{name:'huge.mid',size:5*1024*1024}]}});assert.match(el('log').textContent,/4 MiB/);
 console.log('PASS: production phone: reconnect nonce, calibration gate/OK/finally, 8-byte epoch BEGIN, four octave banks, >32 refusal before STOP/CLEAR, legacy/capacity guard, SAF/FileReader/cancellation, upload ACK/progress');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
