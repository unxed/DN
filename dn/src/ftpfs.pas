{ FtpFS: the file system of a remote host over FTP (docs/NETWORK.md, unxed/dn#90 step 11). This part reads the listings that an FTP server sends:

  - the lines of MLSD and MLST (RFC 3659): facts "name=value;" and the name after one blank. The facts are told in any case; type, size, modify
    (UTC), unix.mode and the link type of Unix servers (OS.unix=slink:<target>, OS.unix=symlink) are taken, the others are left;
  - the lines of LIST, which has no standard form: the one of "ls -l" (most servers), the one of DOS and IIS ("02-03-20  04:05PM  <DIR>  name")
    and the one of NetWare ("d [RWCEAFMS] owner 512 Feb 03 04:05 name"). The times of LIST are in the zone of the server, which is not told:
    they are taken as times of this machine. A date of "ls -l" with a time and no year is of the last months: the year is the one that does not
    put it more than a day after Now.

  TFtpFS is the TRemoteFS over a connection to a server: the control channel (a reply is "<code> text", or lines from "<code>-" to "<code> "), a
  data connection for each listing in passive mode (EPSV, PASV when the server has not got it; the address is the one of the control channel, as
  a server behind NAT often tells an inner one), TYPE I, FEAT, UTF8 when the server has it. List asks MLSD and falls back to LIST after CWD (an
  argument of LIST is taken for a mask by some servers); Stat asks MLST, or finds the name in the list of the directory. OpenRead is a stream over
  RETR (a Seek elsewhere ends the transfer with ABOR and starts it again with REST); OpenWrite is a stream over STOR, which writes the file from
  its start to its end. While a stream is open the control channel is its own, and the other requests fail until it is freed. MkDir (MKD),
  Remove (DELE, RMD), Rename (RNFR, RNTO) and SetMode (SITE CHMOD, which not every server has) look at the paths first, so that the answers are
  those of TLocalFS whatever the server says (rrExists for a taken name, rrNotEmpty for a directory with content).

  When a reply does not come in time, or the server closes the control channel, the connection is broken for good: the next reply could not be
  told from the late one. LastError tells why; make a new TFtpFS to try again.

  The unit is empty in the DOS build and in DN_MINI (as NetProc is).

  MIT, see LICENSE. }
unit FtpFS;

{$mode objfpc}
{$H+}

interface

{$IF NOT (DEFINED(DOS) OR DEFINED(DN_MINI))}
uses
  SysUtils, Classes, ssockets, RemoteFS;

type
  TFtpFS = class(TRemoteFS)
  private
    FCtl: TInetSocket;
    FHost: AnsiString;
    FIn: AnsiString;              { what came on the control channel and is not taken as lines yet, from FInPos }
    FInPos: Integer;
    FFeatures: TStringList;       { the lines of the answer to FEAT, each without its leading blank, in capitals up to the first blank }
    FConnected: Boolean;
    FBroken: Boolean;
    FUseMlsd: Boolean;
    FUseEpsv: Boolean;
    FTimeoutMs: Integer;
    FReplyCode: Integer;
    FReplyText: AnsiString;
    FBusy: Boolean;               { a stream of a file has the control channel }
    function Broke(const Text: AnsiString): Boolean;
    function RecvSome(Sock: TInetSocket; Buf: Pointer; Size: Integer; Deadline: QWord): Integer;
    function ReadSome(Sock: TInetSocket; Deadline: QWord; var Data: AnsiString): Integer;
    function ReadLine(Deadline: QWord; out Line: AnsiString): Boolean;
    function ReadReply(Lines: TStrings): Boolean;
    function Command(const Cmd: AnsiString; Lines: TStrings = nil): Boolean;
    function ReplyResult(const Path: AnsiString): TRemoteResult;
    function OpenData(out Data: TInetSocket): TRemoteResult;
    function Transfer(const Cmd, Path: AnsiString; out Text: AnsiString): TRemoteResult;
    function ListLines(const Dir: AnsiString; out Lines: TStringList; out Machine: Boolean): TRemoteResult;
    function MlstEntry(const Path: AnsiString; out Entry: TRemoteEntry): TRemoteResult;
    function FindInParent(const Path: AnsiString; out Entry: TRemoteEntry): TRemoteResult;
    function StartData(const Cmd, Path: AnsiString; out Data: TInetSocket): TRemoteResult;
    function EndData(var Data: TInetSocket; const Path: AnsiString): TRemoteResult;
    procedure AbortData(var Data: TInetSocket);
    function SendAll(Sock: TInetSocket; Buf: Pointer; Size: Integer): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    { Connects to Host:Port and logs in (User "anonymous" with any password for an open server). rrOk; rrDenied when the login is refused;
      rrFailed with LastError otherwise. }
    function Connect(const Host: AnsiString; Port: Word; const User, Password: AnsiString): TRemoteResult;
    { Sends QUIT and closes the connection. Safe to call again; the file system cannot be connected again after it. }
    procedure Disconnect;
    { The directory in which the server put the session (PWD). }
    function Pwd(out Dir: AnsiString): TRemoteResult;
    { A line of the answer to FEAT, by its first word ("MLST", "UTF8", "EPSV"). }
    function HasFeature(const Name: AnsiString): Boolean;
    function List(const Dir: AnsiString; out Entries: TRemoteEntries): TRemoteResult; override;
    function Stat(const Path: AnsiString; FollowLinks: Boolean; out Entry: TRemoteEntry): TRemoteResult; override;
    { A stream over the file from its start (RETR). A read that fails raises EReadError (LastError tells why); free the stream before the other
      requests and before the file system. }
    function OpenRead(const Path: AnsiString; out Stream: TStream): TRemoteResult; override;
    { A stream that writes the file from its start to its end (STOR); Seek can only tell the place. A write that fails raises EWriteError; the reply
      to the transfer is read when the stream is freed, a refusal is left in LastError. }
    function OpenWrite(const Path: AnsiString; out Stream: TStream): TRemoteResult; override;
    function MkDir(const Path: AnsiString): TRemoteResult; override;
    function Remove(const Path: AnsiString): TRemoteResult; override;
    function Rename(const OldPath, NewPath: AnsiString): TRemoteResult; override;
    function SetMode(const Path: AnsiString; Mode: LongInt): TRemoteResult; override;
    { How long one reply (or one listing) may take, in milliseconds; 30000 at the start. }
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;
    property Connected: Boolean read FConnected;
    { List asks MLSD while this is True (it is set at Connect when the server tells MLST in its FEAT); False: LIST. }
    property UseMlsd: Boolean read FUseMlsd write FUseMlsd;
    { The code and the text of the last reply of the server. }
    property ReplyCode: Integer read FReplyCode;
    property ReplyText: AnsiString read FReplyText;
  end;

{ One line of an answer to MLSD, or the line of an answer to MLST without its leading blank. False for a line that is not one, and for the entries of
  the directory itself and of its parent (type cdir and pdir). }
function FtpParseMlsx(const Line: AnsiString; out E: TRemoteEntry): Boolean;
{ One line of an answer to LIST, in one of the forms of the head of the unit. Now is the time of this machine (for the year of a date without one).
  False for a line that is none of them ("total 12", an empty line). }
function FtpParseList(const Line: AnsiString; Now: TDateTime; out E: TRemoteEntry): Boolean;
{$ENDIF}

implementation

{$IF NOT (DEFINED(DOS) OR DEFINED(DN_MINI))}

uses
  StrUtils, DateUtils, Math;

const
  MonthNames: array[1..12] of AnsiString = ('jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec');

type
  { The words of a line apart by blanks, with the place where each one starts and the place after its end. }
  TWords = record
    Text: array of AnsiString;
    First, After: array of Integer;
    Count: Integer;
  end;

procedure SplitWords(const S: AnsiString; out W: TWords);
var
  P, Q: Integer;
begin
  W.Count := 0;
  SetLength(W.Text, 0);
  SetLength(W.First, 0);
  SetLength(W.After, 0);
  P := 1;
  while True do
  begin
    while (P <= Length(S)) and (S[P] in [' ', #9]) do
      Inc(P);
    if P > Length(S) then
      Break;
    Q := P;
    while (Q <= Length(S)) and (not (S[Q] in [' ', #9])) do
      Inc(Q);
    if W.Count >= Length(W.Text) then
    begin
      SetLength(W.Text, W.Count + 16);
      SetLength(W.First, W.Count + 16);
      SetLength(W.After, W.Count + 16);
    end;
    W.Text[W.Count] := Copy(S, P, Q - P);
    W.First[W.Count] := P;
    W.After[W.Count] := Q;
    Inc(W.Count);
    P := Q;
  end;
end;

procedure ClearEntry(out E: TRemoteEntry);
begin
  E.Name := '';
  E.Kind := rkOther;
  E.Size := -1;
  E.MTime := 0;
  E.Mode := -1;
  E.LinkTarget := '';
end;

function AllDigits(const S: AnsiString): Boolean;
var
  I: Integer;
begin
  Result := S <> '';
  for I := 1 to Length(S) do
    if not (S[I] in ['0'..'9']) then
      Exit(False);
end;

{ A number of digits that fits in Int64; -1 otherwise. }
function DigitsValue(const S: AnsiString): Int64;
begin
  if (not AllDigits(S)) or (Length(S) > 18) then
    Exit(-1);
  Result := StrToInt64(S);
end;

function MonthOf(const S: AnsiString): Integer;
var
  I: Integer;
begin
  for I := 1 to 12 do
    if LowerCase(S) = MonthNames[I] then
      Exit(I);
  Result := 0;
end;

{ "HH:MM" into Hour and Minute. }
function TakeClock(const S: AnsiString; out Hour, Minute: Integer): Boolean;
var
  P: Integer;
begin
  P := Pos(':', S);
  Result := (P >= 2) and (P <= 3) and (Length(S) = P + 2) and AllDigits(Copy(S, 1, P - 1)) and AllDigits(Copy(S, P + 1, 2));
  if not Result then
    Exit;
  Hour := StrToInt(Copy(S, 1, P - 1));
  Minute := StrToInt(Copy(S, P + 1, 2));
  Result := (Hour < 24) and (Minute < 60);
end;

{ The modify fact: YYYYMMDDHHMMSS, perhaps with a fraction of a second; UTC, given as a time of this machine. }
function MlsxTime(const S: AnsiString; out T: TDateTime): Boolean;
var
  Y, Mo, D, H, Mi, Se: Integer;
begin
  Result := False;
  T := 0;
  if (Length(S) < 14) or (not AllDigits(Copy(S, 1, 14))) or ((Length(S) > 14) and (S[15] <> '.')) then
    Exit;
  Y := StrToInt(Copy(S, 1, 4));
  Mo := StrToInt(Copy(S, 5, 2));
  D := StrToInt(Copy(S, 7, 2));
  H := StrToInt(Copy(S, 9, 2));
  Mi := StrToInt(Copy(S, 11, 2));
  Se := StrToInt(Copy(S, 13, 2));
  if Se = 60 then
    Se := 59;
  if not TryEncodeDateTime(Y, Mo, D, H, Mi, Se, 0, T) then
    Exit;
  T := UniversalTimeToLocal(T);
  Result := True;
end;

{ The permission bits written in octal ("0755", "755", and "0o755" as some servers written in Python send it); -1 when it is not a number of up to
  four octal digits after the zeros. }
function OctalValue(const S: AnsiString): LongInt;
var
  I, Start: Integer;
begin
  Result := 0;
  Start := 1;
  if (Length(S) > 2) and (S[1] = '0') and (S[2] in ['o', 'O']) then
    Start := 3;
  if Start > Length(S) then
    Exit(-1);
  for I := Start to Length(S) do
  begin
    if not (S[I] in ['0'..'7']) then
      Exit(-1);
    Result := Result * 8 + (Ord(S[I]) - Ord('0'));
    if Result > &7777 then
      Exit(-1);
  end;
end;

function FtpParseMlsx(const Line: AnsiString; out E: TRemoteEntry): Boolean;
var
  Sp, P, Q, Eq: Integer;
  Facts, Fact, Name, Value: AnsiString;
  T: TDateTime;
  Size: Int64;
begin
  Result := False;
  ClearEntry(E);
  E.Kind := rkFile;
  { the facts end at the first blank; the name, which may hold blanks and ";", is all that follows it }
  Sp := Pos(' ', Line);
  if Sp = 0 then
    Exit;
  Facts := Copy(Line, 1, Sp - 1);
  E.Name := Copy(Line, Sp + 1, Length(Line));
  if (E.Name <> '') and (E.Name[Length(E.Name)] = #13) then
    SetLength(E.Name, Length(E.Name) - 1);
  if E.Name = '' then
    Exit;
  P := 1;
  while P <= Length(Facts) do
  begin
    Q := P;
    while (Q <= Length(Facts)) and (Facts[Q] <> ';') do
      Inc(Q);
    Fact := Copy(Facts, P, Q - P);
    P := Q + 1;
    Eq := Pos('=', Fact);
    if Eq < 2 then
      Continue;
    Name := LowerCase(Copy(Fact, 1, Eq - 1));
    Value := Copy(Fact, Eq + 1, Length(Fact));
    if Name = 'type' then
    begin
      if SameText(Value, 'file') then
        E.Kind := rkFile
      else if SameText(Value, 'dir') then
        E.Kind := rkDir
      else if SameText(Value, 'cdir') or SameText(Value, 'pdir') then
        Exit
      else if SameText(Copy(Value, 1, 14), 'OS.unix=slink:') then
      begin
        E.Kind := rkLink;
        E.LinkTarget := Copy(Value, 15, Length(Value));
      end
      else if SameText(Value, 'OS.unix=symlink') or SameText(Value, 'OS.unix=slink') then
        E.Kind := rkLink
      else
        E.Kind := rkOther;
    end
    else if Name = 'size' then
    begin
      Size := DigitsValue(Value);
      if Size >= 0 then
        E.Size := Size;
    end
    else if Name = 'modify' then
    begin
      if MlsxTime(Value, T) then
        E.MTime := T;
    end
    else if Name = 'unix.mode' then
      E.Mode := OctalValue(Value);
  end;
  if E.Kind = rkDir then
    E.Size := -1;
  Result := True;
end;

{ The kind and the permission bits of the first word of "ls -l" ("drwxr-sr-t", perhaps with "+", "@" or "." after it for an ACL). }
function UnixModeWord(const S: AnsiString; out Kind: TRemoteKind; out Mode: LongInt): Boolean;
const
  Bits: array[0..8] of LongInt = (&400, &200, &100, &40, &20, &10, &4, &2, &1);
var
  I: Integer;
  C: Char;
begin
  Result := False;
  Kind := rkOther;
  Mode := 0;
  if not ((Length(S) = 10) or ((Length(S) = 11) and (S[11] in ['+', '@', '.']))) then
    Exit;
  case S[1] of
    '-': Kind := rkFile;
    'd': Kind := rkDir;
    'l': Kind := rkLink;
    'b', 'c', 'p', 's', 'D': Kind := rkOther;
  else
    Exit;
  end;
  for I := 0 to 8 do
  begin
    C := S[I + 2];
    case I mod 3 of
      0: if C = 'r' then Mode := Mode or Bits[I] else if C <> '-' then Exit;
      1: if C = 'w' then Mode := Mode or Bits[I] else if C <> '-' then Exit;
      2:
        case C of
          'x': Mode := Mode or Bits[I];
          '-': ;
          's', 'S', 't', 'T':
          begin
            { s and t: the bit of execution and the special bit of the triplet; S and T: the special bit alone }
            if (I = 2) and (C in ['s', 'S']) then
              Mode := Mode or &4000
            else if (I = 5) and (C in ['s', 'S']) then
              Mode := Mode or &2000
            else if (I = 8) and (C in ['t', 'T']) then
              Mode := Mode or &1000
            else
              Exit;
            if C in ['s', 't'] then
              Mode := Mode or Bits[I];
          end;
        else
          Exit;
        end;
    end;
  end;
  Result := True;
end;

{ The date of "ls -l" at the word Index of W: a month, a day, then "HH:MM" or a year. }
function LsDateAt(const W: TWords; Index: Integer; Now: TDateTime; out T: TDateTime): Boolean;
var
  Mo, D, Y, H, Mi: Integer;
  NowY, NowM, NowD: Word;
begin
  Result := False;
  T := 0;
  if Index + 2 >= W.Count then
    Exit;
  Mo := MonthOf(W.Text[Index]);
  if (Mo = 0) or (not AllDigits(W.Text[Index + 1])) or (Length(W.Text[Index + 1]) > 2) then
    Exit;
  D := StrToInt(W.Text[Index + 1]);
  if TakeClock(W.Text[Index + 2], H, Mi) then
  begin
    DecodeDate(Now, NowY, NowM, NowD);
    Y := NowY;
    if (not TryEncodeDateTime(Y, Mo, D, H, Mi, 0, 0, T)) or (T > Now + 1) then
    begin
      Y := NowY - 1;
      if not TryEncodeDateTime(Y, Mo, D, H, Mi, 0, 0, T) then
        Exit;
    end;
  end
  else if (Length(W.Text[Index + 2]) = 4) and AllDigits(W.Text[Index + 2]) then
  begin
    Y := StrToInt(W.Text[Index + 2]);
    if not TryEncodeDate(Y, Mo, D, T) then
      Exit;
  end
  else
    Exit;
  Result := True;
end;

{ The name after the word Index: one blank after it (ls puts one), all the rest of the line. }
function NameAfter(const Line: AnsiString; const W: TWords; Index: Integer): AnsiString;
begin
  Result := Copy(Line, W.After[Index] + 1, Length(Line));
end;

{ "ls -l": the mode, then the words up to the date (links, owner, group, perhaps none of the two last); the size is the word before the date. }
function ParseUnix(const Line: AnsiString; const W: TWords; Now: TDateTime; var E: TRemoteEntry): Boolean;
var
  I, P: Integer;
  T: TDateTime;
begin
  Result := False;
  if not UnixModeWord(W.Text[0], E.Kind, E.Mode) then
    Exit;
  for I := 3 to W.Count - 3 do
    if LsDateAt(W, I, Now, T) then
    begin
      E.MTime := T;
      if E.Kind <> rkOther then
        E.Size := DigitsValue(W.Text[I - 1]);
      E.Name := NameAfter(Line, W, I + 2);
      if E.Kind = rkLink then
      begin
        P := Pos(' -> ', E.Name);
        if P > 0 then
        begin
          E.LinkTarget := Copy(E.Name, P + 4, Length(E.Name));
          SetLength(E.Name, P - 1);
        end;
      end;
      Exit(E.Name <> '');
    end;
end;

{ NetWare: "d" or "-", the rights in brackets, the owner, the size, the date as in "ls -l". }
function ParseNetWare(const Line: AnsiString; const W: TWords; Now: TDateTime; var E: TRemoteEntry): Boolean;
var
  T: TDateTime;
begin
  Result := False;
  if (W.Count < 7) or (Length(W.Text[0]) <> 1) or (not (W.Text[0][1] in ['d', '-'])) or (Length(W.Text[1]) < 2) or (W.Text[1][1] <> '[') or
    (W.Text[1][Length(W.Text[1])] <> ']') then
    Exit;
  if not LsDateAt(W, 4, Now, T) then
    Exit;
  if W.Text[0] = 'd' then
    E.Kind := rkDir
  else
  begin
    E.Kind := rkFile;
    E.Size := DigitsValue(W.Text[3]);
  end;
  E.MTime := T;
  E.Name := NameAfter(Line, W, 6);
  Result := E.Name <> '';
end;

{ DOS and IIS: "MM-DD-YY" (or YYYY), "HH:MMAM" (or PM, or a time of 24 hours), "<DIR>" or the size, the name after the blanks. }
function ParseDos(const Line: AnsiString; const W: TWords; var E: TRemoteEntry): Boolean;
var
  S, Clock: AnsiString;
  Mo, D, Y, H, Mi, P: Integer;
  T: TDateTime;
begin
  Result := False;
  if W.Count < 4 then
    Exit;
  S := W.Text[0];
  if not (((Length(S) = 8) or (Length(S) = 10)) and (S[3] = '-') and (S[6] = '-') and AllDigits(Copy(S, 1, 2)) and AllDigits(Copy(S, 4, 2)) and
    AllDigits(Copy(S, 7, Length(S) - 6))) then
    Exit;
  Mo := StrToInt(Copy(S, 1, 2));
  D := StrToInt(Copy(S, 4, 2));
  Y := StrToInt(Copy(S, 7, Length(S) - 6));
  if Length(S) = 8 then
    if Y < 70 then
      Inc(Y, 2000)
    else
      Inc(Y, 1900);
  Clock := UpperCase(W.Text[1]);
  P := Length(Clock);
  if (P > 2) and ((Copy(Clock, P - 1, 2) = 'AM') or (Copy(Clock, P - 1, 2) = 'PM')) then
  begin
    if (not TakeClock(Copy(Clock, 1, P - 2), H, Mi)) or (H < 1) or (H > 12) then
      Exit;
    if H = 12 then
      H := 0;
    if Clock[P - 1] = 'P' then
      Inc(H, 12);
  end
  else if not TakeClock(Clock, H, Mi) then
    Exit;
  if not TryEncodeDateTime(Y, Mo, D, H, Mi, 0, 0, T) then
    Exit;
  if UpperCase(W.Text[2]) = '<DIR>' then
    E.Kind := rkDir
  else
  begin
    E.Size := DigitsValue(StringReplace(W.Text[2], ',', '', [rfReplaceAll]));
    if E.Size < 0 then
      Exit;
    E.Kind := rkFile;
  end;
  E.MTime := T;
  E.Name := Copy(Line, W.First[3], Length(Line));
  Result := True;
end;

function FtpParseList(const Line: AnsiString; Now: TDateTime; out E: TRemoteEntry): Boolean;
var
  S: AnsiString;
  W: TWords;
begin
  ClearEntry(E);
  S := Line;
  if (S <> '') and (S[Length(S)] = #13) then
    SetLength(S, Length(S) - 1);
  SplitWords(S, W);
  if W.Count < 4 then
    Exit(False);
  { each form starts from a clear entry: one that does not fit may have filled some fields }
  Result := ParseUnix(S, W, Now, E);
  if not Result then
  begin
    ClearEntry(E);
    Result := ParseNetWare(S, W, Now, E);
  end;
  if not Result then
  begin
    ClearEntry(E);
    Result := ParseDos(S, W, E);
  end;
  if not Result then
    ClearEntry(E);
end;

const
  { the codes of LastError of a socket whose read waited past its IOTimeout: EAGAIN of Linux and of the BSDs, WSAEWOULDBLOCK, WSAETIMEDOUT }
  WaitCodes: array[0..3] of Integer = (11, 35, 10035, 10060);
  { how long one read of a socket may block, so that the deadline of the reply is looked at often }
  ReadStepMs = 200;

{ TFtpFS }

constructor TFtpFS.Create;
begin
  inherited Create;
  FInPos := 1;
  FTimeoutMs := 30000;
  FFeatures := TStringList.Create;
end;

destructor TFtpFS.Destroy;
begin
  Disconnect;
  FFeatures.Free;
  inherited Destroy;
end;

function TFtpFS.Broke(const Text: AnsiString): Boolean;
begin
  FBroken := True;
  Fail(rrFailed, Text);
  Result := False;
end;

{ Up to Size bytes of Sock into Buf, waiting for them until Deadline: the count, 0 at the end of the stream, -1 when the time is over or the socket
  failed (LastError tells which). }
function TFtpFS.RecvSome(Sock: TInetSocket; Buf: Pointer; Size: Integer; Deadline: QWord): Integer;
var
  I: Integer;
  Waiting: Boolean;
begin
  while True do
  begin
    if GetTickCount64 >= Deadline then
    begin
      Fail(rrFailed, 'the server did not answer in time');
      Exit(-1);
    end;
    Result := Sock.Read(Buf^, Size);
    if Result >= 0 then
      Exit;
    Waiting := False;
    for I := 0 to High(WaitCodes) do
      if Sock.LastError = WaitCodes[I] then
        Waiting := True;
    if not Waiting then
    begin
      Fail(rrFailed, 'the connection failed (error ' + IntToStr(Sock.LastError) + ')');
      Exit(-1);
    end;
  end;
end;

{ What came on Sock (up to 16 KiB) put at the end of Data; the answers of RecvSome. }
function TFtpFS.ReadSome(Sock: TInetSocket; Deadline: QWord; var Data: AnsiString): Integer;
var
  Chunk: array[0..16383] of Char;
begin
  Result := RecvSome(Sock, @Chunk[0], SizeOf(Chunk), Deadline);
  if Result > 0 then
  begin
    SetLength(Data, Length(Data) + Result);
    Move(Chunk[0], Data[Length(Data) - Result + 1], Result);
  end;
end;

function TFtpFS.SendAll(Sock: TInetSocket; Buf: Pointer; Size: Integer): Boolean;
var
  N: Integer;
  P: PByte;
begin
  P := Buf;
  while Size > 0 do
  begin
    try
      N := Sock.Write(P^, Size);
    except
      on E: Exception do
      begin
        Fail(rrFailed, 'cannot send to the server: ' + E.Message);
        Exit(False);
      end;
    end;
    if N <= 0 then
    begin
      Fail(rrFailed, 'cannot send to the server (error ' + IntToStr(Sock.LastError) + ')');
      Exit(False);
    end;
    Inc(P, N);
    Dec(Size, N);
  end;
  Result := True;
end;

{ The next line of the control channel without its line end. False (and the connection broken) when the time is over or the server closed it. }
function TFtpFS.ReadLine(Deadline: QWord; out Line: AnsiString): Boolean;
var
  P, N: SizeInt;
begin
  Line := '';
  while True do
  begin
    P := PosEx(#10, FIn, FInPos);
    if P > 0 then
    begin
      Line := Copy(FIn, FInPos, P - FInPos);
      FInPos := P + 1;
      if (Line <> '') and (Line[Length(Line)] = #13) then
        SetLength(Line, Length(Line) - 1);
      Exit(True);
    end;
    if FInPos > 1 then
    begin
      Delete(FIn, 1, FInPos - 1);
      FInPos := 1;
    end;
    N := ReadSome(FCtl, Deadline, FIn);
    if N = 0 then
      Exit(Broke('the server closed the connection'));
    if N < 0 then
      Exit(Broke(LastError));
  end;
end;

{ One reply: ReplyCode and ReplyText (of its last line); the lines between the first and the last go to Lines when it is not nil. }
function TFtpFS.ReadReply(Lines: TStrings): Boolean;
var
  Line, Code: AnsiString;
  Deadline: QWord;
begin
  Result := False;
  FReplyCode := 0;
  FReplyText := '';
  Deadline := GetTickCount64 + QWord(FTimeoutMs);
  if not ReadLine(Deadline, Line) then
    Exit;
  if (Length(Line) < 3) or (not (Line[1] in ['1'..'5'])) or (not (Line[2] in ['0'..'9'])) or (not (Line[3] in ['0'..'9'])) then
    Exit(Broke('the server does not answer as an FTP server: ' + Copy(Line, 1, 80)));
  Code := Copy(Line, 1, 3);
  if (Length(Line) >= 4) and (Line[4] = '-') then
    { a reply of many lines ends with a line that starts with the code and a blank }
    repeat
      if not ReadLine(Deadline, Line) then
        Exit;
      if (Copy(Line, 1, 3) = Code) and ((Length(Line) = 3) or (Line[4] = ' ')) then
        Break;
      if Lines <> nil then
        Lines.Add(Line);
    until False;
  FReplyCode := StrToInt(Code);
  FReplyText := Copy(Line, 5, Length(Line));
  Result := True;
end;

{ Sends Cmd and reads the reply that ends it (a preliminary 1xx is taken only by the callers that wait for one). }
function TFtpFS.Command(const Cmd: AnsiString; Lines: TStrings): Boolean;
var
  Packet: AnsiString;
begin
  Result := False;
  if (FCtl = nil) or FBroken then
  begin
    Fail(rrFailed, 'the connection is not open');
    Exit;
  end;
  if FBusy then
  begin
    Fail(rrFailed, 'a stream of a file has the connection: free it first');
    Exit;
  end;
  Packet := Cmd + #13#10;
  if not SendAll(FCtl, @Packet[1], Length(Packet)) then
    Exit(Broke(LastError));
  Result := ReadReply(Lines);
end;

{ The result for a reply that refuses: 550 is a path that is not there or not usable, 530 and 553 are refusals, 50x are commands the server has not
  got. LastError tells the reply. }
function TFtpFS.ReplyResult(const Path: AnsiString): TRemoteResult;
var
  Where: AnsiString;
begin
  Where := '';
  if Path <> '' then
    Where := ': ' + Path;
  case FReplyCode of
    550: Result := rrNotFound;
    530, 532, 553: Result := rrDenied;
    500, 501, 502, 504: Result := rrUnsupported;
  else
    Result := rrFailed;
  end;
  Result := Fail(Result, 'the server says: ' + IntToStr(FReplyCode) + ' ' + FReplyText + Where);
end;

{ A data connection in passive mode: EPSV "(|||port|)", or PASV "(h1,h2,h3,h4,p1,p2)" of which only the port is taken. }
function TFtpFS.OpenData(out Data: TInetSocket): TRemoteResult;
var
  P, Q, I, Port: Integer;
  Parts: TStringList;
  Inner: AnsiString;
begin
  Data := nil;
  Port := -1;
  if FUseEpsv then
  begin
    if not Command('EPSV') then
      Exit(rrFailed);
    if FReplyCode = 229 then
    begin
      P := Pos('(', FReplyText);
      Q := Pos(')', FReplyText);
      if (P > 0) and (Q > P + 4) then
      begin
        Inner := Copy(FReplyText, P + 1, Q - P - 1);
        { the delimiter is the first character, three of them before the port and one after it }
        Inner := Copy(Inner, 4, Length(Inner) - 4);
        Port := StrToIntDef(Inner, -1);
      end;
    end
    else
      FUseEpsv := False;
  end;
  if Port < 0 then
  begin
    if not Command('PASV') then
      Exit(rrFailed);
    if FReplyCode <> 227 then
      Exit(ReplyResult(''));
    P := Pos('(', FReplyText);
    Q := Pos(')', FReplyText);
    if (P = 0) or (Q < P) then
    begin
      { some servers leave out the brackets: the numbers start at the first digit after the code }
      P := 0;
      while (P < Length(FReplyText)) and (not (FReplyText[P + 1] in ['0'..'9'])) do
        Inc(P);
      Q := P + 1;
      while (Q <= Length(FReplyText)) and (FReplyText[Q] in ['0'..'9', ',']) do
        Inc(Q);
    end;
    Parts := TStringList.Create;
    try
      Parts.Delimiter := ',';
      Parts.StrictDelimiter := True;
      Parts.DelimitedText := Copy(FReplyText, P + 1, Q - P - 1);
      if Parts.Count = 6 then
      begin
        for I := 0 to 5 do
          if StrToIntDef(Trim(Parts[I]), -1) < 0 then
            Parts.Clear;
        if Parts.Count = 6 then
          Port := StrToInt(Trim(Parts[4])) * 256 + StrToInt(Trim(Parts[5]));
      end;
    finally
      Parts.Free;
    end;
  end;
  if (Port <= 0) or (Port > 65535) then
    Exit(Fail(rrFailed, 'the server did not tell a port for the data: ' + FReplyText));
  try
    Data := TInetSocket.Create(FHost, Port, Max(1000, FTimeoutMs));
    Data.IOTimeout := ReadStepMs;
  except
    on E: Exception do
    begin
      FreeAndNil(Data);
      Exit(Fail(rrFailed, 'cannot open the data connection: ' + E.Message));
    end;
  end;
  Result := rrOk;
end;

{ A command that sends its answer over a data connection (MLSD, LIST): the data in Text. Path is for the messages. }
{ Opens a data connection and sends Cmd on the control channel; rrOk when the server began the transfer (125 or 150), Data is then open. }
function TFtpFS.StartData(const Cmd, Path: AnsiString; out Data: TInetSocket): TRemoteResult;
begin
  Result := OpenData(Data);
  if Result <> rrOk then
    Exit;
  if not Command(Cmd) then
  begin
    FreeAndNil(Data);
    Exit(rrFailed);
  end;
  if (FReplyCode = 125) or (FReplyCode = 150) then
    Exit(rrOk);
  FreeAndNil(Data);
  if FReplyCode div 100 = 2 then
    Exit(Fail(rrFailed, 'the server ended the transfer before it began: ' + FReplyText));
  Result := ReplyResult(Path);
end;

{ Closes the data connection of a transfer and reads the reply that ends it. }
function TFtpFS.EndData(var Data: TInetSocket; const Path: AnsiString): TRemoteResult;
begin
  FreeAndNil(Data);
  if not ReadReply(nil) then
    Exit(rrFailed);
  if FReplyCode div 100 <> 2 then
    Exit(ReplyResult(Path));
  Result := rrOk;
end;

{ Ends a transfer before its end: the data connection is closed and ABOR sent; the server answers with one reply (226) or two (426, then 226),
  so the replies are read while they come. }
procedure TFtpFS.AbortData(var Data: TInetSocket);
var
  Packet: AnsiString;
begin
  FreeAndNil(Data);
  if (FCtl = nil) or FBroken then
    Exit;
  Packet := 'ABOR'#13#10;
  if not SendAll(FCtl, @Packet[1], Length(Packet)) then
  begin
    Broke(LastError);
    Exit;
  end;
  if not ReadReply(nil) then
    Exit;
  if (FReplyCode = 426) or (FReplyCode = 450) or (FReplyCode = 451) or (FReplyCode = 125) or (FReplyCode = 150) then
    ReadReply(nil);
end;

function TFtpFS.Transfer(const Cmd, Path: AnsiString; out Text: AnsiString): TRemoteResult;
var
  Data: TInetSocket;
  Deadline: QWord;
  N: Integer;
begin
  Text := '';
  Result := StartData(Cmd, Path, Data);
  if Result <> rrOk then
    Exit;
  try
    Deadline := GetTickCount64 + QWord(FTimeoutMs);
    repeat
      N := ReadSome(Data, Deadline, Text);
    until N <= 0;
    if N < 0 then
    begin
      FreeAndNil(Data);
      Broke(LastError);
      Exit(rrFailed);
    end;
    Result := EndData(Data, Path);
  finally
    Data.Free;
  end;
end;

{ The lines of the listing of Dir; Machine: they are of MLSD (else of LIST). }
function TFtpFS.ListLines(const Dir: AnsiString; out Lines: TStringList; out Machine: Boolean): TRemoteResult;
var
  Text: AnsiString;
begin
  Lines := nil;
  Machine := FUseMlsd;
  if FUseMlsd then
    Result := Transfer('MLSD ' + Dir, Dir, Text)
  else
  begin
    if not Command('CWD ' + Dir) then
      Exit(rrFailed);
    if FReplyCode div 100 <> 2 then
      Exit(ReplyResult(Dir));
    Result := Transfer('LIST -a', Dir, Text);
    if (Result = rrUnsupported) and (not FBroken) then
      Result := Transfer('LIST', Dir, Text);
  end;
  { a path that cannot be listed is told with 550 or with 501 ("no such directory"): the caller looks at the path }
  if (Result = rrUnsupported) and (FReplyCode = 501) then
    Result := rrNotFound;
  if Result <> rrOk then
    Exit;
  Lines := TStringList.Create;
  Lines.Text := Text;
end;

{ The entry of Path by MLST: the facts are on the line of the reply that starts with a blank. }
function TFtpFS.MlstEntry(const Path: AnsiString; out Entry: TRemoteEntry): TRemoteResult;
var
  Lines: TStringList;
  I: Integer;
  Line, Dir, Name: AnsiString;
begin
  ClearEntry(Entry);
  Lines := TStringList.Create;
  try
    if not Command('MLST ' + Path, Lines) then
      Exit(rrFailed);
    if FReplyCode div 100 <> 2 then
      Exit(ReplyResult(Path));
    for I := 0 to Lines.Count - 1 do
      if (Lines[I] <> '') and (Lines[I][1] = ' ') then
      begin
        { the entry of a directory may be told as the directory itself }
        Line := Copy(Lines[I], 2, Length(Lines[I]));
        Line := StringReplace(Line, 'type=cdir;', 'type=dir;', [rfIgnoreCase]);
        Line := StringReplace(Line, 'type=pdir;', 'type=dir;', [rfIgnoreCase]);
        if FtpParseMlsx(Line, Entry) then
        begin
          RemoteSplit(Path, Dir, Name);
          Entry.Name := Name;
          Exit(rrOk);
        end;
      end;
    Result := Fail(rrFailed, 'the server sent no facts for ' + Path);
  finally
    Lines.Free;
  end;
end;

{ The entry of Path found by its name in the list of its directory, for a server without MLST. }
function TFtpFS.FindInParent(const Path: AnsiString; out Entry: TRemoteEntry): TRemoteResult;
var
  Dir, Name: AnsiString;
  Entries: TRemoteEntries;
  I: Integer;
begin
  ClearEntry(Entry);
  RemoteSplit(Path, Dir, Name);
  Result := List(Dir, Entries);
  if Result = rrNotDir then
    Exit(Fail(rrNotFound, 'not found: ' + Path));
  if Result <> rrOk then
    Exit;
  for I := 0 to High(Entries) do
    if Entries[I].Name = Name then
    begin
      Entry := Entries[I];
      Exit(rrOk);
    end;
  Result := Fail(rrNotFound, 'not found: ' + Path);
end;

function TFtpFS.Connect(const Host: AnsiString; Port: Word; const User, Password: AnsiString): TRemoteResult;
const
  WantFacts: array[0..3] of AnsiString = (';type;', ';size;', ';modify;', ';unix.mode;');
var
  I: Integer;
  S, Facts: AnsiString;
begin
  if FConnected then
    Exit(rrOk);
  if FBroken then
    Exit(Fail(rrFailed, 'the connection cannot be opened'));
  FHost := Host;
  try
    FCtl := TInetSocket.Create(Host, Port, Max(1000, FTimeoutMs));
    FCtl.IOTimeout := ReadStepMs;
  except
    on E: Exception do
    begin
      FreeAndNil(FCtl);
      FBroken := True;
      Exit(Fail(rrFailed, 'cannot connect to ' + Host + ':' + IntToStr(Port) + ': ' + E.Message));
    end;
  end;
  { the greeting: 120 asks to wait for the 220 that follows }
  if not ReadReply(nil) then
    Exit(rrFailed);
  if FReplyCode = 120 then
    if not ReadReply(nil) then
      Exit(rrFailed);
  if FReplyCode <> 220 then
  begin
    Broke('the server does not take the connection: ' + IntToStr(FReplyCode) + ' ' + FReplyText);
    Exit(rrFailed);
  end;
  if not Command('USER ' + User) then
    Exit(rrFailed);
  if FReplyCode = 331 then
    if not Command('PASS ' + Password) then
      Exit(rrFailed);
  if FReplyCode <> 230 then
  begin
    if FReplyCode div 100 = 5 then
      Result := Fail(rrDenied, 'the server refused the login: ' + IntToStr(FReplyCode) + ' ' + FReplyText)
    else
      Result := Fail(rrFailed, 'the login was not finished: ' + IntToStr(FReplyCode) + ' ' + FReplyText);
    FBroken := True;
    FreeAndNil(FCtl);
    Exit;
  end;
  FFeatures.Clear;
  if Command('FEAT', FFeatures) and (FReplyCode = 211) then
    for I := 0 to FFeatures.Count - 1 do
    begin
      S := TrimLeft(FFeatures[I]);
      FFeatures[I] := UpperCase(Copy2Space(S + ' ')) + Copy(S, Length(Copy2Space(S + ' ')) + 1, Length(S));
    end
  else
    FFeatures.Clear;
  if FBroken then
    Exit(rrFailed);
  FUseMlsd := HasFeature('MLST');
  FUseEpsv := True;
  { the facts that a server does not send unless asked (unix.mode is one of them) are asked for, the ones it has of those that are read }
  if FUseMlsd then
  begin
    S := '';
    for I := 0 to FFeatures.Count - 1 do
      if Copy(FFeatures[I], 1, 5) = 'MLST ' then
        S := LowerCase(Copy(FFeatures[I], 6, Length(FFeatures[I])));
    Facts := '';
    for I := 0 to High(WantFacts) do
      if Pos(WantFacts[I], ';' + StringReplace(S, '*', '', [rfReplaceAll])) > 0 then
        Facts := Facts + Copy(WantFacts[I], 2, Length(WantFacts[I]));
    if (Facts <> '') and Command('OPTS MLST ' + Facts) and (FReplyCode div 100 <> 2) then
      Fail(rrFailed, 'the server does not take the facts: ' + FReplyText);
  end;
  if HasFeature('UTF8') then
    Command('OPTS UTF8 ON');
  if (not FBroken) and Command('TYPE I') and (FReplyCode div 100 <> 2) then
    Fail(rrFailed, 'the server has no binary mode: ' + FReplyText);
  if FBroken then
    Exit(rrFailed);
  FConnected := True;
  Result := rrOk;
end;

procedure TFtpFS.Disconnect;
var
  Saved: Integer;
begin
  if FConnected and (not FBroken) then
  begin
    Saved := FTimeoutMs;
    FTimeoutMs := 2000;
    Command('QUIT');
    FTimeoutMs := Saved;
  end;
  FConnected := False;
  FBroken := True;
  FreeAndNil(FCtl);
end;

function TFtpFS.Pwd(out Dir: AnsiString): TRemoteResult;
var
  P, Q: Integer;
begin
  Dir := '';
  if not Command('PWD') then
    Exit(rrFailed);
  if FReplyCode <> 257 then
    Exit(ReplyResult(''));
  { the name is in double quotes, a quote in it is doubled }
  P := Pos('"', FReplyText);
  if P = 0 then
    Exit(Fail(rrFailed, 'the reply to PWD has no name: ' + FReplyText));
  Q := P + 1;
  while Q <= Length(FReplyText) do
  begin
    if FReplyText[Q] = '"' then
    begin
      if (Q < Length(FReplyText)) and (FReplyText[Q + 1] = '"') then
        Inc(Q)
      else
        Break;
    end;
    Dir := Dir + FReplyText[Q];
    Inc(Q);
  end;
  Result := rrOk;
end;

function TFtpFS.HasFeature(const Name: AnsiString): Boolean;
var
  I: Integer;
  U: AnsiString;
begin
  U := UpperCase(Name);
  for I := 0 to FFeatures.Count - 1 do
    if (FFeatures[I] = U) or (Copy(FFeatures[I], 1, Length(U) + 1) = U + ' ') then
      Exit(True);
  Result := False;
end;

function TFtpFS.List(const Dir: AnsiString; out Entries: TRemoteEntries): TRemoteResult;
var
  Clean: AnsiString;
  Lines: TStringList;
  Machine, Ok: Boolean;
  I, N: Integer;
  E: TRemoteEntry;
  Now_: TDateTime;
begin
  SetLength(Entries, 0);
  if not RemoteCleanPath(Dir, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Dir));
  Result := ListLines(Clean, Lines, Machine);
  if Result = rrNotFound then
  begin
    { 550 is told for a file where a directory is needed as well: the kind of the path decides }
    if (not FBroken) and (Stat(Clean, True, E) = rrOk) then
    begin
      if E.Kind <> rkDir then
        Exit(Fail(rrNotDir, 'not a directory: ' + Dir));
      Exit(Fail(rrDenied, 'the directory cannot be read: ' + Dir));
    end;
    if not FBroken then
      Result := Fail(rrNotFound, 'not found: ' + Dir);
  end;
  if Result <> rrOk then
    Exit;
  try
    Now_ := SysUtils.Now;
    SetLength(Entries, Lines.Count);
    N := 0;
    for I := 0 to Lines.Count - 1 do
    begin
      if Machine then
        Ok := FtpParseMlsx(Lines[I], E)
      else
        Ok := FtpParseList(Lines[I], Now_, E);
      if Ok and (E.Name <> '.') and (E.Name <> '..') then
      begin
        Entries[N] := E;
        Inc(N);
      end;
    end;
    SetLength(Entries, N);
  finally
    Lines.Free;
  end;
end;

function TFtpFS.Stat(const Path: AnsiString; FollowLinks: Boolean; out Entry: TRemoteEntry): TRemoteResult;
var
  Clean, Dir, Name, Target: AnsiString;
  Hops: Integer;
  Next: TRemoteEntry;
begin
  ClearEntry(Entry);
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  RemoteSplit(Clean, Dir, Name);
  if Clean = '/' then
  begin
    Entry.Kind := rkDir;
    Exit(rrOk);
  end;
  if HasFeature('MLST') then
    Result := MlstEntry(Clean, Entry)
  else
    Result := FindInParent(Clean, Entry);
  if Result <> rrOk then
    Exit;
  { a link the server tells as a link, followed to what it points to (a link to nothing stays the link) }
  Hops := 0;
  while FollowLinks and (Entry.Kind = rkLink) and (Entry.LinkTarget <> '') and (Hops < 8) do
  begin
    if Entry.LinkTarget[1] = '/' then
      Target := Entry.LinkTarget
    else
      Target := RemoteJoin(Dir, Entry.LinkTarget);
    if (not RemoteCleanPath(Target, Target)) or (Stat(Target, False, Next) <> rrOk) then
    begin
      if FBroken then
        Exit(rrFailed);
      Break;
    end;
    RemoteSplit(Target, Dir, Name);
    Next.Name := Entry.Name;
    Entry := Next;
    Inc(Hops);
  end;
  RemoteSplit(Clean, Dir, Name);
  Entry.Name := Name;
  Result := rrOk;
end;

type
  TFtpReadStream = class(TStream)
  private
    FFS: TFtpFS;
    FPath: AnsiString;
    FData: TInetSocket;           { nil when no transfer runs (at the end of the file, or after a Seek past it) }
    FPos, FSize: Int64;           { FPos: the place in the file of the next byte of FData }
    function Start(Offset: Int64): TRemoteResult;
    procedure Finish;
  protected
    function GetSize: Int64; override;
  public
    constructor Create(AFS: TFtpFS; const APath: AnsiString; ASize: Int64);
    destructor Destroy; override;
    function Read(var Buffer; Count: LongInt): LongInt; override;
    function Write(const Buffer; Count: LongInt): LongInt; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

constructor TFtpReadStream.Create(AFS: TFtpFS; const APath: AnsiString; ASize: Int64);
begin
  inherited Create;
  FFS := AFS;
  FPath := APath;
  FSize := ASize;
end;

destructor TFtpReadStream.Destroy;
begin
  if FData <> nil then
    FFS.AbortData(FData);
  FFS.FBusy := False;
  inherited Destroy;
end;

function TFtpReadStream.GetSize: Int64;
begin
  Result := FSize;
end;

{ A transfer from Offset: REST before RETR when it is not the start. }
function TFtpReadStream.Start(Offset: Int64): TRemoteResult;
begin
  FFS.FBusy := False;
  try
    if Offset > 0 then
    begin
      if not FFS.Command('REST ' + IntToStr(Offset)) then
        Exit(rrFailed);
      if FFS.FReplyCode <> 350 then
        Exit(FFS.Fail(rrUnsupported, 'the server cannot start a file in its middle: ' + FFS.FReplyText));
    end;
    Result := FFS.StartData('RETR ' + FPath, FPath, FData);
  finally
    FFS.FBusy := True;
  end;
  if Result = rrOk then
    FPos := Offset;
end;

{ The end of the data: the reply to the transfer. }
procedure TFtpReadStream.Finish;
begin
  FFS.FBusy := False;
  try
    if FFS.EndData(FData, FPath) <> rrOk then
      raise EReadError.Create(FFS.LastError);
  finally
    FFS.FBusy := True;
  end;
end;

function TFtpReadStream.Read(var Buffer; Count: LongInt): LongInt;
var
  N: Integer;
  Dest: PByte;
begin
  Result := 0;
  Dest := @Buffer;
  while (Count > 0) and (FData <> nil) do
  begin
    N := FFS.RecvSome(FData, Dest, Count, GetTickCount64 + QWord(FFS.FTimeoutMs));
    if N < 0 then
    begin
      FreeAndNil(FData);
      FFS.Broke(FFS.LastError);
      raise EReadError.Create(FFS.LastError);
    end;
    if N = 0 then
    begin
      { the end of the file, as the server sees it now }
      FSize := FPos;
      Finish;
      Break;
    end;
    Inc(FPos, N);
    if FPos > FSize then
      FSize := FPos;
    Inc(Dest, N);
    Dec(Count, N);
    Inc(Result, N);
  end;
end;

function TFtpReadStream.Write(const Buffer; Count: LongInt): LongInt;
begin
  Result := 0;
  raise EWriteError.Create('the stream of a remote file is for reading only');
end;

function TFtpReadStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
var
  Target: Int64;
begin
  case Origin of
    soBeginning: Target := Offset;
    soCurrent: Target := FPos + Offset;
  else
    Target := FSize + Offset;
  end;
  if Target < 0 then
    Target := 0;
  if Target <> FPos then
  begin
    if FData <> nil then
      FFS.AbortData(FData);
    FPos := Target;
    { past the end nothing is asked for: a read there gives nothing }
    if (Target < FSize) and (Start(Target) <> rrOk) then
      raise EReadError.Create(FFS.LastError);
  end;
  Result := FPos;
end;

type
  TFtpWriteStream = class(TStream)
  private
    FFS: TFtpFS;
    FPath: AnsiString;
    FData: TInetSocket;
    FPos: Int64;
  protected
    function GetSize: Int64; override;
  public
    constructor Create(AFS: TFtpFS; const APath: AnsiString; AData: TInetSocket);
    destructor Destroy; override;
    function Read(var Buffer; Count: LongInt): LongInt; override;
    function Write(const Buffer; Count: LongInt): LongInt; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

constructor TFtpWriteStream.Create(AFS: TFtpFS; const APath: AnsiString; AData: TInetSocket);
begin
  inherited Create;
  FFS := AFS;
  FPath := APath;
  FData := AData;
end;

{ The reply to the transfer cannot be passed on from here: a refusal is left in LastError of the file system. }
destructor TFtpWriteStream.Destroy;
begin
  FFS.FBusy := False;
  if FData <> nil then
    FFS.EndData(FData, FPath);
  inherited Destroy;
end;

function TFtpWriteStream.GetSize: Int64;
begin
  Result := FPos;
end;

function TFtpWriteStream.Read(var Buffer; Count: LongInt): LongInt;
begin
  Result := 0;
  raise EReadError.Create('the stream of a remote file is for writing only');
end;

function TFtpWriteStream.Write(const Buffer; Count: LongInt): LongInt;
begin
  Result := 0;
  if Count < 0 then
    raise EWriteError.Create('the number of bytes to write is negative');
  if Count = 0 then
    Exit;
  if FData = nil then
    raise EWriteError.Create(FFS.LastError);
  if not FFS.SendAll(FData, @Buffer, Count) then
  begin
    FreeAndNil(FData);
    FFS.Broke(FFS.LastError);
    raise EWriteError.Create(FFS.LastError);
  end;
  Inc(FPos, Count);
  Result := Count;
end;

function TFtpWriteStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
var
  Target: Int64;
begin
  case Origin of
    soBeginning: Target := Offset;
    soCurrent: Target := FPos + Offset;
  else
    Target := FPos + Offset;
  end;
  if Target <> FPos then
    raise EWriteError.Create('a file is written over FTP from its start to its end');
  Result := FPos;
end;

function TFtpFS.OpenRead(const Path: AnsiString; out Stream: TStream): TRemoteResult;
var
  Clean: AnsiString;
  E: TRemoteEntry;
  S: TFtpReadStream;
begin
  Stream := nil;
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  Result := Stat(Clean, True, E);
  if Result <> rrOk then
    Exit;
  case E.Kind of
    rkDir: Exit(Fail(rrIsDir, 'is a directory: ' + Path));
    rkLink: Exit(Fail(rrNotFound, 'the link points to nothing: ' + Path));
    rkOther: Exit(Fail(rrFailed, 'not a regular file: ' + Path));
  end;
  if E.Size < 0 then
    E.Size := 0;
  S := TFtpReadStream.Create(Self, Clean, E.Size);
  Result := S.Start(0);
  if Result <> rrOk then
  begin
    S.Free;
    Exit;
  end;
  Stream := S;
end;

function TFtpFS.OpenWrite(const Path: AnsiString; out Stream: TStream): TRemoteResult;
var
  Clean, Dir, Name: AnsiString;
  E: TRemoteEntry;
  Data: TInetSocket;
begin
  Stream := nil;
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  if Clean = '/' then
    Exit(Fail(rrIsDir, 'is a directory: ' + Path));
  Result := Stat(Clean, True, E);
  if Result = rrOk then
    case E.Kind of
      rkDir: Exit(Fail(rrIsDir, 'is a directory: ' + Path));
      rkOther: Exit(Fail(rrFailed, 'not a regular file: ' + Path));
    end
  else if Result <> rrNotFound then
    Exit;
  { STOR into a directory that is not there is refused with words of the server: the directory is looked at first }
  RemoteSplit(Clean, Dir, Name);
  Result := Stat(Dir, True, E);
  if Result <> rrOk then
    Exit;
  if E.Kind <> rkDir then
    Exit(Fail(rrNotFound, 'not a directory: ' + Dir));
  Result := StartData('STOR ' + Clean, Clean, Data);
  if Result <> rrOk then
    Exit;
  FBusy := True;
  Stream := TFtpWriteStream.Create(Self, Clean, Data);
end;

function TFtpFS.MkDir(const Path: AnsiString): TRemoteResult;
var
  Clean, Dir, Name: AnsiString;
  E: TRemoteEntry;
begin
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  if Clean = '/' then
    Exit(Fail(rrExists, 'already exists: ' + Path));
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
  if not Command('MKD ' + Clean) then
    Exit(rrFailed);
  if FReplyCode div 100 <> 2 then
    Exit(ReplyResult(Path));
  Result := rrOk;
end;

function TFtpFS.Remove(const Path: AnsiString): TRemoteResult;
var
  Clean: AnsiString;
  E: TRemoteEntry;
  Entries: TRemoteEntries;
begin
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  if Clean = '/' then
    Exit(Fail(rrDenied, 'the root cannot be removed'));
  Result := Stat(Clean, False, E);
  if Result <> rrOk then
    Exit;
  if E.Kind <> rkDir then
  begin
    if not Command('DELE ' + Clean) then
      Exit(rrFailed);
    if FReplyCode div 100 <> 2 then
      Exit(ReplyResult(Path));
    Exit(rrOk);
  end;
  if not Command('RMD ' + Clean) then
    Exit(rrFailed);
  if FReplyCode div 100 = 2 then
    Exit(rrOk);
  Result := ReplyResult(Path);
  { the servers tell a directory with content as a refusal of any kind: its list decides }
  if (not FBroken) and (List(Clean, Entries) = rrOk) and (Length(Entries) > 0) then
    Result := Fail(rrNotEmpty, 'the directory is not empty: ' + Path);
end;

function TFtpFS.Rename(const OldPath, NewPath: AnsiString): TRemoteResult;
var
  OldClean, NewClean: AnsiString;
  E: TRemoteEntry;
begin
  if (not RemoteCleanPath(OldPath, OldClean)) or (not RemoteCleanPath(NewPath, NewClean)) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + OldPath));
  if (OldClean = '/') or (NewClean = '/') then
    Exit(Fail(rrDenied, 'the root cannot be renamed'));
  Result := Stat(OldClean, False, E);
  if Result <> rrOk then
    Exit;
  { RNTO replaces what is there on many servers: the free name is looked at first }
  Result := Stat(NewClean, False, E);
  if Result = rrOk then
    Exit(Fail(rrExists, 'already exists: ' + NewPath));
  if Result <> rrNotFound then
    Exit;
  if not Command('RNFR ' + OldClean) then
    Exit(rrFailed);
  if FReplyCode <> 350 then
    Exit(ReplyResult(OldPath));
  if not Command('RNTO ' + NewClean) then
    Exit(rrFailed);
  if FReplyCode div 100 <> 2 then
    Exit(ReplyResult(NewPath));
  Result := rrOk;
end;

function TFtpFS.SetMode(const Path: AnsiString; Mode: LongInt): TRemoteResult;
var
  Clean: AnsiString;
  E: TRemoteEntry;
begin
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  if (Mode < 0) or (Mode > &7777) then
    Exit(Fail(rrFailed, 'the permission bits are not right: ' + Path));
  Result := Stat(Clean, False, E);
  if Result <> rrOk then
    Exit;
  if not Command('SITE CHMOD ' + OctStr(Mode, 4) + ' ' + Clean) then
    Exit(rrFailed);
  if FReplyCode div 100 <> 2 then
    Exit(ReplyResult(Path));
  Result := rrOk;
end;

{$ENDIF}

end.
