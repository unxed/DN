{ FtpFS: the file system of a remote host over FTP (docs/NETWORK.md, unxed/dn#90 step 11). This part reads the listings that an FTP server sends:

  - the lines of MLSD and MLST (RFC 3659): facts "name=value;" and the name after one blank. The facts are told in any case; type, size, modify
    (UTC), unix.mode and the link type of Unix servers (OS.unix=slink:<target>, OS.unix=symlink) are taken, the others are left;
  - the lines of LIST, which has no standard form: the one of "ls -l" (most servers), the one of DOS and IIS ("02-03-20  04:05PM  <DIR>  name")
    and the one of NetWare ("d [RWCEAFMS] owner 512 Feb 03 04:05 name"). The times of LIST are in the zone of the server, which is not told:
    they are taken as times of this machine. A date of "ls -l" with a time and no year is of the last months: the year is the one that does not
    put it more than a day after Now.

  The connection (the control channel, PASV/EPSV, RETR, STOR and the changes of the tree) follows in the next parts of the step.

  The unit is empty in the DOS build and in DN_MINI (as NetProc is).

  MIT, see LICENSE. }
unit FtpFS;

{$mode objfpc}
{$H+}

interface

{$IF NOT (DEFINED(DOS) OR DEFINED(DN_MINI))}
uses
  SysUtils, RemoteFS;

{ One line of an answer to MLSD, or the line of an answer to MLST without its leading blank. False for a line that is not one, and for the entries of
  the directory itself and of its parent (type cdir and pdir). }
function FtpParseMlsx(const Line: AnsiString; out E: TRemoteEntry): Boolean;
{ One line of an answer to LIST, in one of the forms of the head of the unit. Now is the time of this machine (for the year of a date without one).
  False for a line that is none of them ("total 12", an empty line). }
function FtpParseList(const Line: AnsiString; Now: TDateTime; out E: TRemoteEntry): Boolean;
{$ENDIF}

implementation

{$IF NOT (DEFINED(DOS) OR DEFINED(DN_MINI))}

uses
  DateUtils;

const
  MonthNames: array[1..12] of AnsiString = ('jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec');

type
  { The words of a line apart by blanks, with the place where each one starts and the place after its end. }
  TWords = record
    Text: array of AnsiString;
    First, After: array of Integer;
    Count: Integer;
  end;

procedure SplitWords(const S: AnsiString; out W: TWords);
var
  P, Q: Integer;
begin
  W.Count := 0;
  SetLength(W.Text, 0);
  SetLength(W.First, 0);
  SetLength(W.After, 0);
  P := 1;
  while True do
  begin
    while (P <= Length(S)) and (S[P] in [' ', #9]) do
      Inc(P);
    if P > Length(S) then
      Break;
    Q := P;
    while (Q <= Length(S)) and (not (S[Q] in [' ', #9])) do
      Inc(Q);
    if W.Count >= Length(W.Text) then
    begin
      SetLength(W.Text, W.Count + 16);
      SetLength(W.First, W.Count + 16);
      SetLength(W.After, W.Count + 16);
    end;
    W.Text[W.Count] := Copy(S, P, Q - P);
    W.First[W.Count] := P;
    W.After[W.Count] := Q;
    Inc(W.Count);
    P := Q;
  end;
end;

procedure ClearEntry(out E: TRemoteEntry);
begin
  E.Name := '';
  E.Kind := rkOther;
  E.Size := -1;
  E.MTime := 0;
  E.Mode := -1;
  E.LinkTarget := '';
end;

function AllDigits(const S: AnsiString): Boolean;
var
  I: Integer;
begin
  Result := S <> '';
  for I := 1 to Length(S) do
    if not (S[I] in ['0'..'9']) then
      Exit(False);
end;

{ A number of digits that fits in Int64; -1 otherwise. }
function DigitsValue(const S: AnsiString): Int64;
begin
  if (not AllDigits(S)) or (Length(S) > 18) then
    Exit(-1);
  Result := StrToInt64(S);
end;

function MonthOf(const S: AnsiString): Integer;
var
  I: Integer;
begin
  for I := 1 to 12 do
    if LowerCase(S) = MonthNames[I] then
      Exit(I);
  Result := 0;
end;

{ "HH:MM" into Hour and Minute. }
function TakeClock(const S: AnsiString; out Hour, Minute: Integer): Boolean;
var
  P: Integer;
begin
  P := Pos(':', S);
  Result := (P >= 2) and (P <= 3) and (Length(S) = P + 2) and AllDigits(Copy(S, 1, P - 1)) and AllDigits(Copy(S, P + 1, 2));
  if not Result then
    Exit;
  Hour := StrToInt(Copy(S, 1, P - 1));
  Minute := StrToInt(Copy(S, P + 1, 2));
  Result := (Hour < 24) and (Minute < 60);
end;

{ The modify fact: YYYYMMDDHHMMSS, perhaps with a fraction of a second; UTC, given as a time of this machine. }
function MlsxTime(const S: AnsiString; out T: TDateTime): Boolean;
var
  Y, Mo, D, H, Mi, Se: Integer;
begin
  Result := False;
  T := 0;
  if (Length(S) < 14) or (not AllDigits(Copy(S, 1, 14))) or ((Length(S) > 14) and (S[15] <> '.')) then
    Exit;
  Y := StrToInt(Copy(S, 1, 4));
  Mo := StrToInt(Copy(S, 5, 2));
  D := StrToInt(Copy(S, 7, 2));
  H := StrToInt(Copy(S, 9, 2));
  Mi := StrToInt(Copy(S, 11, 2));
  Se := StrToInt(Copy(S, 13, 2));
  if Se = 60 then
    Se := 59;
  if not TryEncodeDateTime(Y, Mo, D, H, Mi, Se, 0, T) then
    Exit;
  T := UniversalTimeToLocal(T);
  Result := True;
end;

{ The permission bits written in octal ("0755", "755"); -1 when it is not a number of up to four octal digits after the zeros. }
function OctalValue(const S: AnsiString): LongInt;
var
  I: Integer;
begin
  Result := 0;
  if S = '' then
    Exit(-1);
  for I := 1 to Length(S) do
  begin
    if not (S[I] in ['0'..'7']) then
      Exit(-1);
    Result := Result * 8 + (Ord(S[I]) - Ord('0'));
    if Result > &7777 then
      Exit(-1);
  end;
end;

function FtpParseMlsx(const Line: AnsiString; out E: TRemoteEntry): Boolean;
var
  Sp, P, Q, Eq: Integer;
  Facts, Fact, Name, Value: AnsiString;
  T: TDateTime;
  Size: Int64;
begin
  Result := False;
  ClearEntry(E);
  E.Kind := rkFile;
  { the facts end at the first blank; the name, which may hold blanks and ";", is all that follows it }
  Sp := Pos(' ', Line);
  if Sp = 0 then
    Exit;
  Facts := Copy(Line, 1, Sp - 1);
  E.Name := Copy(Line, Sp + 1, Length(Line));
  if (E.Name <> '') and (E.Name[Length(E.Name)] = #13) then
    SetLength(E.Name, Length(E.Name) - 1);
  if E.Name = '' then
    Exit;
  P := 1;
  while P <= Length(Facts) do
  begin
    Q := P;
    while (Q <= Length(Facts)) and (Facts[Q] <> ';') do
      Inc(Q);
    Fact := Copy(Facts, P, Q - P);
    P := Q + 1;
    Eq := Pos('=', Fact);
    if Eq < 2 then
      Continue;
    Name := LowerCase(Copy(Fact, 1, Eq - 1));
    Value := Copy(Fact, Eq + 1, Length(Fact));
    if Name = 'type' then
    begin
      if SameText(Value, 'file') then
        E.Kind := rkFile
      else if SameText(Value, 'dir') then
        E.Kind := rkDir
      else if SameText(Value, 'cdir') or SameText(Value, 'pdir') then
        Exit
      else if SameText(Copy(Value, 1, 14), 'OS.unix=slink:') then
      begin
        E.Kind := rkLink;
        E.LinkTarget := Copy(Value, 15, Length(Value));
      end
      else if SameText(Value, 'OS.unix=symlink') or SameText(Value, 'OS.unix=slink') then
        E.Kind := rkLink
      else
        E.Kind := rkOther;
    end
    else if Name = 'size' then
    begin
      Size := DigitsValue(Value);
      if Size >= 0 then
        E.Size := Size;
    end
    else if Name = 'modify' then
    begin
      if MlsxTime(Value, T) then
        E.MTime := T;
    end
    else if Name = 'unix.mode' then
      E.Mode := OctalValue(Value);
  end;
  if E.Kind = rkDir then
    E.Size := -1;
  Result := True;
end;

{ The kind and the permission bits of the first word of "ls -l" ("drwxr-sr-t", perhaps with "+", "@" or "." after it for an ACL). }
function UnixModeWord(const S: AnsiString; out Kind: TRemoteKind; out Mode: LongInt): Boolean;
const
  Bits: array[0..8] of LongInt = (&400, &200, &100, &40, &20, &10, &4, &2, &1);
var
  I: Integer;
  C: Char;
begin
  Result := False;
  Kind := rkOther;
  Mode := 0;
  if not ((Length(S) = 10) or ((Length(S) = 11) and (S[11] in ['+', '@', '.']))) then
    Exit;
  case S[1] of
    '-': Kind := rkFile;
    'd': Kind := rkDir;
    'l': Kind := rkLink;
    'b', 'c', 'p', 's', 'D': Kind := rkOther;
  else
    Exit;
  end;
  for I := 0 to 8 do
  begin
    C := S[I + 2];
    case I mod 3 of
      0: if C = 'r' then Mode := Mode or Bits[I] else if C <> '-' then Exit;
      1: if C = 'w' then Mode := Mode or Bits[I] else if C <> '-' then Exit;
      2:
        case C of
          'x': Mode := Mode or Bits[I];
          '-': ;
          's', 'S', 't', 'T':
          begin
            { s and t: the bit of execution and the special bit of the triplet; S and T: the special bit alone }
            if (I = 2) and (C in ['s', 'S']) then
              Mode := Mode or &4000
            else if (I = 5) and (C in ['s', 'S']) then
              Mode := Mode or &2000
            else if (I = 8) and (C in ['t', 'T']) then
              Mode := Mode or &1000
            else
              Exit;
            if C in ['s', 't'] then
              Mode := Mode or Bits[I];
          end;
        else
          Exit;
        end;
    end;
  end;
  Result := True;
end;

{ The date of "ls -l" at the word Index of W: a month, a day, then "HH:MM" or a year. }
function LsDateAt(const W: TWords; Index: Integer; Now: TDateTime; out T: TDateTime): Boolean;
var
  Mo, D, Y, H, Mi: Integer;
  NowY, NowM, NowD: Word;
begin
  Result := False;
  T := 0;
  if Index + 2 >= W.Count then
    Exit;
  Mo := MonthOf(W.Text[Index]);
  if (Mo = 0) or (not AllDigits(W.Text[Index + 1])) or (Length(W.Text[Index + 1]) > 2) then
    Exit;
  D := StrToInt(W.Text[Index + 1]);
  if TakeClock(W.Text[Index + 2], H, Mi) then
  begin
    DecodeDate(Now, NowY, NowM, NowD);
    Y := NowY;
    if (not TryEncodeDateTime(Y, Mo, D, H, Mi, 0, 0, T)) or (T > Now + 1) then
    begin
      Y := NowY - 1;
      if not TryEncodeDateTime(Y, Mo, D, H, Mi, 0, 0, T) then
        Exit;
    end;
  end
  else if (Length(W.Text[Index + 2]) = 4) and AllDigits(W.Text[Index + 2]) then
  begin
    Y := StrToInt(W.Text[Index + 2]);
    if not TryEncodeDate(Y, Mo, D, T) then
      Exit;
  end
  else
    Exit;
  Result := True;
end;

{ The name after the word Index: one blank after it (ls puts one), all the rest of the line. }
function NameAfter(const Line: AnsiString; const W: TWords; Index: Integer): AnsiString;
begin
  Result := Copy(Line, W.After[Index] + 1, Length(Line));
end;

{ "ls -l": the mode, then the words up to the date (links, owner, group, perhaps none of the two last); the size is the word before the date. }
function ParseUnix(const Line: AnsiString; const W: TWords; Now: TDateTime; var E: TRemoteEntry): Boolean;
var
  I, P: Integer;
  T: TDateTime;
begin
  Result := False;
  if not UnixModeWord(W.Text[0], E.Kind, E.Mode) then
    Exit;
  for I := 3 to W.Count - 3 do
    if LsDateAt(W, I, Now, T) then
    begin
      E.MTime := T;
      if E.Kind <> rkOther then
        E.Size := DigitsValue(W.Text[I - 1]);
      E.Name := NameAfter(Line, W, I + 2);
      if E.Kind = rkLink then
      begin
        P := Pos(' -> ', E.Name);
        if P > 0 then
        begin
          E.LinkTarget := Copy(E.Name, P + 4, Length(E.Name));
          SetLength(E.Name, P - 1);
        end;
      end;
      Exit(E.Name <> '');
    end;
end;

{ NetWare: "d" or "-", the rights in brackets, the owner, the size, the date as in "ls -l". }
function ParseNetWare(const Line: AnsiString; const W: TWords; Now: TDateTime; var E: TRemoteEntry): Boolean;
var
  T: TDateTime;
begin
  Result := False;
  if (W.Count < 7) or (Length(W.Text[0]) <> 1) or (not (W.Text[0][1] in ['d', '-'])) or (Length(W.Text[1]) < 2) or (W.Text[1][1] <> '[') or
    (W.Text[1][Length(W.Text[1])] <> ']') then
    Exit;
  if not LsDateAt(W, 4, Now, T) then
    Exit;
  if W.Text[0] = 'd' then
    E.Kind := rkDir
  else
  begin
    E.Kind := rkFile;
    E.Size := DigitsValue(W.Text[3]);
  end;
  E.MTime := T;
  E.Name := NameAfter(Line, W, 6);
  Result := E.Name <> '';
end;

{ DOS and IIS: "MM-DD-YY" (or YYYY), "HH:MMAM" (or PM, or a time of 24 hours), "<DIR>" or the size, the name after the blanks. }
function ParseDos(const Line: AnsiString; const W: TWords; var E: TRemoteEntry): Boolean;
var
  S, Clock: AnsiString;
  Mo, D, Y, H, Mi, P: Integer;
  T: TDateTime;
begin
  Result := False;
  if W.Count < 4 then
    Exit;
  S := W.Text[0];
  if not (((Length(S) = 8) or (Length(S) = 10)) and (S[3] = '-') and (S[6] = '-') and AllDigits(Copy(S, 1, 2)) and AllDigits(Copy(S, 4, 2)) and
    AllDigits(Copy(S, 7, Length(S) - 6))) then
    Exit;
  Mo := StrToInt(Copy(S, 1, 2));
  D := StrToInt(Copy(S, 4, 2));
  Y := StrToInt(Copy(S, 7, Length(S) - 6));
  if Length(S) = 8 then
    if Y < 70 then
      Inc(Y, 2000)
    else
      Inc(Y, 1900);
  Clock := UpperCase(W.Text[1]);
  P := Length(Clock);
  if (P > 2) and ((Copy(Clock, P - 1, 2) = 'AM') or (Copy(Clock, P - 1, 2) = 'PM')) then
  begin
    if (not TakeClock(Copy(Clock, 1, P - 2), H, Mi)) or (H < 1) or (H > 12) then
      Exit;
    if H = 12 then
      H := 0;
    if Clock[P - 1] = 'P' then
      Inc(H, 12);
  end
  else if not TakeClock(Clock, H, Mi) then
    Exit;
  if not TryEncodeDateTime(Y, Mo, D, H, Mi, 0, 0, T) then
    Exit;
  if UpperCase(W.Text[2]) = '<DIR>' then
    E.Kind := rkDir
  else
  begin
    E.Size := DigitsValue(StringReplace(W.Text[2], ',', '', [rfReplaceAll]));
    if E.Size < 0 then
      Exit;
    E.Kind := rkFile;
  end;
  E.MTime := T;
  E.Name := Copy(Line, W.First[3], Length(Line));
  Result := True;
end;

function FtpParseList(const Line: AnsiString; Now: TDateTime; out E: TRemoteEntry): Boolean;
var
  S: AnsiString;
  W: TWords;
begin
  ClearEntry(E);
  S := Line;
  if (S <> '') and (S[Length(S)] = #13) then
    SetLength(S, Length(S) - 1);
  SplitWords(S, W);
  if W.Count < 4 then
    Exit(False);
  { each form starts from a clear entry: one that does not fit may have filled some fields }
  Result := ParseUnix(S, W, Now, E);
  if not Result then
  begin
    ClearEntry(E);
    Result := ParseNetWare(S, W, Now, E);
  end;
  if not Result then
  begin
    ClearEntry(E);
    Result := ParseDos(S, W, E);
  end;
  if not Result then
    ClearEntry(E);
end;

{$ENDIF}

end.
