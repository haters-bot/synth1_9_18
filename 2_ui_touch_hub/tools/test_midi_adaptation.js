"use strict";
const assert=require('node:assert/strict'),fs=require('node:fs');
const {parseMidi,adaptToRange}=require('../performance_web/midi.js');
const event=(note,time,on=true,track=0,channel=1)=>({note,time_us:time,on,velocity:on?100:0,track,channel});
const song=events=>({duration_us:1000,events});
function verify(result,base=41,count=32){
 const held=new Set();let prev=-1;
 for(const e of result.events){
  assert.ok(e.note>=base&&e.note<base+count);assert.ok(e.time_us>=prev);prev=e.time_us;
  if(e.on){assert.ok(!held.has(e.note),'duplicate active physical key');held.add(e.note);}
  else {assert.ok(held.has(e.note),'unmatched release');held.delete(e.note);}
 }
 assert.equal(held.size,0);
}
let checks=0;
for(let lo=0;lo<128;lo++)for(let hi=lo;hi<128;hi++){
 const original=song([event(lo,0),event(hi,10),event(lo,20,false),event(hi,30,false)]);
 const snapshot=JSON.stringify(original);
 if(hi-lo<=31){const r=adaptToRange(original,41,32);verify(r);assert.notEqual(r.adaptation.strategy,'fold');assert.equal(r.adaptation.foldedOn,0);}
 else assert.throws(()=>adaptToRange(original,41,32),/超过.*32键.*禁止传输/);
 assert.equal(JSON.stringify(original),snapshot);checks++;
}
for(const base of [41,53,65,77])for(let lo=0;lo<128;lo++)for(let width=1;width<=32 && lo+width<=128;width++){
 const hi=lo+width-1;
 const r=adaptToRange(song([event(lo,0),event(hi,10),event(lo,20,false),event(hi,30,false)]),base,32);
 verify(r,base);assert.equal(r.adaptation.mappedHigh-r.adaptation.mappedLow,hi-lo);
 assert.ok(r.events.every(e=>e.note===lo+r.adaptation.shift || e.note===hi+r.adaptation.shift));
 const minimum=base-lo,maximum=base+31-hi;
 if(Math.ceil(minimum/12)<=Math.floor(maximum/12))assert.ok(r.adaptation.shift%12===0);
 if(lo>=base && hi<=base+31)assert.equal(r.adaptation.shift,0);
 checks++;
}
const input=song([event(0,0),event(12,10),event(0,20,false),event(12,30,false),event(127,40),event(127,50,false)]);
assert.throws(()=>adaptToRange(input,41,32),/128键.*超过/);checks++;
const unclosed=adaptToRange(song([event(41,0),event(99,1,false)]),41,32);verify(unclosed);
assert.equal(unclosed.adaptation.closedNotes,1);assert.equal(unclosed.adaptation.orphanOff,1);checks++;
const overlap=adaptToRange(song([event(60,0,true,0),event(60,10,true,1),event(60,20,false,0),event(60,30,false,1)]),41,32);
verify(overlap);assert.equal(overlap.events[1].time_us,30);checks++;
// A sequential retrigger at the same timestamp must remain Off then On.
const retrigger=adaptToRange(song([event(60,0),event(60,10),event(60,10,false),event(60,20,false)]),41,32);
assert.deepEqual(retrigger.events.map(e=>e.on),[true,false,true,false]);verify(retrigger);checks++;
// Tight but playable range may require a semitone shift instead of an octave.
const tight=adaptToRange(song([event(40,0),event(71,10),event(40,20,false),event(71,30,false)]),41,32);
assert.equal(tight.adaptation.shift,1);assert.equal(tight.adaptation.strategy,'transpose');verify(tight);checks++;
assert.throws(()=>adaptToRange(input,120,32),/音域无效/);checks++;
const file=require.resolve('../performance_web/examples/Twinkle_Twinkle_90bpm_C4_A4.mid');
const b=fs.readFileSync(file),original=parseMidi(b.buffer.slice(b.byteOffset,b.byteOffset+b.length));
const twinkle=adaptToRange(original,41,32);verify(twinkle);
assert.equal(twinkle.adaptation.strategy,'original');assert.equal(twinkle.adaptation.mappedLow,60);assert.equal(twinkle.adaptation.mappedHigh,69);
assert.deepEqual(twinkle.events,original.events);checks++;
console.log(`PASS: ${checks} MIDI adaptation cases: all 8256 pitch ranges, four calibrated banks, inclusive width<=32 only, wide scores refused, intervals preserved, octave priority, retriggers, immutable source, Twinkle unchanged`);
