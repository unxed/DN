program t_sftpfs;
{ Tests of src/sftpfs.pas: the SFTP client. The fields of the packets are checked on bytes made by hand; the file system is checked against the
  sftp-server of this machine (OpenSSH, started directly, without ssh), over a directory tree made for the test. DN_SFTP_SERVER names the server
  when it is not in a usual place; on CI a server that is not found is a failure, elsewhere the checks that need it are left out. }
{$mode objfpc}{$H+}
uses SysUtils, Classes, DateUtils, BaseUnix, RemoteFS, NetProc, SftpFS;
{$I dntest.inc}

procedure PutText(const Path, Text: AnsiString);
var
  F: TFileStream;
begin
  F := TFileStream.Create(Path, fmCreate);
  try
    if Text <> '' then
      F.WriteBuffer(Text[1], Length(Text));
  finally
    F.Free;
  end;
end;

procedure RemoveTree(const Dir: AnsiString);
var
  SR: TSearchRec;
begin
  if FindFirst(Dir + '/*', faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        if ((SR.Attr and faDirectory) <> 0) and ((SR.Attr and faSymLink) = 0) then
          RemoveTree(Dir + '/' + SR.Name)
        else
          DeleteFile(Dir + '/' + SR.Name);
      end;
    until FindNext(SR) <> 0;
  end;
  FindClose(SR);
  RemoveDir(Dir);
end;

function LoadText(const Path: AnsiString): AnsiString;
var
  F: TFileStream;
begin
  Result := '';
  try
    F := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Result, F.Size);
      if Length(Result) > 0 then
        F.ReadBuffer(Result[1], Length(Result));
    finally
      F.Free;
    end;
  except
    on Exception do
      Result := '';
  end;
end;

{ 1 MiB: a run of zero bytes, every value of a byte, then bytes that do not repeat soon. }
function BigData: AnsiString;
var
  I: Integer;
  V: LongWord;
begin
  SetLength(Result, 1048576);
  V := 12345;
  for I := 1 to Length(Result) do
    if I <= 5000 then
      Result[I] := #0
    else if I <= 5000 + 256 * 4 then
      Result[I] := Chr((I - 5001) mod 256)
    else
    begin
      V := V * 1103515245 + 12345;
      Result[I] := Chr((V shr 16) and $FF);
    end;
end;

{ All of a stream, read in pieces of Piece bytes. }
function ReadAll(S: TStream; Piece: Integer): AnsiString;
var
  Buf: AnsiString;
  N: Integer;
begin
  Result := '';
  SetLength(Buf, Piece);
  repeat
    N := S.Read(Buf[1], Piece);
    Result := Result + Copy(Buf, 1, N);
  until N = 0;
end;

procedure WriteText(S: TStream; const Text: AnsiString; Piece: Integer);
var
  P, N: Integer;
begin
  P := 1;
  while P <= Length(Text) do
  begin
    N := Length(Text) - P + 1;
    if N > Piece then
      N := Piece;
    S.WriteBuffer(Text[P], N);
    Inc(P, N);
  end;
end;

function IndexOf(const Entries: TRemoteEntries; const Name: AnsiString): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Entries) do
    if Entries[I].Name = Name then
      Exit(I);
  Result := -1;
end;

function FindServer: AnsiString;
const
  Places: array[0..4] of AnsiString = ('/usr/lib/openssh/sftp-server', '/usr/libexec/openssh/sftp-server', '/usr/libexec/sftp-server',
    '/usr/lib/ssh/sftp-server', '/usr/lib/sftp-server');
var
  I: Integer;
begin
  Result := GetEnvironmentVariable('DN_SFTP_SERVER');
  if Result <> '' then
    Exit;
  for I := 0 to High(Places) do
    if FileExists(Places[I]) then
      Exit(Places[I]);
end;

{ The fields of the packets, on bytes made by hand. }
procedure CheckFields;
var
  R: TSftpReader;
  E: TRemoteEntry;
  Attrs: AnsiString;
