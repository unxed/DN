program t_remotedrive;
{ Tests of src/remotedrive.pas: the drive of a panel over a TLocalFS made for the test (the list, the change of directory, the way up), and
  RemoteDriveTarget. }
{$mode objfpc}{$H+}
uses Dos, SysUtils, Classes, Defines, Basics, FilesCol, FileType, panelsetup, Drives, RemoteFS, RemoteDrive;
{$I dntest.inc}

function TargetOf(const Dir, ADir: AnsiString): AnsiString;
begin
  if not RemoteDriveTarget('sh://host', Dir, ADir, Result) then
    Result := '(refused)';
end;

procedure PutFile(const Path, Text: AnsiString);
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

{ The names of the list, in its order, apart by blanks; a directory ends with "/". }
function NamesOf(C: TFilesCollection): AnsiString;
var
  I: Integer;
  P: PFileRec;
begin
  Result := '';
  for I := 0 to C.Count - 1 do
  begin
    P := PFileRec(C.At(I));
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + P^.FlName[True];
    if P^.Attr and Directory <> 0 then
      Result := Result + '/';
  end;
end;

{ The sorted names of the list, as NamesOf. }
function SortedNamesOf(C: TFilesCollection): AnsiString;
var
  L: TStringList;
  I: Integer;
  P: PFileRec;
  S: AnsiString;
begin
  L := TStringList.Create;
  try
    L.Sorted := True;
    for I := 0 to C.Count - 1 do
    begin
      P := PFileRec(C.At(I));
      S := P^.FlName[True];
      if P^.Attr and Directory <> 0 then
        S := S + '/';
      L.Add(S);
    end;
    Result := '';
    for I := 0 to L.Count - 1 do
    begin
      if I > 0 then
        Result := Result + ' ';
      Result := Result + L[I];
    end;
  finally
    L.Free;
  end;
end;

function FindRec(C: TFilesCollection; const Name: AnsiString): PFileRec;
var
  I: Integer;
begin
  for I := 0 to C.Count - 1 do
    if PFileRec(C.At(I))^.FlName[True] = Name then
      Exit(PFileRec(C.At(I)));
  Result := nil;
end;

procedure RemoveTree(const Dir: AnsiString);
var
  SR: TSearchRec;
begin
  if FindFirst(Dir + DirectorySeparator + '*', faAnyFile or faSymLink, SR) = 0 then
  begin
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      if (SR.Attr and faDirectory <> 0) and (SR.Attr and faSymLink = 0) then
        RemoveTree(Dir + DirectorySeparator + SR.Name)
      else
        DeleteFile(Dir + DirectorySeparator + SR.Name);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  RemoveDir(Dir);
end;

var
  Base, Root, S: AnsiString;
  D: TRemoteDrive;
  C: TFilesCollection;
  Total: TSize;
  P: PFileRec;
  Up: ShortString;
