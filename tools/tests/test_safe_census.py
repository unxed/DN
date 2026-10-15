import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("safe_census", ROOT / "tools/safe-census.py")
safe_census = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(safe_census)


class SafeCensusTests(unittest.TestCase):
    def test_counts_rules_and_ignores_comments_and_strings(self):
        source = """
        unit Sample;
        interface
        type
          TThing = object end;
          TBox = class end;
        implementation
        procedure Test;
        begin
          GetMem(P, 4); FreeMem(P); New(P); Dispose(P);
          Move(A, B, 1); FillChar(B, 1, 0);
          Obj.Free; Obj.Destroy; FreeAndNil(Obj);
          X: Pointer; Y: PByte; Z: ^Integer; @Value;
          S: ShortString; W: WideString; U: UnicodeString; N: String[10];
          { GetMem(X, 1); } (* Move(X, Y, 1); *) // Obj.Free
          Text := 'Dispose(X); Pointer; ShortString';
        end;
        """
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path = root / "sample.pas"
            path.write_text(source, encoding="utf-8")
            result = safe_census.count_file(path, root)
        self.assertEqual({rule: result[rule] for rule in safe_census.RULES},
                         {"S1": 4, "S2": 2, "S3": 3, "S4": 4, "S9": 4})
        self.assertEqual((result["objects"], result["classes"]), (1, 1))

    def test_census_aggregates_units(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for directory in safe_census.SOURCE_DIRS:
                (root / directory).mkdir(parents=True)
            (root / "dn/src/a.pas").write_text("unit A; begin New(P) end.", encoding="utf-8")
            (root / "tv/src/b.pas").write_text("unit B; begin Move(A, B, 1) end.", encoding="utf-8")
            report = safe_census.census(root)
        self.assertEqual(report["totals"]["units"], 2)
        self.assertEqual(report["totals"]["S1"], 1)
        self.assertEqual(report["totals"]["S2"], 1)
        self.assertEqual([unit["file"] for unit in report["closest_to_safe"]], ["dn/src/a.pas", "tv/src/b.pas"])


if __name__ == "__main__":
    unittest.main()
