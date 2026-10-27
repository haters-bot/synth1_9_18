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
EFFECT_MODE_CC = 51
DELAY_TIME_CC = 52
DELAY_FEEDBACK_CC = 53
DELAY_MIX_CC = 54
REVERB_SIZE_CC = 55
REVERB_DECAY_CC = 56
REVERB_MIX_CC = 57
DISTORTION_ENABLE_CC = 58
DISTORTION_TYPE_CC = 59
DISTORTION_DRIVE_CC = 60
DISTORTION_TONE_CC = 61
DISTORTION_MIX_CC = 62
CHORUS_ENABLE_CC = 63
CHORUS_RATE_CC = 64
CHORUS_DEPTH_CC = 65
CHORUS_DELAY_CC = 66
CHORUS_FEEDBACK_CC = 67
CHORUS_MIX_CC = 68
PHASER_ENABLE_CC = 69
PHASER_RATE_CC = 70
PHASER_DEPTH_CC = 71
PHASER_CENTER_CC = 72
PHASER_FEEDBACK_CC = 73
PHASER_MIX_CC = 74
COMPRESSOR_ENABLE_CC = 75
COMPRESSOR_THRESHOLD_CC = 76
COMPRESSOR_RATIO_CC = 77
COMPRESSOR_ATTACK_CC = 78
COMPRESSOR_RELEASE_CC = 79
COMPRESSOR_MAKEUP_CC = 80
COMPRESSOR_MIX_CC = 81
VIBRATO_ENABLE_CC = 82
VIBRATO_RATE_CC = 83
VIBRATO_DEPTH_CC = 84
PORTAMENTO_ENABLE_CC = 85
PORTAMENTO_TIME_CC = 86
# 三个独立三点LFO共享同一个8槽调制矩阵和一次原子提交。
FILTER_LFO_PARAMETER_SETS = (
    {
        "enable": 16, "step_0": 17, "step_1": 18,
        "point_0": 20, "point_1": 21, "point_2": 22,
        "curve_0": 23, "curve_1": 24,
    },
    {
        "enable": 31, "step_0": 32, "step_1": 33,
        "point_0": 34, "point_1": 35, "point_2": 36,
        "curve_0": 37, "curve_1": 38,
    },
    {
        "enable": 39, "step_0": 40, "step_1": 41,
        "point_0": 42, "point_1": 43, "point_2": 44,
        "curve_0": 45, "curve_1": 46,
    },
)
FILTER_LFO_PARAMETER = {
    "commit": 25,
    "route_index": 26,
    "route_enable": 27,
    "route_destination": 28,
    "route_depth": 29,
    "route_source": 30,
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
    "OSC A Detune": 11,
    "OSC B Detune": 12,
    "Master Level": 13,
    "Distortion Drive": 14,
    "Distortion Mix": 15,
    "Chorus Depth": 16,
    "Chorus Mix": 17,
    "Phaser Depth": 18,
    "Phaser Mix": 19,
    "Reverb Mix": 20,
    "Delay Mix": 21,

}
LFO_SOURCES = {"LFO 1": 0, "LFO 2": 1, "LFO 3": 2}
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
    "wavetable_index": 49,
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
    "wavetable_index": 50,
}
WAVEFORM_VALUES = {
    "正弦波": 0,
    "三角波": 32,
    "方波": 64,
    "锯齿波": 96,
    "SD/DDR波表": 127,
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
EFFECT_MODE_VALUES = {
    "旁路": 0,
    "Delay": 1,
    "Reverb": 2,
    "Delay + Reverb": 3,
}
DISTORTION_TYPE_VALUES = {
    "Soft Clip": 0,
    "Hard Clip": 1,
    "Foldback": 2,
}

# 音色预设只组合现有协议参数，不引入新的FPGA控制命令。
# 钢琴和提琴分别使用测试波表包中的8号、9号波表。
SYNTH_PRESETS = {
    "合成钢琴（波表8）": {
        "controls": {
            "pan": 64,
            "filter_mode": "低通",
            "filter_cutoff": 105,
            "filter_resonance": 8,
            "filter_mix": 127,
            "master_level": 105,
            "effect_mode": "Reverb",
            "delay_time": 64,
            "delay_feedback": 32,
            "delay_mix": 0,
            "reverb_size": 55,
            "reverb_decay": 60,
            "reverb_mix": 22,
            "distortion_enabled": False,
            "distortion_type": "Soft Clip",
            "distortion_drive": 24,
            "distortion_tone": 127,
            "distortion_mix": 0,
            "chorus_enabled": False,
            "chorus_rate": 12,
            "chorus_depth": 20,
            "chorus_delay": 40,
            "chorus_feedback": 8,
            "chorus_mix": 0,
            "phaser_enabled": False,
            "phaser_rate": 20,
            "phaser_depth": 32,
            "phaser_center": 64,
            "phaser_feedback": 8,
            "phaser_mix": 0,
            "compressor_enabled": False,
            "compressor_threshold": 96,
            "compressor_ratio": 48,
            "compressor_attack": 12,
            "compressor_release": 64,
            "compressor_makeup": 0,
            "compressor_mix": 127,
        },
        "oscillators": {
            "A": {
                "enabled": True,
                "waveform": "SD/DDR波表",
                "warp_mode": "关闭",
                "warp_amount": 0,
                "wavetable_index": 8,
                "wt_position": 112,
                "detune": 64,
                "unison": 1,
                "level": 105,
                "attack": 0,
                "decay": 92,
                "sustain": 0,
                "release": 48,
            },
            "B": {
                "enabled": True,
                "waveform": "SD/DDR波表",
                "warp_mode": "关闭",
                "warp_amount": 0,
                "wavetable_index": 8,
                "wt_position": 0,
                "detune": 64,
                "unison": 1,
                "level": 28,
                "attack": 0,
                "decay": 36,
                "sustain": 0,
                "release": 24,
            },
        },
    },
    "合成提琴（波表9）": {
        "controls": {
            "pan": 64,
            "filter_mode": "低通",
            "filter_cutoff": 88,
            "filter_resonance": 14,
            "filter_mix": 120,
            "master_level": 100,
            "effect_mode": "Reverb",
            "delay_time": 64,
            "delay_feedback": 32,
            "delay_mix": 0,
            "reverb_size": 65,
            "reverb_decay": 75,
            "reverb_mix": 30,
            "distortion_enabled": False,
            "distortion_type": "Soft Clip",
            "distortion_drive": 24,
            "distortion_tone": 127,
            "distortion_mix": 0,
            "chorus_enabled": True,
            "chorus_rate": 12,
            "chorus_depth": 24,
            "chorus_delay": 40,
            "chorus_feedback": 10,
            "chorus_mix": 26,
            "phaser_enabled": False,
            "phaser_rate": 20,
            "phaser_depth": 32,
            "phaser_center": 64,
            "phaser_feedback": 8,
            "phaser_mix": 0,
            "compressor_enabled": False,
            "compressor_threshold": 96,
            "compressor_ratio": 48,
            "compressor_attack": 20,
            "compressor_release": 80,
            "compressor_makeup": 0,
            "compressor_mix": 127,
        },
        "oscillators": {
            "A": {
                "enabled": True,
                "waveform": "SD/DDR波表",
                "warp_mode": "关闭",
                "warp_amount": 0,
                "wavetable_index": 9,
                "wt_position": 78,
                "detune": 24,
                "unison": 2,
                "level": 95,
                "attack": 56,
                "decay": 40,
                "sustain": 112,
                "release": 72,
            },
            "B": {
                "enabled": True,
                "waveform": "SD/DDR波表",
                "warp_mode": "关闭",
                "warp_amount": 0,
                "wavetable_index": 9,
                "wt_position": 42,
                "detune": 18,
                "unison": 1,
                "level": 42,
                "attack": 60,
                "decay": 48,
                "sustain": 105,
                "release": 72,
            },
        },
    },
}


def note_name(note: int) -> str:
    return f"{NOTE_NAMES[note % 12]}{note // 12 - 1}"


class MidiUartSender:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("FPGA MIDI UART 测试器")
        self.root.resizable(True, True)
        screen_width = self.root.winfo_screenwidth()
        screen_height = self.root.winfo_screenheight()
        window_width = max(640, min(1280, screen_width - 80))
        window_height = max(480, min(860, screen_height - 120))
        self.root.geometry(f"{window_width}x{window_height}")
        self.root.minsize(640, 480)

        self.port = None
        self.port_lookup: dict[str, str] = {}
        self.active_notes: set[int] = set()
        self.keyboard_notes: set[int] = set()
        self.filter_lfo_curves = [LfoCurve() for _ in range(3)]
        self.filter_lfo_windows: list[tk.Toplevel | None] = [None, None, None]
        self.filter_lfo_config_after_id: str | None = None

        self.port_name = tk.StringVar()
        self.baud_rate = tk.StringVar(value="31250")
        self.channel = tk.IntVar(value=1)
        self.velocity = tk.IntVar(value=100)
        self.preset_name = tk.StringVar(value="选择音色…")
        self.pan = tk.IntVar(value=64)
        self.filter_mode = tk.StringVar(value="旁路")
        self.filter_cutoff = tk.IntVar(value=127)
        self.filter_resonance = tk.IntVar(value=0)
        self.filter_mix = tk.IntVar(value=127)
        self.master_level = tk.IntVar(value=127)
        self.effect_mode = tk.StringVar(value="旁路")
        self.delay_time = tk.IntVar(value=64)
        self.delay_feedback = tk.IntVar(value=48)
        self.delay_mix = tk.IntVar(value=64)
        self.reverb_size = tk.IntVar(value=64)
        self.reverb_decay = tk.IntVar(value=72)
        self.reverb_mix = tk.IntVar(value=48)
        self.distortion_enabled = tk.BooleanVar(value=False)
        self.distortion_type = tk.StringVar(value="Soft Clip")
        self.distortion_drive = tk.IntVar(value=32)
        self.distortion_tone = tk.IntVar(value=127)
        self.distortion_mix = tk.IntVar(value=64)
        self.chorus_enabled = tk.BooleanVar(value=False)
        self.chorus_rate = tk.IntVar(value=20)
        self.chorus_depth = tk.IntVar(value=32)
        self.chorus_delay = tk.IntVar(value=48)
        self.chorus_feedback = tk.IntVar(value=20)
        self.chorus_mix = tk.IntVar(value=64)
        self.phaser_enabled = tk.BooleanVar(value=False)
        self.phaser_rate = tk.IntVar(value=20)
        self.phaser_depth = tk.IntVar(value=48)
        self.phaser_center = tk.IntVar(value=64)
        self.phaser_feedback = tk.IntVar(value=20)
        self.phaser_mix = tk.IntVar(value=64)
        self.compressor_enabled = tk.BooleanVar(value=False)
        self.compressor_threshold = tk.IntVar(value=96)
        self.compressor_ratio = tk.IntVar(value=64)
        self.compressor_attack = tk.IntVar(value=20)
        self.compressor_release = tk.IntVar(value=80)
        self.compressor_makeup = tk.IntVar(value=0)
        self.compressor_mix = tk.IntVar(value=127)
        self.vibrato_enabled = tk.BooleanVar(value=False)
        self.vibrato_rate = tk.IntVar(value=52)
        self.vibrato_depth = tk.IntVar(value=0)
        self.portamento_enabled = tk.BooleanVar(value=False)
        self.portamento_time = tk.IntVar(value=80)
        self.filter_lfo_enabled = [
            tk.BooleanVar(value=False) for _ in range(3)
        ]
        self.filter_lfo_rate = [
            tk.DoubleVar(value=0.5) for _ in range(3)
        ]
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
                    "source": tk.StringVar(value="LFO 1"),
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
                "wavetable_index": tk.IntVar(value=0),
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
        self.root.rowconfigure(0, weight=1)
        self.root.columnconfigure(0, weight=1)
        viewport = ttk.Frame(self.root)
        viewport.grid(row=0, column=0, sticky="nsew")
        viewport.rowconfigure(0, weight=1)
        viewport.columnconfigure(0, weight=1)
        self.main_canvas = tk.Canvas(viewport, highlightthickness=0)
        vertical_scrollbar = ttk.Scrollbar(
            viewport, orient=tk.VERTICAL, command=self.main_canvas.yview
        )
        horizontal_scrollbar = ttk.Scrollbar(
            viewport, orient=tk.HORIZONTAL, command=self.main_canvas.xview
        )
        self.main_canvas.configure(
            yscrollcommand=vertical_scrollbar.set,
            xscrollcommand=horizontal_scrollbar.set,
        )
        self.main_canvas.grid(row=0, column=0, sticky="nsew")
        vertical_scrollbar.grid(row=0, column=1, sticky="ns")
        horizontal_scrollbar.grid(row=1, column=0, sticky="ew")
        self.main_content = ttk.Frame(self.main_canvas)
        self.main_content.columnconfigure(0, weight=1)
        self.main_content_window = self.main_canvas.create_window(
            (0, 0), window=self.main_content, anchor="nw"
        )
        self.main_content.bind("<Configure>", self._update_scroll_region)
        self.main_canvas.bind("<Configure>", self._resize_scroll_content)
        self.root.bind_all("<MouseWheel>", self._scroll_main_view, add="+")

        connection = ttk.LabelFrame(self.main_content, text="串口连接", padding=10)
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

        controls = ttk.LabelFrame(self.main_content, text="MIDI参数", padding=10)
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

        ttk.Label(controls, text="音色预设").grid(
            row=2, column=0, padx=4, pady=(8, 0), sticky="e"
        )
        preset_box = ttk.Combobox(
            controls,
            textvariable=self.preset_name,
            values=tuple(SYNTH_PRESETS),
            width=22,
            state="readonly",
        )
        preset_box.grid(
            row=2, column=1, columnspan=2, padx=4, pady=(8, 0), sticky="w"
        )
        preset_box.bind(
            "<<ComboboxSelected>>",
            lambda _event: self.apply_selected_preset(),
        )
        ttk.Button(
            controls, text="重新应用音色", command=self.apply_selected_preset
        ).grid(row=2, column=3, padx=4, pady=(8, 0), sticky="w")

        parameter_controls = ttk.LabelFrame(
            self.main_content, text="双振荡器参数（松开滑块时发送）", padding=10
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

        pitch_frame = ttk.LabelFrame(
            parameter_controls, text="颤音与单音Legato滑音", padding=6
        )
        pitch_frame.grid(
            row=2, column=0, columnspan=2, padx=6, pady=(6, 0), sticky="ew"
        )
        ttk.Checkbutton(
            pitch_frame,
            text="开启Vibrato",
            variable=self.vibrato_enabled,
            command=lambda: self.send_synth_control(
                VIBRATO_ENABLE_CC, 127 if self.vibrato_enabled.get() else 0
            ),
        ).grid(row=0, column=0, padx=4, sticky="w")
        pitch_specs = (
            ("Vibrato Rate", self.vibrato_rate, VIBRATO_RATE_CC),
            ("Vibrato Depth", self.vibrato_depth, VIBRATO_DEPTH_CC),
            ("Glide Time", self.portamento_time, PORTAMENTO_TIME_CC),
        )
        for index, (label, variable, controller) in enumerate(pitch_specs):
            column = 1 + index * 2
            ttk.Label(pitch_frame, text=label).grid(
                row=0, column=column, padx=(8, 2), sticky="e"
            )
            scale = tk.Scale(
                pitch_frame, from_=0, to=127, orient=tk.HORIZONTAL,
                variable=variable, length=145,
            )
            scale.grid(row=0, column=column + 1, padx=2)
            scale.bind(
                "<ButtonRelease-1>",
                lambda _event, cc=controller, var=variable: (
                    self.send_synth_control(cc, var.get())
                ),
            )
        ttk.Checkbutton(
            pitch_frame,
            text="开启单音Legato Portamento",
            variable=self.portamento_enabled,
            command=lambda: self.send_synth_control(
                PORTAMENTO_ENABLE_CC,
                127 if self.portamento_enabled.get() else 0,
            ),
        ).grid(row=1, column=0, columnspan=3, padx=4, sticky="w")

        lfo_frame = ttk.LabelFrame(
            parameter_controls, text="FPGA通用LFO与调制路由", padding=6
        )
        lfo_frame.grid(
            row=3, column=0, columnspan=2, padx=6, pady=(6, 0), sticky="ew"
        )

        for lfo_index in range(3):
            ttk.Checkbutton(
                lfo_frame,
                text=f"开启 LFO {lfo_index + 1}",
                variable=self.filter_lfo_enabled[lfo_index],
                command=self.send_filter_lfo_configuration,
            ).grid(row=lfo_index, column=0, padx=4, sticky="w")
            ttk.Label(lfo_frame, text="速率/Hz").grid(
                row=lfo_index, column=1, padx=4, sticky="e"
            )
            lfo_rate_scale = tk.Scale(
                lfo_frame,
                from_=0.1,
                to=10.0,
                resolution=0.1,
                orient=tk.HORIZONTAL,
                variable=self.filter_lfo_rate[lfo_index],
                length=210,
            )
            lfo_rate_scale.grid(row=lfo_index, column=2, padx=4)
            lfo_rate_scale.bind(
                "<ButtonRelease-1>",
                lambda _event: self.send_filter_lfo_configuration(),
            )
            ttk.Button(
                lfo_frame,
                text=f"编辑 LFO {lfo_index + 1} 曲线",
                command=lambda index=lfo_index: self.open_filter_lfo_editor(index),
            ).grid(row=lfo_index, column=3, padx=4)

        ttk.Button(
            lfo_frame,
            text="应用LFO与路由",
            command=self.send_filter_lfo_configuration,
        ).grid(row=0, column=4, padx=4)

        for route_index, route in enumerate(self.lfo_routes):
            route_row = 3 + route_index
            route_column = 0
            ttk.Checkbutton(
                lfo_frame,
                text=f"路由{route_index + 1}",
                variable=route["enabled"],
            ).grid(row=route_row, column=route_column, padx=4, sticky="w")
            ttk.Combobox(
                lfo_frame,
                textvariable=route["source"],
                values=tuple(LFO_SOURCES),
                width=6,
                state="readonly",
            ).grid(row=route_row, column=route_column + 1, padx=4)
            ttk.Combobox(
                lfo_frame,
                textvariable=route["destination"],
                values=tuple(LFO_DESTINATIONS),
                width=20,
                state="readonly",
            ).grid(row=route_row, column=route_column + 2, padx=4)
            tk.Spinbox(
                lfo_frame,
                from_=-127,
                to=127,
                textvariable=route["depth"],
                width=6,
            ).grid(row=route_row, column=route_column + 3, padx=4)

        effects_frame = ttk.LabelFrame(
            parameter_controls, text="全局效果器", padding=6
        )
        effects_frame.grid(
            row=4, column=0, columnspan=2, padx=6, pady=(6, 0), sticky="ew"
        )
        ttk.Label(effects_frame, text="模式").grid(row=0, column=0, padx=4)
        effect_mode_box = ttk.Combobox(
            effects_frame,
            textvariable=self.effect_mode,
            values=tuple(EFFECT_MODE_VALUES),
            width=16,
            state="readonly",
        )
        effect_mode_box.grid(row=0, column=1, padx=4)
        effect_mode_box.bind(
            "<<ComboboxSelected>>",
            lambda _event: self.send_effect_mode_selection(),
        )

        effect_specs = (
            ("Delay Time", self.delay_time, DELAY_TIME_CC),
            ("Delay Feedback", self.delay_feedback, DELAY_FEEDBACK_CC),
            ("Delay Mix", self.delay_mix, DELAY_MIX_CC),
            ("Reverb Size", self.reverb_size, REVERB_SIZE_CC),
            ("Reverb Decay", self.reverb_decay, REVERB_DECAY_CC),
            ("Reverb Mix", self.reverb_mix, REVERB_MIX_CC),
        )
        for index, (label, variable, controller) in enumerate(effect_specs):
            row = index // 2
            column = 2 + (index % 2) * 2
            ttk.Label(effects_frame, text=label).grid(
                row=row, column=column, padx=(10, 2), sticky="e"
            )
            scale = tk.Scale(
                effects_frame,
                from_=0,
                to=127,
                orient=tk.HORIZONTAL,
                variable=variable,
                length=150,
            )
            scale.grid(row=row, column=column + 1, padx=2)
            scale.bind(
                "<ButtonRelease-1>",
                lambda _event, cc=controller, var=variable: (
                    self.send_synth_control(cc, var.get())
                ),
            )

        advanced_effects_frame = ttk.LabelFrame(
            parameter_controls,
            text="Distortion / Chorus / Phaser / Compressor",
            padding=6,
        )
        advanced_effects_frame.grid(
            row=5, column=0, columnspan=2, padx=6, pady=(6, 0), sticky="ew"
        )
        effect_blocks = (
            (
                "Distortion", self.distortion_enabled, DISTORTION_ENABLE_CC,
                (
                    ("Drive", self.distortion_drive, DISTORTION_DRIVE_CC),
                    ("Tone", self.distortion_tone, DISTORTION_TONE_CC),
                    ("Mix", self.distortion_mix, DISTORTION_MIX_CC),
                ),
            ),
            (
                "Chorus", self.chorus_enabled, CHORUS_ENABLE_CC,
                (
                    ("Rate", self.chorus_rate, CHORUS_RATE_CC),
                    ("Depth", self.chorus_depth, CHORUS_DEPTH_CC),
                    ("Delay", self.chorus_delay, CHORUS_DELAY_CC),
                    ("Feedback", self.chorus_feedback, CHORUS_FEEDBACK_CC),
                    ("Mix", self.chorus_mix, CHORUS_MIX_CC),
                ),
            ),
            (
                "Phaser", self.phaser_enabled, PHASER_ENABLE_CC,
                (
                    ("Rate", self.phaser_rate, PHASER_RATE_CC),
                    ("Depth", self.phaser_depth, PHASER_DEPTH_CC),
                    ("Center", self.phaser_center, PHASER_CENTER_CC),
                    ("Feedback", self.phaser_feedback, PHASER_FEEDBACK_CC),
                    ("Mix", self.phaser_mix, PHASER_MIX_CC),
                ),
            ),
            (
                "Compressor", self.compressor_enabled, COMPRESSOR_ENABLE_CC,
                (
                    ("Threshold", self.compressor_threshold,
                     COMPRESSOR_THRESHOLD_CC),
                    ("Ratio", self.compressor_ratio, COMPRESSOR_RATIO_CC),
                    ("Attack", self.compressor_attack, COMPRESSOR_ATTACK_CC),
                    ("Release", self.compressor_release, COMPRESSOR_RELEASE_CC),
                    ("Makeup", self.compressor_makeup, COMPRESSOR_MAKEUP_CC),
                    ("Mix", self.compressor_mix, COMPRESSOR_MIX_CC),
                ),
            ),
        )
        for block_index, (title, enabled, enable_cc, specs) in enumerate(
            effect_blocks
        ):
            block = ttk.LabelFrame(advanced_effects_frame, text=title, padding=4)
            block.grid(
                row=block_index // 2,
                column=block_index % 2,
                padx=4,
                pady=4,
                sticky="nsew",
            )
            ttk.Checkbutton(
                block,
                text="开启",
                variable=enabled,
                command=lambda var=enabled, cc=enable_cc: self.send_synth_control(
                    cc, 127 if var.get() else 0
                ),
            ).grid(row=0, column=0, padx=4, sticky="w")
            start_row = 1
            if title == "Distortion":
                type_box = ttk.Combobox(
                    block,
                    textvariable=self.distortion_type,
                    values=tuple(DISTORTION_TYPE_VALUES),
                    width=12,
                    state="readonly",
                )
                type_box.grid(row=0, column=1, padx=4)
                type_box.bind(
                    "<<ComboboxSelected>>",
                    lambda _event: self.send_distortion_type_selection(),
                )
            for spec_index, (label, variable, controller) in enumerate(specs):
                row = start_row + spec_index // 2
                column = (spec_index % 2) * 2
                ttk.Label(block, text=label).grid(
                    row=row, column=column, padx=2, sticky="e"
                )
                scale = tk.Scale(
                    block, from_=0, to=127, orient=tk.HORIZONTAL,
                    variable=variable, length=130,
                )
                scale.grid(row=row, column=column + 1, padx=2)
                scale.bind(
                    "<ButtonRelease-1>",
                    lambda _event, cc=controller, var=variable: (
                        self.send_synth_control(cc, var.get())
                    ),
                )

        for column, osc_name in enumerate(("A", "B")):
            osc_frame = ttk.LabelFrame(
                parameter_controls, text=f"OSC {osc_name}", padding=8
            )
            osc_frame.grid(row=6, column=column, padx=6, pady=(6, 0))
            self._build_oscillator_controls(osc_frame, osc_name)

        keyboard = ttk.LabelFrame(
            self.main_content,
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

        bottom = ttk.Frame(self.main_content, padding=(10, 0, 10, 10))
        bottom.grid(row=4, column=0, sticky="ew")
        ttk.Label(bottom, textvariable=self.status).pack(side=tk.LEFT)
        self.log = tk.Text(bottom, width=54, height=5, state=tk.DISABLED)
        self.log.pack(side=tk.RIGHT)

    def _update_scroll_region(self, _event=None) -> None:
        self.main_canvas.configure(scrollregion=self.main_canvas.bbox("all"))

    def _resize_scroll_content(self, event) -> None:
        content_width = max(event.width, self.main_content.winfo_reqwidth())
        self.main_canvas.itemconfigure(
            self.main_content_window, width=content_width
        )

    def _scroll_main_view(self, event) -> None:
        if event.delta == 0:
            return
        direction = -1 if event.delta > 0 else 1
        if event.state & 0x0001:
            self.main_canvas.xview_scroll(direction, "units")
        else:
            self.main_canvas.yview_scroll(direction, "units")

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
            ("DDR波表编号", "wavetable_index", 0, 15),
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

    def apply_selected_preset(self) -> None:
        preset_name = self.preset_name.get()
        preset = SYNTH_PRESETS.get(preset_name)
        if preset is None:
            self.status.set("请先选择一个音色预设")
            return

        for control_name, value in preset["controls"].items():
            getattr(self, control_name).set(value)
        for osc_name, values in preset["oscillators"].items():
            controls = self.osc_controls[osc_name]
            for control_name, value in values.items():
                controls[control_name].set(value)

        # 预设不继承上一个音色的LFO路由，避免隐藏调制导致听感不确定。
        for enabled in self.filter_lfo_enabled:
            enabled.set(False)
        for route in self.lfo_routes:
            route["enabled"].set(False)
            route["source"].set("LFO 1")
            route["destination"].set("无")
            route["depth"].set(0)

        connected = self.port is not None and self.port.is_open
        if connected:
            self.send_all_synth_controls()
            if self.port is not None and self.port.is_open:
                self.status.set(f"已应用音色：{preset_name}")
                self._append_log(f"应用音色预设：{preset_name}")
        else:
            self.status.set(f"已载入音色：{preset_name}；连接串口后自动发送")

    def send_effect_mode_selection(self) -> None:
        mode_name = self.effect_mode.get()
        value = EFFECT_MODE_VALUES.get(mode_name, EFFECT_MODE_VALUES["旁路"])
        if self.send_control_change(EFFECT_MODE_CC, value, CONTROL_CHANNEL):
            self.status.set(f"全局效果器模式：{mode_name}")

    def send_distortion_type_selection(self) -> None:
        type_name = self.distortion_type.get()
        value = DISTORTION_TYPE_VALUES.get(type_name, 0)
        if self.send_control_change(
            DISTORTION_TYPE_CC, value, CONTROL_CHANNEL
        ):
            self.status.set(f"Distortion类型：{type_name}")

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
        """发送三条曲线和8条共享路由，最后在FPGA中原子提交。"""
        self.filter_lfo_config_after_id = None
        if self.port is None or not self.port.is_open:
            return

        active_rates = []
        phase_scale = float(1 << FILTER_LFO_PHASE_BITS)
        for lfo_index, parameter_map in enumerate(FILTER_LFO_PARAMETER_SETS):
            points = self.filter_lfo_curves[lfo_index].points
            middle_time = max(0.125, min(0.875, float(points[1].time)))
            rate_hz = max(
                0.1, min(10.0, float(self.filter_lfo_rate[lfo_index].get()))
            )
            active_rates.append(rate_hz)
            step_0 = round(
                rate_hz * phase_scale / (FILTER_LFO_SAMPLE_RATE * middle_time)
            )
            step_1 = round(
                rate_hz * phase_scale
                / (FILTER_LFO_SAMPLE_RATE * (1.0 - middle_time))
            )
            values = (
                (
                    parameter_map["enable"],
                    1 if self.filter_lfo_enabled[lfo_index].get() else 0,
                ),
                (parameter_map["step_0"], max(1, min(0x3FFF, step_0))),
                (parameter_map["step_1"], max(1, min(0x3FFF, step_1))),
                (
                    parameter_map["point_0"],
                    self._encode_bipolar_q13(points[0].level),
                ),
                (
                    parameter_map["point_1"],
                    self._encode_bipolar_q13(points[1].level),
                ),
                (
                    parameter_map["point_2"],
                    self._encode_bipolar_q13(points[2].level),
                ),
                (
                    parameter_map["curve_0"],
                    self._encode_bipolar_q13(points[0].curve),
                ),
                (
                    parameter_map["curve_1"],
                    self._encode_bipolar_q13(points[1].curve),
                ),
            )
            for parameter_id, value in values:
                if not self.send_highres_parameter(
                    parameter_id, value, log_message=False
                ):
                    return

        enabled_route_count = 0
        for route_index, route in enumerate(self.lfo_routes):
            destination_name = route["destination"].get()
            destination = LFO_DESTINATIONS.get(destination_name, 0)
            source = LFO_SOURCES.get(route["source"].get(), 0)
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
                (FILTER_LFO_PARAMETER["route_source"], source),
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

        enabled_names = [
            f"LFO{index + 1}"
            for index, enabled in enumerate(self.filter_lfo_enabled)
            if enabled.get()
        ]
        state = "/".join(enabled_names) if enabled_names else "全部关闭"
        self.status.set(
            f"FPGA通用LFO：{state}，速率 "
            f"{active_rates[0]:.1f}/{active_rates[1]:.1f}/{active_rates[2]:.1f} Hz，"
            f"启用{enabled_route_count}条路由"
        )

    def open_filter_lfo_editor(self, lfo_index: int) -> None:
        if self.filter_lfo_windows[lfo_index] is not None:
            self.filter_lfo_windows[lfo_index].lift()
            self.filter_lfo_windows[lfo_index].focus_force()
            return

        window = tk.Toplevel(self.root)
        window.title(f"通用 LFO {lfo_index + 1} 曲线编辑器")
        window.resizable(False, False)
        editor = LfoCurveEditor(
            window,
            self.filter_lfo_curves[lfo_index],
            on_change=self._filter_lfo_curve_changed,
        )
        editor.pack(padx=10, pady=10)
        self.filter_lfo_windows[lfo_index] = window

        def close_editor() -> None:
            window.destroy()
            self.filter_lfo_windows[lfo_index] = None

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
        self.send_synth_control(
            VIBRATO_ENABLE_CC, 127 if self.vibrato_enabled.get() else 0
        )
        self.send_synth_control(VIBRATO_RATE_CC, self.vibrato_rate.get())
        self.send_synth_control(VIBRATO_DEPTH_CC, self.vibrato_depth.get())
        self.send_synth_control(
            PORTAMENTO_ENABLE_CC,
            127 if self.portamento_enabled.get() else 0,
        )
        self.send_synth_control(PORTAMENTO_TIME_CC, self.portamento_time.get())
        self.send_effect_mode_selection()
        self.send_synth_control(DELAY_TIME_CC, self.delay_time.get())
        self.send_synth_control(DELAY_FEEDBACK_CC, self.delay_feedback.get())
        self.send_synth_control(DELAY_MIX_CC, self.delay_mix.get())
        self.send_synth_control(REVERB_SIZE_CC, self.reverb_size.get())
        self.send_synth_control(REVERB_DECAY_CC, self.reverb_decay.get())
        self.send_synth_control(REVERB_MIX_CC, self.reverb_mix.get())
        self.send_synth_control(
            DISTORTION_ENABLE_CC, 127 if self.distortion_enabled.get() else 0
        )
        self.send_distortion_type_selection()
        self.send_synth_control(DISTORTION_DRIVE_CC, self.distortion_drive.get())
        self.send_synth_control(DISTORTION_TONE_CC, self.distortion_tone.get())
        self.send_synth_control(DISTORTION_MIX_CC, self.distortion_mix.get())
        effect_parameter_groups = (
            (
                self.chorus_enabled, CHORUS_ENABLE_CC,
                (
                    (CHORUS_RATE_CC, self.chorus_rate),
                    (CHORUS_DEPTH_CC, self.chorus_depth),
                    (CHORUS_DELAY_CC, self.chorus_delay),
                    (CHORUS_FEEDBACK_CC, self.chorus_feedback),
                    (CHORUS_MIX_CC, self.chorus_mix),
                ),
            ),
            (
                self.phaser_enabled, PHASER_ENABLE_CC,
                (
                    (PHASER_RATE_CC, self.phaser_rate),
                    (PHASER_DEPTH_CC, self.phaser_depth),
                    (PHASER_CENTER_CC, self.phaser_center),
                    (PHASER_FEEDBACK_CC, self.phaser_feedback),
                    (PHASER_MIX_CC, self.phaser_mix),
                ),
            ),
            (
                self.compressor_enabled, COMPRESSOR_ENABLE_CC,
                (
                    (COMPRESSOR_THRESHOLD_CC, self.compressor_threshold),
                    (COMPRESSOR_RATIO_CC, self.compressor_ratio),
                    (COMPRESSOR_ATTACK_CC, self.compressor_attack),
                    (COMPRESSOR_RELEASE_CC, self.compressor_release),
                    (COMPRESSOR_MAKEUP_CC, self.compressor_makeup),
                    (COMPRESSOR_MIX_CC, self.compressor_mix),
                ),
            ),
        )
        for enabled, enable_cc, parameters in effect_parameter_groups:
            self.send_synth_control(enable_cc, 127 if enabled.get() else 0)
            for controller, variable in parameters:
                self.send_synth_control(controller, variable.get())
        self.send_filter_lfo_configuration()
        for osc_name, cc_map in (("A", OSC_A_CC), ("B", OSC_B_CC)):
            controls = self.osc_controls[osc_name]
            self.send_oscillator_enable(osc_name)
            self.send_waveform_selection(osc_name)
            self.send_warp_mode_selection(osc_name)
            for key in (
                "warp_amount",
                "wavetable_index",
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
