{ RemoteDrive: the drive of a panel that shows a remote file system (docs/NETWORK.md, unxed/dn#90 step 7). TRemoteDrive holds a TRemoteFS (FISH, SFTP,
  FTP, or TLocalFS in the tests) and gives the panel what it asks a drive for: the list of the current directory, a change of directory, the way up.
  One class serves every protocol; what the protocol is, is the TRemoteFS.

  The drive owns the file system: freeing the drive closes the connection. The current directory (CurDir) is a clean path of the remote side
  ("/", components apart by "/"); GetDir puts the address in front of it (Url, as "sh://user@host", without a path), so that the panel title and the
  history tell where the panel is. lChDir takes a name in the current directory, "..", a remote path from "/", or such a full address.

  Done so far: browsing. Copy, erase, making a directory and opening a file do nothing yet (step 8 of the plan). A drive that cannot be reached
  again is not kept in the desktop file: when it is read back, the panel shows the local disk.

  The unit is empty in the DOS build and in DN_MINI (as the file systems are).

  MIT, see LICENSE. }
unit RemoteDrive;

{$I STDEFINE.INC}
{$I netbuild.inc}

interface

{$IFDEF DN_NET}
uses
  Defines, Streams, Views, FilesCol, DiskInfo, Collect, Drives, RemoteFS;

type
  TRemoteDrive = class(TDrive)
    FS: TRemoteFS;
    Url: String;              { the address without the path: "sh://user@host" }
    LastError: String;        { why the last change of directory or listing failed, in English; '' after a success }
    constructor Create(AFS: TRemoteFS; const AUrl, ADir: String; AOwner: Pointer); overload;
    destructor Destroy; override;
    function Read(Ip: ipstream): Pointer; override;
    function StreamableName: ShortString; override;
    class function Build: TStreamable; static;
    procedure Write(Os: opstream); override;
    procedure lChDir(ADir: String); override;
    function GetDir: String; override;
    function GetDirectory(const FileMask: String; var TotalInfo: TSize): TFilesCollection; override;
    procedure CopyFiles(Files: TCollection; Own: TView; MoveMode: Boolean); override;
    procedure CopyFilesInto(Files: TCollection; Own: TView; MoveMode: Boolean); override;
    procedure EraseFiles(Files: TCollection); override;
    procedure UseFile(P: PFileRec; Command: Word); override;
    procedure MakeDir; override;
    procedure GetFreeSpace(var S: String); override;
    function Disposable: Boolean; override;
    function GetRealName: String; override;
    function GetInternalName: String; override;
    function GetRealDir: String; override;
    procedure GetDirInfo(var B: TDiskInfoRec); override;
    function isUp: Boolean; override;
    procedure ChangeUp(var S: String); override;
    procedure ChangeRoot; override;
    procedure EditDescription(PF: PFileRec); override;
    procedure GetDirLength(PF: PFileRec); override;
    function OpenDirectory(const Dir: String; PutDirs: Boolean): TDrive; override;
    procedure DrvFindFile(FC: TFilesCollection); override;
    procedure ReadDescrptions(FilesC: TFilesCollection); override;
    function GetDriveLetter: Char; override;
  end;

{ The directory that ADir names for a drive whose address is Url and whose current directory is Dir (both as in TRemoteDrive): a clean remote
  path, or False when ADir is not a path of this drive (another address, or a ".." above the root). }
function RemoteDriveTarget(const Url, Dir, ADir: AnsiString; out Target: AnsiString): Boolean;
{$ENDIF}

implementation

{$IFDEF DN_NET}
uses
  SysUtils, Dos, osdep, Basics, fileutil, panelsetup, panelroot;

function RemoteDriveTarget(const Url, Dir, ADir: AnsiString; out Target: AnsiString): Boolean;
var
  S: AnsiString;
begin
  Target := '';
  S := ADir;
  if (Url <> '') and (Copy(S, 1, Length(Url)) = Url) then
  begin
    S := Copy(S, Length(Url) + 1, MaxInt);
    if S = '' then
      S := '/';
    if S[1] <> '/' then
      Exit(False);
  end
  else if Pos('://', S) > 0 then
    Exit(False);
  if S = '' then
    S := Dir
  else if S[1] <> '/' then
    S := RemoteJoin(Dir, S);
  Result := RemoteCleanPath(S, Target);