begin
  PrepareExtCollection;    { what the program does at its start: NewFileRec looks up the kind of a file }
  Check(TargetOf('/a', 'b') = '/a/b', 'a name in the current directory');
  Check(TargetOf('/a/b', '..') = '/a', '".." is the parent');
  Check(TargetOf('/', '..') = '(refused)', 'no ".." above the root');
  Check(TargetOf('/a', '/x/./y/') = '/x/y', 'a remote path from the root, made clean');
  Check(TargetOf('/a', 'sh://host/x') = '/x', 'the full address of the drive');
  Check(TargetOf('/a', 'sh://host') = '/', 'the address alone is the root');
  Check(TargetOf('/a', 'sh://other/x') = '(refused)', 'another address is not a path of this drive');
  Check(TargetOf('/a', 'sh://hostx/y') = '(refused)', 'nor one that only starts the same way');
  Check(TargetOf('/a', '') = '/a', 'nothing is the current directory');

  Base := GetTempDir + 't_remotedrive_' + IntToStr(GetProcessID);
  Root := Base + DirectorySeparator + 'root';
  ForceDirectories(Root + DirectorySeparator + 'sub' + DirectorySeparator + 'deep');
  PutFile(Root + DirectorySeparator + 'a.txt', 'hello');
  PutFile(Root + DirectorySeparator + 'b.pas', '1234567890');
  PutFile(Root + DirectorySeparator + '.hidden', '');
  PutFile(Root + DirectorySeparator + 'sub' + DirectorySeparator + 'c.txt', 'c');

  D := TRemoteDrive.Create(TLocalFS.Create(Root), 'test://h', '/', nil);
  try
    Check(D.DriveType = dtNet, 'the drive is of a network');
    Check(D.GetDir = 'test://h/', 'the title is the address and the path: ' + D.GetDir);
    Check(not D.isUp, 'no way up from the root of a drive that replaced nothing');

    C := D.GetDirectory('*', Total);
    try
      S := SortedNamesOf(C);
      Check(S = '.hidden a.txt b.pas sub/', 'the root: ' + S);
      Check(Total = 15, 'the total size of the files: ' + IntToStr(Total));
      P := FindRec(C, 'b.pas');
      Check((P <> nil) and (P^.Size = 10), 'the size of a file');
      Check((P <> nil) and (P^.Yr >= 2020), 'the year of a file: ' + IntToStr(P^.Yr));
      P := FindRec(C, '.hidden');
      Check((P <> nil) and (P^.Attr and Hidden <> 0), 'a name with a dot in front is hidden');
      P := FindRec(C, 'sub');
      Check((P <> nil) and (P^.Owner <> nil) and (P^.Owner^ = '/'), 'an entry belongs to the current directory');
    finally
      C.Free;
    end;

    C := D.GetDirectory('*.txt', Total);
    try
      S := SortedNamesOf(C);
      Check(S = 'a.txt sub/', 'a mask leaves the directories: ' + S);
    finally
      C.Free;
    end;

    Abort := False;
    D.lChDir('sub');
    Check(not Abort and (D.CurDir = '/sub'), 'into a directory: ' + D.CurDir + ' ' + D.LastError);
    Check(D.GetDir = 'test://h/sub', 'the title follows: ' + D.GetDir);
    Check(D.isUp, 'a way up from a directory');
    C := D.GetDirectory('*', Total);
    try
      S := NamesOf(C);
      Check(Copy(S, 1, 4) = '../ ', '".." comes first: ' + S);
      P := FindRec(C, '..');
      Check((P <> nil) and (P^.Yr >= 2020), '".." has the time of the directory, the year: ' + IntToStr(P^.Yr));
      Check(SortedNamesOf(C) = '../ c.txt deep/', 'the directory: ' + SortedNamesOf(C));
    finally
      C.Free;
    end;

    D.lChDir('deep');
    Check(D.CurDir = '/sub/deep', 'deeper: ' + D.CurDir);
    D.ChangeUp(Up);
    Check((D.CurDir = '/sub') and (Up = 'deep'), 'the way up names the directory left: ' + D.CurDir + ' ' + Up);
    D.lChDir('..');
    Check(D.CurDir = '/', '".." to the root: ' + D.CurDir);
    D.lChDir('test://h/sub/deep');
    Check(D.CurDir = '/sub/deep', 'the full address: ' + D.CurDir);
    D.ChangeRoot;
    Check(D.CurDir = '/', 'to the root');

    Abort := False;
    D.lChDir('nothing');
    Check(Abort and (D.CurDir = '/') and (D.LastError <> ''), 'a directory that is not there: ' + D.LastError);
    Abort := False;
    D.lChDir('a.txt');
    Check(Abort and (D.CurDir = '/'), 'a file is not entered: ' + D.LastError);
    Abort := False;
    D.lChDir('other://h/sub');
    Check(Abort and (D.CurDir = '/'), 'another address is refused: ' + D.LastError);
    Abort := False;
    D.lChDir(#0);
    Check(not Abort and (D.CurDir = '/'), 'the empty mark changes nothing');

    RemoveTree(Root + DirectorySeparator + 'sub');
    D.lChDir('/');
    Abort := False;
    D.CurDir := '/sub';
    C := D.GetDirectory('*', Total);
    try
      Check(Abort and (D.LastError <> ''), 'a list that fails says why: ' + D.LastError);
      Check(NamesOf(C) = '../', 'and still has the way up: ' + NamesOf(C));
    finally
      C.Free;
    end;
    Abort := False;
  finally
    D.Free;
  end;

  RemoveTree(Base);
  Check(not DirectoryExists(Base), 'the test directory is removed');
  Finish;
end.
