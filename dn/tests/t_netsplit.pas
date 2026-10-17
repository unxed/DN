program t_netsplit;
{ Tests of src/netsplit.pas: an address split into its parts and put together again, the percent coding. }
{$mode objfpc}{$H+}
uses SysUtils, NetSplit;
{$I dntest.inc}

function Split(const Url: AnsiString; DefaultPort: Integer; out R: TNetUrl): Boolean;
var
  Err: AnsiString;
begin
  Result := NetSplitUrl(Url, DefaultPort, R, Err);
end;

function Refused(const Url: AnsiString): Boolean;
var
  R: TNetUrl;
  Err: AnsiString;
begin
  Result := (not NetSplitUrl(Url, 21, R, Err)) and (Err <> '') and (R.Host = '') and (R.Scheme = '') and (R.Path = '/');
end;

var
  R, R2: TNetUrl;
  S, Err: AnsiString;
  I: Integer;
  Bytes: AnsiString;
begin
  { a plain address: the default port, the path "/" }
  Check(Split('ftp://example.com', 21, R), 'host only is an address');
  Check((R.Scheme = 'ftp') and (R.Host = 'example.com') and (R.Path = '/'), 'host only: scheme, host and the path "/"');
  Check((R.Port = 21) and not R.PortGiven, 'host only: the default port, not given');
  Check((R.User = '') and not R.HasPassword, 'host only: no user and no password');
  Check(Split('ftp://example.com/', 21, R) and (R.Path = '/'), 'host and "/" is the path "/"');

  { the port }
  Check(Split('sftp://example.com:2222/home', 22, R) and (R.Port = 2222) and R.PortGiven, 'the port that is given');
  Check(Split('sftp://example.com:/home', 22, R) and (R.Port = 22) and not R.PortGiven, 'a colon with no port names none');
  Check(Split('sftp://example.com:65535/', 22, R) and (R.Port = 65535), 'the port 65535');
  Check(Split('sftp://example.com:1/', 22, R) and (R.Port = 1), 'the port 1');
  Check(Refused('sftp://example.com:0/'), 'the port 0 is refused');
  Check(Refused('sftp://example.com:65536/'), 'the port 65536 is refused');
  Check(Refused('sftp://example.com:abc/'), 'a port that is not a number is refused');
  Check(Refused('sftp://example.com:-1/'), 'a negative port is refused');
  Check(Refused('sftp://example.com:21:22/'), 'two ports are refused');

  { the user and the password }
  Check(Split('ftp://anna@example.com/pub', 21, R) and (R.User = 'anna') and not R.HasPassword, 'a user without a password');
  Check(Split('ftp://anna:secret@example.com/pub', 21, R) and (R.User = 'anna') and R.HasPassword and (R.Password = 'secret'), 'a user and a password');
  Check(Split('ftp://anna:@example.com/', 21, R) and R.HasPassword and (R.Password = ''), 'an empty password is a password');
  Check(Split('ftp://:secret@example.com/', 21, R) and (R.User = '') and (R.Password = 'secret'), 'a password without a user');
  Check(Split('ftp://anna:p%40ss%3Aw%2Fd@example.com/', 21, R) and (R.Password = 'p@ss:w/d'), 'the password is decoded');
  Check(Split('ftp://anna:p@ss@example.com/', 21, R) and (R.User = 'anna') and (R.Password = 'p@ss') and (R.Host = 'example.com'),
    'the host follows the last "@"');
  Check(Split('ftp://an%20na@example.com/', 21, R) and (R.User = 'an na'), 'the user is decoded');

  { the host: lower case, IPv6 in brackets }
  Check(Split('SFTP://Example.COM/Dir', 22, R) and (R.Scheme = 'sftp') and (R.Host = 'example.com') and (R.Path = '/Dir'),
    'the scheme and the host are in lower case, the path is not');
  Check(Split('sh://[::1]/tmp', 22, R) and (R.Host = '::1') and (R.Port = 22) and not R.PortGiven, 'IPv6 in brackets');
  Check(Split('sh://[fe80::1:2]:2200/tmp', 22, R) and (R.Host = 'fe80::1:2') and (R.Port = 2200) and R.PortGiven, 'IPv6 in brackets with a port');
  Check(Split('sh://u:p@[2001:DB8::7]:2200/tmp', 22, R) and (R.Host = '2001:db8::7') and (R.User = 'u') and (R.Password = 'p'),
    'IPv6 with a user and a password');
  Check(Split('sh://[::ffff:192.0.2.1]/', 22, R) and (R.Host = '::ffff:192.0.2.1'), 'IPv6 with an IPv4 tail');
  Check(Refused('sh://::1/tmp'), 'IPv6 without brackets is refused');
  Check(Refused('sh://[::1/tmp'), 'a bracket that is not closed is refused');
  Check(Refused('sh://[::1]x/tmp'), 'something after the bracket that is not a port is refused');
  Check(Refused('sh://[]/tmp'), 'empty brackets are refused');
  Check(Refused('sh://[example.com]/tmp'), 'a name in brackets is refused');
  Check(Split('sh://192.0.2.7/tmp', 22, R) and (R.Host = '192.0.2.7'), 'an IPv4 address');
  Check(Split('sh://my_host-1.example/', 22, R) and (R.Host = 'my_host-1.example'), 'a host name with "-" and "_"');

  { the path }
  Check(Split('ftp://example.com/a%20b/c%C3%A9', 21, R) and (R.Path = '/a b/c' + #$C3#$A9), 'the path is decoded to bytes');
  Check(Split('ftp://example.com/a?b#c', 21, R) and (R.Path = '/a?b#c'), '"?" and "#" are part of the path');
  Check(Split('ftp://example.com/a%3Fb', 21, R) and (R.Path = '/a?b'), '%3F is "?" in the path');
  Check(Split('ftp://example.com//double//slash/', 21, R) and (R.Path = '//double//slash/'), 'the path is kept as it is typed');
  Check(Split('ftp://example.com/a+b', 21, R) and (R.Path = '/a+b'), '"+" is not a space');

  { what is not an address }
  Check(Refused(''), 'an empty text is refused');
  Check(Refused('example.com/pub'), 'no scheme is refused');
  Check(Refused('://example.com/'), 'an empty scheme is refused');
  Check(Refused('1ftp://example.com/'), 'a scheme that starts with a digit is refused');
  Check(Refused('f tp://example.com/'), 'a scheme with a space is refused');
  Check(Refused('ftp://'), 'no host is refused');
  Check(Refused('ftp:///pub'), 'an empty host before the path is refused');
  Check(Refused('ftp://user@/pub'), 'a user and no host is refused');
  Check(Refused('ftp://exa mple.com/'), 'a host with a space is refused');
  Check(Refused('ftp://example.com/%zz'), 'a wrong escape in the path is refused');
  Check(Refused('ftp://example.com/%4'), 'a short escape in the path is refused');
  Check(Refused('ftp://example.com/%'), 'a lone percent sign is refused');
  Check(Refused('ftp://us%zzer@example.com/'), 'a wrong escape in the user is refused');
  Check(Refused('ftp://user:p%@example.com/'), 'a wrong escape in the password is refused');
  Check(Refused('ftp://example.com/a%00b'), 'a NUL byte in the path is refused');
  Check(Refused('ftp://exam' + #0 + 'ple.com/'), 'a NUL byte in the host is refused');
  Check(Refused('ftp://user%00@example.com/'), 'a NUL byte in the user is refused');
  Check(not NetSplitUrl('x', 21, R, Err) and (Pos('scheme', Err) > 0), 'the message names what is wrong');

  { the percent coding }
  Check(NetPercentDecode('a%20b%2fc%2Fd', S) and (S = 'a b/c/d'), 'decode: both cases of the hex digits');
  Check(NetPercentDecode('', S) and (S = ''), 'decode: empty');
  Check(NetPercentDecode('a+b', S) and (S = 'a+b'), 'decode: "+" stays');
  Check((not NetPercentDecode('a%2', S)) and (S = ''), 'decode: a short escape fails and leaves nothing');
  Check(NetPercentEncode('a b', False) = 'a%20b', 'encode: a space');
  Check(NetPercentEncode('a/b', False) = 'a%2Fb', 'encode: "/" is coded in a name');
  Check(NetPercentEncode('a/b', True) = 'a/b', 'encode: "/" is kept in a path');
  Check(NetPercentEncode('AZaz09-._~', False) = 'AZaz09-._~', 'encode: the plain signs stay');
  Check(NetPercentEncode('100%', False) = '100%25', 'encode: the percent sign');
  Check(NetPercentEncode('a?b#c', True) = 'a%3Fb%23c', 'encode: "?" and "#" are coded in a path');
  Check(NetPercentEncode(#$C3#$A9, False) = '%C3%A9', 'encode: the bytes above 127, capital hex digits');
  Bytes := '';
  for I := 0 to 255 do
    Bytes := Bytes + Chr(I);
  Check(NetPercentDecode(NetPercentEncode(Bytes, False), S) and (S = Bytes), 'the 256 byte values go through encode and decode');
  Check(NetPercentDecode(NetPercentEncode(Bytes, True), S) and (S = Bytes), 'the 256 byte values go through encode (path) and decode');

  { put together }
  Check(Split('SFTP://anna:p%40ss@Example.com:2222/home/a%20b', 22, R), 'a full address is split');
  Check(NetJoinUrl(R, True) = 'sftp://anna:p%40ss@example.com:2222/home/a%20b', 'join: the whole address');
  Check(NetJoinUrl(R, False) = 'sftp://anna@example.com:2222/home/a%20b', 'join: the password is left out');
  Check(Split('sh://[::1]:2200/x', 22, R) and (NetJoinUrl(R, True) = 'sh://[::1]:2200/x'), 'join: IPv6 in brackets');
  Check(Split('sh://example.com/x', 22, R) and (NetJoinUrl(R, True) = 'sh://example.com/x'), 'join: no port that was not given');
  Check(Split('ftp://:secret@example.com/', 21, R) and (NetJoinUrl(R, False) = 'ftp://example.com/'), 'join: no user and the password hidden leave no "@"');
  Check(Split('ftp://anna:@example.com/', 21, R) and (NetJoinUrl(R, True) = 'ftp://anna:@example.com/'), 'join: an empty password keeps its colon');
  R.Scheme := 'ftp'; R.User := ''; R.Password := ''; R.HasPassword := False; R.Host := 'h'; R.Port := 21; R.PortGiven := False; R.Path := '';
  Check(NetJoinUrl(R, True) = 'ftp://h/', 'join: an empty path is "/"');

  { split and join of the same address give the same parts }
  S := 'ftp://us%40er:pa%3Ass@Host.Example:2121/%E2%82%AC/x%20y/%25';
  Check(Split(S, 21, R) and Split(NetJoinUrl(R, True), 21, R2), 'the joined address is an address');
  Check((R2.Scheme = R.Scheme) and (R2.User = R.User) and (R2.Password = R.Password) and (R2.HasPassword = R.HasPassword) and
    (R2.Host = R.Host) and (R2.Port = R.Port) and (R2.PortGiven = R.PortGiven) and (R2.Path = R.Path), 'split, join and split again: the same parts');
  Check((R.User = 'us@er') and (R.Password = 'pa:ss') and (R.Path = '/' + #$E2#$82#$AC + '/x y/%'), 'the parts of the long address');

  Finish;
end.