end;

{ The packed time of DOS that a TFileRec keeps, for a time of TRemoteEntry; 0 when it is not known. }
function PackedTime(T: TDateTime): LongInt;
var
  D: DateTime;
  Y, Mo, Dy, H, Mi, Sc, Ms: Word;
begin
  Result := 0;
  if T <= 0 then
    Exit;
  DecodeDate(T, Y, Mo, Dy);
  DecodeTime(T, H, Mi, Sc, Ms);
  if (Y < 1980) or (Y > 2107) then
    Exit;
  D.Year := Y;
  D.Month := Mo;
  D.Day := Dy;
  D.Hour := H;
  D.Min := Mi;
  D.Sec := Sc;
  PackTime(D, Result);
end;

constructor TRemoteDrive.Create(AFS: TRemoteFS; const AUrl, ADir: String; AOwner: Pointer);
var
  Clean: AnsiString;
begin
  inherited Create($FF, AOwner);
  FS := AFS;
  Url := AUrl;
  if not RemoteCleanPath(ADir, Clean) then
    Clean := '/';
  CurDir := Clean;
  LastError := '';
  DriveType := dtNet;
  ColAllowed := PanelFileColAllowed[pcDisk];
end;

destructor TRemoteDrive.Destroy;
begin
  FS.Free;
  FS := nil;
  inherited Destroy;
end;

function TRemoteDrive.Read(Ip: ipstream): Pointer;
begin
  inherited Read(Ip);
  ReadStrV(Ip, Url);
  { the connection is not in the stream: the panel takes the local disk instead }
  Free;
  Result := nil;
end;

procedure TRemoteDrive.Write(Os: opstream);
begin
  inherited Write(Os);
  Os.WriteString(@Url);
end;

class function TRemoteDrive.Build: TStreamable;
begin
  Result := TRemoteDrive.Create(streamableInit);
end;

function TRemoteDrive.StreamableName: ShortString;
begin
  Result := 'RemoteDrive.TRemoteDrive';
end;

procedure TRemoteDrive.lChDir(ADir: String);
var
  Target: AnsiString;
  E: TRemoteEntry;
  R: TRemoteResult;
begin
  if ADir = #0 then
    Exit;
  LastError := '';
  if not RemoteDriveTarget(Url, CurDir, ADir, Target) then
  begin
    LastError := 'not a directory of ' + Url + ': ' + ADir;
    Abort := True;
    Exit;
  end;
  if Length(Target) > 255 then
  begin
    { CurDir is a ShortString: a longer path would be cut }
    LastError := 'the path is too long for the panel: ' + Target;
    Abort := True;
    Exit;
  end;
  R := FS.Stat(Target, True, E);
  if (R = rrOk) and (E.Kind <> rkDir) then
    R := rrNotDir;
  if R <> rrOk then
  begin
    if FS.LastError <> '' then
      LastError := FS.LastError
    else
      LastError := RemoteResultText(R) + ': ' + Target;
    Abort := True;
    Exit;
  end;
  CurDir := Target;
end;

function TRemoteDrive.GetDir: String;
begin
  Result := Url + CurDir;
end;

function TRemoteDrive.GetDirectory(const FileMask: String; var TotalInfo: TSize): TFilesCollection;
var
  Entries: TRemoteEntries;
  E, T: TRemoteEntry;
  I: Integer;
  Attr: Word;
  Size: TSize;
  P: PFileRec;
  AllFiles: Boolean;
  UpTime: LongInt;
