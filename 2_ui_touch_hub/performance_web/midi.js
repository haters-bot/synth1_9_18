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

  // Keep the original song immutable. Pitch adaptation runs only on the upload
  // copy, against the range acknowledged by the FPGA.
  function adaptToRange(song, base, count) {
    const last = base + count - 1;
    if (!Number.isInteger(base) || !Number.isInteger(count) || base < 0 || last > 127 || count < 12)
      throw new Error("板卡音域无效，至少需要一个完整八度");
    if (!song.events.length) throw new Error("曲谱没有 Note 事件");
    let low = 127, high = 0;
    const sounding = song.events.filter(e => e.on && e.velocity > 0);
    if (!sounding.length) throw new Error("曲谱没有 Note On 事件");
    for (const e of sounding) { low = Math.min(low, e.note); high = Math.max(high, e.note); }
    const width = high - low + 1;
    if (width > count) throw new Error(`曲谱音域 MIDI ${low}–${high}，含两端共${width}键，超过本次校准的${count}键；不能整体移调容纳，已禁止传输。请另行导出音域较小的编曲`);
    let shift = 0, strategy = "original";
    if (low < base || high > last) {
      const minShift = base - low, maxShift = last - high;
      if (minShift <= maxShift) {
        // Prefer whole octaves: the key signature and intervals stay intact.
        const firstOct = Math.ceil(minShift / 12), lastOct = Math.floor(maxShift / 12);
        shift = firstOct <= lastOct ? Math.max(firstOct, Math.min(0, lastOct)) * 12 :
          (minShift > 0 ? minShift : maxShift);
        strategy = "transpose";
      }
    }
    const mapNote = note => note + shift;
    // Tracks may share a physical key. Keep it down until all owners release it.
    const active = new Map(), held = new Map(), events = [];
    let foldedOn = 0, mergedOn = 0, orphanOff = 0, closedNotes = 0;
    const ordered = song.events.slice().sort((a,b) => a.time_us-b.time_us || Number(a.on)-Number(b.on));
    for (const e of ordered) {
      const note = mapNote(e.note), key = `${e.track || 0}:${e.channel || 1}:${e.note}`;
      const refs = active.get(note) || 0, own = held.get(key) || 0;
      if (e.on) {
        if (note !== e.note + shift) foldedOn++;
        held.set(key, own + 1); active.set(note, refs + 1);
        if (!refs) events.push({...e, note}); else mergedOn++;
      } else if (own) {
        held.set(key, own - 1); active.set(note, refs - 1);
        if (refs === 1) events.push({...e, note});
      } else orphanOff++;
    }
    for (const [note, refs] of active) if (refs) {
      events.push({time_us:song.duration_us, note, velocity:0, on:false}); closedNotes++;
    }
    let mappedLow = 127, mappedHigh = 0;
    for (const e of events) { mappedLow = Math.min(mappedLow, e.note); mappedHigh = Math.max(mappedHigh, e.note); }
    const pitchText = strategy === "original" ? "保持原调" :
      `整曲${shift > 0 ? "升" : "降"}${Math.abs(shift)}个半音`;
    const details = [pitchText, `MIDI ${low}–${high} → ${mappedLow}–${mappedHigh}`];
    if (mergedOn) details.push(`合并${mergedOn}个重叠同键音`);
    if (orphanOff) details.push(`忽略${orphanOff}个无对应按下的松键`);
    if (closedNotes) details.push(`末尾补齐${closedNotes}个松键`);
    return {...song, events, adaptation:{strategy, shift, foldedOn, mergedOn, orphanOff, closedNotes,
      originalLow:low, originalHigh:high, mappedLow, mappedHigh, summary:details.join("；")}};
  }

  if(typeof module !== "undefined" && module.exports) module.exports = {parseMidi, adaptToRange}; else root.PerformanceMidi = {parseMidi, adaptToRange};
})(typeof globalThis !== "undefined" ? globalThis : this);
