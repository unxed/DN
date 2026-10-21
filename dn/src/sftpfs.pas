{ SftpFS: the file system of a remote host over the SSH file transfer protocol, version 3 (docs/NETWORK.md, unxed/dn#90 step 9). TSftpFS is a
  TRemoteFS that speaks to an SFTP server through a TNetProc: the program is the server itself (sftp-server of this machine, as in the tests) or a
  client that carries the protocol to a host ("ssh -s host sftp").

  A packet is its length (4 bytes), its type (1 byte) and its fields; a number is big endian, a string is its length (4 bytes) and its bytes. Every
  request but the first carries a number that its answer repeats; one request is in flight at a time, so an answer with another number means that the
  two sides are out of step.

  Done so far: List (OPENDIR, READDIR, CLOSE), Stat (STAT, LSTAT, and READLINK for the target of a link), RealPath, and the streams of OpenRead
  (OPEN, READ in pieces as the caller reads, so Seek is cheap) and OpenWrite (OPEN that makes or empties the file, WRITE as the caller writes, CLOSE
  when the stream is freed), and the changes of the tree: MkDir (MKDIR), Remove (REMOVE, RMDIR), Rename (RENAME) and SetMode (SETSTAT). Before a change
  the paths are looked at, so that the answers are those of TLocalFS whatever words the server has for its errors (rrExists for a taken name,
  rrNotEmpty for a directory with content); RENAME of version 3 does not overwrite, and a name that is taken is refused before it is sent.

  When a request does not get its answer in time, or the server ends, the connection is broken for good: the next answer could not be told from the
  late one. LastError tells why; make a new TSftpFS to try again.

  The unit is empty in the DOS build and in DN_MINI (as NetProc is).

  MIT, see LICENSE. }
unit SftpFS;

{$I netbuild.inc}

{$mode objfpc}
{$H+}

interface

{$IFDEF DN_NET}
uses
  SysUtils, Classes, RemoteFS, NetProc;

type
  { The fields of a packet that has come, read from the front; Bad is set when a field would go past the end. }
  TSftpReader = record
    Data: AnsiString;
    At: Integer;
    Bad: Boolean;
  end;

  TSftpFS = class(TRemoteFS)
  private
    FProc: TNetProc;
    FOwnsProc: Boolean;
    FNextId: LongWord;
    FIn: AnsiString;              { what came from the server and is not taken as packets yet, from FInPos }
    FInPos: Integer;
    FErrTail: AnsiString;         { the last bytes of the standard error of the program }
    FVersion: LongWord;
    FExtensions: TStringList;     { name=data of the extensions that the server told in its VERSION }
    FConnected: Boolean;
    FBroken: Boolean;
    FTimeoutMs: Integer;
    procedure DrainErr;
    function Broke(const Text: AnsiString): Boolean;
    function FillIn(Deadline: QWord): Boolean;
    function SendPacket(Kind: Byte; const Body: AnsiString): Boolean;
    function ReadPacket(Deadline: QWord; out Kind: Byte; out R: TSftpReader): Boolean;
    function Request(Kind: Byte; const Fields: AnsiString; out Reply: Byte; out R: TSftpReader): Boolean;
    function StatusResult(var R: TSftpReader; const Path: AnsiString): TRemoteResult;
    function Unexpected(Reply: Byte): TRemoteResult;
    function AskHandle(Kind: Byte; const Fields, Path: AnsiString; out Handle: AnsiString): TRemoteResult;
    function AskStatus(Kind: Byte; const Fields, Path: AnsiString): TRemoteResult;
    function CloseHandle(const Handle, Path: AnsiString): TRemoteResult;
    function ReadAt(const Handle, Path: AnsiString; Offset: Int64; Len: Integer; out Data: AnsiString): TRemoteResult;
    function WriteAt(const Handle, Path: AnsiString; Offset: Int64; const Data: AnsiString): TRemoteResult;
    function AskAttrs(Kind: Byte; const Path: AnsiString; out Entry: TRemoteEntry): TRemoteResult;
    function AskName(Kind: Byte; const Path: AnsiString; out Name: AnsiString): TRemoteResult;
  public
    { Proc is the program that talks the protocol (already started); OwnsProc: it is freed with this file system. }
    constructor Create(AProc: TNetProc; AOwnsProc: Boolean);
    destructor Destroy; override;
    { Sends INIT and waits for VERSION. rrOk, or rrFailed with LastError (also for a server that does not speak version 3). }
    function Connect: TRemoteResult;
    { Ends the session and the program. Safe to call again; the file system cannot be connected again after it. }
    procedure Disconnect;
    { The absolute clean form of Path on the server ("." is the directory in which the server started, its home for ssh). }
    function RealPath(const Path: AnsiString; out Abs: AnsiString): TRemoteResult;
    { The data of the extension Name that the server told in its VERSION; False when it told none of that name. }
    function Extension(const Name: AnsiString; out Data: AnsiString): Boolean;
    function List(const Dir: AnsiString; out Entries: TRemoteEntries): TRemoteResult; override;
    function Stat(const Path: AnsiString; FollowLinks: Boolean; out Entry: TRemoteEntry): TRemoteResult; override;
    { A stream over the file, from its start; it asks the server for a piece of the file when a read goes past what it has. A read that fails raises
      EReadError (LastError tells why); the stream is the caller's, free it before the file system. }
    function OpenRead(const Path: AnsiString; out Stream: TStream): TRemoteResult; override;
    { A stream that writes the file from its start (Seek moves the place of the next write; a gap reads as zero bytes). A write that fails raises
      EWriteError; the file is closed when the stream is freed. }
    function OpenWrite(const Path: AnsiString; out Stream: TStream): TRemoteResult; override;
    function MkDir(const Path: AnsiString): TRemoteResult; override;
    function Remove(const Path: AnsiString): TRemoteResult; override;
    function Rename(const OldPath, NewPath: AnsiString): TRemoteResult; override;
    function SetMode(const Path: AnsiString; Mode: LongInt): TRemoteResult; override;
    { How long one request may take, in milliseconds (the whole answer, not a byte of it); 30000 at the start. }
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;
    property Connected: Boolean read FConnected;
    { The version that the server answered with (3 once connected). }
    property Version: LongWord read FVersion;
  end;

{ A TSftpFS over "ssh -s host sftp" (unit NetSsh) for the address Url, sftp://, connected; the path of the address is not looked at. rrOk and FS;
  otherwise FS is nil and Err tells why (what ssh said, when it could not connect). }
function OpenSftpSsh(const Url: AnsiString; out FS: TSftpFS; out Err: AnsiString): TRemoteResult;
{ The packet fields: a number of 4 and of 8 bytes, a string. }
function SftpU32(V: LongWord): AnsiString;
function SftpU64(V: QWord): AnsiString;
function SftpStr(const S: AnsiString): AnsiString;
{ A reader over the fields in Data. }
function SftpReader(const Data: AnsiString): TSftpReader;
function SftpTakeByte(var R: TSftpReader): Byte;
function SftpTakeU32(var R: TSftpReader): LongWord;
function SftpTakeU64(var R: TSftpReader): QWord;
function SftpTakeStr(var R: TSftpReader): AnsiString;
{ The attributes of a file (the ATTRS of the protocol) into Kind, Size, MTime and Mode of E; the other fields of E stay as they are. }
procedure SftpTakeAttrs(var R: TSftpReader; var E: TRemoteEntry);
{$ENDIF}

implementation

{$IFDEF DN_NET}

uses
  DateUtils, NetSplit, NetSsh;

const
  ProtocolVersion = 3;

  FxpInit = 1;
  FxpVersion = 2;
  FxpOpen = 3;
  FxpClose = 4;
  FxpRead = 5;
  FxpWrite = 6;
  FxpLstat = 7;
  FxpSetstat = 9;
  FxpOpendir = 11;
  FxpReaddir = 12;
  FxpRemove = 13;
  FxpMkdir = 14;
  FxpRmdir = 15;
  FxpRealpath = 16;
  FxpStat = 17;
  FxpRename = 18;
  FxpReadlink = 19;
  FxpStatus = 101;
  FxpHandle = 102;
  FxpData = 103;
  FxpName = 104;
  FxpAttrs = 105;

  FxOk = 0;
  FxEof = 1;
  FxNoSuchFile = 2;
  FxPermissionDenied = 3;
  FxOpUnsupported = 8;

  FxfRead = $00000001;
  FxfWrite = $00000002;
  FxfCreat = $00000008;
  FxfTrunc = $00000010;

  AttrSize = $00000001;
  AttrUidGid = $00000002;
  AttrPermissions = $00000004;
  AttrAcModTime = $00000008;
  AttrExtended = $80000000;

  ModeTypeMask = &170000;
  ModeDir = &040000;
  ModeFile = &100000;
  ModeLink = &120000;

  { A packet longer than this is taken for noise (the servers send 256 KiB of data at most). }
  MaxPacket = 4 * 1024 * 1024;
  { The data of one READ or WRITE: every server takes 32 KiB. }
  DataChunk = 32768;

function SftpU32(V: LongWord): AnsiString;
begin
  SetLength(Result, 4);
  Result[1] := Chr((V shr 24) and $FF);
  Result[2] := Chr((V shr 16) and $FF);
  Result[3] := Chr((V shr 8) and $FF);
  Result[4] := Chr(V and $FF);
end;

function SftpU64(V: QWord): AnsiString;
begin
  Result := SftpU32(LongWord(V shr 32)) + SftpU32(LongWord(V and $FFFFFFFF));
end;

function SftpStr(const S: AnsiString): AnsiString;
begin
  Result := SftpU32(Length(S)) + S;
end;

function SftpReader(const Data: AnsiString): TSftpReader;
begin
  Result.Data := Data;
  Result.At := 1;
  Result.Bad := False;
end;

{ True when Count more bytes are there; Bad otherwise. }
function Has(var R: TSftpReader; Count: Int64): Boolean;
begin
  Result := (not R.Bad) and (Count >= 0) and (Int64(R.At) + Count - 1 <= Length(R.Data));
  if not Result then
    R.Bad := True;
end;

function SftpTakeByte(var R: TSftpReader): Byte;
begin
  Result := 0;
  if not Has(R, 1) then
    Exit;
  Result := Ord(R.Data[R.At]);
  Inc(R.At);
end;

function SftpTakeU32(var R: TSftpReader): LongWord;
begin
  Result := 0;
  if not Has(R, 4) then
    Exit;
  Result := (LongWord(Ord(R.Data[R.At])) shl 24) or (LongWord(Ord(R.Data[R.At + 1])) shl 16) or
    (LongWord(Ord(R.Data[R.At + 2])) shl 8) or LongWord(Ord(R.Data[R.At + 3]));
  Inc(R.At, 4);
end;

function SftpTakeU64(var R: TSftpReader): QWord;
var
  Hi: LongWord;
begin
  Hi := SftpTakeU32(R);
  Result := (QWord(Hi) shl 32) or SftpTakeU32(R);
end;

function SftpTakeStr(var R: TSftpReader): AnsiString;
var
  Len: LongWord;
begin
  Result := '';
  Len := SftpTakeU32(R);
  if not Has(R, Len) then
    Exit;
  Result := Copy(R.Data, R.At, Len);
  Inc(R.At, Len);
end;

procedure SftpTakeAttrs(var R: TSftpReader; var E: TRemoteEntry);
var
  Flags, Perm, Count, I: LongWord;
  Size: QWord;
begin
  E.Kind := rkFile;
  E.Size := -1;
  E.MTime := 0;
  E.Mode := -1;
  Flags := SftpTakeU32(R);
  if (Flags and AttrSize) <> 0 then
  begin
    Size := SftpTakeU64(R);
    if Size <= QWord(High(Int64)) then
      E.Size := Int64(Size);
  end;
  if (Flags and AttrUidGid) <> 0 then
  begin
    SftpTakeU32(R);
    SftpTakeU32(R);
  end;
  if (Flags and AttrPermissions) <> 0 then
  begin
    Perm := SftpTakeU32(R);
    E.Mode := LongInt(Perm and &7777);
    case Perm and ModeTypeMask of
      0, ModeFile: E.Kind := rkFile;
      ModeDir: E.Kind := rkDir;
      ModeLink: E.Kind := rkLink;
    else
      E.Kind := rkOther;
    end;
  end;
  if (Flags and AttrAcModTime) <> 0 then
  begin
    SftpTakeU32(R);
    E.MTime := UniversalTimeToLocal(UnixToDateTime(SftpTakeU32(R)));
  end;
  if (Flags and AttrExtended) <> 0 then
  begin
    Count := SftpTakeU32(R);
    I := 0;
    while (I < Count) and (not R.Bad) do
    begin
      SftpTakeStr(R);
      SftpTakeStr(R);
      Inc(I);
    end;
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

{ TSftpFS }

constructor TSftpFS.Create(AProc: TNetProc; AOwnsProc: Boolean);
begin
  inherited Create;
  FProc := AProc;
  FOwnsProc := AOwnsProc;
  FInPos := 1;
  FTimeoutMs := 30000;
  FExtensions := TStringList.Create;
end;

destructor TSftpFS.Destroy;
begin
  Disconnect;
  if FOwnsProc then
    FProc.Free;
  FExtensions.Free;
  inherited Destroy;
end;

{ Takes what the program wrote to its standard error, so that a program that fills the pipe is not stopped by it; the end of it is kept for the
  messages (ssh tells there why it could not connect). }
procedure TSftpFS.DrainErr;
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
function TSftpFS.Broke(const Text: AnsiString): Boolean;
var
  Tail: AnsiString;
begin
  FBroken := True;
  Tail := Trim(StringReplace(StringReplace(FErrTail, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Tail <> '' then
    Fail(rrFailed, Text + ' (the program said: ' + Tail + ')')
  else
    Fail(rrFailed, Text);
  Result := False;
end;

{ Takes one more piece of what the server wrote into FIn, waiting for it until Deadline. False (and the connection broken) when the time is over or
  the program ended. }
function TSftpFS.FillIn(Deadline: QWord): Boolean;
var
  Chunk: array[0..16383] of Char;
  N: Integer;
  Left: Int64;
begin
  Left := Int64(Deadline) - Int64(GetTickCount64);
  if Left <= 0 then
    Exit(Broke('the server did not answer in time'));
  if Left > 200 then
    Left := 200;
  N := FProc.Read(Chunk, SizeOf(Chunk), Integer(Left));
  DrainErr;
  if N < 0 then
    Exit(Broke('the server has ended'));
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

function TSftpFS.SendPacket(Kind: Byte; const Body: AnsiString): Boolean;
begin
  if not FProc.Write(SftpU32(Length(Body) + 1) + Chr(Kind) + Body) then
    Exit(Broke('cannot send to the server: ' + FProc.LastError));
  Result := True;
end;

{ The next packet: its type in Kind, a reader over its fields in R. False (and the connection broken) when it does not come whole in time or its
  length cannot be one. }
function TSftpFS.ReadPacket(Deadline: QWord; out Kind: Byte; out R: TSftpReader): Boolean;
var
  Head: TSftpReader;
  Len: LongWord;
begin
  Kind := 0;
  R := SftpReader('');
  while Length(FIn) - FInPos + 1 < 4 do
    if not FillIn(Deadline) then
      Exit(False);
  Head := SftpReader(Copy(FIn, FInPos, 4));
  Len := SftpTakeU32(Head);
  if (Len < 1) or (Len > MaxPacket) then
    Exit(Broke('the server sent a packet of ' + IntToStr(Len) + ' bytes, which cannot be one of SFTP'));
  while Length(FIn) - FInPos + 1 < 4 + Int64(Len) do
    if not FillIn(Deadline) then
      Exit(False);
  Kind := Ord(FIn[FInPos + 4]);
  R := SftpReader(Copy(FIn, FInPos + 5, Len - 1));
  Inc(FInPos, 4 + Integer(Len));
  Result := True;
end;

{ Sends a request of type Kind (its number, then Fields) and takes its answer: Reply is the type of the answer, R reads the fields after the number.
  False when the request could not be done at all (LastError tells, the connection is broken unless it was not there). }
function TSftpFS.Request(Kind: Byte; const Fields: AnsiString; out Reply: Byte; out R: TSftpReader): Boolean;
var
  Id: LongWord;
  Deadline: QWord;
begin
  Result := False;
  Reply := 0;
  R := SftpReader('');
  if (not FConnected) or FBroken then
  begin
    Fail(rrFailed, 'the connection is not open');
    Exit;
  end;
  Inc(FNextId);
  Id := FNextId;
  if not SendPacket(Kind, SftpU32(Id) + Fields) then
    Exit;
  Deadline := GetTickCount64 + QWord(FTimeoutMs);
  if not ReadPacket(Deadline, Reply, R) then
    Exit;
  if SftpTakeU32(R) <> Id then
  begin
    Broke('the answers are out of step');
    Exit;
  end;
  Result := True;
end;

{ The result for a STATUS answer (R after the number): rrOk for OK, else the code made a result and LastError the message of the server. }
function TSftpFS.StatusResult(var R: TSftpReader; const Path: AnsiString): TRemoteResult;
var
  Code: LongWord;
  Msg, Where: AnsiString;
begin
  Code := SftpTakeU32(R);
  Msg := SftpTakeStr(R);
  if Code = FxOk then
    Exit(rrOk);
  if Msg = '' then
    Msg := 'error ' + IntToStr(Code);
  Where := '';
  if Path <> '' then
    Where := ': ' + Path;
  case Code of
    FxEof, FxNoSuchFile: Result := rrNotFound;
    FxPermissionDenied: Result := rrDenied;
    FxOpUnsupported: Result := rrUnsupported;
  else
    Result := rrFailed;
  end;
  Result := Fail(Result, 'the server says: ' + Msg + Where);
end;

{ An answer of a type that the request cannot have: the two sides do not understand each other. }
function TSftpFS.Unexpected(Reply: Byte): TRemoteResult;
begin
  Broke('the server answered with a packet of type ' + IntToStr(Reply));
  Result := rrFailed;
end;

{ A request that answers with a HANDLE (OPENDIR, OPEN). }
function TSftpFS.AskHandle(Kind: Byte; const Fields, Path: AnsiString; out Handle: AnsiString): TRemoteResult;
var
  Reply: Byte;
  R: TSftpReader;
begin
  Handle := '';
  if not Request(Kind, Fields, Reply, R) then
    Exit(rrFailed);
  case Reply of
    FxpStatus:
    begin
      Result := StatusResult(R, Path);
      if Result = rrOk then
        Result := Unexpected(Reply);
    end;
    FxpHandle:
    begin
      Handle := SftpTakeStr(R);
      if R.Bad then
        Exit(Unexpected(Reply));
      Result := rrOk;
    end;
  else
    Result := Unexpected(Reply);
  end;
end;

{ A request that answers with a STATUS only (CLOSE, WRITE, the changes of the tree). }
function TSftpFS.AskStatus(Kind: Byte; const Fields, Path: AnsiString): TRemoteResult;
var
  Reply: Byte;
  R: TSftpReader;
begin
  if not Request(Kind, Fields, Reply, R) then
    Exit(rrFailed);
  if Reply <> FxpStatus then
    Exit(Unexpected(Reply));
  Result := StatusResult(R, Path);
end;

{ Lets the server forget a handle. For a file that was written the answer tells whether the last of the data reached the disk. }
function TSftpFS.CloseHandle(const Handle, Path: AnsiString): TRemoteResult;
begin
  Result := AskStatus(FxpClose, SftpStr(Handle), Path);
end;

{ Up to Len bytes of the open file Handle from Offset in Data; '' (and rrOk) at the end of the file. }
function TSftpFS.ReadAt(const Handle, Path: AnsiString; Offset: Int64; Len: Integer; out Data: AnsiString): TRemoteResult;
var
  Reply: Byte;
  R, Peek: TSftpReader;
begin
  Data := '';
  if not Request(FxpRead, SftpStr(Handle) + SftpU64(QWord(Offset)) + SftpU32(LongWord(Len)), Reply, R) then
    Exit(rrFailed);
  case Reply of
    FxpData:
    begin
      Data := SftpTakeStr(R);
      if R.Bad or (Length(Data) > Len) then
      begin
        Data := '';
        Exit(Unexpected(Reply));
      end;
      Result := rrOk;
    end;
    FxpStatus:
    begin
      Peek := R;
      if SftpTakeU32(Peek) = FxEof then
        Exit(rrOk);
      Result := StatusResult(R, Path);
      if Result = rrOk then
        Result := Unexpected(Reply);
    end;
  else
    Result := Unexpected(Reply);
  end;
end;

function TSftpFS.WriteAt(const Handle, Path: AnsiString; Offset: Int64; const Data: AnsiString): TRemoteResult;
begin
  Result := AskStatus(FxpWrite, SftpStr(Handle) + SftpU64(QWord(Offset)) + SftpStr(Data), Path);
end;

{ STAT or LSTAT of Path into Entry (without its name). }
function TSftpFS.AskAttrs(Kind: Byte; const Path: AnsiString; out Entry: TRemoteEntry): TRemoteResult;
var
  Reply: Byte;
  R: TSftpReader;
begin
  ClearEntry(Entry);
  if not Request(Kind, SftpStr(Path), Reply, R) then
    Exit(rrFailed);
  case Reply of
    FxpStatus:
    begin
      Result := StatusResult(R, Path);
      if Result = rrOk then
        Result := Unexpected(Reply);
    end;
    FxpAttrs:
    begin
      SftpTakeAttrs(R, Entry);
      if R.Bad then
        Exit(Unexpected(Reply));
      Result := rrOk;
    end;
  else
    Result := Unexpected(Reply);
  end;
end;

{ A request that answers with a NAME of one entry (REALPATH, READLINK): its file name. }
function TSftpFS.AskName(Kind: Byte; const Path: AnsiString; out Name: AnsiString): TRemoteResult;
var
  Reply: Byte;
  R: TSftpReader;
begin
  Name := '';
  if not Request(Kind, SftpStr(Path), Reply, R) then
    Exit(rrFailed);
  case Reply of
    FxpStatus:
    begin
      Result := StatusResult(R, Path);
      if Result = rrOk then
        Result := Unexpected(Reply);
    end;
    FxpName:
    begin
      if SftpTakeU32(R) < 1 then
        Exit(Unexpected(Reply));
      Name := SftpTakeStr(R);
      if R.Bad then
        Exit(Unexpected(Reply));
      Result := rrOk;
    end;
  else
    Result := Unexpected(Reply);
  end;
end;

function TSftpFS.Connect: TRemoteResult;
var
  Kind: Byte;
  R: TSftpReader;
  Name, Data: AnsiString;
begin
  if FConnected then
    Exit(rrOk);
  if (FProc = nil) or FBroken then
    Exit(Fail(rrFailed, 'the connection cannot be opened'));
  { INIT is the one packet without a number of request: its field is the version }
  if not SendPacket(FxpInit, SftpU32(ProtocolVersion)) then
    Exit(rrFailed);
  if not ReadPacket(GetTickCount64 + QWord(FTimeoutMs), Kind, R) then
    Exit(rrFailed);
  if Kind <> FxpVersion then
  begin
    Broke('the program does not answer as an SFTP server (a packet of type ' + IntToStr(Kind) + ' instead of VERSION)');
    Exit(rrFailed);
  end;
  FVersion := SftpTakeU32(R);
  if R.Bad or (FVersion < ProtocolVersion) then
  begin
    Broke('the server speaks SFTP version ' + IntToStr(FVersion) + ', version 3 is needed');
    Exit(rrFailed);
  end;
  FExtensions.Clear;
  while R.At <= Length(R.Data) do
  begin
    Name := SftpTakeStr(R);
    Data := SftpTakeStr(R);
    if R.Bad then
      Break;
    FExtensions.Add(Name + '=' + Data);
  end;
  FNextId := 0;
  FConnected := True;
  Result := rrOk;
end;

procedure TSftpFS.Disconnect;
var
  Chunk: array[0..511] of Char;
  Deadline: QWord;
begin
  if (FProc <> nil) and FConnected and (not FBroken) then
  begin
    { the server ends at the end of its input; it is given a moment for that before it is stopped }
    FProc.CloseInput;
    Deadline := GetTickCount64 + 2000;
    while (GetTickCount64 < Deadline) and (FProc.Read(Chunk, SizeOf(Chunk), 100) >= 0) do
      DrainErr;
  end;
  FConnected := False;
  FBroken := True;
  if FProc <> nil then
  begin
    FProc.CloseInput;
    FProc.Stop;
  end;
end;

function TSftpFS.RealPath(const Path: AnsiString; out Abs: AnsiString): TRemoteResult;
begin
  Result := AskName(FxpRealpath, Path, Abs);
end;

function TSftpFS.Extension(const Name: AnsiString; out Data: AnsiString): Boolean;
var
  I: Integer;
begin
  I := FExtensions.IndexOfName(Name);
  Result := I >= 0;
  if Result then
    Data := FExtensions.ValueFromIndex[I]
  else
    Data := '';
end;

function TSftpFS.List(const Dir: AnsiString; out Entries: TRemoteEntries): TRemoteResult;
var
  Clean, Handle: AnsiString;
  Reply: Byte;
  R, Peek: TSftpReader;
  Count, I: LongWord;
  N: Integer;
  E: TRemoteEntry;
begin
  SetLength(Entries, 0);
  if not RemoteCleanPath(Dir, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Dir));
  Result := AskHandle(FxpOpendir, SftpStr(Clean), Clean, Handle);
  if Result in [rrNotFound, rrFailed] then
  begin
    { the servers tell a file where a directory is needed in the words of their system (often "No such file"): the kind of the path decides }
    if (not FBroken) and (AskAttrs(FxpStat, Clean, E) = rrOk) then
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
  N := 0;
  try
    while True do
    begin
      if not Request(FxpReaddir, SftpStr(Handle), Reply, R) then
        Exit(rrFailed);
      if Reply = FxpStatus then
      begin
        Peek := R;
        if SftpTakeU32(Peek) = FxEof then
          Break;
        Result := StatusResult(R, Dir);
        if Result = rrOk then
          Result := Unexpected(Reply);
        Exit;
      end;
      if Reply <> FxpName then
        Exit(Unexpected(Reply));
      Count := SftpTakeU32(R);
      I := 0;
      while (I < Count) and (not R.Bad) do
      begin
        ClearEntry(E);
        E.Name := SftpTakeStr(R);
        SftpTakeStr(R);                { the long name, a line of "ls -l" for people }
        SftpTakeAttrs(R, E);
        if (not R.Bad) and (E.Name <> '') and (E.Name <> '.') and (E.Name <> '..') then
        begin
          if N >= Length(Entries) then
            SetLength(Entries, N + 64);
          Entries[N] := E;
          Inc(N);
        end;
        Inc(I);
      end;
      if R.Bad then
        Exit(Unexpected(Reply));
    end;
    Result := rrOk;
  finally
    SetLength(Entries, N);
    if not FBroken then
      CloseHandle(Handle, Dir);
    if Result <> rrOk then
      SetLength(Entries, 0);
  end;
end;

function TSftpFS.Stat(const Path: AnsiString; FollowLinks: Boolean; out Entry: TRemoteEntry): TRemoteResult;
var
  Clean, Dir, Name, Target: AnsiString;
begin
  ClearEntry(Entry);
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  RemoteSplit(Clean, Dir, Name);
  if FollowLinks then
  begin
    Result := AskAttrs(FxpStat, Clean, Entry);
    { a link whose target is not there is told as the link itself }
    if (Result = rrNotFound) and (not FBroken) then
    begin
      if (AskAttrs(FxpLstat, Clean, Entry) = rrOk) and (Entry.Kind = rkLink) then
        Result := rrOk
      else if FBroken then
        Result := rrFailed
      else
        Result := Fail(rrNotFound, 'not found: ' + Path);
    end;
  end
  else
    Result := AskAttrs(FxpLstat, Clean, Entry);
  if Result <> rrOk then
  begin
    ClearEntry(Entry);
    Exit;
  end;
  if (Entry.Kind = rkLink) and (AskName(FxpReadlink, Clean, Target) = rrOk) then
    Entry.LinkTarget := Target
  else if FBroken then
  begin
    ClearEntry(Entry);
    Exit(rrFailed);
  end;
  Entry.Name := Name;
  Result := rrOk;
end;

type
  TSftpReadStream = class(TStream)
  private
    FFS: TSftpFS;
    FHandle, FPath: AnsiString;
    FPos, FSize, FBufStart: Int64;
    FBuf: AnsiString;
  protected
    function GetSize: Int64; override;
  public
    constructor Create(AFS: TSftpFS; const AHandle, APath: AnsiString; ASize: Int64);
    destructor Destroy; override;
    function Read(var Buffer; Count: LongInt): LongInt; override;
    function Write(const Buffer; Count: LongInt): LongInt; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

constructor TSftpReadStream.Create(AFS: TSftpFS; const AHandle, APath: AnsiString; ASize: Int64);
begin
  inherited Create;
  FFS := AFS;
  FHandle := AHandle;
  FPath := APath;
  FSize := ASize;
end;

destructor TSftpReadStream.Destroy;
begin
  if FFS.Connected and (not FFS.FBroken) then
    FFS.CloseHandle(FHandle, FPath);
  inherited Destroy;
end;

function TSftpReadStream.GetSize: Int64;
begin
  Result := FSize;
end;

function TSftpReadStream.Read(var Buffer; Count: LongInt): LongInt;
var
  Data: AnsiString;
  Take: Integer;
  Dest: PChar;
begin
  Result := 0;
  Dest := @Buffer;
  while Count > 0 do
  begin
    if (FPos < FBufStart) or (FPos >= FBufStart + Length(FBuf)) then
    begin
      if FFS.ReadAt(FHandle, FPath, FPos, DataChunk, Data) <> rrOk then
        raise EReadError.Create(FFS.LastError);
      FBuf := Data;
      FBufStart := FPos;
      if Data = '' then
      begin
        { the end of the file, as the server sees it now (the file may have changed since it was opened) }
        FSize := FPos;
        Break;
      end;
      if FBufStart + Length(FBuf) > FSize then
        FSize := FBufStart + Length(FBuf);
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

function TSftpReadStream.Write(const Buffer; Count: LongInt): LongInt;
begin
  Result := 0;
  raise EWriteError.Create('the stream of a remote file is for reading only');
end;

function TSftpReadStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
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
  TSftpWriteStream = class(TStream)
  private
    FFS: TSftpFS;
    FHandle, FPath: AnsiString;
    FPos, FSize: Int64;
  protected
    function GetSize: Int64; override;
  public
    constructor Create(AFS: TSftpFS; const AHandle, APath: AnsiString);
    destructor Destroy; override;
    function Read(var Buffer; Count: LongInt): LongInt; override;
    function Write(const Buffer; Count: LongInt): LongInt; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

constructor TSftpWriteStream.Create(AFS: TSftpFS; const AHandle, APath: AnsiString);
begin
  inherited Create;
  FFS := AFS;
  FHandle := AHandle;
  FPath := APath;
end;

{ The answer to CLOSE cannot be passed on from here: a failure is left in LastError of the file system. }
destructor TSftpWriteStream.Destroy;
begin
  if FFS.Connected and (not FFS.FBroken) then
    FFS.CloseHandle(FHandle, FPath);
  inherited Destroy;
end;

function TSftpWriteStream.GetSize: Int64;
begin
  Result := FSize;
end;

function TSftpWriteStream.Read(var Buffer; Count: LongInt): LongInt;
begin
  Result := 0;
  raise EReadError.Create('the stream of a remote file is for writing only');
end;

function TSftpWriteStream.Write(const Buffer; Count: LongInt): LongInt;
var
  Data: AnsiString;
  Src: PByte;
  Take: Integer;
begin
  Result := 0;
  if Count < 0 then
    raise EWriteError.Create('the number of bytes to write is negative');
  if FPos > High(Int64) - Count then
    raise EWriteError.Create('the file position is too large');
  Src := @Buffer;
  while Result < Count do
  begin
    Take := Count - Result;
    if Take > DataChunk then
      Take := DataChunk;
    SetLength(Data, Take);
    Move(Src^, Data[1], Take);
    if FFS.WriteAt(FHandle, FPath, FPos, Data) <> rrOk then
      raise EWriteError.Create(FFS.LastError);
    Inc(FPos, Take);
    Inc(Src, Take);
    Inc(Result, Take);
    if FPos > FSize then
      FSize := FPos;
  end;
end;

function TSftpWriteStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
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

function TSftpFS.OpenRead(const Path: AnsiString; out Stream: TStream): TRemoteResult;
var
  Clean, Handle: AnsiString;
  E: TRemoteEntry;
begin
  Stream := nil;
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  { the kind decides first: a server opens a directory for reading too, and the open of a pipe would wait for a writer }
  Result := Stat(Clean, True, E);
  if Result <> rrOk then
    Exit;
  case E.Kind of
    rkDir: Exit(Fail(rrIsDir, 'is a directory: ' + Path));
    rkLink: Exit(Fail(rrNotFound, 'the link points to nothing: ' + Path));
    rkOther: Exit(Fail(rrFailed, 'not a regular file: ' + Path));
  end;
  Result := AskHandle(FxpOpen, SftpStr(Clean) + SftpU32(FxfRead) + SftpU32(0), Clean, Handle);
  if Result <> rrOk then
    Exit;
  if E.Size < 0 then
    E.Size := 0;
  Stream := TSftpReadStream.Create(Self, Handle, Clean, E.Size);
end;

function TSftpFS.OpenWrite(const Path: AnsiString; out Stream: TStream): TRemoteResult;
var
  Clean, Handle: AnsiString;
  E: TRemoteEntry;
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
  Result := AskHandle(FxpOpen, SftpStr(Clean) + SftpU32(FxfWrite or FxfCreat or FxfTrunc) + SftpU32(0), Clean, Handle);
  if Result <> rrOk then
    Exit;
  Stream := TSftpWriteStream.Create(Self, Handle, Clean);
end;

function TSftpFS.MkDir(const Path: AnsiString): TRemoteResult;
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
  Result := AskStatus(FxpMkdir, SftpStr(Clean) + SftpU32(0), Clean);
end;

function TSftpFS.Remove(const Path: AnsiString): TRemoteResult;
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
  { a link to a directory is a link and goes with REMOVE }
  if E.Kind <> rkDir then
    Exit(AskStatus(FxpRemove, SftpStr(Clean), Clean));
  Result := AskStatus(FxpRmdir, SftpStr(Clean), Clean);
  { the servers tell a directory with content as a failure of any kind: its list decides }
  if (Result in [rrFailed, rrDenied]) and (not FBroken) and (List(Clean, Entries) = rrOk) and (Length(Entries) > 0) then
    Result := Fail(rrNotEmpty, 'the directory is not empty: ' + Path);
end;

function TSftpFS.Rename(const OldPath, NewPath: AnsiString): TRemoteResult;
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
  Result := Stat(NewClean, False, E);
  if Result = rrOk then
    Exit(Fail(rrExists, 'already exists: ' + NewPath));
  if Result <> rrNotFound then
    Exit;
  Result := AskStatus(FxpRename, SftpStr(OldClean) + SftpStr(NewClean), OldClean);
end;

function TSftpFS.SetMode(const Path: AnsiString; Mode: LongInt): TRemoteResult;
var
  Clean: AnsiString;
begin
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  if (Mode < 0) or (Mode > &7777) then
    Exit(Fail(rrFailed, 'the permission bits are not right: ' + Path));
  Result := AskStatus(FxpSetstat, SftpStr(Clean) + SftpU32(AttrPermissions) + SftpU32(LongWord(Mode)), Clean);
end;

function OpenSftpSsh(const Url: AnsiString; out FS: TSftpFS; out Err: AnsiString): TRemoteResult;
var
  U: TNetUrl;
  Args: TSshArgs;
  Purpose: TSshPurpose;
  Proc: TNetProc;
begin
  FS := nil;
  Result := rrFailed;
  if not NetSplitUrl(Url, SshDefaultPort, U, Err) then
    Exit;
  if (not SshPurposeOf(U.Scheme, Purpose)) or (Purpose <> spSftp) then
  begin
    Err := 'not an address of SFTP (sftp://): ' + Url;
    Exit;
  end;
  if not SshArgs(U, spSftp, Args, Err) then
    Exit;
  Proc := TNetProc.Create;
  if not Proc.Start(SshProgram, Args) then
  begin
    Err := Proc.LastError;
    Proc.Free;
    Exit;
  end;
  FS := TSftpFS.Create(Proc, True);
  Result := FS.Connect;
  if Result <> rrOk then
  begin
    Err := FS.LastError;
    FreeAndNil(FS);
  end;
end;

{$ENDIF}

end.
