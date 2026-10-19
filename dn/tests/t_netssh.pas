program t_netssh;
{ Tests of src/netssh.pas: the command line of ssh for an address, from addresses split by NetSplitUrl. }
{$mode objfpc}{$H+}
uses SysUtils, NetSplit, NetSsh;
{$I dntest.inc}

function Joined(const Args: TSshArgs): AnsiString;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Args) do
  begin
    if I > 0 then
      Result := Result + ' ';
    Result := Result + '[' + Args[I] + ']';
  end;
end;

{ The arguments for Url, or 'ERR: ' and the message. }
function ArgsOf(const Url: AnsiString; Purpose: TSshPurpose): AnsiString;
var
  U: TNetUrl;
  Err: AnsiString;
  Args: TSshArgs;
begin
  if not NetSplitUrl(Url, SshDefaultPort, U, Err) then
    Exit('SPLIT: ' + Err);
  if not SshArgs(U, Purpose, Args, Err) then
    Exit('ERR: ' + Err);
  Result := Joined(Args);
end;

var
  P: TSshPurpose;
  S, Base, Err: AnsiString;
  U: TNetUrl;
  Args: TSshArgs;
begin
  Base := '[-T] [-o] [BatchMode=yes] [-o] [ConnectTimeout=' + IntToStr(SshConnectTimeout) + ']';
  S := ArgsOf('sh://example.org/home', spShell);
  Check(S = Base + ' [--] [example.org] [sh]', 'a host alone: ' + S);
  S := ArgsOf('sh://alice@example.org:2222/', spShell);
  Check(S = Base + ' [-p] [2222] [-l] [alice] [--] [example.org] [sh]', 'a user and a port: ' + S);
  S := ArgsOf('sftp://bob@Example.ORG/', spSftp);
  Check(S = Base + ' [-l] [bob] [-s] [--] [example.org] [sftp]', 'the sftp subsystem: ' + S);
  S := ArgsOf('sftp://[::1]:2200/tmp', spSftp);
  Check(S = Base + ' [-p] [2200] [-s] [--] [::1] [sftp]', 'an IPv6 host without its brackets: ' + S);
  S := ArgsOf('sh://us%40er%3Ax@host/', spShell);
  Check(S = Base + ' [-l] [us@er:x] [--] [host] [sh]', 'a user with "@" and ":" is one value of -l: ' + S);
  S := ArgsOf('sh://-oproxy/', spShell);
  Check(Copy(S, 1, 5) = 'ERR: ', 'a host that starts with "-" is refused: ' + S);
  S := ArgsOf('sh://alice:secret@host/', spShell);
  Check((Copy(S, 1, 5) = 'ERR: ') and (Pos('password', S) > 0), 'a password is refused: ' + S);
  S := ArgsOf('sh://alice:@host/', spShell);
  Check(Copy(S, 1, 5) = 'ERR: ', 'an empty password is a password too');
  U.Scheme := 'sh';
  U.User := '';
  U.Password := '';
  U.HasPassword := False;
  U.Port := 22;
  U.PortGiven := False;
  U.Path := '/';
  U.Host := 'bad host';
  Check(not SshArgs(U, spShell, Args, Err), 'an address made by hand with a blank in its host is refused: ' + Err);
  U.Host := 'h' + #10 + 'x';
  Check(not SshArgs(U, spShell, Args, Err), 'and with a line end');
  U.Host := '';
  Check(not SshArgs(U, spShell, Args, Err), 'and without a host');
  Check(Pos('[-p]', ArgsOf('sh://host:22/', spShell)) > 0, 'a port that is given is passed even when it is 22');
  Check(Pos('[-p]', ArgsOf('sh://host/', spShell)) = 0, 'no port: ssh takes its own setting (~/.ssh/config)');

  Check(SshPurposeOf('sh', P) and (P = spShell), 'sh is a shell');
  Check(SshPurposeOf('fish', P) and (P = spShell), 'fish is a shell');
  Check(SshPurposeOf('sftp', P) and (P = spSftp), 'sftp is the subsystem');
  Check(not SshPurposeOf('ftp', P), 'ftp is not reached through ssh');
  Finish;
end.
