(function(root) {
  "use strict";
  function readU16(view, at) { return view.getUint16(at, false); }
  function readU32(view, at) { return view.getUint32(at, false); }
  function vlq(bytes, pos, end) {
    let value = 0;
    for (let i = 0; i < 4; i++) {
      if (pos >= end) throw new Error("MIDI VLQ truncated");
      const b = bytes[pos++]; value = (value << 7) | (b & 0x7f);
      if (!(b & 0x80)) return [value, pos];
    }
    throw new Error("MIDI VLQ too long");
  }
  function parseMidi(buffer) {
    const bytes = new Uint8Array(buffer), view = new DataView(buffer);
    if (bytes.length < 14 || String.fromCharCode(...bytes.slice(0, 4)) !== "MThd") throw new Error("不是有效 MIDI 文件");
    if (readU32(view, 4) !== 6) throw new Error("不支持的 MIDI 头长度");
    const format = readU16(view, 8), tracks = readU16(view, 10), division = readU16(view, 12);
    if (![0, 1].includes(format) || division & 0x8000 || !division || !tracks || (format === 0 && tracks !== 1)) throw new Error("仅支持 PPQN 格式 0/1 MIDI");
    let pos = 14, all = [], tempos = [{ tick: 0, tempo: 500000 }], maxTick = 0;
    for (let track = 0; track < tracks; track++) {
      if (pos + 8 > bytes.length || String.fromCharCode(...bytes.slice(pos, pos + 4)) !== "MTrk") throw new Error("MIDI 音轨损坏");
      const len = readU32(view, pos + 4), start = pos + 8, end = start + len; pos = end;
      if (end > bytes.length) throw new Error("MIDI 音轨越界");
      let p = start, tick = 0, running = 0, seq = 0;
      while (p < end) {
        let d; [d, p] = vlq(bytes, p, end); tick += d; maxTick = Math.max(maxTick, tick);
        if (p >= end) throw new Error("MIDI status truncated");
        let status = bytes[p];
        if (status & 0x80) { p++; if (status >= 0x80 && status <= 0xef) running = status; else if (status < 0xf8) running = 0; }
        else if (running) status = running; else throw new Error("MIDI running status 缺失");
        if (status === 0xff) {
          if (p >= end) throw new Error("MIDI meta 损坏"); const type = bytes[p++]; let n; [n, p] = vlq(bytes, p, end);
          if (p + n > end) throw new Error("MIDI meta 越界");
          if (type === 0x51 && n === 3) tempos.push({ tick, tempo: (bytes[p] << 16) | (bytes[p + 1] << 8) | bytes[p + 2] });
          p += n; seq++; if (type === 0x2f) break; continue;
        }
        if (status === 0xf0 || status === 0xf7) { let n; [n, p] = vlq(bytes, p, end); if (p + n > end) throw new Error("MIDI SysEx truncated"); p += n; running = 0; seq++; continue; }
        if (status >= 0xf8) { seq++; continue; }
        const type = status & 0xf0, channel = (status & 0x0f) + 1;
        if ([0x80, 0x90, 0xa0, 0xb0, 0xe0].includes(type)) {
          if (p + 2 > end) throw new Error("MIDI 数据损坏"); const a = bytes[p++], b = bytes[p++]; if (a > 127 || b > 127) throw new Error("MIDI data byte invalid");
          if (type === 0x80 || (type === 0x90 && b === 0)) all.push({ tick, seq, track, note: a, velocity: b, on: false, channel });
          else if (type === 0x90) all.push({ tick, seq, track, note: a, velocity: b, on: true, channel });
        } else if (type === 0xc0 || type === 0xd0) { if (p >= end || bytes[p++] > 127) throw new Error("MIDI data truncated"); }
        else throw new Error(`不支持的 MIDI 状态 0x${status.toString(16)}`);
        seq++;
      }
    }
    const byTick = new Map([[0, 500000]]); tempos.sort((a, b) => a.tick - b.tick).forEach(t => byTick.set(t.tick, t.tempo));
    const points = [...byTick.keys()].sort((a, b) => a - b), starts = []; let base = 0, prev = points[0], tempo = byTick.get(prev);
    starts.push({ tick: prev, base, tempo });
    for (const t of points.slice(1)) { base += ((t - prev) * tempo) / division; prev = t; tempo = byTick.get(t); starts.push({ tick: t, base, tempo }); }
    const timeOf = (t) => { let i = 0; while (i + 1 < starts.length && starts[i + 1].tick <= t) i++; const s = starts[i]; return Math.floor(s.base + ((t - s.tick) * s.tempo) / division); };
    if (tempos.some(t => !t.tempo)) throw new Error("MIDI tempo cannot be zero");
    const events = all.map(e => ({ ...e, time_us: timeOf(e.tick) }));
    events.sort((a, b) => a.time_us - b.time_us || Number(a.on) - Number(b.on) || a.track - b.track || a.seq - b.seq);
    const duration_us = timeOf(maxTick); if (!Number.isSafeInteger(duration_us) || duration_us > 4294967295000) throw new Error("MIDI duration overflow");
    return { format, division, duration_us, events };
  }

  if(typeof module !== "undefined" && module.exports) module.exports = {parseMidi}; else root.PerformanceMidi = {parseMidi};
})(typeof globalThis !== "undefined" ? globalThis : this);
