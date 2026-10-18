program t_fishfs;
{ Tests of src/fishfs.pas: the FISH+ client. The program on the other side is a shell of this machine (/bin/sh, and bash and dash where they are), which
  gets the helper script of third-party/f4-fish/helper.sh; the host is a directory tree made for the test, and TLocalFS over the same tree is the reference. }
{$mode objfpc}{$H+}
uses SysUtils, Classes, DateUtils, BaseUnix, RemoteFS, NetProc, FishFS;
{$I dntest.inc}

const
  HelperPath = '../third-party/f4-fish/helper.sh';

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

{ The index of the entry called Name, -1 when it is not there. }
function IndexOf(const L: TRemoteEntries; const Name: AnsiString): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(L) do
    if L[I].Name = Name then
      Exit(I);
end;

{ The list of Dir from the remote side has the same names, kinds and sizes of files as the list of the same directory from TLocalFS. }
procedure CompareLists(const Tag: AnsiString; FS: TFishFS; Local: TLocalFS; const Dir: AnsiString);
var
  Remote, Want: TRemoteEntries;
  R: TRemoteResult;
  I, J: Integer;
  Same, SameKind, SameSize: Boolean;
begin
  R := FS.List(Dir, Remote);
  Check(R = rrOk, Tag + 'the list of ' + Dir + ' is taken: ' + FS.LastError);
  Check(Local.List(Dir, Want) = rrOk, Tag + 'the reference list is taken');
  if (R <> rrOk) then
    Exit;
  Check(Length(Remote) = Length(Want), Tag + 'the same number of entries as the reference');
  Same := True;
  SameKind := True;
  SameSize := True;
  for I := 0 to High(Want) do
  begin
    J := IndexOf(Remote, Want[I].Name);
    if J < 0 then
    begin
      Same := False;
      Continue;
    end;
    if Remote[J].Kind <> Want[I].Kind then
      SameKind := False;
    if (Want[I].Kind = rkFile) and (Remote[J].Size <> Want[I].Size) then
      SameSize := False;
  end;
  Check(Same, Tag + 'every name of the reference is in the list');
  Check(SameKind, Tag + 'the kinds are the same');
  Check(SameSize, Tag + 'the sizes of the files are the same');
end;

procedure RunWithShell(const Shell, Helper, Base, Weird: AnsiString);
var
  Tag, Dir, Dir2: AnsiString;
  P: TNetProc;
  FS: TFishFS;
  Local: TLocalFS;
  Remote: TRemoteEntries;
  E: TRemoteEntry;
  R: TRemoteResult;
  I: Integer;
  Want: TDateTime;
