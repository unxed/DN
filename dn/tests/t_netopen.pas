program t_netopen;
{ Tests of src/netopen.pas that need no server: which texts are addresses, the address that a panel shows, the refusals. The connections through
  ssh are tested in t_sshfs. }
{$mode objfpc}{$H+}
uses SysUtils, RemoteFS, NetOpen;
{$I dntest.inc}

var
  FS: TRemoteFS;
  Address, Path, Err: AnsiString;
  R: TRemoteResult;
begin
  Check(NetIsUrl('sh://host/'), 'sh:// is an address');
  Check(NetIsUrl('fish://host'), 'fish:// is an address');
  Check(NetIsUrl('SFTP://host/x'), 'the scheme in any case');
  Check(NetIsUrl('ftp://host'), 'ftp:// is an address');
  Check(not NetIsUrl('http://host/'), 'a scheme the registry does not know is not');
  Check(not NetIsUrl('/home/user'), 'a local path is not');
  Check(not NetIsUrl('C:\dos'), 'nor a path of DOS');
  Check(not NetIsUrl('://host'), 'nor a text without a scheme');
  Check(not NetIsUrl('dir/sh://x'), 'nor a name that holds an address further on');

  R := NetOpenUrl('/home/user', FS, Address, Path, Err);
  Check((R = rrFailed) and (FS = nil) and (Err <> ''), 'a local path is not opened: ' + Err);
  R := NetOpenUrl('sh://', FS, Address, Path, Err);
  Check((R = rrFailed) and (FS = nil), 'an address without a host: ' + Err);
  R := NetOpenUrl('sftp://host/a/../../b', FS, Address, Path, Err);
  Check((R = rrFailed) and (FS = nil) and (Pos('above', Err) > 0), 'a path above the root: ' + Err);

  { nothing listens on port 1 of this machine: the connection fails at once, the address is made all the same }
  R := NetOpenUrl('ftp://u:secret@127.0.0.1:1/pub/./x/', FS, Address, Path, Err);
  Check((R <> rrOk) and (FS = nil) and (Err <> ''), 'FTP to a closed port fails: ' + Err);
  Check(Address = 'ftp://u@127.0.0.1:1', 'the address keeps the user and the port, not the password: ' + Address);
  Check(Pos('secret', Address + Path) = 0, 'the password is nowhere in what a panel shows');

  { the helper is read before ssh is started: nothing goes out to the host }
  FishHelperPath := '/nonexistent/fishhelper.sh';
  R := NetOpenUrl('SH://Alice@Host.Example/tmp', FS, Address, Path, Err);
  Check((R = rrFailed) and (FS = nil) and (Pos('helper', Err) > 0), 'FISH without its helper script says so: ' + Err);
  Check(Address = 'sh://Alice@host.example', 'the scheme and the host in lower case, no port when none is given: ' + Address);
  Finish;
end.
