"""The contract of Better Pascal in DN (docs/BETTER-PASCAL.md, unxed/dn#87 step 2): the submodule bp/, its pin, and the unit
paths that DN_BP=1 adds in tools/dn-env.sh. Nothing here needs a compiler."""
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs/BETTER-PASCAL.md"


def upaths(extra, tmp):
    """DN_UPATHS of tools/dn-env.sh for linux64 (FPC=false: the compiler is not asked for anything that matters here)."""
    env = dict(os.environ, here=str(ROOT), DN_TARGET="linux64", FPC="false", TMPDIR=tmp)
    env.pop("DN_BP", None)
    env.pop("DN_BP_DIR", None)
    env.update(extra)
    return subprocess.run(["sh", "-c", '. "$here/tools/dn-env.sh"; printf %s "$DN_UPATHS"'], env=env,
                          capture_output=True, text=True)


class BetterPascalTests(unittest.TestCase):
    def test_submodule_is_unxed_bp(self):
        text = (ROOT / ".gitmodules").read_text(encoding="utf-8")
        self.assertRegex(text, r'\[submodule "bp"\]\n\tpath = bp\n\turl = https://github\.com/unxed/bp\n')

    def test_the_pin_is_named_in_the_contract(self):
        entry = subprocess.check_output(["git", "-C", str(ROOT), "ls-files", "-s", "--", "bp"], text=True).split()
        self.assertEqual(entry[:1], ["160000"], "bp/ must be a submodule (a gitlink)")
        self.assertIn(entry[1], DOC.read_text(encoding="utf-8"),
                      "docs/BETTER-PASCAL.md must name the commit that bp/ is pinned to")

    def test_default_build_has_no_bp_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            r = upaths({}, tmp)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("-Fu%s/bp" % ROOT, r.stdout)

    def test_dn_bp_adds_bp_safe_and_ext_and_never_fpide(self):
        with tempfile.TemporaryDirectory() as tmp:
            bp = Path(tmp) / "bpcheckout"
            (bp / "safe").mkdir(parents=True)
            (bp / "ext").mkdir()
            (bp / "bp.pas").write_text("unit BP;\n", encoding="utf-8")
            (bp / "safe/safe.pas").write_text("unit Safe;\n", encoding="utf-8")
            r = upaths({"DN_BP": "1", "DN_BP_DIR": str(bp)}, tmp)
            self.assertEqual(r.returncode, 0, r.stderr)
            words = r.stdout.split()
            for path in (bp, bp / "safe", bp / "ext"):
                self.assertIn("-Fu%s" % path, words)
        self.assertNotIn("fpide", r.stdout)

    def test_dn_bp_without_the_sources_stops(self):
        with tempfile.TemporaryDirectory() as tmp:
            r = upaths({"DN_BP": "1", "DN_BP_DIR": tmp}, tmp)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("bp.pas", r.stderr)

    @unittest.skipUnless((ROOT / "bp/bp.pas").is_file(), "the submodule bp/ is not checked out")
    def test_checked_out_bp_has_the_units_of_the_contract(self):
        bp = ROOT / "bp"
        self.assertRegex((bp / "bp.pas").read_text(encoding="utf-8"), r"(?m)^unit BP;")
        self.assertRegex((bp / "safe/safe.pas").read_text(encoding="utf-8"), r"(?m)^unit Safe;")
        self.assertTrue((bp / "ext/bpthreads.pas").is_file())
        for unit, base in ((bp / "bp.pas", bp), (bp / "safe/safe.pas", bp / "safe")):
            for inc in re.findall(r"\{\$I\s+([^}\s]+)\}", unit.read_text(encoding="utf-8")):
                with self.subTest(unit=unit.name, include=inc):
                    self.assertTrue((base / inc).is_file(), "%s includes %s, which is missing" % (unit.name, inc))
        self.assertTrue((bp / "LICENSE").is_file())


if __name__ == "__main__":
    unittest.main()
