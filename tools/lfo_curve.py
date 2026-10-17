"""精简版可编辑LFO曲线模型与Tk控件。"""

from __future__ import annotations

from dataclasses import dataclass
import bisect
import tkinter as tk
from tkinter import ttk
from typing import Callable


MAX_CONTROL_POINTS = 3
TABLE_SIZE = 256
MIN_MIDDLE_TIME = 0.125
MAX_MIDDLE_TIME = 0.875


@dataclass
class LfoPoint:
    time: float
    level: float
    curve: float = 0.0


class LfoCurve:
    """保存硬件LFO使用的三个控制点和两段曲率。"""

    def __init__(self) -> None:
        self.points = [
            LfoPoint(0.00, -1.0),
            LfoPoint(0.50, 1.0),
            LfoPoint(1.00, -1.0),
        ]
        self.loop_smooth = True

    @staticmethod
    def _clamp(value: float, minimum: float, maximum: float) -> float:
        return max(minimum, min(maximum, value))

    def move_point(self, index: int, time_value: float, level: float) -> None:
        point = self.points[index]
        if index == 0:
            point.time = 0.0
        elif index == len(self.points) - 1:
            point.time = 1.0
        else:
            # 两段局部相位步进使用14位配置。把中点限制在1/8～7/8，
            # 使0.1～10 Hz范围内的两段步进都能装入14位。
            point.time = self._clamp(time_value, MIN_MIDDLE_TIME, MAX_MIDDLE_TIME)
        point.level = self._clamp(level, -1.0, 1.0)
        if self.loop_smooth and index in (0, len(self.points) - 1):
            other = len(self.points) - 1 if index == 0 else 0
            self.points[other].level = point.level

    @staticmethod
    def _segment_weight(u: float, point: LfoPoint) -> float:
        # 与FPGA定点实现一致：正曲率向t²混合，负曲率向
        # 1-(1-t)²混合，0为线性。
        strength = abs(point.curve)
        quadratic = u * u if point.curve >= 0.0 else 2.0 * u - u * u
        return u + (quadratic - u) * strength

    def evaluate(self, phase: float) -> float:
        phase = phase % 1.0
        times = [point.time for point in self.points]
        index = max(0, min(len(self.points) - 2, bisect.bisect_right(times, phase) - 1))
        start = self.points[index]
        end = self.points[index + 1]
        width = max(end.time - start.time, 1.0e-9)
        u = self._clamp((phase - start.time) / width, 0.0, 1.0)
        weight = self._segment_weight(u, start)
        return start.level + (end.level - start.level) * weight

