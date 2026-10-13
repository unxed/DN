{ farux: the "Far UX mode" switch of DN (off by default).

  Far behaviour (panels, fast find, dialogs: iterations I2-I5 of
  docs/FARUX-PLAN.md) is enabled only while the FarUxMode setting
  ([FilePanels] in dn.ini) is on. Call sites branch through FarUxEnabled
  so the default DN behaviour stays untouched.
  Our own code (MIT, see LICENSE). }
unit farux;

interface

uses
  DnIni, Drivers;

function FarUxEnabled: Boolean;
{` True while the Far UX mode setting is on (default: False). `}

function FarFastFindChar(KeyCode: LongInt): Char;
{` In Far UX mode: the letter of an Alt+letter key for fast find
  (as in Far: hold Alt and type the start of the name), else #0.
  Alt+F-keys, Alt+Enter and Alt+Space give #0 here. `}

implementation

function FarUxEnabled: Boolean;
begin
  FarUxEnabled := FarUxMode;
end;

function FarFastFindChar(KeyCode: LongInt): Char;
var
  C: Char;
begin
  Result := #0;
  if not FarUxMode then
    Exit;
  C := Drivers.GetAltChar(KeyCode);
  if C = #$F0 then { Alt+Space is not a file-name character }
    Exit;
  Result := C;
end;

end.
