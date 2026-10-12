"""Check Pocket packaging constraints for controls and core identity."""
import importlib.util
from pathlib import Path
import unittest
from tempfile import TemporaryDirectory

spec = importlib.util.spec_from_file_location(
    "pocket_package", Path(__file__).resolve().parents[1] / "tools/package.py")
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class ControlLabels(unittest.TestCase):
    def definition(self, label):
        return {"input": {"controllers": [{"mappings": [
            {"name": label, "key": "pad_btn_select"}]}]}}

    def test_accepts_nineteen_characters(self):
        package.validate_input(self.definition("x" * 19))

    def test_rejects_twenty_characters(self):
        with self.assertRaisesRegex(ValueError, "pad_btn_select label exceeds 19"):
            package.validate_input(self.definition("x" * 20))

    def test_rejects_original_reset_label(self):
        with self.assertRaises(ValueError):
            package.validate_input(self.definition("Reset: Select + Start"))


class CoreIdentity(unittest.TestCase):
    def validate(self, author, shortname):
        with TemporaryDirectory() as temp:
            core = Path(temp) / "Local.PocketDreamConsole"
            package.write_json(core / "core.json", {"core": {"metadata": {
                "author": author, "shortname": shortname}}})
            package.validate_core_identity(core)

    def test_accepts_matching_folder(self):
        self.validate("Local", "PocketDreamConsole")

    def test_rejects_original_metadata(self):
        with self.assertRaisesRegex(ValueError, "differs from folder"):
            self.validate("Local build", "Pocket Dream Console")


if __name__ == "__main__":
    unittest.main()
