{ NetSplit: the address of a remote place, "scheme://user:password@host:port/path", split into its parts, and put together again; the percent
  coding of the parts.

  The unit knows no protocol: the port that an address without a port gets is given by the caller (the registry of the protocols, later). The parts
  are bytes: a name that is not valid UTF-8 survives the round trip. The rules:

    - the scheme is letters, digits, "+", "-" and "." and starts with a letter; it is put in lower case, so is the host name;
    - "user:password" is cut at the first ":", the user information from the host at the last "@" (a password may hold "@" typed as it is);
    - a host with a colon (IPv6) is written in brackets, "[::1]:2200"; the brackets are not part of Host;
    - the port is 1..65535; "host:" with nothing after the colon names no port;
    - the path starts at the first "/" after the host, "/" when the address ends after the host; "?" and "#" are part of the path (a name may
      hold them); the percent coding of the user, the password and the path is decoded ("%2F" becomes "/": a name with a slash cannot be told apart);
    - a NUL byte (typed or "%00") is refused: it cannot be part of a name, and a text protocol would end a line there.

  MIT, see LICENSE. }
unit NetSplit;

{$mode objfpc}
{$H+}

interface

type
  TNetUrl = record
    Scheme: AnsiString;       { in lower case }
    User: AnsiString;         { decoded; '' when the address names no user }
    Password: AnsiString;     { decoded }
    HasPassword: Boolean;     { "user:@host" has an empty password, "user@host" has none }
    Host: AnsiString;         { in lower case; an IPv6 address without the brackets }
    Port: Integer;            { the port of the address, DefaultPort when it names none }
    PortGiven: Boolean;
    Path: AnsiString;         { decoded; starts with "/" }
  end;

{ Splits Url. False when it is not an address: Err tells what is wrong (in English, for a message to the user) and R is empty. DefaultPort is the
  port of an address that names none. }
function NetSplitUrl(const Url: AnsiString; DefaultPort: Integer; out R: TNetUrl; out Err: AnsiString): Boolean;

{ The address as text: the host in brackets when it holds a colon, the port only when it was given, the user, the password (only when
  ShowPassword is True, else the colon and the password are left out) and the path coded. NetSplitUrl of the result is R again. }
function NetJoinUrl(const R: TNetUrl; ShowPassword: Boolean): AnsiString;

{ "%41" to "A": the bytes of the escapes. False when a "%" is not followed by two hex digits (Res is ''). "+" stays "+". }
function NetPercentDecode(const S: AnsiString; out Res: AnsiString): Boolean;
{ Every byte but the letters, the digits and "-._~" (and the "/" of a path, KeepSlash, and the signs that a path keeps for the eye: ":@+,;=$&!()*") as
  "%41" with capital hex digits. }
function NetPercentEncode(const S: AnsiString; KeepSlash: Boolean): AnsiString;

implementation

uses
  SysUtils;

const
  HexDigits: array[0..15] of Char = '0123456789ABCDEF';

