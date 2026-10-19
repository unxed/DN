program t_ftpfs;
{ Tests of src/ftpfs.pas: the listings of FTP servers, on lines made for the test in each form (MLSD of RFC 3659, LIST as "ls -l", DOS/IIS,
  NetWare). }
{$mode objfpc}{$H+}
uses SysUtils, DateUtils, RemoteFS, FtpFS;
{$I dntest.inc}

var
  E: TRemoteEntry;

function At(Y, Mo, D, H, Mi, S: Word): TDateTime;
begin
  Result := EncodeDateTime(Y, Mo, D, H, Mi, S, 0);
end;

procedure CheckMlsx;
begin
  Check(FtpParseMlsx('type=file;size=1234;modify=20200203040506;unix.mode=0640;perm=adfr; plain.txt', E), 'mlsd: a file');
  Check((E.Name = 'plain.txt') and (E.Kind = rkFile) and (E.Size = 1234) and (E.Mode = &640), 'mlsd: its name, kind, size and mode');
  Check(E.MTime = UniversalTimeToLocal(At(2020, 2, 3, 4, 5, 6)), 'mlsd: the time is UTC, given as a time of this machine');
  Check(FtpParseMlsx('type=dir;sizd=4096;modify=20200203040506.123;perm=flcdmpe; sub dir', E), 'mlsd: a directory');
  Check((E.Name = 'sub dir') and (E.Kind = rkDir) and (E.Size = -1) and (E.Mode = -1), 'mlsd: a name with a blank, no size, no mode');
  Check(E.MTime = UniversalTimeToLocal(At(2020, 2, 3, 4, 5, 6)), 'mlsd: a time with a fraction');
  Check(not FtpParseMlsx('type=cdir;modify=20200203040506; /pub', E), 'mlsd: the directory itself is left out');
  Check(not FtpParseMlsx('type=pdir;modify=20200203040506; ..', E), 'mlsd: the parent is left out');
  Check(FtpParseMlsx('Type=File;Size=5;Modify=20200203040506; name;with;semicolons', E), 'mlsd: facts in another case');
  Check((E.Name = 'name;with;semicolons') and (E.Kind = rkFile) and (E.Size = 5), 'mlsd: a name with ";" is whole');
  Check(FtpParseMlsx('type=file;size=1;  two blanks', E) and (E.Name = ' two blanks'), 'mlsd: the name is all after the first blank');
  Check(FtpParseMlsx('type=OS.unix=slink:/target/path;modify=20200203040506; link', E), 'mlsd: a link of a Unix server');
  Check((E.Kind = rkLink) and (E.LinkTarget = '/target/path') and (E.Name = 'link'), 'mlsd: the link and its target');
  Check(FtpParseMlsx('type=OS.unix=symlink; l2', E) and (E.Kind = rkLink) and (E.LinkTarget = ''), 'mlsd: a link without its target');
  Check(FtpParseMlsx('type=OS.unix=blkdev; sda', E) and (E.Kind = rkOther), 'mlsd: another type of the server');
  Check(FtpParseMlsx(' no-facts', E) and (E.Name = 'no-facts') and (E.Kind = rkFile) and (E.Size = -1), 'mlsd: a line without facts');
  Check(FtpParseMlsx('type=file;size=7; crlf' + #13, E) and (E.Name = 'crlf'), 'mlsd: the CR of the line end is not in the name');
  Check(FtpParseMlsx('type=file;size=x;modify=2020;unix.mode=0999; bad', E), 'mlsd: facts that cannot be read');
  Check((E.Size = -1) and (E.MTime = 0) and (E.Mode = -1), 'mlsd: are left unknown');
  Check(FtpParseMlsx('type=file;size=5000000000; big', E) and (E.Size = 5000000000), 'mlsd: a size above 4 GiB');
  Check(not FtpParseMlsx('garbage', E), 'mlsd: a line without a blank');
  Check(not FtpParseMlsx('type=file;size=1; ', E), 'mlsd: a line without a name');
  Check(not FtpParseMlsx('', E), 'mlsd: an empty line');
end;

procedure CheckUnix;
var
  Summer, Winter: TDateTime;
begin
  Summer := At(2020, 6, 1, 12, 0, 0);
  Winter := At(2020, 1, 15, 12, 0, 0);
  Check(FtpParseList('-rw-r-----   1 user  group      1234 Feb  3 04:05 plain.txt', Summer, E), 'ls: a file');
  Check((E.Name = 'plain.txt') and (E.Kind = rkFile) and (E.Size = 1234) and (E.Mode = &640), 'ls: its name, kind, size and mode');
  Check(E.MTime = At(2020, 2, 3, 4, 5, 0), 'ls: a time without a year is of this year');
  Check(FtpParseList('-rw-r-----   1 user  group      1234 Feb  3 04:05 plain.txt', Winter, E) and (E.MTime = At(2019, 2, 3, 4, 5, 0)),
    'ls: and of the year before when it would be after now');
  Check(FtpParseList('-rw-r--r--   1 user  group         1 Jan 16 10:00 tomorrow', Winter, E) and (E.MTime = At(2020, 1, 16, 10, 0, 0)),
    'ls: a day after now is still this year (clocks differ)');
  Check(FtpParseList('-rw-r--r--   1 user  group         1 Feb 29 10:00 leap', At(2021, 6, 1, 0, 0, 0), E) and
    (E.MTime = At(2020, 2, 29, 10, 0, 0)), 'ls: Feb 29 without a year is of the last leap year');
  Check(FtpParseList('drwxr-xr-x   2 user group 4096 Jan  1  2019 sub dir', Summer, E), 'ls: a directory');
  Check((E.Name = 'sub dir') and (E.Kind = rkDir) and (E.Mode = &755) and (E.MTime = At(2019, 1, 1, 0, 0, 0)), 'ls: with a year, a blank in the name');
  Check(FtpParseList('lrwxrwxrwx 1 u g 3 Mar 10 12:00 link -> sub', Summer, E), 'ls: a link');
  Check((E.Kind = rkLink) and (E.Name = 'link') and (E.LinkTarget = 'sub'), 'ls: the link and its target');
  Check(FtpParseList('-rwsr-sr-t 1 u g 0 Mar 10 2018 special', Summer, E) and (E.Mode = &7755), 'ls: s and t');
  Check(FtpParseList('-rwSr-Sr-T 1 u g 0 Mar 10 2018 special', Summer, E) and (E.Mode = &7644), 'ls: S and T');
  Check(FtpParseList('crw-rw-rw- 1 root root 1, 3 Mar 10 2018 null', Summer, E), 'ls: a device');
  Check((E.Kind = rkOther) and (E.Size = -1) and (E.Name = 'null'), 'ls: is of the other kind, without a size');
  Check(FtpParseList('-rw-r--r-- 1 owner 1234 Jan 1 2020 nogroup', Summer, E) and (E.Size = 1234) and (E.Name = 'nogroup'), 'ls: no group');
  Check(FtpParseList('-rw-r--r-- user group 77 Jan 1 2020 nolinks', Summer, E) and (E.Size = 77), 'ls: no count of links');
  Check(FtpParseList('-rw-r--r--+ 1 u g 5 Jan 1 2020 acl', Summer, E) and (E.Mode = &644), 'ls: a mark of an ACL');
  Check(FtpParseList('-rw-r--r-- 1 u g 5 Jan 1 2020  two blanks', Summer, E) and (E.Name = ' two blanks'), 'ls: one blank before the name');
  Check(FtpParseList('-rw-r--r-- 1 user 12 Jan 1 2020 Jan 1 2020', Summer, E) and (E.Name = 'Jan 1 2020') and (E.Size = 12),
    'ls: a name that looks like a date');
  Check(FtpParseList('-rw-r--r-- 1 u g 5000000000 Jan 1 2020 big', Summer, E) and (E.Size = 5000000000), 'ls: a size above 4 GiB');
  Check(FtpParseList('-rw-r--r-- 1 u g 5 jan 1 2020 lower' + #13, Summer, E) and (E.Name = 'lower'), 'ls: a month in small letters, a CR');
  Check(not FtpParseList('total 12', Summer, E), 'ls: the total');
  Check(not FtpParseList('', Summer, E), 'ls: an empty line');
  Check(not FtpParseList('-rw-r--r-- 1 u g 5 Foo 1 2020 name', Summer, E), 'ls: not a month');
  Check(not FtpParseList('-rw-r--r-- 1 u g 5 Jan 1 2020', Summer, E), 'ls: no name');
  Check(not FtpParseList('-rwxr-xr-q 1 u g 5 Jan 1 2020 bad', Summer, E), 'ls: a mode that is not one');
  Check(not FtpParseList('-rw-r--r-- 1 u g 5 Jan 32 2020 bad', Summer, E), 'ls: a day that is not one');
end;

procedure CheckDosNetWare;
var
  Now: TDateTime;
begin
  Now := At(2020, 6, 1, 12, 0, 0);
  Check(FtpParseList('02-03-20  04:05PM       <DIR>          sub dir', Now, E), 'dos: a directory');
  Check((E.Kind = rkDir) and (E.Name = 'sub dir') and (E.Size = -1) and (E.MTime = At(2020, 2, 3, 16, 5, 0)), 'dos: its name and time');
  Check(FtpParseList('02-03-2020  11:15AM              1234 file.txt', Now, E), 'dos: a file with a year of four digits');
  Check((E.Kind = rkFile) and (E.Size = 1234) and (E.Name = 'file.txt') and (E.MTime = At(2020, 2, 3, 11, 15, 0)) and (E.Mode = -1),
    'dos: its size and time');
  Check(FtpParseList('12-31-99  12:00AM 5 old', Now, E) and (E.MTime = At(1999, 12, 31, 0, 0, 0)), 'dos: 99 and midnight');
  Check(FtpParseList('02-03-20  12:30PM 5 noon', Now, E) and (E.MTime = At(2020, 2, 3, 12, 30, 0)), 'dos: noon');
  Check(FtpParseList('02-03-20  17:45 1,234,567 comma', Now, E) and (E.Size = 1234567) and (E.MTime = At(2020, 2, 3, 17, 45, 0)),
    'dos: a time of 24 hours and a size with commas');
  Check(not FtpParseList('13-03-20  04:05PM 5 bad', Now, E), 'dos: a month that is not one');
  Check(not FtpParseList('02-03-20  13:05PM 5 bad', Now, E), 'dos: an hour that is not one');

  Check(FtpParseList('d [RWCEAFMS] admin                512 Feb 03 04:05 SYSTEM', Now, E), 'netware: a directory');
  Check((E.Kind = rkDir) and (E.Name = 'SYSTEM') and (E.MTime = At(2020, 2, 3, 4, 5, 0)), 'netware: its name and time');
  Check(FtpParseList('- [R----F--] admin              1234 Jan 01  2019 file name.txt', Now, E), 'netware: a file');
  Check((E.Kind = rkFile) and (E.Size = 1234) and (E.Name = 'file name.txt') and (E.MTime = At(2019, 1, 1, 0, 0, 0)), 'netware: its size and name');
  Check((E.Mode = -1) and (E.LinkTarget = ''), 'netware: no mode, nothing from the forms tried before');
end;

begin
  CheckMlsx;
  CheckUnix;
  CheckDosNetWare;
  Finish;
end.
