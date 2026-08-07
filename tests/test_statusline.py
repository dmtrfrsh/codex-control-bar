import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("statusline_installer", ROOT / "scripts" / "install_statusline.py")
statusline = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(statusline)


class StatusLineInstallerTests(unittest.TestCase):
    def test_adds_tui_section_without_touching_existing_values(self):
        source = 'model = "gpt-test"\n[mcp_servers.local]\ncommand = "safe"\n'
        result = statusline.update_document(source)
        self.assertIn(source, result)
        self.assertIn("[tui]\n", result)
        self.assertIn('"context-used"', result)

    def test_replaces_only_status_keys_and_is_idempotent(self):
        source = """[tui]
animations = false
status_line = [
  "model-with-reasoning",
  "current-dir",
]
status_line_use_colors = false

[history]
persistence = "save-all"
"""
        result = statusline.update_document(source)
        self.assertIn("animations = false", result)
        self.assertIn('[history]\npersistence = "save-all"', result)
        self.assertNotIn('"current-dir"', result)
        self.assertEqual(statusline.update_document(result), result)


if __name__ == "__main__":
    unittest.main()
