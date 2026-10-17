program t_remotefs;
{ Tests of src/remotefs.pas: the paths of a remote file system, and TLocalFS over a directory made for the test. }
{$mode objfpc}{$H+}
uses SysUtils, Classes, RemoteFS;
{$I dntest.inc}

function CleanOf(const Path: AnsiString): AnsiString;
begin
  if not RemoteCleanPath(Path, Result) then
    Result := '(refused)';
end;

function JoinOf(const Dir, Name: AnsiString): AnsiString;
begin
  Result := RemoteJoin(Dir, Name);
end;

function SplitOf(const Path: AnsiString): AnsiString;
var
  D, N: AnsiString;
begin
  RemoteSplit(Path, D, N);
  Result := D + '|' + N;
end;

function Slurp(Stream: TStream): AnsiString;
begin
  SetLength(Result, Stream.Size);
  if Length(Result) > 0 then
    Stream.ReadBuffer(Result[1], Length(Result));
end;

function Put(FS: TRemoteFS; const Path, Text: AnsiString): TRemoteResult;
var
  S: TStream;
begin
  Result := FS.OpenWrite(Path, S);
  if Result <> rrOk then
    Exit;
  try
    if Text <> '' then
      S.WriteBuffer(Text[1], Length(Text));
  finally
    S.Free;
  end;
end;

function Get(FS: TRemoteFS; const Path: AnsiString; out Text: AnsiString): TRemoteResult;
var
  S: TStream;
begin
  Text := '';
  Result := FS.OpenRead(Path, S);
  if Result <> rrOk then
    Exit;
  try
    Text := Slurp(S);
  finally
    S.Free;
  end;
end;

{ The entry called Name in the list of Dir, or Kind rkOther and Size -2 when it is not there. }
function Find(FS: TRemoteFS; const Dir, Name: AnsiString): TRemoteEntry;
var
  L: TRemoteEntries;
  I: Integer;
begin
  Result.Name := '';
  Result.Kind := rkOther;
  Result.Size := -2;
  if FS.List(Dir, L) <> rrOk then
    Exit;
  for I := 0 to High(L) do
    if L[I].Name = Name then
      Exit(L[I]);
end;

function Count(FS: TRemoteFS; const Dir: AnsiString): Integer;
var
  L: TRemoteEntries;
begin
  if FS.List(Dir, L) <> rrOk then
    Exit(-1);
  Result := Length(L);
end;

var
  Base, Root, Text, Big, Back, Odd: AnsiString;
  FS: TLocalFS;
  E: TRemoteEntry;
  L: TRemoteEntries;
  S: TStream;
  I: Integer;