begin
  Check(SftpU32($01020304) = #1#2#3#4, 'a number of 4 bytes is big endian');
  Check(SftpU64($0102030405060708) = #1#2#3#4#5#6#7#8, 'a number of 8 bytes is big endian');
  Check(SftpStr('ab') = #0#0#0#2'ab', 'a string is its length and its bytes');

  R := SftpReader(#7 + SftpU32($FFFFFFFE) + SftpU64(QWord(1) shl 40) + SftpStr('name') + SftpStr(''));
  Check(SftpTakeByte(R) = 7, 'a byte is read');
  Check(SftpTakeU32(R) = $FFFFFFFE, 'a number of 4 bytes is read');
  Check(SftpTakeU64(R) = QWord(1) shl 40, 'a number of 8 bytes is read');
  Check(SftpTakeStr(R) = 'name', 'a string is read');
  Check(SftpTakeStr(R) = '', 'an empty string is read');
  Check((not R.Bad) and (R.At = Length(R.Data) + 1), 'all the fields are taken and none was short');
  SftpTakeByte(R);
  Check(R.Bad, 'a field past the end is told');

  R := SftpReader(#0#0#0#9'abc');
  Check((SftpTakeStr(R) = '') and R.Bad, 'a string longer than the packet is told');
  R := SftpReader(#0#0);
  Check((SftpTakeU32(R) = 0) and R.Bad, 'a short number is told');

  { size, owner, permissions of a directory, times, one extended pair }
  Attrs := SftpU32($8000000F) + SftpU64(4096) + SftpU32(1000) + SftpU32(1000) + SftpU32(&040755) + SftpU32(1500000000) + SftpU32(1580000000) +
    SftpU32(1) + SftpStr('x@y') + SftpStr('z');
  R := SftpReader(Attrs + 'rest');
  E.Name := 'keep';
  SftpTakeAttrs(R, E);
  Check(not R.Bad, 'attributes with every field are read');
  Check(E.Kind = rkDir, 'the kind comes from the permissions');
  Check(E.Mode = &755, 'the mode is the permission bits');
  Check(E.Size = 4096, 'the size is read');
  Check(E.MTime = UniversalTimeToLocal(UnixToDateTime(1580000000)), 'the time is the modification time');
  Check(E.Name = 'keep', 'the name is left as it was');
  Check(Copy(R.Data, R.At, 4) = 'rest', 'the reader stops after the attributes');

  R := SftpReader(SftpU32(4) + SftpU32(&120777));
  SftpTakeAttrs(R, E);
  Check((E.Kind = rkLink) and (E.Mode = &777) and (E.Size = -1) and (E.MTime = 0), 'a link with only its permissions');
  R := SftpReader(SftpU32(4) + SftpU32(&020644));
  SftpTakeAttrs(R, E);
  Check(E.Kind = rkOther, 'a device is of the other kind');
  R := SftpReader(SftpU32(0));
  SftpTakeAttrs(R, E);
  Check((not R.Bad) and (E.Kind = rkFile) and (E.Mode = -1) and (E.Size = -1), 'attributes without fields');
  R := SftpReader(SftpU32(1) + #0#0);
  SftpTakeAttrs(R, E);
  Check(R.Bad, 'short attributes are told');
end;

{ A program that is not an SFTP server is refused at Connect. }
procedure CheckNotServer(const Exe, Tag, Want: AnsiString);
var
  Proc: TNetProc;
  FS: TSftpFS;
  Entries: TRemoteEntries;
begin
  if not FileExists(Exe) then
    Exit;
  Proc := TNetProc.Create;
  Check(Proc.Start(Exe, []), Tag + ': the program starts');
  FS := TSftpFS.Create(Proc, True);
  try
    FS.TimeoutMs := 5000;
    Check(FS.Connect = rrFailed, Tag + ': Connect fails');
    Check(Pos(Want, FS.LastError) > 0, Tag + ': the message tells why (' + Copy(FS.LastError, 1, 120) + ')');
    Check(not FS.Connected, Tag + ': not connected');
    Check(FS.List('/', Entries) = rrFailed, Tag + ': nothing can be asked');
  finally
    FS.Free;
  end;
end;

{ OpenRead and OpenWrite against the server; the files are compared with what this machine reads. }
procedure CheckStreams(FS: TSftpFS; const Base: AnsiString);
var
  Stream: TStream;
  Big, Got: AnsiString;
  Buf: array[0..9] of Char;
  Raised: Boolean;
  E: TRemoteEntry;
begin
  Big := BigData;

  Check(FS.OpenRead(Base + '/plain.txt', Stream) = rrOk, 'a file is opened for reading: ' + FS.LastError);
  if Stream <> nil then
  begin
    Check(Stream.Size = 3, 'the stream has the size of the file');
    Check(ReadAll(Stream, 100) = 'abc', 'the content of a small file');
    Raised := False;
    try
      Stream.Write(Buf, 1);
    except
      on EWriteError do
        Raised := True;
    end;
    Check(Raised, 'a stream for reading does not write');
    Stream.Free;
  end;

  Check(FS.OpenRead(Base + '/big.bin', Stream) = rrOk, 'a file of 1 MiB is opened');
  if Stream <> nil then
  begin
    Check(Stream.Size = Length(Big), 'its size');
    Got := ReadAll(Stream, 70000);
    Check(Got = Big, 'it is read whole in pieces larger than those of the server: ' + IntToStr(Length(Got)) + ' bytes');
    Stream.Position := 4995;
    Stream.ReadBuffer(Buf, 10);
    Check(CompareByte(Buf, Big[4996], 10) = 0, 'a read after Seek, across the end of the zero bytes');
    Stream.Seek(-10, soEnd);
    Check((Stream.Read(Buf, 10) = 10) and (CompareByte(Buf, Big[Length(Big) - 9], 10) = 0) and (Stream.Read(Buf, 10) = 0),
      'the last bytes, then the end');
    Stream.Position := 40000;
    Check(ReadAll(Stream, 1) = Copy(Big, 40001, Length(Big)), 'a read one byte at a time from the middle');
    Stream.Free;
  end;

  Check(FS.OpenRead(Base + '/empty-file', Stream) = rrOk, 'an empty file is opened');
  if Stream <> nil then
  begin
    Check((Stream.Size = 0) and (ReadAll(Stream, 10) = ''), 'it has nothing');
    Stream.Free;
  end;
  Check(FS.OpenRead(Base + '/with space.txt', Stream) = rrOk, 'a name with a blank is opened');
  if Stream <> nil then
  begin
    Check(ReadAll(Stream, 4) = 'hello world', 'its content');
    Stream.Free;
  end;

  Check((FS.OpenRead(Base + '/sub', Stream) = rrIsDir) and (Stream = nil), 'a directory is not read');
  Check((FS.OpenRead(Base + '/no-such', Stream) = rrNotFound) and (Stream = nil), 'a missing file is not found');
  Check((FS.OpenRead(Base + '/dangling', Stream) = rrNotFound) and (Stream = nil), 'a link to nothing is not found');
  Check((FS.OpenRead('relative', Stream) = rrDenied) and (Stream = nil), 'a path that is not absolute is refused');
  fpMkFifo(PChar(Base + '/pipe'), &600);
  Check((FS.OpenRead(Base + '/pipe', Stream) = rrFailed) and (Stream = nil), 'a pipe is not opened (the server would wait for a writer)');
  Check((FS.OpenWrite(Base + '/pipe', Stream) = rrFailed) and (Stream = nil), 'nor written');
  DeleteFile(Base + '/pipe');

  Check(FS.OpenWrite(Base + '/up.bin', Stream) = rrOk, 'a new file is opened for writing: ' + FS.LastError);
  if Stream <> nil then
  begin
    WriteText(Stream, Big, 7000);
    Check(Stream.Size = Length(Big), 'the stream counts what was written');
    Raised := False;
    try
      Stream.Read(Buf, 1);
    except
      on EReadError do
        Raised := True;
    end;
    Check(Raised, 'a stream for writing does not read');
    Stream.Free;
  end;
  Check(LoadText(Base + '/up.bin') = Big, '1 MiB written in pieces of 7000 bytes is the same on the disk');

  Check(FS.OpenWrite(Base + '/plain.txt', Stream) = rrOk, 'a file that is there is opened for writing');
  if Stream <> nil then
  begin
    WriteText(Stream, 'xy', 10);
    Stream.Free;
  end;
  Check(LoadText(Base + '/plain.txt') = 'xy', 'it was emptied first');
  Check((FS.Stat(Base + '/plain.txt', False, E) = rrOk) and (E.Mode = &640), 'its permissions stay');

  Check(FS.OpenWrite(Base + '/gap.bin', Stream) = rrOk, 'a file is written with a gap');
  if Stream <> nil then
  begin
    WriteText(Stream, 'ab', 10);
    Stream.Position := 10;
    WriteText(Stream, 'Z', 10);
    Check(Stream.Size = 11, 'the size counts the gap');
    Stream.Free;
  end;
  Check(LoadText(Base + '/gap.bin') = 'ab' + StringOfChar(#0, 8) + 'Z', 'the gap is zero bytes');

  Check(FS.OpenWrite(Base + '/caf' + #195#169 + ' new.txt', Stream) = rrOk, 'a name in UTF-8 with a blank is written');
  if Stream <> nil then
  begin
    WriteText(Stream, 'u', 10);
    Stream.Free;
  end;
  Check(LoadText(Base + '/caf' + #195#169 + ' new.txt') = 'u', 'it is on the disk');
  Check(FS.OpenWrite(Base + '/empty-new', Stream) = rrOk, 'a file is made without writing to it');
  Stream.Free;
  Check(FileExists(Base + '/empty-new') and (LoadText(Base + '/empty-new') = ''), 'it is there and empty');

  Check((FS.OpenWrite(Base + '/sub', Stream) = rrIsDir) and (Stream = nil), 'a directory is not written');
  Check((FS.OpenWrite('/', Stream) = rrIsDir) and (Stream = nil), 'the root is not written');
  Check((FS.OpenWrite(Base + '/no-such/f', Stream) = rrNotFound) and (Stream = nil), 'a file in a missing directory: ' + FS.LastError);
  Check((FS.OpenWrite(Base + '/plain.txt/f', Stream) = rrNotFound) and (Stream = nil), 'a file under a file');
  if fpGetUID <> 0 then
  begin
    fpChmod(Base + '/closed', &555);
    Check((FS.OpenWrite(Base + '/closed/f', Stream) = rrDenied) and (Stream = nil), 'a directory that cannot be written is not allowed');
    fpChmod(Base + '/closed', &755);
    fpChmod(Base + '/up.bin', &000);
    Check((FS.OpenRead(Base + '/up.bin', Stream) = rrDenied) and (Stream = nil), 'a file that cannot be read is not allowed');
    fpChmod(Base + '/up.bin', &644);
  end;
  Check(FS.Connected, 'the refusals leave the connection open');
end;

procedure CheckServer(const Server, Base: AnsiString; Stamp: LongInt);
var
  Proc: TNetProc;
  FS: TSftpFS;
  Local: TLocalFS;
  Remote, Want: TRemoteEntries;
  E: TRemoteEntry;
  Abs1, Abs2, Data: AnsiString;
  I, J: Integer;
  Same: Boolean;
begin
  Proc := TNetProc.Create;
  Check(Proc.Start(Server, []), 'sftp-server starts: ' + Server + ' ' + Proc.LastError);
  FS := TSftpFS.Create(Proc, True);
  Local := TLocalFS.Create('/');
  try
    Check(FS.Connect = rrOk, 'Connect: ' + FS.LastError);
    Check(FS.Connected and (FS.Version = 3), 'the server speaks version 3');
    Check(FS.Connect = rrOk, 'a second Connect is nothing');
    Check(FS.Extension('posix-rename@openssh.com', Data) and (Data = '1'), 'the extensions of VERSION are kept (OpenSSH tells posix-rename)');
    Check((not FS.Extension('no-such@dn', Data)) and (Data = ''), 'an extension that was not told is not there');

    Check((FS.RealPath('.', Abs1) = rrOk) and (Abs1 <> '') and (Abs1[1] = '/'), 'RealPath of "." is absolute: ' + Abs1);
    Check((FS.RealPath(Base, Abs1) = rrOk) and (FS.RealPath(Base + '/sub/../sub/..', Abs2) = rrOk) and (Abs1 = Abs2),
      'RealPath takes ".." back');

    { the list against TLocalFS over the same tree }
    Check(FS.List(Base, Remote) = rrOk, 'the tree is listed: ' + FS.LastError);
    Check(Local.List(Base, Want) = rrOk, 'the reference lists the tree');
    Check(Length(Remote) = Length(Want), 'as many entries as the reference: ' + IntToStr(Length(Remote)) + ' and ' + IntToStr(Length(Want)));
    Same := True;
    for I := 0 to High(Want) do
    begin
      J := IndexOf(Remote, Want[I].Name);
      if (J < 0) or (Remote[J].Kind <> Want[I].Kind) or ((Want[I].Kind = rkFile) and (Remote[J].Size <> Want[I].Size)) then
      begin
        WriteLn('  differs: ', Want[I].Name);
        Same := False;
      end;
    end;
    Check(Same, 'every name, kind and size is that of the reference');
    Check(IndexOf(Remote, '.') + IndexOf(Remote, '..') = -2, 'no "." or ".."');
    Check(IndexOf(Remote, 'with space.txt') >= 0, 'a name with a blank');
    Check(IndexOf(Remote, ' lead and trail ') >= 0, 'a name with blanks at both ends');
    Check(IndexOf(Remote, 'caf' + #195#169 + '.txt') >= 0, 'a name in UTF-8');
    Check(IndexOf(Remote, 'new' + #10 + 'line') >= 0, 'a name with a line end in it');
    I := IndexOf(Remote, 'plain.txt');
    Check(I >= 0, 'plain.txt is in the list');
    if I >= 0 then
    begin
      Check((Remote[I].Kind = rkFile) and (Remote[I].Size = 3), 'it is a file of 3 bytes');
      Check(Remote[I].Mode = &640, 'its permissions are 640');
      Check(Abs(Remote[I].MTime - FileDateToDateTime(Stamp)) < 2 / 86400, 'its time is the time that was set');
    end;
    I := IndexOf(Remote, 'link');
    Check((I >= 0) and (Remote[I].Kind = rkLink), 'a link is a link in the list');

    Check((FS.List(Base + '/many', Remote) = rrOk) and (Length(Remote) = 300), 'a list longer than one answer of the server is whole: ' +
      IntToStr(Length(Remote)));
    Check((FS.List(Base + '/sub/', Remote) = rrOk) and (Length(Remote) = 1) and (Remote[0].Name = 'inner.bin') and (Remote[0].Size = 1000),
      'a path with "/" at the end');
    Check(FS.List(Base + '/empty', Remote) = rrOk, 'an empty directory is listed');
    Check(Length(Remote) = 0, 'it has nothing');
    Check(FS.List(Base + '/plain.txt', Remote) = rrNotDir, 'a file is not a directory: ' + FS.LastError);
    Check(FS.List(Base + '/no-such', Remote) = rrNotFound, 'a missing directory is not found: ' + FS.LastError);
    Check(FS.List('relative', Remote) = rrDenied, 'a path that is not absolute is refused');
    Check((FS.List('/', Remote) = rrOk) and (Length(Remote) > 0), 'the root is listed');

    { stat }
    Check(FS.Stat(Base + '/plain.txt', False, E) = rrOk, 'stat of a file');
    Check((E.Name = 'plain.txt') and (E.Kind = rkFile) and (E.Size = 3) and (E.Mode = &640), 'its name, kind, size and permissions');
    Check(FS.Stat(Base + '/link', False, E) = rrOk, 'stat of a link');
    Check((E.Kind = rkLink) and (E.LinkTarget = 'sub'), 'the link and its target: ' + E.LinkTarget);
    Check((FS.Stat(Base + '/link', True, E) = rrOk) and (E.Kind = rkDir) and (E.Name = 'link'), 'a link followed is what it points to');
    Check((FS.Stat(Base + '/dangling', True, E) = rrOk) and (E.Kind = rkLink) and (E.LinkTarget = 'no-such-target'),
      'a link to nothing, followed, is the link');
    Check((FS.Stat(Base + '/sub', True, E) = rrOk) and (E.Kind = rkDir) and (E.Name = 'sub'), 'stat of a directory');
    Check((FS.Stat('/', True, E) = rrOk) and (E.Kind = rkDir), 'the root is a directory');
    Check(FS.Stat(Base + '/no-such', True, E) = rrNotFound, 'a missing path is not found (followed)');
    Check(FS.Stat(Base + '/no-such', False, E) = rrNotFound, 'a missing path is not found');
    Check(FS.Stat(Base + '/plain.txt/x', False, E) = rrNotFound, 'a path under a file is not found');
    Check((FS.Stat(Base + '/with space.txt', False, E) = rrOk) and (E.Size = 11), 'stat of a name with a blank');

    if fpGetUID <> 0 then
    begin
      fpChmod(Base + '/closed', &000);
      Check(FS.List(Base + '/closed', Remote) = rrDenied, 'a directory that cannot be read is not allowed: ' + FS.LastError);
      fpChmod(Base + '/closed', &755);
    end;

    CheckStreams(FS, Base);

    { the part that follows }
    Check(FS.MkDir(Base + '/d') = rrUnsupported, 'MkDir is not done yet');
    Check(FS.Remove(Base + '/plain.txt') = rrUnsupported, 'Remove is not done yet');
    Check(FS.Rename(Base + '/plain.txt', Base + '/p') = rrUnsupported, 'Rename is not done yet');
    Check(FS.SetMode(Base + '/plain.txt', &600) = rrUnsupported, 'SetMode is not done yet');
    Check(FS.Connected, 'the refusals leave the connection open');
    Check((FS.Stat(Base + '/plain.txt', False, E) = rrOk) and (E.Mode = &640) and FileExists(Base + '/plain.txt') and
      (not DirectoryExists(Base + '/d')) and (not FileExists(Base + '/p')), 'and nothing was changed');

    FS.Disconnect;
    Check(not FS.Connected, 'Disconnect ends the session');
    Check(FS.List(Base, Remote) = rrFailed, 'nothing can be asked after it');
    FS.Disconnect;
    Check(not Proc.Running, 'the server has ended');
  finally
    Local.Free;
    FS.Free;
  end;
end;

var
  Server, Tmp, Base: AnsiString;
  Stamp: LongInt;
  I: Integer;
begin
  CheckFields;
  CheckNotServer('/bin/cat', 'cat', 'does not answer as an SFTP server');
  CheckNotServer('/bin/true', 'true', 'has ended');

  Server := FindServer;
  if Server = '' then
  begin
    if GetEnvironmentVariable('CI') <> '' then
      Check(False, 'sftp-server is installed (DN_SFTP_SERVER names it)')
    else
      WriteLn('SKIP the checks against sftp-server: it is not installed (DN_SFTP_SERVER names it)');
    Finish;
    Exit;
  end;

  Tmp := GetEnvironmentVariable('TMPDIR');
  if Tmp = '' then
    Tmp := '/tmp';
  Base := Tmp + '/sftpfs-' + IntToStr(fpGetPid);
  RemoveTree(Base);
  Check(ForceDirectories(Base + '/sub') and ForceDirectories(Base + '/many') and ForceDirectories(Base + '/empty') and
    ForceDirectories(Base + '/closed') and ForceDirectories(Base + '/new' + #10 + 'line'), 'the test tree is made');
  PutText(Base + '/plain.txt', 'abc');
  PutText(Base + '/with space.txt', 'hello world');
  PutText(Base + '/ lead and trail ', '');
  PutText(Base + '/caf' + #195#169 + '.txt', 'x');
  PutText(Base + '/sub/inner.bin', StringOfChar('z', 1000));
  PutText(Base + '/big.bin', BigData);
  PutText(Base + '/empty-file', '');
  for I := 1 to 300 do
    PutText(Base + '/many/file-' + IntToStr(I) + '-' + StringOfChar('n', 40), '');
  fpChmod(Base + '/plain.txt', &640);
  Stamp := DateTimeToFileDate(EncodeDate(2020, 2, 3) + EncodeTime(4, 5, 6, 0));
  FileSetDate(Base + '/plain.txt', Stamp);
  fpSymlink(PChar('sub'), PChar(Base + '/link'));
  fpSymlink(PChar('no-such-target'), PChar(Base + '/dangling'));
  try
    CheckServer(Server, Base, Stamp);
  finally
    fpChmod(Base + '/closed', &755);
    RemoveTree(Base);
  end;
  Finish;
end.
