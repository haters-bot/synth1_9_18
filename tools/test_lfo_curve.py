import random
import unittest
from fractions import Fraction
from lfo_curve import LfoCurve
from lfo_v2_protocol import *

class LfoV2Test(unittest.TestCase):
    def test_fixed_nodes(self):
        c=LfoCurve()
        for n in range(7):
            c.move_point(n, 0.123, 200)
            self.assertEqual(c.points[n].time,n/6)
            self.assertEqual(c.points[n].level,127)
        self.assertEqual(c.evaluate(1),127)
    def test_fraction_reference_and_monotonic_bounds(self):
        rng=random.Random(728)
        for points in list(PRESETS)+[tuple(rng.randrange(128) for _ in range(7)) for _ in range(25)]:
            for phase in range(385):
                self.assertEqual(value_q6(points,phase,True),points[min(phase//64,6)]*64)
                if phase==384:
                    self.assertEqual(value_q6(points,phase),points[6]*64)
                    continue
                s,t6=divmod(phase,64); t=Fraction(t6,64)
                def mm(x,y):
                    return (1 if x>0 else -1)*min(abs(x),abs(y)) if x*y>0 else 0
                dm=points[s+1]-points[s]
                m0=mm(points[s]-points[s-1],dm) if s else 0
                m1=mm(dm,points[s+2]-points[s+1]) if s<5 else 0
                # 独立Hermite基函数模型，不复写RTL的Horner表达式。
                y=(2*t**3-3*t**2+1)*points[s]+(t**3-2*t**2+t)*m0+(-2*t**3+3*t**2)*points[s+1]+(t**3-t**2)*m1
                self.assertEqual(value_q6(points,phase),int(y*64))
                self.assertTrue(min(points[s:s+2])*64<=value_q6(points,phase)<=max(points[s:s+2])*64)
    def test_protocol_and_signed_depth(self):
        self.assertEqual(len(TARGET_NAMES),53)
        self.assertEqual(sysex(96,pack_route(1,-64)),bytes.fromhex('F0 7D 60 03 40 F7'))
        self.assertEqual(modulate(64,1,-127,127),0)
        self.assertEqual(modulate(0,1,127,127),126)
        self.assertEqual(modulate(20,0,127,127),20)
        for source in range(4):
            for depth in range(-127,128):
                frame=sysex(125,pack_route(source,depth))
                self.assertTrue(all(v<128 for v in frame[1:-1]))
        with self.assertRaises(ValueError): pack_route(1,-128)
    def test_full_sync(self):
        fields=configuration_fields(list(PRESETS),[(2,False,False)]*3,[(0,0)]*53)
        self.assertEqual(len(fields),77)
        self.assertEqual(set(fields),set(range(48,72))|set(range(73,126)))
        self.assertEqual((len(fields)+3+1)*6*10/31250,0.15552)

if __name__=='__main__': unittest.main()