begin
  { the paths }
  Check(CleanOf('/') = '/', 'clean: the root');
  Check(CleanOf('//a///b/') = '/a/b', 'clean: slashes');
  Check(CleanOf('/a/./b') = '/a/b', 'clean: a dot');
  Check(CleanOf('/a/../b') = '/b', 'clean: two dots');
  Check(CleanOf('/a/b/../..') = '/', 'clean: back to the root');
  Check(CleanOf('/..') = '(refused)', 'clean: two dots above the root');
  Check(CleanOf('/a/../..') = '(refused)', 'clean: two dots above the root, later');
  Check(CleanOf('a/b') = '(refused)', 'clean: a relative path');
  Check(CleanOf('') = '(refused)', 'clean: an empty path');
  Check(CleanOf('/a b/c' + #10 + 'd') = '/a b/c' + #10 + 'd', 'clean: a space and a line break in a name are letters');
  Check(CleanOf('/...') = '/...', 'clean: three dots are a name');
  Check(JoinOf('/a', 'b') = '/a/b', 'join: a directory and a name');
  Check(JoinOf('/', 'b') = '/b', 'join: the root and a name');
  Check(JoinOf('/a/', 'b') = '/a/b', 'join: a directory with a slash at the end');
  Check(SplitOf('/a/b') = '/a|b', 'split: a path');
  Check(SplitOf('/b') = '/|b', 'split: a name in the root');
  Check(SplitOf('/') = '/|', 'split: the root');
  Check(RemoteResultText(rrNotFound) <> RemoteResultText(rrExists), 'the results have their own texts');

  { a directory for the test }
  Base := GetTempDir + 't_remotefs_' + IntToStr(GetProcessID) + DirectorySeparator;
  Root := Base + 'root';
  ForceDirectories(Root);
  FS := TLocalFS.Create(Root + DirectorySeparator);
  try
    Check(Count(FS, '/') = 0, 'the empty root lists nothing');
    Check(FS.Stat('/', False, E) = rrOk, 'stat of the root');
    Check(E.Kind = rkDir, 'the root is a directory');

    { make a directory, write a file }
    Check(FS.MkDir('/a') = rrOk, 'make a directory');
    Check(FS.MkDir('/a') = rrExists, 'make it again: it exists');
    Check(FS.MkDir('/x/y') = rrNotFound, 'make a directory in a directory that is not there');
    Check(FS.MkDir('/') = rrExists, 'make the root: it exists');
    Check(Put(FS, '/a/file one.txt', 'hello') = rrOk, 'write a file with a space in the name');
    Check(FS.MkDir('/a/file one.txt') = rrExists, 'a file holds the name of a directory');
    Check(FS.MkDir('/a/file one.txt/sub') = rrNotDir, 'a directory inside a file');
    Check(Put(FS, '/a', 'x') = rrIsDir, 'write a file over a directory');
    Check(Put(FS, '/', 'x') = rrIsDir, 'write a file over the root');
    Check(Put(FS, '/nodir/f', 'x') = rrNotFound, 'write a file in a directory that is not there');
    Check(Put(FS, '/a/file one.txt/f', 'x') = rrNotDir, 'write a file inside a file');

    { list and stat }
    Check(FS.List('/a', L) = rrOk, 'list a directory');
    Check(Length(L) = 1, 'the list holds one entry (not "." and "..")');
    E := Find(FS, '/a', 'file one.txt');
    Check(E.Name = 'file one.txt', 'the entry has the name');
    Check(E.Kind = rkFile, 'the entry is a file');
    Check(E.Size = 5, 'the entry has the size');
    Check(Abs(E.MTime - Now) < 1.0, 'the entry has a time of today');
    Check(E.Mode = -1, 'the local file system tells no permissions');
    Check(FS.Stat('/a/file one.txt', False, E) = rrOk, 'stat of a file');
    Check((E.Kind = rkFile) and (E.Size = 5), 'stat: a file of 5 bytes');
    Check(FS.Stat('/a', False, E) = rrOk, 'stat of a directory');
    Check(E.Kind = rkDir, 'stat: a directory');
    Check(FS.Stat('/a/../a/./file one.txt', True, E) = rrOk, 'stat of an unclean path');
    Check(FS.Stat('/nope', False, E) = rrNotFound, 'stat of what is not there');
    Check(FS.Stat('/a/nope', False, E) = rrNotFound, 'stat of what is not there in a directory');
    Check(FS.Stat('/nope/x', False, E) = rrNotFound, 'stat in a directory that is not there');
    Check(FS.Stat('/a/file one.txt/x', False, E) = rrNotDir, 'stat inside a file');
    Check(FS.List('/nope', L) = rrNotFound, 'list what is not there');
    Check(FS.List('/a/file one.txt', L) = rrNotDir, 'list a file');
    Check(FS.LastError <> '', 'a failure leaves a message');

    { read }
    Check((Get(FS, '/a/file one.txt', Text) = rrOk) and (Text = 'hello'), 'read what was written');
    Check(Get(FS, '/a', Text) = rrIsDir, 'read a directory');
    Check(Get(FS, '/nope', Text) = rrNotFound, 'read what is not there');
    Check(Get(FS, '/nodir/f', Text) = rrNotFound, 'read in a directory that is not there');

    { write again: the file is emptied first }
    Check(Put(FS, '/a/file one.txt', 'no') = rrOk, 'write over a file');
    Check((Get(FS, '/a/file one.txt', Text) = rrOk) and (Text = 'no'), 'the file holds the new content only');
    Check(Put(FS, '/a/empty', '') = rrOk, 'write an empty file');
    E := Find(FS, '/a', 'empty');
    Check((E.Kind = rkFile) and (E.Size = 0), 'an empty file has the size 0');

    { names: bytes of UTF-8, a line break, a mask sign }
    Odd := 'caf' + #$C3#$A9 + ' ' + #$E2#$82#$AC;
    Check(Put(FS, '/' + Odd, 'u') = rrOk, 'write a file with a name in UTF-8');
    Check(Find(FS, '/', Odd).Kind = rkFile, 'the name in UTF-8 is listed as it is');
    Odd := 'line' + #10 + 'break';
    Check(Put(FS, '/' + Odd, 'n') = rrOk, 'write a file with a line break in the name');
    Check(Find(FS, '/', Odd).Kind = rkFile, 'the name with a line break is listed as it is');
    Check(Put(FS, '/star*q?', 'm') = rrOk, 'write a file with "*" and "?" in the name');
    Check(FS.Stat('/star*q?', False, E) = rrOk, 'stat of the name with "*" and "?"');
    Check((E.Name = 'star*q?') and (E.Size = 1), 'stat does not take "*" and "?" for a mask');
    Check(FS.Stat('/s*', False, E) = rrNotFound, 'stat of a mask finds nothing');
    Check(Put(FS, '/.hidden', 'h') = rrOk, 'write a file that starts with a dot');
    Check(Find(FS, '/', '.hidden').Kind = rkFile, 'a name with a dot first is listed');

    { a file with every byte value, more than a block }
    SetLength(Big, 70001);
    for I := 0 to 70000 do
      Big[I + 1] := Chr(I mod 256);
    Check(Put(FS, '/a/big.bin', Big) = rrOk, 'write 70001 bytes with all byte values');
    Check((Get(FS, '/a/big.bin', Back) = rrOk) and (Back = Big), 'read them back unchanged');
    Check(Find(FS, '/a', 'big.bin').Size = Length(Big), 'the size of the big file');

    { a stream is the caller's }
    Check(FS.OpenRead('/a/big.bin', S) = rrOk, 'open a stream');
    Check(S.Size = Length(Big), 'the stream has the size of the file');
    S.Free;

    { leave the root }
    Check(FS.Stat('/..', False, E) = rrDenied, 'stat above the root is denied');
    Check(FS.List('/../', L) = rrDenied, 'list above the root is denied');
    Check(Put(FS, '/a/../../evil', 'e') = rrDenied, 'write above the root is denied');
    Check(not FileExists(Base + 'evil'), 'nothing was written above the root');
    Check(FS.MkDir('/../evildir') = rrDenied, 'make a directory above the root is denied');
    Check(not DirectoryExists(Base + 'evildir'), 'no directory was made above the root');
    Check(FS.Remove('/../root') = rrDenied, 'remove above the root is denied');
    Check(FS.Rename('/a/big.bin', '/../moved') = rrDenied, 'rename to above the root is denied');
    Check(FS.Stat('relative', False, E) = rrDenied, 'a relative path is denied');

    { rename }
    Check(FS.Rename('/a/file one.txt', '/a/two.txt') = rrOk, 'rename a file');
    Check(FS.Stat('/a/file one.txt', False, E) = rrNotFound, 'the old name is gone');
    Check((Get(FS, '/a/two.txt', Text) = rrOk) and (Text = 'no'), 'the new name holds the content');
    Check(FS.Rename('/a/two.txt', '/a/empty') = rrExists, 'rename onto a name that is taken');
    Check(FS.Rename('/a/nope', '/a/other') = rrNotFound, 'rename what is not there');
    Check(FS.Rename('/a/two.txt', '/nodir/two.txt') = rrNotFound, 'rename into a directory that is not there');
    Check(FS.Rename('/', '/b') = rrDenied, 'rename the root');
    Check(FS.MkDir('/b') = rrOk, 'make a directory to move');
    Check(FS.Rename('/a/two.txt', '/b/moved.txt') = rrOk, 'move a file to another directory');
    Check((Get(FS, '/b/moved.txt', Text) = rrOk) and (Text = 'no'), 'the moved file holds the content');
    Check(FS.Rename('/b', '/c') = rrOk, 'rename a directory');
    Check(Find(FS, '/c', 'moved.txt').Kind = rkFile, 'the renamed directory holds its file');

    { permissions are not set here }
    Check(FS.SetMode('/c', 493) = rrUnsupported, 'set the mode: not supported by the local file system');

    { remove }
    Check(FS.Remove('/c') = rrNotEmpty, 'remove a directory that holds a file');
    Check(FS.Remove('/c/moved.txt') = rrOk, 'remove a file');
    Check(FS.Remove('/c') = rrOk, 'remove an empty directory');
    Check(FS.Remove('/c') = rrNotFound, 'remove it again');
    Check(FS.Remove('/') = rrDenied, 'remove the root');
    Check(FS.Remove('/star*q?') = rrOk, 'remove the name with "*" and "?"');
    Check(FS.Remove('/s*') = rrNotFound, 'remove a mask finds nothing');
    Check(FS.Stat('/.hidden', False, E) = rrOk, 'the file with the dot is still there');
    Check(FS.Remove('/a') = rrNotEmpty, 'remove a directory with files');

    { clean up }
    FS.List('/a', L);
    for I := 0 to High(L) do
      Check(FS.Remove('/a/' + L[I].Name) = rrOk, 'clean up: ' + L[I].Name);
    FS.List('/', L);
    for I := 0 to High(L) do
      if L[I].Kind = rkDir then
        Check(FS.Remove('/' + L[I].Name) = rrOk, 'clean up the directory: ' + L[I].Name)
      else
        Check(FS.Remove('/' + L[I].Name) = rrOk, 'clean up the file');
    Check(Count(FS, '/') = 0, 'the root is empty again');
  finally
    FS.Free;
  end;
  RemoveDir(Root);
  RemoveDir(Base);
  Finish;
end.
