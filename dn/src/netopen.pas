{ NetOpen: the registry of the addresses of remote places (docs/NETWORK.md, unxed/dn#90 step 7). An address that starts with a scheme the registry
  knows opens the file system of its protocol:
    sh://, fish://  FISH over "ssh host sh" (fishfs.pas), with the helper script fishhelper.sh beside the program;
    sftp://         SFTP over "ssh -s host sftp" (sftpfs.pas);
    ftp://          FTP (ftpfs.pas); without a user the login is "anonymous".
  Any other text is not claimed: the panel takes it as a local path, as before.

  The address that a panel shows (NetOpenUrl, Address) never holds the password: it is the scheme, the user, the host and the port as typed.

  The unit is empty in the DOS build and in DN_MINI (as the file systems are).

  MIT, see LICENSE. }
unit NetOpen;

{$mode objfpc}
{$H+}

interface

{$IF NOT (DEFINED(DOS) OR DEFINED(DN_MINI))}
uses
  RemoteFS;

const
  { The name of the helper script of FISH beside the program (tools/dn-pack.sh puts it there). }
  FishHelperName = 'fishhelper.sh';
  FtpDefaultPort = 21;

var
  { The file of the helper script of FISH; '' for FishHelperName in the directory of the program. The tests give theirs. }
  FishHelperPath: AnsiString = '';

{ True when Text starts with a scheme that the registry knows ("sh://", "fish://", "sftp://", "ftp://", in any case). }
function NetIsUrl(const Text: AnsiString): Boolean;
{ Opens the file system for Url. rrOk: FS is connected (the caller owns it), Address is what a panel shows before the path ("sftp://bob@host"),
  Path is the clean path of the address. Otherwise FS is nil and Err tells why (in English, for a message to the user). }
function NetOpenUrl(const Url: AnsiString; out FS: TRemoteFS; out Address, Path, Err: AnsiString): TRemoteResult;
{$ENDIF}

implementation

{$IF NOT (DEFINED(DOS) OR DEFINED(DN_MINI))}
uses
  SysUtils, Classes, NetSplit, NetSsh, FishFS, SftpFS, FtpFS;

function SchemeOf(const Text: AnsiString): AnsiString;
var
  I: Integer;
begin
  Result := '';
  I := Pos('://', Text);
  if I > 1 then
    Result := LowerCase(Copy(Text, 1, I - 1));
end;

function NetIsUrl(const Text: AnsiString): Boolean;
var
  S: AnsiString;
begin
  S := SchemeOf(Text);
  Result := (S = 'sh') or (S = 'fish') or (S = 'sftp') or (S = 'ftp');
end;

function FishHelperFile: AnsiString;
begin
  Result := FishHelperPath;
  if Result = '' then
    Result := ExtractFilePath(ParamStr(0)) + FishHelperName;
end;

function ReadHelper(out Text, Err: AnsiString): Boolean;
var
  F: TFileStream;
  Name: AnsiString;
begin
  Result := False;
  Text := '';
  Name := FishHelperFile;
  try
    F := TFileStream.Create(Name, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Text, F.Size);
      if Length(Text) > 0 then
        F.ReadBuffer(Text[1], Length(Text));
    finally
      F.Free;
    end;
  except
    on E: Exception do
    begin
      Err := 'the helper script of FISH cannot be read: ' + Name + ': ' + E.Message;
      Exit;
    end;
  end;
  Result := True;
end;

function NetOpenUrl(const Url: AnsiString; out FS: TRemoteFS; out Address, Path, Err: AnsiString): TRemoteResult;
var
  U, Shown: TNetUrl;
  Port: Integer;
  Helper, User, Password: AnsiString;
  Fish: TFishFS;
  Sftp: TSftpFS;
  Ftp: TFtpFS;
begin
  FS := nil;
  Address := '';
  Path := '';
  Err := '';
  Result := rrFailed;
  if not NetIsUrl(Url) then
  begin
    Err := 'not an address of a remote place: ' + Url;
    Exit;
  end;
  if SchemeOf(Url) = 'ftp' then
    Port := FtpDefaultPort
  else
    Port := SshDefaultPort;
  if not NetSplitUrl(Url, Port, U, Err) then
    Exit;
  if not RemoteCleanPath(U.Path, Path) then
  begin
    Err := 'the path climbs above the root: ' + U.Path;
    Exit;
  end;
  Shown := U;
  Shown.Password := '';
  Shown.HasPassword := False;
  Shown.Path := '';
  Address := NetJoinUrl(Shown, False);
  if (Address <> '') and (Address[Length(Address)] = '/') then
    SetLength(Address, Length(Address) - 1);
  if U.Scheme = 'ftp' then
  begin
    User := U.User;
    Password := U.Password;
    if User = '' then
    begin
      User := 'anonymous';
      if not U.HasPassword then
        Password := 'anonymous@';
    end;
    Ftp := TFtpFS.Create;
    Result := Ftp.Connect(U.Host, U.Port, User, Password);
    if Result <> rrOk then
    begin
      Err := Ftp.LastError;
      Ftp.Free;
      Exit;
    end;
    FS := Ftp;
  end
  else if U.Scheme = 'sftp' then
  begin
    Result := OpenSftpSsh(Url, Sftp, Err);
    if Result = rrOk then
      FS := Sftp;
  end
  else
  begin
    if not ReadHelper(Helper, Err) then
      Exit;
    Result := OpenFishSsh(Url, Helper, Fish, Err);
    if Result = rrOk then
      FS := Fish;
  end;
  if Result <> rrOk then
    Path := '';
end;
{$ENDIF}

end.
