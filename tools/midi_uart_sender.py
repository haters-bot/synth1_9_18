#!/usr/bin/env python3
"""通过串口发送MIDI演奏消息和双振荡器控制消息的桌面测试工具。"""

from __future__ import annotations

import tkinter as tk
from tkinter import messagebox, ttk

from lfo_curve import LfoCurve, LfoCurveEditor

try:
    import serial
    from serial.tools import list_ports
except ImportError:  # 允许在缺少依赖时显示清晰提示，而不是直接退出。
    serial = None
    list_ports = None


NOTE_NAMES = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
KEY_TO_NOTE = {
    "a": 60,
    "w": 61,
    "s": 62,
    "e": 63,
    "d": 64,
    "f": 65,
    "t": 66,
    "g": 67,
    "y": 68,
    "h": 69,
    "u": 70,
    "j": 71,
    "k": 72,
}
CONTROL_CHANNEL = 16
PAN_CC = 10
FILTER_MODE_CC = 42
FILTER_CUTOFF_CC = 43
FILTER_RESONANCE_CC = 44
FILTER_MIX_CC = 45
MASTER_LEVEL_CC = 48
# FPGA三点通用LFO与8槽调制矩阵的影子寄存器参数编号。
FILTER_LFO_PARAMETER = {
    "enable": 16,
    "step_0": 17,
    "step_1": 18,
    "point_0": 20,
    "point_1": 21,
    "point_2": 22,
    "curve_0": 23,
    "curve_1": 24,
    "commit": 25,
    "route_index": 26,
    "route_enable": 27,
    "route_destination": 28,
    "route_depth": 29,
}
FILTER_LFO_CONFIG_DEBOUNCE_MS = 75
FILTER_LFO_PHASE_BITS = 24
FILTER_LFO_SAMPLE_RATE = 96000.0
LFO_DESTINATIONS = {
    "无": 0,
    "OSC A WT Position": 1,
    "OSC A Warp Amount": 2,
    "OSC A Level": 3,
    "OSC B WT Position": 4,
    "OSC B Warp Amount": 5,
    "OSC B Level": 6,
    "Pan（当前预留）": 7,
    "Filter Cutoff": 8,
    "Filter Resonance": 9,
    "Filter Mix": 10,
}
OSC_A_CC = {
    "enable": 36,
    "warp_mode": 38,
    "warp_amount": 39,
    "wt_position": 20,
    "waveform": 21,
    "detune": 22,
    "unison": 23,
    "attack": 24,
    "decay": 25,
    "sustain": 26,
    "release": 27,
    "level": 46,
}
OSC_B_CC = {
    "enable": 37,
    "warp_mode": 40,
    "warp_amount": 41,
    "wt_position": 28,
    "waveform": 29,
    "detune": 30,
    "unison": 31,
    "attack": 32,
    "decay": 33,
    "sustain": 34,
    "release": 35,
    "level": 47,
}
WAVEFORM_VALUES = {
    "正弦波": 0,
    "三角波": 32,
    "方波": 64,
    "锯齿波": 96,
    "Acid波表": 127,
}
WARP_MODE_VALUES = {
    "关闭": 0,
    "PWM": 1,
    "Sync": 2,
    "Bend +": 3,
    "Bend -": 4,
    "Bend +/-": 5,
    "Asym +": 6,
    "Asym -": 7,
    "Asym +/-": 8,
    "Flip": 9,
    "Mirror": 10,
    "Quantize": 11,
}
FILTER_MODE_VALUES = {
    "旁路": 0,
    "低通": 1,
    "高通": 2,
    "带通": 3,
    "陷波": 4,
    "梳状 +": 5,
    "梳状 -": 6,
}


def note_name(note: int) -> str:
    return f"{NOTE_NAMES[note % 12]}{note // 12 - 1}"


