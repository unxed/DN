{ FishFS: the file system of a remote host that is reached through a shell, over the FISH+ protocol (docs/NETWORK.md, unxed/dn#90). TFishFS is a
  TRemoteFS that speaks to a program (a shell on this machine, later ssh) through a TNetProc: it sends a small helper script to the shell, then asks
  it for lists and for the data of one path at a time, in lines of the form "<id> <command>" with the paths on lines of their own. The answers are
  lines too, the last of them carries the token of the session: it is chosen anew for every connection, so a name in a list cannot be taken for the end
  of the answer.

  The helper script is not part of the unit: Connect gets its text (dn/third-party/f4-fish/helper.sh, or the file that is installed beside the
  program as fishhelper.sh). The listings of all four tools of the helper are read: GNU find, GNU stat, BSD stat and ls (in the three ways in which ls
  prints the time; the helper reports which one it uses). A file is read in pieces of one request each (OpenRead gives a stream over them). OpenWrite truncates on open
  and sends bounded binary or base64 ranges as the caller writes. MkDir, Remove, Rename and SetMode ask the helper for the change after looking at the
  paths, so that the answers are those of TLocalFS (rrExists for a taken name, rrNotEmpty for a directory with content).

  When a request does not get its answer in time, or the shell ends, the connection is broken for good: the next answer could not be told from the
  late one. LastError tells why; make a new TFishFS to try again.

  The unit is empty in the DOS build and in DN_MINI (as NetProc is).

  MIT, see LICENSE. }
unit FishFS;

{$mode objfpc}
{$H+}

interface

{$IF NOT (DEFINED(DOS) OR DEFINED(DN_MINI))}
uses
  SysUtils, Classes, RemoteFS, NetProc;

type
  TFishFS = class(TRemoteFS)
  private
    FProc: TNetProc;
    FOwnsProc: Boolean;
    FToken: AnsiString;
    FNextId: Integer;
    FIn: AnsiString;              { what came from the shell and is not taken as lines yet, from FInPos }
    FInPos: Integer;
    FFeatures: AnsiString;        { the words of the banner, each between blanks }
    FErrTail: AnsiString;         { the last bytes of the standard error of the shell }
    FConnected: Boolean;
    FBroken: Boolean;
    FTimeoutMs: Integer;
    procedure DrainErr;
    function Broke(const Text: AnsiString): Boolean;
    function FillIn(Deadline: QWord): Boolean;
    function ReadLine(Deadline: QWord; out Line: AnsiString): Boolean;
    function ReadBytes(Deadline: QWord; Count: Integer; var Dest: AnsiString): Boolean;
    function SendRequest(const Cmd: AnsiString; const Paths: array of AnsiString; out Id: Integer): Boolean;
    function Request(const Cmd: AnsiString; const Paths: array of AnsiString; Lines: TStrings; out Status, Msg: AnsiString): Boolean;
    function Ask(const Cmd: AnsiString; const Paths: array of AnsiString; Lines: TStrings): TRemoteResult;
    function WriteRange(const Path: AnsiString; Offset: Int64; const Data: AnsiString): TRemoteResult;
  public
    { Proc is the program that talks the protocol (already started); OwnsProc: it is freed with this file system. }
    constructor Create(AProc: TNetProc; AOwnsProc: Boolean);
    destructor Destroy; override;
    { Sends the helper (the text of its script) and waits for its banner. rrOk, or rrFailed with LastError. }
    function Connect(const HelperSource: AnsiString): TRemoteResult;
    { Ends the session and the program. Safe to call again; the file system cannot be connected again after it. }
    procedure Disconnect;
    { A word of the banner of the helper, for example "base64" or "mode:find". }
    function HasFeature(const Name: AnsiString): Boolean;
    { The part after "Name:" of a word of the banner ("find" for Name "mode"), '' when there is none. }
    function FeatureValue(const Name: AnsiString): AnsiString;
    { The directory in which the remote shell was started. }
    function Pwd(out Dir: AnsiString): TRemoteResult;
    { Makes the helper list with the tool Mode ("find", "stat", "statbsd", "ls"); rrFailed when the host has not got it. }
    function SetListingMode(const Mode: AnsiString): TRemoteResult;
    function List(const Dir: AnsiString; out Entries: TRemoteEntries): TRemoteResult; override;
    function Stat(const Path: AnsiString; FollowLinks: Boolean; out Entry: TRemoteEntry): TRemoteResult; override;
    { Up to Len bytes of the file from Offset (fewer at the end of the file, none past it) in Data, and the size of the file as the helper saw it. }
    function ReadRange(const Path: AnsiString; Offset: Int64; Len: Integer; out Data: AnsiString; out FileSize: Int64): TRemoteResult;
    { A stream over the file, from its start; it asks the host for a piece of the file when a read goes past what it has, so Seek is cheap. A read that
      fails raises EReadError (LastError tells why); the stream is the caller's, free it before the file system. }
    function OpenRead(const Path: AnsiString; out Stream: TStream): TRemoteResult; override;
    function OpenWrite(const Path: AnsiString; out Stream: TStream): TRemoteResult; override;
    function MkDir(const Path: AnsiString): TRemoteResult; override;
    function Remove(const Path: AnsiString): TRemoteResult; override;
    function Rename(const OldPath, NewPath: AnsiString): TRemoteResult; override;
    function SetMode(const Path: AnsiString; Mode: LongInt): TRemoteResult; override;
    { How long one request may take, in milliseconds (the whole answer, not a byte of it); 30000 at the start. }
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;
    property Connected: Boolean read FConnected;
  end;

{ One line of a list or of an answer to a stat, in the form of the tool Mode ("find", "stat", "statbsd", or "ls " and the way of ls to print the time:
  "ls epoch", "ls iso", "ls bsd"); False when the line does not fit it. }
function ParseEntry(const Mode, Line: AnsiString; out E: TRemoteEntry): Boolean;
{$ENDIF}

implementation

{$IF NOT (DEFINED(DOS) OR DEFINED(DN_MINI))}

uses
  StrUtils, DateUtils, base64;

const
  TokenMark = '__F4_TOKEN__';
  EndMark = 'F4EOF';
  MaxNoiseLines = 1000;
  { The size of the piece of a file that is asked for at once, and the place where the pieces start: a multiple of the block size of dd. }
  ReadChunk = 262144;

{ The field of S that starts at P, up to the next blank; P moves after the blank. }
function TakeField(const S: AnsiString; var P: Integer): AnsiString;
var
  Q: Integer;
begin
  Q := P;
  while (Q <= Length(S)) and (S[Q] <> ' ') do
    Inc(Q);
  Result := Copy(S, P, Q - P);
  P := Q + 1;
end;

{ The text of the helper as it goes over the wire: the token put in, the comments, the blank lines and the indent taken away. }
function CompactHelper(const Source, Token: AnsiString): AnsiString;
var
  Lines: TStringList;
  I, B: Integer;
  S: AnsiString;
begin
  Result := '';
  Lines := TStringList.Create;
  try
    Lines.Text := StringReplace(Source, TokenMark, Token, [rfReplaceAll]);
    for I := 0 to Lines.Count - 1 do
    begin
      S := Lines[I];
      B := 1;
      while (B <= Length(S)) and (S[B] in [' ', #9]) do
        Inc(B);
      if (B > Length(S)) or (S[B] = '#') then
        Continue;
      Result := Result + Copy(S, B, Length(S)) + #10;
    end;
  finally
    Lines.Free;
  end;
end;

{ A path as a line of a request: as it is, unless a line cannot carry it (a line end in it, or the mark of the coded form at the start). }
function EncodePath(const Path: AnsiString): AnsiString;
begin
  if (Pos(#10, Path) > 0) or ((Path <> '') and (Path[1] = '~')) then
    Result := '~' + EncodeStringBase64(Path)
  else
    Result := Path;
end;

{ The result for the words of a message of the helper. }
function ResultOfMessage(const Msg: AnsiString): TRemoteResult;
var
  L: AnsiString;
begin
  L := LowerCase(Msg);
  { dash says "cannot create ...: Directory nonexistent" where bash says "No such file or directory" }
  if (Pos('no such file', L) > 0) or (Pos('not found', L) > 0) or (Pos('nonexistent', L) > 0) then
    Result := rrNotFound
  else if Pos('not a directory', L) > 0 then
    Result := rrNotDir
  else if Pos('is a directory', L) > 0 then
    Result := rrIsDir
  else if Pos('permission denied', L) > 0 then
    Result := rrDenied
  else if (Pos('file exists', L) > 0) or (Pos('already exists', L) > 0) then
    Result := rrExists
  else if Pos('not empty', L) > 0 then
    Result := rrNotEmpty
  else
    Result := rrFailed;
end;

function OctalValue(const S: AnsiString): LongInt;
var
  I: Integer;
begin
  Result := -1;
  if (S = '') or (Length(S) > 6) then
    Exit;
  Result := 0;
  for I := 1 to Length(S) do
  begin
    if not (S[I] in ['0'..'7']) then
      Exit(-1);
    Result := Result * 8 + (Ord(S[I]) - Ord('0'));
  end;
end;

{ The time of the remote clock, given as seconds since 1970 (with a fraction or not), on the clock of this machine; 0 when it is not a number. }
function EpochTime(const S: AnsiString): TDateTime;
var
  P: Integer;
  V: Int64;
begin
  P := Pos('.', S);
  if P > 0 then
    V := StrToInt64Def(Copy(S, 1, P - 1), -1)
  else
    V := StrToInt64Def(S, -1);
  if V < 0 then
    Result := 0
  else
    Result := UniversalTimeToLocal(UnixToDateTime(V));
end;

{ The next word of S from P, the blanks before it passed over; P is left at the blank after the word ('' at the end of the line). }
function TakeWord(const S: AnsiString; var P: Integer): AnsiString;
var
  Q: Integer;
begin
  while (P <= Length(S)) and (S[P] in [' ', #9]) do
    Inc(P);
  Q := P;
  while (Q <= Length(S)) and not (S[Q] in [' ', #9]) do
    Inc(Q);
  Result := Copy(S, P, Q - P);
  P := Q;
end;

function IsDigits(const S: AnsiString): Boolean;
var
  I: Integer;
begin
  Result := S <> '';
  for I := 1 to Length(S) do
    if not (S[I] in ['0'..'9']) then
      Exit(False);
end;

{ The type and the permission bits of the first word of a line of ls ("drwxr-sr-t", a mark of an attribute or an ACL after it is of no matter); -1 when it is
  not such a word. }
function LsModeBits(const S: AnsiString; out Kind: TRemoteKind): LongInt;
var
  T, I: Integer;
  Sh: LongInt;
begin
  Result := -1;
  Kind := rkOther;
  if Length(S) < 10 then
    Exit;
  case S[1] of
    'd': Kind := rkDir;
    '-': Kind := rkFile;
    'l': Kind := rkLink;
    'c', 'b', 'p', 's': Kind := rkOther;
  else
    Exit;
  end;
  for I := 2 to 10 do
    if not (S[I] in ['r', 'w', 'x', 's', 'S', 't', 'T', '-']) then
      Exit;
  Result := 0;
  for T := 0 to 2 do
  begin
    Sh := 6 - 3 * T;
    if S[2 + 3 * T] = 'r' then
      Result := Result or (4 shl Sh);
    if S[3 + 3 * T] = 'w' then
      Result := Result or (2 shl Sh);
    { the place of x is also the place of the setuid, setgid and sticky bits: a small letter is the bit and x, a capital one is the bit alone }
    case S[4 + 3 * T] of
      'x': Result := Result or (1 shl Sh);
      's', 't': Result := Result or (1 shl Sh) or (&4000 shr T);
      'S', 'T': Result := Result or (&4000 shr T);
    end;
  end;
end;

{ The time of a line of ls on the clock of this machine. Epoch: W1 is the seconds. Iso: W1 "2026-06-05", W2 "15:09:23" or "15:09:23.480954998", W3 the zone
  "+0300". Bsd: W1 the month "Jun", W2 the day, W3 "15:09:23", W4 the year; this form has no zone, so it is taken to be the zone of this machine. }
function LsTime(const Dialect, W1, W2, W3, W4: AnsiString; out T: TDateTime): Boolean;
const
  Months = 'JanFebMarAprMayJunJulAugSepOctNovDec';
var
  D, Tm: TDateTime;
  Y, Mo, Dy, H, Mi, Sc, M, ZH, ZM: Integer;
  Clock, Zone: AnsiString;
  Off: Integer;
begin
  Result := False;
  T := 0;
  if Dialect = 'epoch' then
  begin
    if not IsDigits(W1) then
      Exit;
    T := EpochTime(W1);
    Exit(True);
  end;
  if Dialect = 'iso' then
  begin
    Clock := W2;
    Zone := W3;
    if (Length(W1) <> 10) or (W1[5] <> '-') or (W1[8] <> '-') or (Length(Zone) <> 5) or not (Zone[1] in ['+', '-']) then
      Exit;
    Y := StrToIntDef(Copy(W1, 1, 4), -1);
    Mo := StrToIntDef(Copy(W1, 6, 2), -1);
    Dy := StrToIntDef(Copy(W1, 9, 2), -1);
    ZH := StrToIntDef(Copy(Zone, 2, 2), -1);
    ZM := StrToIntDef(Copy(Zone, 4, 2), -1);
    if (ZH < 0) or (ZM < 0) then
      Exit;
    Off := ZH * 60 + ZM;
    if Zone[1] = '-' then
      Off := -Off;
  end
  else if Dialect = 'bsd' then
  begin
    Clock := W3;
    M := Pos(W1, Months);
    if (Length(W1) <> 3) or (M = 0) or ((M - 1) mod 3 <> 0) or not IsDigits(W2) or not IsDigits(W4) then
      Exit;
    Y := StrToIntDef(W4, -1);
    Mo := (M - 1) div 3 + 1;
    Dy := StrToIntDef(W2, -1);
    Off := 0;
  end
  else
    Exit;
  if (Length(Clock) < 8) or (Clock[3] <> ':') or (Clock[6] <> ':') then
    Exit;
  H := StrToIntDef(Copy(Clock, 1, 2), -1);
  Mi := StrToIntDef(Copy(Clock, 4, 2), -1);
  Sc := StrToIntDef(Copy(Clock, 7, 2), -1);
  if (Y < 0) or (Mo < 0) or (Dy < 0) or (H < 0) or (Mi < 0) or (Sc < 0) then
    Exit;
  if not TryEncodeDate(Y, Mo, Dy, D) or not TryEncodeTime(H, Mi, Sc, 0, Tm) then
    Exit;
  if Dialect = 'iso' then
    T := UniversalTimeToLocal(D + Tm - Off / 1440)
  else
    T := D + Tm;
  Result := True;
end;

{ One line of ls -lan in the way Dialect (epoch, iso or bsd) prints the time. The fields before the name are a fixed number of words (ids are numbers, so
  no name of a user can be one of them): the name is all that is left after the blank that follows them, with its own blanks. The line "total ..." and the
  lines that are not a long listing are refused. }
function ParseLsEntry(const Dialect, Line: AnsiString; out E: TRemoteEntry): Boolean;
var
  P, Arrow, Slash, TimeWords: Integer;
  ModeS, LinksS, UidS, GidS, SizeS, W1, W2, W3, W4: AnsiString;
begin
  Result := False;
  W1 := '';
  W2 := '';
  W3 := '';
  W4 := '';
  if Dialect = 'epoch' then
    TimeWords := 1
  else if Dialect = 'iso' then
    TimeWords := 3
  else if Dialect = 'bsd' then
    TimeWords := 4
  else
    Exit;
  P := 1;
  ModeS := TakeWord(Line, P);
  LinksS := TakeWord(Line, P);
  UidS := TakeWord(Line, P);
  GidS := TakeWord(Line, P);
  SizeS := TakeWord(Line, P);
  E.Mode := LsModeBits(ModeS, E.Kind);
  if (E.Mode < 0) or not IsDigits(LinksS) or not IsDigits(UidS) or not IsDigits(GidS) then
    Exit;
  if (SizeS <> '') and (SizeS[Length(SizeS)] = ',') then
  begin
    { a device: "major, minor" stands where the size is }
    if not IsDigits(Copy(SizeS, 1, Length(SizeS) - 1)) or not IsDigits(TakeWord(Line, P)) then
      Exit;
    E.Size := 0;
  end
  else
  begin
    if not IsDigits(SizeS) then
      Exit;
    E.Size := StrToInt64Def(SizeS, -1);
  end;
  W1 := TakeWord(Line, P);
  if TimeWords > 1 then
    W2 := TakeWord(Line, P);
  if TimeWords > 2 then
    W3 := TakeWord(Line, P);
  if TimeWords > 3 then
    W4 := TakeWord(Line, P);
  if not LsTime(Dialect, W1, W2, W3, W4, E.MTime) then
    Exit;
  { P is at the blank after the last word: a single blank is the column gap, the rest is the name }
  if (P >= Length(Line)) or not (Line[P] in [' ', #9]) then
    Exit;
  E.Name := Copy(Line, P + 1, Length(Line));
  if E.Kind = rkLink then
  begin
    Arrow := Pos(' -> ', E.Name);
    if Arrow > 0 then
    begin
      E.LinkTarget := Copy(E.Name, Arrow + 4, Length(E.Name));
      E.Name := Copy(E.Name, 1, Arrow - 1);
    end;
  end;
  while (Length(E.Name) > 1) and (E.Name[Length(E.Name)] = '/') do
    SetLength(E.Name, Length(E.Name) - 1);
  if E.Name <> '/' then
  begin
    Slash := LastDelimiter('/', E.Name);
    E.Name := Copy(E.Name, Slash + 1, Length(E.Name));
  end;
  Result := E.Name <> '';
end;

{ One line of a list or of an answer to a stat, in the form of the tool Mode ("find", "stat", "statbsd", "ls epoch", "ls iso", "ls bsd"). False when the line
  does not fit it (a name with a line end in it shows up as two lines, the helper cannot do better). }
function ParseEntry(const Mode, Line: AnsiString; out E: TRemoteEntry): Boolean;
var
  P, Code, Slash, Arrow: Integer;
  TypeS, SizeS, MTimeS, ModeS: AnsiString;
  Bits: LongInt;
begin
  Result := False;
  E.Name := '';
  E.Kind := rkOther;
  E.Size := -1;
  E.MTime := 0;
  E.Mode := -1;
  E.LinkTarget := '';
  if Copy(Mode, 1, 3) = 'ls ' then
    Exit(ParseLsEntry(Copy(Mode, 4, Length(Mode)), Line, E));
  P := 1;
  if Mode = 'find' then
  begin
    { %y %Y %s %T@ %A@ %C@ %m %U %G %f: the type, the type of the target, the size, the three times, the permissions, the owner, the group, the name }
    TypeS := TakeField(Line, P);
    TakeField(Line, P);
    SizeS := TakeField(Line, P);
    MTimeS := TakeField(Line, P);
    TakeField(Line, P);
    TakeField(Line, P);
    ModeS := TakeField(Line, P);
    TakeField(Line, P);
    TakeField(Line, P);
    if (Length(TypeS) <> 1) or (P > Length(Line) + 1) or (SizeS = '') or (MTimeS = '') then
      Exit;
    case TypeS[1] of
      'd': E.Kind := rkDir;
      'f': E.Kind := rkFile;
      'l': E.Kind := rkLink;
    else
      E.Kind := rkOther;
    end;
    E.Name := Copy(Line, P, Length(Line));
    E.Mode := OctalValue(ModeS);
  end
  else if Mode = 'stat' then
  begin
    { %f %s %Y %X %Z %u %g %n: the type and permissions in hexadecimal, the size, the three times, the owner, the group, the name as it was asked for }
    ModeS := TakeField(Line, P);
    SizeS := TakeField(Line, P);
    MTimeS := TakeField(Line, P);
    TakeField(Line, P);
    TakeField(Line, P);
    TakeField(Line, P);
    TakeField(Line, P);
    if (ModeS = '') or (SizeS = '') or (MTimeS = '') or (P > Length(Line) + 1) then
      Exit;
    Val('$' + ModeS, Bits, Code);
    if Code <> 0 then
      Exit;
    case Bits and $F000 of
      $4000: E.Kind := rkDir;
      $8000: E.Kind := rkFile;
      $A000: E.Kind := rkLink;
    else
      E.Kind := rkOther;
    end;
    E.Mode := Bits and $FFF;
    E.Name := Copy(Line, P, Length(Line));
    Slash := LastDelimiter('/', E.Name);
    E.Name := Copy(E.Name, Slash + 1, Length(E.Name));
  end
  else if Mode = 'statbsd' then
  begin
    { %p %z %m %a %c %u %g %N: the type and permissions in octal, the size, the three times, the owner, the group, the name as it was asked for (a link
      shows as "name -> target") }
    ModeS := TakeField(Line, P);
    SizeS := TakeField(Line, P);
    MTimeS := TakeField(Line, P);
    TakeField(Line, P);
    TakeField(Line, P);
    TakeField(Line, P);
    TakeField(Line, P);
    if (ModeS = '') or (SizeS = '') or (MTimeS = '') or (P > Length(Line) + 1) then
      Exit;
    Bits := OctalValue(ModeS);
    if Bits < 0 then
      Exit;
    case Bits and $F000 of
      $4000: E.Kind := rkDir;
      $8000: E.Kind := rkFile;
      $A000: E.Kind := rkLink;
    else
      E.Kind := rkOther;
    end;
    E.Mode := Bits and $FFF;
    E.Name := Copy(Line, P, Length(Line));
    if E.Kind = rkLink then
    begin
      Arrow := Pos(' -> ', E.Name);
      if Arrow > 0 then
      begin
        E.LinkTarget := Copy(E.Name, Arrow + 4, Length(E.Name));
        E.Name := Copy(E.Name, 1, Arrow - 1);
      end;
    end;
    Slash := LastDelimiter('/', E.Name);
    E.Name := Copy(E.Name, Slash + 1, Length(E.Name));
  end
  else
    Exit;
  E.Size := StrToInt64Def(SizeS, -1);
  E.MTime := EpochTime(MTimeS);
  Result := True;
end;

{ The tool of the first line of a list ("M find" gives "find", "M ls epoch" gives "ls epoch"). }
function ModeOfLine(const Line: AnsiString; out Mode: AnsiString): Boolean;
begin
  Mode := '';
  Result := (Length(Line) > 2) and (Line[1] = 'M') and (Line[2] = ' ');
  if Result then
    Mode := Trim(Copy(Line, 3, Length(Line)));
end;

{ ParseEntry knows the tool. }
function ReadableMode(const Mode: AnsiString): Boolean;
begin
  Result := (Mode = 'find') or (Mode = 'stat') or (Mode = 'statbsd') or (Mode = 'ls epoch') or (Mode = 'ls iso') or (Mode = 'ls bsd');
end;

{ TFishFS }

constructor TFishFS.Create(AProc: TNetProc; AOwnsProc: Boolean);
begin
  inherited Create;
  FProc := AProc;
  FOwnsProc := AOwnsProc;
  FInPos := 1;
  FTimeoutMs := 30000;
end;

destructor TFishFS.Destroy;
begin
  Disconnect;
  if FOwnsProc then
    FProc.Free;
  inherited Destroy;
end;

{ Takes what the shell wrote to its standard error, so that a shell that fills the pipe is not stopped by it; the end of it is kept for the messages. }
procedure TFishFS.DrainErr;
var
  Chunk: array[0..511] of Char;
  N: Integer;
  S: AnsiString;
begin
  repeat
    N := FProc.ReadErr(Chunk, SizeOf(Chunk), 0);
    if N > 0 then
    begin
      SetString(S, PChar(@Chunk[0]), N);
      FErrTail := FErrTail + S;
      if Length(FErrTail) > 400 then
        Delete(FErrTail, 1, Length(FErrTail) - 400);
    end;
  until N <= 0;
end;

{ The connection cannot be used any more: tells it in LastError and answers False, so that the callers can pass it on. }
function TFishFS.Broke(const Text: AnsiString): Boolean;
var
  Tail: AnsiString;
begin
  FBroken := True;
  Tail := Trim(StringReplace(StringReplace(FErrTail, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Tail <> '' then
    Fail(rrFailed, Text + ' (the shell said: ' + Tail + ')')
  else
    Fail(rrFailed, Text);
  Result := False;
end;

{ Takes one more piece of what the shell wrote into FIn, waiting for it until Deadline. False (and the connection broken) when the time is over or the
  shell ended. }
function TFishFS.FillIn(Deadline: QWord): Boolean;
var
  Chunk: array[0..16383] of Char;
  N: Integer;
  Left: Int64;
begin
  Left := Int64(Deadline) - Int64(GetTickCount64);
  if Left <= 0 then
    Exit(Broke('the remote side did not answer in time'));
  if Left > 200 then
    Left := 200;
  N := FProc.Read(Chunk, SizeOf(Chunk), Integer(Left));
  DrainErr;
  if N < 0 then
    Exit(Broke('the remote shell has ended'));
  if N > 0 then
  begin
    if FInPos > 1 then
    begin
      Delete(FIn, 1, FInPos - 1);
      FInPos := 1;
    end;
    SetLength(FIn, Length(FIn) + N);
    Move(Chunk[0], FIn[Length(FIn) - N + 1], N);
  end;
  Result := True;
end;

{ The next line of the standard output of the shell, without its line end. False (and the connection broken) when the time is over or the shell ended. }
function TFishFS.ReadLine(Deadline: QWord; out Line: AnsiString): Boolean;
var
  P: SizeInt;
begin
  Line := '';
  while True do
  begin
    P := PosEx(#10, FIn, FInPos);
    if P > 0 then
    begin
      Line := Copy(FIn, FInPos, P - FInPos);
      FInPos := P + 1;
      Exit(True);
    end;
    if not FillIn(Deadline) then
      Exit(False);
  end;
end;

{ Exactly Count raw bytes from the shell, put at the end of Dest. False (and the connection broken) when they do not come. }
function TFishFS.ReadBytes(Deadline: QWord; Count: Integer; var Dest: AnsiString): Boolean;
var
  Old, Put, Have, Take: Integer;
begin
  Old := Length(Dest);
  Put := 0;
  SetLength(Dest, Old + Count);
  while Put < Count do
  begin
    Have := Length(FIn) - FInPos + 1;
    if Have > 0 then
    begin
      Take := Count - Put;
      if Take > Have then
        Take := Have;
      Move(FIn[FInPos], Dest[Old + Put + 1], Take);
      Inc(FInPos, Take);
      Inc(Put, Take);
    end
    else if not FillIn(Deadline) then
    begin
      SetLength(Dest, Old + Put);
      Exit(False);
    end;
  end;
  Result := True;
end;

{ Sends the request "<id> <Cmd>" and a line for each of the Paths; Id is the number it got. False when it could not be sent (LastError tells, the
  connection is broken unless it was not there). }
function TFishFS.SendRequest(const Cmd: AnsiString; const Paths: array of AnsiString; out Id: Integer): Boolean;
var
  I: Integer;
  Packet: AnsiString;
begin
  Result := False;
  Id := 0;
  if (not FConnected) or FBroken then
  begin
    Fail(rrFailed, 'the connection is not open');
    Exit;
  end;
  Inc(FNextId);
  Id := FNextId;
  Packet := IntToStr(Id) + ' ' + Cmd + #10;
  for I := 0 to High(Paths) do
    Packet := Packet + EncodePath(Paths[I]) + #10;
  if not FProc.Write(Packet) then
  begin
    Broke('cannot send to the remote shell');
    Exit;
  end;
  Result := True;
end;

{ Sends a request and takes the answer: the lines before the end go to Lines (when it is not nil), Status is "ok" or "err", Msg what follows it. False when
  the request could not be done at all (LastError tells, the connection is broken unless it was not there). }
function TFishFS.Request(const Cmd: AnsiString; const Paths: array of AnsiString; Lines: TStrings; out Status, Msg: AnsiString): Boolean;
var
  Id, P: Integer;
  Term, Line, Rest: AnsiString;
  Deadline: QWord;
begin
  Result := False;
  Status := '';
  Msg := '';
  if not SendRequest(Cmd, Paths, Id) then
    Exit;
  Term := '.' + FToken + ' ' + IntToStr(Id) + ' ';
  Deadline := GetTickCount64 + QWord(FTimeoutMs);
  while True do
  begin
    if not ReadLine(Deadline, Line) then
      Exit;
    if Copy(Line, 1, Length(Term)) = Term then
      Break;
    if Copy(Line, 1, Length(FToken) + 2) = '.' + FToken + ' ' then
    begin
      Broke('the answers are out of step');
      Exit;
    end;
    if Lines <> nil then
      Lines.Add(Line);
  end;
  Rest := Copy(Line, Length(Term) + 1, Length(Line));
  P := Pos(' ', Rest);
  if P = 0 then
    Status := Rest
  else
  begin
    Status := Copy(Rest, 1, P - 1);
    Msg := Copy(Rest, P + 1, Length(Rest));
  end;
  Result := True;
end;

{ Request, with the answer "err" made a result. }
function TFishFS.Ask(const Cmd: AnsiString; const Paths: array of AnsiString; Lines: TStrings): TRemoteResult;
var
  Status, Msg, Where: AnsiString;
begin
  if not Request(Cmd, Paths, Lines, Status, Msg) then
    Exit(rrFailed);
  if Status = 'ok' then
    Exit(rrOk);
  Where := '';
  if Length(Paths) > 0 then
    Where := ': ' + Paths[0];
  Result := Fail(ResultOfMessage(Msg), 'the remote side says: ' + Msg + Where);
end;

function TFishFS.Connect(const HelperSource: AnsiString): TRemoteResult;
var
  Guid: TGUID;
  Line, Marker, Hello, Rest, Verdict: AnsiString;
  Deadline: QWord;
  I, P: Integer;
  Ready, Banner: Boolean;
begin
  if FConnected then
    Exit(rrOk);
  if (FProc = nil) or FBroken then
    Exit(Fail(rrFailed, 'the connection cannot be opened'));
  if HelperSource = '' then
    Exit(Fail(rrFailed, 'the text of the helper is empty'));
  CreateGUID(Guid);
  FToken := LowerCase(StringReplace(StringReplace(StringReplace(GUIDToString(Guid), '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]), '-', '', [rfReplaceAll]));
  Deadline := GetTickCount64 + QWord(FTimeoutMs);
  { The shell parses one short line, which prints the marker and then reads the script with its own "read", up to the end mark: a shell that read the script
    off the same stream as the requests could take a request for a part of the script. The marker is written in two pieces so that a terminal that echoes
    the line cannot be taken for the shell that answers. }
  Hello := 'echo F4R"DY"' + FToken + '; F4NL=$(printf ''\nx''); F4NL=${F4NL%x}; F4S=; ' +
    'while IFS= read -r F4L; do [ "$F4L" = ' + EndMark + ' ] && break; F4S=$F4S$F4L$F4NL; done; eval "$F4S"' + #10;
  if not FProc.Write(Hello) then
  begin
    Broke('cannot send to the remote shell');
    Exit(rrFailed);
  end;
  Marker := 'F4RDY' + FToken;
  Ready := False;
  for I := 1 to MaxNoiseLines do
  begin
    if not ReadLine(Deadline, Line) then
      Exit(rrFailed);
    if Pos(Marker, Line) > 0 then
    begin
      Ready := True;
      Break;
    end;
  end;
  if not Ready then
  begin
    Broke('the remote shell does not start the helper');
    Exit(rrFailed);
  end;
  if not FProc.Write(CompactHelper(HelperSource, FToken) + EndMark + #10) then
  begin
    Broke('cannot send the helper to the remote shell');
    Exit(rrFailed);
  end;
  { The banner is looked for anywhere in a line: what the shell printed before it may have no line end. }
  Marker := '.' + FToken + ' 0 ';
  Banner := False;
  for I := 1 to MaxNoiseLines do
  begin
    if not ReadLine(Deadline, Line) then
      Exit(rrFailed);
    P := Pos(Marker, Line);
    if P > 0 then
    begin
      Rest := TrimRight(Copy(Line, P + Length(Marker), Length(Line)));
      Banner := True;
      Break;
    end;
  end;
  if not Banner then
  begin
    Broke('the helper does not answer');
    Exit(rrFailed);
  end;
  P := 1;
  Verdict := TakeField(Rest, P);
  if Verdict <> 'ok' then
  begin
    Broke('the helper refuses: ' + Copy(Rest, P, Length(Rest)));
    Exit(rrFailed);
  end;
  if (TakeField(Rest, P) <> 'FISHPLUS') or (TakeField(Rest, P) <> '1') then
  begin
    Broke('the helper speaks another protocol: ' + Rest);
    Exit(rrFailed);
  end;
  FFeatures := ' ' + Copy(Rest, P, Length(Rest)) + ' ';
  FNextId := 0;
  FConnected := True;
  Result := rrOk;
end;

procedure TFishFS.Disconnect;
var
  Status, Msg: AnsiString;
  Saved: Integer;
begin
  if (FProc <> nil) and FConnected and (not FBroken) then
  begin
    Saved := FTimeoutMs;
    FTimeoutMs := 2000;
    Request('exit', [], nil, Status, Msg);
    FTimeoutMs := Saved;
  end;
  FConnected := False;
  FBroken := True;
  if FProc <> nil then
  begin
    FProc.CloseInput;
    FProc.Stop;
  end;
end;

function TFishFS.HasFeature(const Name: AnsiString): Boolean;
begin
  Result := Pos(' ' + Name + ' ', FFeatures) > 0;
end;

function TFishFS.FeatureValue(const Name: AnsiString): AnsiString;
var
  P, Q: Integer;
begin
  Result := '';
  P := Pos(' ' + Name + ':', FFeatures);
  if P = 0 then
    Exit;
  Inc(P, Length(Name) + 2);
  Q := P;
  while (Q <= Length(FFeatures)) and (FFeatures[Q] <> ' ') do
    Inc(Q);
  Result := Copy(FFeatures, P, Q - P);
end;

function TFishFS.Pwd(out Dir: AnsiString): TRemoteResult;
var
  Lines: TStringList;
begin
  Dir := '';
  Lines := TStringList.Create;
  try
    Result := Ask('pwd', [], Lines);
    if Result <> rrOk then
      Exit;
    if Lines.Count < 1 then
      Exit(Fail(rrFailed, 'the remote shell did not tell its directory'));
    Dir := Lines[0];
  finally
    Lines.Free;
  end;
end;

function TFishFS.SetListingMode(const Mode: AnsiString): TRemoteResult;
var
  I: Integer;
begin
  if Mode = '' then
    Exit(Fail(rrFailed, 'the name of the listing tool is empty'));
  for I := 1 to Length(Mode) do
    if not (Mode[I] in ['a'..'z']) then
      Exit(Fail(rrFailed, 'not a name of a listing tool: ' + Mode));
  Result := Ask('mode ' + Mode, [], nil);
end;

function TFishFS.List(const Dir: AnsiString; out Entries: TRemoteEntries): TRemoteResult;
var
  Clean, Mode: AnsiString;
  Lines: TStringList;
  I, N: Integer;
  E: TRemoteEntry;
begin
  SetLength(Entries, 0);
  if not RemoteCleanPath(Dir, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Dir));
  Lines := TStringList.Create;
  try
    Result := Ask('enum', [Clean], Lines);
    if Result = rrNotDir then
    begin
      { the helper says "not a directory" for a path that is not there as well }
      if Stat(Clean, True, E) = rrNotFound then
        Result := Fail(rrNotFound, 'not found: ' + Dir)
      else
        Result := Fail(rrNotDir, 'not a directory: ' + Dir);
    end;
    if Result <> rrOk then
      Exit;
    if (Lines.Count < 1) or (not ModeOfLine(Lines[0], Mode)) then
      Exit(Fail(rrFailed, 'the list has no line with the tool that made it'));
    if not ReadableMode(Mode) then
      Exit(Fail(rrUnsupported, 'the remote host lists with "' + Mode + '", which is not read yet'));
    SetLength(Entries, Lines.Count);
    N := 0;
    for I := 1 to Lines.Count - 1 do
      if ParseEntry(Mode, Lines[I], E) and (E.Name <> '') and (E.Name <> '.') and (E.Name <> '..') then
      begin
        Entries[N] := E;
        Inc(N);
      end;
    SetLength(Entries, N);
    Result := rrOk;
  finally
    Lines.Free;
  end;
end;

function TFishFS.Stat(const Path: AnsiString; FollowLinks: Boolean; out Entry: TRemoteEntry): TRemoteResult;
var
  Clean, Cmd, Mode, Dir, Name: AnsiString;
  Lines: TStringList;
begin
  Entry.Name := '';
  Entry.Kind := rkOther;
  Entry.Size := -1;
  Entry.MTime := 0;
  Entry.Mode := -1;
  Entry.LinkTarget := '';
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  if FollowLinks then
    Cmd := 'info'
  else
    Cmd := 'linfo';
  Lines := TStringList.Create;
  try
    Result := Ask(Cmd, [Clean], Lines);
    if Result <> rrOk then
      Exit;
    if (Lines.Count < 2) or (not ModeOfLine(Lines[0], Mode)) then
      Exit(Fail(rrFailed, 'the answer has no line with the tool that made it'));
    if not ReadableMode(Mode) then
      Exit(Fail(rrUnsupported, 'the remote host lists with "' + Mode + '", which is not read yet'));
    if not ParseEntry(Mode, Lines[1], Entry) then
      Exit(Fail(rrFailed, 'cannot read the answer: ' + Lines[1]));
    RemoteSplit(Clean, Dir, Name);
    Entry.Name := Name;
    Result := rrOk;
  finally
    Lines.Free;
  end;
end;

function TFishFS.ReadRange(const Path: AnsiString; Offset: Int64; Len: Integer; out Data: AnsiString; out FileSize: Int64): TRemoteResult;
var
  Clean, Term, Line, Rest, Msg: AnsiString;
  Id, N, Code, P: Integer;
  Deadline: QWord;
  HaveFrame: Boolean;
begin
  Data := '';
  FileSize := -1;
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  if (Offset < 0) or (Len <= 0) then
    Exit(Fail(rrFailed, 'the range of the file is not right'));
  if not SendRequest('read ' + IntToStr(Offset) + ' ' + IntToStr(Len), [Clean], Id) then
    Exit(rrFailed);
  Term := '.' + FToken + ' ' + IntToStr(Id) + ' ';
  Deadline := GetTickCount64 + QWord(FTimeoutMs);
  HaveFrame := False;
  while True do
  begin
    if not ReadLine(Deadline, Line) then
      Exit(rrFailed);
    if Copy(Line, 1, Length(Term)) = Term then
      Break;
    if Copy(Line, 1, Length(FToken) + 2) = '.' + FToken + ' ' then
    begin
      Broke('the answers are out of step');
      Exit(rrFailed);
    end;
    if (Length(Line) > 2) and (Line[1] = 'S') and (Line[2] = ' ') then
      FileSize := StrToInt64Def(Copy(Line, 3, Length(Line)), -1)
    else if (Length(Line) > 1) and (Line[1] = '#') then
    begin
      { the frame: the bytes follow the line at once, as they are, and the end of the answer follows the last of them }
      Val(Copy(Line, 2, Length(Line)), N, Code);
      if (Code <> 0) or (N < 0) or (N > Len) or HaveFrame then
      begin
        Broke('the piece of the file is not as it was asked for');
        Exit(rrFailed);
      end;
      if not ReadBytes(Deadline, N, Data) then
        Exit(rrFailed);
      HaveFrame := True;
    end;
  end;
  Rest := Copy(Line, Length(Term) + 1, Length(Line));
  P := Pos(' ', Rest);
  if P = 0 then
  begin
    Msg := '';
    Line := Rest;
  end
  else
  begin
    Line := Copy(Rest, 1, P - 1);
    Msg := Copy(Rest, P + 1, Length(Rest));
  end;
  if Line <> 'ok' then
  begin
    Data := '';
    FileSize := -1;
    Exit(Fail(ResultOfMessage(Msg), 'the remote side says: ' + Msg + ': ' + Path));
  end;
  if (not HaveFrame) or (FileSize < 0) then
  begin
    Data := '';
    Broke('the answer to a read has no data');
    Exit(rrFailed);
  end;
  Result := rrOk;
end;

{ The encoding of the data of a "write" request for the write method the helper reports: "b64" sends one base64 line, the dd
  methods (ddbytes, ddbs1) read the bytes as they are, "raw". '' for a method this client does not know. }
function WriteEncoding(const Method: AnsiString): AnsiString;
begin
  if Method = 'b64' then
    Result := 'b64'
  else if (Method = 'ddbytes') or (Method = 'ddbs1') then
    Result := 'raw'
  else
    Result := '';
end;

function TFishFS.WriteRange(const Path: AnsiString; Offset: Int64; const Data: AnsiString): TRemoteResult;
var
  Clean, Term, Line, Status, Msg, Encoding, Payload: AnsiString;
  Id, P: Integer;
  Deadline: QWord;
  GotDataMark: Boolean;
begin
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  if (Offset < 0) or (Data = '') or (Length(Data) > ReadChunk) then
    Exit(Fail(rrFailed, 'the range of the file is not right'));
  Encoding := WriteEncoding(FeatureValue('write'));
  if Encoding = '' then
    Exit(Fail(rrUnsupported, 'the remote host cannot write files: ' + Path));
  if Encoding = 'b64' then
    Payload := EncodeStringBase64(Data) + #10
  else
    Payload := Data;
  if not SendRequest('write ' + IntToStr(Offset) + ' ' + IntToStr(Length(Data)) + ' ' + Encoding, [Clean], Id) then
    Exit(rrFailed);
  if not FProc.Write(Payload) then
  begin
    Broke('cannot send file data to the remote shell');
    Exit(rrFailed);
  end;
  Term := '.' + FToken + ' ' + IntToStr(Id) + ' ';
  Deadline := GetTickCount64 + QWord(FTimeoutMs);
  GotDataMark := False;
  while True do
  begin
    if not ReadLine(Deadline, Line) then
      Exit(rrFailed);
    if Copy(Line, 1, Length(Term)) = Term then
      Break;
    if Copy(Line, 1, Length(FToken) + 2) = '.' + FToken + ' ' then
    begin
      Broke('the answers are out of step');
      Exit(rrFailed);
    end;
    if Line = 'D' then
      GotDataMark := True;
  end;
  if not GotDataMark then
  begin
    Msg := Copy(Line, Length(Term) + 1, Length(Line));
    P := Pos(' ', Msg);
    if P = 0 then
      Msg := ''
    else
      Msg := Copy(Msg, P + 1, Length(Msg));
    if Msg <> '' then
      Broke('the remote side did not confirm receiving the file data: ' + Msg)
    else
      Broke('the remote side did not confirm receiving the file data');
    Exit(rrFailed);
  end;
  Msg := Copy(Line, Length(Term) + 1, Length(Line));
  P := Pos(' ', Msg);
  if P = 0 then
    Status := Msg
  else
  begin
    Status := Copy(Msg, 1, P - 1);
    Msg := Copy(Msg, P + 1, Length(Msg));
  end;
  if Status = 'ok' then
    Exit(rrOk);
  Result := Fail(ResultOfMessage(Msg), 'the remote side says: ' + Msg + ': ' + Path);
end;

{ The stream of OpenRead: the piece of the file that was read last is kept, a read that goes outside it asks for the piece (ReadChunk bytes, from a
  multiple of ReadChunk) that holds the place. }
type
  TFishReadStream = class(TStream)
  private
    FFS: TFishFS;
    FPath: AnsiString;
    FPos, FSize, FBufStart: Int64;
    FBuf: AnsiString;
  protected
    function GetSize: Int64; override;
  public
    constructor Create(AFS: TFishFS; const APath: AnsiString; ASize: Int64);
    function Read(var Buffer; Count: LongInt): LongInt; override;
    function Write(const Buffer; Count: LongInt): LongInt; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

constructor TFishReadStream.Create(AFS: TFishFS; const APath: AnsiString; ASize: Int64);
begin
  inherited Create;
  FFS := AFS;
  FPath := APath;
  FSize := ASize;
end;

function TFishReadStream.GetSize: Int64;
begin
  Result := FSize;
end;

function TFishReadStream.Read(var Buffer; Count: LongInt): LongInt;
var
  Start, Seen: Int64;
  Take: Integer;
  Data: AnsiString;
  Dest: PChar;
begin
  Result := 0;
  Dest := @Buffer;
  while (Count > 0) and (FPos < FSize) do
  begin
    if (FBuf = '') or (FPos < FBufStart) or (FPos >= FBufStart + Length(FBuf)) then
    begin
      Start := (FPos div ReadChunk) * ReadChunk;
      if FFS.ReadRange(FPath, Start, ReadChunk, Data, Seen) <> rrOk then
        raise EReadError.Create(FFS.LastError);
      FBuf := Data;
      FBufStart := Start;
      { the file may have grown or shrunk since it was opened: the end is where the host sees it }
      FSize := Seen;
      if FPos >= Start + Length(Data) then
      begin
        { the host has nothing at this place (the file became shorter) }
        FSize := FPos;
        Break;
      end;
    end;
    Take := Integer(FBufStart + Length(FBuf) - FPos);
    if Take > Count then
      Take := Count;
    Move(FBuf[Integer(FPos - FBufStart) + 1], Dest^, Take);
    Inc(FPos, Take);
    Inc(Dest, Take);
    Dec(Count, Take);
    Inc(Result, Take);
  end;
end;

function TFishReadStream.Write(const Buffer; Count: LongInt): LongInt;
begin
  Result := 0;
  raise EWriteError.Create('the stream of a remote file is for reading only');
end;

function TFishReadStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  case Origin of
    soBeginning: FPos := Offset;
    soCurrent: FPos := FPos + Offset;
    soEnd: FPos := FSize + Offset;
  end;
  if FPos < 0 then
    FPos := 0;
  Result := FPos;
end;

type
  TFishWriteStream = class(TStream)
  private
    FFS: TFishFS;
    FPath: AnsiString;
    FPos, FSize: Int64;
  protected
    function GetSize: Int64; override;
  public
    constructor Create(AFS: TFishFS; const APath: AnsiString);
    function Read(var Buffer; Count: LongInt): LongInt; override;
    function Write(const Buffer; Count: LongInt): LongInt; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

constructor TFishWriteStream.Create(AFS: TFishFS; const APath: AnsiString);
begin
  inherited Create;
  FFS := AFS;
  FPath := APath;
end;

function TFishWriteStream.GetSize: Int64;
begin
  Result := FSize;
end;

function TFishWriteStream.Read(var Buffer; Count: LongInt): LongInt;
begin
  Result := 0;
  raise EReadError.Create('the stream of a remote file is for writing only');
end;

function TFishWriteStream.Write(const Buffer; Count: LongInt): LongInt;
var
  Data: AnsiString;
  Dest: PByte;
  Take: Integer;
begin
  Result := 0;
  if Count < 0 then
    raise EWriteError.Create('the number of bytes to write is negative');
  if Count = 0 then
    Exit;
  if FPos > High(Int64) - Count then
    raise EWriteError.Create('the file position is too large');
  Dest := @Buffer;
  while Result < Count do
  begin
    Take := Count - Result;
    if Take > ReadChunk then
      Take := ReadChunk;
    SetLength(Data, Take);
    Move(Dest^, Data[1], Take);
    if FFS.WriteRange(FPath, FPos, Data) <> rrOk then
      raise EWriteError.Create(FFS.LastError);
    Inc(FPos, Take);
    Inc(Dest, Take);
    Inc(Result, Take);
    if FPos > FSize then
      FSize := FPos;
  end;
end;

function TFishWriteStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  case Origin of
    soBeginning: FPos := Offset;
    soCurrent: FPos := FPos + Offset;
    soEnd: FPos := FSize + Offset;
  end;
  if FPos < 0 then
    FPos := 0;
  Result := FPos;
end;

function TFishFS.OpenRead(const Path: AnsiString; out Stream: TStream): TRemoteResult;
var
  Clean, Dummy: AnsiString;
  E: TRemoteEntry;
  Size: Int64;
begin
  Stream := nil;
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  Result := Stat(Clean, True, E);
  if Result = rrUnsupported then
  begin
    { the host lists with a tool that is not read yet; the read itself tells whether the path is a file, and its answer has the size }
    E.Kind := rkFile;
    E.Size := -1;
    Result := rrOk;
  end;
  if Result <> rrOk then
    Exit;
  case E.Kind of
    rkDir: Exit(Fail(rrIsDir, 'is a directory: ' + Path));
    rkLink: Exit(Fail(rrNotFound, 'the link points to nothing: ' + Path));
    rkOther: Exit(Fail(rrFailed, 'not a regular file: ' + Path));
  end;
  Size := E.Size;
  if Size < 0 then
  begin
    Result := ReadRange(Clean, 0, 1, Dummy, Size);
    if Result <> rrOk then
      Exit;
  end;
  Stream := TFishReadStream.Create(Self, Clean, Size);
  Result := rrOk;
end;

function TFishFS.OpenWrite(const Path: AnsiString; out Stream: TStream): TRemoteResult;
var
  Clean: AnsiString;
begin
  Stream := nil;
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  if WriteEncoding(FeatureValue('write')) = '' then
    Exit(Fail(rrUnsupported, 'the remote host cannot write files: ' + Path));
  Result := Ask('trunc 0', [Clean], nil);
  if Result <> rrOk then
    Exit;
  Stream := TFishWriteStream.Create(Self, Clean);
  Result := rrOk;
end;

{ The permission bits as the octal digits the helper takes. }
function OctalText(Value: LongInt): AnsiString;
begin
  Result := '';
  repeat
    Result := Chr(Ord('0') + (Value and 7)) + Result;
    Value := Value shr 3;
  until Value = 0;
end;

function TFishFS.MkDir(const Path: AnsiString): TRemoteResult;
var
  Clean, Dir, Name: AnsiString;
  E: TRemoteEntry;
begin
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  if Clean = '/' then
    Exit(Fail(rrExists, 'already exists: ' + Path));
  { the helper makes the missing parents too (mkdir -p) and is content with a directory that is there, so both are looked at first }
  Result := Stat(Clean, False, E);
  if Result = rrOk then
    Exit(Fail(rrExists, 'already exists: ' + Path));
  if Result <> rrNotFound then
    Exit;
  RemoteSplit(Clean, Dir, Name);
  Result := Stat(Dir, True, E);
  if Result <> rrOk then
    Exit;
  if E.Kind <> rkDir then
    Exit(Fail(rrNotDir, 'not a directory: ' + Dir));
  Result := Ask('mkdir', [Clean], nil);
end;

function TFishFS.Remove(const Path: AnsiString): TRemoteResult;
var
  Clean: AnsiString;
  E: TRemoteEntry;
begin
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  if Clean = '/' then
    Exit(Fail(rrDenied, 'the root cannot be removed'));
  Result := Stat(Clean, False, E);
  if Result = rrOk then
  begin
    { rmdir tells a directory that holds something (rrNotEmpty); a link to a directory is a link and goes with rm }
    if E.Kind = rkDir then
      Result := Ask('rmdir', [Clean], nil)
    else
      Result := Ask('rm', [Clean], nil);
    Exit;
  end;
  if Result <> rrUnsupported then
    Exit;
  { the host lists with a tool that is not read yet: rm -f does not mind a missing path, so only a directory is told by its refusal }
  Result := Ask('rm', [Clean], nil);
  if Result = rrIsDir then
    Result := Ask('rmdir', [Clean], nil);
end;

function TFishFS.Rename(const OldPath, NewPath: AnsiString): TRemoteResult;
var
  OldClean, NewClean: AnsiString;
  E: TRemoteEntry;
begin
  if (not RemoteCleanPath(OldPath, OldClean)) or (not RemoteCleanPath(NewPath, NewClean)) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + OldPath));
  if (OldClean = '/') or (NewClean = '/') then
    Exit(Fail(rrDenied, 'the root cannot be renamed'));
  { mv -f replaces what is there, and moves into a directory of that name: the free name is looked at first }
  Result := Stat(OldClean, False, E);
  if Result <> rrOk then
    Exit;
  Result := Stat(NewClean, False, E);
  if Result = rrOk then
    Exit(Fail(rrExists, 'already exists: ' + NewPath));
  if Result <> rrNotFound then
    Exit;
  Result := Ask('mv', [OldClean, NewClean], nil);
end;

function TFishFS.SetMode(const Path: AnsiString; Mode: LongInt): TRemoteResult;
var
  Clean: AnsiString;
begin
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  if (Mode < 0) or (Mode > &7777) then
    Exit(Fail(rrFailed, 'the permission bits are not right: ' + Path));
  Result := Ask('chmod ' + OctalText(Mode), [Clean], nil);
end;

{$ENDIF}

end.
