program t_sshfs;
{ Tests of OpenFishSsh (src/fishfs.pas) and OpenSftpSsh (src/sftpfs.pas): FISH and SFTP through the ssh of the system. The other side is an sshd of
  the test (a port of 127.0.0.1, keys made for the run, no PAM, no password), which ssh reaches through a configuration file of the test
  (NetSsh.SshConfigFile); the files are a tree made for the test, and what the file systems did is looked at on this machine. On CI an sshd that is
  not found is a failure, elsewhere the checks are left out. }
{$mode objfpc}{$H+}
uses SysUtils, Classes, BaseUnix, Process, ssockets, RemoteFS, NetProc, NetSsh, FishFS, SftpFS;
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

function FindProgram(const Places: array of AnsiString): AnsiString;
var
  I: Integer;
begin
  for I := 0 to High(Places) do
    if FileExists(Places[I]) then
      Exit(Places[I]);
  Result := '';
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

function Run(const Exe: AnsiString; const Args: array of AnsiString): Boolean;
var
  Output: AnsiString;
begin
  Result := RunCommand(Exe, Args, Output);
end;

{ Starts sshd with the configuration of K on a port that is free; the port, or 0. The server must still run once the port answers: another one may
  hold the port, and then this one has ended. }
function StartSshd(const Sshd, SftpServer, K: AnsiString; out Server: TProcess): Integer;
var
  Try_, Waited: Integer;
  Sock: TInetSocket;
  Up: Boolean;
  Cfg: AnsiString;
begin
  Server := nil;
  for Try_ := 0 to 4 do
  begin
    Result := 20000 + (fpGetPid * 13 + Try_ * 991 + 5000) mod 30000;
    Cfg := 'Port ' + IntToStr(Result) + LineEnding + 'ListenAddress 127.0.0.1' + LineEnding + 'HostKey ' + K + '/host' + LineEnding +
      'PidFile ' + K + '/sshd.pid' + LineEnding + 'AuthorizedKeysFile ' + K + '/authorized_keys' + LineEnding + 'UsePAM no' + LineEnding +
      'PermitRootLogin prohibit-password' + LineEnding +   { root in the VM of FreeBSD, whose sshd says no to root by default }
      'PasswordAuthentication no' + LineEnding + 'KbdInteractiveAuthentication no' + LineEnding + 'PubkeyAuthentication yes' + LineEnding +
      'StrictModes no' + LineEnding + 'Subsystem sftp ' + SftpServer + LineEnding;
    PutText(K + '/sshd_config', Cfg);
    PutText(K + '/cfg', 'Host dnhost' + LineEnding + '  HostName 127.0.0.1' + LineEnding + '  Port ' + IntToStr(Result) + LineEnding +
      '  IdentityFile ' + K + '/user' + LineEnding + '  IdentitiesOnly yes' + LineEnding + '  StrictHostKeyChecking no' + LineEnding +
      '  UserKnownHostsFile /dev/null' + LineEnding + '  LogLevel ERROR' + LineEnding +
      'Host dnnone' + LineEnding + '  HostName 127.0.0.1' + LineEnding + '  Port 1' + LineEnding);
    Server := TProcess.Create(nil);
    Server.Executable := '/bin/sh';
    Server.Parameters.Add('-c');
    Server.Parameters.Add('exec "$0" -D -e -f "$1" 2>"$2"');
    Server.Parameters.Add(Sshd);
    Server.Parameters.Add(K + '/sshd_config');
    Server.Parameters.Add(K + '/sshd.log');
    Server.Execute;
    Up := False;
    Waited := 0;
    while (not Up) and Server.Running and (Waited < 10000) do
    begin
      Sleep(100);
      Inc(Waited, 100);
      try
        Sock := TInetSocket.Create('127.0.0.1', Result, 1000);
        Sock.Free;
        Sleep(200);
        Up := Server.Running;
      except
        on Exception do
          Up := False;
      end;
    end;
    if Up then
      Exit;
    if Server.Running then
      Server.Terminate(1);
    Server.WaitOnExit;
    FreeAndNil(Server);
  end;
  Result := 0;
