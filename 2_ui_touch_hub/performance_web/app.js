(() => {
  "use strict";

  const KEY_COUNT = 32;
  const MAX_EVENTS = 16384;
  const PROTOCOL = Object.freeze({
    SYNC: 0xA5, VERSION: 0x01, MAX_PAYLOAD: 64,
    HELLO: 0x01, SONG_CLEAR: 0x10, SONG_BEGIN: 0x11, EVENT_BATCH: 0x12,
    SONG_END: 0x13, PLAY: 0x20, PAUSE: 0x21, STOP: 0x22,
    MANUAL_NOTE: 0x30, RECORD_START: 0x40, RECORD_STOP: 0x41
  });
  const state = { song: null, socket: null, baseNote: 60, recording: false, wavUrl: null, sequence: 0 };
  const $ = (id) => document.getElementById(id);

  function log(message) { $("log").textContent = message; }
  function setStatus(id, text, muted = false) {
    const node = $(id); node.textContent = text; node.classList.toggle("muted", muted);
  }
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
    if (![0, 1].includes(format) || division & 0x8000 || !division) throw new Error("仅支持 PPQN 格式 0/1 MIDI");
    let pos = 14, all = [], tempos = [{ tick: 0, tempo: 500000 }], maxTick = 0;
    for (let track = 0; track < tracks; track++) {
      if (pos + 8 > bytes.length || String.fromCharCode(...bytes.slice(pos, pos + 4)) !== "MTrk") throw new Error("MIDI 音轨损坏");
      const len = readU32(view, pos + 4), start = pos + 8, end = start + len; pos = end;
      if (end > bytes.length) throw new Error("MIDI 音轨越界");
      let p = start, tick = 0, running = 0, seq = 0;
      while (p < end) {
        let d; [d, p] = vlq(bytes, p, end); tick += d; maxTick = Math.max(maxTick, tick);
        let status = bytes[p];
        if (status & 0x80) { p++; if (status >= 0x80 && status <= 0xef) running = status; else if (status < 0xf8) running = 0; }
        else if (running) status = running; else throw new Error("MIDI running status 缺失");
        if (status === 0xff) {
          if (p >= end) throw new Error("MIDI meta 损坏"); const type = bytes[p++]; let n; [n, p] = vlq(bytes, p, end);
          if (p + n > end) throw new Error("MIDI meta 越界");
          if (type === 0x51 && n === 3) tempos.push({ tick, tempo: (bytes[p] << 16) | (bytes[p + 1] << 8) | bytes[p + 2] });
          p += n; seq++; if (type === 0x2f) break; continue;
        }
        if (status === 0xf0 || status === 0xf7) { let n; [n, p] = vlq(bytes, p, end); p += n; running = 0; seq++; continue; }
        if (status >= 0xf8) { seq++; continue; }
        const type = status & 0xf0, channel = (status & 0x0f) + 1;
        if ([0x80, 0x90, 0xa0, 0xb0, 0xe0].includes(type)) {
          if (p + 2 > end) throw new Error("MIDI 数据损坏"); const a = bytes[p++] & 0x7f, b = bytes[p++] & 0x7f;
          if (type === 0x80 || (type === 0x90 && b === 0)) all.push({ tick, seq, track, note: a, velocity: b, on: false, channel });
          else if (type === 0x90) all.push({ tick, seq, track, note: a, velocity: b, on: true, channel });
        } else if (type === 0xc0 || type === 0xd0) p++;
        else throw new Error(`不支持的 MIDI 状态 0x${status.toString(16)}`);
        seq++;
      }
    }
    const byTick = new Map([[0, 500000]]); tempos.sort((a, b) => a.tick - b.tick).forEach(t => byTick.set(t.tick, t.tempo));
    const points = [...byTick.keys()].sort((a, b) => a - b), starts = []; let base = 0, prev = points[0], tempo = byTick.get(prev);
    starts.push({ tick: prev, base, tempo });
    for (const t of points.slice(1)) { base += ((t - prev) * tempo) / division; prev = t; tempo = byTick.get(t); starts.push({ tick: t, base, tempo }); }
    const timeOf = (t) => { let i = 0; while (i + 1 < starts.length && starts[i + 1].tick <= t) i++; const s = starts[i]; return Math.floor(s.base + ((t - s.tick) * s.tempo) / division); };
    const events = all.filter(e => e.note >= 21 && e.note <= 108).map(e => ({ ...e, time_us: timeOf(e.tick) }));
    events.sort((a, b) => a.time_us - b.time_us || Number(a.on) - Number(b.on) || a.track - b.track || a.seq - b.seq);
    return { format, division, duration_us: timeOf(maxTick), events };
  }

  function renderPiano() {
    const piano = $("piano"); piano.replaceChildren();
    for (let i = 0; i < KEY_COUNT; i++) {
      const key = document.createElement("button"), note = state.baseNote + i;
      const pitch = note % 12, black = [1, 3, 6, 8, 10].includes(pitch);
      key.className = `key${black ? " black" : ""}`; key.dataset.key = i; key.textContent = black ? "" : `${note}`;
      const down = () => { key.classList.add("active"); send({ type: "MANUAL_NOTE", key: i, note, on: true, velocity: 100 }); };
      const up = () => { key.classList.remove("active"); send({ type: "MANUAL_NOTE", key: i, note, on: false, velocity: 0 }); };
      key.addEventListener("pointerdown", down); key.addEventListener("pointerup", up); key.addEventListener("pointercancel", up); key.addEventListener("pointerleave", (e) => { if (e.buttons) up(); });
      piano.appendChild(key);
    }
  }
  function crc16(bytes) {
    let crc = 0xffff;
    for (const byte of bytes) {
      crc ^= byte << 8;
      for (let i = 0; i < 8; i++) crc = (crc & 0x8000) ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
    }
    return crc;
  }
  function frame(type, payload = new Uint8Array()) {
    if (payload.length > PROTOCOL.MAX_PAYLOAD) throw new Error("性能帧载荷过大");
    const body = new Uint8Array(5 + payload.length);
    body[0] = PROTOCOL.VERSION; body[1] = type; body[2] = state.sequence++ & 0xff;
    body[3] = payload.length & 0xff; body[4] = (payload.length >>> 8) & 0xff; body.set(payload, 5);
    const crc = crc16(body), out = new Uint8Array(body.length + 3);
    out[0] = PROTOCOL.SYNC; out.set(body, 1); out[out.length - 2] = crc & 0xff; out[out.length - 1] = crc >>> 8;
    return out;
  }
  function u16(value) { return new Uint8Array([value & 0xff, (value >>> 8) & 0xff]); }
  function u32(value) { return new Uint8Array([value & 0xff, (value >>> 8) & 0xff, (value >>> 16) & 0xff, (value >>> 24) & 0xff]); }
  function sendFrame(type, payload = new Uint8Array()) {
    if (state.socket && state.socket.readyState === WebSocket.OPEN) state.socket.send(frame(type, payload));
    else log("网关未连接，控制帧未发送");
  }
  function concatBytes(...parts) {
    const total = parts.reduce((n, part) => n + part.length, 0), out = new Uint8Array(total); let at = 0;
    for (const part of parts) { out.set(part, at); at += part.length; }
    return out;
  }
  function sendEventBatch(events) {
    const payload = new Uint8Array(events.length * 8);
    events.forEach((event, index) => {
      const at = index * 8, time = Math.max(0, Math.floor(event.time_us / 1000));
      payload.set(u32(time), at); payload[at + 4] = event.note; payload[at + 5] = event.velocity;
      payload[at + 6] = event.on ? 1 : 0; payload[at + 7] = 0;
    });
    sendFrame(PROTOCOL.EVENT_BATCH, payload);
  }
  function connect() {
    if (state.socket) state.socket.close();
    const url = `${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/ws`;
    try {
      state.socket = new WebSocket(url); setStatus("gatewayStatus", "连接中…");
      state.socket.binaryType = "arraybuffer";
      state.socket.onopen = () => { setStatus("gatewayStatus", "网关已连接"); sendFrame(PROTOCOL.HELLO); log("已连接到性能网关，传输协议 V1"); };
      state.socket.onclose = () => setStatus("gatewayStatus", "网关未连接", true);
      state.socket.onerror = () => { setStatus("gatewayStatus", "连接失败", true); log("当前页面可离线解析 MIDI；网关 WebSocket 尚未接入"); };
      state.socket.onmessage = async (e) => {
        if (typeof e.data !== "string") return;
        try {
          const m = JSON.parse(e.data);
          if (m.progress != null) $("progress").style.width = `${Math.max(0, Math.min(1, m.progress)) * 100}%`;
          if (m.next_note != null) $("nextNote").textContent = `下一音符：MIDI ${m.next_note}`;
          if (m.recording === false && state.recording) { state.recording = false; $("recordButton").textContent = "开始录音"; }
        } catch (_) { /* Gateway status is advisory; binary FPGA frames are not rendered here. */ }
      };
    } catch (e) { setStatus("gatewayStatus", "浏览器不支持", true); log(String(e)); }
  }
  function formatTime(us) { const total = Math.round(us / 1e6); return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`; }
  $("songFile").addEventListener("change", async (e) => {
    const file = e.target.files?.[0]; if (!file) return;
    try {
      state.song = parseMidi(await file.arrayBuffer()); state.song.name = file.name;
      $("songTitle").textContent = file.name; $("songMeta").textContent = `${formatTime(state.song.duration_us)} · ${state.song.events.length} 个 Note 事件`;
      $("eventStats").textContent = `${state.song.events.length} events`; setStatus("songStatus", "曲谱已解析"); log("曲谱已在手机本地解析，等待发送到网关");
    } catch (err) { state.song = null; setStatus("songStatus", "曲谱错误", true); log(err.message || String(err)); }
  });
  $("baseNote").addEventListener("change", (e) => { state.baseNote = Number(e.target.value); renderPiano(); });
  $("connectButton").addEventListener("click", connect);
  $("uploadButton").addEventListener("click", () => {
    if (!state.song) return log("请先选择有效 MIDI 曲谱");
    if (state.song.events.length > MAX_EVENTS) return log("曲谱超过此候选固件的 16384 个事件容量，不能截断发送");
    sendFrame(PROTOCOL.SONG_CLEAR);
    sendFrame(PROTOCOL.SONG_BEGIN, concatBytes(u32(Math.floor(state.song.duration_us / 1000)), u16(state.song.events.length)));
    for (let at = 0; at < state.song.events.length; at += 8) sendEventBatch(state.song.events.slice(at, at + 8));
    sendFrame(PROTOCOL.SONG_END);
    setStatus("songStatus", "已发送到网关");
    log(`已发送 ${state.song.events.length} 个事件（V1 二进制分块）`);
  });
  $("playButton").addEventListener("click", () => sendFrame(PROTOCOL.PLAY));
  $("pauseButton").addEventListener("click", () => sendFrame(PROTOCOL.PAUSE));
  $("stopButton").addEventListener("click", () => sendFrame(PROTOCOL.STOP));
  $("recordButton").addEventListener("click", () => {
    state.recording = !state.recording; $("recordButton").textContent = state.recording ? "停止录音" : "开始录音";
    sendFrame(state.recording ? PROTOCOL.RECORD_START : PROTOCOL.RECORD_STOP);
  });
  renderPiano();
})();