begin
  Abort := False;
  NoMemory := False;
  TotalInfo := 0;
  Result := TFilesCollection.Create($10, $20);
  Result.Panel := Panel;
  if isUp then
  begin
    { ".." shows the time of the current directory, as on a local drive }
    UpTime := 0;
    if FS.Stat(CurDir, True, T) = rrOk then
      UpTime := PackedTime(T.MTime);
    Result.AtInsert(0, NewFileRec('..', '..', -1, UpTime, 0, 0, Directory, @CurDir));
  end;
  if FS.List(CurDir, Entries) <> rrOk then
  begin
    LastError := FS.LastError;
    Abort := True;
    Exit;
  end;
  LastError := '';
  AllFiles := (FileMask = x_x) or (FileMask = '*');
  for I := 0 to High(Entries) do
  begin
    E := Entries[I];
    { a name that the panel cannot hold (a ShortString) is left out rather than cut }
    if (E.Name = '') or (Length(E.Name) > 255) then
      Continue;
    Attr := 0;
    if E.Kind = rkDir then
      Attr := Directory
    else if E.Kind = rkLink then
    begin
      Attr := SysLinkAttr;
      if (FS.Stat(RemoteJoin(CurDir, E.Name), True, T) = rrOk) and (T.Kind = rkDir) then
        Attr := Attr or Directory;
    end;
    if (E.Name[1] = '.') then
      Attr := Attr or Hidden;
    if (Attr and Directory = 0) and not AllFiles and not InFilter(E.Name, FileMask) then
      Continue;
    if (Attr and Directory <> 0) or (E.Size < 0) then
      Size := 0
    else
      Size := E.Size;
    P := NewFileRec(E.Name, E.Name, Size, PackedTime(E.MTime), 0, 0, Attr, @CurDir);
    if Attr and Directory = 0 then
      TotalInfo := TotalInfo + Size;
    Result.AtInsert(Result.Count, P);
  end;
end;

procedure TRemoteDrive.CopyFiles(Files: TCollection; Own: TView; MoveMode: Boolean);
begin
end;

procedure TRemoteDrive.CopyFilesInto(Files: TCollection; Own: TView; MoveMode: Boolean);
begin
end;

procedure TRemoteDrive.EraseFiles(Files: TCollection);
begin
end;

procedure TRemoteDrive.UseFile(P: PFileRec; Command: Word);
begin
end;

procedure TRemoteDrive.MakeDir;
begin
end;

procedure TRemoteDrive.GetFreeSpace(var S: String);
begin
  S := '';
end;

function TRemoteDrive.Disposable: Boolean;
begin
  Result := False;
end;

function TRemoteDrive.GetRealName: String;
begin
  Result := GetDir;
end;

function TRemoteDrive.GetInternalName: String;
begin
  Result := '';
end;

function TRemoteDrive.GetRealDir: String;
begin
  Result := GetDir;
end;

procedure TRemoteDrive.GetDirInfo(var B: TDiskInfoRec);
begin
  B.Dir := NewStr(GetDir);
end;

function TRemoteDrive.isUp: Boolean;
begin
  Result := (CurDir <> '/') or (Prev <> nil);
end;

procedure TRemoteDrive.ChangeUp(var S: String);
var
  Dir, Name: AnsiString;
begin
  S := '';
  if CurDir <> '/' then
  begin
    RemoteSplit(CurDir, Dir, Name);
    S := Name;
    CurDir := Dir;
    Exit;
  end;
  if (Prev = nil) or (Panel = nil) then
    Exit;
  { above the root: back to the drive the panel had before; this drive (and the connection) ends here }
  TFilePanelRoot(Panel).Drive := Prev;
  Prev := nil;
  Free;
end;

procedure TRemoteDrive.ChangeRoot;
begin
  CurDir := '/';
end;

procedure TRemoteDrive.EditDescription(PF: PFileRec);
begin
end;

procedure TRemoteDrive.GetDirLength(PF: PFileRec);
begin
end;

function TRemoteDrive.OpenDirectory(const Dir: String; PutDirs: Boolean): TDrive;
begin
  Result := nil;
end;

procedure TRemoteDrive.DrvFindFile(FC: TFilesCollection);
begin
end;

procedure TRemoteDrive.ReadDescrptions(FilesC: TFilesCollection);
begin
end;

function TRemoteDrive.GetDriveLetter: Char;
begin
  Result := '/';
end;
{$ENDIF}

end.