end;

procedure CheckFish(const Base, Helper: AnsiString);
var
  FS: TFishFS;
  Err, Dir, Data: AnsiString;
  Entries: TRemoteEntries;
  E: TRemoteEntry;
  Stream: TStream;
  Size: Int64;
begin
  Check(OpenFishSsh('sh://dnhost/', Helper, FS, Err) = rrOk, 'FISH through ssh connects: ' + Err);
  if FS = nil then
    Exit;
  try
    Check((FS.Pwd(Dir) = rrOk) and (Dir <> '') and (Dir[1] = '/'), 'the shell has a directory: ' + Dir);
    Check(FS.List(Base, Entries) = rrOk, 'the tree is listed: ' + FS.LastError);
    Check((IndexOf(Entries, 'plain.txt') >= 0) and (IndexOf(Entries, 'with space.txt') >= 0) and (IndexOf(Entries, 'sub') >= 0),
      'the names of the tree are in the list');
    Check((FS.Stat(Base + '/plain.txt', False, E) = rrOk) and (E.Kind = rkFile) and (E.Size = 3), 'stat of a file');
    Check((FS.ReadRange(Base + '/with space.txt', 0, 100, Data, Size) = rrOk) and (Data = 'hello world'), 'a file is read: ' + Data);
    Check(FS.OpenWrite(Base + '/fish-up.txt', Stream) = rrOk, 'a file is opened for writing');
    if Stream <> nil then
    begin
      Stream.WriteBuffer(PChar('over ssh')^, 8);
      Stream.Free;
    end;
    Check(LoadText(Base + '/fish-up.txt') = 'over ssh', 'it is on the disk');
    Check((FS.MkDir(Base + '/fish-dir') = rrOk) and DirectoryExists(Base + '/fish-dir'), 'a directory is made');
  finally
    FS.Free;
  end;
end;

procedure CheckSftp(const Base: AnsiString);
var
  FS: TSftpFS;
  Err: AnsiString;
  Entries: TRemoteEntries;
  E: TRemoteEntry;
  Stream: TStream;
  Buf: array[0..99] of Char;
  N: Integer;
begin
  Check(OpenSftpSsh('sftp://dnhost/', FS, Err) = rrOk, 'SFTP through ssh connects: ' + Err);
  if FS = nil then
    Exit;
  try
    Check(FS.Version = 3, 'the server speaks version 3');
    Check(FS.List(Base, Entries) = rrOk, 'the tree is listed: ' + FS.LastError);
    Check((IndexOf(Entries, 'plain.txt') >= 0) and (IndexOf(Entries, 'with space.txt') >= 0), 'the names of the tree are in the list');
    Check((FS.Stat(Base + '/sub', True, E) = rrOk) and (E.Kind = rkDir), 'stat of a directory');
    Check(FS.OpenRead(Base + '/plain.txt', Stream) = rrOk, 'a file is opened for reading');
    if Stream <> nil then
    begin
      N := Stream.Read(Buf, SizeOf(Buf));
      Check(Copy(Buf, 1, N) = 'abc', 'its content');
      Stream.Free;
    end;
    Check(FS.OpenWrite(Base + '/sftp-up.txt', Stream) = rrOk, 'a file is opened for writing');
    if Stream <> nil then
    begin
      Stream.WriteBuffer(PChar('sftp over ssh')^, 13);
      Stream.Free;
    end;
    Check(LoadText(Base + '/sftp-up.txt') = 'sftp over ssh', 'it is on the disk');
    Check((FS.Rename(Base + '/sftp-up.txt', Base + '/sftp-moved.txt') = rrOk) and FileExists(Base + '/sftp-moved.txt'), 'a file is renamed');
  finally
    FS.Free;
  end;
end;

procedure CheckRefusals(const Helper: AnsiString);
var
  Fish: TFishFS;
  Sftp: TSftpFS;
  Err: AnsiString;
