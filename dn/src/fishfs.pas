{ FishFS: the file system of a remote host that is reached through a shell, over the FISH+ protocol (docs/NETWORK.md, unxed/dn#90). TFishFS is a
  TRemoteFS that speaks to a program (a shell on this machine, later ssh) through a TNetProc: it sends a small helper script to the shell, then asks
  it for lists and for the data of one path at a time, in lines of the form "<id> <command>" with the paths on lines of their own. The answers are
  lines too, the last of them carries the token of the session: it is chosen anew for every connection, so a name in a list cannot be taken for the end
  of the answer.

  The helper script is not part of the unit: Connect gets its text (dn/third-party/f4-fish/helper.sh, or the file that is installed beside the
  program as fishhelper.sh). The listings of the hosts that have GNU find or GNU stat are read (the helper reports which one it uses); BSD stat and
  ls are told as rrUnsupported for now. Reading and writing a file, and the changes of the tree, are the next steps: those methods answer
  rrUnsupported until then.

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
    function ReadLine(Deadline: QWord; out Line: AnsiString): Boolean;
    function Request(const Cmd: AnsiString; const Paths: array of AnsiString; Lines: TStrings; out Status, Msg: AnsiString): Boolean;
    function Ask(const Cmd: AnsiString; const Paths: array of AnsiString; Lines: TStrings): TRemoteResult;
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
    { Makes the helper list with the tool Mode ("find", "stat"); rrFailed when the host has not got it. }
    function SetListingMode(const Mode: AnsiString): TRemoteResult;
    function List(const Dir: AnsiString; out Entries: TRemoteEntries): TRemoteResult; override;
    function Stat(const Path: AnsiString; FollowLinks: Boolean; out Entry: TRemoteEntry): TRemoteResult; override;
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
{$ENDIF}

implementation

{$IF NOT (DEFINED(DOS) OR DEFINED(DN_MINI))}

uses
  StrUtils, DateUtils, base64;

const
  TokenMark = '__F4_TOKEN__';
  EndMark = 'F4EOF';
  MaxNoiseLines = 1000;

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
  if (Pos('no such file', L) > 0) or (Pos('not found', L) > 0) then
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

{ One line of a list or of an answer to a stat, in the form of the tool Mode ("find", "stat"). False when the line does not fit it (a name with a line
  end in it shows up as two lines, the helper cannot do better). }
function ParseEntry(const Mode, Line: AnsiString; out E: TRemoteEntry): Boolean;
var
  P, Code, Slash: Integer;
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
  else
    Exit;
  E.Size := StrToInt64Def(SizeS, -1);
  E.MTime := EpochTime(MTimeS);
  Result := True;
end;

{ The tool of the first line of a list ("M find", "M ls epoch"). }
function ModeOfLine(const Line: AnsiString; out Mode: AnsiString): Boolean;
var
  P: Integer;
begin
  Mode := '';
  Result := (Length(Line) > 2) and (Line[1] = 'M') and (Line[2] = ' ');
  if Result then
  begin
    P := 3;
    Mode := TakeField(Line, P);
  end;
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

{ The next line of the standard output of the shell, without its line end. False (and the connection broken) when the time is over or the shell ended. }
function TFishFS.ReadLine(Deadline: QWord; out Line: AnsiString): Boolean;
var
  P: SizeInt;
  Chunk: array[0..4095] of Char;
  N: Integer;
  Left: Int64;
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
  end;
end;

{ Sends a request and takes the answer: the lines before the end go to Lines (when it is not nil), Status is "ok" or "err", Msg what follows it. False when
  the request could not be done at all (LastError tells, the connection is broken unless it was not there). }
function TFishFS.Request(const Cmd: AnsiString; const Paths: array of AnsiString; Lines: TStrings; out Status, Msg: AnsiString): Boolean;
var
  Id, I, P: Integer;
  Packet, Term, Line, Rest: AnsiString;
  Deadline: QWord;
begin
  Result := False;
  Status := '';
  Msg := '';
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
    if (Mode <> 'find') and (Mode <> 'stat') then
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
    if (Mode <> 'find') and (Mode <> 'stat') then
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

function TFishFS.OpenRead(const Path: AnsiString; out Stream: TStream): TRemoteResult;
begin
  Stream := nil;
  Result := Fail(rrUnsupported, 'reading a file is not done yet: ' + Path);
end;

function TFishFS.OpenWrite(const Path: AnsiString; out Stream: TStream): TRemoteResult;
begin
  Stream := nil;
  Result := Fail(rrUnsupported, 'writing a file is not done yet: ' + Path);
end;

function TFishFS.MkDir(const Path: AnsiString): TRemoteResult;
begin
  Result := Fail(rrUnsupported, 'making a directory is not done yet: ' + Path);
end;

function TFishFS.Remove(const Path: AnsiString): TRemoteResult;
begin
  Result := Fail(rrUnsupported, 'removing is not done yet: ' + Path);
end;

function TFishFS.Rename(const OldPath, NewPath: AnsiString): TRemoteResult;
begin
  Result := Fail(rrUnsupported, 'renaming is not done yet: ' + OldPath);
end;

function TFishFS.SetMode(const Path: AnsiString; Mode: LongInt): TRemoteResult;
begin
  Result := Fail(rrUnsupported, 'setting the permissions is not done yet: ' + Path);
end;

{$ENDIF}

end.
