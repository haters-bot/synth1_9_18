"use strict";
const assert=require("node:assert/strict");
const P=require("../performance_web/protocol.js"),M=require("../performance_web/midi.js");
const T=P.TYPES;
const status=(kind,code=0,generation=7)=>P.join(Uint8Array.of(code,kind,28,4),P.u32(6000),P.u16(2),Uint8Array.of(60,32),P.u32(96000),P.u32(generation),P.u16(16384));
const wire=(type,seq,payload)=>P.frame(type,seq,payload);
let checks=0;
async function main(){
 assert.equal(P.crc16(Uint8Array.from(Buffer.from("123456789"))),0x29b1);checks++;
 const good=wire(T.ACK,5,status(T.HELLO)),bad=good.slice();bad[bad.length-1]^=1;
 const d=new P.Decoder(),stream=P.join(Uint8Array.of(0,4,165),bad,good);
 let decoded=[];for(const b of stream)decoded.push(...d.feed(Uint8Array.of(b)));
 assert.equal(decoded.length,1);assert.equal(decoded[0].seq,5);assert.ok(d.bad>0);checks++;
 let writes=0,c;
 c=new P.Client(bytes=>{
  writes++;const p=new P.Decoder().feed(bytes)[0];
  if(writes===1)return; // Lost ACK: same sequence and wire bytes must be retried.
  setTimeout(()=>c.receive(wire(T.ACK,p.seq,status(p.type))),1);
 },{timeout:10});
 const s=await c.request(T.HELLO);assert.equal(writes,2);assert.equal(s.baseNote,60);assert.equal(s.generation,7);checks++;
 let concurrent=0,maxConcurrent=0;
 c=new P.Client(bytes=>{
  const p=new P.Decoder().feed(bytes)[0];concurrent++;maxConcurrent=Math.max(concurrent,maxConcurrent);
  setTimeout(()=>{concurrent--;c.receive(wire(T.ACK,p.seq,status(p.type)));},1);
 },{timeout:50});
 await Promise.all([c.request(T.STOP),c.request(T.CLEAR),c.request(T.BEGIN)]);assert.equal(maxConcurrent,1);checks++;
 let attempt=0;const audio=P.join(P.u32(13),Uint8Array.of(2,2),P.u32(7),Uint8Array.of(1,2,3,4,5,6,7,8));
 c=new P.Client(bytes=>{
  const p=new P.Decoder().feed(bytes)[0];attempt++;
  const data=wire(T.AUDIO,p.seq,audio);
  if(attempt===1)data[data.length-1]^=64;
  setTimeout(()=>{
   const packets=P.join(data,wire(T.ACK,p.seq,status(T.READ)));
   for(let at=0;at<packets.length;at+=3)c.receive(packets.slice(at,at+3));
  },1);
 },{timeout:10});
 const result=await c.request(T.READ,P.join(P.u32(13),P.u16(2),Uint8Array.of(2)),{offset:13,count:2,channels:2,generation:7});
 assert.equal(attempt,2);assert.deepEqual([...result.pcm],[1,2,3,4,5,6,7,8]);checks++;
 c=new P.Client(bytes=>{const p=new P.Decoder().feed(bytes)[0];setTimeout(()=>c.receive(wire(T.ACK,p.seq,status(T.PLAY,3))),1);},{timeout:20});
 await assert.rejects(c.request(T.PLAY),/曲谱不完整/);checks++;
 c=new P.Client(bytes=>{const p=new P.Decoder().feed(bytes)[0];const corrupted=audio.slice();corrupted[6]=8;
  setTimeout(()=>c.receive(wire(T.AUDIO,p.seq,corrupted)),1);},{timeout:20});
 await assert.rejects(c.request(T.READ,new Uint8Array(),{offset:13,count:2,channels:2,generation:7}),/代次/);checks++;
 c=new P.Client(()=>{},{timeout:5,retries:2});await assert.rejects(c.request(T.HELLO),/板卡应答/);checks++;
 c=new P.Client(()=>{},{timeout:100});const pending=c.request(T.STOP);await Promise.resolve();c.close();await assert.rejects(pending,/中断/);checks++;
 const h=P.wavHeader(8000,2);assert.equal(Buffer.from(h.slice(0,4)).toString(),"RIFF");
 assert.equal(new DataView(h.buffer).getUint32(40,true),32000);checks++;
 const track=Buffer.from([0,0x90,60,100,0x83,0x60,60,0,0,0xff,0x2f,0]);
 const midi=Buffer.concat([Buffer.from("4d546864000000060000000101e04d54726b","hex"),Buffer.from([0,0,0,track.length]),track]);
 const song=M.parseMidi(midi.buffer.slice(midi.byteOffset,midi.byteOffset+midi.byteLength));
 assert.equal(song.events.length,2);assert.equal(song.events[1].time_us,500000);assert.equal(song.events[1].on,false);checks++;
 const wrong=midi.subarray(0,midi.length-3);assert.throws(()=>M.parseMidi(wrong.buffer.slice(wrong.byteOffset,wrong.byteOffset+wrong.byteLength)),/越界/);checks++;
 // MIDI notes outside the physical range must survive parsing for an explicit upload error.
 const outside=Buffer.from(midi);outside[outside.length-track.length+2]=120;
 const parsed=M.parseMidi(outside.buffer.slice(outside.byteOffset,outside.byteOffset+outside.length));assert.equal(parsed.events[0].note,120);checks++;
 const payload=P.eventsPayload(song.events);assert.equal(payload.length,16);assert.equal(new DataView(payload.buffer).getUint32(8,true),500);checks++;
 const base26=P.join(status(T.STATUS),Uint8Array.of(1,2),P.u16(99));base26[2]|=128;
 assert.equal(P.status(base26).calibrated,true);assert.equal(P.status(base26).calibrationEpoch,99);checks++;
 for(let baud=0;baud<3;baud++){
  const info=base26.slice();info[1]=T.RECORD_INFO;
  const token=Uint8Array.from({length:16},(_,i)=>i+1);
  const parsed=P.status(P.join(info,Uint8Array.of(1,baud),token));
  assert.equal(parsed.baud,[9600,115200,230400][baud]);assert.equal(parsed.recordInfoSupported,true);
  assert.equal(parsed.recordingToken,Buffer.from(token).toString("hex"));assert.equal(parsed.calibrated,true);checks++;
 }
 assert.throws(()=>P.status(P.join(base26,new Uint8Array(18))),/长度/);checks++;
 c=new P.Client(bytes=>{const p=new P.Decoder().feed(bytes)[0];setTimeout(()=>c.receive(wire(T.ACK,p.seq,status(p.type,1))),1);},{timeout:20});
 await assert.rejects(c.request(T.RECORD_INFO,new Uint8Array(16)),e=>e.boardCode===1);checks++;
 console.log(`PASS: ${checks} phone client checks: CRC/fragmentation, lost ACK, serialized commands, missing audio retry, generation/error/disconnect, WAV and MIDI running status/range`);
}
main().catch(error=>{console.error(error);process.exitCode=1;});