begin
  Check((OpenFishSsh('sh://dnnone/', Helper, Fish, Err) = rrFailed) and (Fish = nil), 'FISH: no server on the port fails');
  Check(Pos('refused', Err) > 0, 'the message is what ssh said: ' + Err);
  Check((OpenSftpSsh('sftp://dnnone/', Sftp, Err) = rrFailed) and (Sftp = nil), 'SFTP: no server on the port fails');
  Check(Pos('refused', Err) > 0, 'the message is what ssh said: ' + Err);
  Check((OpenFishSsh('sh://u:pw@dnhost/', Helper, Fish, Err) = rrFailed) and (Pos('password', Err) > 0), 'a password in the address: ' + Err);
  Check((OpenFishSsh('sftp://dnhost/', Helper, Fish, Err) = rrFailed) and (Fish = nil), 'FISH does not take an address of SFTP: ' + Err);
  Check((OpenSftpSsh('sh://dnhost/', Sftp, Err) = rrFailed) and (Sftp = nil), 'SFTP does not take an address of a shell: ' + Err);
  Check(OpenSftpSsh('not an address', Sftp, Err) = rrFailed, 'not an address: ' + Err);
end;

var
  Sshd, Keygen, SftpServer, Tmp, Base, K, Helper: AnsiString;
  Server: TProcess;
  Port: Integer;
begin
  Sshd := FindProgram(['/usr/sbin/sshd', '/usr/local/sbin/sshd', '/usr/bin/sshd']);
  Keygen := FindProgram(['/usr/bin/ssh-keygen', '/usr/local/bin/ssh-keygen']);
  SftpServer := FindProgram(['/usr/lib/openssh/sftp-server', '/usr/libexec/openssh/sftp-server', '/usr/libexec/sftp-server',
    '/usr/lib/ssh/sftp-server']);
  if (Sshd = '') or (Keygen = '') or (SftpServer = '') then
  begin
    if GetEnvironmentVariable('CI') <> '' then
      Check(False, 'sshd, ssh-keygen and sftp-server are installed')
    else
      WriteLn('SKIP: sshd, ssh-keygen or sftp-server is not installed');
    Finish;
    Exit;
  end;
  Helper := LoadText(HelperPath);
  Check(Length(Helper) > 1000, 'the text of the helper is found');

  Tmp := GetEnvironmentVariable('TMPDIR');
  if Tmp = '' then
    Tmp := '/tmp';
  Base := Tmp + '/sshfs-' + IntToStr(fpGetPid);
  K := Base + '-k';
  RemoveTree(Base);
  RemoveTree(K);
  Check(ForceDirectories(Base + '/sub') and ForceDirectories(K), 'the test tree is made');
  PutText(Base + '/plain.txt', 'abc');
  PutText(Base + '/with space.txt', 'hello world');
  { the empty passphrase is written in the text of the command: TProcess of FPC 3.2.2 drops an empty argument }
  Run('/bin/sh', ['-c', '"$0" -q -t ed25519 -N "" -f "$1" && "$0" -q -t ed25519 -N "" -f "$2"', Keygen, K + '/host', K + '/user']);
  Check(FileExists(K + '/host') and FileExists(K + '/user.pub'), 'the keys are made');
  PutText(K + '/authorized_keys', LoadText(K + '/user.pub'));
  fpChmod(K + '/user', &600);
  Port := StartSshd(Sshd, SftpServer, K, Server);
  Check(Port > 0, 'sshd of the test runs: ' + LoadText(K + '/sshd.log'));
  SshConfigFile := K + '/cfg';
  try
    if Port > 0 then
    begin
      CheckFish(Base, Helper);
      CheckSftp(Base);
      CheckRefusals(Helper);
    end;
  finally
    if Server <> nil then
    begin
      if Server.Running then
        Server.Terminate(1);
      Server.WaitOnExit;
      Server.Free;
    end;
    RemoveTree(Base);
    RemoveTree(K);
  end;
  Finish;
end.
