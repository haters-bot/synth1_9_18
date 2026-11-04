"""Exercise serial diagnostic output without requiring a COM port or pyserial."""
import unittest
from lfo_serial_monitor import describe, decode_stream, HZ


class MonitorTests(unittest.TestCase):
    def test_all_modes(self):
        for bank in range(3):
            for index, hz in enumerate(HZ):
                for flags in (0, 8, 16, 24):
                    mode = index | flags
                    frame = bytes((0xF0, 0x7D, 0x45 + bank, 0, mode, 0xF7))
                    text = describe(frame, hz)
                    self.assertIn(f'UI_Hz={hz}', text)
                    self.assertIn(f'rate_index={index}', text)
                    self.assertIn(f'mode_value={mode}', text)
                    self.assertIn('UI_match=True', text)
                    self.assertIn(frame.hex(' ').upper(), text)

    def test_capture_mismatch_is_visible(self):
        self.assertIn('UI_match=False', describe(bytes.fromhex('F0 7D 45 00 00 F7'), '2'))

    def test_stream_and_realtime(self):
        wire = bytes.fromhex('BF 18 7F F0 7D 45 F8 00 03 F7 F0 7D 48 00 04 F7 F0 7D 7E 00 00 F7')
        lines = list(decode_stream(wire, '2'))
        self.assertEqual(len(lines), 3)
        self.assertIn('mode_value=3', lines[0])
        self.assertIn('id=0x48 value=4', lines[1])
        self.assertIn('id=0x7E value=0', lines[2])


if __name__ == '__main__':
    unittest.main()