class MidiUartSender:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("FPGA MIDI UART 测试器")
        self.root.resizable(False, False)

        self.port = None
        self.port_lookup: dict[str, str] = {}
        self.active_notes: set[int] = set()
        self.keyboard_notes: set[int] = set()
        self.filter_lfo_curve = LfoCurve()
        self.filter_lfo_window: tk.Toplevel | None = None
        self.filter_lfo_config_after_id: str | None = None

        self.port_name = tk.StringVar()
        self.baud_rate = tk.StringVar(value="31250")
        self.channel = tk.IntVar(value=1)
        self.velocity = tk.IntVar(value=100)
        self.pan = tk.IntVar(value=64)
        self.filter_mode = tk.StringVar(value="旁路")
        self.filter_cutoff = tk.IntVar(value=127)
        self.filter_resonance = tk.IntVar(value=0)
        self.filter_mix = tk.IntVar(value=127)
        self.master_level = tk.IntVar(value=127)
        self.filter_lfo_enabled = tk.BooleanVar(value=False)
        self.filter_lfo_rate = tk.DoubleVar(value=0.5)
        self.lfo_routes = []
        default_routes = [
            (True, "Filter Cutoff", 32),
            (False, "无", 0),
            (False, "无", 0),
            (False, "无", 0),
            (False, "无", 0),
            (False, "无", 0),
            (False, "无", 0),
            (False, "无", 0),
        ]
        for enabled, destination, depth in default_routes:
            self.lfo_routes.append(
                {
                    "enabled": tk.BooleanVar(value=enabled),
                    "destination": tk.StringVar(value=destination),
                    "depth": tk.IntVar(value=depth),
                }
            )
        self.osc_controls = {}
        for osc_name in ("A", "B"):
            # 默认值与FPGA复位音色一致：约10 ms、102 ms、70%、315 ms。
            self.osc_controls[osc_name] = {
                "enabled": tk.BooleanVar(value=True),
                "waveform": tk.StringVar(value="方波"),
                "warp_mode": tk.StringVar(value="关闭"),
                "warp_amount": tk.IntVar(value=0),
                "wt_position": tk.IntVar(value=0),
                "detune": tk.IntVar(value=64),
                "unison": tk.IntVar(value=1),
                "attack": tk.IntVar(value=27),
                "decay": tk.IntVar(value=54),
                "sustain": tk.IntVar(value=89),
                "release": tk.IntVar(value=67),
                "level": tk.IntVar(value=127),
            }
        self.status = tk.StringVar(value="未连接")

        self._build_ui()
        self.refresh_ports()

        self.root.bind_all("<KeyPress>", self._key_press)
        self.root.bind_all("<KeyRelease>", self._key_release)
        self.root.protocol("WM_DELETE_WINDOW", self.close)

    def _build_ui(self) -> None:
        connection = ttk.LabelFrame(self.root, text="串口连接", padding=10)
        connection.grid(row=0, column=0, padx=10, pady=8, sticky="ew")

        ttk.Label(connection, text="端口").grid(row=0, column=0, padx=4)
        self.port_box = ttk.Combobox(
            connection, textvariable=self.port_name, width=18, state="readonly"
        )
        self.port_box.grid(row=0, column=1, padx=4)
        ttk.Button(connection, text="刷新", command=self.refresh_ports).grid(
            row=0, column=2, padx=4
        )

        ttk.Label(connection, text="波特率").grid(row=0, column=3, padx=(12, 4))
        self.baud_box = ttk.Combobox(
            connection,
            textvariable=self.baud_rate,
            values=("31250", "7812", "115200"),
            width=9,
        )
        self.baud_box.grid(row=0, column=4, padx=4)

        self.connect_button = ttk.Button(
            connection, text="连接", command=self.toggle_connection
        )
        self.connect_button.grid(row=0, column=5, padx=(12, 4))

        controls = ttk.LabelFrame(self.root, text="MIDI参数", padding=10)
        controls.grid(row=1, column=0, padx=10, pady=4, sticky="ew")

        ttk.Label(controls, text="演奏通道固定为1").grid(
            row=0, column=0, columnspan=2, padx=4
        )

        ttk.Label(controls, text="力度").grid(row=0, column=2, padx=(14, 4))
        tk.Scale(
            controls,
            from_=1,
            to=127,
            orient=tk.HORIZONTAL,
            variable=self.velocity,
            length=220,
        ).grid(row=0, column=3, padx=4)

        ttk.Button(controls, text="全部停止", command=self.all_notes_off).grid(
            row=0, column=4, padx=(14, 4)
        )

        ttk.Label(controls, text="控制通道固定为16；OSC A/B参数独立").grid(
            row=1, column=0, columnspan=5, padx=4, pady=(8, 0), sticky="w"
        )

        parameter_controls = ttk.LabelFrame(
            self.root, text="双振荡器参数（松开滑块时发送）", padding=10
        )
        parameter_controls.grid(row=2, column=0, padx=10, pady=4, sticky="ew")

        ttk.Label(parameter_controls, text="全局Pan").grid(
            row=0, column=0, padx=4, sticky="w"
        )
        pan_scale = tk.Scale(
            parameter_controls,
            from_=0,
            to=127,
            orient=tk.HORIZONTAL,
            variable=self.pan,
            length=300,
        )
        pan_scale.grid(row=0, column=1, columnspan=2, padx=4, sticky="w")
        pan_scale.bind(
            "<ButtonRelease-1>",
            lambda _event: self.send_synth_control(PAN_CC, self.pan.get()),
        )

        filter_frame = ttk.LabelFrame(
            parameter_controls, text="全局滤波器", padding=6
        )
        filter_frame.grid(
            row=1, column=0, columnspan=2, padx=6, pady=(6, 0), sticky="ew"
        )

        ttk.Label(filter_frame, text="模式").grid(row=0, column=0, padx=4)
        filter_mode_box = ttk.Combobox(
            filter_frame,
            textvariable=self.filter_mode,
            values=tuple(FILTER_MODE_VALUES.keys()),
            width=10,
            state="readonly",
        )
        filter_mode_box.grid(row=0, column=1, padx=4)
        filter_mode_box.bind(
            "<<ComboboxSelected>>",
            lambda _event: self.send_filter_mode_selection(),
        )

        ttk.Label(filter_frame, text="Cutoff").grid(row=0, column=2, padx=(12, 4))
        cutoff_scale = tk.Scale(
            filter_frame,
            from_=0,
            to=127,
            orient=tk.HORIZONTAL,
            variable=self.filter_cutoff,
            length=210,
        )
        cutoff_scale.grid(row=0, column=3, padx=4)
        cutoff_scale.bind(
            "<ButtonRelease-1>",
            lambda _event: self.send_filter_cutoff(),
        )

        ttk.Label(filter_frame, text="Resonance").grid(
            row=0, column=4, padx=(12, 4)
        )
        resonance_scale = tk.Scale(
            filter_frame,
            from_=0,
            to=127,
            orient=tk.HORIZONTAL,
            variable=self.filter_resonance,
            length=210,
        )
        resonance_scale.grid(row=0, column=5, padx=4)
        resonance_scale.bind(
            "<ButtonRelease-1>",
            lambda _event: self.send_synth_control(
                FILTER_RESONANCE_CC, self.filter_resonance.get()
            ),
        )

        ttk.Label(filter_frame, text="Mix").grid(row=1, column=2, padx=(12, 4))
        mix_scale = tk.Scale(
            filter_frame,
            from_=0,
            to=127,
            orient=tk.HORIZONTAL,
            variable=self.filter_mix,
            length=210,
        )
        mix_scale.grid(row=1, column=3, padx=4)
        mix_scale.bind(
            "<ButtonRelease-1>",
            lambda _event: self.send_synth_control(
                FILTER_MIX_CC, self.filter_mix.get()
            ),
        )

        ttk.Label(filter_frame, text="Master Level").grid(
            row=1, column=4, padx=(12, 4)
        )
        master_scale = tk.Scale(
            filter_frame,
            from_=0,
            to=127,
            orient=tk.HORIZONTAL,
            variable=self.master_level,
            length=210,
        )
        master_scale.grid(row=1, column=5, padx=4)
        master_scale.bind(
            "<ButtonRelease-1>",
            lambda _event: self.send_synth_control(
                MASTER_LEVEL_CC, self.master_level.get()
            ),
        )

        lfo_frame = ttk.LabelFrame(
            parameter_controls, text="FPGA通用LFO与调制路由", padding=6
        )
        lfo_frame.grid(
            row=2, column=0, columnspan=2, padx=6, pady=(6, 0), sticky="ew"
        )

        ttk.Checkbutton(
            lfo_frame,
            text="开启LFO",
            variable=self.filter_lfo_enabled,
            command=self.send_filter_lfo_configuration,
        ).grid(row=0, column=0, padx=4, sticky="w")

        ttk.Label(lfo_frame, text="速率/Hz").grid(
            row=0, column=1, padx=4, sticky="e"
        )
        lfo_rate_scale = tk.Scale(
            lfo_frame,
            from_=0.1,
            to=10.0,
            resolution=0.1,
            orient=tk.HORIZONTAL,
            variable=self.filter_lfo_rate,
            length=210,
        )
        lfo_rate_scale.grid(row=0, column=2, padx=4)
        lfo_rate_scale.bind(
            "<ButtonRelease-1>",
            lambda _event: self.send_filter_lfo_configuration(),
        )

        ttk.Button(
            lfo_frame,
            text="编辑LFO曲线",
            command=self.open_filter_lfo_editor,
        ).grid(row=0, column=3, padx=4)
        ttk.Button(
            lfo_frame,
            text="应用LFO与路由",
            command=self.send_filter_lfo_configuration,
        ).grid(row=0, column=4, padx=4)

        for route_index, route in enumerate(self.lfo_routes):
            route_row = 1 + (route_index % 4)
            route_column = 0 if route_index < 4 else 3
            ttk.Checkbutton(
                lfo_frame,
                text=f"路由{route_index + 1}",
                variable=route["enabled"],
            ).grid(row=route_row, column=route_column, padx=4, sticky="w")
            ttk.Combobox(
                lfo_frame,
                textvariable=route["destination"],
                values=tuple(LFO_DESTINATIONS),
                width=20,
                state="readonly",
            ).grid(row=route_row, column=route_column + 1, padx=4)
            tk.Spinbox(
                lfo_frame,
                from_=-127,
                to=127,
                textvariable=route["depth"],
                width=6,
            ).grid(row=route_row, column=route_column + 2, padx=4)

        for column, osc_name in enumerate(("A", "B")):
            osc_frame = ttk.LabelFrame(
                parameter_controls, text=f"OSC {osc_name}", padding=8
            )
            osc_frame.grid(row=3, column=column, padx=6, pady=(6, 0))
            self._build_oscillator_controls(osc_frame, osc_name)

        keyboard = ttk.LabelFrame(
            self.root,
            text="虚拟键盘（鼠标按住发声；电脑键盘 A W S E D F T G Y H U J K）",
            padding=10,
        )
        keyboard.grid(row=3, column=0, padx=10, pady=8)

        for column, note in enumerate(range(48, 73)):
            label = f"{note_name(note)}\n{note}"
            button = tk.Button(
                keyboard,
                text=label,
                width=4,
                height=3,
                bg="#303030" if "#" in note_name(note) else "white",
                fg="white" if "#" in note_name(note) else "black",
                activebackground="#70a5ff",
            )
            button.grid(row=0, column=column, padx=1)
            button.bind("<ButtonPress-1>", lambda _event, n=note: self.note_on(n))
            button.bind("<ButtonRelease-1>", lambda _event, n=note: self.note_off(n))

        bottom = ttk.Frame(self.root, padding=(10, 0, 10, 10))
        bottom.grid(row=4, column=0, sticky="ew")
        ttk.Label(bottom, textvariable=self.status).pack(side=tk.LEFT)
        self.log = tk.Text(bottom, width=54, height=5, state=tk.DISABLED)
        self.log.pack(side=tk.RIGHT)

    def _build_oscillator_controls(
        self, parent: ttk.LabelFrame, osc_name: str
    ) -> None:
        controls = self.osc_controls[osc_name]
        cc_map = OSC_A_CC if osc_name == "A" else OSC_B_CC

        ttk.Label(parent, text="波形").grid(row=0, column=0, padx=4, sticky="w")
        waveform_box = ttk.Combobox(
            parent,
            textvariable=controls["waveform"],
            values=tuple(WAVEFORM_VALUES),
            width=9,
            state="readonly",
        )
        waveform_box.grid(row=0, column=1, padx=4, sticky="w")
        waveform_box.bind(
            "<<ComboboxSelected>>",
            lambda _event, name=osc_name: self.send_waveform_selection(name),
        )
        ttk.Checkbutton(
            parent,
            text="开启",
            variable=controls["enabled"],
            command=lambda name=osc_name: self.send_oscillator_enable(name),
        ).grid(row=0, column=2, padx=(8, 4), sticky="w")

        ttk.Label(parent, text="Warp模式").grid(
            row=1, column=0, padx=4, sticky="w"
        )
        warp_mode_box = ttk.Combobox(
            parent,
            textvariable=controls["warp_mode"],
            values=tuple(WARP_MODE_VALUES),
            width=9,
            state="readonly",
        )
        warp_mode_box.grid(row=1, column=1, padx=4, sticky="w")
        warp_mode_box.bind(
            "<<ComboboxSelected>>",
            lambda _event, name=osc_name: self.send_warp_mode_selection(name),
        )

        parameter_specs = (
            ("Warp Amount", "warp_amount", 0, 127),
            ("WT Position", "wt_position", 0, 127),
            ("Detune", "detune", 0, 127),
            ("Unison", "unison", 1, 8),
            ("Level", "level", 0, 127),
            ("Attack", "attack", 0, 127),
            ("Decay", "decay", 0, 127),
            ("Sustain", "sustain", 0, 127),
            ("Release", "release", 0, 127),
        )
        for row, (label, key, minimum, maximum) in enumerate(
            parameter_specs, start=2
        ):
            variable = controls[key]
            controller = cc_map[key]
            ttk.Label(parent, text=label).grid(
                row=row, column=0, padx=4, sticky="w"
            )
            scale = tk.Scale(
                parent,
                from_=minimum,
                to=maximum,
                orient=tk.HORIZONTAL,
                variable=variable,
                length=260,
            )
            scale.grid(row=row, column=1, padx=4)
            scale.bind(
                "<ButtonRelease-1>",
                lambda _event, cc=controller, var=variable: (
                    self.send_synth_control(cc, var.get())
                ),
            )

    def refresh_ports(self) -> None:
        if list_ports is None:
            self.status.set("缺少 pyserial：请运行 pip install pyserial")
            self.port_box["values"] = ()
            return

        entries = []
        self.port_lookup.clear()
        for item in list_ports.comports():
            channel = ""
            serial_number = item.serial_number or ""
            if item.vid == 0x0403 and item.pid == 0x6010:
                if serial_number.endswith("B"):
                    channel = " - FTDI B / UART推荐"
                elif serial_number.endswith("A"):
                    channel = " - FTDI A / JTAG"
            label = f"{item.device} - {item.description}{channel}"
            self.port_lookup[label] = item.device
            entries.append((0 if "UART推荐" in label else 1, label))

        labels = [label for _priority, label in sorted(entries)]
        self.port_box["values"] = labels
        if labels and self.port_name.get() not in labels:
            self.port_name.set(labels[0])
        elif not labels:
            self.port_name.set("")
            self.status.set("未发现COM端口")

    def toggle_connection(self) -> None:
        if self.port is not None:
            self.disconnect()
            return

        if serial is None:
            messagebox.showerror("缺少依赖", "请先运行：pip install pyserial")
            return

        selected_label = self.port_name.get()
        if not selected_label:
            messagebox.showwarning("没有端口", "请连接开发板并刷新端口列表。")
            return

        try:
            baud = int(self.baud_rate.get())
            device = self.port_lookup.get(selected_label, selected_label)
            self.port = serial.Serial(
                port=device,
                baudrate=baud,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=0,
                write_timeout=1,
            )
        except (ValueError, serial.SerialException) as exc:
            self.port = None
            messagebox.showerror("连接失败", str(exc))
            return

        self.connect_button.configure(text="断开")
        self.status.set(f"已连接 {device} @ {baud} baud")
        self._append_log(f"连接 {device} @ {baud}")
        self.send_all_synth_controls()

    def disconnect(self) -> None:
        if self.port is None:
            return
        self.all_notes_off()
        port_to_close = self.port
        self.port = None
        if port_to_close is not None:
            port_to_close.close()
        self.connect_button.configure(text="连接")
        self.status.set("未连接")

    def _send(self, message: bytes, log_message: bool = True) -> bool:
        if self.port is None or not self.port.is_open:
            self.status.set("请先连接串口")
            return False
        try:
            self.port.write(message)
        except serial.SerialException as exc:
            failed_port = self.port
            self.port = None
            if failed_port is not None:
                failed_port.close()
            self.active_notes.clear()
            self.keyboard_notes.clear()
            self.connect_button.configure(text="连接")
            self.status.set("串口连接已断开")
            messagebox.showerror("发送失败", str(exc))
            return False
        if log_message:
            self._append_log("TX " + " ".join(f"{value:02X}" for value in message))
        return True

    def note_on(self, note: int) -> None:
        if note in self.active_notes:
            return
        channel = max(1, min(16, self.channel.get())) - 1
        velocity = max(1, min(127, self.velocity.get()))
        if self._send(bytes((0x90 | channel, note, velocity))):
            self.active_notes.add(note)
            self.status.set(f"Note On  {note_name(note)} ({note})")

    def note_off(self, note: int) -> None:
        if note not in self.active_notes:
            return
        channel = max(1, min(16, self.channel.get())) - 1
        if self._send(bytes((0x80 | channel, note, 0))):
            self.active_notes.discard(note)
            self.status.set(f"Note Off {note_name(note)} ({note})")

    def send_control_change(
        self,
        controller: int,
        value: int,
        channel_number: int | None = None,
        log_message: bool = True,
    ) -> bool:
        if channel_number is None:
            channel_number = self.channel.get()
        channel = max(1, min(16, channel_number)) - 1
        controller = max(0, min(127, controller))
        value = max(0, min(127, value))
        return self._send(
            bytes((0xB0 | channel, controller, value)),
            log_message=log_message,
        )

    def send_highres_parameter(
        self,
        parameter_id: int,
        value: int,
        log_message: bool = True,
    ) -> bool:
        """发送F0 7D id value_msb value_lsb F7格式的14位参数。"""
        parameter_id = max(0, min(127, int(parameter_id)))
        value = max(0, min(0x3FFF, int(value)))
        message = bytes(
            (
                0xF0,
                0x7D,
                parameter_id,
                (value >> 7) & 0x7F,
                value & 0x7F,
                0xF7,
            )
        )
        return self._send(message, log_message=log_message)

    def send_waveform_selection(self, osc_name: str) -> None:
        controls = self.osc_controls[osc_name]
        cc_map = OSC_A_CC if osc_name == "A" else OSC_B_CC
        waveform_name = controls["waveform"].get()
        value = WAVEFORM_VALUES.get(waveform_name, WAVEFORM_VALUES["方波"])
        if self.send_control_change(cc_map["waveform"], value, CONTROL_CHANNEL):
            self.status.set(f"OSC {osc_name}波形：{waveform_name}")

    def send_warp_mode_selection(self, osc_name: str) -> None:
        controls = self.osc_controls[osc_name]
        cc_map = OSC_A_CC if osc_name == "A" else OSC_B_CC
        mode_name = controls["warp_mode"].get()
        value = WARP_MODE_VALUES.get(mode_name, WARP_MODE_VALUES["关闭"])
        if self.send_control_change(cc_map["warp_mode"], value, CONTROL_CHANNEL):
            self.status.set(f"OSC {osc_name} Warp模式：{mode_name}")

    def send_oscillator_enable(self, osc_name: str) -> None:
        controls = self.osc_controls[osc_name]
        cc_map = OSC_A_CC if osc_name == "A" else OSC_B_CC
        enabled = bool(controls["enabled"].get())
        value = 127 if enabled else 0
        if self.send_control_change(cc_map["enable"], value, CONTROL_CHANNEL):
            state = "开启" if enabled else "关闭"
            self.status.set(f"OSC {osc_name}：{state}")

    def send_synth_control(self, controller: int, value: int) -> None:
        if self.send_control_change(controller, value, CONTROL_CHANNEL):
            self.status.set(f"控制通道16：CC{controller} = {value}")

    def send_filter_mode_selection(self) -> None:
        mode_name = self.filter_mode.get()
        value = FILTER_MODE_VALUES.get(mode_name, FILTER_MODE_VALUES["旁路"])
        if self.send_control_change(FILTER_MODE_CC, value, CONTROL_CHANNEL):
            self.status.set(f"全局滤波器模式：{mode_name}")

    def send_filter_cutoff(self) -> None:
        base_value = max(0, min(127, int(self.filter_cutoff.get())))
        self.send_synth_control(FILTER_CUTOFF_CC, base_value)

    def _filter_lfo_curve_changed(self) -> None:
        # 拖动节点会高频触发回调。等待75 ms后一次性发送完整配置，
        # 避免31250 bit/s串口积压。
        if self.filter_lfo_config_after_id is not None:
            self.root.after_cancel(self.filter_lfo_config_after_id)
        self.filter_lfo_config_after_id = self.root.after(
            FILTER_LFO_CONFIG_DEBOUNCE_MS,
            self.send_filter_lfo_configuration,
        )

    @staticmethod
    def _encode_bipolar_q13(value: float) -> int:
        value = max(-1.0, min(1.0, float(value)))
        return max(0, min(0x3FFF, round((value + 1.0) * 8191.5)))

    @staticmethod
    def _encode_route_depth(value: int) -> int:
        """把-127～+127转换为14位Offset Binary调制深度。"""
        value = max(-127, min(127, int(value)))
        return max(0, min(0x3FFF, round((value + 127) * 16383 / 254)))

    def send_filter_lfo_configuration(self) -> None:
        """发送曲线和8条路由，最后用commit在FPGA中同时生效。"""
        self.filter_lfo_config_after_id = None
        if self.port is None or not self.port.is_open:
            return

        points = self.filter_lfo_curve.points
        middle_time = max(0.125, min(0.875, float(points[1].time)))
        rate_hz = max(0.1, min(10.0, float(self.filter_lfo_rate.get())))
        phase_scale = float(1 << FILTER_LFO_PHASE_BITS)
        step_0 = round(
            rate_hz * phase_scale / (FILTER_LFO_SAMPLE_RATE * middle_time)
        )
        step_1 = round(
            rate_hz * phase_scale
            / (FILTER_LFO_SAMPLE_RATE * (1.0 - middle_time))
        )

        values = (
            (FILTER_LFO_PARAMETER["enable"], 1 if self.filter_lfo_enabled.get() else 0),
            (FILTER_LFO_PARAMETER["step_0"], max(1, min(0x3FFF, step_0))),
            (FILTER_LFO_PARAMETER["step_1"], max(1, min(0x3FFF, step_1))),
            (FILTER_LFO_PARAMETER["point_0"], self._encode_bipolar_q13(points[0].level)),
            (FILTER_LFO_PARAMETER["point_1"], self._encode_bipolar_q13(points[1].level)),
            (FILTER_LFO_PARAMETER["point_2"], self._encode_bipolar_q13(points[2].level)),
            (FILTER_LFO_PARAMETER["curve_0"], self._encode_bipolar_q13(points[0].curve)),
            (FILTER_LFO_PARAMETER["curve_1"], self._encode_bipolar_q13(points[1].curve)),
        )

        for parameter_id, value in values:
            if not self.send_highres_parameter(parameter_id, value, log_message=False):
                return

        enabled_route_count = 0
        for route_index, route in enumerate(self.lfo_routes):
            destination_name = route["destination"].get()
            destination = LFO_DESTINATIONS.get(destination_name, 0)
            enabled = bool(route["enabled"].get()) and destination != 0
            if enabled:
                enabled_route_count += 1
            route_values = (
                (FILTER_LFO_PARAMETER["route_index"], route_index),
                (FILTER_LFO_PARAMETER["route_enable"], 1 if enabled else 0),
                (FILTER_LFO_PARAMETER["route_destination"], destination),
                (
                    FILTER_LFO_PARAMETER["route_depth"],
                    self._encode_route_depth(route["depth"].get()),
                ),
            )
            for parameter_id, value in route_values:
                if not self.send_highres_parameter(
                    parameter_id, value, log_message=False
                ):
                    return

        if not self.send_highres_parameter(
            FILTER_LFO_PARAMETER["commit"], 1, log_message=False
        ):
            return

        state = "开启" if self.filter_lfo_enabled.get() else "关闭"
        self.status.set(
            f"FPGA通用LFO已{state}：{rate_hz:.1f} Hz，"
            f"启用{enabled_route_count}条路由"
        )

    def open_filter_lfo_editor(self) -> None:
        if self.filter_lfo_window is not None:
            self.filter_lfo_window.lift()
            self.filter_lfo_window.focus_force()
            return

        window = tk.Toplevel(self.root)
        window.title("通用LFO曲线编辑器")
        window.resizable(False, False)
        editor = LfoCurveEditor(
            window,
            self.filter_lfo_curve,
            on_change=self._filter_lfo_curve_changed,
        )
        editor.pack(padx=10, pady=10)
        self.filter_lfo_window = window

        def close_editor() -> None:
            window.destroy()
            self.filter_lfo_window = None

        window.protocol("WM_DELETE_WINDOW", close_editor)

    def send_all_synth_controls(self) -> None:
        self.send_synth_control(PAN_CC, self.pan.get())
        self.send_filter_mode_selection()
        self.send_synth_control(FILTER_CUTOFF_CC, self.filter_cutoff.get())
        self.send_synth_control(
            FILTER_RESONANCE_CC, self.filter_resonance.get()
        )
        self.send_synth_control(FILTER_MIX_CC, self.filter_mix.get())
        self.send_synth_control(MASTER_LEVEL_CC, self.master_level.get())
        self.send_filter_lfo_configuration()
        for osc_name, cc_map in (("A", OSC_A_CC), ("B", OSC_B_CC)):
            controls = self.osc_controls[osc_name]
            self.send_oscillator_enable(osc_name)
            self.send_waveform_selection(osc_name)
            self.send_warp_mode_selection(osc_name)
            for key in (
                "warp_amount",
                "wt_position",
                "detune",
                "unison",
                "level",
                "attack",
                "decay",
                "sustain",
                "release",
            ):
                self.send_synth_control(cc_map[key], controls[key].get())

    def all_notes_off(self) -> None:
        if self.port is None:
            self.active_notes.clear()
            self.keyboard_notes.clear()
            return
        for note in sorted(self.active_notes):
            self.note_off(note)
        channel = max(1, min(16, self.channel.get())) - 1
        self._send(bytes((0xB0 | channel, 123, 0)))
        self.keyboard_notes.clear()
        self.status.set("全部音符已停止")

    def _key_press(self, event: tk.Event) -> None:
        key = event.keysym.lower()
        note = KEY_TO_NOTE.get(key)
        if note is not None and note not in self.keyboard_notes:
            self.keyboard_notes.add(note)
            self.note_on(note)

    def _key_release(self, event: tk.Event) -> None:
        key = event.keysym.lower()
        note = KEY_TO_NOTE.get(key)
        if note is not None and note in self.keyboard_notes:
            self.keyboard_notes.discard(note)
            self.note_off(note)

    def _append_log(self, text: str) -> None:
        self.log.configure(state=tk.NORMAL)
        self.log.insert(tk.END, text + "\n")
        self.log.see(tk.END)
        self.log.configure(state=tk.DISABLED)

    def close(self) -> None:
        if self.filter_lfo_config_after_id is not None:
            self.root.after_cancel(self.filter_lfo_config_after_id)
            self.filter_lfo_config_after_id = None
        self.disconnect()
        self.root.destroy()


def main() -> None:
    root = tk.Tk()
    MidiUartSender(root)
    root.mainloop()


if __name__ == "__main__":
    main()
