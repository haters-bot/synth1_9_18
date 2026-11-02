"use strict";
const assert=require('node:assert/strict');
const {adaptToRange}=require('../performance_web/midi.js');
const event=(note,time,on=true,track=0,channel=1,id=0)=>({note,time_us:time,on,velocity:on?100:0,track,channel,id});
const song=events=>({duration_us:Math.max(1000,...events.map(e=>e.time_us)),events});
function verify(result,original,base,count){
 const active=new Set();let previous=-1;
 for(const e of result.events){
  assert.ok(e.note>=base && e.note<base+count);assert.ok(e.time_us>=previous);previous=e.time_us;
  if(e.on){assert.ok(!active.has(e.note));active.add(e.note);}
  else {assert.ok(active.has(e.note));active.delete(e.note);}
 }
 assert.equal(active.size,0);
 assert.equal(result.duration_us,original.duration_us);
 assert.equal(result.events.filter(e=>e.on).length+result.adaptation.mergedOn,original.events.filter(e=>e.on && e.velocity>0).length);
 assert.ok(Number.isFinite(result.adaptation.optimizationCost));
}
let checks=0;
for(const base of [41,53,65,77])for(let low=0;low<128;low++)for(let high=low;high<128;high++)for(const position of [0,.5,1]){
 const input=song([event(low,0,true,0,1,1),event(high,10,true,0,1,2),event(low,20,false),event(high,30,false)]);
 const snapshot=JSON.stringify(input),wide=high-low>=32;
 const output=adaptToRange(input,base,32,{position,compress:true});verify(output,input,base,32);
 const a=output.adaptation;
 assert.equal(a.compressed,wide);assert.equal(a.mappedLow,base+Math.round(a.availableShift*position));
 for(const e of output.events.filter(e=>e.on)){
  const source=input.events.find(s=>s.on && s.id===e.id);
  assert.equal(e.time_us,source.time_us);assert.equal(e.velocity,source.velocity);
  assert.equal(Math.abs((e.note-source.note-a.shift)%12),0);
  if(!wide)assert.equal(e.note,source.note+a.shift);
 }
 if(!wide){assert.equal(a.mappedHigh-a.mappedLow,high-low);assert.equal(a.foldedOn,0);}
 assert.equal(JSON.stringify(input),snapshot);checks++;
}
// Include all MIDI pitches and independent, overlapping track/channel owners.
const chromatic=[];
for(let n=0;n<128;n++){chromatic.push(event(n,n*1000,true,n%3,n%4+1,n));chromatic.push(event(n,n*1000+800,false,n%3,n%4+1,n));}
const full=song(chromatic),copy=JSON.stringify(full),folded=adaptToRange(full,41,32,{position:0,compress:true});
verify(folded,full,41,32);assert.ok(folded.adaptation.foldedOn>0);assert.equal(JSON.stringify(full),copy);checks++;
// Force an octave collision in a one-octave target. The first source's release
// must not release the second owner, and no note can be left hanging.
const shared=song([event(0,0,true,0,1),event(120,100,true,1,2),event(0,200,false,0,1),event(120,300,false,1,2)]);
const merged=adaptToRange(shared,41,12,{compress:true,position:0});verify(merged,shared,41,12);
assert.equal(merged.adaptation.mergedOn,1);assert.deepEqual(merged.events.map(e=>e.time_us),[0,300]);checks++;
// Repeated overlapping source notes retain their own mapped release queue.
const repeated=song([event(0,0),event(72,10),event(72,15),event(127,20),event(72,30,false),event(127,35,false),event(72,40,false),event(0,50,false)]);
verify(adaptToRange(repeated,77,32,{compress:true,position:1}),repeated,77,32);checks++;
const unclosed=song([event(0,0),event(127,20),event(90,30,false)]);
const fixed=adaptToRange(unclosed,41,32,{compress:true,position:0});verify(fixed,unclosed,41,32);assert.equal(fixed.adaptation.orphanOff,1);assert.ok(fixed.adaptation.closedNotes);checks++;
const wide=song([event(40,0),event(72,10),event(40,20,false),event(72,30,false)]);
assert.throws(()=>adaptToRange(wide,41,32,{position:0,compress:false}),/允许八度压缩/);checks++;
assert.throws(()=>adaptToRange(wide,41,32,{position:0,compress:'false'}),/允许八度压缩/);checks++;
// Independent exhaustive search checks the dynamic optimizer's minimum for a
// small voice, rather than comparing it with another dynamic implementation.
const pitches=[0,100,101,127],smallEvents=[];
for(let i=0;i<pitches.length;i++){smallEvents.push(event(pitches[i],i*100,true));smallEvents.push(event(pitches[i],i*100+50,false));}
const small=song(smallEvents),optimized=adaptToRange(small,41,32,{compress:true,position:0}),scale=31/127;
function cost(path){
 let total=0;
 for(let i=0;i<path.length;i++){
  total+=(1+50/500000*100/127)*(path[i]-pitches[i]*scale)**2;
  if(i){const source=pitches[i]-pitches[i-1],actual=path[i]-path[i-1];total+=.75*(actual-source*scale)**2;if(source*actual<0)total+=36+4*Math.abs(actual);}
 }
 return total;
}
let minimum=Infinity;
function enumerate(path){
 if(path.length===pitches.length){minimum=Math.min(minimum,cost(path));return;}
 const p=pitches[path.length];if(!p)enumerate([...path,0]);else for(let q=p%12;q<32;q+=12)enumerate([...path,q]);
}
enumerate([]);
assert.ok(Math.abs(optimized.adaptation.optimizationCost-minimum)<1e-7);
assert.ok(Math.abs(cost(optimized.events.filter(e=>e.on).map(e=>e.note-41))-minimum)<1e-7);checks++;
for(const position of [-1,2,NaN,Infinity]){assert.throws(()=>adaptToRange(wide,41,32,{compress:true,position}),/琴键位置/);checks++;}
console.log(`PASS: ${checks} explicit placement/octave-compression cases; all 8256 source ranges x4 banks x3 positions, pitch classes/timing/velocity, immutable source, collision/release ownership, repeated notes and opt-in guard`);
