(function (root) {
  "use strict";
  const TYPES = Object.freeze({HELLO:1, STATUS:2, CLEAR:16, BEGIN:17, EVENTS:18, END:19,
    PLAY:32, PAUSE:33, STOP:34, MODE:35, NOTE:48, RECORD_START:64, RECORD_STOP:65, READ:67, ACK:112, AUDIO:113});
  const u16 = n => Uint8Array.of(n & 255, n >>> 8 & 255);
  const u32 = n => Uint8Array.of(n & 255, n >>> 8 & 255, n >>> 16 & 255, n >>> 24 & 255);
  function join(...parts) {
    const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0)); let at=0;
    for (const p of parts) {out.set(p, at); at+=p.length;} return out;
  }
  function crc16(data) {
    let c=65535; for(const b of data) {c^=b<<8; for(let n=0;n<8;n++) c=(c&32768)?((c<<1)^0x1021)&65535:(c<<1)&65535;} return c;
  }
  function frame(type, seq, data=new Uint8Array()) {
    if(data.length>64) throw Error("Payload exceeds 64 bytes");
    const body=join(Uint8Array.of(1,type,seq),u16(data.length),data);
    return join(Uint8Array.of(165),body,u16(crc16(body)));
  }
  class Decoder {
    constructor() {this.bytes=new Uint8Array(); this.bad=0;}
    feed(bytes) {
      this.bytes=join(this.bytes,bytes);const packets=[];
      while(this.bytes.length) {
        if(this.bytes[0]!==165) {this.bytes=this.bytes.slice(1); continue;}
        if(this.bytes.length<6)break;
        const n=this.bytes[4]|this.bytes[5]<<8;
        if(this.bytes[1]!==1 || n>64) {this.bytes=this.bytes.slice(1);this.bad++;continue;}
        if(this.bytes.length<n+8)break;
        if(crc16(this.bytes.slice(1,n+6))!==(this.bytes[n+6]|this.bytes[n+7]<<8)) {this.bytes=this.bytes.slice(1);this.bad++;continue;}
        packets.push({type:this.bytes[2],seq:this.bytes[3],payload:this.bytes.slice(6,n+6)});
        this.bytes=this.bytes.slice(n+8);
      }
      return packets;
    }
  }
  function status(data) {
    if(data.length!==22)throw Error("板卡状态帧长度错误");
    const v=new DataView(data.buffer,data.byteOffset,data.byteLength);
    return {code:data[0],request:data[1],flags:data[2],recordStatus:data[3],storedFrames:v.getUint32(4,true),
      events:v.getUint16(8,true),baseNote:data[10],keyCount:data[11],sampleRate:v.getUint32(12,true),
      generation:v.getUint32(16,true),maxEvents:v.getUint16(20,true),
      recording:!!(data[2]&1),busy:!!(data[2]&2),backend:!!(data[2]&4),loaded:!!(data[2]&8),fast:!!(data[2]&16)};
  }
  const errors={1:"格式或音域错误",2:"板卡忙或音源／DDR未就绪",3:"曲谱不完整或调度拒绝",4:"录音范围无效",5:"DDR读取错误",6:"板卡处理超时"};
  class Client {
    constructor(send, options={}) {this.send=send;this.decoder=new Decoder();this.sequence=0;this.tail=Promise.resolve();this.pending=null;
      this.timeout=options.timeout||3500;this.retryLimit=options.retries||3;this.onStatus=options.onStatus||(()=>{});this.lastStatus=null;this.closed=false;}
    request(type,payload=new Uint8Array(),audio=null) {
      const run=()=>this.perform(type,payload,audio);
      const promise=this.tail.then(run);this.tail=promise.catch(()=>{});return promise;
    }
    perform(type,payload,audio) {
      if(this.closed)return Promise.reject(Error("连接已断开"));
      return new Promise((resolve,reject)=>{
        const seq=this.sequence++&255,wire=frame(type,seq,payload);
        const p={type,seq,resolve,reject,audio,attempt:0,wire,timer:null};
        if(audio) {p.pcm=new Uint8Array(audio.count*audio.channels*2);p.seen=new Uint8Array(audio.count);}
        this.pending=p;this.transmit(p);
      });
    }
    arm(p) {clearTimeout(p.timer);p.timer=setTimeout(()=>this.transmit(p),this.timeout);}
    transmit(p) {
      if(this.pending!==p)return;
      if(++p.attempt>this.retryLimit) {this.finish(p,Error("未收到完整板卡应答；检查模块配对、交叉接线和波特率"));return;}
      // A truncated response from an earlier attempt must not hide the retry's ACK.
      this.decoder=new Decoder();
      try {this.send(p.wire);this.arm(p);}catch(e){this.finish(p,e);}
    }
    receive(bytes) {
      for(const packet of this.decoder.feed(bytes)) {
        const p=this.pending;if(!p || p.seq!==packet.seq)continue;
        try {
          if(packet.type===TYPES.AUDIO && p.audio) {
            const b=packet.payload;if(b.length<10)throw Error("录音数据帧过短");
            const v=new DataView(b.buffer,b.byteOffset,b.byteLength),at=v.getUint32(0,true),n=b[4],ch=b[5],gen=v.getUint32(6,true);
            if(!n || ch!==p.audio.channels || gen!==p.audio.generation || at<p.audio.offset || at+n>p.audio.offset+p.audio.count || b.length!==10+n*ch*2)
              throw Error("录音数据偏移、声道或录音代次不一致");
            p.pcm.set(b.slice(10),(at-p.audio.offset)*ch*2);p.seen.fill(1,at-p.audio.offset,at-p.audio.offset+n);p.audio.onProgress?.(p.seen.reduce((a,b)=>a+b,0));this.arm(p);
          } else if(packet.type===TYPES.ACK) {
            const s=status(packet.payload);if(s.request!==p.type)continue;
            this.lastStatus=s;this.onStatus(s);
            if(s.code)throw Error(`板卡拒绝：${errors[s.code]||s.code}`);
            if(p.audio) {
              if(s.generation!==p.audio.generation)throw Error("录音已被新一轮覆盖，停止下载");
              if(p.seen.some(n=>!n))continue; // Retain request; timeout retries missing/CRC-bad data.
            }
            this.finish(p,null,p.audio?{status:s,pcm:p.pcm}:s);
          }
        } catch(e) {this.finish(p,e);}
      }
    }
    finish(p,error,result) {if(this.pending!==p)return;clearTimeout(p.timer);this.pending=null;error?p.reject(error):p.resolve(result);}
    close() {this.closed=true;if(this.pending)this.finish(this.pending,Error("蓝牙连接中断；曲谱请重新上传，录音可按原偏移重试"));}
  }
  function eventsPayload(events) {
    if(!events.length || events.length>8)throw Error("事件批量范围错误");
    return join(...events.map(e=>join(u32(Math.floor(e.time_us/1000)),Uint8Array.of(e.note,e.velocity,e.on?1:0,0))));
  }
  function wavHeader(frames,channels,rate=8000) {
    const b=new Uint8Array(44),v=new DataView(b.buffer),size=frames*channels*2;
    const ascii=(at,s)=>[...s].forEach((c,i)=>b[at+i]=c.charCodeAt(0));
    ascii(0,"RIFF");v.setUint32(4,36+size,true);ascii(8,"WAVEfmt ");v.setUint32(16,16,true);v.setUint16(20,1,true);
    v.setUint16(22,channels,true);v.setUint32(24,rate,true);v.setUint32(28,rate*channels*2,true);
    v.setUint16(32,channels*2,true);v.setUint16(34,16,true);ascii(36,"data");v.setUint32(40,size,true);return b;
  }
  const api={TYPES,u16,u32,join,crc16,frame,Decoder,status,Client,eventsPayload,wavHeader};
  if(typeof module!=="undefined" && module.exports)module.exports=api;else root.PerformanceProtocol=api;
})(typeof globalThis!=="undefined"?globalThis:this);
