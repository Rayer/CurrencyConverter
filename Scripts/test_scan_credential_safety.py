import contextlib
import io
import runpy
import sys
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

        self.assertEqual(
            findings,
            [("artifact-7:dir-1:unreadable", "credential-like material")],
        )

    def test_tracked_and_nested_artifact_labels_do_not_include_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tracked_file = root / ("tracked" + "-credential-name")
            tracked_file.write_text("api" + "Key" + "=synthetic-value\n", encoding="utf-8")
            artifact_root = root / ("artifact" + "-credential-name")
            nested_directory = artifact_root / ("nested" + "-credential-name")
            nested_directory.mkdir(parents=True)
            artifact_file = nested_directory / ("artifact" + "-credential-name")
            artifact_file.write_text("secret" + "Key" + "=synthetic-value\n", encoding="utf-8")
            symlink = artifact_root / ("directory" + "-link")
            symlink.symlink_to(nested_directory, target_is_directory=True)

            scanner_globals = SCANNER["main"].__globals__
            original_tracked_files = scanner_globals["tracked_files"]
            original_argv = sys.argv
            scanner_globals["tracked_files"] = lambda _root: [tracked_file]
            sys.argv = ["scan-credential-safety.py", "--root", str(root)]
            output = io.StringIO()
            try:
                with contextlib.redirect_stdout(output):
                    status = SCANNER["main"]()
            finally:
                scanner_globals["tracked_files"] = original_tracked_files
                sys.argv = original_argv

            self.assertEqual(status, 1)
            self.assertIn("tracked-file-1:1", output.getvalue())
            self.assertNotIn(str(tracked_file), output.getvalue())

            findings = []
            SCANNER["scan_artifact"](artifact_root, findings, label="artifact-7")
            locations = [location for location, _ in findings]
            self.assertIn("artifact-7:file-1:1", locations)
            self.assertTrue(
                any(
                    location.startswith("artifact-7:dir-")
                    and location.endswith(":symlink")
                    for location in locations
                )
            )
            self.assertNotIn(str(artifact_root), str(findings))


if __name__ == "__main__":
    unittest.main()
