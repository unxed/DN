import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
THIRD_PARTY = ROOT / "dn/third-party"


def projects():
    return sorted(p for p in THIRD_PARTY.iterdir() if p.is_dir())


class ThirdPartyTests(unittest.TestCase):
    def test_freebsd64_notice_is_supported(self):
        with tempfile.TemporaryDirectory() as dest:
            result = subprocess.run(
                [str(ROOT / "tools/dn-notices.sh"), dest, "freebsd64"],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            readme = (Path(dest) / "README.TXT").read_text(encoding="utf-8")
            self.assertIn("DN for FreeBSD", readme)
            self.assertIn("dn-VERSION-freebsd64.tar.gz", readme)
            self.assertNotIn("DN for Linux", readme)

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