class LfoCurveEditor(ttk.LabelFrame):
    """通过拖动节点编辑时间和电平，并设置节点后的线段属性。"""

    WIDTH = 650
    HEIGHT = 170
    MARGIN = 12

    def __init__(
        self,
        parent: tk.Misc,
        curve: LfoCurve,
        on_change: Callable[[], None] | None = None,
    ) -> None:
        super().__init__(parent, text="FPGA Cutoff LFO（三点、两段曲率）", padding=6)
        self.curve = curve
        self.on_change = on_change
        self.selected_index = 0
        self.curve_amount = tk.DoubleVar(value=self.curve.points[0].curve)
        self.loop_smooth = tk.BooleanVar(value=self.curve.loop_smooth)
        self.selection_text = tk.StringVar()

        self.canvas = tk.Canvas(
            self,
            width=self.WIDTH,
            height=self.HEIGHT,
            background="#15191d",
            highlightthickness=1,
            highlightbackground="#555f68",
        )
        self.canvas.grid(row=0, column=0, columnspan=6, sticky="ew")
        self.canvas.bind("<Button-1>", self._select_point)
        self.canvas.bind("<B1-Motion>", self._drag_point)

        ttk.Label(self, textvariable=self.selection_text, width=30).grid(
            row=1, column=0, padx=4, sticky="w"
        )
        ttk.Label(self, text="到下一点的曲率").grid(
            row=1, column=1, columnspan=2, padx=(8, 2)
        )
        curve_scale = tk.Scale(
            self,
            from_=-1.0,
            to=1.0,
            resolution=0.01,
            orient=tk.HORIZONTAL,
            variable=self.curve_amount,
            length=180,
            command=self._change_curve,
        )
        curve_scale.grid(row=1, column=3, columnspan=2, padx=2)
        ttk.Checkbutton(
            self,
            text="首尾连续",
            variable=self.loop_smooth,
            command=self._toggle_loop_smooth,
        ).grid(row=1, column=5, padx=8)
        self.redraw()

    def _to_canvas(self, time_value: float, level: float) -> tuple[float, float]:
        width = self.WIDTH - 2 * self.MARGIN
        height = self.HEIGHT - 2 * self.MARGIN
        return (
            self.MARGIN + time_value * width,
            self.MARGIN + (1.0 - level) * 0.5 * height,
        )

    def _from_canvas(self, x_value: float, y_value: float) -> tuple[float, float]:
        width = self.WIDTH - 2 * self.MARGIN
        height = self.HEIGHT - 2 * self.MARGIN
        time_value = (x_value - self.MARGIN) / width
        level = 1.0 - 2.0 * (y_value - self.MARGIN) / height
        return (
            max(0.0, min(1.0, time_value)),
            max(-1.0, min(1.0, level)),
        )

    def _nearest_point(self, x_value: float, y_value: float) -> int:
        best_index = -1
        best_distance = 11.0 * 11.0
        for index, point in enumerate(self.curve.points):
            point_x, point_y = self._to_canvas(point.time, point.level)
            distance = (point_x - x_value) ** 2 + (point_y - y_value) ** 2
            if distance <= best_distance:
                best_distance = distance
                best_index = index
        return best_index

    def _select_point(self, event: tk.Event) -> None:
        index = self._nearest_point(event.x, event.y)
        if index >= 0:
            self.selected_index = index
            self._sync_controls()
            self.redraw()

    def _drag_point(self, event: tk.Event) -> None:
        if not 0 <= self.selected_index < len(self.curve.points):
            return
        time_value, level = self._from_canvas(event.x, event.y)
        self.curve.move_point(self.selected_index, time_value, level)
        self._changed()

    def _change_curve(self, _value: str) -> None:
        if self.selected_index < len(self.curve.points) - 1:
            self.curve.points[self.selected_index].curve = float(self.curve_amount.get())
            self._changed(sync_controls=False)

    def _toggle_loop_smooth(self) -> None:
        self.curve.loop_smooth = bool(self.loop_smooth.get())
        if self.curve.loop_smooth:
            self.curve.points[-1].level = self.curve.points[0].level
        self._changed()

    def _sync_controls(self) -> None:
        point = self.curve.points[self.selected_index]
        self.curve_amount.set(point.curve)
        self.selection_text.set(
            f"点 {self.selected_index + 1}/{len(self.curve.points)}  "
            f"时间={point.time:.3f}  电平={point.level:+.3f}"
        )

    def _changed(self, sync_controls: bool = True) -> None:
        if sync_controls:
            self._sync_controls()
        else:
            point = self.curve.points[self.selected_index]
            self.selection_text.set(
                f"点 {self.selected_index + 1}/{len(self.curve.points)}  "
                f"时间={point.time:.3f}  电平={point.level:+.3f}"
            )
        self.redraw()
        if self.on_change is not None:
            self.on_change()

    def redraw(self) -> None:
        self.canvas.delete("all")
        for division in range(9):
            x_value = self.MARGIN + division * (self.WIDTH - 2 * self.MARGIN) / 8
            self.canvas.create_line(x_value, self.MARGIN, x_value, self.HEIGHT - self.MARGIN,
                                    fill="#293138")
        middle_y = self.HEIGHT / 2
        self.canvas.create_line(self.MARGIN, middle_y, self.WIDTH - self.MARGIN, middle_y,
                                fill="#46515a")

        coordinates: list[float] = []
        for index in range(TABLE_SIZE + 1):
            phase = index / TABLE_SIZE
            value = self.curve.evaluate(phase if phase < 1.0 else 0.999999)
            x_value, y_value = self._to_canvas(phase, value)
            coordinates.extend((x_value, y_value))
        self.canvas.create_line(*coordinates, fill="#67d8ff", width=2, smooth=False)

        for index, point in enumerate(self.curve.points):
            x_value, y_value = self._to_canvas(point.time, point.level)
            radius = 6 if index == self.selected_index else 5
            fill = "#ffcf55" if index == self.selected_index else "#f0f4f7"
            self.canvas.create_oval(
                x_value - radius,
                y_value - radius,
                x_value + radius,
                y_value + radius,
                fill=fill,
                outline="#202428",
            )
        self._sync_controls()
