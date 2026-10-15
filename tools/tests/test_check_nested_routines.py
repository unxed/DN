import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "check-nested-routines.py"


class NestedRoutineCheckTest(unittest.TestCase):
    def test_lists_only_routines_at_least_two_levels_deep(self):
        source = """unit Sample;
interface
type TCallback = procedure;
implementation
procedure Outer;
  procedure Middle;
    procedure Inner;
    begin
    end;
  begin
  end;
begin
end;
procedure Plain;
begin
end;
// procedure Fake;
""".replace("+", "")
        with tempfile.TemporaryDirectory() as temporary:
            unit = Path(temporary) / "sample.pas"
            unit.write_text(source, encoding="ascii")
            result = subprocess.run(
                ["python3", str(SCRIPT), temporary],
                check=True,
                capture_output=True,
                text=True,
            )
        self.assertIn("inner nested in middle", result.stdout.lower())
        self.assertNotIn("middle nested", result.stdout.lower())
        self.assertNotIn("fake", result.stdout.lower())


if __name__ == "__main__":
    unittest.main()
