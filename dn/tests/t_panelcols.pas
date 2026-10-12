{$mode objfpc}{$H-}
program t_panelcols;
{ panelsetup.pas, dn#19: the field Columns of the panel appearance (a fixed number of columns of names) and the presets of a
  configuration saved before it, which are moved over with every other field kept and no fixed number of columns. }
uses Defines, panelsetup;
{$I dntest.inc}
var
  Show: TPanelShowSetup;
  Old: TOldPanelSetupPresets;
  i: Integer;
  pc: TPanelClass;
  Same: Boolean;
begin
  FillChar(Show, SizeOf(Show), 0);
  Check(FixedColumns(Show) = 0, 'empty: as many as fit');
  Show.Columns := '0';
  Check(FixedColumns(Show) = 0, '"0": as many as fit');
  Show.Columns := '2';
  Check(FixedColumns(Show) = 2, '"2": two columns');
  Show.Columns := '9';
  Check(FixedColumns(Show) = 9, '"9": nine columns');
  Show.Columns := 'x';
  Check(FixedColumns(Show) = 0, 'not a digit: as many as fit');

  { the block of the old configuration is shorter by the field Columns in each of the 40 setups }
  Check(SizeOf(PanSetupPreset) - SizeOf(Old) = 10 * (Ord(High(TPanelClass)) + 1) * SizeOf(Show.Columns),
    'the old block differs by the field Columns only');

  FillChar(Old, SizeOf(Old), 0);
  for i := 1 to 10 do
    for pc := Low(TPanelClass) to High(TPanelClass) do
      with Old[i][pc] do
      begin
        Show.ColumnsMask := i * 10 + Ord(pc);
        Show.LFNLen := '18';
        Show.MiscOptions := 2;
        Sort.SortMode := i;
        FileMask := '*.txt';
      end;
  FillChar(PanSetupPreset, SizeOf(PanSetupPreset), $FF);
  PresetsFromOld(Old);
  Same := True;
  for i := 1 to 10 do
    for pc := Low(TPanelClass) to High(TPanelClass) do
      with PanSetupPreset[i][pc] do
        Same := Same and (Show.ColumnsMask = i * 10 + Ord(pc)) and (Show.LFNLen = '18') and (Show.MiscOptions = 2)
          and (Sort.SortMode = i) and (FileMask = '*.txt') and (FixedColumns(Show) = 0);
  Check(Same, 'the old presets are moved over field by field, without a fixed number of columns');
  Finish;
end.
