{ RemoteFS: the file system behind a panel that does not show a local directory. TRemoteFS is an abstract class with no user interface (the
  panel side is a drive of the panel, later); a protocol is a descendant. TLocalFS is the descendant over a directory of this machine: it is the
  reference of how the methods behave, and what the tests of the layers above use.

  A path of a remote file system is always written the way the remote side writes it: "/", the components apart by "/", no drive, no
  backslash. It is never a path of this machine (DnPath is for those). A path is absolute; the panel keeps the current directory. The names are
  bytes: nothing here changes their code page.

  Every method answers with a TRemoteResult; LastError tells it in words after a failure. A stream that OpenRead or OpenWrite returns is the
  caller's: the transfer is finished when it is freed (a descendant that sends the file over a connection ends the upload there).

  MIT, see LICENSE. }
unit RemoteFS;

{$mode objfpc}
{$H+}

interface

uses
  SysUtils, Classes;

type
  TRemoteResult = (
    rrOk,
    rrNotFound,       { the path or its directory is not there }
    rrExists,         { the name is taken }
    rrDenied,         { not allowed, or the path leaves the root }
    rrNotEmpty,       { Remove of a directory that holds something }
    rrNotDir,         { a file where a directory is needed }
    rrIsDir,          { a directory where a file is needed }
    rrUnsupported,    { this file system cannot do it }
    rrFailed);        { anything else (the connection, the disk): LastError tells more }

  TRemoteKind = (rkFile, rkDir, rkLink, rkOther);

  TRemoteEntry = record
    Name: AnsiString;       { the name without a path }
    Kind: TRemoteKind;      { a link is rkLink; Stat with FollowLinks gives the kind of what it points to }
    Size: Int64;            { bytes; -1 when not known; of no meaning for a directory }
    MTime: TDateTime;       { the time of the last change on the clock of this machine, as FileDateToDateTime gives it; 0 when not known }
    Mode: LongInt;          { the permission bits of Unix (octal 7777 at most); -1 when not known }
    LinkTarget: AnsiString; { what a link points to, '' when it is not told }
  end;

  TRemoteEntries = array of TRemoteEntry;

  TRemoteFS = class
  private
    FLastError: AnsiString;
  protected
    { Sets LastError to Text and returns R. }
    function Fail(R: TRemoteResult; const Text: AnsiString): TRemoteResult;
  public
    { The entries of the directory Dir, without "." and "..", in the order of the server. }
    function List(const Dir: AnsiString; out Entries: TRemoteEntries): TRemoteResult; virtual; abstract;
    { One entry. Path "/" is a directory. FollowLinks False: a link is rkLink; True: the kind (and the size) of its target, rkLink if the target is not there. }
    function Stat(const Path: AnsiString; FollowLinks: Boolean; out Entry: TRemoteEntry): TRemoteResult; virtual; abstract;
    { The content of a file, from the start. }
    function OpenRead(const Path: AnsiString; out Stream: TStream): TRemoteResult; virtual; abstract;
    { A file written from the start: made when it is not there, emptied when it is. The directory must exist. }
    function OpenWrite(const Path: AnsiString; out Stream: TStream): TRemoteResult; virtual; abstract;
    function MkDir(const Path: AnsiString): TRemoteResult; virtual; abstract;
    { A file, a link or an empty directory; rrNotEmpty for a directory that holds something. }
    function Remove(const Path: AnsiString): TRemoteResult; virtual; abstract;
    { Fails with rrExists when NewPath is taken (nothing is overwritten). }
    function Rename(const OldPath, NewPath: AnsiString): TRemoteResult; virtual; abstract;
    { The permission bits (see TRemoteEntry.Mode). }
    function SetMode(const Path: AnsiString; Mode: LongInt): TRemoteResult; virtual; abstract;

    property LastError: AnsiString read FLastError;
  end;

  { The directory Root of this machine as a remote file system: "/" is Root, nothing outside it can be reached ("/.." stays at "/" only as an error). It has no permissions
    to tell or to set: Mode is -1, SetMode is rrUnsupported, LinkTarget is ''. }
  TLocalFS = class(TRemoteFS)
  private
    FRoot: AnsiString;
    function HostPath(const Path: AnsiString; out Host: AnsiString): TRemoteResult;
    function HostPaths(const Path: AnsiString; out Host, ParentHost: AnsiString): TRemoteResult;
    function ListHost(const Host: AnsiString; out Entries: TRemoteEntries): TRemoteResult;
    function FindEntry(const Path: AnsiString; out Entry: TRemoteEntry): TRemoteResult;
  public
    constructor Create(const ARoot: AnsiString);
    function List(const Dir: AnsiString; out Entries: TRemoteEntries): TRemoteResult; override;
    function Stat(const Path: AnsiString; FollowLinks: Boolean; out Entry: TRemoteEntry): TRemoteResult; override;
    function OpenRead(const Path: AnsiString; out Stream: TStream): TRemoteResult; override;
    function OpenWrite(const Path: AnsiString; out Stream: TStream): TRemoteResult; override;
    function MkDir(const Path: AnsiString): TRemoteResult; override;
    function Remove(const Path: AnsiString): TRemoteResult; override;
    function Rename(const OldPath, NewPath: AnsiString): TRemoteResult; override;
    function SetMode(const Path: AnsiString; Mode: LongInt): TRemoteResult; override;
    property Root: AnsiString read FRoot;
  end;

