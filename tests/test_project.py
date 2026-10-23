"""Publication regression checks for links, manifest exclusions, and archives."""
import importlib.util
import json
from pathlib import Path
import re
import shutil
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("release_builder", ROOT / "scripts/build-release.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class ProjectTests(unittest.TestCase):
    def test_relative_markdown_links_exist(self):
        for document in ROOT.rglob("*.md"):
            for target in re.findall(r"\]\(([^)]+)\)", document.read_text(encoding="utf-8")):
                if target.startswith(("http:", "https:", "mailto:", "#")):
                    continue
                path = target.split("#", 1)[0]
                self.assertTrue((document.parent / path).exists(), f"Broken link in {document.name}: {target}")

    def test_manifest_rejects_sensitive_and_escaping_paths(self):
        for name in ("auth.json", "AUTH.JSON", ".env.local", "monitor.log.1", ".git/config", "state-example.json", "../escape.md"):
            with self.subTest(name=name), tempfile.TemporaryDirectory(prefix="quota-manifest-") as temp:
                root = Path(temp)
                (root / "publish-manifest.txt").write_text(name + "\n", encoding="utf-8")
                with self.assertRaises(ValueError):
                    builder.listed_files(root)

    def test_archive_has_only_manifest_entries_and_retains_dotfiles(self):
        files = builder.listed_files(ROOT)
        with tempfile.TemporaryDirectory(prefix="quota-release-") as temp:
            stage = Path(temp) / "source"
            stage.mkdir()
            for relative, source in files:
                destination = stage / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
            # An unlisted fake credential must never enter the release.
            (stage / "auth.json").write_text('{"fixture": "not-a-real-credential"}')
            archive, count = builder.build(stage, Path(temp) / "output")
            with zipfile.ZipFile(archive) as zipped:
                names = zipped.namelist()
                self.assertEqual(count, len(files))
                self.assertEqual(len(names), count)
                self.assertTrue(any(name.endswith("/.gitignore") for name in names))
                self.assertTrue(any(name.endswith("/.github/workflows/ci.yml") for name in names))
                self.assertFalse(any(name.endswith("/auth.json") for name in names))
                shell = next(info for info in zipped.infolist() if info.filename.endswith("/setup.sh"))
                self.assertTrue((shell.external_attr >> 16) & 0o111)

    def test_both_homepages_lead_with_host_requirement(self):
        chinese = (ROOT / "README.md").read_text(encoding="utf-8").splitlines()[:8]
        english = (ROOT / "README.en.md").read_text(encoding="utf-8").splitlines()[:10]
        self.assertIn("持续开机", "\n".join(chinese))
        self.assertIn("保持联网", "\n".join(chinese))
        self.assertIn("powered on", "\n".join(english))
        self.assertIn("connected to the internet", "\n".join(english))


if __name__ == "__main__":
    unittest.main(verbosity=2)
