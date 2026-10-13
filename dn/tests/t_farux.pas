{ Far UX mode flag: off by default, the accessor follows the setting. }
{$mode delphi}{$H+}
program t_farux;
uses DnIni, farux, Commands;
{$I dntest.inc}

begin
  Check(FarUxMode = False, 'FarUxMode is off by default');
  Check(FarUxEnabled = False, 'the accessor reports off by default');
  FarUxMode := True;
  Check(FarUxEnabled = True, 'the accessor follows the setting');
  FarUxMode := False;
  Check(FarUxEnabled = False, 'the setting can be switched back');
  Check(FarFastFindChar(kbAltA) = #0, 'no fast-find letter while the mode is off');
  FarUxMode := True;
  Check(FarFastFindChar(kbAltA) = 'A', 'Alt+A gives its letter in Far mode');
  Check(FarFastFindChar(kbAltZ) = 'Z', 'Alt+Z gives its letter in Far mode');
  Check(FarFastFindChar(kbAlt1) = '1', 'Alt+1 gives its character in Far mode');
  Check(FarFastFindChar(kbAltF1) = #0, 'Alt+F1 is not a fast-find letter');
  Check(FarFastFindChar(kbAltEnter) = #0, 'Alt+Enter is not a fast-find letter');
  Check(FarFastFindChar(kbAltSpace) = #0, 'Alt+Space is not a fast-find letter');
  Check(FarFastFindChar(kbF3) = #0, 'a plain F-key is not a fast-find letter');
  FarUxMode := False;
  Finish;
end.
