program t_ftpfs;
{ Tests of src/ftpfs.pas: the listings of FTP servers, on lines made for the test in each form (MLSD of RFC 3659, LIST as "ls -l", DOS/IIS,
  NetWare); then TFtpFS against pyftpdlib (python3 -m pyftpdlib, an anonymous server over a tree made for the test, on a port of this machine).
  On CI a pyftpdlib that is not found is a failure, elsewhere the checks that need it are left out. }
{$mode objfpc}{$H+}
uses SysUtils, Classes, DateUtils, BaseUnix, Process, RemoteFS, FtpFS;
{$I dntest.inc}

var
  E: TRemoteEntry;

function At(Y, Mo, D, H, Mi, S: Word): TDateTime;
begin
  Result := EncodeDateTime(Y, Mo, D, H, Mi, S, 0);
end;

procedure CheckMlsx;
begin
  Check(FtpParseMlsx('type=file;size=1234;modify=20200203040506;unix.mode=0640;perm=adfr; plain.txt', E), 'mlsd: a file');
  Check((E.Name = 'plain.txt') and (E.Kind = rkFile) and (E.Size = 1234) and (E.Mode = &640), 'mlsd: its name, kind, size and mode');
  Check(E.MTime = UniversalTimeToLocal(At(2020, 2, 3, 4, 5, 6)), 'mlsd: the time is UTC, given as a time of this machine');
  Check(FtpParseMlsx('type=dir;sizd=4096;modify=20200203040506.123;perm=flcdmpe; sub dir', E), 'mlsd: a directory');
  Check((E.Name = 'sub dir') and (E.Kind = rkDir) and (E.Size = -1) and (E.Mode = -1), 'mlsd: a name with a blank, no size, no mode');
  Check(E.MTime = UniversalTimeToLocal(At(2020, 2, 3, 4, 5, 6)), 'mlsd: a time with a fraction');
  Check(not FtpParseMlsx('type=cdir;modify=20200203040506; /pub', E), 'mlsd: the directory itself is left out');
  Check(not FtpParseMlsx('type=pdir;modify=20200203040506; ..', E), 'mlsd: the parent is left out');
  Check(FtpParseMlsx('Type=File;Size=5;Modify=20200203040506; name;with;semicolons', E), 'mlsd: facts in another case');
  Check((E.Name = 'name;with;semicolons') and (E.Kind = rkFile) and (E.Size = 5), 'mlsd: a name with ";" is whole');
  Check(FtpParseMlsx('type=file;size=1;  two blanks', E) and (E.Name = ' two blanks'), 'mlsd: the name is all after the first blank');
  Check(FtpParseMlsx('type=OS.unix=slink:/target/path;modify=20200203040506; link', E), 'mlsd: a link of a Unix server');
  Check((E.Kind = rkLink) and (E.LinkTarget = '/target/path') and (E.Name = 'link'), 'mlsd: the link and its target');
  Check(FtpParseMlsx('type=OS.unix=symlink; l2', E) and (E.Kind = rkLink) and (E.LinkTarget = ''), 'mlsd: a link without its target');
  Check(FtpParseMlsx('type=OS.unix=blkdev; sda', E) and (E.Kind = rkOther), 'mlsd: another type of the server');
  Check(FtpParseMlsx(' no-facts', E) and (E.Name = 'no-facts') and (E.Kind = rkFile) and (E.Size = -1), 'mlsd: a line without facts');
  Check(FtpParseMlsx('type=file;size=7; crlf' + #13, E) and (E.Name = 'crlf'), 'mlsd: the CR of the line end is not in the name');
  Check(FtpParseMlsx('type=file;size=x;modify=2020;unix.mode=0999; bad', E), 'mlsd: facts that cannot be read');
  Check((E.Size = -1) and (E.MTime = 0) and (E.Mode = -1), 'mlsd: are left unknown');
  Check(FtpParseMlsx('type=file;size=5000000000; big', E) and (E.Size = 5000000000), 'mlsd: a size above 4 GiB');
  Check(FtpParseMlsx('type=file;unix.mode=0o4755; py', E) and (E.Mode = &4755), 'mlsd: a mode written as 0o4755');
  Check(FtpParseMlsx('type=file;unix.mode=0o; py', E) and (E.Mode = -1), 'mlsd: 0o alone is not a mode');
  Check(not FtpParseMlsx('garbage', E), 'mlsd: a line without a blank');
  Check(not FtpParseMlsx('type=file;size=1; ', E), 'mlsd: a line without a name');
  Check(not FtpParseMlsx('', E), 'mlsd: an empty line');
end;

procedure CheckUnix;
var
  Summer, Winter: TDateTime;
begin
  Summer := At(2020, 6, 1, 12, 0, 0);
  Winter := At(2020, 1, 15, 12, 0, 0);
  Check(FtpParseList('-rw-r-----   1 user  group      1234 Feb  3 04:05 plain.txt', Summer, E), 'ls: a file');
  Check((E.Name = 'plain.txt') and (E.Kind = rkFile) and (E.Size = 1234) and (E.Mode = &640), 'ls: its name, kind, size and mode');
  Check(E.MTime = At(2020, 2, 3, 4, 5, 0), 'ls: a time without a year is of this year');
  Check(FtpParseList('-rw-r-----   1 user  group      1234 Feb  3 04:05 plain.txt', Winter, E) and (E.MTime = At(2019, 2, 3, 4, 5, 0)),
    'ls: and of the year before when it would be after now');
  Check(FtpParseList('-rw-r--r--   1 user  group         1 Jan 16 10:00 tomorrow', Winter, E) and (E.MTime = At(2020, 1, 16, 10, 0, 0)),
    'ls: a day after now is still this year (clocks differ)');
  Check(FtpParseList('-rw-r--r--   1 user  group         1 Feb 29 10:00 leap', At(2021, 6, 1, 0, 0, 0), E) and
    (E.MTime = At(2020, 2, 29, 10, 0, 0)), 'ls: Feb 29 without a year is of the last leap year');
  Check(FtpParseList('drwxr-xr-x   2 user group 4096 Jan  1  2019 sub dir', Summer, E), 'ls: a directory');
  Check((E.Name = 'sub dir') and (E.Kind = rkDir) and (E.Mode = &755) and (E.MTime = At(2019, 1, 1, 0, 0, 0)), 'ls: with a year, a blank in the name');
  Check(FtpParseList('lrwxrwxrwx 1 u g 3 Mar 10 12:00 link -> sub', Summer, E), 'ls: a link');
  Check((E.Kind = rkLink) and (E.Name = 'link') and (E.LinkTarget = 'sub'), 'ls: the link and its target');
  Check(FtpParseList('-rwsr-sr-t 1 u g 0 Mar 10 2018 special', Summer, E) and (E.Mode = &7755), 'ls: s and t');
  Check(FtpParseList('-rwSr-Sr-T 1 u g 0 Mar 10 2018 special', Summer, E) and (E.Mode = &7644), 'ls: S and T');
  Check(FtpParseList('crw-rw-rw- 1 root root 1, 3 Mar 10 2018 null', Summer, E), 'ls: a device');
  Check((E.Kind = rkOther) and (E.Size = -1) and (E.Name = 'null'), 'ls: is of the other kind, without a size');
  Check(FtpParseList('-rw-r--r-- 1 owner 1234 Jan 1 2020 nogroup', Summer, E) and (E.Size = 1234) and (E.Name = 'nogroup'), 'ls: no group');
  Check(FtpParseList('-rw-r--r-- user group 77 Jan 1 2020 nolinks', Summer, E) and (E.Size = 77), 'ls: no count of links');
  Check(FtpParseList('-rw-r--r--+ 1 u g 5 Jan 1 2020 acl', Summer, E) and (E.Mode = &644), 'ls: a mark of an ACL');
  Check(FtpParseList('-rw-r--r-- 1 u g 5 Jan 1 2020  two blanks', Summer, E) and (E.Name = ' two blanks'), 'ls: one blank before the name');
  Check(FtpParseList('-rw-r--r-- 1 user 12 Jan 1 2020 Jan 1 2020', Summer, E) and (E.Name = 'Jan 1 2020') and (E.Size = 12),
    'ls: a name that looks like a date');
  Check(FtpParseList('-rw-r--r-- 1 u g 5000000000 Jan 1 2020 big', Summer, E) and (E.Size = 5000000000), 'ls: a size above 4 GiB');
  Check(FtpParseList('-rw-r--r-- 1 u g 5 jan 1 2020 lower' + #13, Summer, E) and (E.Name = 'lower'), 'ls: a month in small letters, a CR');
  Check(not FtpParseList('total 12', Summer, E), 'ls: the total');
  Check(not FtpParseList('', Summer, E), 'ls: an empty line');
  Check(not FtpParseList('-rw-r--r-- 1 u g 5 Foo 1 2020 name', Summer, E), 'ls: not a month');
  Check(not FtpParseList('-rw-r--r-- 1 u g 5 Jan 1 2020', Summer, E), 'ls: no name');
  Check(not FtpParseList('-rwxr-xr-q 1 u g 5 Jan 1 2020 bad', Summer, E), 'ls: a mode that is not one');
  Check(not FtpParseList('-rw-r--r-- 1 u g 5 Jan 32 2020 bad', Summer, E), 'ls: a day that is not one');
end;

procedure CheckDosNetWare;
var
  Now: TDateTime;
begin
  Now := At(2020, 6, 1, 12, 0, 0);
  Check(FtpParseList('02-03-20  04:05PM       <DIR>          sub dir', Now, E), 'dos: a directory');
  Check((E.Kind = rkDir) and (E.Name = 'sub dir') and (E.Size = -1) and (E.MTime = At(2020, 2, 3, 16, 5, 0)), 'dos: its name and time');
  Check(FtpParseList('02-03-2020  11:15AM              1234 file.txt', Now, E), 'dos: a file with a year of four digits');
  Check((E.Kind = rkFile) and (E.Size = 1234) and (E.Name = 'file.txt') and (E.MTime = At(2020, 2, 3, 11, 15, 0)) and (E.Mode = -1),
    'dos: its size and time');
  Check(FtpParseList('12-31-99  12:00AM 5 old', Now, E) and (E.MTime = At(1999, 12, 31, 0, 0, 0)), 'dos: 99 and midnight');
  Check(FtpParseList('02-03-20  12:30PM 5 noon', Now, E) and (E.MTime = At(2020, 2, 3, 12, 30, 0)), 'dos: noon');
  Check(FtpParseList('02-03-20  17:45 1,234,567 comma', Now, E) and (E.Size = 1234567) and (E.MTime = At(2020, 2, 3, 17, 45, 0)),
    'dos: a time of 24 hours and a size with commas');
  Check(not FtpParseList('13-03-20  04:05PM 5 bad', Now, E), 'dos: a month that is not one');
  Check(not FtpParseList('02-03-20  13:05PM 5 bad', Now, E), 'dos: an hour that is not one');

  Check(FtpParseList('d [RWCEAFMS] admin                512 Feb 03 04:05 SYSTEM', Now, E), 'netware: a directory');
  Check((E.Kind = rkDir) and (E.Name = 'SYSTEM') and (E.MTime = At(2020, 2, 3, 4, 5, 0)), 'netware: its name and time');
  Check(FtpParseList('- [R----F--] admin              1234 Jan 01  2019 file name.txt', Now, E), 'netware: a file');
  Check((E.Kind = rkFile) and (E.Size = 1234) and (E.Name = 'file name.txt') and (E.MTime = At(2019, 1, 1, 0, 0, 0)), 'netware: its size and name');
  Check((E.Mode = -1) and (E.LinkTarget = ''), 'netware: no mode, nothing from the forms tried before');
end;

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

function IndexOf(const Entries: TRemoteEntries; const Name: AnsiString): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Entries) do
    if Entries[I].Name = Name then
      Exit(I);
  Result := -1;
end;

function HavePyftpdlib: Boolean;
var
  Output: AnsiString;
begin
  Result := RunCommand('python3', ['-c', 'import pyftpdlib'], Output) and (Trim(Output) = '');
end;

{ The names, kinds and sizes of the files of List against TLocalFS over the same tree, leaving out the links (a server may tell what they point to). }
function SameAsLocal(const Remote, Want: TRemoteEntries): Boolean;
var
  I, J, Links: Integer;
begin
  Result := True;
  Links := 0;
  for I := 0 to High(Want) do
  begin
    if Want[I].Kind = rkLink then
    begin
      Inc(Links);
      Continue;
    end;
    J := IndexOf(Remote, Want[I].Name);
    if (J < 0) or (Remote[J].Kind <> Want[I].Kind) or ((Want[I].Kind = rkFile) and (Remote[J].Size <> Want[I].Size)) then
    begin
      WriteLn('  differs: "', Want[I].Name, '"');
      Result := False;
    end;
  end;
  if Length(Remote) <> Length(Want) then
  begin
    WriteLn('  ', Length(Remote), ' entries, the reference has ', Length(Want));
    Result := False;
  end;
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

{ OpenRead and OpenWrite against the server; the files are compared with what this machine reads. }
procedure CheckStreams(FS: TFtpFS; const Base: AnsiString);
var
  Stream: TStream;
  Big, Got: AnsiString;
  Buf: array[0..9] of Char;
  Raised: Boolean;
  Entries: TRemoteEntries;
begin
  Big := BigData;
  Check(FS.OpenRead('/big.bin', Stream) = rrOk, 'a file of 1 MiB is opened for reading: ' + FS.LastError);
  if Stream <> nil then
  begin
    Check(Stream.Size = Length(Big), 'its size');
    Check(FS.List('/', Entries) = rrFailed, 'while it is open the connection is its own: ' + FS.LastError);
    Got := ReadAll(Stream, 70000);
    Check(Got = Big, 'it is read whole: ' + IntToStr(Length(Got)) + ' bytes');
    Stream.Position := 4995;
    Stream.ReadBuffer(Buf, 10);
    Check(CompareByte(Buf, Big[4996], 10) = 0, 'a read after Seek (REST and RETR again)');
    Stream.Seek(-10, soEnd);
    Check((Stream.Read(Buf, 10) = 10) and (CompareByte(Buf, Big[Length(Big) - 9], 10) = 0) and (Stream.Read(Buf, 10) = 0),
      'the last bytes, then the end');
    Stream.Position := 1000;
    Stream.ReadBuffer(Buf, 10);
    Check(CompareByte(Buf, Big[1001], 10) = 0, 'a Seek back, in the middle of a transfer');
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
  Check(FS.List('/', Entries) = rrOk, 'after the stream (aborted in the middle) is freed the connection answers: ' + FS.LastError);

  Check(FS.OpenRead('/plain.txt', Stream) = rrOk, 'a small file is opened');
  if Stream <> nil then
  begin
    Check(ReadAll(Stream, 1) = 'abc', 'read one byte at a time');
    Stream.Free;
  end;
  Check(FS.OpenRead('/empty-file', Stream) = rrOk, 'an empty file is opened');
  if Stream <> nil then
  begin
    Check((Stream.Size = 0) and (ReadAll(Stream, 10) = ''), 'it has nothing');
    Stream.Free;
  end;
  Check((FS.OpenRead('/sub', Stream) = rrIsDir) and (Stream = nil), 'a directory is not read');
  Check((FS.OpenRead('/no-such', Stream) = rrNotFound) and (Stream = nil), 'a missing file is not found');
  Check((FS.OpenRead('relative', Stream) = rrDenied) and (Stream = nil), 'a path that is not absolute is refused');

  Check(FS.OpenWrite('/up.bin', Stream) = rrOk, 'a new file is opened for writing: ' + FS.LastError);
  if Stream <> nil then
  begin
    WriteText(Stream, Big, 7000);
    Check((Stream.Size = Length(Big)) and (Stream.Position = Length(Big)), 'the stream counts what was written');
    Raised := False;
    try
      Stream.Position := 10;
    except
      on EWriteError do
        Raised := True;
    end;
    Check(Raised, 'a write stream does not go back');
    Stream.Free;
  end;
  Check(LoadText(Base + '/up.bin') = Big, '1 MiB written in pieces of 7000 bytes is the same on the disk');
  Check(FS.OpenWrite('/with space.txt', Stream) = rrOk, 'a file that is there is opened for writing');
  if Stream <> nil then
  begin
    WriteText(Stream, 'xy', 10);
    Stream.Free;
  end;
  Check(LoadText(Base + '/with space.txt') = 'xy', 'it was emptied first');
  Check(FS.OpenWrite('/caf' + #195#169 + ' new.txt', Stream) = rrOk, 'a name in UTF-8 with a blank is written');
  if Stream <> nil then
  begin
    WriteText(Stream, 'u', 10);
    Stream.Free;
  end;
  Check(LoadText(Base + '/caf' + #195#169 + ' new.txt') = 'u', 'it is on the disk');
  Check(FS.OpenWrite('/empty-new', Stream) = rrOk, 'a file is made without writing to it');
  Stream.Free;
  Check(FileExists(Base + '/empty-new') and (LoadText(Base + '/empty-new') = ''), 'it is there and empty');
  Check((FS.OpenWrite('/sub', Stream) = rrIsDir) and (Stream = nil), 'a directory is not written');
  Check((FS.OpenWrite('/', Stream) = rrIsDir) and (Stream = nil), 'the root is not written');
  Check((FS.OpenWrite('/no-such/f', Stream) = rrNotFound) and (Stream = nil), 'a file in a missing directory: ' + FS.LastError);
  Check((FS.OpenWrite('/plain.txt/f', Stream) = rrNotFound) and (Stream = nil), 'a file under a file');
  Check(FS.Connected, 'the refusals leave the connection open');
end;

{ MkDir, Remove, Rename and SetMode in a tree of their own; what they did is looked at on this machine. }
procedure CheckChanges(FS: TFtpFS; const Base: AnsiString);
var
  C, H, Odd: AnsiString;
  St: Stat;
  Entries: TRemoteEntries;
begin
  C := '/ch';
  H := Base + C;
  Odd := C + '/caf' + #195#169 + ' dir';
  ForceDirectories(H + '/full/inner');
  PutText(H + '/file.txt', 'f');
  PutText(H + '/taken.txt', 't');
  PutText(H + '/full/x', 'x');

  Check(FS.MkDir(C + '/new') = rrOk, 'MkDir: ' + FS.LastError);
  Check(DirectoryExists(H + '/new'), 'the directory is made');
  Check((FS.MkDir(Odd) = rrOk) and DirectoryExists(Base + Odd), 'MkDir of a name in UTF-8 with a blank');
  Check(FS.MkDir(C + '/new') = rrExists, 'MkDir of a directory that is there');
  Check(FS.MkDir(C + '/file.txt') = rrExists, 'MkDir of a file that is there');
  Check(FS.MkDir(C + '/no-such/x') = rrNotFound, 'MkDir in a missing directory');
  Check(FS.MkDir(C + '/file.txt/x') = rrNotDir, 'MkDir under a file');
  Check(FS.MkDir('/') = rrExists, 'the root is there');

  Check(FS.SetMode(C + '/file.txt', &600) = rrOk, 'SetMode (SITE CHMOD): ' + FS.LastError);
  Check((fpStat(H + '/file.txt', St) = 0) and ((St.st_mode and &777) = &600), 'the permissions are set');
  Check(FS.SetMode(C + '/no-such', &600) = rrNotFound, 'SetMode of a missing path');
  Check(FS.SetMode(C + '/file.txt', &10000) = rrFailed, 'a mode above 7777 is refused');

  Check(FS.Rename(C + '/file.txt', C + '/moved.txt') = rrOk, 'Rename of a file: ' + FS.LastError);
  Check((not FileExists(H + '/file.txt')) and (LoadText(H + '/moved.txt') = 'f'), 'the file has its new name and its content');
  Check(FS.Rename(C + '/moved.txt', C + '/taken.txt') = rrExists, 'Rename onto a name that is taken');
  Check((LoadText(H + '/moved.txt') = 'f') and (LoadText(H + '/taken.txt') = 't'), 'nothing is overwritten');
  Check(FS.Rename(C + '/no-such', C + '/x') = rrNotFound, 'Rename of a missing path');
  Check(FS.Rename(C + '/full', Odd + '/full') = rrOk, 'Rename of a directory with content into another one');
  Check(FileExists(Base + Odd + '/full/x') and (not DirectoryExists(H + '/full')), 'it moved whole');
  Check(FS.Rename(Odd + '/full', C + '/full') = rrOk, 'and back');
  Check(FS.Rename('/', C + '/r') = rrDenied, 'the root is not renamed');

  Check(FS.Remove(C + '/full') = rrNotEmpty, 'Remove of a directory with content: ' + FS.LastError);
  Check(FileExists(H + '/full/x'), 'it stays');
  Check((FS.Remove(C + '/moved.txt') = rrOk) and (not FileExists(H + '/moved.txt')), 'Remove of a file');
  Check((FS.Remove(C + '/new') = rrOk) and (not DirectoryExists(H + '/new')), 'Remove of an empty directory');
  Check(FS.Remove(C + '/no-such') = rrNotFound, 'Remove of a missing path');
  Check(FS.Remove('/') = rrDenied, 'the root is not removed');
  Check((FS.List(C, Entries) = rrOk) and (Length(Entries) = 3), 'what is left: full, taken.txt and the directory in UTF-8 (' +
    IntToStr(Length(Entries)) + ')');
  Check(FS.Connected, 'the refusals leave the connection open');
end;

procedure CheckServer(const Base: AnsiString; Port: Integer; Stamp: LongInt);
var
  FS: TFtpFS;
  Local: TLocalFS;
  Remote, Want: TRemoteEntries;
  Dir: AnsiString;
  I: Integer;
begin
  FS := TFtpFS.Create;
  try
    FS.TimeoutMs := 5000;
    Check(FS.Connect('127.0.0.1', Port, 'no-such-user', 'x') = rrDenied, 'a login that the server does not know is refused: ' + FS.LastError);
  finally
    FS.Free;
  end;
  FS := TFtpFS.Create;
  try
    FS.TimeoutMs := 3000;
    Check(FS.Connect('127.0.0.1', 1, 'anonymous', 'x') = rrFailed, 'a port where nothing listens fails');
    Check(not FS.Connected, 'not connected');
  finally
    FS.Free;
  end;

  FS := TFtpFS.Create;
  Local := TLocalFS.Create(Base);
  try
    Check(FS.Connect('127.0.0.1', Port, 'anonymous', 'dn@') = rrOk, 'Connect: ' + FS.LastError);
    Check(FS.Connected and FS.HasFeature('MLST') and FS.UseMlsd, 'the server tells MLST, the lists are of MLSD');
    Check((FS.Pwd(Dir) = rrOk) and (Dir = '/'), 'PWD: ' + Dir);

    Check(FS.List('/', Remote) = rrOk, 'the tree is listed: ' + FS.LastError);
    Check(Local.List('/', Want) = rrOk, 'the reference lists the tree');
    Check(SameAsLocal(Remote, Want), 'MLSD: every name, kind and size is that of the reference');
    Check(IndexOf(Remote, 'with space.txt') >= 0, 'a name with a blank');
    Check(IndexOf(Remote, ' lead and trail ') >= 0, 'a name with blanks at both ends');
    Check(IndexOf(Remote, 'caf' + #195#169 + '.txt') >= 0, 'a name in UTF-8');
    I := IndexOf(Remote, 'plain.txt');
    Check(I >= 0, 'plain.txt is in the list');
    if I >= 0 then
    begin
      Check((Remote[I].Kind = rkFile) and (Remote[I].Size = 3), 'it is a file of 3 bytes');
      Check(Remote[I].Mode = &640, 'its permissions are 640');
      Check(Abs(Remote[I].MTime - FileDateToDateTime(Stamp)) < 2 / 86400, 'its time is the time that was set');
    end;
    Check((FS.List('/many', Remote) = rrOk) and (Length(Remote) = 300), 'a long list is whole: ' + IntToStr(Length(Remote)));
    Check((FS.List('/sub/', Remote) = rrOk) and (Length(Remote) = 1) and (Remote[0].Name = 'inner.bin') and (Remote[0].Size = 1000),
      'a path with "/" at the end');
    Check((FS.List('/dir with space', Remote) = rrOk) and (Length(Remote) = 1), 'a directory with a blank in its name');
    Check((FS.List('/empty', Remote) = rrOk) and (Length(Remote) = 0), 'an empty directory');
    Check(FS.List('/plain.txt', Remote) = rrNotDir, 'a file is not a directory: ' + FS.LastError);
    Check(FS.List('/no-such', Remote) = rrNotFound, 'a missing directory is not found: ' + FS.LastError);
    Check(FS.List('relative', Remote) = rrDenied, 'a path that is not absolute is refused');

    Check(FS.Stat('/plain.txt', False, E) = rrOk, 'stat of a file: ' + FS.LastError);
    Check((E.Name = 'plain.txt') and (E.Kind = rkFile) and (E.Size = 3) and (E.Mode = &640), 'its name, kind, size and permissions');
    Check((FS.Stat('/sub', True, E) = rrOk) and (E.Kind = rkDir) and (E.Name = 'sub'), 'stat of a directory');
    Check((FS.Stat('/dir with space', True, E) = rrOk) and (E.Kind = rkDir), 'stat of a directory with a blank');
    Check((FS.Stat('/', True, E) = rrOk) and (E.Kind = rkDir), 'the root is a directory');
    Check((FS.Stat('/link', True, E) = rrOk) and (E.Kind = rkDir), 'a link followed is a directory');
    Check(FS.Stat('/no-such', True, E) = rrNotFound, 'a missing path is not found: ' + FS.LastError);

    { LIST: the same tree as "ls -l" from the server }
    FS.UseMlsd := False;
    Check(FS.List('/', Remote) = rrOk, 'LIST: the tree is listed: ' + FS.LastError);
    Check(SameAsLocal(Remote, Want), 'LIST: every name, kind and size is that of the reference');
    Check((FS.List('/dir with space', Remote) = rrOk) and (Length(Remote) = 1), 'LIST: a directory with a blank in its name');
    Check((FS.List('/many', Remote) = rrOk) and (Length(Remote) = 300), 'LIST: a long list');
    Check(FS.List('/no-such', Remote) = rrNotFound, 'LIST: a missing directory');
    FS.UseMlsd := True;

    CheckStreams(FS, Base);
    CheckChanges(FS, Base);

    FS.Disconnect;
    Check(not FS.Connected, 'Disconnect ends the session');
    Check(FS.List('/', Remote) = rrFailed, 'nothing can be asked after it');
  finally
    Local.Free;
    FS.Free;
  end;
end;

{ Starts pyftpdlib over Base on a free port of this machine and waits until it answers; the port, or 0. The server that answers must be this one
  (a server of another run may hold the port, and then this one cannot start): it must show the file of the marker of this run, and still run. }
function StartServer(const Base: AnsiString; out Server: TProcess): Integer;
var
  Try_, Waited: Integer;
  FS: TFtpFS;
  E: TRemoteEntry;
  Up: Boolean;
  Marker: AnsiString;
begin
  Marker := '/.dn-test-' + IntToStr(fpGetPid);
  PutText(Base + Marker, '');
  Result := 0;
  Server := nil;
  for Try_ := 0 to 4 do
  begin
    Result := 20000 + (fpGetPid * 7 + Try_ * 997) mod 30000;
    Server := TProcess.Create(nil);
    Server.Executable := '/bin/sh';
    Server.Parameters.Add('-c');
    Server.Parameters.Add('exec python3 -m pyftpdlib -w -i 127.0.0.1 -p ' + IntToStr(Result) + ' -d "$0" >/dev/null 2>&1');
    Server.Parameters.Add(Base);
    Server.Execute;
    Up := False;
    Waited := 0;
    while (not Up) and Server.Running and (Waited < 10000) do
    begin
      Sleep(100);
      Inc(Waited, 100);
      FS := TFtpFS.Create;
      FS.TimeoutMs := 2000;
      Up := (FS.Connect('127.0.0.1', Result, 'anonymous', 'dn@') = rrOk) and (FS.Stat(Marker, False, E) = rrOk) and Server.Running;
      FS.Free;
    end;
    if Up then
    begin
      DeleteFile(Base + Marker);
      Exit;
    end;
    if Server.Running then
      Server.Terminate(1);
    Server.WaitOnExit;
    FreeAndNil(Server);
  end;
  Result := 0;
end;

var
  Tmp, Base: AnsiString;
  Stamp: LongInt;
  I, Port: Integer;
  Server: TProcess;
begin
  CheckMlsx;
  CheckUnix;
  CheckDosNetWare;

  if not HavePyftpdlib then
  begin
    if GetEnvironmentVariable('CI') <> '' then
      Check(False, 'pyftpdlib is installed')
    else
      WriteLn('SKIP the checks against pyftpdlib: it is not installed');
    Finish;
    Exit;
  end;
  Tmp := GetEnvironmentVariable('TMPDIR');
  if Tmp = '' then
    Tmp := '/tmp';
  Base := Tmp + '/ftpfs-' + IntToStr(fpGetPid);
  RemoveTree(Base);
  Check(ForceDirectories(Base + '/sub') and ForceDirectories(Base + '/many') and ForceDirectories(Base + '/empty') and
    ForceDirectories(Base + '/dir with space'), 'the test tree is made');
  PutText(Base + '/plain.txt', 'abc');
  PutText(Base + '/with space.txt', 'hello world');
  PutText(Base + '/ lead and trail ', '');
  PutText(Base + '/caf' + #195#169 + '.txt', 'x');
  PutText(Base + '/sub/inner.bin', StringOfChar('z', 1000));
  PutText(Base + '/dir with space/f', 'f');
  PutText(Base + '/big.bin', BigData);
  PutText(Base + '/empty-file', '');
  for I := 1 to 300 do
    PutText(Base + '/many/file-' + IntToStr(I) + '-' + StringOfChar('n', 40), '');
  fpChmod(Base + '/plain.txt', &640);
  Stamp := DateTimeToFileDate(EncodeDate(2020, 2, 3) + EncodeTime(4, 5, 6, 0));
  FileSetDate(Base + '/plain.txt', Stamp);
  fpSymlink(PChar('sub'), PChar(Base + '/link'));
  Port := StartServer(Base, Server);
  Check(Port > 0, 'pyftpdlib answers');
  try
    if Port > 0 then
      CheckServer(Base, Port, Stamp);
  finally
    if Server <> nil then
    begin
      if Server.Running then
        Server.Terminate(1);
      Server.WaitOnExit;
      Server.Free;
    end;
    RemoveTree(Base);
  end;
  Finish;
end.
