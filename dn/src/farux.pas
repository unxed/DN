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

type
  TFarUxKeyHook = function(var Event: TEvent): Boolean;
{` A key of the Far UX mode that is dealt with before the status line sees it: it returns True when the key is used up. `}

var
  FarUxEarlyKey: TFarUxKeyHook;
{` Set by the application loop (apploop.pas); TProgram.GetEvent calls it before the status line, which turns some
  Ctrl+function keys into commands of its own (Ctrl+F3 is "create panel"). nil: no such keys. `}

function FarFastFindChar(KeyCode: LongInt): Char;
{` In Far UX mode: the letter of an Alt+letter key for fast find
  (as in Far: hold Alt and type the start of the name), else #0.
  Alt+F-keys, Alt+Enter and Alt+Space give #0 here. `}

function FarCtrlGrayKey(KeyCode: LongInt; VirtualKey: Word): Char;
{` In Far UX mode: '+', '-' or '*' for Ctrl with a gray key of the numpad,
  else #0. KeyCode is in the form of DN (DNKeyCode), VirtualKey is the
  Windows VK_* code of the event (0 if the terminal does not tell it).
  The BIOS codes (kbCtrlGPlus...) carry the numpad scan; a terminal gives
  the character with pure Ctrl and no scan: it counts unless VirtualKey
  names another key (Ctrl with '-' of the main keyboard is VK_OEM_MINUS). `}

implementation

uses
  Commands;

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

function FarCtrlGrayKey(KeyCode: LongInt; VirtualKey: Word): Char;
const
  VkMultiply = $6A;
  VkAdd = $6B;
  VkSubtract = $6D;
var
  C: Char;
  Vk: Word;
begin
  Result := #0;
  if not FarUxMode then
    Exit;
  case KeyCode of
    kbCtrlGPlus: Exit('+');
    kbCtrlGMinus: Exit('-');
    kbCtrlGAst: Exit('*');
  end;
  if (KeyCode shr 16) <> 4 then { pure Ctrl }
    Exit;
  if (KeyCode and $FF00) <> 0 then
    Exit;
  C := Char(KeyCode and $FF);
  case C of
    '+': Vk := VkAdd;
    '-': Vk := VkSubtract;
    '*': Vk := VkMultiply;
  else
    Exit;
  end;
  if (VirtualKey = 0) or (VirtualKey = Vk) then
    Result := C;
end;

end.