function HexValue(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

{ Lower case of the letters A..Z only: a name with bytes above 127 is not touched, and the locale does not matter. }
function AsciiLower(const S: AnsiString): AnsiString;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if Result[I] in ['A'..'Z'] then
      Result[I] := Chr(Ord(Result[I]) + 32);
end;

function NetPercentDecode(const S: AnsiString; out Res: AnsiString): Boolean;
var
  I, N, K, H, L: Integer;
begin
  Result := False;
  Res := '';
  N := Length(S);
  SetLength(Res, N);
  K := 0;
  I := 1;
  while I <= N do
  begin
    if S[I] = '%' then
    begin
      if I + 2 > N then
      begin
        Res := '';
        Exit;
      end;
      H := HexValue(S[I + 1]);
      L := HexValue(S[I + 2]);
      if (H < 0) or (L < 0) then
      begin
        Res := '';
        Exit;
      end;
      Inc(K);
      Res[K] := Chr(H * 16 + L);
      Inc(I, 3);
    end
    else
    begin
      Inc(K);
      Res[K] := S[I];
      Inc(I);
    end;
  end;
  SetLength(Res, K);
  Result := True;
end;

function NetPercentEncode(const S: AnsiString; KeepSlash: Boolean): AnsiString;
var
  I, K: Integer;
  C: Char;
  Keep: Boolean;
begin
  SetLength(Result, Length(S) * 3);
  K := 0;
  for I := 1 to Length(S) do
  begin
    C := S[I];
    Keep := C in ['A'..'Z', 'a'..'z', '0'..'9', '-', '.', '_', '~'];
    if (not Keep) and KeepSlash then
      Keep := C in ['/', ':', '@', '+', ',', ';', '=', '$', '&', '!', '(', ')', '*'];
    if Keep then
    begin
      Inc(K);
      Result[K] := C;
    end
    else
    begin
      Result[K + 1] := '%';
      Result[K + 2] := HexDigits[Ord(C) shr 4];
      Result[K + 3] := HexDigits[Ord(C) and 15];
      Inc(K, 3);
    end;
  end;
  SetLength(Result, K);
end;

function SchemeIsValid(const S: AnsiString): Boolean;
var
  I: Integer;
begin
  Result := (S <> '') and (S[1] in ['A'..'Z', 'a'..'z']);
  if not Result then
    Exit;
  for I := 2 to Length(S) do
    if not (S[I] in ['A'..'Z', 'a'..'z', '0'..'9', '+', '-', '.']) then
      Exit(False);
end;

{ A host name: letters, digits, "-", "_" and "."; the bytes above 127 are let through (a name in UTF-8). }
function HostIsValid(const S: AnsiString): Boolean;
var
  I: Integer;
begin
  Result := S <> '';
  for I := 1 to Length(S) do
    if not (S[I] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', #128..#255]) then
      Exit(False);
end;

{ An IPv6 address (between the brackets): hex digits, ":" and "." (an IPv4 tail), "%" and the name of a zone. }
function Ip6IsValid(const S: AnsiString): Boolean;
var
  I: Integer;
begin
  Result := (S <> '') and (Pos(':', S) > 0);
  for I := 1 to Length(S) do
    if not (S[I] in ['A'..'Z', 'a'..'z', '0'..'9', ':', '.', '%', '-', '_']) then
      Exit(False);
end;

function PortFromText(const S: AnsiString; out Port: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  Port := 0;
  if (S = '') or (Length(S) > 5) then
    Exit;
  for I := 1 to Length(S) do
  begin
    if not (S[I] in ['0'..'9']) then
      Exit;
    Port := Port * 10 + (Ord(S[I]) - Ord('0'));
  end;
  Result := (Port >= 1) and (Port <= 65535);
end;

function HasNul(const S: AnsiString): Boolean;
begin
  Result := Pos(#0, S) > 0;
end;

procedure ClearUrl(out R: TNetUrl; DefaultPort: Integer);
begin
  R.Scheme := '';
  R.User := '';
  R.Password := '';
  R.HasPassword := False;
  R.Host := '';
  R.Port := DefaultPort;
  R.PortGiven := False;
  R.Path := '/';
end;

function SplitUrl(const Url: AnsiString; DefaultPort: Integer; out R: TNetUrl; out Err: AnsiString): Boolean;
var
  P, Q: Integer;
  Rest, Auth, RawPath, Info, HostPort, RawUser, RawPass, PortText: AnsiString;
begin
  Result := False;
  Err := '';
  ClearUrl(R, DefaultPort);

  if HasNul(Url) then
  begin
    Err := 'the address holds a NUL byte';
    Exit;
  end;
  P := Pos('://', Url);
  if (P < 2) or not SchemeIsValid(Copy(Url, 1, P - 1)) then
  begin
    Err := 'the address has no scheme (scheme://host/path)';
    Exit;
  end;
  R.Scheme := AsciiLower(Copy(Url, 1, P - 1));
  Rest := Copy(Url, P + 3, Length(Url));

  { the authority ends at the first "/" }
  P := Pos('/', Rest);
  if P = 0 then
  begin
    Auth := Rest;
    RawPath := '';
  end
  else
  begin
    Auth := Copy(Rest, 1, P - 1);
    RawPath := Copy(Rest, P, Length(Rest));
  end;

  { the user information ends at the last "@" }
  Info := '';
  HostPort := Auth;
  P := 0;
  for Q := Length(Auth) downto 1 do
    if Auth[Q] = '@' then
    begin
      P := Q;
      Break;
    end;
  if P > 0 then
  begin
    Info := Copy(Auth, 1, P - 1);
    HostPort := Copy(Auth, P + 1, Length(Auth));
    Q := Pos(':', Info);
    if Q = 0 then
    begin
      RawUser := Info;
      RawPass := '';
    end
    else
    begin
      RawUser := Copy(Info, 1, Q - 1);
      RawPass := Copy(Info, Q + 1, Length(Info));
      R.HasPassword := True;
    end;
    if not NetPercentDecode(RawUser, R.User) then
    begin
      Err := 'the user name has a wrong %-escape';
      Exit;
    end;
    if not NetPercentDecode(RawPass, R.Password) then
    begin
      Err := 'the password has a wrong %-escape';
      Exit;
    end;
    if HasNul(R.User) or HasNul(R.Password) then
    begin
      Err := 'the address holds a NUL byte';
      Exit;
    end;
  end;

  { the host and the port }
  PortText := '';
  if (HostPort <> '') and (HostPort[1] = '[') then
  begin
    P := Pos(']', HostPort);
    if P = 0 then
    begin
      Err := 'the "[" of the host has no "]"';
      Exit;
    end;
    R.Host := Copy(HostPort, 2, P - 2);
    if not Ip6IsValid(R.Host) then
    begin
      Err := 'the host in brackets is not an IPv6 address';
      Exit;
    end;
    Rest := Copy(HostPort, P + 1, Length(HostPort));
    if Rest <> '' then
    begin
      if Rest[1] <> ':' then
      begin
        Err := 'something other than a port follows the host in brackets';
        Exit;
      end;
      PortText := Copy(Rest, 2, Length(Rest));
    end;
  end
  else
  begin
    P := Pos(':', HostPort);
    if P = 0 then
      R.Host := HostPort
    else
    begin
      R.Host := Copy(HostPort, 1, P - 1);
      PortText := Copy(HostPort, P + 1, Length(HostPort));
      if Pos(':', PortText) > 0 then
      begin
        Err := 'an IPv6 address must be written in brackets';
        Exit;
      end;
    end;
    if not HostIsValid(R.Host) then
    begin
      if R.Host = '' then
        Err := 'the address has no host'
      else
        Err := 'the host name has a character that a host name cannot hold';
      Exit;
    end;
  end;
  R.Host := AsciiLower(R.Host);
  if PortText <> '' then
  begin
    if not PortFromText(PortText, R.Port) then
    begin
      Err := 'the port is not a number from 1 to 65535';
      Exit;
    end;
    R.PortGiven := True;
  end;

  { the path }
  if RawPath <> '' then
  begin
    if not NetPercentDecode(RawPath, R.Path) then
    begin
      Err := 'the path has a wrong %-escape';
      Exit;
    end;
    if HasNul(R.Path) then
    begin
      Err := 'the address holds a NUL byte';
      Exit;
    end;
  end;
  Result := True;
end;

function NetSplitUrl(const Url: AnsiString; DefaultPort: Integer; out R: TNetUrl; out Err: AnsiString): Boolean;
begin
  Result := SplitUrl(Url, DefaultPort, R, Err);
  if not Result then
    ClearUrl(R, DefaultPort);
end;

function NetJoinUrl(const R: TNetUrl; ShowPassword: Boolean): AnsiString;
begin
  Result := R.Scheme + '://';
  if (R.User <> '') or (R.HasPassword and ShowPassword) then
  begin
    Result := Result + NetPercentEncode(R.User, False);
    if R.HasPassword and ShowPassword then
      Result := Result + ':' + NetPercentEncode(R.Password, False);
    Result := Result + '@';
  end;
  if Pos(':', R.Host) > 0 then
    Result := Result + '[' + R.Host + ']'
  else
    Result := Result + R.Host;
  if R.PortGiven then
    Result := Result + ':' + IntToStr(R.Port);
  if R.Path = '' then
    Result := Result + '/'
  else
    Result := Result + NetPercentEncode(R.Path, True);
end;

end.