{ Path made clean: the components apart by one "/", "." dropped, ".." taken back, no "/" at the end ("/" for the root). False for a path that is not
  absolute and for a ".." that climbs above the root (Clean is ''). }
function RemoteCleanPath(const Path: AnsiString; out Clean: AnsiString): Boolean;
{ Dir and Name put together: "/a" and "b" make "/a/b", "/" and "b" make "/b". }
function RemoteJoin(const Dir, Name: AnsiString): AnsiString;
{ A clean path cut at its last "/": "/a/b" is "/a" and "b", "/b" is "/" and "b", "/" is "/" and "". }
procedure RemoteSplit(const Path: AnsiString; out Dir, Name: AnsiString);
{ A short English text for the result, for a message. }
function RemoteResultText(R: TRemoteResult): AnsiString;

implementation

{ The bit of a symbolic link in TSearchRec.Attr: it has the same value on every target of DN (where the system has no links, FindFirst never sets
  it), so the warning about a symbol of some platforms is off. }
{$PUSH}{$WARN 5044 OFF}
const
  FindAll = faAnyFile or faSymLink;
  FindLink = faSymLink;
{$POP}

function RemoteCleanPath(const Path: AnsiString; out Clean: AnsiString): Boolean;
var
  Parts: array of AnsiString;
  N, I, Start: Integer;
  Part: AnsiString;
begin
  Result := False;
  Clean := '';
  if (Path = '') or (Path[1] <> '/') then
    Exit;
  SetLength(Parts, 0);
  N := 0;
  Start := 1;
  for I := 1 to Length(Path) + 1 do
    if (I > Length(Path)) or (Path[I] = '/') then
    begin
      Part := Copy(Path, Start, I - Start);
      Start := I + 1;
      if (Part = '') or (Part = '.') then
        Continue;
      if Part = '..' then
      begin
        if N = 0 then
          Exit;
        Dec(N);
        Continue;
      end;
      if N >= Length(Parts) then
        SetLength(Parts, N + 8);
      Parts[N] := Part;
      Inc(N);
    end;
  if N = 0 then
    Clean := '/'
  else
    for I := 0 to N - 1 do
      Clean := Clean + '/' + Parts[I];
  Result := True;
end;

function RemoteJoin(const Dir, Name: AnsiString): AnsiString;
begin
  if (Dir <> '') and (Dir[Length(Dir)] = '/') then
    Result := Dir + Name
  else
    Result := Dir + '/' + Name;
end;

