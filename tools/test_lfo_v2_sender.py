"""不连接硬件，验证桌面V2配置与控件构建；需要可用的Tk环境。"""
import tkinter as tk
from types import SimpleNamespace
from midi_uart_sender import MidiUartSender
root=tk.Tk(); root.withdraw()
app=MidiUartSender(root)
root.update_idletasks()
events=[]
app.port=SimpleNamespace(is_open=True)
app._send=lambda message,log_message=True: events.append(message) or True
app.send_filter_lfo_configuration()
assert len(events)==81, len(events)
assert all(len(f)==6 and all(v<128 for v in f[1:-1]) for f in events)
assert events[-1]==bytes.fromhex('F0 7D 7E 00 00 F7')
app.filter_lfo_enabled[0].set(True)
app.lfo_routes[23]['source'].set('LFO 1')
app.lfo_routes[23]['depth'].set(-64)
events.clear(); app.send_filter_lfo_configuration()
assert events==[bytes.fromhex('F0 7D 60 03 40 F7'),bytes.fromhex('F0 7D 7E 00 00 F7')],events
app.filter_lfo_curves[1].move_point(3,0.5,70)
events.clear(); app.send_filter_lfo_configuration()
assert len(events)==3 and events[-2]==bytes.fromhex('F0 7D 48 00 05 F7'),events
app.open_filter_lfo_editor(0)
app.filter_lfo_windows[0].withdraw()
root.update_idletasks()
print('PASS: desktop widgets, 7-node editor, 53 targets, 81-frame initial sync, signed routing, dirty/restart transaction')
app.port=None
root.destroy()
