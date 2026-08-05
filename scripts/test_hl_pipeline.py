import os
import sys
import unittest
from types import SimpleNamespace

sys.path.insert(0, os.path.dirname(__file__))

from hl_pipeline import Codegen, IR_JZ


class ConditionalBranchCodegenTests(unittest.TestCase):
    def test_jz_uses_destination_vreg_and_returns_rel32_offset(self):
        codegen = Codegen({}, 'test')
        codegen.ra_map[7] = 0
        ir = SimpleNamespace(dst=[7], src1=[99], src2=[0], op=[IR_JZ])

        branch_site = codegen.emit_ir(0, ir)

        self.assertEqual(branch_site, 5)
        self.assertEqual(
            codegen.buf,
            bytearray([0x48, 0x85, 0xC0, 0x0F, 0x84, 0, 0, 0, 0]),
        )


if __name__ == '__main__':
    unittest.main()