procedure RemoteSplit(const Path: AnsiString; out Dir, Name: AnsiString);
var
  I: Integer;
begin
  I := Length(Path);
  while (I > 0) and (Path[I] <> '/') do
    Dec(I);
  if I <= 1 then
    Dir := '/'
  else
    Dir := Copy(Path, 1, I - 1);
  Name := Copy(Path, I + 1, Length(Path));
end;

function RemoteResultText(R: TRemoteResult): AnsiString;
begin
  case R of
    rrOk: Result := 'done';
    rrNotFound: Result := 'not found';
    rrExists: Result := 'already exists';
    rrDenied: Result := 'not allowed';
    rrNotEmpty: Result := 'the directory is not empty';
    rrNotDir: Result := 'not a directory';
    rrIsDir: Result := 'is a directory';
    rrUnsupported: Result := 'not supported';
  else
    Result := 'failed';
  end;
end;

{ TRemoteFS }

function TRemoteFS.Fail(R: TRemoteResult; const Text: AnsiString): TRemoteResult;
begin
  FLastError := Text;
  Result := R;
end;

{ TLocalFS }

constructor TLocalFS.Create(const ARoot: AnsiString);
begin
  inherited Create;
  FRoot := ARoot;
  while (Length(FRoot) > 1) and (FRoot[Length(FRoot)] = DirectorySeparator) do
    SetLength(FRoot, Length(FRoot) - 1);
  if FRoot = '' then
    FRoot := '.';
end;

{ The path of this machine for a path of the file system; rrDenied when the path is not clean or leaves the root. }
function TLocalFS.HostPath(const Path: AnsiString; out Host: AnsiString): TRemoteResult;
var
  Clean, Part: AnsiString;
  I, Start: Integer;
