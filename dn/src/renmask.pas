{ RenMask: the mask of a group rename (dn#40, part 3). A mask is the new name written with fields in brackets:
    [N]    the name without the extension
    [E]    the extension without its dot
    [C]    the counter, [C3] the counter with at least three digits (zeros in front; 1..9 digits)
    [[     a bracket
  everything else is copied as it is, and so is a bracket that opens no known field. The extension is found as in the
  panels (PosLastDot): a name that starts with a dot and has no other one (.bashrc) has no extension.
  MIT, see LICENSE. }
unit RenMask;
{$mode objfpc}{$H-}

interface

{ The new name of the file Name (a name without a directory) by the mask Mask; Counter is the number of the file in the group. }
function ExpandRenameMask(const Name, Mask: String; Counter: LongInt): String;

implementation

uses
  strutil;

function Padded(N: LongInt; Width: Integer): String;
begin
  Str(N, Result);
  while Length(Result) < Width do
    Result := '0' + Result;
end;

function ExpandRenameMask(const Name, Mask: String; Counter: LongInt): String;
var
  Dot, I: Integer;
  Base, Ext: String;
begin
  Dot := PosLastDot(Name);
  Base := Copy(Name, 1, Dot - 1);
  Ext := Copy(Name, Dot + 1, MaxInt);
  Result := '';
  I := 1;
  while I <= Length(Mask) do
  begin
    if Mask[I] <> '[' then
    begin
      Result := Result + Mask[I];
      Inc(I);
      Continue;
    end;
    if Copy(Mask, I, 2) = '[[' then
    begin
      Result := Result + '[';
      Inc(I, 2);
    end
    else if (Copy(Mask, I, 3) = '[N]') or (Copy(Mask, I, 3) = '[n]') then
    begin
      Result := Result + Base;
      Inc(I, 3);
    end
    else if (Copy(Mask, I, 3) = '[E]') or (Copy(Mask, I, 3) = '[e]') then
    begin
      Result := Result + Ext;
      Inc(I, 3);
    end
    else if (Copy(Mask, I, 3) = '[C]') or (Copy(Mask, I, 3) = '[c]') then
    begin
      Result := Result + Padded(Counter, 0);
      Inc(I, 3);
    end
    else if (I + 3 <= Length(Mask)) and (UpCase(Mask[I + 1]) = 'C') and (Mask[I + 2] in ['1'..'9'])
      and (Mask[I + 3] = ']') then
    begin
      Result := Result + Padded(Counter, Ord(Mask[I + 2]) - Ord('0'));
      Inc(I, 4);
    end
    else
    begin
      Result := Result + '[';                   { not a field: the bracket stays }
      Inc(I);
    end;
  end;
end;

end.
