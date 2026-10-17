import unittest

from lfo_curve import LfoCurve, MAX_CONTROL_POINTS, TABLE_SIZE


class LfoCurveTest(unittest.TestCase):
    def test_default_table_and_loop_boundary(self) -> None:
        curve = LfoCurve()
        self.assertEqual(len(curve.table), TABLE_SIZE)
        self.assertAlmostEqual(curve.table_value(0.0), 0.0, places=6)
        self.assertGreater(curve.table_value(0.25), 0.99)
        self.assertLess(curve.table_value(0.75), -0.99)

    def test_point_limit(self) -> None:
        curve = LfoCurve()
        while len(curve.points) < MAX_CONTROL_POINTS:
            curve.add_point((len(curve.points) - 2) / MAX_CONTROL_POINTS + 0.01, 0.0)
        self.assertEqual(len(curve.points), MAX_CONTROL_POINTS)
        self.assertEqual(curve.add_point(0.5, 0.0), -1)

    def test_segment_types(self) -> None:
        curve = LfoCurve()
        curve.points = curve.points[:2]
        curve.points[0].time = 0.0
        curve.points[0].level = -1.0
        curve.points[1].time = 1.0
        curve.points[1].level = 1.0

        curve.points[0].segment = "Linear"
        self.assertAlmostEqual(curve.evaluate(0.5), 0.0, places=6)
        curve.points[0].segment = "Step"
        self.assertAlmostEqual(curve.evaluate(0.5), -1.0, places=6)
        curve.points[0].segment = "Curve"
        curve.points[0].curve = 1.0
        self.assertLess(curve.evaluate(0.5), -0.9)


if __name__ == "__main__":
    unittest.main()
