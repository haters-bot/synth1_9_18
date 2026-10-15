#!/usr/bin/env python3
"""通过串口发送MIDI演奏消息和双振荡器控制消息的桌面测试工具。"""

from __future__ import annotations

import tkinter as tk
from tkinter import messagebox, ttk

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

        self.port_name = tk.StringVar()
        self.baud_rate = tk.StringVar(value="31250")
        self.channel = tk.IntVar(value=1)
        self.velocity = tk.IntVar(value=100)
        self.pan = tk.IntVar(value=64)
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

        for column, osc_name in enumerate(("A", "B")):
            osc_frame = ttk.LabelFrame(
                parameter_controls, text=f"OSC {osc_name}", padding=8
            )
            osc_frame.grid(row=1, column=column, padx=6, pady=(6, 0))
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

    def _send(self, message: bytes) -> bool:
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
        self, controller: int, value: int, channel_number: int | None = None
    ) -> bool:
        if channel_number is None:
            channel_number = self.channel.get()
        channel = max(1, min(16, channel_number)) - 1
        controller = max(0, min(127, controller))
        value = max(0, min(127, value))
        return self._send(bytes((0xB0 | channel, controller, value)))

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

    def send_all_synth_controls(self) -> None:
        self.send_synth_control(PAN_CC, self.pan.get())
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
        self.disconnect()
        self.root.destroy()


def main() -> None:
    root = tk.Tk()
    MidiUartSender(root)
    root.mainloop()


if __name__ == "__main__":
    main()
