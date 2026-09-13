import ctypes
import platform
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "Engine/Quake3/zq3_runtime.c"
INC = ROOT / "Engine/Quake3"


class Input(ctypes.Structure):
    _fields_ = [
        ("move_x", ctypes.c_float), ("move_y", ctypes.c_float),
        ("look_x", ctypes.c_float), ("look_y", ctypes.c_float),
        ("fire", ctypes.c_uint8), ("aim", ctypes.c_uint8),
        ("jump", ctypes.c_uint8), ("reload", ctypes.c_uint8),
    ]


class Player(ctypes.Structure):
    _fields_ = [
        ("position", ctypes.c_float * 3),
        ("yaw", ctypes.c_float), ("pitch", ctypes.c_float),
        ("vertical_velocity", ctypes.c_float),
        ("grounded", ctypes.c_uint8),
        ("frame_number", ctypes.c_uint64),
    ]


class QuakeRuntimeNativeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        suffix = ".dylib" if platform.system() == "Darwin" else ".so"
        output = Path(cls.tmp.name) / f"libzq3{suffix}"
        cmd = ["cc", "-std=c99", "-I", str(INC), str(SRC), "-o", str(output)]
        if platform.system() == "Darwin":
            cmd[1:1] = ["-dynamiclib"]
        else:
            cmd[1:1] = ["-shared", "-fPIC"]
        cmd.append("-lm")
        subprocess.run(cmd, check=True, capture_output=True)
        cls.lib = ctypes.CDLL(str(output))
        cls.lib.zq3_init.restype = ctypes.c_int
        cls.lib.zq3_load_world.restype = ctypes.c_int
        cls.lib.zq3_set_input.argtypes = [ctypes.POINTER(Input)]
        cls.lib.zq3_step.argtypes = [ctypes.c_float]
        cls.lib.zq3_get_player_state.argtypes = [ctypes.POINTER(Player)]

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def setUp(self):
        self.assertEqual(self.lib.zq3_init(), 0)
        # Two triangles forming a flat 20x20 floor at Y=0.
        vertices = (ctypes.c_float * 12)(-10,0,-10, 10,0,-10, 10,0,10, -10,0,10)
        indices = (ctypes.c_uint32 * 6)(0,2,1, 0,3,2)
        spawn = (ctypes.c_float * 3)(0, 4, 6)
        self.assertEqual(self.lib.zq3_load_world(vertices, 4, indices, 6, spawn), 0)

    def tearDown(self):
        self.lib.zq3_shutdown()

    def state(self):
        s = Player()
        self.lib.zq3_get_player_state(ctypes.byref(s))
        return s

    def test_load_snaps_player_to_floor(self):
        s = self.state()
        self.assertAlmostEqual(s.position[1], 1.65, places=2)
        self.assertEqual(s.grounded, 1)

    def test_forward_input_moves_player(self):
        before = self.state()
        command = Input(move_y=1)
        self.lib.zq3_set_input(ctypes.byref(command))
        for _ in range(10):
            self.lib.zq3_step(ctypes.c_float(1/60))
        after = self.state()
        self.assertLess(after.position[2], before.position[2])
        self.assertGreater(after.frame_number, before.frame_number)

    def test_jump_leaves_floor(self):
        command = Input(jump=1)
        self.lib.zq3_set_input(ctypes.byref(command))
        self.lib.zq3_step(ctypes.c_float(1/60))
        s = self.state()
        self.assertGreater(s.position[1], 1.65)
        self.assertEqual(s.grounded, 0)


if __name__ == "__main__":
    unittest.main()
