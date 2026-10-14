import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class LinuxPackageLayoutTest(unittest.TestCase):
    def test_linux_archive_can_be_extracted_under_prefix(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            build = temp / "build"
            pack = temp / "pack"
            build.mkdir()
            for name in ("dn", "en.lng", "dn.dlg", "dn.hlp"):
                (build / name).write_text("fixture\n", encoding="utf-8")

            subprocess.run(
                [str(ROOT / "tools/dn-pack.sh"), str(build), "linux64", "tar", str(pack), "v-test"],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )

            archive = pack / "dn-v-test-linux64.tar.gz"
            with tarfile.open(archive, "r:gz") as tar:
                names = set(tar.getnames())
                prefix = "dn-v-test-linux64/"
                for path in (
                    "bin/dn",
                    "lib/dn/dn",
                    "lib/dn/dn-autoupdate.sh",
                    "lib/dn/en.lng",
                    "lib/dn/dn.dlg",
                    "lib/dn/dn.hlp",
                    "lib/dn/xlt",
                    "lib/dn/dn.ext",
                    "share/applications/dn.desktop",
                    "share/icons/hicolor/scalable/apps/dn.svg",
                ):
                    self.assertIn(prefix + path, names)

                wrapper = tar.extractfile(prefix + "bin/dn").read().decode("utf-8")
                self.assertIn('"$PREFIX/lib/dn"', wrapper)
                self.assertIn('exec "$LIB/dn" "$@"', wrapper)
                self.assertTrue(tar.getmember(prefix + "bin/dn").mode & 0o111)


if __name__ == "__main__":
    unittest.main()
