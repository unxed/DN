{ The mask of a group rename (renmask, dn#40 part 3): the fields [N], [E], [C], [Cn] and [[. }
{$mode objfpc}{$H-}
program t_renmask;
uses RenMask;
{$I dntest.inc}

procedure Expect(const Name, Mask: String; Counter: LongInt; const Want: String);
var
  Got, N: String;
begin
  Got := ExpandRenameMask(Name, Mask, Counter);
  Str(Counter, N);
  Check(Got = Want, Name + ' by ' + Mask + ' (' + N + '): [' + Got + '], want [' + Want + ']');
end;

begin
  Expect('photo.jpg', '[N].[E]', 1, 'photo.jpg');
  Expect('photo.jpg', 'img_[C3].[E]', 7, 'img_007.jpg');
  Expect('photo.jpg', 'img_[C].[E]', 12, 'img_12.jpg');
  Expect('photo.jpg', 'img_[C2].[E]', 123, 'img_123.jpg');
  Expect('photo.jpg', '[N]_copy.[E]', 1, 'photo_copy.jpg');
  Expect('archive.tar.gz', '[N]-old.[E]', 1, 'archive.tar-old.gz');
  Expect('README', '[N].txt', 1, 'README.txt');
  Expect('README', '[N].[E]', 1, 'README.');
  Expect('.bashrc', '[N].bak', 1, '.bashrc.bak');
  Expect('a.txt', '[[[N]]].[e]', 1, '[a]].txt');
  Expect('a.txt', '[X][N]', 1, '[X]a');
  Expect('a.txt', 'end[', 1, 'end[');
  Expect('a.txt', '[c9]', 5, '000000005');
  Expect('a.txt', '', 1, '');
  Finish;
end.
