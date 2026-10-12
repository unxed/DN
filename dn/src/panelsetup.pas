{AK155 = Alexey Korop, 2:461/155@fidonet}

unit panelsetup;
  { types and variables related to file panels and
    drives inserted into them }

{$I stdefine.inc}

interface

uses
  Commands;

type
  TPanelShowSetup = record
  {` Data block for the panel view settings dialog dlgPanelShowSetup }
    ColumnsMask: Word; {Checkbox[11]}
    DirRegister: Word; {Combo}
    FileRegister: Word; {Combo}
    LFNLen: String[3];
    EXTLen: String[3];
    TabulateExt: Word; {Combo}
    NoTabulateDirExt: Word; {Checkbox[1]}
    ShowCurFile: Word; {Checkbox[1]}
    CurFileNameType: Word; {Combo}
    SelectedInfo: Word; {Combo}
    FilterInfo: Word; {Combo}
    PathDescrInfo: Word; {Combo}
    PackedSizeInfo: Word; {Combo}
    BriefPercentInfo: Word; {Combo}
    LFN_InFooter: Word; {Combo}
    TotalsInfo: Word; {Combo}
    FreeSpaceInfo: Word; {Combo}
    MiscOptions: Word; {` Checkbox[2]: ZoomPanel, ShowTitles `}
    Columns: String[1];
      {` InputLine: the number of columns of names, '1'..'9'; '' or '0': as many
        as the width of the name lets in (dn#19). See FixedColumns `}
    end;
  {`}

  TOldPanelShowSetup = record
  {` TPanelShowSetup before Columns: the presets of a configuration saved before it
    are read into it (boot.pas, cfgPanSetupPreset) and moved over `}
    ColumnsMask: Word;
    DirRegister: Word;
    FileRegister: Word;
    LFNLen: String[3];
    EXTLen: String[3];
    TabulateExt: Word;
    NoTabulateDirExt: Word;
    ShowCurFile: Word;
    CurFileNameType: Word;
    SelectedInfo: Word;
    FilterInfo: Word;
    PathDescrInfo: Word;
    PackedSizeInfo: Word;
    BriefPercentInfo: Word;
    LFN_InFooter: Word;
    TotalsInfo: Word;
    FreeSpaceInfo: Word;
    MiscOptions: Word;
    end;

  TPanelSortSetup = record
  {` Data block for the panel sort settings dialog dlgPanelSortSetup }
    SortMode: Word;
    SortFlags: Word;
    Ups: array[1..4] of Word;
    CompareMethod: Word;
    end;
  {`}

  PPanelSetup = ^TPanelSetup;
  {`2 Panel settings block }
  TPanelSetup = record
    Show: TPanelShowSetup;
    Sort: TPanelSortSetup;
    FileMask: String;
    end;
  {`}

  TPanelClass = (pcDisk, pcList, pcArc, pcArvid);
    {` File panel classes, each of which has
     its own settings block of type TPanelSetup `}

  PPanelSetupSet = ^TPanelSetupSet;
    {`2 full set of settings for all panel classes }
  TPanelSetupSet = array[TPanelClass] of TPanelSetup;
  {`}

  TOldPanelSetup = record
    Show: TOldPanelShowSetup;
    Sort: TPanelSortSetup;
    FileMask: String;
    end;
  TOldPanelSetupPresets = array[1..10] of array[TPanelClass] of TOldPanelSetup;

  TDriveType = (dtUndefined, dtDisk, dtFind, dtTemp, dtList, dtArcFind,
       dtArc, dtNet, dtLink, dtArvid);

var
  PanSetupPreset: array[1..10] of TPanelSetupSet;
    {` 10 settings blocks selected via Ctrl-digit `}

const
  dt2pc: array[TDriveType] of TPanelClass =
    (pcDisk, pcDisk, pcList, pcList, pcList, pcList,
     pcArc, pcDisk, pcDisk, pcArvid);

const // Values

  cfnTypeOther = 0;
    {` CurFileNameType value "Not the same as in the panel" `}
  cfnAlwaysLong = 1;

  cfnHide = cfnAlwaysLong+1;
    {` CurFileNameType value "Do not show" `}

type
  TFileColWidht = array[TFileColNumber] of ShortInt;
    {` Column widths (except name).
      For unlimited-width columns (path, description) width is -1.
      For the time column, whose width depends on country settings,
    width is artificially -2 (actually 6 for 24-hour and 7 for
    12-hour format).
      Consistency is required:
       - of the order of values in this array,
       - of bit masks like psShowDescript,
       - of the functions that form the corresponding strings in columns
         (GetFull, MakeDate, FileSizeStr).
      This also means that all same-type columns (dates and times)
    have the same width.
     `}
  TFileColAllowed = array [TFileColNumber] of Boolean;
    {` Whether columns are allowed for the given panel type `}

const
  FileColWidht: TFileColWidht =
{Size  PSize Ratio Date Time CrDate CrTime LaDate LaTime Descr Path}
 (10,  11,   4,    9,   -2,  9,     -2,    9,     -2,    -1,   -1);

  PanelFileColAllowed: array[TPanelClass] of TFileColAllowed =
  ( {pcDisk}
 (True, False,False, True,True,True, True, True,  True,  True,  False)
  , {pcList}
 (True, False,False, True,True,True, True, True,  True,  False, True)
  , {pcArc}
 (True, True, True, True,True,False,False,False, False, False, False)
  , {pcArvid}
 (True, False,False, True,True,False,False,False, False, True,  False)
  );

procedure DefaultInit;
{` I was too lazy to write out structured constants with all
settings of all modes, so I dragged the old column
settings here as an auxiliary constant, and filled the presets
with the DefaultInit program. Now it is called only at
initialization, but eventually its call could be made via
(a new) "Restore defaults" command. `}

{ The presets of a configuration saved before the field Columns, moved into PanSetupPreset (no fixed number of columns). }
procedure PresetsFromOld(const Old: TOldPanelSetupPresets);

{ The number of columns of names the setting asks for, 1..9; 0 when it is empty or "0": as many as fit (dn#19). }
function FixedColumns(const Show: TPanelShowSetup): Integer;

{ The sort of all the preset panels by a name from dn.ini (name, ext, size, date, unsorted; any case); another name changes nothing. }
procedure ApplyDefaultSortMode(const Mode: String);

implementation

const
  ColumnsDefaults: array[TPanelClass] of array[1..10] of
    record
      Param: Word;
      LFNLen: String[3];
      EXTLen: String[3];
      end =
  (
(*
  psShowSize = $0001;
  psShowDate = $0002;
  psShowTime = $0004;
  psShowCrDate = $0008;
  psShowCrTime = $0010;
  psShowLADate = $0020;
  psShowLATime = $0040;
  psShowDescript = $0080;
  psShowDir = $0100;
  psShowPacked = $0200;
  psShowRatio = $0400;
*)
//  ColumnsDefaultsDisk1
    ((Param: 0; LFNLen: '12'; EXTLen: '3'),
     (Param: $7FF; LFNLen: '12'; EXTLen: '3'),
     (Param: 0; LFNLen: '18'; EXTLen: '4'),
     (Param: 0; LFNLen: '18'; EXTLen: '0'),
     (Param: 0; LFNLen: '38'; EXTLen: '4'),
     (Param: 0; LFNLen: '252'; EXTLen: '0'),
     (Param: psShowSize; LFNLen: '252'; EXTLen: '0'),
     (Param: psShowDescript; LFNLen: '12'; EXTLen: '3'),
     (Param: 0; LFNLen: '12'; EXTLen: '3'),
     (Param: 0; LFNLen: '12'; EXTLen: '3')
    ),

//  ColumnsDefaultsFind
    ((Param: psShowDir; LFNLen: '12'; EXTLen: '3'),
     (Param: $7FF; LFNLen: '12'; EXTLen: '3'),
     (Param: 0; LFNLen: '18'; EXTLen: '4'),
     (Param: 0; LFNLen: '18'; EXTLen: '0'),
     (Param: 0; LFNLen: '38'; EXTLen: '4'),
     (Param: 0; LFNLen: '252'; EXTLen: '0'),
     (Param: psShowSize; LFNLen: '252'; EXTLen: '0'),
     (Param: psShowDir; LFNLen: '12'; EXTLen: '3'),
     (Param: 0; LFNLen: '12'; EXTLen: '3'),
     (Param: 0; LFNLen: '12'; EXTLen: '3')
    ),

//  ColumnsDefaultsArch
    ((Param: 0; LFNLen: '12'; EXTLen: '3'),
     (Param: $7FF; LFNLen: '12'; EXTLen: '3'),
     (Param: 0; LFNLen: '18'; EXTLen: '4'),
     (Param: 0; LFNLen: '18'; EXTLen: '0'),
     (Param: 0; LFNLen: '38'; EXTLen: '4'),
     (Param: 0; LFNLen: '252'; EXTLen: '0'),
     (Param: psShowSize+psShowPacked+psShowRatio;
        LFNLen: '252'; EXTLen: '0'),
     (Param: psShowSize+psShowPacked+psShowRatio;
        LFNLen: '12'; EXTLen: '3'),
     (Param: psShowRatio; LFNLen: '12'; EXTLen: '3'),
     (Param: 0; LFNLen: '12'; EXTLen: '3')
    ),

//  ColumnsDefaultsArvd:
    ((Param: 0; LFNLen: '12'; EXTLen: '3'),
     (Param: $7FF; LFNLen: '12'; EXTLen: '3'),
     (Param: 0; LFNLen: '18'; EXTLen: '4'),
     (Param: 0; LFNLen: '18'; EXTLen: '0'),
     (Param: 0; LFNLen: '38'; EXTLen: '4'),
     (Param: 0; LFNLen: '252'; EXTLen: '0'),
     (Param: psShowSize; LFNLen: '252'; EXTLen: '0'),
     (Param: psShowDescript; LFNLen: '12'; EXTLen: '3'),
     (Param: 0; LFNLen: '12'; EXTLen: '3'),
     (Param: 0; LFNLen: '12'; EXTLen: '3')
    )
  );

procedure PresetsFromOld(const Old: TOldPanelSetupPresets);
  var
    i: Integer;
    pc: TPanelClass;
  begin
  for i := 1 to 10 do
    for pc := Low(TPanelClass) to High(TPanelClass) do
      begin
      Move(Old[i][pc].Show, PanSetupPreset[i][pc].Show, SizeOf(TOldPanelShowSetup));
      PanSetupPreset[i][pc].Show.Columns := '';
      PanSetupPreset[i][pc].Sort := Old[i][pc].Sort;
      PanSetupPreset[i][pc].FileMask := Old[i][pc].FileMask;
      end;
  end;

function FixedColumns(const Show: TPanelShowSetup): Integer;
  begin
  if (Length(Show.Columns) = 1) and (Show.Columns[1] in ['1'..'9']) then
    Result := Ord(Show.Columns[1])-Ord('0')
  else
    Result := 0;
  end;

procedure DefaultInit;
  var
    i: Integer;
    pc: TPanelClass;
  begin
  FillChar(PanSetupPreset, SizeOf(PanSetupPreset), 0);
  for i := 1 to 10 do
    for pc := Low(TPanelClass) to High(TPanelClass) do
      with PanSetupPreset[i][pc] do
        begin
        FileMask := '*.*';
        Show.ColumnsMask  := ColumnsDefaults[pc][i].Param
            or psLFN_InColumns  ;
        Show.LFNLen := ColumnsDefaults[pc][i].LFNLen;
        Show.ExtLen := ColumnsDefaults[pc][i].ExtLen;
        if Show.ColumnsMask <> 0 then
          Show.MiscOptions := 2; { column headers }

        Show.TabulateExt := 3; {Always}
        Show.FilterInfo := fseInDivider;
        Show.ShowCurFile := 1;
        Show.SelectedInfo := fseInDivider;
        Sort.SortMode := psmLongExt;
        Sort.CompareMethod := 2; { lowercase }
        Sort.Ups[1] := upsDirs;
        end;
  end;

procedure ApplyDefaultSortMode(const Mode: String);
  var
    i: Integer;
    pc: TPanelClass;
    M: Integer;
    S: String;
  begin
  S := LowerCase(Mode);
  if S = 'name' then M := psmLongName
  else if S = 'ext' then M := psmLongExt
  else if S = 'size' then M := psmSize
  else if (S = 'date') or (S = 'time') then M := psmTime
  else if S = 'unsorted' then M := psmUnsorted
  else
    Exit;
  for i := 1 to 10 do
    for pc := Low(TPanelClass) to High(TPanelClass) do
      PanSetupPreset[i][pc].Sort.SortMode := M;
  end;

begin
DefaultInit;
end.

