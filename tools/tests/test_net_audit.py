import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/net-audit.sh"


def audit(root):
    return subprocess.run(["sh", str(SCRIPT), str(root)], capture_output=True, text=True)


def make_tree(root, files):
    for name in ("dn/src", "dn/compat", "tools"):
        (root / name).mkdir(parents=True, exist_ok=True)
    for name, text in files.items():
        (root / name).write_text(text, encoding="utf-8")


class NetAuditTests(unittest.TestCase):
    def test_repository_has_no_unlisted_network_code(self):
        result = audit(ROOT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_clean_tree(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            make_tree(root, {"dn/src/a.pas": "unit A; // see https://github.com/unxed/dn\ninterface\nimplementation\nend.\n"})
            result = audit(root)
        self.assertEqual(result.returncode, 0)
        self.assertIn("no network code", result.stdout)

    def test_socket_unit_is_found(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            make_tree(root, {"dn/compat/net.pas": "unit Net;\ninterface\nuses Sockets;\nimplementation\nend.\n"})
            result = audit(root)
        self.assertEqual(result.returncode, 1)
        self.assertIn("dn/compat/net.pas", result.stdout + result.stderr)

    def test_listed_file_is_allowed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            make_tree(root, {
                "dn/src/ftpfs.pas": "unit FtpFs;\ninterface\nuses ssockets;\nimplementation\nend.\n",
                "tools/net-audit.allow": "# the FTP client\ndn/src/ftpfs.pas  # step 11\n",
            })
            result = audit(root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("allowed", result.stdout)

    def test_missing_source_directory_is_an_error(self):
        with tempfile.TemporaryDirectory() as temp:
            result = audit(Path(temp))
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