begin
  Host := '';
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  Host := FRoot;
  Start := 2;
  for I := 2 to Length(Clean) + 1 do
    if (I > Length(Clean)) or (Clean[I] = '/') then
    begin
      Part := Copy(Clean, Start, I - Start);
      Start := I + 1;
      if Part = '' then
        Continue;
      if (Pos(#0, Part) > 0) or ((DirectorySeparator <> '/') and (Pos(DirectorySeparator, Part) > 0)) then
      begin
        Host := '';
        Exit(Fail(rrDenied, 'the name cannot be used on this machine: ' + Part));
      end;
      if Host[Length(Host)] <> DirectorySeparator then
        Host := Host + DirectorySeparator;
      Host := Host + Part;
    end;
  Result := rrOk;
end;

{ The paths of this machine of Path and of its directory. }
function TLocalFS.HostPaths(const Path: AnsiString; out Host, ParentHost: AnsiString): TRemoteResult;
var
  Clean, Dir, Name: AnsiString;
begin
  ParentHost := '';
  Result := HostPath(Path, Host);
  if Result <> rrOk then
    Exit;
  RemoteCleanPath(Path, Clean);              { HostPath has seen that it is clean }
  RemoteSplit(Clean, Dir, Name);
  Result := HostPath(Dir, ParentHost);
end;

function TLocalFS.ListHost(const Host: AnsiString; out Entries: TRemoteEntries): TRemoteResult;
var
  SR: TSearchRec;
  N: Integer;
  Mask: AnsiString;
begin
  SetLength(Entries, 0);
  if not DirectoryExists(Host) then
  begin
    if FileExists(Host) then
      Exit(Fail(rrNotDir, 'not a directory: ' + Host));
    Exit(Fail(rrNotFound, 'not found: ' + Host));
  end;
  if Host[Length(Host)] = DirectorySeparator then
    Mask := Host + '*'
  else
    Mask := Host + DirectorySeparator + '*';
  if FindFirst(Mask, FindAll, SR) <> 0 then
  begin
    FindClose(SR);
    Exit(Fail(rrDenied, 'the directory cannot be read: ' + Host));
  end;
  N := 0;
  repeat
    if (SR.Name = '.') or (SR.Name = '..') then
      Continue;
    if N >= Length(Entries) then
      SetLength(Entries, N + 32);
    Entries[N].Name := SR.Name;
    if (SR.Attr and FindLink) <> 0 then
      Entries[N].Kind := rkLink
    else if (SR.Attr and faDirectory) <> 0 then
      Entries[N].Kind := rkDir
    else
      Entries[N].Kind := rkFile;
    Entries[N].Size := SR.Size;
    Entries[N].MTime := FileDateToDateTime(SR.Time);
    Entries[N].Mode := -1;
    Entries[N].LinkTarget := '';
    Inc(N);
  until FindNext(SR) <> 0;
  FindClose(SR);
  SetLength(Entries, N);
  Result := rrOk;
end;

{ The entry of a path, found by its name in the list of its directory: FindFirst on the path itself would take "*" and "?" of a name for a mask. }
function TLocalFS.FindEntry(const Path: AnsiString; out Entry: TRemoteEntry): TRemoteResult;
var
  Clean, Dir, Name, HostDir: AnsiString;
  Entries: TRemoteEntries;
  I: Integer;
begin
  if not RemoteCleanPath(Path, Clean) then
    Exit(Fail(rrDenied, 'the path is not absolute or leaves the root: ' + Path));
  RemoteSplit(Clean, Dir, Name);
  Result := HostPath(Dir, HostDir);
  if Result <> rrOk then
    Exit;
  Result := ListHost(HostDir, Entries);
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

function TLocalFS.List(const Dir: AnsiString; out Entries: TRemoteEntries): TRemoteResult;
var
  Host: AnsiString;
begin
  SetLength(Entries, 0);
  Result := HostPath(Dir, Host);
  if Result = rrOk then
    Result := ListHost(Host, Entries);
end;

function TLocalFS.Stat(const Path: AnsiString; FollowLinks: Boolean; out Entry: TRemoteEntry): TRemoteResult;
var
  Host: AnsiString;
  Probe: TFileStream;
begin
  Entry.Name := '';
  Entry.Kind := rkOther;
  Entry.Size := -1;
  Entry.MTime := 0;
  Entry.Mode := -1;
  Entry.LinkTarget := '';
  Result := HostPath(Path, Host);
  if Result <> rrOk then
    Exit;
  if Host = FRoot then
  begin
    if not DirectoryExists(Host) then
      Exit(Fail(rrNotFound, 'not found: ' + Host));
    Entry.Kind := rkDir;
    Entry.Size := 0;
    Exit(rrOk);
  end;
  Result := FindEntry(Path, Entry);
  if (Result <> rrOk) or (Entry.Kind <> rkLink) or not FollowLinks then
    Exit;
  if DirectoryExists(Host) then
  begin
    Entry.Kind := rkDir;
    Entry.Size := 0;
  end
  else if FileExists(Host) then
  begin
    Entry.Kind := rkFile;
    try
      Probe := TFileStream.Create(Host, fmOpenRead or fmShareDenyNone);
      try
        Entry.Size := Probe.Size;
      finally
        Probe.Free;
      end;
    except
      on EFOpenError do
        Entry.Size := -1;
    end;
  end;
end;

function TLocalFS.OpenRead(const Path: AnsiString; out Stream: TStream): TRemoteResult;
var
  Host: AnsiString;
begin
  Stream := nil;
  Result := HostPath(Path, Host);
  if Result <> rrOk then
    Exit;
  if DirectoryExists(Host) then
    Exit(Fail(rrIsDir, 'is a directory: ' + Path));
  if not FileExists(Host) then
    Exit(Fail(rrNotFound, 'not found: ' + Path));
  try
    Stream := TFileStream.Create(Host, fmOpenRead or fmShareDenyWrite);
  except
    on EFOpenError do
    begin
      Stream := nil;
      Exit(Fail(rrDenied, 'cannot be opened: ' + Path));
    end;
  end;
  Result := rrOk;
end;

function TLocalFS.OpenWrite(const Path: AnsiString; out Stream: TStream): TRemoteResult;
var
  Host, ParentHost: AnsiString;
begin
  Stream := nil;
  Result := HostPaths(Path, Host, ParentHost);
  if Result <> rrOk then
    Exit;
  if (Host = FRoot) or DirectoryExists(Host) then
    Exit(Fail(rrIsDir, 'is a directory: ' + Path));
  if not DirectoryExists(ParentHost) then
  begin
    if FileExists(ParentHost) then
      Exit(Fail(rrNotDir, 'not a directory: ' + ParentHost));
    Exit(Fail(rrNotFound, 'not found: ' + ParentHost));
  end;
  try
    Stream := TFileStream.Create(Host, fmCreate);
  except
    on EFCreateError do
    begin
      Stream := nil;
      Exit(Fail(rrDenied, 'cannot be written: ' + Path));
    end;
  end;
  Result := rrOk;
end;

function TLocalFS.MkDir(const Path: AnsiString): TRemoteResult;
var
  Host, ParentHost: AnsiString;
begin
  Result := HostPaths(Path, Host, ParentHost);
  if Result <> rrOk then
    Exit;
  if (Host = FRoot) or DirectoryExists(Host) or FileExists(Host) then
    Exit(Fail(rrExists, 'already exists: ' + Path));
  if not DirectoryExists(ParentHost) then
  begin
    if FileExists(ParentHost) then
      Exit(Fail(rrNotDir, 'not a directory: ' + ParentHost));
    Exit(Fail(rrNotFound, 'not found: ' + ParentHost));
  end;
  if CreateDir(Host) then
    Result := rrOk
  else
    Result := Fail(rrDenied, 'the directory cannot be made: ' + Path);
end;

function TLocalFS.Remove(const Path: AnsiString): TRemoteResult;
var
  Host: AnsiString;
  E: TRemoteEntry;
  Entries: TRemoteEntries;
begin
  Result := HostPath(Path, Host);
  if Result <> rrOk then
    Exit;
  if Host = FRoot then
    Exit(Fail(rrDenied, 'the root cannot be removed'));
  Result := FindEntry(Path, E);
  if Result <> rrOk then
    Exit;
  if E.Kind = rkDir then
  begin
    if (ListHost(Host, Entries) = rrOk) and (Length(Entries) > 0) then
      Exit(Fail(rrNotEmpty, 'the directory is not empty: ' + Path));
    if RemoveDir(Host) then
      Result := rrOk
    else
      Result := Fail(rrDenied, 'the directory cannot be removed: ' + Path);
  end
  else if DeleteFile(Host) then
    Result := rrOk
  else
    Result := Fail(rrDenied, 'cannot be removed: ' + Path);
end;

function TLocalFS.Rename(const OldPath, NewPath: AnsiString): TRemoteResult;
var
  OldHost, NewHost, NewParent: AnsiString;
  E: TRemoteEntry;
begin
  Result := HostPath(OldPath, OldHost);
  if Result <> rrOk then
    Exit;
  Result := HostPaths(NewPath, NewHost, NewParent);
  if Result <> rrOk then
    Exit;
  if (OldHost = FRoot) or (NewHost = FRoot) then
    Exit(Fail(rrDenied, 'the root cannot be renamed'));
  Result := FindEntry(OldPath, E);
  if Result <> rrOk then
    Exit;
  if FindEntry(NewPath, E) = rrOk then
    Exit(Fail(rrExists, 'already exists: ' + NewPath));
  if not DirectoryExists(NewParent) then
    Exit(Fail(rrNotFound, 'not found: ' + NewParent));
  if RenameFile(OldHost, NewHost) then
    Result := rrOk
  else
    Result := Fail(rrFailed, 'cannot be renamed: ' + OldPath);
end;

function TLocalFS.SetMode(const Path: AnsiString; Mode: LongInt): TRemoteResult;
begin
  Result := Fail(rrUnsupported, 'the local file system does not set permissions: ' + Path);
end;

end.
