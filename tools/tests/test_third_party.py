import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
THIRD_PARTY = ROOT / "dn/third-party"


def projects():
    return sorted(p for p in THIRD_PARTY.iterdir() if p.is_dir())


class ThirdPartyTests(unittest.TestCase):
    def test_every_project_has_license_and_notice(self):
        self.assertTrue(projects())
        for project in projects():
            with self.subTest(project=project.name):
                self.assertTrue((project / "LICENSE").is_file())
                notice = (project / "NOTICE").read_text(encoding="utf-8")
                self.assertRegex(notice, r"https://github\.com/\S+")
                self.assertRegex(notice, r"commit:\s+[0-9a-f]{40}\b")

    def test_release_archives_carry_license_and_notice(self):
        script = (ROOT / "tools/dn-notices.sh").read_text(encoding="utf-8")
        for project in projects():
            with self.subTest(project=project.name):
                for name in ("LICENSE", "NOTICE"):
                    self.assertRegex(script, r"(?m)^copy dn/third-party/%s/%s \S+$" % (re.escape(project.name), name))

    def test_provenance_lists_every_project(self):
        provenance = (ROOT / "dn/PROVENANCE.md").read_text(encoding="utf-8")
        for project in projects():
            with self.subTest(project=project.name):
                self.assertIn("`third-party/%s/`" % project.name, provenance)


if __name__ == "__main__":
    unittest.main()