begin
  Tag := ExtractFileName(Shell) + ': ';
  P := TNetProc.Create;
  Check(P.Start(Shell, []), Tag + 'the shell is started');
  FS := TFishFS.Create(P, True);
  Local := TLocalFS.Create(Base);
  try
    FS.TimeoutMs := 20000;
    R := FS.Connect(Helper);
    Check(R = rrOk, Tag + 'the helper is sent and answers: ' + FS.LastError);
    if R <> rrOk then
      Exit;
    Check(FS.Connected, Tag + 'the connection is open');
    Check(FS.HasFeature('base64'), Tag + 'the banner names the base64 decoder');
    Check(FS.FeatureValue('mode') <> '', Tag + 'the banner names the tool of the lists');
    Check(not FS.HasFeature('no-such-feature'), Tag + 'a word that is not in the banner is not there');

    Check((FS.Pwd(Dir) = rrOk) and (Length(Dir) > 0) and (Dir[1] = '/'), Tag + 'the directory of the shell is told');

    { the lists }
    CompareLists(Tag, FS, Local, '/');
    CompareLists(Tag, FS, Local, '/sub');
    CompareLists(Tag, FS, Local, '/sub/');
    Check(FS.List('/sub/../sub/.', Remote) = rrOk, Tag + 'a path is made clean before it is sent');
    Check(FS.List('/sub/..', Remote) = rrOk, Tag + 'the parent of a directory is listed');
    Check(FS.List('/..', Remote) = rrDenied, Tag + 'a path that leaves the root is refused');
    Check(FS.List('sub', Remote) = rrDenied, Tag + 'a path that is not absolute is refused');
    Check(FS.List('/no-such-directory-here', Remote) = rrNotFound, Tag + 'a directory that is not there is not found');
    Check(FS.List('/plain.txt', Remote) = rrNotDir, Tag + 'a file is not a directory');
    Check(Length(Remote) = 0, Tag + 'a failed list gives no entries');
    Check(FS.Connected, Tag + 'the refusals leave the connection open');

    { the fields of an entry }
    Check(FS.List('/', Remote) = rrOk, Tag + 'the root is listed');
    I := IndexOf(Remote, 'plain.txt');
    Check(I >= 0, Tag + 'plain.txt is in the list');
    if I >= 0 then
    begin
      Check(Remote[I].Kind = rkFile, Tag + 'it is a file');
      Check(Remote[I].Size = 3, Tag + 'its size is 3');
      Check(Remote[I].Mode = &640, Tag + 'its permissions are 640');
      Want := EncodeDate(2020, 2, 3) + EncodeTime(4, 5, 6, 0);
      Check(Abs(Remote[I].MTime - Want) < 3 / 86400, Tag + 'its time is the time that was set');
    end;
    Check(IndexOf(Remote, ' lead and trail ') >= 0, Tag + 'a name with blanks at both ends is whole');
    Check(IndexOf(Remote, 'with space.txt') >= 0, Tag + 'a name with a blank in it is whole');
    Check(IndexOf(Remote, 'caf' + #195#169 + '.txt') >= 0, Tag + 'a name that is not ASCII is whole');
    Check((IndexOf(Remote, '.') < 0) and (IndexOf(Remote, '..') < 0), Tag + 'the list has neither "." nor ".."');
    I := IndexOf(Remote, 'link');
    Check((I >= 0) and (Remote[I].Kind = rkLink), Tag + 'a link is a link in the list');

    { one entry }
    Check(FS.Stat('/plain.txt', False, E) = rrOk, Tag + 'Stat of a file');
    Check((E.Name = 'plain.txt') and (E.Kind = rkFile) and (E.Size = 3) and (E.Mode = &640), Tag + 'the entry is the file');
    Check((FS.Stat('/sub', False, E) = rrOk) and (E.Kind = rkDir) and (E.Name = 'sub'), Tag + 'Stat of a directory');
    Check((FS.Stat('/', False, E) = rrOk) and (E.Kind = rkDir) and (E.Name = ''), Tag + 'Stat of the root');
    Check((FS.Stat('/link', False, E) = rrOk) and (E.Kind = rkLink), Tag + 'Stat of a link without following it');
    Check((FS.Stat('/link', True, E) = rrOk) and (E.Kind = rkDir), Tag + 'Stat of a link to a directory with following it');
    Check((FS.Stat('/dangling', True, E) = rrOk) and (E.Kind = rkLink), Tag + 'a link to nothing stays a link');
    Check(FS.Stat('/nothing-here', False, E) = rrNotFound, Tag + 'Stat of what is not there');
    Check(FS.Stat('plain.txt', False, E) = rrDenied, Tag + 'Stat of a path that is not absolute');
    Check((FS.Stat('/with space.txt', False, E) = rrOk) and (E.Size = 11) and (E.Name = 'with space.txt'), Tag + 'Stat of a name with a blank');

    { the paths that a line cannot carry }
    Dir := Weird + '/new' + #10 + 'line';
    Check(FS.List(Dir, Remote) = rrOk, Tag + 'a directory with a line end in its name is listed: ' + FS.LastError);
    Check((Length(Remote) = 1) and (Remote[0].Name = 'x') and (Remote[0].Size = 1), Tag + 'and its file is found');
    Check((FS.Stat(Dir + '/x', False, E) = rrOk) and (E.Name = 'x'), Tag + 'Stat of a file in it');
    Dir2 := Weird + '/~tilde';
    Check((FS.List(Dir2, Remote) = rrOk) and (Length(Remote) = 1) and (Remote[0].Name = 'y'), Tag + 'a directory with a tilde in its name');

    { the other tool for the lists }
    if FS.FeatureValue('mode') = 'find' then
    begin
      Check(FS.SetListingMode('stat') = rrOk, Tag + 'the helper lists with stat');
      CompareLists(Tag, FS, Local, '/');
      Check((FS.Stat('/plain.txt', False, E) = rrOk) and (E.Name = 'plain.txt') and (E.Size = 3) and (E.Mode = &640), Tag + 'Stat with stat');
      Check((FS.Stat('/link', True, E) = rrOk) and (E.Kind = rkDir), Tag + 'a link to a directory is followed by stat');
      Check(FS.SetListingMode('find') = rrOk, Tag + 'and back to find');
    end;
    Check(FS.SetListingMode('no-such-tool') <> rrOk, Tag + 'a tool that is not there is refused');
    Check(FS.SetListingMode('nosuchtool') <> rrOk, Tag + 'a name of a tool that is not there is refused');
    Check(FS.Connected, Tag + 'the connection is still open');

    { what is not done yet }
    Check(FS.MkDir('/new-dir') = rrUnsupported, Tag + 'making a directory is not done yet');
    Check(FS.SetMode('/plain.txt', &600) = rrUnsupported, Tag + 'setting the permissions is not done yet');
  finally
    Local.Free;
    FS.Free;
  end;
end;

procedure RunFailures(const Helper: AnsiString);
var
  P: TNetProc;
  FS: TFishFS;
  Remote: TRemoteEntries;
  Start: TDateTime;
begin
  { a program that takes the first line, says something else and ends }
  P := TNetProc.Create;
  Check(P.Start('/bin/sh', ['-c', 'read line; echo hello; exit 0']), 'a program that does not know the protocol is started');
  FS := TFishFS.Create(P, True);
  FS.TimeoutMs := 5000;
  Check(FS.Connect(Helper) = rrFailed, 'it is not a FISH+ host');
  Check(FS.LastError <> '', 'the failure is told in words');
  Check((not FS.Connected) and (FS.List('/', Remote) = rrFailed), 'nothing is sent over a connection that was not made');
  FS.Free;

  { a program that is silent }
  P := TNetProc.Create;
  Check(P.Start('/bin/sh', ['-c', 'sleep 5']), 'a silent program is started');
  FS := TFishFS.Create(P, True);
  FS.TimeoutMs := 400;
  Start := Now;
  Check(FS.Connect(Helper) = rrFailed, 'a program that does not answer is given up');
  Check(MilliSecondsBetween(Now, Start) < 4000, 'in about the time that was given');
  FS.Free;

  { the text of the helper that is empty }
  P := TNetProc.Create;
  Check(P.Start('/bin/cat', []), 'cat is started');
  FS := TFishFS.Create(P, True);
  Check(FS.Connect('') = rrFailed, 'no text of the helper is no connection');
  FS.Disconnect;
  FS.Disconnect;
  Check(FS.Connect(Helper) = rrFailed, 'a file system that was disconnected cannot be connected again');
  FS.Free;
end;

var
  Helper, Tmp, Base, Weird: AnsiString;
  Shells: array[0..2] of AnsiString = ('/bin/sh', '/bin/bash', '/bin/dash');
  I: Integer;
  Stamp: LongInt;
begin
  Helper := LoadText(HelperPath);
  Check(Length(Helper) > 1000, 'the text of the helper is found');
  if Helper = '' then
    Finish;

  Tmp := GetEnvironmentVariable('TMPDIR');
  if Tmp = '' then
    Tmp := '/tmp';
  Base := Tmp + '/fishfs-' + IntToStr(fpGetPid);
  Weird := Base + '-w';
  RemoveTree(Base);
  RemoveTree(Weird);
  Check(ForceDirectories(Base + '/sub') and ForceDirectories(Weird + '/new' + #10 + 'line') and ForceDirectories(Weird + '/~tilde'), 'the test tree is made');
  PutText(Base + '/plain.txt', 'abc');
  PutText(Base + '/with space.txt', 'hello world');
  PutText(Base + '/ lead and trail ', '');
  PutText(Base + '/caf' + #195#169 + '.txt', 'x');
  PutText(Base + '/sub/inner.bin', StringOfChar('z', 1000));
  PutText(Base + '/sub/other.txt', 'o');
  PutText(Weird + '/new' + #10 + 'line/x', 'q');
  PutText(Weird + '/~tilde/y', 'w');
  fpChmod(Base + '/plain.txt', &640);
  Stamp := DateTimeToFileDate(EncodeDate(2020, 2, 3) + EncodeTime(4, 5, 6, 0));
  FileSetDate(Base + '/plain.txt', Stamp);
  fpSymlink(PChar('sub'), PChar(Base + '/link'));
  fpSymlink(PChar('no-such-target'), PChar(Base + '/dangling'));

  try
    for I := 0 to High(Shells) do
      if FileExists(Shells[I]) then
        RunWithShell(Shells[I], Helper, Base, Weird);
    RunFailures(Helper);
  finally
    RemoveTree(Base);
    RemoveTree(Weird);
  end;

  Finish;
end.
