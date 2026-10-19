{ NetSsh: the command line of the ssh client of the system for a remote place (unxed/dn#90 step 7). The file systems that reach a host through ssh
  start it with TNetProc: FISH as "ssh ... host sh" (a shell whose standard input and output are the channel), SFTP as "ssh ... -s host sftp" (the
  subsystem of the server).

  The client is run without a terminal (-T) and in batch mode: it never asks for a password or a passphrase on the terminal, the keys and the agent
  of the user are used, as for any ssh of the system. So a password in the address is refused (ssh has no way to take it from a program), and a
  host that is not yet known fails as ssh tells it (StrictHostKeyChecking is the user's setting). The host comes after "--": a name that starts
  with "-" could not be taken for an option, but it is refused all the same, as no host has such a name.

  MIT, see LICENSE. }
unit NetSsh;

{$mode objfpc}
{$H+}

interface

uses
  NetSplit;

type
  TSshPurpose = (
    spShell,      { a shell on the host: FISH }
    spSftp);      { the sftp subsystem of the server }

  TSshArgs = array of AnsiString;

const
  { The program that is started: found in PATH (on Windows the OpenSSH client of the system, ssh.exe). }
  SshProgram = 'ssh';
  { The port of ssh, for NetSplitUrl. }
  SshDefaultPort = 22;
  { How long ssh may take to open the connection, in seconds. }
  SshConnectTimeout = 20;

{ The arguments of ssh (without the name of the program) for the address U. False when the address cannot be reached this way: Err tells why (in
  English, for a message to the user). }
function SshArgs(const U: TNetUrl; Purpose: TSshPurpose; out Args: TSshArgs; out Err: AnsiString): Boolean;
{ The purpose for a scheme of an address: "sh" and "fish" are spShell, "sftp" is spSftp. False for any other scheme. }
function SshPurposeOf(const Scheme: AnsiString; out Purpose: TSshPurpose): Boolean;

implementation

uses
  SysUtils;

function SshPurposeOf(const Scheme: AnsiString; out Purpose: TSshPurpose): Boolean;
begin
  Result := True;
  Purpose := spShell;
  if (Scheme = 'sh') or (Scheme = 'fish') then
    Purpose := spShell
  else if Scheme = 'sftp' then
    Purpose := spSftp
  else
    Result := False;
end;

procedure Add(var Args: TSshArgs; const S: AnsiString);
begin
  SetLength(Args, Length(Args) + 1);
  Args[High(Args)] := S;
end;

function SshArgs(const U: TNetUrl; Purpose: TSshPurpose; out Args: TSshArgs; out Err: AnsiString): Boolean;
var
  I: Integer;
begin
  Result := False;
  Err := '';
  SetLength(Args, 0);
  if U.Host = '' then
  begin
    Err := 'the address names no host';
    Exit;
  end;
  if U.Host[1] = '-' then
  begin
    Err := 'a host name cannot start with "-": ' + U.Host;
    Exit;
  end;
  { the characters of a host name and of an IPv6 address (NetSplitUrl lets only these through, an address made by hand may have others) }
  for I := 1 to Length(U.Host) do
    if not (U.Host[I] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', ':', #128..#255]) then
    begin
      Err := 'the host name has a character that a host name cannot have: ' + U.Host;
      Exit;
    end;
  if U.HasPassword then
  begin
    Err := 'ssh takes no password from the address: use a key or the agent (the address without ":password")';
    Exit;
  end;
  if (U.User <> '') and (Pos(#0, U.User) > 0) then
  begin
    Err := 'the user name has a NUL byte';
    Exit;
  end;
  Add(Args, '-T');
  Add(Args, '-o');
  Add(Args, 'BatchMode=yes');
  Add(Args, '-o');
  Add(Args, 'ConnectTimeout=' + IntToStr(SshConnectTimeout));
  if U.PortGiven then
  begin
    Add(Args, '-p');
    Add(Args, IntToStr(U.Port));
  end;
  if U.User <> '' then
  begin
    { the user as the value of -l: a name with "@" or ":" in it is not read as a part of the destination }
    Add(Args, '-l');
    Add(Args, U.User);
  end;
  if Purpose = spSftp then
    Add(Args, '-s');
  Add(Args, '--');
  Add(Args, U.Host);
  if Purpose = spSftp then
    Add(Args, 'sftp')
  else
    Add(Args, 'sh');
  Result := True;
end;

end.
