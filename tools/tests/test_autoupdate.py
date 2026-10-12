"""tools/dn-autoupdate.sh picks the newest v* release, pre-releases included.

GitHub's /releases/latest never returns a pre-release, and every DN release
so far is one, so the script used to find nothing (issue #4). The script runs
here against a release list and assets served from file:// URLs, with id and
uname stubbed so it acts as root on the architecture under test.
"""

import json
import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "dn-autoupdate.sh"


class AutoupdateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.state = self.tmp / "state"

    def stub(self, name, output):
        path = self.bin / name
        path.write_text(f"#!/bin/sh\necho {output}\n")
        path.chmod(0o755)

    def asset(self, name, payload):
        top = self.tmp / name.replace(".tar.gz", "")
        top.mkdir()
        (top / "dn").write_text(payload)
        archive = self.tmp / name
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(top, arcname=top.name)
        return archive.as_uri()

    def run_update(self, arch, releases):
        self.stub("id", "0")
        self.stub("uname", arch)
        api = self.tmp / "releases.json"
        api.write_text(json.dumps(releases, indent=2))
        env = dict(os.environ)
        env.update({
            "PATH": f"{self.bin}:{env['PATH']}",
            "DN_UPDATE_API": api.as_uri(),
            "DN_UPDATE_STATE": str(self.state),
            "DN_UPDATE_EVERY": "1",
            "DN_LIB": str(self.tmp / "lib"),
        })
        subprocess.run(["sh", str(SCRIPT)], env=env, check=True)

    def release(self, tag, assets):
        return {"tag_name": tag, "prerelease": True, "draft": False,
                "assets": [{"name": n, "browser_download_url": u} for n, u in assets]}

    def test_newest_v_prerelease_is_staged_and_nightly_skipped(self):
        nightly = self.asset("dn-abc-linux64.tar.gz", "nightly build")
        alpha = self.asset("dn-v2.20-alpha.1-linux64.tar.gz", "alpha build")
        self.run_update("x86_64", [
            self.release("nightly", [("dn-abc-linux64.tar.gz", nightly)]),
            self.release("v2.20-alpha.1", [("dn-v2.20-alpha.1-linux64.tar.gz", alpha)]),
        ])
        self.assertEqual((self.state / "pending" / "dn").read_text(), "alpha build")
        self.assertEqual((self.state / "pending-tag").read_text().strip(), "v2.20-alpha.1")

    def test_no_build_for_this_arch_means_no_update(self):
        x86 = self.asset("dn-v2.20-alpha.1-linux64.tar.gz", "x86 build")
        self.run_update("aarch64", [
            self.release("v2.20-alpha.1", [("dn-v2.20-alpha.1-linux64.tar.gz", x86)]),
        ])
        self.assertFalse((self.state / "pending").exists())


if __name__ == "__main__":
    unittest.main()
