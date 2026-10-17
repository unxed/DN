import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "check-nested-routines.py"


def run_check(source: str) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory() as temporary:
        unit = Path(temporary) / "sample.pas"
        unit.write_text(source, encoding="ascii")
        return subprocess.run(
            ["python3", str(SCRIPT), temporary],
            capture_output=True,
            text=True,
        )


class NestedRoutineCheckTest(unittest.TestCase):
    def test_block_inside_a_nested_body_does_not_hide_later_routines(self):
        # The `begin` of `if ... then begin` inside Middle must not be taken for the body of Outer.
        result = run_check("""unit Sample;
interface
implementation
procedure Outer;
  var X: Integer;
  procedure Middle;
    begin
    if X = 0 then
      begin
      X := 1;
      end;
    end;
  procedure Middle2;
    procedure Inner2;
      begin
      end;
    begin
    end;
begin
end;
end.
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("inner2 nested in middle2", result.stdout.lower())
        self.assertNotIn("middle", result.stdout.lower().replace("middle2", ""))

    def test_methods_asm_forward_and_case_in_record(self):
        result = run_check("""unit Sample;
interface
implementation
type
  TRec = record
    case Integer of
      0: (A: Integer);
      1: (B: Byte);
  end;
procedure Later; forward;
procedure TFoo.Method;
  procedure Level2;
    procedure Level3;
      asm
        nop
      end;
    begin
    case 1 of
      1: ;
    end;
    end;
  begin
  try
    Level2;
  finally
  end;
  end;
procedure Later;
begin
end;
end.
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.lower().strip().split(": ", 1)[1], "level3 nested in level2")

    def test_unbalanced_source_is_an_error(self):
        result = run_check("""unit Sample;
implementation
procedure Broken;
begin
  if True then
    begin
end.
""")
        self.assertEqual(result.returncode, 2)
        self.assertIn("unbalanced", result.stderr)

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

    def test_reads_lists_only_names_taken_from_above_the_parent(self):
        source = """unit Sample;
interface
implementation
procedure Outer(Param: Integer);
  var Top: Integer;
  procedure Middle;
    var Mid: Integer;
    procedure Far;
      var Own: Integer;
      begin
      Own := Param + Mid;
      end;
    procedure Near;
      begin
      Mid := Mid + 1;
      Rec.Top := 1;
      end;
    function Calc: Integer;
      procedure Deep;
        begin
        Calc := Top;
        end;
      begin
      Result := 0;
      end;
    begin
    end;
  begin
  end;
begin
end;
end.
"""
        with tempfile.TemporaryDirectory() as temporary:
            unit = Path(temporary) / "sample.pas"
            unit.write_text(source, encoding="ascii")
            result = subprocess.run(
                ["python3", str(SCRIPT), "--reads", temporary],
                check=True,
                capture_output=True,
                text=True,
            )
        lines = [line.split(": ", 1)[1] for line in result.stdout.lower().strip().splitlines()]
        # Far reads Param from Outer, two levels up; Near reads only Mid, its parent's, and the field `.Top`.
        # Deep reads Top from Outer and the result of Calc, its own parent's.
        self.assertEqual(lines, ["far nested in middle reads param (outer)", "deep nested in calc reads top (outer)"])


if __name__ == "__main__":
    unittest.main()
