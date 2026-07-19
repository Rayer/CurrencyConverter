import runpy
import tempfile
import unittest
from pathlib import Path


SCANNER = runpy.run_path(str(Path(__file__).with_name("scan-credential-safety.py")))


class ScannerTraversalTests(unittest.TestCase):
    def test_injected_traversal_error_is_reported_with_opaque_label(self):
        with tempfile.TemporaryDirectory() as directory:
            findings = []

            def failing_walker(_path, topdown, onerror, followlinks):
                self.assertTrue(topdown)
                self.assertFalse(followlinks)
                onerror(OSError("injected traversal failure"))
                return iter(())

            SCANNER["scan_artifact"](
                Path(directory),
                findings,
                label="artifact-7",
                walker=failing_walker,
            )

        self.assertEqual(findings, [("artifact-7:unreadable", "credential-like material")])


if __name__ == "__main__":
    unittest.main()
