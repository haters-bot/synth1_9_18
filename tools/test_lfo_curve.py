import unittest

from lfo_curve import (
    LfoCurve,
    MAX_CONTROL_POINTS,
    MAX_MIDDLE_TIME,
    MIN_MIDDLE_TIME,
)


class LfoCurveTest(unittest.TestCase):
    def test_default_curve_and_loop_boundary(self) -> None:
        curve = LfoCurve()
        self.assertAlmostEqual(curve.evaluate(0.0), -1.0, places=6)
        self.assertGreater(curve.evaluate(0.5), 0.99)
        self.assertAlmostEqual(curve.points[-1].level, curve.points[0].level)

    def test_point_limit(self) -> None:
        curve = LfoCurve()
        self.assertEqual(len(curve.points), MAX_CONTROL_POINTS)

    def test_two_curve_directions(self) -> None:
        curve = LfoCurve()
        curve.points[0].time = 0.0
        curve.points[0].level = -1.0
        curve.points[1].time = 0.5
        curve.points[1].level = 1.0

        curve.points[0].curve = 0.0
        self.assertAlmostEqual(curve.evaluate(0.25), 0.0, places=6)
        curve.points[0].curve = 1.0
        self.assertAlmostEqual(curve.evaluate(0.25), -0.375, places=6)
        curve.points[0].curve = -1.0
        self.assertAlmostEqual(curve.evaluate(0.25), 0.375, places=6)

    def test_segment_endpoint_slopes_are_zero(self) -> None:
        curve = LfoCurve()
        epsilon = 1.0e-5
        for curvature in (-1.0, 0.0, 1.0):
            curve.points[0].curve = curvature
            start_slope = (
                curve.evaluate(epsilon) - curve.evaluate(0.0)
            ) / epsilon
            end_slope = (
                curve.evaluate(0.5) - curve.evaluate(0.5 - epsilon)
            ) / epsilon
            self.assertAlmostEqual(start_slope, 0.0, places=3)
            self.assertAlmostEqual(end_slope, 0.0, places=3)

    def test_middle_time_is_hardware_safe(self) -> None:
        curve = LfoCurve()
        curve.move_point(1, 0.0, 0.5)
        self.assertEqual(curve.points[1].time, MIN_MIDDLE_TIME)
        curve.move_point(1, 1.0, 0.5)
        self.assertEqual(curve.points[1].time, MAX_MIDDLE_TIME)


if __name__ == "__main__":
    unittest.main()
